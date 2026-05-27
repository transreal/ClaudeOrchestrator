# ClaudeOrchestrator

Mathematica / Wolfram Language 向けマルチエージェント・オーケストレーション層パッケージ

## 設計思想と実装の概要

ClaudeOrchestrator は、[ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) を「単一エージェント実行核」として保持したまま、その上位レイヤーとして動作するマルチエージェント分解・並列ワーカー配車・アーティファクト収集・統合・コミット機構です。タスク分解の結果を **ペトリネット (Workflow Net)** として表現・実行する真の multi-token workflow エンジンと、その実行を観測するモジュール、さらに `ClaudeEval` の複雑なプロンプトを WorkflowNet として再実行する **PromptWorkflow** 拡張を統合しています。

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
ClaudeOrchestrator         ← 本パッケージ (Workflow / Observability / PromptWorkflow を統合)
  ├─ ClaudeOrchestrator_workflow.wl        (真の multi-token Petri net エンジン)
  ├─ ClaudeOrchestrator_observability.wl   (LLM 呼び出し / Handler 観測 / Tooltip 可視化)
  ├─ ClaudeOrchestrator_promptworkflow.wl  (ClaudeEval 複雑プロンプトの WorkflowNet 化)
  └─ docs/examples/petri_from_prompt.wl    (自然文 → ペトリネット → 実行のサンプル)
  ↑
claudecode
```

### フェーズ構成

パイプラインは次の 4 フェーズで構成されます。

**Planning フェーズ** では、`ClaudePlanTasks` が親タスクを TaskSpec の DAG（有向非巡回グラフ）に分解します。各 TaskSpec は `TaskId`・`Role`・`Goal`・`Inputs`・`Outputs`・`Capabilities`・`DependsOn`・`ExpectedArtifactType`・`OutputSchema` を持ちます。デフォルトではモックプランナーを使用しますが、実 LLM を呼ぶカスタム関数も渡せます。また `"Planner" -> "LLM"` を指定することで、`$ClaudeOrchestratorRealLLMEndpoint` に設定したエンドポイント経由で実際の LLM にタスク分解を依頼できます。

**Spawn フェーズ** では、`ClaudeSpawnWorkers` がトポロジカルソートした依存順に worker runtime を順次起動し、各タスクのアーティファクトを収集します。worker は `Explore`・`Plan`・`Draft`・`Verify`・`Reduce` のいずれかの Role で動作し、`$ClaudeOrchestratorDenyHeads` に列挙された危険な操作（`NotebookWrite`・`RunProcess`・`SystemCredential` など）を提案することを禁止されています。

**Reduce フェーズ** では、`ClaudeReduceArtifacts` が複数のアーティファクトを統合し、整合した `ReducedArtifact` を生成します。

**Commit フェーズ** では、`ClaudeCommitArtifacts` が single committer runtime を起動し、`ReducedArtifact` をターゲットノートブックに反映します。スライド生成が検出された場合、ユーザーの作業ノートブックを保護するために `CreateDocument` で新規ノートブックを自動生成してコミット先とします。

### ペトリネット拡張 (Workflow)

**真の multi-token Petri net (MTP) workflow engine** が `ClaudeOrchestrator\`Workflow\`` 名前空間として統合されています。これにより、DAG に閉じない並行・同期・選択を含むワークフローを **place / transition / arc / token / marking** の Petri net 用語のまま記述・実行できます。

`ClaudeOrchestrator.wl` をロードすると、**Workflow エンジン (`ClaudeOrchestrator_workflow.wl`)・Observability (`ClaudeOrchestrator_observability.wl`)・PromptWorkflow (`ClaudeOrchestrator_promptworkflow.wl`) の 3 サブモジュールはすべて自動的に取り込まれます**。中核となる「自然言語で書いた目標 → LLM がペトリネット仕様を生成 → 実行 → 観測 → トレース」という一連の流れは、サンプルライブラリ `docs/examples/petri_from_prompt.wl` を `Get` することで体験できます。

