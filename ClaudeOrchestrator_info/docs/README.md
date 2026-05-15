# ClaudeOrchestrator

Mathematica / Wolfram Language 向けマルチエージェント・オーケストレーション層パッケージ

## 設計思想と実装の概要

ClaudeOrchestrator は、[ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) を「単一エージェント実行核」として保持したまま、その上位レイヤーとして動作するマルチエージェント分解・並列ワーカー配車・アーティファクト収集・統合・コミット機構です。Phase 36 以降は、タスク分解の結果を **ペトリネット (Workflow Net)** として表現・実行する真の multi-token workflow エンジンが統合され、自然文プロンプトから直接ペトリネットを構築して可視化・追跡できる拡張も同梱されています。

### なぜこの設計が必要か

以前の設計では、サブターンを独立した CLI プロセスとして起動し、それぞれに Mathematica ノートブックへの直接書き込みを期待していました。しかし、この方式では次のような根本的な問題が生じることが分かりました。

- サブターン間で Mathematica 変数が共有されない
- `EvaluationNotebook[]` が現在のノートブックを安定に指さない
- `CreateNotebook[...]` による意図しない新規ノートブック作成が発生する
- ツール呼び出しタグと Mathematica プロポーザルが混線する
- 先行サブターンの結果が空または `Null` となり、依存解決に失敗する

これらの教訓から、**並列ワーカーに live ノートブックへの直接副作用を持たせる設計は採用しない**という原則が確立されました。

### 設計上の不変条件

1. **ClaudeRuntime は単一エージェントカーネルのまま維持する** — オーケストレーション層は ClaudeRuntime の外側に置く
2. **並列ワーカーはアーティファクト生成のみ** — `NotebookWrite` の直接呼び出しは禁止
3. **実ノートブックへの書き込みは single committer のみ** — 書き込み競合を根本から排除する
4. **ワーカー間共有状態は明示的な Association / JSON / アーティファクトのみ** — 暗黙的な変数共有を行わない
5. **`EvaluationNotebook[]` / `CreateNotebook[...]` は worker 内で deny** — committer だけが制御された方法でノートブックを操作する

### アーキテクチャの全体像

```
NBAccess
  ↑
claudecode_base
  ↑
ClaudeRuntime              ← 単一エージェント実行核
  ↑
ClaudeOrchestrator         ← 本パッケージ (Phase 36 でペトリネット拡張を統合)
  ├─ Workflow サブモジュール       (真の multi-token Petri net エンジン)
  ├─ Observability サブモジュール  (LLM 呼び出し / Handler 観測 / Tooltip 可視化)
  └─ docs/examples/petri_from_prompt.wl  (自然文 → ペトリネット → 実行のサンプル)
  ↑
claudecode
```

### フェーズ構成

パイプラインは次の 4 フェーズで構成されます。

**Planning フェーズ** では、`ClaudePlanTasks` が親タスクを TaskSpec の DAG（有向非巡回グラフ）に分解します。各 TaskSpec は `TaskId`・`Role`・`Goal`・`Inputs`・`Outputs`・`Capabilities`・`DependsOn`・`ExpectedArtifactType`・`OutputSchema` を持ちます。デフォルトではモックプランナーを使用しますが、実 LLM を呼ぶカスタム関数も渡せます。また `"Planner" -> "LLM"` を指定することで、`$ClaudeOrchestratorRealLLMEndpoint` に設定したエンドポイント経由で実際の LLM にタスク分解を依頼できます。

**Spawn フェーズ** では、`ClaudeSpawnWorkers` がトポロジカルソートした依存順に worker runtime を順次起動し、各タスクのアーティファクトを収集します。worker は `Explore`・`Plan`・`Draft`・`Verify`・`Reduce` のいずれかの Role で動作し、`$ClaudeOrchestratorDenyHeads` に列挙された危険な操作（`NotebookWrite`・`RunProcess`・`SystemCredential` など）を提案することを禁止されています。

**Reduce フェーズ** では、`ClaudeReduceArtifacts` が複数のアーティファクトを統合し、整合した `ReducedArtifact` を生成します。

**Commit フェーズ** では、`ClaudeCommitArtifacts` が single committer runtime を起動し、`ReducedArtifact` をターゲットノートブックに反映します。スライド生成が検出された場合、ユーザーの作業ノートブックを保護するために `CreateDocument` で新規ノートブックを自動生成してコミット先とします。

### ペトリネット拡張（Phase 36 以降）

Phase 36 で **真の multi-token Petri net (MTP) workflow engine** が `ClaudeOrchestrator\`Workflow\`` 名前空間として統合されました。これにより、DAG に閉じない並行・同期・選択を含むワークフローを **place / transition / arc / token / marking** の Petri net 用語のまま記述・実行できます。

`ClaudeOrchestrator.wl` をロードすると、**Workflow エンジン (`ClaudeOrchestrator_workflow.wl`) と Observability サブモジュール (`ClaudeOrchestrator_observability.wl`) は自動的に取り込まれます**(2026-05-15 以降)。さらに参考実装として `docs/examples/petri_from_prompt.wl` が付属しており、自然言語の目標から LLM にネット仕様を生成させることができます。こちらは example 段階のサンプル兼ライブラリなので、本体には統合されておらず別途 `Get` する必要があります。

