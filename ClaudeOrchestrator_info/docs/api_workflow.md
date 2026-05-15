# ClaudeOrchestrator_workflow API リファレンス

真の multi-token Petri net (MTP) workflow engine。`ClaudeOrchestrator`Workflow`` 名前空間。

## 変数

### $WorkflowVersion
型: String
パッケージのバージョン文字列。

### $ClaudeWorkflowSnapshotDir
型: String, 初期値: `$ClaudeWorkingDirectory/workflow_snapshots`
`ClaudeSnapshotWorkflow` の既定 snapshot 親ディレクトリ。

## 型ビルダー

### WorkflowToken[opts]
immutable な token Association を生成する。
→ Association
Options: "TokenId" -> Automatic, "Kind" -> _ ("Task"|"Worker"|"Artifact"|"Approval"|"PackageTransaction"|"XSMSentinel"), "Payload" -> <||>, "PrivacyLabel" -> 0.0, "ParentIds" -> {}, "CreatedBy" -> ""

### WorkflowPlace[name, opts]
place Association を生成する。
→ Association
Options: "Capacity" -> Infinity, "Visibility" -> "Internal" ("Internal"|"UserVisible"), "AcceptedKinds" -> All (All|List), "Description" -> ""

### WorkflowTransition[name, opts]
transition Association を生成する。
→ Association
Options: "InputArcs" -> {} (List of `<|"Place"->...,"Multiplicity"->1,"TokenKind"->...|>`), "OutputArcs" -> {} (同形式), "Guard" -> None (Function|None), "Executor" -> _ ("ClaudeRuntime"|"PackageManager"|"PureFunction"|"External"), "RuntimeSpec" -> <||>, "RetryPolicy" -> <||>, "AccessPolicy" -> <||>, "Timeout" -> None (Quantity|None), "Priority" -> 0

### WorkflowNet[opts]
WorkflowNet 全体 Association を生成する。
→ Association
Options: "WorkflowId" -> Automatic, "SourcePlace" -> _ (必須, String), "FinalPlaces" -> {"Done"}, "Places" -> <||>, "Transitions" -> <||>, "InitialMarking" -> <||>, "Description" -> "", "ParentRuntime" -> Missing[]

## WorkflowNet 登録・投入

### ClaudeCreateWorkflowNet[spec, opts]
WorkflowNet spec を validate し WorkflowId を発行、内部 registry に登録する。実行は開始しない。
→ String (WorkflowId)
Options: "ValidateStrict" -> True (validation エラーを Throw), "Description" -> "", "ParentRuntime" -> Missing[]

### ClaudeSubmitToken[wid, token, place:Automatic] → Association
token を WorkflowNet の指定 place に投入する。place を省略すると SourcePlace に投入。token は immutable、後続 transition で consume+produce される。

## 状態参照

### ClaudeWorkflowStatus[wid] → Association
現在の状態を返す: `<|"Status", "CurrentMarking", "ElapsedSec"|>`。

### ClaudeWorkflowList[] → Dataset
登録済み全 WorkflowNet の wid と Status を Dataset で返す。

### ClaudeWorkflowState[wid] → Association
全体状態を返す: `<|"Tokens" -> <|tid -> tokenAssoc, ...|>, "Marking" -> <|placeName -> {tids}, ...|>, "Status", "WorkflowId"|>`。token payload まで参照可能。

### ClaudeWorkflowTrace[wid] → List
実行 trace event のリストを返す: `{<|"Event", "Timestamp", ...|>, ...}`。

### ClaudeEnabledTransitions[wid] → List
現在 fire 可能な transition と binding の組合せを Priority 降順で返す: `{<|"Name" -> ..., "Binding" -> <|place -> token|>, "Priority" -> n|>, ...}`。

## 実行制御

### ClaudeFireTransition[wid, transitionName, binding, opts]
1 transition を 1 binding で fire する。NBAccess hard policy check → guard → capability の順で検証。
→ `<|"Status" -> "Fired"|"Blocked"|"NeedsApproval", "ConsumedTokens" -> {tids}, "ProducedTokens" -> {tids}, "ExecutorResult" -> ..., "Marking" -> <|...|>|>`
Options: "ForceAllow" -> False (テスト用、NBAccess check をバイパス)

### ClaudeStepWorkflow[wid, opts]
enabled transition から Priority 最優先の 1 つを選んで fire する。
→ Association (enabled が無ければ Status -> "Stuck")
Options: "ForceAllow" -> False

### ClaudeRunWorkflow[wid, opts]
sink 到達 / enabled 空 / MaxSteps 到達まで Step を反復する。
→ Sync: `<|"Status", "TerminationReason", "Steps", "ElapsedSec", "FinalMarking", "StepLog"|>` / Async: `<|"WorkflowId", "Status" -> "Async-Started", "PollKey", "StartTime"|>`
Options: "Async" -> False (True なら `ClaudeCode``$iSharedPollingTask` に寄生して非同期実行、即座に WorkflowId を返す), "MaxSteps" -> 1000, "MaxWait" -> Quantity[600, "Seconds"], "ForceAllow" -> False
例: `ClaudeRunWorkflow[wid, "Async" -> True, "MaxSteps" -> 200]`