```
自然文 goal
   ↓ proposePetriNet         (petri_from_prompt.wl: LLM にコード生成させる)
proposal["Code"]              (Wolfram コード文字列)
   ↓ ClaudeApplyProposal      (workflow: proposal を評価して builder 関数を定義)
   ↓ または parsePetriCode    (petri_from_prompt.wl: net Association を取り出す)
net                           (Places / Transitions / InitialMarking を持つ Association)
   ↓ instrumentNetForObservation   (observability: handler を観測ラッパで包む)
observedNet
   ↓ ClaudeCreateWorkflowNet  (workflow: WorkflowId を発行・登録)
wid                           (文字列。以降の API はすべて wid に対して呼ぶ)
   ↓ ClaudeSubmitToken / ClaudeBindAndSubmit / ClaudeSubmitInputs
                              (SourcePlace に初期 token を投入)
   ↓ ClaudeRunWorkflow        (sink 到達 / MaxSteps まで実行。Async 切替可)
   ↓ traceTransitions / showLLMCallLog / plotPetriNetDetail
                              (observability: 結果と挙動を確認)
```

主要な API は以下のとおりです。

- **WorkflowNet 構築** — `WorkflowToken`・`WorkflowPlace`・`WorkflowTransition`・`WorkflowNet` で immutable な net 仕様を組み立て、`ClaudeCreateWorkflowNet` で WorkflowId を発行・登録します。
- **トークン投入と Fire 制御** — `ClaudeSubmitToken` で SourcePlace あるいは任意の place にトークンを投入し、糖衣関数 `ClaudeSubmitInputs` / `ClaudeBindAndSubmit` でも Payload Association を簡単に作れます。`ClaudeEnabledTransitions` で fire 可能な (transition, binding) を確認、`ClaudeFireTransition` / `ClaudeStepWorkflow` で一歩ずつ進行できます。
- **Proposal 適用** — `ClaudeApplyProposal` は `proposePetriNet` の戻り値 (proposal) の `"Code"` を評価して `"BuilderName"` の builder 関数を定義します。`builder[]` を呼ぶことで `WorkflowNet[...]` Association が得られます。
- **同期 / 非同期実行** — `ClaudeRunWorkflow` は sink 到達 / enabled 空 / MaxSteps 到達まで反復実行し、`"Async" -> True` で `ClaudeCode` の polling task に寄生して非同期実行も可能です。`ClaudeWaitWorkflow` / `ClaudeAsyncJobInfo` / `ClaudeCleanupAsyncJob` で async ジョブを管理できます。
- **状態参照とトレース** — `ClaudeWorkflowStatus`・`ClaudeWorkflowList`・`ClaudeWorkflowState`・`ClaudeWorkflowTrace` で marking・トークン payload・event 履歴を任意の時点で取得できます。
- **ライフサイクル制御** — `ClaudePauseWorkflow` / `ClaudeResumeWorkflow` / `ClaudeCancelWorkflow` で一時停止・再開・中止を制御できます。
- **Completion Hook** — `ClaudeRegisterCompletionHook` / `ClaudeUnregisterCompletionHooks` で workflow 完了時のコールバックを登録できます。同一 wid に複数登録可、登録順に一回限り発火します。
- **AwaitingLLM コールバック** — `ClaudeCompleteHandlerOutput` で `AwaitingLLM` 状態の transition に非同期 LLM 応答を流し込めます。
- **Snapshot / Restore** — `ClaudeSnapshotWorkflow` で WorkflowNet を FormatVersion 2 のディレクトリ（meta / workflow / llmgraph / aux）として保存し、`ClaudeRestoreWorkflow` で再構築できます。

#### ペトリネット拡張の最小コード例