中核となる「自然言語で書いた目標 → LLM がペトリネット仕様を生成 → 実行 → 観測 → トレース」という一連の流れで、3 つのモジュールがどう役割分担するかを表すと:

```
自然文 goal
   ↓ proposePetriNet         (petri_from_prompt.wl: LLM にコード生成させる)
proposal["Code"]              (Wolfram コード文字列)
   ↓ parsePetriCode           (ToExpression して net Association を取り出す)
net                           (Places / Transitions / InitialMarking を持つ Association)
   ↓ instrumentNetForObservation   (observability: handler を観測ラッパで包む)
observedNet
   ↓ ClaudeCreateWorkflowNet  (Workflow: WorkflowId を発行・登録)
wid                           (文字列。以降の API はすべて wid に対して呼ぶ)
   ↓ ClaudeSubmitToken        (SourcePlace に初期 token を投入)
   ↓ ClaudeRunWorkflow        (sink 到達 / MaxSteps まで実行。Async 切替可)
   ↓ traceTransitions / showLLMCallLog / plotPetriNetDetail
                              (observability: 結果と挙動を確認)
```

主要な API は以下のとおりです。

- **WorkflowNet 構築** — `WorkflowToken`・`WorkflowPlace`・`WorkflowTransition`・`WorkflowNet` で immutable な net 仕様を組み立て、`ClaudeCreateWorkflowNet` で WorkflowId を発行・登録します。
- **トークン投入と Fire 制御** — `ClaudeSubmitToken` で SourcePlace あるいは任意の place にトークンを投入し、`ClaudeEnabledTransitions` で fire 可能な (transition, binding) を確認、`ClaudeFireTransition` / `ClaudeStepWorkflow` で一歩ずつ進行できます。
- **同期 / 非同期実行** — `ClaudeRunWorkflow` は sink 到達 / enabled 空 / MaxSteps 到達まで反復実行し、`"Async" -> True` で `ClaudeCode` の polling task に寄生して非同期実行も可能です。`ClaudeWaitWorkflow` / `ClaudeAsyncJobInfo` / `ClaudeCleanupAsyncJob` で async ジョブを管理できます。
- **状態参照とトレース** — `ClaudeWorkflowStatus`・`ClaudeWorkflowList`・`ClaudeWorkflowState`・`ClaudeWorkflowTrace` で marking・トークン payload・event 履歴を任意の時点で取得できます。
- **ライフサイクル制御** — `ClaudePauseWorkflow` / `ClaudeResumeWorkflow` / `ClaudeCancelWorkflow` で一時停止・再開・中止を制御できます。
- **Completion Hook** — `ClaudeRegisterCompletionHook` / `ClaudeUnregisterCompletionHooks` で workflow 完了時のコールバックを登録できます。同一 wid に複数登録可、登録順に一回限り発火します。
- **Snapshot / Restore** — `ClaudeSnapshotWorkflow` で WorkflowNet を FormatVersion 2 のディレクトリ（meta / workflow / llmgraph / aux）として保存し、`ClaudeRestoreWorkflow` で再構築できます。

#### ペトリネット拡張の最小コード例

```wolfram
(* ロード: ClaudeOrchestrator.wl 本体 + サンプル petri_from_prompt.wl *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator.wl"}]]];
Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator_info",
  "docs", "examples", "petri_from_prompt.wl"}]];

goal = "3 方式 (Monte Carlo / Leibniz / Wallis) で π を計算して比較する";
proposal = proposePetriNet[goal];          (* LLM が WorkflowNet コードを生成 *)
net      = parsePetriCode[proposal["Code"]]; (* Wolfram コードを評価 *)

observedNet = instrumentNetForObservation[net];  (* 観測ラッパを装着 *)
wid         = ClaudeCreateWorkflowNet[observedNet];

ClaudeSubmitToken[wid,
  WorkflowToken["Payload" -> <|"NumSamples" -> 100000|>]];

ClaudeRunWorkflow[wid, "Async" -> False, "MaxSteps" -> 50];
ClaudeWorkflowState[wid]["Marking"]   (* <|"Done" -> {tid}, ...|> *)
```

詳しい一連の流れ(提案 → レビュー → パース → 可視化 → 観測装着 → 実行 → トレース → snapshot) は `example.md` の **Part A** を参照してください。

### 観測 (Observability) サブモジュール

`petri_from_prompt.wl` 用に **LLM 呼び出しログ・Handler 観測・Tooltip 付き可視化・transition 追跡 Dataset** を提供する観測層が別関数として共存します(本体 `ClaudeQueryBg` / `parsePetriCode` / `plotPetriNet` は上書きしません)。

