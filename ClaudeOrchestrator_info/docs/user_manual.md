# ClaudeOrchestrator ユーザーマニュアル

## 目次

1. [概要](#概要)
2. [基本的な使い方](#基本的な使い方)
3. [タスク分解・計画フェーズ](#タスク分解計画フェーズ)
4. [ワーカー起動・アーティファクト収集フェーズ](#ワーカー起動アーティファクト収集フェーズ)
5. [アーティファクト統合フェーズ](#アーティファクト統合フェーズ)
6. [コミットフェーズ](#コミットフェーズ)
7. [非同期実行 API](#非同期実行-api)
8. [バッチ実行](#バッチ実行)
9. [ペトリネット拡張 (Workflow + Observability + PromptWorkflow)](#ペトリネット拡張-workflow--observability--promptworkflow)
10. [Real LLM 統合](#real-llm-統合)
11. [グローバル設定変数](#グローバル設定変数)
12. [エラーと検証](#エラーと検証)

---

## 概要

ClaudeOrchestrator は [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) の上位レイヤーとして動作する、マルチエージェント分解・並列ワーカー配車・アーティファクト収集・統合・コミット機構です。

**設計上の基本原則:**

- ClaudeRuntime は単一エージェント実行核として維持します。
- 並列ワーカーはアーティファクト生成のみを担当し、`NotebookWrite` を直接呼び出しません。
- 実ノートブックへの書き込みは **single committer** のみが行います。
- ワーカー間の共有状態は明示的な `Association` / JSON / アーティファクトで受け渡します。

```
NBAccess → claudecode_base → ClaudeRuntime → ClaudeOrchestrator → claudecode
```

**ClaudeEval の非同期化(v2026-04-20 以降):**

`$ClaudeEvalHook`(ClaudeEval) は `ClaudeRunOrchestrationAsync` 経由でオーケストレーションを起動し、フロントエンド(ノートブック UI)をブロックせずに `orchJobId` を即座に返します。完了後の結果は `ClaudeOrchestrationResult` で取得できます。

**自動ロードされるサブモジュール:**

以下のサブモジュールは本体に統合されており、`ClaudeOrchestrator.wl` を単独で `Get` するだけで利用できます。

- `ClaudeOrchestratorDirectives` — ディレクティブ管理
- `ClaudeOrchestratorRouting` — ローカル LLM 名／モデル名のルーティング
- `claudecode_commit_safety` — コミット前後の整合性チェック
- `claudecode_a4_stub` → `ClaudeOrchestratorA4` — A4 フェーズ用フック群
- `ClaudeOrchestrator`Workflow`` — multi-token Petri net 実行エンジン (`ClaudeOrchestrator_workflow.wl`)
- 観測サブモジュール — `ClaudeOrchestrator_observability.wl`
- PromptWorkflow 拡張 — `ClaudeEval` の複雑プロンプトを WorkflowNet として再実行する経路 (`ClaudeOrchestrator_promptworkflow.wl`)

**Auto ゲート強化:**

`$ClaudeEvalAutoSkipKeywords` / `$ClaudeEvalAutoFactualEndings` / `$ClaudeEvalAutoComplexMarkers` の 3 つのリストにより、Auto モードで短い factual query をオーケストレーション経路から除外し、Single パスに直送できます。詳細は[グローバル設定変数](#グローバル設定変数)を参照してください。

---

## 基本的な使い方

```wolfram
(* パッケージ読み込み *)
Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]
Needs["ClaudeOrchestrator`"]
```

オーケストレーションは**フロントエンドをブロックしない非同期実行に統一**されています。`ClaudeRunOrchestrationAsync` で起動し、`ClaudeOrchestrationStatus` で進捗を確認、`ClaudeOrchestrationWait` で完了を待ってから `ClaudeOrchestrationResult` で結果を取り出します。

```wolfram
jobId = ClaudeRunOrchestrationAsync[
  "30 ページのスライド資料を作成する",
  MaxTasks -> 5];
(* すぐに orchJobId が返る — ノートブック UI はブロックされない *)

ClaudeOrchestrationStatus[jobId][["Status"]]
(* "Planning" → "Spawning" → "Reducing" → "Committing" → "Done" *)

ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["Status"]]
(* "Complete" など *)
```

---

## タスク分解・計画フェーズ

### ClaudePlanTasks

親タスクを TaskSpec の DAG (有向非巡回グラフ) に分解します。

**シグネチャ:**
```wolfram
ClaudePlanTasks[input, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `Planner` | `Automatic` | プランナー関数（省略時はモック） |
| `MaxTasks` | `10` | 生成するタスクの最大数 |

**戻り値の構造:**
```wolfram
<|
  "Tasks" -> {
    <|
      "TaskId" -> "t1",
      "Role" -> "Explore",
      "Goal" -> "テンプレートの構造を把握する",
      "Inputs" -> {"templateSnapshot"},
      "Outputs" -> {"templateSummary"},
      "Capabilities" -> {"ReadNotebookSnapshot", "StructuredOutput"},
      "DependsOn" -> {},
      "ExpectedArtifactType" -> "TemplateSummary",
      "OutputSchema" -> <|"Headings" -> "List[String]", ...|>
    |>,
    ...
  }
|>
```

**使用例:**
```wolfram
plan = ClaudePlanTasks[
  "Mathematica パッケージのドキュメントを自動生成する",
  MaxTasks -> 4
];
plan["Tasks"] // Length
(* 4 *)
```

---

### ClaudeValidateTaskSpec

TaskSpec の妥当性 (必須キーの存在、Role の整合性など) を検証します。

**シグネチャ:**
```wolfram
ClaudeValidateTaskSpec[taskSpec]
```

**戻り値:** `<|"Valid" -> True/False, "Errors" -> {...}|>`

**使用例:**
```wolfram
validation = ClaudeValidateTaskSpec[plan];
If[validation["Valid"],
  Print["TaskSpec is valid."],
  Print[validation["Errors"]]
]
```

---

## ワーカー起動・アーティファクト収集フェーズ

### ClaudeSpawnWorkers

TaskSpec の依存順に従ってワーカー runtime を起動し、各タスクのアーティファクトを収集します。現バージョンは順次実行（`MaxParallelism -> 1`）です。

**シグネチャ:**
```wolfram
ClaudeSpawnWorkers[tasks, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `WorkerAdapterBuilder` | `Automatic` | `(Role, TaskSpec) -> adapter` を返す関数 |
| `MaxParallelism` | `1` | 並列数（Stage 2 以降で拡張予定） |

**戻り値:**
```wolfram
<|
  "Artifacts" -> <|"t1" -> artifact1, "t2" -> artifact2, ...|>,
  "Failures"  -> {},
  "Status"    -> "Complete"  (* "Complete" | "Partial" | "Failed" *)
|>
```

**使用例:**
```wolfram
spawnResult = ClaudeSpawnWorkers[plan["Tasks"]];
spawnResult["Status"]
(* "Complete" *)
```

---

### ClaudeCollectArtifacts

`ClaudeSpawnWorkers` の結果からアーティファクトを `Dataset` として取得します。ノートブック上で確認しやすい形式で返します。

**シグネチャ:**
```wolfram
ClaudeCollectArtifacts[spawnResult]
```

**使用例:**
```wolfram
artifacts = ClaudeCollectArtifacts[spawnResult];
artifacts  (* Dataset として表示 *)
```

---

### ClaudeValidateArtifact

アーティファクトの `Payload` が `OutputSchema` を満たすか検証します。

**シグネチャ:**
```wolfram
ClaudeValidateArtifact[artifact, outputSchema]
```

**戻り値:** `<|"Valid" -> True/False, "Errors" -> {...}|>`

**使用例:**
```wolfram
schema = <|"Headings" -> "List[String]", "Constraints" -> "List[String]"|>;
ClaudeValidateArtifact[artifacts["t1"], schema]
(* <|"Valid" -> True, "Errors" -> {}|> *)
```

---

## アーティファクト統合フェーズ

### ClaudeReduceArtifacts

複数のアーティファクトを統合し、ReducedArtifact を生成します。

**シグネチャ:**
```wolfram
ClaudeReduceArtifacts[artifacts, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `Reducer` | `Automatic` | `artifacts -> ReducedArtifact` を返す関数 |

**戻り値:**
```wolfram
<|
  "ArtifactType" -> "Reduced",
  "Payload"      -> <| ... |>,
  "Sources"      -> {"t1", "t2", ...}
|>
```

**使用例:**
```wolfram
reduced = ClaudeReduceArtifacts[
  spawnResult["Artifacts"],
  Reducer -> Function[arts, <|"Summary" -> arts|>]
];
reduced["ArtifactType"]
(* "Reduced" *)
```

---

## コミットフェーズ

### ClaudeCommitArtifacts

single committer runtime を起動し、`reducedArtifact` を対象ノートブックに反映します。

**重要:** `EvaluationNotebook[]` / `CreateNotebook[...]` への参照は、指定した `targetNotebook` に自動置換されます。

**シグネチャ:**
```wolfram
ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `CommitterAdapterBuilder` | `Automatic` | committer adapter 構築関数 |
| `CommitMode` | `"Direct"` | `"Direct"` または `"Transactional"` |
| `Verifier` | `Automatic` | `(buffer, cells) -> True/False` |

**`"Transactional"` モード:** shadow buffer に書いてから検証・フラッシュします。失敗時は対象ノートブックを無変更のまま rollback します (spec §12.3)。

**戻り値:**
```wolfram
<|
  "Status"  -> "Committed"  (* "Committed" | "Failed" | "RolledBack" *),
  "Mode"    -> "Direct",
  "Details" -> <| ... |>
|>
```

`CommitResult["Diagnostics"]` には commit safety 経路を通った場合に `HeldExprFound` / `LastProviderResponseHead` などの診断情報が付属します。`"CommitRetryMax" -> N` で再試行回数を、`"DeterministicFallback" -> False` で決定論的フォールバックを無効化できます。

**使用例:**
```wolfram
nb = InputNotebook[];
commitResult = ClaudeCommitArtifacts[nb, reduced,
  CommitMode -> "Transactional"
];
commitResult["Status"]
(* "Committed" *)
```

---

## 非同期実行 API

オーケストレーションは**フロントエンドをブロックしない非同期実行に統一**されています。`ClaudeRunOrchestrationAsync` で起動し、`ClaudeOrchestrationStatus` / `ClaudeOrchestrationResult` / `ClaudeOrchestrationWait` / `ClaudeOrchestrationCancel` でジョブのライフサイクルを制御します。`$ClaudeEvalHook`(ClaudeEval) もこの非同期 API を経由します。

### ClaudeRunOrchestrationAsync

Planning → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し、`orchJobId` を即座に返します。

**シグネチャ:**
```wolfram
ClaudeRunOrchestrationAsync[input, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `TargetNotebook` | (なし) | Commit 先ノートブック(指定時のみ Commit フェーズを実行) |
| `Planner` | `Automatic` | プランナー関数 |
| `WorkerAdapterBuilder` | `Automatic` | ワーカー adapter 構築関数 |
| `Reducer` | `Automatic` | Reducer 関数 |
| `CommitterAdapterBuilder` | `Automatic` | Committer adapter 構築関数 |
| `MaxTasks` | `10` | タスク上限数 |
| `MaxParallelism` | `1` | 並列数 |
| `Confirm` | `False` | 各フェーズ前に確認を求めるか |
| `Model` | `Automatic` | 実 LLM を使うときのモデル名指定 |

**戻り値:** `orchJobId`(文字列)。実行結果は `ClaudeOrchestrationResult[orchJobId]` で取得します。

**`$ClaudeEvalHook` との関係:**

`$ClaudeEvalHook` は内部的にこの関数を呼び出します。ノートブックのセルを評価するとバックグラウンドでオーケストレーションが開始され、セルの評価は即座に完了します。結果は `ClaudeOrchestrationResult` で後から取得します。

**使用例:**
```wolfram
jobId = ClaudeRunOrchestrationAsync["論文要約を 3 つ作成する", MaxTasks -> 3];
jobId
(* "orch-20260421-001" *)
```

---

### ClaudeOrchestrationStatus

実行中ジョブの現在フェーズと経過時間を返します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationStatus[orchJobId]
```

**戻り値例:**
```wolfram
<|
  "Status"      -> "Spawning",
  "Phase"       -> "worker-t2",
  "ElapsedSecs" -> 12.4,
  "PlanJobId"   -> "plan-001",
  "SpawnJobId"  -> "spawn-001"
|>
```

---

### ClaudeOrchestrationResult

完了済みジョブの最終結果を返します。未完了の場合は `Missing` を返します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationResult[orchJobId]
```

**使用例:**
```wolfram
(* ポーリング例 *)
While[ClaudeOrchestrationStatus[jobId]["Status"] =!= "Done", Pause[5]];
ClaudeOrchestrationResult[jobId]
```

---

### ClaudeOrchestrationWait

ジョブ完了まで待機します（テスト・スクリプト専用。対話セルでは使用を避けてください）。

**シグネチャ:**
```wolfram
ClaudeOrchestrationWait[orchJobId, timeoutSec]
```

既定タイムアウトは 300 秒です。

**使用例:**
```wolfram
ClaudeOrchestrationWait[jobId, 120]
ClaudeOrchestrationResult[jobId]
```

---

### ClaudeOrchestrationCancel

実行中の DAG を中断し、レジストリから除去します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationCancel[orchJobId]
```

**使用例:**
```wolfram
ClaudeOrchestrationCancel[jobId]
```

---

### ClaudeOrchestrationJobs

追跡中のジョブ一覧を `Dataset` で返します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationJobs[]
```

**使用例:**
```wolfram
ClaudeOrchestrationJobs[]
(* Dataset[<|"orch-001" -> <|"Status" -> "Done", ...|>, ...|>] *)
```

---

## バッチ実行

### ClaudeContinueBatch

単一の runtime セッションを維持したまま、複数の prompt を `ClaudeContinueTurn` で順次投入します。ノートブック共有問題を回避する現実解です（spec §17.1）。

**シグネチャ:**
```wolfram
ClaudeContinueBatch[runtimeId, batchInstructions, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `WaitBetween` | `Quantity[1, "Seconds"]` | 各プロンプト間の待機時間 |

**戻り値:** `{<|"Index" -> i, "Prompt" -> ..., "Result" -> ...|>, ...}`

**使用例:**
```wolfram
rt = CreateClaudeRuntime[...];  (* ClaudeRuntime より *)
batchResult = ClaudeContinueBatch[
  rt["RuntimeId"],
  {"第1章を要約せよ", "第2章を要約せよ", "全体をまとめよ"},
  WaitBetween -> Quantity[2, "Seconds"]
];
batchResult[[All, "Result"]]
```

---

## ペトリネット拡張 (Workflow + Observability + PromptWorkflow)

ClaudeOrchestrator は、DAG に閉じない並行・同期・選択を含むワークフローを **place / transition / arc / token / marking** のペトリネット用語のまま記述・実行できる Workflow エンジン (`ClaudeOrchestrator\`Workflow\``) と、それを観測するための Observability サブモジュールを内蔵しています。どちらも `ClaudeOrchestrator.wl` をロードすれば**自動的に取り込まれます**(2026-05-15 以降)。

さらに、参考実装として `docs/examples/petri_from_prompt.wl` というサンプル兼ライブラリが付属しており、自然言語の目標から LLM にネット仕様を生成させることができます。**これは example の段階の参考実装で本体には統合されていないため、利用する場合は別途 `Get` してください。**

**全体の流れ:**

```
自然文 goal
   ↓ proposePetriNet            (petri_from_prompt.wl: LLM がコード生成)
proposal["Code"]                 (コード文字列)
   ↓ parsePetriCode              (ToExpression で WorkflowNet[...] を取り出す)
net                              (Association: Places / Transitions / ...)
   ↓ instrumentNetForObservation (observability: handler を観測ラッパで包む)
observedNet
   ↓ ClaudeCreateWorkflowNet     (Workflow: WorkflowId を発行・登録)
wid                              (以後の API はすべて wid で呼ぶ)
   ↓ ClaudeSubmitToken           (SourcePlace に初期 token を投入)
   ↓ ClaudeRunWorkflow           (sink 到達 / MaxSteps まで実行 / Async 切替可)
   ↓ traceTransitions / showLLMCallLog / plotPetriNetDetail
```

具体的な逐次実行は `example.md` の **Part A** にまとまっています。本節では API リファレンスを役割別に解説します。

---

### A. ネット生成 (docs/examples/petri_from_prompt.wl)

サンプル兼ライブラリ `docs/examples/petri_from_prompt.wl` が提供する API です。**`ClaudeOrchestrator.wl` 本体には統合されていない example 段階の参考実装**なので、利用する前に明示的に `Get` してください。

```wolfram
Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator_info",
  "docs", "examples", "petri_from_prompt.wl"}]]
```

#### proposePetriNet

```
proposePetriNet[goal_String, opts:OptionsPattern[]]
```

自然言語の目標 `goal` を Claude CLI 経由で LLM に渡し、`buildXxxNet[] := WorkflowNet[<|...|>]` 形式の Wolfram コードを生成させます。生成コードは複数の静的検査(禁止 API 検出・共有入力 Place 検出・重複 transition 検出・retry guard 検出)を経て、問題があれば自動的にフィードバックを付けて再生成します。

**主なオプション:**

- `"Providers"` (`{}`) — `{"anthropic", "openai", ...}` のリスト。空なら単一プロバイダ(claudecode CLI)。複数指定すると multi-provider モードに切り替わります。
- `"InputPayloadKeys"` (`{}`) — 各 handler が入力 Token の `Payload` から取り出すべきキー名のヒント。生成コードのプロンプトに混ぜられます。
- `"MaxRetries"` (`2`) — 自動再生成の最大回数。`MaxRetries + 1` 回試行されます。
- `"Verbose"` (`False`) — 再試行のたびに進捗を Print。

**戻り値 Association の主なキー:**

| キー | 内容 |
|---|---|
| `"Goal"` | 入力 goal をそのまま |
| `"Code"` | LLM が生成した Wolfram コード(コードブロック ``` の中身) |
| `"BuilderName"` | 検出された builder 関数名(例: `"buildPiComparisonNet"`) |
| `"CodeLength"` / `"ResponseLength"` | 文字数 |
| `"Truncated"` | LLM 応答が途中で切れている(閉じ ``` 無し)なら `True` |
| `"ForbiddenFound"` | 禁止 API のリスト(本来 `ClaudeCreateWorkflowNet` 等は呼ばせない) |
| `"SharedInputPlaces"` | 複数 transition が共有する入力 Place(Stuck の原因) |
| `"DuplicatedTransitions"` | 同名 transition の重複 |
| `"RetryGuardIssues"` / `"PayloadAccessIssues"` | 設計問題のヒント |
| `"IsErrorResponse"` | LLM が API エラー応答を返している場合 `True` |
| `"Attempts"` | 実際に試行した回数 |

**典型例:**

```wolfram
proposal = proposePetriNet[
  "3 つの方法 (Monte Carlo / Leibniz / Wallis) で π を近似計算し、結果を比較する"];
proposal["BuilderName"]    (* 例: "buildPiComparisonNet" *)
proposal["Code"]           (* 生成されたコード文字列 *)
```

#### reviewPetriProposal

```
reviewPetriProposal[goal_String]
```

`proposePetriNet[goal]` を呼んだ上で、結果を Frame 付き Column で人間が読める形式に整形して返します。診断指標(Status / BuilderName / SharedInputPlaces / ResponseLen / CodeLen)とコード本体が一覧できます。LLM 応答品質の目視確認に使います。

#### parsePetriCode

```
parsePetriCode[code_String]
```

生成コード(文字列)を `ToExpression` で評価して、`WorkflowNet[...]` の Association を取り出します。

- 内部で禁止 API を再チェックし、検出されたら `$Failed` を返してエラー出力(LLM が指示に反したケース)。
- `buildXxxNet[]` を呼んで返り値が `WorkflowNet[...]` Association ならそれを返す。
- builder 不在または非 Association の場合は、コード末尾の `WorkflowNet[...]` 式を直接評価する fallback あり(ChatGPT 5.5 など直書き型に対応)。

**戻り値:** WorkflowNet Association(`"Places"`、`"Transitions"`、`"SourcePlace"`、`"FinalPlaces"`、`"InitialMarking"` 等を持つ)。エラー時は `$Failed`。

#### plotPetriNet

```
plotPetriNet[netOrWid, opts:OptionsPattern[Graph]]
```

WorkflowNet を Petri net グラフ(Place = 円、Transition = 四角)として描画します。`netOrWid` には Association(`parsePetriCode` の結果)または既に登録された wid 文字列のどちらでも渡せます。Tooltip 無し(基本表示)で、Observability の `plotPetriNetDetail` とは独立に共存します。

---

### B. ネット実行エンジン (ClaudeOrchestrator`Workflow`)

`ClaudeOrchestrator_workflow.wl` が提供する公開 API です。すべて `ClaudeOrchestrator.wl` をロードするだけで利用できます。

#### B-1. 型ビルダー(immutable)

| 関数 | 役割 |
|---|---|
| `WorkflowToken[opts]` | Token Association を生成。`"TokenId"` (Automatic)、`"Kind"` (`"Task"`/`"Worker"`/`"Artifact"`/`"Approval"`/`"PackageTransaction"`/`"XSMSentinel"`)、`"Payload"` (Association)、`"PrivacyLabel"`、`"ParentIds"`、`"CreatedBy"`。 |
| `WorkflowPlace[name, opts]` | Place Association を生成。`"Capacity"` (Infinity)、`"Visibility"` (`"Internal"`/`"UserVisible"`)、`"AcceptedKinds"` (All または List)、`"Description"`。 |
| `WorkflowTransition[name, opts]` | Transition Association を生成。`"InputArcs"` / `"OutputArcs"` (`{<\|"Place"->...,"Multiplicity"->1,"TokenKind"->...\|>, ...}`)、`"Guard"` (Function または None)、`"Executor"` (`"ClaudeRuntime"`/`"PackageManager"`/`"PureFunction"`/`"External"`)、`"RuntimeSpec"`、`"RetryPolicy"`、`"AccessPolicy"`、`"Timeout"`、`"Priority"`。 |
| `WorkflowNet[opts]` | ネット全体。必須: `"SourcePlace"`。既定: `"FinalPlaces" -> {"Done"}`、`"Places"`、`"Transitions"`、`"InitialMarking"`、`"Description"`、`"ParentRuntime"`。 |

#### B-2. 登録と Token 投入

| 関数 | 役割 |
|---|---|
| `ClaudeCreateWorkflowNet[spec, opts]` | spec を validate し WorkflowId を発行・registry に登録。実行はまだ開始しない。オプション: `"ValidateStrict" -> True`、`"Description"`、`"ParentRuntime"`。 |
| `ClaudeSubmitToken[wid, token, place_:Automatic]` | Token を指定 place に投入(既定は SourcePlace)。Token は immutable に保たれ、後続 transition で consume + produce される。multi-source workflow なら place を明示して各 source を seed。 |

#### B-3. Fire 制御と実行

| 関数 | 役割 |
|---|---|
| `ClaudeEnabledTransitions[wid]` | 現在 fire 可能な `{<\|"Name", "Binding" -> <\|place -> token\|>, "Priority"\|>, ...}` を Priority 降順で返す。 |
| `ClaudeFireTransition[wid, name, binding, opts]` | 1 transition を 1 binding で fire。NBAccess hard policy → guard → capability の順で検証し、通れば input tokens を consume + output tokens を produce。オプション `"ForceAllow" -> False`(テスト用 bypass)。戻り値に `"Status"` (`"Fired"`/`"Blocked"`/`"NeedsApproval"`)・`"ConsumedTokens"`・`"ProducedTokens"`・`"ExecutorResult"`・`"Marking"`。 |
| `ClaudeStepWorkflow[wid, opts]` | enabled の中から Priority 最優先の 1 つを選んで fire。Stuck (enabled 空)なら `"Status" -> "Stuck"` を返す。 |
| `ClaudeRunWorkflow[wid, opts]` | sink 到達 / enabled 空 / `MaxSteps` 到達まで Step を反復。`"Async" -> True` で `ClaudeCode\`$iSharedPollingTask` に寄生して非同期実行、即座に WorkflowId を返す。オプション: `"Async"` (False)、`"MaxSteps"` (1000)、`"MaxWait"` (Quantity[600, Seconds])、`"ForceAllow"` (False)。Sync 戻り値: `"Status"`・`"TerminationReason"`・`"Steps"`・`"ElapsedSec"`・`"FinalMarking"`・`"StepLog"`。Async 戻り値: `"WorkflowId"`・`"Status" -> "Async-Started"`・`"PollKey"`・`"StartTime"`。 |

#### B-4. 状態参照とトレース

| 関数 | 役割 |
|---|---|
| `ClaudeWorkflowStatus[wid]` | 軽量な現在状態。`<\|"Status", "CurrentMarking", "ElapsedSec"\|>`。 |
| `ClaudeWorkflowList[]` | 登録済み全 WorkflowNet の wid と Status を Dataset で返す。 |
| `ClaudeWorkflowState[wid]` | 詳細な現在状態。`<\|"Tokens" -> <\|tid -> tokenAssoc\|>, "Marking" -> <\|placeName -> {tids}\|>, "Status", "WorkflowId"\|>`。Test/inspector から Payload まで参照可。 |
| `ClaudeWorkflowTrace[wid]` | 実行 trace event のリスト。`{<\|"Event", "Timestamp", ...\|>, ...}`。 |

#### B-5. ライフサイクル制御

| 関数 | 役割 |
|---|---|
| `ClaudePauseWorkflow[wid]` | Status を `"Paused"` に。Step / Run は `"Skipped"` を返す。 |
| `ClaudeResumeWorkflow[wid]` | `"Paused"` → `"Running"` 復帰。それ以外は no-op。 |
| `ClaudeCancelWorkflow[wid]` | Status を `"Cancelled"`(再開不可、Resume は Paused のみ)。Async 実行中にも効き、polling task entry もクリーンアップ。 |
| `ClaudeWaitWorkflow[wid, opts]` | Async 起動した workflow が完了するまで同期的に待つ。`"MaxWait" -> Quantity[300, "Seconds"]` 既定。 |
| `ClaudeAsyncJobInfo[wid]` | Async ジョブの進捗情報。 |
| `ClaudeCleanupAsyncJob[wid]` | 終了済 Async ジョブの登録を GC。 |

#### B-6. Hook と Snapshot

| 関数 | 役割 |
|---|---|
| `ClaudeRegisterCompletionHook[wid, fn]` | workflow 完了時のコールバックを登録。同一 wid に複数登録可、登録順に一回限り発火。 |
| `ClaudeUnregisterCompletionHooks[wid]` | 登録解除。 |
| `ClaudeSnapshotWorkflow[wid, opts]` | WorkflowNet を FormatVersion 2 のディレクトリ(meta / workflow / llmgraph / aux)として `$ClaudeWorkflowSnapshotDir` 配下に保存。 |
| `ClaudeRestoreWorkflow[snapshotDir]` | snapshot から再構築。新しい wid を返す。 |
| `ClaudeListWorkflowSnapshots[wid_:All]` | snapshot 一覧。 |

---

### C. 観測 (Observability)

`ClaudeOrchestrator_observability.wl` が提供します。本体 (`ClaudeQueryBg` / `parsePetriCode` / `plotPetriNet`) を上書きせず別関数として共存する設計で、必要なときだけ装着します。

#### C-1. LLM 呼び出しログ

```
ClaudeQueryBgLogged[prompt, opts]
showLLMCallLog[]
showLLMCallLog[idx_Integer]
clearLLMCallLog[]
```

`ClaudeQueryBgLogged` は `ClaudeCode\`ClaudeQueryBg` と同じ呼び出しを行いつつ、開始時刻 / 所要時間 / Model / Fallback / Prompt / Response を `$LLMCallLog` に追記します。呼び出し中に `$CurrentObservedTransition`(後述 `instrumentNetForObservation` が束縛)が立っていれば、その transition 名も記録されます。

`showLLMCallLog[]` は呼出履歴を Dataset で返し、`showLLMCallLog[idx]` で 1 件の Prompt / Response 全文を Pane 付き Column で表示します。`clearLLMCallLog[]` でリセット。

#### C-2. Handler 観測

```
instrumentNetForObservation[net]
clearObservedHandlerLog[]
$ObservedHandlerLog
```

`instrumentNetForObservation` は net の各 transition の Handler を観測ラッパで包んだ新しい net を返します。副次効果:

- Symbol handler でも明示的に `handler[binding]` を呼ぶラッパで包むので、本体 `iExecutePureFunction` の Symbol/Function 判定差(Bug 2)を回避できます。
- `Block` で `$CurrentObservedTransition` を局所束縛するので、handler 内で `ClaudeQueryBgLogged` が transition 名を知ることができます。

handler が呼ばれるたびに `$ObservedHandlerLog` に `<\|"TransitionName", "Time", "Binding", "OutputRaw", "OutputAssocQ", "OutputHead", "RawKeys", "PayloadKeys", "PayloadKeyMissing", "FailedHead", "Messages"\|>` が追記されます。

#### C-3. Logger 注入

```
withLLMLogging[code_String]
```

文字列コード中の `ClaudeQueryBg` 呼び出しを `Global\`ClaudeQueryBgLogged` に置換した新しい文字列を返します。`ClaudeCode\`ClaudeQueryBg` と無修飾 `ClaudeQueryBg` の両方を扱い、関数名のみを書き換えるので Function スコープ・局所変数・HoldAll などには影響しません。

`proposePetriNet` が返したコード文字列を `parsePetriCode` する前に `withLLMLogging` でくぐらせると、`instrumentNetForObservation` を使わずに LLM 呼び出しだけログに残せます。

#### C-4. 可視化

```
plotPetriNetDetail[netOrWid, opts]
checkPetriNetVertices[net]
```

`plotPetriNetDetail` は本体 `plotPetriNet` の Tooltip 拡張版です。オプション `"TraceWid" -> wid` を渡すか、wid 文字列を直接第 1 引数に渡すと、Place / Transition / Edge にホバー Tooltip で:

- **Place** → 現在その place にあるトークンの TokenId / Kind / Payload
- **Transition** → handler 呼び出し履歴(binding / Output Payload / Messages)・対応する LLM 呼び出し履歴(Prompt / Response 抜粋)
- **Edge** → アークの種類(InputArc / OutputArc)・端点の役割

を表示する Graph を返します。Tooltip 無しの基本表示が欲しいときは本体 `plotPetriNet` を直接使ってください。

`checkPetriNetVertices` はネットの頂点整合性を検査する診断ユーティリティで、`<\|"DeclaredVertices", "VerticesFromEdges", "IsolatedDeclaredVertices", "UnknownVerticesInEdges"\|>` を返します。

- `IsolatedDeclaredVertices` が非空 → 宣言だけで辺を持たない頂点。`Graph[edges, ...]`(1 引数形式)では描画落ちするが、`plotPetriNet` / `plotPetriNetDetail` は 2 引数形式で対応済み。
- `UnknownVerticesInEdges` が非空 → handler や `iExtractEdges` のバグ可能性、または `Places` / `Transitions` の登録漏れ。

#### C-5. 実行追跡

```
traceTransitions[wid, opts]
```

`ClaudeWorkflowTrace` の firing event と `$ObservedHandlerLog` / `$LLMCallLog` を結合した Dataset を返します。各行は `Step` / `Transition` / `Status` / `OutputAssoc?` / `OutputHead` / `RawKeys` / `PayloadKeys` / `PayloadKeyMissing` / `FailedHead` / `Messages` / `ConsumedIds` / `ProducedIds` を含みます。

**オプション:**

- `"Detail" -> True` — 対応する LLM 呼び出し(Model / Prompt 抜粋 / Response 抜粋 / Duration)を統合した拡張 Dataset を返す。
- `"PromptPreviewLen" -> 200` / `"ResponsePreviewLen" -> 200` — Detail モードの Prompt / Response 抜粋文字数。
- `"TimeMatchTolerance" -> 60.0` — firing と LLM call の時刻マッチ許容幅(秒)。

#### C-6. ChatGPT Codex 対応 (2026-05-27 追記)

`ClaudeOrchestrator_observability.wl` は ChatGPT Codex(OpenAI 系プロバイダ)からの応答も `ClaudeQueryBgLogged` の単一経路でログ化できるよう、以下の点が更新されています。

- **応答パース耐性の強化**: Codex が返す応答が文字列ではなく `<|"response" -> ...|>` 形式の Association(あるいは入れ子の raw レコード)で返ってくるケースに対応し、`StringQ[raw], raw` → `AssociationQ[raw], Lookup[raw, "response", ...]` → `True, ToString[raw]` の優先順で安全にテキスト化します。Response が `HoldComplete` 等で包まれていても `ToString` まで降りて落ちません。
- **A6 post-processing フックの共通化**: `iApplyA6Hook[result, raw]` という内部フックを導入し、`ClaudeOrchestrator\`A6PostProcessParseProposal` が定義されていれば呼び出して `result` Association を加工した上で返します。未定義なら `result` をそのまま返す no-op です。これにより Codex 応答に固有の整形ロジック(`"ArtifactPayload" -> <|"Summary" -> text|>` への詰め直しなど)を本体を壊さず差し込めます。
- **transition 名の伝搬**: `Block[{$CurrentObservedTransition = ...}]` のスコープは Codex 呼び出し中も維持されるため、`showLLMCallLog[]` で Anthropic / OpenAI どちらの呼び出しかを `Model` 列で識別しつつ、`Transition` 列で発火元の transition を追跡できます。
- **自動ロード**: `ClaudeOrchestrator_observability.wl` は `ClaudeOrchestrator.wl` のロード時に自動取り込みされます。手動で再ロードしたい場合は `Get["ClaudeOrchestrator_observability.wl"]` を実行してください(`$petriObservabilityVersion` が定義されていれば取り込み済み)。

> Codex プロバイダ経由のときは `ClaudeQueryBgLogged` のオプションで `"Provider" -> "openai"` 等を明示するか、`$ClaudeOrchestratorRealLLMEndpoint` を経由してルーティング設定に従わせてください。`$LLMCallLog` の `Model` 列がプロバイダ識別の最終手段になります。

---

### D. PromptWorkflow 拡張 (ClaudeOrchestrator_promptworkflow.wl)

PromptWorkflow 拡張は、`ClaudeEval` に与えられた **複雑なプロンプト**(複数のサブタスクや順序制御を含むもの)を WorkflowNet として再実行するための経路です。`ClaudeOrchestrator.wl` のロード時に自動的に取り込まれます。

A 節の `proposePetriNet` が example 段階のサンプルであるのに対し、PromptWorkflow 拡張は本体に統合された機能で、LLM 提案コードの安全な取り扱い(評価前の静的検査・非評価 parse・承認待ち停止)を一貫して行います。

#### ClaudeWorkflowComplexPromptQ

プロンプトが workflow 候補かどうかを、**評価を伴わずローカルで** deterministic に判定します。ルーター LLM を呼ぶ前に動作するため、workflow 候補かを試すためだけに秘密のプロンプトが外部送信されることはありません。

```mathematica
ClaudeWorkflowComplexPromptQ["文書を要約し、要点を抽出し、レポートにまとめる"]
(* → <|"Decision" -> "WorkflowCandidate", "Reason" -> ..., "Signals" -> ...|> *)

ClaudeWorkflowComplexPromptQ["今日の天気は？"]
(* → <|"Decision" -> "NotComplex", ...|> *)
```

明示的な workflow 要求、複数のサブタスク動詞、またはサブタスク動詞と順序制御語の組み合わせを手がかりに判定します。

#### ClaudeProposeWorkflowNetFromPrompt

自然言語のゴールを WorkflowNet の提案に変換します。コードプロバイダーに WorkflowNet コードを要求し、safe parser に通し、失敗時は静的診断をフィードバックして再試行します。**提案のみ**で、workflow の実行・登録は一切しません。

```mathematica
prop = ClaudeProposeWorkflowNetFromPrompt[
  "文書を要約し、要点を抽出し、レポートにまとめる"];
prop["Status"]
(* "Proposed" / "NeedsRepair" / "Rejected" *)
prop["AttemptTrace"]   (* 各試行の記録 *)
```

**オプション:**

- `"MaxProposalAttempts" -> 3` — 提案の最大試行回数。
- `"CodeProvider" -> Automatic` — `Automatic` なら `ClaudeCode`ClaudeQuery` を weak-call。`Function` を渡すとコードを直接供給(テスト用)。
- `"FeedbackMode" -> "StaticDiagnostics"` — 再試行時に静的診断をフィードバック。

#### ClaudeParseWorkflowNetCode / ClaudeWorkflowCheckForbidden

LLM が提案した WorkflowNet コードを **評価せずに** 扱うための関数です。`ClaudeParseWorkflowNetCode` はフェンス付きコードブロックを抽出し、禁止パターン検査を行い、`HoldComplete` でくるんだ非評価 parse で AST から `WorkflowNet[spec]` を取り出します。builder を呼び出すことはありません。

```mathematica
res = ClaudeParseWorkflowNetCode[codeString];
res["Status"]
(* "Parsed" / "Rejected" / "ParseFailed" / "NoWorkflowNet" *)

(* 評価せずに禁止パターンだけを静的検査することもできる *)
ClaudeWorkflowCheckForbidden[codeString]
(* → <|"Status" -> "Clean" | "ForbiddenDetected", "Findings" -> {...}|> *)
```

`ClaudeWorkflowForbiddenPatternRegistry[]` で禁止パターンの一覧(ファイル / ネットワーク / プロセス / 資格情報 / notebook 変更系)を確認できます。

#### ClaudeCreateWorkflowRouteDraft

成功した提案を WorkflowRouteDraft に変換します。workflow コード本体は SourceVault PrivateVault 配下に private artifact として保存され、draft メタデータは `CodeHash` と `CodeStorage` 参照のみを持ちます。draft は Status `NeedsApproval` で作成され、自動昇格・自動実行はされません。

```mathematica
draft = ClaudeCreateWorkflowRouteDraft["...", prop];
draft["Status"]
(* "NeedsApproval" *)
```

**オプション:**

- `"DryRun" -> True` — 既定。書き込みを行わず計画のみ報告します。実際に保存するには `"DryRun" -> False` を明示します。
- `"PrivacyLevel" -> 0.75`
- `"WorkflowTemplateId" -> Automatic`

#### ClaudeWorkflowRouteFromPrompt

`ClaudeEval` の workflow 統合フロー全体をオーケストレーションします。既存の一意な route があればそれを使い、なければローカルの複雑プロンプト検出器を実行し、`WorkflowCandidate` と判定されたものだけが提案と WorkflowRouteDraft 作成へ進みます。

```mathematica
decision = ClaudeWorkflowRouteFromPrompt[
  "文書を要約し、要点を抽出し、レポートにまとめる"];
```

新規に生成された workflow は **つねに `NeedsApproval` で停止** し、ユーザーの承認なしに自動登録・自動実行されることはありません。

#### PromptWorkflow 拡張の注意事項

- LLM 提案コードは `ClaudeParseWorkflowNetCode` の非評価 parse を経るため、そのまま評価されることはありません。評価前に `ClaudeWorkflowCheckForbidden` が禁止パターンを静的検出します。
- 新規生成された workflow はつねに承認待ちで停止します。`ClaudeWorkflowRouteFromPrompt` / `ClaudeProposeWorkflowNetFromPrompt` は workflow を自動登録・自動実行しません。
- `ClaudeCreateWorkflowRouteDraft` の既定は `DryRun -> True` です。実際に draft を保存するには `"DryRun" -> False` を明示してください。
- `ClaudeWorkflowComplexPromptQ` は評価を伴わずローカルで動作するため、複雑プロンプト判定のためにプロンプトが外部送信されることはありません。
- API の詳細は `api_promptworkflow.md` を参照してください。

---
### 全体ワークフロー: 最小コード例

`example.md` の Part A の要点だけを 1 ブロックにまとめると以下のとおりです。

```wolfram
(* 1. ロード。
   ClaudeOrchestrator.wl をロードすると Workflow エンジンと
   Observability サブモジュール (checkPetriNetVertices /
   instrumentNetForObservation / plotPetriNetDetail /
   traceTransitions / showLLMCallLog ほか) は自動的に取り込まれる。
   petri_from_prompt.wl は example 段階のサンプルなので別途 Get する。
   実環境に合わせてパスを調整すること。 *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator.wl"}]]];
Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator_info",
  "docs", "examples", "petri_from_prompt.wl"}]];

(* 2. 自然文から提案 *)
goal = "3 方式 (Monte Carlo / Leibniz / Wallis) で π を計算して比較する";
proposal = proposePetriNet[goal];

(* 3. レビュー(任意) *)
reviewPetriProposal[goal]

(* 4. パース & 構造チェック *)
net = parsePetriCode[proposal["Code"]];
checkPetriNetVertices[net]

(* 5. 観測ラッパ装着 *)
clearLLMCallLog[]; clearObservedHandlerLog[];
observedNet = instrumentNetForObservation[net];

(* 6. 登録 & token 投入 *)
wid = ClaudeCreateWorkflowNet[observedNet];
ClaudeSubmitToken[wid,
  WorkflowToken["Payload" -> <|"NumSamples" -> 100000|>]];

(* 7. 実行 *)
runResult = ClaudeRunWorkflow[wid, "Async" -> False, "MaxSteps" -> 50];

(* 8. 観測 *)
plotPetriNetDetail[wid]                    (* Tooltip 付き構造図 *)
ClaudeWorkflowState[wid]                   (* token / marking 最終状態 *)
traceTransitions[wid, "Detail" -> True]    (* firing + LLM 統合トレース *)
showLLMCallLog[]                           (* LLM 呼び出し一覧 *)

(* 9. 保存 *)
snapshotDir = ClaudeSnapshotWorkflow[wid];
```

> **メモ:** `$petriObservabilityVersion` が未定義のままだったり、`checkPetriNetVertices` などの呼び出しが未評価式として残る場合は、`ClaudeOrchestrator_observability.wl` の自動ロードに失敗しています。`Get["ClaudeOrchestrator_observability.wl"]` を手動で実行するか、ファイルが `$Path` 上にあるか確認してください。

---

### 注意事項

- `proposePetriNet` は CLI 経由(`provider="claudecode"`、Pro/Max サブスクリプション内・課金なし)で LLM を呼びます。`"Providers" -> {"anthropic", "openai", ...}` で multi-provider モードに切り替える場合は NBAccess の課金 API 許可フラグが必要です。
- ネット内で `ClaudeCreateWorkflowNet` / `ClaudeSubmitToken` / `ClaudeRunWorkflow` 等を**呼ばないでください**。これらはネット**外側**の制御 API です。生成コード(handler 内)でこれらを呼ぶと禁止 API 検出に引っかかり、`parsePetriCode` が `$Failed` を返します。
- `$ClaudeOrchestratorDenyHeads` の制約はペトリネット経路でも適用されます。Transition 側の handler は `NotebookWrite` などを直接呼べません。最終出力は `"Done"` Place の Token Payload に集約し、`ClaudeWorkflowState` 経由で読み取ってください。
- `ClaudeRunWorkflow[wid, "Async" -> True]` を使うときは、必ず `ClaudeBeginParallelKernels[]` で別カーネルが起動済みであることを確認してください(`ClaudeOrchestrator.wl` のロード時に自動で呼ばれます)。
- Snapshot ディレクトリ容量は累積するので、定期的に古いものを掃除してください。`ClaudeListWorkflowSnapshots[]` で一覧、ディレクトリは普通の `DeleteDirectory` で削除できます。

---

## Real LLM 統合

テスト・開発時はモック動作しますが、本物の LLM エンドポイントに接続することもできます。

### ClaudeRealLLMAvailable

Real LLM 統合が設定済みかどうかを確認します。

**シグネチャ:**
```wolfram
ClaudeRealLLMAvailable[]
(* True / False *)
```

---

### ClaudeRealLLMQuery

設定済みのエンドポイントを使って prompt を実行します。

**シグネチャ:**
```wolfram
ClaudeRealLLMQuery[prompt]
(* 応答 String または $Failed *)
```

**使用例:**
```wolfram
$ClaudeOrchestratorRealLLMEndpoint = "ClaudeCode";
ClaudeRealLLMQuery["Wolfram Language で Hello World を書いてください"]
(* "Print[\"Hello World\"]" *)
```

---

### ClaudeRealLLMDiagnose

Real LLM 呼び出しを実行し、エンドポイント・CLIパス・終了コード・raw stdout・JSON パース可否などの診断情報を返します。呼び出し失敗時の切り分けに使います。

**シグネチャ:**
```wolfram
ClaudeRealLLMDiagnose[prompt]
```

**使用例:**
```wolfram
diag = ClaudeRealLLMDiagnose["test"];
diag["ExitCode"]    (* 0 *)
diag["JsonParsed"]  (* True / False *)
```

---

### ClaudeRealLLMDiagnosePlan

Real LLM planner パイプライン全体を実行し、プラン結果・raw LLM 応答・タスク数・ステータス・エラー情報を返します。プランニングフェーズの失敗切り分けに使います。

**シグネチャ:**
```wolfram
ClaudeRealLLMDiagnosePlan[input]
```

**使用例:**
```wolfram
pd = ClaudeRealLLMDiagnosePlan["ドキュメントを自動生成する"];
pd["TaskCount"]  (* 3 *)
pd["Status"]     (* "OK" / "Failed" *)
```

---

## グローバル設定変数

| 変数 | 既定値 | 説明 |
|---|---|---|
| `$ClaudeOrchestratorVersion` | (文字列) | パッケージバージョン |
| `$ClaudeOrchestratorRoles` | `{"Explore","Plan","Draft","Verify","Reduce","Commit"}` | 許容 Role 一覧 |
| `$ClaudeOrchestratorCapabilities` | `Association` | Role → Capability リスト |
| `$ClaudeOrchestratorDenyHeads` | `{NotebookWrite, CreateNotebook, ...}` | ワーカー禁止ヘッド一覧 |
| `$ClaudeOrchestratorRealLLMEndpoint` | `None` | Real LLM エンドポイント設定 |
| `$ClaudeOrchestratorCLICommand` | `Automatic` | CLI コマンド名/パス |
| `$ClaudeEvalAutoSkipKeywords` | (リスト) | Auto モードで Single パスにフォールバックさせる技術名・拡張子等 |
| `$ClaudeEvalAutoFactualEndings` | (リスト) | factual query を識別する語尾・フレーズ |
| `$ClaudeEvalAutoComplexMarkers` | (リスト) | Orchestrator 経路を強制する複雑タスクのマーカー |

### `$ClaudeOrchestratorRealLLMEndpoint` の設定値

| 値 | 動作 |
|---|---|
| `None` | Real LLM テストをスキップ(既定) |
| `"ClaudeCode"` | `ClaudeCode``ClaudeQueryBg`(同期版)を使用 |
| `"CLI"` | `claude` CLI を `RunProcess` 経由で呼び出す |
| `fn[prompt]` | カスタム関数を使用 |

環境変数 `CLAUDE_ORCH_REAL_LLM` でも opt-in できます。

### Auto ゲートのカスタマイズ

Auto モードで「短い factual query は Orchestrator を通さず Single パスに直送する」挙動を制御する 3 つのリストを公開しています。プロジェクト固有の用語が頻出する場合は、これらを拡張することで余計なオーケストレーション起動を抑えられます。

| 変数 | 用途 |
|---|---|
| `$ClaudeEvalAutoSkipKeywords` | パッケージ名・関数名・拡張子など、出現するだけで Single パスに渡したいキーワード |
| `$ClaudeEvalAutoFactualEndings` | 「を調べて」「を教えて」「check if」「compare」など、調査・質問型を示す語尾／フレーズ |
| `$ClaudeEvalAutoComplexMarkers` | 「スライド」「レポート」「プレゼン」「複数の成果物」など、必ず Orchestrator 経由にしたい複雑タスクのマーカー |

判定の概要:

- プロンプトが 300 文字未満かつ複雑さマーカーを含まず、`$ClaudeEvalAutoSkipKeywords` または `$ClaudeEvalAutoFactualEndings` のいずれかにヒットすれば Single パスへ。
- `$ClaudeEvalAutoComplexMarkers` がヒットした場合は、短いプロンプトでも Orchestrator 経路を通す。

```wolfram
(* プロジェクト固有の名称を Auto ゲートに登録 *)
AppendTo[$ClaudeEvalAutoSkipKeywords, "MyPackageName"];
AppendTo[$ClaudeEvalAutoComplexMarkers, "10ページ"];
```

---

## エラーと検証

### よくあるエラーと対処法

| 症状 | 原因 | 対処 |
|---|---|---|
| `ClaudeValidateTaskSpec` が `"Valid" -> False` を返す | TaskSpec に必須キーが不足している | `"Errors"` の内容を確認し、全必須キーを補完する |
| `SpawnResult["Status"] == "Partial"` | 一部ワーカーが失敗 | `SpawnResult["Failures"]` を確認し、該当タスクを再実行する |
| `CommitResult["Status"] == "RolledBack"` | Verifier が検証失敗 | `CommitResult["Details"]` を確認し、reduced artifact を修正する |
| `CommitResult["Diagnostics", "HeldExprFound"]` が `True` で書き込みが起きない | commit safety 経路が HeldExpr を検出して停止 | `"CommitRetryMax" -> N` で再試行、または `"DeterministicFallback" -> True` を確認 |
| `ClaudeRealLLMQuery` が `$Failed` を返す | エンドポイントの設定誤り | `ClaudeRealLLMDiagnose` で詳細を確認する |
| `ClaudeOrchestrationResult[jobId]` が `Missing` を返す | ジョブが未完了 | `ClaudeOrchestrationStatus[jobId]["Status"]` で進捗を確認する |
| 非同期ジョブが `"Failed"` 状態になる | バックグラウンド実行中のエラー | `ClaudeOrchestrationResult[jobId]["Failures"]` でエラー詳細を確認する |
| ChatGPT Codex 応答が `showLLMCallLog[]` に文字列として残らない | Codex が Association 形式で返している | `ClaudeOrchestrator_observability.wl` を再ロードして `ClaudeQueryBgLogged` の Association 対応を有効化(C-6 節参照) |
| `petri_from_prompt.wl` の `Get` が失敗する | `docs/examples/` パスが解決できていない | `$packageDirectory` 配下に `ClaudeOrchestrator/docs/examples/petri_from_prompt.wl` が存在するか確認する |

### TaskSpec の必須キー

`ClaudeValidateTaskSpec` は以下のキーをすべて要求します。

```wolfram
{"TaskId", "Role", "Goal", "Inputs", "Outputs",
 "Capabilities", "DependsOn", "ExpectedArtifactType", "OutputSchema"}
```

### 許容 Role

```wolfram
$ClaudeOrchestratorRoles
(* {"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"} *)