### ClaudePauseWorkflow[wid] → Association
Status を "Paused" に。Pause 中は Step/Run が "Skipped" を返す。

### ClaudeResumeWorkflow[wid] → Association
"Paused" を "Running" に戻す。Pause でなければ何もせず現在 Status を返す。

### ClaudeCancelWorkflow[wid] → Association
Status を "Cancelled" に。再開不可。Async 実行中の polling task entry もクリーンアップする。

## 非同期実行

### ClaudeWaitWorkflow[wid, opts]
async 起動した workflow が完了するまで block する。完了 = `Status ∈ {Done, Cancelled, Stuck, Failed, NeedsApproval, Blocked, MaxStepsReached, Timeout}`。Paused はそのまま待つ。
→ `<|"WorkflowId", "Status" -> "Completed"|"WaitTimeout", "AsyncJob" -> ..., "WorkflowStatus" -> ..., "FinalMarking" -> ...|>`
Options: "PollInterval" -> Quantity[0.5, "Seconds"], "MaxWait" -> Quantity[600, "Seconds"]

### ClaudeAsyncJobInfo[wid] → Association
async 実行中/完了直後の進捗情報を返す。entry が無ければ `<|"Status" -> "NotFound", "WorkflowId" -> wid|>`。
主キー: Status ("Running"|"Completed"), TerminationReason, StartTime, EndTime, Steps, MaxSteps, MaxWaitSec, StepLog, LastStepResult。

### ClaudeCleanupAsyncJob[wid] → Association
async job entry を `$iWorkflowAsyncJobs` registry から削除し、polling tick 登録も解除する手動 GC API。
→ `<|"Status" -> "Cleaned"|"NotFound", "WorkflowId" -> wid|>`

## Completion hooks

### ClaudeRegisterCompletionHook[wid, fn]
workflow 完了時 (Sync は `ClaudeRunWorkflow` 戻り値直前、Async は `iMarkAsyncCompleted` 経由) に発火する hook を登録する。`fn` は完了情報 Association を 1 引数で受ける。
→ `<|"WorkflowId", "HookCount", "FiredImmediately"|>`
fn 受け取り Association: `<|"WorkflowId", "Status", "TerminationReason", "Mode" -> "Sync"|"Async", "ElapsedSec", "Steps", "FinalMarking", "EndTime"|>`
セマンティクス: 一回限り発火 (発火と同時に当該 wid の hooks 全消去)、例外は `Quiet@Check` で捕捉して他 hook を阻害しない、同一 wid に複数登録可能で登録順に発火、既に完了済みなら登録時に即発火。
例: `ClaudeRegisterCompletionHook[wid, Function[info, Print[info["Status"]]]]`

### ClaudeUnregisterCompletionHooks[wid] → Association
wid に対する全 completion hook を削除する。
→ `<|"WorkflowId", "Removed" -> count|>`

## Snapshot / Restore

### ClaudeSnapshotWorkflow[wid, opts]
WorkflowNet を FormatVersion 2 でディレクトリに保存する。保存内容: meta.wl + workflow.wl + llmgraph.wl (Day 4b では空) + aux.wl (Day 4b では空)。`$iWorkflowAsyncJobs` entry は含めない (restore 後は再度 `ClaudeRunWorkflow` で起動)。
→ `<|"WorkflowId", "SnapshotDir", "FormatVersion" -> 2, "SavedAt"|>`
Options: "SnapshotDir" -> Automatic (= `$ClaudeWorkflowSnapshotDir`), "Description" -> ""

### ClaudeRestoreWorkflow[snapDir, opts]
保存された workflow を復元する。FormatVersion 2 のみ対応。
→ `<|"WorkflowId", "OriginalWid", "Restored" -> True, "FormatVersion", "SnapshotDir"|>`
Options: "AsNewWorkflowId" -> True (新しい wid を発行、元 wid は OriginalWid に保持)

### ClaudeListWorkflowSnapshots[opts] → Dataset
`$ClaudeWorkflowSnapshotDir` 配下の snapshot 一覧。各エントリ: `<|"SnapshotDir", "WorkflowId", "FormatVersion", "Description", "SavedAt"|>`。
Options: "SnapshotDir" -> Automatic

## 依存パッケージ

- [claudecode](https://github.com/transreal/claudecode) — `LLMGraphDAGCreate`, `$iSharedPollingTask`, `ClaudeRegisterPollingTick` / `ClaudeUnregisterPollingTick`
- [NBAccess](https://github.com/transreal/NBAccess) — `NBDirectiveDerivedPolicy` (hard policy check)
- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — `ClaudeRuntimeExecuteTransition` (Stage C 予定)
- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) — phase API (DSL) から本 engine を呼び出す上位パッケージ