- **LLM ログ** — `ClaudeQueryBgLogged` は `ClaudeQueryBg` を呼び出しつつ Prompt / Response / Model / Duration を `$LLMCallLog` に記録します。`showLLMCallLog[]` で Dataset 一覧、`showLLMCallLog[idx]` で 1 件の Prompt / Response 全文表示、`clearLLMCallLog[]` でリセットできます。
- **Handler 観測** — `instrumentNetForObservation` は net の全 transition の Handler を観測ラッパで包み、binding・OutputPayload・`$MessageList` を `$ObservedHandlerLog` に追記します。`clearObservedHandlerLog[]` でリセット。
- **Logger 注入** — `withLLMLogging[code_String]` は生成コード文字列中の `ClaudeQueryBg` 呼び出しを `Global\`ClaudeQueryBgLogged` に置換します。関数名のみの置換なので Function スコープ・局所変数・HoldAll は壊しません。
- **拡張描画** — `plotPetriNetDetail[wid_or_net, opts]` は place / transition / edge にトークン内容・handler binding・LLM Prompt / Response の Tooltip を表示する Graph を返します。`wid` 文字列を直接渡すと自動的に `"TraceWid" -> wid` モードになります。本体 `plotPetriNet`(Tooltip なし基本表示)とは共存します。
- **構造診断** — `checkPetriNetVertices[net]` は宣言頂点と辺集合の整合性を検査し、`IsolatedDeclaredVertices`(宣言だけで辺なし)と `UnknownVerticesInEdges`(辺だけで宣言なし)を返します。
- **Transition 追跡** — `traceTransitions[wid]` は `ClaudeWorkflowTrace` の firing event と `$ObservedHandlerLog` / `$LLMCallLog` を結合した Dataset を返し、`"Detail" -> True` で Prompt / Response 抜粋付きにも切り替えられます。

#### 観測モジュールの最小コード例

```wolfram
clearLLMCallLog[];
clearObservedHandlerLog[];

observedNet = instrumentNetForObservation[net];
wid = ClaudeCreateWorkflowNet[observedNet];
ClaudeSubmitToken[wid, WorkflowToken[]];
ClaudeRunWorkflow[wid];

traceTransitions[wid]                     (* firing 一覧 (Dataset) *)
traceTransitions[wid, "Detail" -> True]   (* + Prompt / Response 抜粋 *)
showLLMCallLog[]                          (* LLM 呼出一覧 *)
showLLMCallLog[1]                         (* 1 件の Prompt / Response 全文 *)
plotPetriNetDetail[wid]                   (* Tooltip 付き Graph *)
```

### docs/examples/petri_from_prompt.wl — 自然文プロンプトからペトリネットへ

`docs/examples/petri_from_prompt.wl` は、**ClaudeOrchestrator パッケージ本体には統合されていない example 段階のサンプル兼ライブラリ**です。上記の Workflow / Observability サブモジュールと連携して、自然文の要求から place / transition / arc を含むペトリネット仕様(Wolfram コード)を LLM に生成させます。利用する場合は `ClaudeOrchestrator.wl` をロードしたあと、別途このファイルを `Get` してください。

主な公開関数:

- **`proposePetriNet[goal, opts]`** — 自然文 goal を CLI 経由で LLM に渡し、`buildXxxNet[] := WorkflowNet[...]` 形式のコード提案を返します(オプション: `"Providers"`・`"InputPayloadKeys"`・`"MaxRetries"`・`"Verbose"`)。戻り値は `"Code"` / `"BuilderName"` / `"Truncated"` / `"ForbiddenFound"` / `"SharedInputPlaces"` / `"DuplicatedTransitions"` / `"Attempts"` 等を含む Association。
- **`reviewPetriProposal[goal]`** — 提案を Frame 付き Column で人間が読める形式で表示します(コード本体・診断指標)。
- **`parsePetriCode[code]`** — 生成コードを評価して `WorkflowNet[...]` Association を取り出します。`builder[]` 不在時には末尾の `WorkflowNet[...]` 式を直接評価する fallback あり。
- **`plotPetriNet[netOrWid]`** — 基本的なペトリネット可視化(Tooltip なし、Observability の `plotPetriNetDetail` とは独立に共存)。

詳細な実行例は `example.md` の Part A を参照してください。

### 非同期実行と状態管理

`ClaudeRunOrchestrationAsync` は Planning → Spawn → Reduce → Commit の全フェーズを DAG コールバックチェーンで非同期実行し、呼び出し元をブロックせずに `orchJobId` を即座に返します。`ClaudeOrchestrationStatus`・`ClaudeOrchestrationResult`・`ClaudeOrchestrationWait`・`ClaudeOrchestrationCancel` でジョブのライフサイクルを制御できます。

### ClaudeEval との統合(非同期化 — v2026-04-20 以降)

**ClaudeOrchestrator をロードすると、`ClaudeEval` の実装が自動的にオーケストレーターベースに切り替わります。** 具体的には、パッケージ読み込み時に `$ClaudeEvalHook` が上書きされ、以後の `ClaudeEval[...]` 呼び出しはすべてオーケストレーターパイプライン経由で実行されます。

`$ClaudeEvalHook` はオーケストレーションを `ClaudeRunOrchestrationAsync` 経由で起動し、フロントエンド(ノートブック UI)をブロックせずに `orchJobId` を即座に返します。完了後の結果は `ClaudeOrchestrationResult` で取得できます。

ClaudeRuntime 単体の動作に戻したい場合は、ClaudeOrchestrator をロードしないか、`$ClaudeEvalHook` を手動でリセットしてください。

### Auto ゲート（Phase 32 Task 3.2 以降）