```wolfram
(* ロード: ClaudeOrchestrator.wl 本体だけで Workflow / Observability /
   PromptWorkflow の 3 サブモジュールがすべて自動ロードされる *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator.wl"}]]];

(* 自然文プロンプトからのサンプル例を試す場合のみ追加で Get する *)
Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator_info",
  "docs", "examples", "petri_from_prompt.wl"}]];

goal     = "3 方式 (Monte Carlo / Leibniz / Wallis) で π を計算して比較する";
proposal = proposePetriNet[goal];          (* LLM が WorkflowNet コードを生成 *)
builder  = ClaudeApplyProposal[proposal];  (* proposal を評価し builder を定義 *)
net      = builder[];                      (* WorkflowNet[...] Association を取得 *)

observedNet = instrumentNetForObservation[net];  (* 観測ラッパを装着 *)
wid         = ClaudeCreateWorkflowNet[observedNet];

ClaudeSubmitInputs[wid, <|"NumSamples" -> 100000|>];

ClaudeRunWorkflow[wid, "Async" -> False, "MaxSteps" -> 50];
ClaudeWorkflowState[wid]["Marking"]   (* <|"Done" -> {tid}, ...|> *)
```

詳しい一連の流れ(提案 → レビュー → パース → 可視化 → 観測装着 → 実行 → トレース → snapshot) は `example.md` の **Part A** を参照してください。

### PromptWorkflow 拡張 — ClaudeEval の複雑プロンプトを workflow に

`ClaudeEval` に与えられるプロンプトのうち、複数のサブタスクや順序制御を含む **複雑なもの**は、単一の関数呼び出しでは表せません。PromptWorkflow 拡張 (`ClaudeOrchestrator_promptworkflow.wl`) は、こうした複雑プロンプトを WorkflowNet (Petri-net workflow) として再実行するための経路を提供します。`ClaudeOrchestrator.wl` のロード時に自動的に読み込まれます。

PromptWorkflow 拡張の中核は、LLM が提案した workflow コードを **安全に扱う**ことです。提案コードはそのまま評価されず、次の流れを経ます。

```
複雑プロンプト
   ↓ ClaudeWorkflowComplexPromptQ   (評価なし・ローカルで複雑さを判定)
WorkflowCandidate と判定されたものだけ次へ
   ↓ ClaudeProposeWorkflowNetFromPrompt   (LLM に WorkflowNet コードを要求)
   ↓ ClaudeWorkflowCheckForbidden   (禁止パターンの静的検査)
   ↓ ClaudeParseWorkflowNetCode   (HoldComplete でくるんだ非評価 parse)
WorkflowNet[spec]   (builder を呼ばずに AST から抽出)
   ↓ ClaudeCreateWorkflowRouteDraft   (PrivateVault にコード artifact を保存)
WorkflowRouteDraft (Status: NeedsApproval)
```

設計上の要点は次のとおりです。

- **複雑さの判定は評価を伴わずローカルで行う** — `ClaudeWorkflowComplexPromptQ` はルーター LLM を呼ぶ前に動作するため、workflow 候補かを試すためだけに秘密のプロンプトが外部送信されることはありません。
- **提案コードは評価しない** — `ClaudeParseWorkflowNetCode` は `HoldComplete` でくるんだ非評価 parse を行い、builder を呼ばずに `WorkflowNet[spec]` を取り出します。評価前に `ClaudeWorkflowCheckForbidden` がファイル / ネットワーク / プロセス / 資格情報 / notebook 変更系の禁止パターンを静的検出します。
- **自動実行・自動登録をしない** — 新規に生成された workflow はつねに `NeedsApproval` で停止します。`ClaudeWorkflowRouteFromPrompt` が `ClaudeEval` 統合フロー全体をオーケストレーションしますが、既存の一意な route がなければ提案と WorkflowRouteDraft 作成までで止まり、ユーザーの承認なしに実行されることはありません。
- **draft は DryRun が既定** — `ClaudeCreateWorkflowRouteDraft` の既定は `DryRun -> True` で、明示的に `"DryRun" -> False` を渡さないかぎり書き込みを行いません。workflow コード本体は SourceVault PrivateVault 配下に private artifact として保存され、draft メタデータは `CodeHash` と `CodeStorage` 参照のみを持ちます。

主要な API は以下のとおりです。

