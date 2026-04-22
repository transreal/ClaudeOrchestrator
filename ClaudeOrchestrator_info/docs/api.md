# ClaudeOrchestrator API Reference

ClaudeOrchestrator は [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) の上に乗るマルチエージェント・オーケストレーション層だ。タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit を提供する。

依存: [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime), [claudecode](https://github.com/transreal/claudecode)

ロード:
```mathematica
Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]
```

## 定数・設定変数

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン。

### $ClaudeOrchestratorRoles
型: List
許容 Role のリスト: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`

### $ClaudeOrchestratorCapabilities
型: Association
Role → Capability リストの Association。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト。`NotebookWrite`, `CreateNotebook`, `EvaluationNotebook`, `RunProcess`, `SystemCredential` などを含む。

### $ClaudeOrchestratorRealLLMEndpoint
型: None | "ClaudeCode" | "CLI" | Function, 初期値: None
real LLM 統合テストのエンドポイント設定。`None` でスキップ。`"ClaudeCode"` は `ClaudeCode`ClaudeQueryBg` を使う。`"CLI"` は claude CLI を `RunProcess` で呼ぶ。関数を渡すとカスタム呼び出しになる。環境変数 `CLAUDE_ORCH_REAL_LLM` でも opt-in 可能。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI モードで起動する実行ファイル名またはフルパス。`Automatic` では OS に応じて `"claude"` (Unix) / `"claude.cmd"` (Windows) を使う。環境変数 `CLAUDE_ORCH_CLI_PATH` でも上書き可能。

### $ClaudeOrchestratorAsyncMode
型: True | False, 初期値: True
`True` (既定) で `$ClaudeEvalHook` が非同期経路 (`ClaudeRunOrchestrationAsync`) を使う。`False` にすると旧同期挙動に戻る。

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるためのテクニカルマーカーリスト (パッケージ名・関数名・拡張子等)。これらのトークンのいずれかがプロンプトに含まれ、かつタスクが 300 文字未満・複雑さ指標なしの場合、Orchestrator を通らず直接処理される。ユーザーはリストを拡張してプロジェクト固有の名称を追加できる。

### $ClaudeEvalAutoFactualEndings
型: List
Auto モードで Single フォールバックさせるための「調査・質問型」語尾・フレーズリスト。「を調べて」「を教えて」`check if`、`compare` 等を含む。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき「複雑タスク」を識別するためのマーカーリスト。スライド・レポート・プレゼン・複数の成果物要求などを含む。これらがプロンプトに現れると短いタスクでも Orchestrator 経路を通る。

## コア API

### ClaudePlanTasks[input, opts]
親タスク `input` を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...}|>`
Options: `Planner -> Automatic` (mock を使う。実関数を渡すと実 LLM planner になる), `MaxTasks -> 10`

例: `ClaudePlanTasks["データを集計してレポートを作成する", MaxTasks -> 5]`

### ClaudeValidateTaskSpec[taskSpec]
TaskSpec の妥当性を検証する。
→ `<|"Valid" -> True|False, "Errors" -> {...}|>`

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し、各タスクの artifact を収集する (直列または順次)。
→ `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: `WorkerAdapterBuilder -> Automatic` (Role → TaskSpec を受け取り adapter を返す関数), `MaxParallelism -> 1` (現状 1。Stage 2 以降で拡張)

### ClaudeCollectArtifacts[spawnResult]
`spawnResult["Artifacts"]` を Dataset として返す。
→ `Dataset`

### ClaudeValidateArtifact[artifact, outputSchema]
artifact の payload が OutputSchema を満たすか検証する。
→ `<|"Valid" -> True|False, "Errors" -> {...}|>`

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物を返す。
→ `<|"ArtifactType" -> "Reduced", "Payload" -> ..., "Sources" -> ...|>`
Options: `Reducer -> Automatic` (artifacts を受け取り ReducedArtifact を返す関数)

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し `reducedArtifact` を `targetNotebook` に反映する。committer の HeldExpr 内の `EvaluationNotebook[]` / `CreateNotebook[...]` 参照は `targetNotebook` に `ReplaceAll` で書き換えられる。`"Transactional"` モードでは shadow buffer に書いてから verify / flush し、失敗時は target notebook を無変更のまま rollback する (spec §12.3)。
→ `<|"Status" -> "Committed"|"Failed"|"RolledBack", "Mode" -> ..., "Details" -> ...|>`
Options: `CommitterAdapterBuilder -> Automatic`, `CommitMode -> "Direct"` (`"Transactional"` も選択可), `Verifier -> Automatic` (`fn[buffer, cells] -> True|False`)

### ClaudeRunOrchestration[input, opts]
Planning → Spawn → Reduce → (optional) Commit の全フェーズを直列に回す。
→ 4 フェーズの結果を束ねた Association
Options: `TargetNotebook -> None` (Commit するなら指定), `Planner -> Automatic`, `WorkerAdapterBuilder -> Automatic`, `Reducer -> Automatic`, `CommitterAdapterBuilder -> Automatic`, `MaxTasks -> 10`, `MaxParallelism -> 1`, `Confirm -> False`

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま `batchInstructions` に含まれる prompt を `ClaudeContinueTurn` で順次投入する。notebook 共有問題を回避する現実解 (spec §17.1)。
→ `{<|"Index" -> i, "Prompt" -> ..., "Result" -> ...|>, ...}`
Options: `WaitBetween -> Quantity[1, "Seconds"]`

## Real LLM ユーティリティ

### ClaudeRealLLMAvailable[]
→ `True|False`
`$ClaudeOrchestratorRealLLMEndpoint` および環境変数 `CLAUDE_ORCH_REAL_LLM` を確認し、real LLM 統合が設定済みかを返す。

### ClaudeRealLLMQuery[prompt]
→ `String | $Failed`
設定済みの real LLM エンドポイント経由で `prompt` を実行し、応答文字列を返す。

### ClaudeRealLLMDiagnose[prompt]
→ Association
real LLM 呼び出しを実行し、診断情報 (endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否) を返す。W1–W3 等が失敗した際の切り分けに使用する。

### ClaudeRealLLMDiagnosePlan[input]
→ Association
実 LLM planner パイプラインを走らせ、plan 結果・raw LLM 応答 head・task count・status・error 情報を返す。W1 の失敗切り分け用。

## 非同期オーケストレーション API

### ClaudeRunOrchestrationAsync[input, opts]
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し、`orchJobId` を即座に返す。フロントエンドをブロックしない。opts は `ClaudeRunOrchestration` と同じ。
→ `orchJobId` (String)

状態参照は `ClaudeOrchestrationStatus` / `ClaudeOrchestrationResult` を使う。

### ClaudeOrchestrationStatus[orchJobId]
→ `<|"Status" -> "Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase" -> ..., "ElapsedSecs" -> ..., "PlanJobId" -> ..., "SpawnJobId" -> ...|>`
orchestration ジョブの現在状態を返す。

### ClaudeOrchestrationResult[orchJobId]
→ Association | Missing
完了済み orchestration の最終結果 (`ClaudeRunOrchestration` と同形の Association) を返す。未完了なら `Missing` を返す。

### ClaudeOrchestrationWait[orchJobId, timeoutSec]
orchestration 完了まで待機する (テスト・スクリプト専用。対話セルでの使用は避ける)。既定タイムアウト 300 秒。
→ Association | $Failed

### ClaudeOrchestrationCancel[orchJobId]
実行中の DAG を中止しレジストリから除去する。
→ Association

### ClaudeOrchestrationJobs[]
現在追跡中の orchestration ジョブ一覧を返す。
→ `Dataset`