`$ClaudeEvalAutoSkipKeywords` / `$ClaudeEvalAutoFactualEndings` / `$ClaudeEvalAutoComplexMarkers` の 3 つのリストにより、Auto モードでの分岐をプロジェクトに合わせて調整できます。短い factual query（パッケージ名・関数名・拡張子などのマーカーや「を調べて」「を教えて」「check」などの語尾を含むもの）は Orchestrator を経由せず Single パスに直送し、「スライド」「レポート」「プレゼン」「ペトリネット」など複雑タスク識別マーカーが含まれるプロンプトは短文でも Orchestrator 経路を通します。

### Phase 36 統合

旧来は別ファイルだった以下のサブモジュールが本体の自動ロード対象になっており、`ClaudeOrchestrator.wl` を単独で `Get` するだけで利用できるようになりました。

- `ClaudeOrchestratorDirectives` — ディレクティブ管理
- `ClaudeOrchestratorRouting` — ローカル LLM 名／モデル名のルーティング
- `claudecode_commit_safety` — コミット前後の整合性チェック
- `claudecode_a4_stub` → `ClaudeOrchestratorA4` — A4 フェーズ用フック群
- `ClaudeOrchestrator\`Workflow\`` — 真の multi-token Petri net engine (`ClaudeOrchestrator_workflow.wl`)
- 観測サブモジュール — `ClaudeQueryBgLogged` / `instrumentNetForObservation` / `plotPetriNetDetail` / `checkPetriNetVertices` / `traceTransitions` / `showLLMCallLog` / `withLLMLogging` ほか (`ClaudeOrchestrator_observability.wl`、2026-05-15 から自動ロード)

自動ロードはファイル単位の存在チェック + 重複ロード回避を行うため、`ClaudeOrchestrator.wl` を 2 回 `Get` しても副作用はありません。観測モジュールは `BeginPackage` を持たない読み込み型ファイルなので、`$petriObservabilityVersion` の `ValueQ` で初期化済みかを判定しています。

#### サンプル: `docs/examples/petri_from_prompt.wl`

自然文プロンプトから WorkflowNet を生成するサンプル兼ライブラリ `docs/examples/petri_from_prompt.wl` がリポジトリに同梱されています。**これは example の段階の参考実装で、`ClaudeOrchestrator.wl` 本体には統合されておらず、自動ロードもされません。** Part A のような流れ(自然文 → ネット生成 → 実行 → 観測)を試す場合は、`ClaudeOrchestrator.wl` をロードしたあと別途 `Get` してください。詳細は `example.md` の事前準備を参照。

### Real LLM 統合

`$ClaudeOrchestratorRealLLMEndpoint` を `"ClaudeCode"`（ClaudeCode パッケージ経由）・`"CLI"`（claude CLI を RunProcess で呼ぶ）・カスタム関数のいずれかに設定することで、実際の LLM をプランナーとして利用できます。デフォルト（`None`）はモックのみで動作するため、CI 環境でも安全に使用できます。Windows 環境では `claude.cmd` を自動検出し、UTF-8 の文字化けを防ぐためにファイル経由の stdout 取得方式（`chcp 65001` + リダイレクト）を採用しています。

---

## 詳細説明

### 動作環境

| 項目 | 最低バージョン |
|------|--------------|
| Mathematica / Wolfram Engine | 13.3 以上 |
| Claude CLI (`claude.cmd`) | 最新版（Anthropic 公式） |
| ClaudeRuntime パッケージ | 同梱または別途取得 |
| ClaudeCode パッケージ | 同梱または別途取得 |

> **注意:** 動作検証は Windows 11 上で行っています。macOS・Linux での動作は未検証です（生成 AI の処理で対応可能と想定されます）。

### インストール

#### 1. Claude CLI のインストール

[Anthropic 公式ドキュメント](https://docs.anthropic.com/ja/docs/claude-code/setup) に従い、`claude.cmd` をインストールしてください。インストール後、以下でバージョンを確認します。

```
claude --version
```

PATH が通っている状態（`claude.cmd` がどのディレクトリからも呼べる状態）にしてください。

#### 2. パッケージの取得

```
git clone https://github.com/transreal/ClaudeOrchestrator
```

依存パッケージも同じ `$packageDirectory` に配置します。

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [claudecode](https://github.com/transreal/claudecode)

#### 3. `$Path` の設定

すべての `.wl` ファイルは `$packageDirectory` 直下に置きます。**サブディレクトリを `$Path` に追加しないでください。**

```mathematica
$packageDirectory = "C:\\Users\\YourName\\MyPackages";  (* 実際のパスに変更 *)
If[!MemberQ[$Path, $packageDirectory],
   AppendTo[$Path, $packageDirectory]];
```

`claudecode` パッケージを使用している場合、`$Path` は自動的に設定されます。

#### 4. パッケージの読み込み

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];
```

依存パッケージが自動読み込みされない場合は先に読み込みます。

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeRuntime`",      "ClaudeRuntime.wl"];
  Needs["ClaudeCode`",         "claudecode.wl"];
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];
```

#### 5. API キーの設定

Anthropic API キーは環境変数 `ANTHROPIC_API_KEY` として設定します。

**PowerShell（セッション限定）:**

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

**システム環境変数（恒久設定）:**
「システムの詳細設定」→「環境変数」→「システム環境変数」に `ANTHROPIC_API_KEY` を追加してください。Mathematica を再起動すると反映されます。

---

### クイックスタート

以下のコードで、モックプランナーを使った最小動作を確認できます。

```mathematica
(* 1. パッケージ読み込み *)
$packageDirectory = "C:\\Users\\YourName\\MyPackages";
If[!MemberQ[$Path, $packageDirectory], AppendTo[$Path, $packageDirectory]];

Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeRuntime`",      "ClaudeRuntime.wl"];
  Needs["ClaudeCode`",         "claudecode.wl"];
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];