- **複雑プロンプト判定** — `ClaudeWorkflowComplexPromptQ` でプロンプトが workflow 候補かを deterministic に判定します。
- **WorkflowNet 提案** — `ClaudeProposeWorkflowNetFromPrompt` で自然言語のゴールから WorkflowNet コードを提案させ、safe parser に通し、失敗時は静的診断をフィードバックして再試行します。
- **安全な parse** — `ClaudeParseWorkflowNetCode` / `ClaudeWorkflowCheckForbidden` / `ClaudeWorkflowNetWellFormedQ` で、提案コードを評価せずに検査・抽出します。
- **WorkflowRouteDraft 作成** — `ClaudeCreateWorkflowRouteDraft` で提案を承認待ちの draft に変換します。
- **統合フロー** — `ClaudeWorkflowRouteFromPrompt` が `ClaudeEval` の workflow 統合フロー全体をオーケストレーションします。

詳細は `api_promptworkflow.md` を参照してください。

### 観測 (Observability) サブモジュール

WorkflowNet 実行に **LLM 呼び出しログ・Handler 観測・Tooltip 付き可視化・transition 追跡 Dataset** を提供する観測層が `ClaudeOrchestrator_observability.wl` として共存します(本体 `ClaudeQueryBg` / `parsePetriCode` / `plotPetriNet` は上書きしません)。

- **LLM ログ** — `ClaudeQueryBgLogged` は `ClaudeQueryBg` を呼び出しつつ Prompt / Response / Model / Duration を `$LLMCallLog` に記録します。`showLLMCallLog[]` で Dataset 一覧、`showLLMCallLog[idx]` で 1 件の Prompt / Response 全文表示、`clearLLMCallLog[]` でリセットできます。
- **Handler 観測** — `instrumentNetForObservation` は net の全 transition の Handler を観測ラッパで包み、binding・OutputPayload・`$MessageList` を `$ObservedHandlerLog` に追記します。`clearObservedHandlerLog[]` でリセット。
- **Logger 注入** — `withLLMLogging[code_String]` は生成コード文字列中の `ClaudeQueryBg` 呼び出しを `Global\`ClaudeQueryBgLogged` に置換します。関数名のみの置換なので Function スコープ・局所変数・HoldAll は壊しません。
- **拡張描画** — `plotPetriNetDetail[wid_or_net, opts]` は place / transition / edge にトークン内容・handler binding・LLM Prompt / Response の Tooltip を表示する Graph を返します。`wid` 文字列を直接渡すと自動的に `"TraceWid" -> wid` モードになります。サンプル `petri_from_prompt.wl` 側の `plotPetriNet` (Tooltip なし基本表示) とは共存します。
- **構造診断** — `checkPetriNetVertices[net]` は宣言頂点と辺集合の整合性を検査し、`IsolatedDeclaredVertices`(宣言だけで辺なし)と `UnknownVerticesInEdges`(辺だけで宣言なし)を返します。
- **Transition 追跡** — `traceTransitions[wid]` は `ClaudeWorkflowTrace` の firing event と `$ObservedHandlerLog` / `$LLMCallLog` を結合した Dataset を返し、`"Detail" -> True` で Prompt / Response 抜粋付きにも切り替えられます。

#### ChatGPT Codex 対応(2026-05-26 以降)

`ClaudeOrchestrator_observability.wl` は、Claude 以外のプロバイダ呼び出しもログ上で識別できるよう拡張されています。

- **プロバイダ表示名の正規化** — 内部ヘルパ `iProviderDisplayName` が `"chatgptcodex"` / `"ChatGPTCodexCLI"` といった provider id を `"ChatGPT Codex"` に正規化します。`"claude"` / `"openai"` / `"lmstudio"` などの主要プロバイダも統一的に表示名へ変換され、未知 id は素通しされます。
- **provenance キーの自動取り込み** — `ClaudeQueryBgLogged` は応答が `ProviderResultMetadata` を持つ Association の場合、`ProviderKind`・`ProviderDisplayName`・`HarnessBundleId`・`DirectiveSnapshotId`・`RuntimeEnvironmentHash` などを `$LLMCallLog` の各エントリに lift します。これにより Codex 経由の呼び出しと Claude 経由の呼び出しを区別したまま保存できます。
- **ログ表示の更新** — `showLLMCallLog[]` の Dataset には `Provider` カラムが追加され、`showLLMCallLog[idx]` の詳細表示でも `Provider` / `HarnessBundle` / `DirectiveSnapshot` / `RuntimeEnvHash` が Missing 以外のときに表示されます。`traceTransitions` の Detail モードもこの情報を反映します。

