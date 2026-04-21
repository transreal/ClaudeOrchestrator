# ClaudeOrchestrator API Reference

パッケージ: `ClaudeOrchestrator\``
GitHub: https://github.com/transreal/ClaudeOrchestrator
依存: [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime), [claudecode](https://github.com/transreal/claudecode)
ロード: `Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]`

## 定数・設定変数

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン文字列。

### $ClaudeOrchestratorRoles
型: List, 値: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`
許容 Role のリスト。TaskSpec の `"Role"` フィールドはここに含まれる値でなければならない。

### $ClaudeOrchestratorCapabilities
型: Association (Role -> Capability リスト)
各 Role で許可される Capability の対応表。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト。`NotebookWrite`, `CreateNotebook`, `EvaluationNotebook`, `RunProcess`, `SystemCredential` などを含む。

### $ClaudeOrchestratorRealLLMEndpoint
型: None | "ClaudeCode" | "CLI" | Function, 初期値: None
real LLM 統合の設定。`None` でスキップ、`"ClaudeCode"` で ClaudeCode バックエンド、`"CLI"` で claude CLI、任意関数も受け付ける。環境変数 `CLAUDE_ORCH_REAL_LLM` でも opt-in 可能。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode で使用する実行ファイル。`Automatic` は OS に応じて `"claude"` (Unix) / `"claude.cmd"` (Windows) を選択。環境変数 `CLAUDE_ORCH_CLI_PATH` で上書き可能。

### $ClaudeOrchestratorAsyncMode
型: True | False, 初期値: True
`True` (既定) で `$ClaudeEvalHook` が `ClaudeRunOrchestrationAsync` を使用。`False` で同期の `ClaudeRunOrchestration` に切り替わる。

## タスク計画

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...}|>`
Options: `Planner -> Automatic` (mock を使う。カスタム planner 関数も指定可), `MaxTasks -> 10`

例: `ClaudePlanTasks["input", Planner -> myPlannerFn, MaxTasks -> 5]`

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証する。戻り値: `<|"Valid" -> True/False, "Errors" -> {...}|>`

## Worker 実行・Artifact 収集

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し各タスクの artifact を収集する(直列または順次)。
→ `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: `WorkerAdapterBuilder -> Automatic` (Role -> TaskSpec を受け取り adapter を返す関数), `MaxParallelism -> 1` (Stage 2 以降で拡張予定)

### ClaudeCollectArtifacts[spawnResult] → Dataset
`spawnResult["Artifacts"]` を Dataset として返す。ノートブック上での確認に適した形式。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証する。戻り値: `<|"Valid" -> True/False, "Errors" -> {...}|>`

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物を返す。
→ `<|"ArtifactType" -> "Reduced", "Payload" -> ..., "Sources" -> ...|>`
Options: `Reducer -> Automatic` (artifacts を受け取り ReducedArtifact を返す関数)

## Commit

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し reducedArtifact を targetNotebook に反映する。committer の HeldExpr 内の `EvaluationNotebook[]` / `CreateNotebook[...]` 参照は targetNotebook に ReplaceAll で書き換えられる。
→ `<|"Status" -> "Committed"|"Failed"|"RolledBack", "Mode" -> ..., "Details" -> ...|>`
Options: `CommitterAdapterBuilder -> Automatic`, `CommitMode -> "Direct"` ("Transactional" は Stage 4 で shadow buffer に書いてから verify/flush し、失敗時は rollback), `Verifier -> Automatic` (fn[buffer, cells] -> True/False)

## フルパイプライン(同期)

### ClaudeRunOrchestration[input, opts]
Planning → Spawn → Reduce → (optional) Commit の全フェーズを直列実行する。
→ 4 フェーズの結果を束ねた Association
Options: `TargetNotebook -> None` (Commit するなら指定), `Planner -> Automatic`, `WorkerAdapterBuilder -> Automatic`, `Reducer -> Automatic`, `CommitterAdapterBuilder -> Automatic`, `MaxTasks -> 10`, `MaxParallelism -> 1`, `Confirm -> False`

## フルパイプライン(非同期)

### ClaudeRunOrchestrationAsync[input, opts]
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し orchJobId を即座に返す。フロントエンドをブロックしない。opts は `ClaudeRunOrchestration` と同じ。
→ orchJobId (String)

### ClaudeOrchestrationStatus[orchJobId] → Association
orchestration ジョブの現在状態を返す。戻り値例: `<|"Status" -> "Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase" -> ..., "ElapsedSecs" -> ..., "PlanJobId" -> ..., "SpawnJobId" -> ...|>`

### ClaudeOrchestrationResult[orchJobId] → Association | Missing
完了済み orchestration の最終結果(`ClaudeRunOrchestration` と同形の Association)を返す。未完了なら `Missing` を返す。

### ClaudeOrchestrationWait[orchJobId, timeoutSec]
orchestration 完了まで待機する。テスト・スクリプト専用。対話セルでの使用は避けること。既定タイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId]
実行中の DAG を中止しレジストリから除去する。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧を Dataset で返す。

## バッチ継続

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま batchInstructions 内の prompt を `ClaudeContinueTurn` で順次投入する。notebook 共有問題を回避する現実解(spec §17.1)。
→ `{<|"Index" -> i, "Prompt" -> ..., "Result" -> ...|>, ...}`
Options: `WaitBetween -> Quantity[1, "Seconds"]`

## real LLM ユーティリティ

### ClaudeRealLLMAvailable[] → True | False
`$ClaudeOrchestratorRealLLMEndpoint` および環境変数 `CLAUDE_ORCH_REAL_LLM` を確認し、real LLM 統合が設定されているか返す。

### ClaudeRealLLMQuery[prompt] → String | $Failed
設定済み real LLM エンドポイントを通じて prompt を実行する。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し、endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否を含む診断情報を返す。W1–W3 等の失敗切り分けに使用。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ、plan 結果・raw LLM 応答 head・task count・status・error 情報を返す。W1 の失敗切り分け用。