(* 2. バージョン確認 *)
$ClaudeOrchestratorVersion

(* 3. フルパイプラインの非同期実行(モックプランナー使用)。
   オーケストレーションは非同期実行に統一されている。 *)
jobId = ClaudeRunOrchestrationAsync[
  "Mathematica で素数リストを生成して CSV に保存する",
  TargetNotebook -> InputNotebook[],
  MaxTasks -> 5];
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["Status"]]
(* "Complete" または "Partial" が返れば成功 *)
```

**ペトリネット拡張のクイック試用:**

```mathematica
(* 同梱サンプルをロードして自然文 → ペトリネット → 実行 *)
petriExampleFile = FileNameJoin[{
  Quiet @ Check[NotebookDirectory[], $packageDirectory],
  "ClaudeOrchestrator", "docs", "examples", "petri_from_prompt.wl"
}];
Get[petriExampleFile]
```

**実 LLM を使う場合の追加設定:**

| 変数 | 既定値 | 説明 |
|------|--------|------|
| `$ClaudeOrchestratorRealLLMEndpoint` | `None` | `"ClaudeCode"` / `"CLI"` / カスタム関数 |
| `$ClaudeOrchestratorCLICommand` | `Automatic` | CLI 実行ファイルのパス(Windows では `claude.cmd`) |

環境変数による設定も可能です。

| 環境変数 | 対応する変数 |
|---------|------------|
| `CLAUDE_ORCH_REAL_LLM` | `$ClaudeOrchestratorRealLLMEndpoint` |
| `CLAUDE_ORCH_CLI_PATH` | `$ClaudeOrchestratorCLICommand` |

```mathematica
(* CLI 経由で実 LLM を使う例 *)
$ClaudeOrchestratorRealLLMEndpoint = "CLI";
ClaudeRealLLMAvailable[]  (* True が返れば OK *)