これにより、ChatGPT Codex を含む複数プロバイダを混在運用しても、どの transition がどのプロバイダ・どのハーネスバンドルで実行されたかを単一のログから追跡できます。

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
showLLMCallLog[]                          (* LLM 呼出一覧 (Provider カラム付) *)
showLLMCallLog[1]                         (* 1 件の Prompt / Response 全文 *)
plotPetriNetDetail[wid]                   (* Tooltip 付き Graph *)
```

### docs/examples/petri_from_prompt.wl — 自然文プロンプトからペトリネットへ

`docs/examples/petri_from_prompt.wl` は、**ClaudeOrchestrator パッケージ本体には統合されていない example 段階のサンプル兼ライブラリ**です。Workflow / Observability / PromptWorkflow の 3 サブモジュールと連携して、自然文の要求から place / transition / arc を含むペトリネット仕様(Wolfram コード)を LLM に生成させます。

PromptWorkflow 拡張が安全な静的解析と `WorkflowRouteDraft` 作成までを担当し、本サンプルは **LLM に評価可能なコードを生成させて即座に実行する** 軽量経路を提供します。両者は使い分けることを想定しています — 機密プロンプトや承認フローが必要な場合は PromptWorkflow を、自由なペトリネット試作には本サンプルを使ってください。利用する場合は `ClaudeOrchestrator.wl` をロードしたあと、別途このファイルを `Get` してください。

主な公開関数:

- **`proposePetriNet[goal, opts]`** — 自然文 goal を CLI 経由で LLM に渡し、`buildXxxNet[] := WorkflowNet[...]` 形式のコード提案を返します(オプション: `"Providers"`・`"InputPayloadKeys"`・`"MaxRetries"`・`"Verbose"`)。戻り値は `"Code"` / `"BuilderName"` / `"Truncated"` / `"ForbiddenFound"` / `"SharedInputPlaces"` / `"DuplicatedTransitions"` / `"Attempts"` 等を含む Association。
- **`reviewPetriProposal[goal]`** — 提案を Frame 付き Column で人間が読める形式で表示します(コード本体・診断指標)。
- **`parsePetriCode[code]`** — 生成コードを評価して `WorkflowNet[...]` Association を取り出します。`builder[]` 不在時には末尾の `WorkflowNet[...]` 式を直接評価する fallback あり。
- **`plotPetriNet[netOrWid]`** — 基本的なペトリネット可視化(Tooltip なし、Observability の `plotPetriNetDetail` とは独立に共存)。

なお、proposal を直接 builder として展開する `ClaudeApplyProposal`、Payload Association 生成の糖衣関数 `ClaudeSubmitInputs` / `ClaudeBindAndSubmit` は Workflow サブモジュールに統合済みなので、本サンプルと組み合わせてシンプルに記述できます。

詳細な実行例は `example.md` の Part A を参照してください。

### 非同期実行と状態管理

`ClaudeRunOrchestrationAsync` は Planning → Spawn → Reduce → Commit の全フェーズを DAG コールバックチェーンで非同期実行し、呼び出し元をブロックせずに `orchJobId` を即座に返します。`ClaudeOrchestrationStatus`・`ClaudeOrchestrationResult`・`ClaudeOrchestrationWait`・`ClaudeOrchestrationCancel` でジョブのライフサイクルを制御できます。

### ClaudeEval との統合(非同期化 — v2026-04-20 以降)

**ClaudeOrchestrator をロードすると、`ClaudeEval` の実装が自動的にオーケストレーターベースに切り替わります。** 具体的には、パッケージ読み込み時に `$ClaudeEvalHook` が上書きされ、以後の `ClaudeEval[...]` 呼び出しはすべてオーケストレーターパイプライン経由で実行されます。

`$ClaudeEvalHook` はオーケストレーションを `ClaudeRunOrchestrationAsync` 経由で起動し、フロントエンド(ノートブック UI)をブロックせずに `orchJobId` を即座に返します。完了後の結果は `ClaudeOrchestrationResult` で取得できます。

ClaudeRuntime 単体の動作に戻したい場合は、ClaudeOrchestrator をロードしないか、`$ClaudeEvalHook` を手動でリセットしてください。

### Auto ゲート

`$ClaudeEvalAutoSkipKeywords` / `$ClaudeEvalAutoFactualEndings` / `$ClaudeEvalAutoComplexMarkers` の 3 つのリストにより、Auto モードでの分岐をプロジェクトに合わせて調整できます。短い factual query（パッケージ名・関数名・拡張子などのマーカーや「を調べて」「を教えて」「check」などの語尾を含むもの）は Orchestrator を経由せず Single パスに直送し、「スライド」「レポート」「プレゼン」「ペトリネット」など複雑タスク識別マーカーが含まれるプロンプトは短文でも Orchestrator 経路を通します。

### モジュール構成と自動ロード

`ClaudeOrchestrator.wl` のモジュール構成は、**本体に直接インライン統合された旧サブモジュール群** と、**自動ロードされる 3 つの外部サブモジュール** の二層に整理されています。

#### 本体にインライン統合済みの旧サブモジュール (Phase 36, 2026-04-28 以降)

以下の旧サブモジュールは現在 `ClaudeOrchestrator.wl` 本体にインライン統合されており、別ファイルとしてのロードは不要です。`Get["ClaudeOrchestrator.wl"]` ひとつですべて利用できます。

- 旧 `ClaudeOrchestratorDirectives` — ディレクティブ管理 (Role / Capability / 禁止 Head)
- 旧 `ClaudeOrchestratorRouting` — ローカル LLM 名・モデル名のルーティング
- 旧 `claudecode_commit_safety.wl` — コミット前後の整合性チェック (HeldExpr 検出・決定論的フォールバック)
- 旧 `claudecode_a4_stub.wl` / `ClaudeOrchestratorA4` — A4 フェーズ用フック群

これらの機能は本体パッケージから引き続き呼び出せます。バージョン文字列はそれぞれ `$DirectivesVersion` / `$RoutingVersion` / `$ClaudeCommitSafetyVersion` / `$A4StubVersion` として参照できます。

#### 自動ロードされる外部サブモジュール (3 ファイル)

以下の 3 ファイルは `ClaudeOrchestrator.wl` のロード時に自動的に取り込まれます。`BeginPackage["ClaudeOrchestrator\`"]` と同一コンテキストを使うため、外側から見ると単一パッケージのように扱えます。

| ファイル | 役割 | 主な公開 API |
|---|---|---|
| [`ClaudeOrchestrator_workflow.wl`](https://github.com/transreal/ClaudeOrchestrator_workflow) | multi-token Petri net 実行エンジン (`ClaudeOrchestrator\`Workflow\``) | `ClaudeCreateWorkflowNet` / `ClaudeSubmitToken` / `ClaudeSubmitInputs` / `ClaudeBindAndSubmit` / `ClaudeApplyProposal` / `ClaudeRunWorkflow` / `ClaudeWorkflowState` / `ClaudeSnapshotWorkflow` ほか |
| [`ClaudeOrchestrator_observability.wl`](https://github.com/transreal/ClaudeOrchestrator_observability) | LLM 呼び出し・transition handler のログ／Tooltip 付き可視化 (ChatGPT Codex を含む複数プロバイダの provenance 記録対応) | `ClaudeQueryBgLogged` / `showLLMCallLog` / `instrumentNetForObservation` / `plotPetriNetDetail` / `traceTransitions` / `checkPetriNetVertices` ほか |
| [`ClaudeOrchestrator_promptworkflow.wl`](https://github.com/transreal/ClaudeOrchestrator_promptworkflow) | `ClaudeEval` の複雑プロンプトを WorkflowNet として再実行する経路 | `ClaudeWorkflowComplexPromptQ` / `ClaudeProposeWorkflowNetFromPrompt` / `ClaudeParseWorkflowNetCode` / `ClaudeWorkflowCheckForbidden` / `ClaudeCreateWorkflowRouteDraft` / `ClaudeWorkflowRouteFromPrompt` ほか |

自動ロードはファイル単位の存在チェック + 重複ロード回避を行うため、`ClaudeOrchestrator.wl` を 2 回 `Get` しても副作用はありません。手動ロード防止フラグ (例: `Global\`$ClaudeOrchestratorDisablePromptWorkflowAutoLoad = True`) を立てると個別に無効化できます。観測モジュールは `BeginPackage` を持たない読み込み型ファイルなので、`$petriObservabilityVersion` の `ValueQ` で初期化済みかを判定しています。

#### サンプル: `docs/examples/petri_from_prompt.wl`

自然文プロンプトから WorkflowNet を生成するサンプル兼ライブラリ `docs/examples/petri_from_prompt.wl` がリポジトリに同梱されています。**これは example の段階の参考実装で、`ClaudeOrchestrator.wl` 本体には統合されておらず、自動ロードもされません。** 自然文 → ネット生成 → 実行 → 観測 の一連のフローを試す場合は、`ClaudeOrchestrator.wl` をロードしたあと別途 `Get` してください。詳細は `example.md` の事前準備を参照。

### Real LLM 統合

`$ClaudeOrchestratorRealLLMEndpoint` を `"ClaudeCode"`（ClaudeCode パッケージ経由）・`"CLI"`（claude CLI を RunProcess で呼ぶ）・カスタム関数のいずれかに設定することで、実際の LLM をプランナーとして利用できます。デフォルト（`None`）はモックのみで動作するため、CI 環境でも安全に使用できます。Windows 環境では `claude.cmd` を自動検出し、UTF-8 の文字化けを防ぐためにファイル経由の stdout 取得方式（`chcp 65001` + リダイレクト）を採用しています。

ChatGPT Codex など Claude 以外のプロバイダで実行された呼び出しも、Observability サブモジュールの `$LLMCallLog` に `ProviderKind` / `ProviderDisplayName` 付きで保存されるため、混在運用時のトレースが容易です。

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

[github](https://github.com/transreal/github) パッケージがインストール済みの場合は、`GitHubInstallPackage` でリポジトリから `$packageDirectory` へ直接インストールできます。

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["GitHub`", "github.wl"]];

GitHubInstallPackage["ClaudeOrchestrator",
  "https://github.com/transreal/ClaudeOrchestrator"]
```

自動ロードされる 3 つの外部サブモジュール (`ClaudeOrchestrator_workflow.wl` / `ClaudeOrchestrator_observability.wl` / `ClaudeOrchestrator_promptworkflow.wl`) は `ClaudeOrchestrator.wl` と同じディレクトリに必要です（本体ロード時に自動ロードされます）。リポジトリに同梱されている場合は同時に取得されます。一度インストールしたパッケージは `GitHubUpdatePackage["ClaudeOrchestrator"]` で最新版に更新できます。

github パッケージを使わない場合は、`git clone` で取得します。

```
git clone https://github.com/transreal/ClaudeOrchestrator
```

いずれの場合も、依存パッケージも同じ `$packageDirectory` に配置します。

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [claudecode](https://github.com/transreal/claudecode)
- [github](https://github.com/transreal/github)（インストールの簡略化に使用）

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
- **`ClaudeSubmitInputs[wid, payload, place]`** — `payload` Association から `Kind="Task"` の Token を作って SourcePlace に投入する糖衣関数。
- **`ClaudeBindAndSubmit[wid, vars...]`** — グローバルシンボル群を `SymbolName -> 値` の Association として束ねて投入する HoldRest 糖衣関数。
- **`ClaudeApplyProposal[pro