jobId = ClaudeRunOrchestrationAsync[
  "行列の固有値を求めてレポートを生成する",
  Planner -> "LLM",
  MaxTasks -> 4];
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["Status"]]
```

---

### 主な機能

#### タスク計画

- **`ClaudePlanTasks[input, opts]`** — 親タスクを TaskSpec DAG に分解します。`Planner -> Automatic` でモック、`Planner -> "LLM"` で実 LLM を使用します。オプション: `MaxTasks -> 10`。
- **`ClaudeValidateTaskSpec[taskSpec]`** — TaskSpec の妥当性（必須キー・Role の整合性・依存関係）を検証し、`<|"Valid" -> True/False, "Errors" -> {...}|>` を返します。

#### ワーカー実行・アーティファクト収集

- **`ClaudeSpawnWorkers[tasks, opts]`** — 依存順に worker runtime を起動し、各タスクのアーティファクトを収集します。戻り値: `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`。
- **`ClaudeCollectArtifacts[spawnResult]`** — アーティファクト一覧を Dataset として返します。
- **`ClaudeValidateArtifact[artifact, outputSchema]`** — アーティファクトのペイロードが OutputSchema を満たすか検証します。

#### アーティファクト統合・コミット

- **`ClaudeReduceArtifacts[artifacts, opts]`** — 複数アーティファクトを統合し `ReducedArtifact` を返します。`Reducer -> fn` でカスタム統合関数を渡せます。
- **`ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]`** — single committer を起動し、アーティファクトをターゲットノートブックに反映します。`CommitMode -> "Transactional"` でシャドーバッファ経由の安全なコミットが可能です。

#### 非同期実行

- **`ClaudeRunOrchestrationAsync[input, opts]`** — Planning → Spawn → Reduce → Commit の全フェーズを非同期実行し、`orchJobId` を即座に返します。フロントエンドをブロックしません。オーケストレーションはこの非同期実行に統一されています。
- **`ClaudeOrchestrationStatus[orchJobId]`** — ジョブの現在状態を返します(`"Planning"` / `"Spawning"` / `"Reducing"` / `"Committing"` / `"Done"` / `"Failed"`)。
- **`ClaudeOrchestrationResult[orchJobId]`** — 完了済みジョブの最終結果を返します。
- **`ClaudeOrchestrationWait[orchJobId, timeoutSec]`** — ジョブ完了まで待機します(テスト・スクリプト専用)。
- **`ClaudeOrchestrationCancel[orchJobId]`** — 実行中のジョブを中断します。
- **`ClaudeOrchestrationJobs[]`** — 追跡中のジョブ一覧を Dataset で返します。
- **`ClaudeContinueBatch[runtimeId, batchInstructions, opts]`** — 単一 runtime セッションを維持したまま、複数プロンプトを `ClaudeContinueTurn` で順次投入します。ノートブック共有問題を回避する現実解です。

#### ペトリネット (Workflow) 拡張

- **`WorkflowToken` / `WorkflowPlace` / `WorkflowTransition` / `WorkflowNet`** — immutable な net 構成要素のビルダー。`Kind`・`Capacity`・`AcceptedKinds`・`InputArcs` / `OutputArcs`・`Guard`・`Executor`・`RetryPolicy`・`AccessPolicy`・`Timeout`・`Priority` を指定できます。
- **`ClaudeCreateWorkflowNet[spec, opts]`** — WorkflowNet 仕様を検証し WorkflowId を発行・登録します。
- **`ClaudeSubmitToken[wid, token, place]`** — 任意の place（省略時は SourcePlace）にトークンを投入します。
- **`ClaudeEnabledTransitions[wid]`** — 現在 fire 可能な (transition, binding) を Priority 降順で返します。
- **`ClaudeFireTransition[wid, transitionName, binding, opts]`** / **`ClaudeStepWorkflow[wid, opts]`** — 1 transition / 1 step ずつ fire します。NBAccess hard policy → guard → capability の順で検証されます。
- **`ClaudeRunWorkflow[wid, opts]`** — sink 到達 / enabled 空 / `MaxSteps` 到達まで反復実行します。`"Async" -> True` で非同期実行に切り替え、即座に WorkflowId を返します。
- **`ClaudeWaitWorkflow[wid, opts]`** / **`ClaudeAsyncJobInfo[wid]`** / **`ClaudeCleanupAsyncJob[wid]`** — 非同期 workflow の待機・進捗参照・GC を行います。
- **`ClaudePauseWorkflow[wid]`** / **`ClaudeResumeWorkflow[wid]`** / **`ClaudeCancelWorkflow[wid]`** — ライフサイクル制御。
- **`ClaudeWorkflowStatus[wid]`** / **`ClaudeWorkflowList[]`** / **`ClaudeWorkflowState[wid]`** / **`ClaudeWorkflowTrace[wid]`** — marking・トークン payload・event 履歴を参照します。
- **`ClaudeRegisterCompletionHook[wid, fn]`** / **`ClaudeUnregisterCompletionHooks[wid]`** — 完了時コールバックを登録・解除します。
- **`ClaudeSnapshotWorkflow[wid, opts]`** — FormatVersion 2 のディレクトリへ snapshot を保存します。

#### 観測 (Observability) 拡張

- **`ClaudeQueryBgLogged[prompt, opts]`** — `ClaudeQueryBg` を呼びつつ Prompt / Response / Model / Duration を `$LLMCallLog` に記録します。`showLLMCallLog[]` / `clearLLMCallLog[]` で参照・リセット可能。
- **`instrumentNetForObservation[net]`** — WorkflowNet の全 transition Handler を観測ラッパで包み、binding / OutputPayload / $MessageList を `$ObservedHandlerLog` に追記します。
- **`withLLMLogging[code]`** — 文字列コード中の `ClaudeQueryBg` 呼び出しを `ClaudeQueryBgLogged` に書き換える logger 注入ヘルパ。
- **`plotPetriNetDetail[widOrNet, opts]`** — トークン内容・handler binding・LLM Prompt/Response の Tooltip 付きで描画する Graph を返します。
- **`checkPetriNetVertices[netOrWid]`** — 宣言頂点と辺集合の整合性を検査します。
- **`traceTransitions[wid, opts]`** — firing event と handler / LLM ログを結合した Dataset を返します。`"Detail" -> True` で Prompt / Response 抜粋付き拡張モード。

#### docs/examples/petri_from_prompt.wl

- 自然文プロンプト → `proposePetriNet` → place / transition / arc を含む WorkflowNet コード → `parsePetriCode` で Association 化 → `instrumentNetForObservation` で観測ラッパ装着 → `ClaudeCreateWorkflowNet` で wid 発行 → `ClaudeRunWorkflow` で実行 → `plotPetriNetDetail` / `traceTransitions` で観測する **エンドツーエンドサンプル**。詳細は `example.md` の Part A を参照。

#### ClaudeEval との統合(非同期化)

ClaudeOrchestrator をロードすると `$ClaudeEvalHook` が自動的に上書きされ、`ClaudeEval[...]` はオーケストレーターパイプライン経由で実行されます。`ClaudeEval[...]` は `ClaudeRunOrchestrationAsync` を呼び出してノートブック UI をブロックせず `orchJobId` を即座に返し、完了後の結果は `ClaudeOrchestrationResult` で取得できます。

#### Real LLM 統合・診断

- **`ClaudeRealLLMAvailable[]`** — 実 LLM 統合が設定されているか確認します。
- **`ClaudeRealLLMQuery[prompt]`** — 設定済みエンドポイント経由でプロンプトを実行します。
- **`ClaudeRealLLMDiagnose[prompt]`** — エンドポイント・CLI パス・ExitCode・stdout・JSON パース結果などの診断情報を返します。
- **`ClaudeRealLLMDiagnosePlan[input]`** — 実 LLM プランナーパイプラインを走らせ、結果と診断情報を返します。

#### グローバル定数・変数

- **`$ClaudeOrchestratorVersion`** — パッケージバージョン文字列
- **`$ClaudeOrchestratorRoles`** — 許容 Role のリスト: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`
- **`$ClaudeOrchestratorCapabilities`** — Role → Capability リストの Association
- **`$ClaudeOrchestratorDenyHeads`** — worker が提案を禁止されている head のリスト
- **`$ClaudeOrchestratorRealLLMEndpoint`** — 実 LLM 統合モードの制御(既定: `None`)
- **`$ClaudeOrchestratorCLICommand`** — CLI 実行ファイルのパス(既定: `Automatic`)
- **`$ClaudeEvalAutoSkipKeywords` / `$ClaudeEvalAutoFactualEndings` / `$ClaudeEvalAutoComplexMarkers`** — Auto ゲート分岐に使うキーワードリスト群
- **`$WorkflowVersion`** — Workflow サブモジュールのバージョン
- **`$ClaudeWorkflowSnapshotDir`** — `ClaudeSnapshotWorkflow` の既定保存先
- **`$petriObservabilityVersion`** — 観測サブモジュールのバージョン
- **`$LLMCallLog` / `$ObservedHandlerLog` / `$CurrentObservedTransition`** — 観測モジュールが追記するログ群
- **`$ClaudeSlidesTemplatePath`** — スライド生成時の StyleDefinitions テンプレートパス

---

### ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| `api.md` | API リファレンス（全関数・データ型・グローバル変数の仕様） |
| `api_workflow.md` | ペトリネット (Workflow) サブモジュールの API リファレンス |
| `api_observability.md` | 観測 (Observability) サブモジュールの API リファレンス |
| `user_manual.md` | ユーザーマニュアル（各フェーズ・ClaudeEval 非同期化・ペトリネット拡張の詳細な使い方） |
| `setup.md` | インストール手順書（動作要件・環境構築・トラブルシューティング） |
| `example.md` | 使用例集（バージョン確認からペトリネット拡張・バッチ処理まで） |
| `docs/examples/petri_from_prompt.wl` | 自然文 → ペトリネット → 実行のエンドツーエンドサンプル |

---

## 使用例・デモ

### ClaudeEval の非同期化について(v2026-04-20 以降)

**ClaudeOrchestrator をロードすると、`ClaudeEval` の実装が自動的にオーケストレーターベースに切り替わります。** パッケージ読み込み時に内部フック `$ClaudeEvalHook` が上書きされ、以後の `ClaudeEval[...]` 呼び出しはすべてマルチエージェントパイプライン経由で `ClaudeRunOrchestrationAsync` 経由で非同期実行されます(ノートブックをブロックしません)。

ClaudeRuntime 単体の動作に戻したい場合は、ClaudeOrchestrator をロードしないか、`$ClaudeEvalHook` を手動でリセットしてください。

### 例 0: ClaudeEval がオーケストレーターに切り替わることの確認

```mathematica
(* ClaudeOrchestrator ロード前 — ClaudeRuntime ベースの ClaudeEval *)
Needs["ClaudeRuntime`", "ClaudeRuntime.wl"];
$ClaudeEvalHook  (* ClaudeRuntime 既定のフック *)

(* ClaudeOrchestrator をロード *)
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];

(* ロード後 — $ClaudeEvalHook がオーケストレーターに置き換わっていることを確認 *)
$ClaudeEvalHook
(* ClaudeOrchestrator ベースのフック関数が返る *)

(* 以降の ClaudeEval 呼び出しはすべてオーケストレーターパイプラインを通る(非同期) *)
ClaudeEval["フィボナッチ数列の最初の 10 項を求めて表示する"]
(* → ClaudeRunOrchestrationAsync 経由で非同期実行される(orchJobId を即座に返す) *)
```

### 例 1: タスク分解（モックプランナー）

```mathematica
plan = ClaudePlanTasks["Mathematica で素数リストを生成して CSV に保存する"];
plan["Tasks"][[All, {"TaskId", "Role", "Goal"}]]
```

### 例 2: TaskSpec の検証

```mathematica
spec = <|
  "TaskId" -> "t1", "Role" -> "Draft",
  "Goal" -> "素数リストを生成する",
  "Inputs" -> {}, "Outputs" -> {"primes.csv"},
  "Capabilities" -> {"FileWrite"}, "DependsOn" -> {},
  "ExpectedArtifactType" -> "File", "OutputSchema" -> <||>
|>;
ClaudeValidateTaskSpec[spec]
(* <|"Valid" -> True, "Errors" -> {}|> *)
```

### 例 3: 非同期オーケストレーション

```mathematica
(* ジョブを非同期で起動 *)
jobId = ClaudeRunOrchestrationAsync[
  "行列の固有値を求めてレポートを生成する",
  MaxTasks -> 4
];

(* 状態を確認 *)
ClaudeOrchestrationStatus[jobId][["Status"]]
(* "Planning" → ... → "Done" *)

(* 完了を待機してから結果取得 *)
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["SpawnResult", "Status"]]
(* "Complete" *)
```

### 例 4: バッチ処理(単一セッション継続)

```mathematica
runtime = First @ ClaudeSpawnWorkers[tasks]["Artifacts"];
runtimeId = runtime["RuntimeId"];

results = ClaudeContinueBatch[
  runtimeId,
  {"ステップ 1 を実行", "ステップ 2 を実行", "結果を要約"},
  WaitBetween -> Quantity[2, "Seconds"]
];
results[[All, "Index"]]
(* {1, 2, 3} *)
```

### 例 5: ペトリネット拡張 — 自然文プロンプトからペトリネット実行

`docs/examples/petri_from_prompt.wl` を `Get` すると、`proposePetriNet` / `reviewPetriProposal` / `parsePetriCode` / `plotPetriNet` などのサンプル API が定義されます。これらを使うと、自然文の目標から WorkflowNet コードを LLM に生成させ、Workflow + Observability エンジンで実行・観測できます。

```mathematica
(* 同梱サンプルの解決とロード *)
petriExampleFile = FileNameJoin[{
  Quiet @ Check[NotebookDirectory[], $packageDirectory],
  "ClaudeOrchestrator", "docs", "examples", "petri_from_prompt.wl"
}];
Get[petriExampleFile]

(* 自然文 → WorkflowNet コード生成 → 実行 *)
goal = "3 方式 (Monte Carlo / Leibniz / Wallis) で π を計算して比較する";
proposal    = proposePetriNet[goal];
net         = parsePetriCode[proposal["Code"]];
observedNet = instrumentNetForObservation[net];
wid         = ClaudeCreateWorkflowNet[observedNet];
ClaudeSubmitToken[wid,
  WorkflowToken["Payload" -> <|"NumSamples" -> 100000|>]];
ClaudeRunWorkflow[wid];
ClaudeWorkflowState[wid]["Marking"]
```

詳細な解説と各 API の使用例は `example.md` の Part A を参照してください。

### 例 6: ペトリネット拡張 — Workflow API で直接 net を組む

```mathematica
(* Place / Transition / Net を組み立て、WorkflowId を発行 *)
src  = WorkflowPlace["Start"];
mid  = WorkflowPlace["Mid"];
dst  = WorkflowPlace["Done"];
t1   = WorkflowTransition["T1",
  "InputArcs"  -> {<|"Place" -> "Start", "Multiplicity" -> 1|>},
  "OutputArcs" -> {<|"Place" -> "Mid",   "Multiplicity" -> 1|>},
  "Executor"   -> "PureFunction",
  "RuntimeSpec"-> <|"Handler" -> (#&)|>];
t2   = WorkflowTransition["T2",
  "InputArcs"  -> {<|"Place" -> "Mid",   "Multiplicity" -> 1|>},
  "OutputArcs" -> {<|"Place" -> "Done",  "Multiplicity" -> 1|>},
  "Executor"   -> "PureFunction",
  "RuntimeSpec"-> <|"Handler" -> (#&)|>];
net = WorkflowNet[
  "SourcePlace" -> "Start",
  "FinalPlaces" -> {"Done"},
  "Places"      -> <|"Start" -> src, "Mid" -> mid, "Done" -> dst|>,
  "Transitions" -> <|"T1" -> t1, "T2" -> t2|>];
wid = ClaudeCreateWorkflowNet[net];

(* トークン投入と実行 *)
ClaudeSubmitToken[wid, WorkflowToken["Kind" -> "Task", "Payload" -> <|"id" -> 1|>]];
ClaudeRunWorkflow[wid, "MaxSteps" -> 10][["Status"]]
(* "Done" *)
```

### 例 7: ペトリネット拡張 — 観測モジュールでトレースと可視化

```mathematica
(* 観測ラッパで Handler を包む *)
netObs = instrumentNetForObservation[net];
widObs = ClaudeCreateWorkflowNet[netObs];
ClaudeSubmitToken[widObs, WorkflowToken["Kind" -> "Task", "Payload" -> <|"id" -> 1|>]];
ClaudeRunWorkflow[widObs, "MaxSteps" -> 10];

(* transition firing と LLM 呼び出しを結合した Dataset *)
traceTransitions[widObs, "Detail" -> True]

(* Tooltip 付きグラフ *)
plotPetriNetDetail[widObs, VertexLayout -> "LayeredDigraphEmbedding"]

(* LLM 呼び出しログの確認 *)
showLLMCallLog[]
```

### 例 8: Real LLM 統合の診断

```mathematica
$ClaudeOrchestratorRealLLMEndpoint = "CLI";
ClaudeRealLLMAvailable[]
(* True *)

diag = ClaudeRealLLMDiagnose["Hello, world!"];
diag[["ExitCode"]]
(* 0 *)
```

### 例 9: ジョブ一覧と中断

```mathematica
ClaudeOrchestrationJobs[]
(* Dataset[{<|"JobId"->..., "Status"->"Running", ...|>}] *)

ClaudeOrchestrationCancel[jobId]
(* True *)
```

リポジトリ: [https://github.com/transreal/ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator)

関連リポジトリ:

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — 単一エージェント実行核
- [claudecode](https://github.com/transreal/claudecode) — 上位 UI / セッション層
- [ClaudeOrchestrator_workflow](https://github.com/transreal/ClaudeOrchestrator_workflow) — Workflow サブモジュール
- [ClaudeOrchestrator_observability](https://github.com/transreal/ClaudeOrchestrator_observability) — Observability サブモジュール
- [NBAccess](https://github.com/transreal/NBAccess) — ノートブックアクセス基盤

---

## 免責事項

本ソフトウェアは "as is"（現状有姿）で提供されており、明示・黙示を問わずいかなる保証もありません。
本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。
今後の動作保証のための更新が行われるとは限りません。
本ソフトウェアとドキュメントはほぼすべてが生成AIによって生成されたものです。
Windows 11上での実行を想定しており、MacOS, LinuxのMathematicaでの動作検証は一切していません(生成AIの処理で対応可能と想定されます)。

---

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.