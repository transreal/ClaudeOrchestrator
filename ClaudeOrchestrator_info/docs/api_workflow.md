# ClaudeOrchestrator_workflow API リファレンス

Multi-token Petri net (MTP) workflow engine。`ClaudeOrchestrator``Workflow`` 名前空間。

## バージョン

### $WorkflowVersion
型: String
パッケージのバージョン文字列を返す。

## 型ビルダー

### WorkflowToken[opts]
immutable な token Association を生成する。
→ Association
Options: "TokenId" -> Automatic, "Kind" -> "Task" ("Task"|"Worker"|"Artifact"|"Approval"|"PackageTransaction"|"XSMSentinel"), "Payload" -> <||> (Association), "PrivacyLabel" -> 0.0 (Real), "ParentIds" -> {} (List), "CreatedBy" -> "" (String)

### WorkflowPlace[name, opts]
place Association を生成する。
→ Association
Options: "Capacity" -> Infinity, "Visibility" -> "Internal" ("Internal"|"UserVisible"), "AcceptedKinds" -> All (All | List), "Description" -> "" (String)

### WorkflowTransition[name, opts]
transition Association を生成する。
→ Association
Options: "InputArcs" -> {} (List of <|"Place"->...,"Multiplicity"->1,"TokenKind"->...|>), "OutputArcs" -> {} (同形式), "Guard" -> None (Function|None), "Executor" -> "PureFunction" ("ClaudeRuntime"|"PackageManager"|"PureFunction"|"External"), "RuntimeSpec" -> <||> (Association), "RetryPolicy" -> <||> (Association), "AccessPolicy" -> <||> (Association), "Timeout" -> None (Quantity|None), "Priority" -> 0 (Integer)

### WorkflowNet[opts]
WorkflowNet 全体 Association を生成する。
→ Association
Options: "WorkflowId" -> Automatic, "SourcePlace" -> 必須 (String), "FinalPlaces" -> {"Done"} (List), "Places" -> <||> (Association), "Transitions" -> <||> (Association), "InitialMarking" -> <||> (Association), "Description" -> "" (String), "ParentRuntime" -> Missing[] (String|Missing[])

## ワークフロー作成・投入

### ClaudeCreateWorkflowNet[spec_Association, opts]
WorkflowNet spec を validate し、WorkflowId を発行、内部 registry に登録する。実行はまだ開始しない。
→ String (WorkflowId)
Options: "ValidateStrict" -> True (validation エラーを Throw), "Description" -> "", "ParentRuntime" -> Missing[]

### ClaudeSubmitToken[wid, token, place:Automatic] → Association
token を WorkflowNet の指定 place に投入する (デフォルトは SourcePlace)。multi-source workflow で各 place を直接 seed できる。

### ClaudeSubmitInputs[wid, payload_Association, place:Automatic] → Association
payload を Kind="Task" の Token として SourcePlace (または指定 place) に投入する糖衣。
例: `ClaudeSubmitInputs[wid, <|"Text" -> text|>]`

### ClaudeBindAndSubmit[wid, vars__Symbol] / ClaudeBindAndSubmit[wid, varsList_List]
HoldRest。Global シンボル群の SymbolName と現在値から Payload Association を構築し、SourcePlace の Token として投入する。
→ Association
例:
```
text = "..."; ClaudeBindAndSubmit[wid, text]
(* Payload: <|"text" -> text の値|> *)

title = "..."; text = "...";
ClaudeBindAndSubmit[wid, title, text]
(* Payload: <|"title" -> ..., "text" -> ...|> *)

ClaudeBindAndSubmit[wid, {title, text}]
(* List 形式も HoldRest で同じ動作 *)
```
worker handler 側: `Lookup[binding[["Source", "Payload"]], "text", ""]`

### ClaudeApplyProposal[] / ClaudeApplyProposal[proposal_Association]
proposePetriNet が返す proposal の "Code" 文字列を ToExpression で評価し、"BuilderName" が指す builder 関数を定義する。
→ Symbol (BuilderName) | Null | $Failed
例:
```
proposal = proposePetriNet[goal];
builder  = ClaudeApplyProposal[proposal];
wid      = ClaudeCreateWorkflowNet[builder[]];
ClaudeBindAndSubmit[wid, text];
ClaudeRunWorkflow[wid, "Async" -> False]
```
引数なし版は Global`proposal を参照する。reviewPetriProposal の戻り値 (Column) は使えない。

## 状態照会

### ClaudeWorkflowStatus[wid] → Association
<|"Status", "CurrentMarking", "ElapsedSec"|> を返す。

### ClaudeWorkflowList[] → Dataset
登録済み全 WorkflowNet の wid と Status を返す。

### ClaudeWorkflowState[wid] → Association
<|"Tokens" -> <|tid -> tokenAssoc|>, "Marking" -> <|place -> {tids}|>, "Status", "WorkflowId"|>。token payload まで参照可能。

### ClaudeWorkflowTrace[wid] → List
{<|"Event", "Timestamp", ...|>, ...} 形式の実行 trace。

### ClaudeEnabledTransitions[wid] → List
現在 fire 可能な transition と binding の組合せを Priority 降順で返す。{<|"Name", "Binding" -> <|place -> token|>, "Priority"|>, ...}

## 実行

### ClaudeFireTransition[wid, transitionName, binding, opts]
1 transition を 1 binding で fire。NBAccess hard policy → guard → capability の順で検証。
→ <|"Status" -> "Fired"|"Blocked"|"NeedsApproval", "ConsumedTokens", "ProducedTokens", "ExecutorResult", "Marking"|>
Options: "ForceAllow" -> False (テスト用、NBAccess check をバイパス)

### ClaudeStepWorkflow[wid, opts] → Association
enabled transition から Priority 最優先の 1 つを fire。Stuck なら Status -> "Stuck"。

### ClaudeRunWorkflow[wid, opts]
sink 到達 / enabled が空 / MaxSteps 到達まで Step 反復。
→ Sync: <|"Status", "TerminationReason", "Steps", "ElapsedSec", "FinalMarking", "StepLog"|>
→ Async: <|"WorkflowId", "Status" -> "Async-Started", "PollKey", "StartTime"|>
Options: "Async" -> False (True で ClaudeCode`$iSharedPollingTask に寄生し非同期実行), "MaxSteps" -> 1000, "MaxWait" -> Quantity[600, "Seconds"], "ForceAllow" -> False

## 制御 (Pause / Resume / Cancel)

### ClaudePauseWorkflow[wid] → Association
Status を "Paused" にする。Pause 中は Step/Run が "Skipped" を返す。

### ClaudeResumeWorkflow[wid] → Association
"Paused" を "Running" に戻す。Paused でないときは何もせず現在 Status を返す。

### ClaudeCancelWorkflow[wid] → Association
Status を "Cancelled" にする。再開不可。Async 実行中にも効き polling task entry もクリーンアップ。

## 非同期 (Async)

### ClaudeWaitWorkflow[wid, opts]
async 起動した workflow が完了するまで block する。完了の定義: Status ∈ {Done, Cancelled, Stuck, Failed, NeedsApproval, Blocked, MaxStepsReached, Timeout}。Paused はそのまま待つ。
→ <|"WorkflowId", "Status" -> "Completed"|"WaitTimeout", "AsyncJob", "WorkflowStatus", "FinalMarking"|>
Options: "PollInterval" -> Quantity[0.5, "Seconds"], "MaxWait" -> Quantity[600, "Seconds"]

### ClaudeAsyncJobInfo[wid] → Association
async 実行中 / 完了直後の進捗情報。entry なしなら <|"Status" -> "NotFound", "WorkflowId"|>。
主キー: Status ("Running"|"Completed"), TerminationReason, StartTime, EndTime, Steps, MaxSteps, MaxWaitSec, StepLog, LastStepResult

### ClaudeCleanupAsyncJob[wid] → Association
async job entry を $iWorkflowAsyncJobs registry から削除、polling tick 登録も解除。
→ <|"Status" -> "Cleaned"|"NotFound", "WorkflowId"|>

## Awaiting LLM (非同期 callback handler)

### ClaudeCompleteHandlerOutput[wid, awaitId_String, output]
AwaitingLLM 状態の transition の output token を確定的に produce する。非同期 LLM 呼出しの callback から呼ぶ。
→ <|"Status" -> "Completed"|"Discarded"|"NotFound", "WorkflowId", "AwaitId", "TransitionName", "ProducedTokens", "Marking"|>

output 形式:
- `<|"Payload" -> <|...|>|>` (推奨)
- `<|... payload キー ...|>` ("Payload" ラップなし)

awaitId が見つからない場合 (Cancel 後の callback 遅延到着等) は $Failed をサイレント返却。

timeout 機構: transition.RuntimeSpec.AwaitingLLMTimeout または wf.DefaultAwaitingLLMTimeout 指定時、Awaiting 突入時に SessionSubmit[ScheduledTask] でタイマー仕込み。timeout 経過で自動発火し、Payload に `"_timeout" -> True`, `"_handler" -> transitionName` を付与。二重発火は silent discard (Trace に TransitionCallbackDiscarded)。

### ClaudeAwaitingTransitions[wid] → Dataset
現在 AwaitingLLM 状態の transition 一覧。各エントリ: <|"AwaitId", "TransitionName", "StartTime", "ElapsedSec", "ConsumedIds"|>。

### $ClaudeCurrentWid
型: String | Missing["NotInHandler"]
Awaiting handler 内で参照できる現在の WorkflowId。iExecutePureFunction が handler 評価中のみ Block で動的束縛。

### $ClaudeCurrentTransition
型: String | Missing["NotInHandler"]
Awaiting handler 内で参照できる現在の transition 名。

### $ClaudeCurrentAwaitId
型: String | Missing["NotInHandler"]
Awaiting handler 内で参照できる現在の await ID。ClaudeCompleteHandlerOutput に渡す。

### $ClaudeCurrentBinding
型: Association | Missing["NotInHandler"]
Awaiting handler 内で参照できる現在の binding Association。closure fallback 用。

## Completion hooks

### ClaudeRegisterCompletionHook[wid, fn]
workflow 完了時 (Sync は ClaudeRunWorkflow 戻り値直前、Async は iMarkAsyncCompleted 経由) に発火する hook を登録。fn は完了情報 Association を 1 引数で受ける。
→ <|"WorkflowId", "HookCount", "FiredImmediately"|>

fn 受信 Association: <|"WorkflowId", "Status", "TerminationReason", "Mode" -> "Sync"|"Async", "ElapsedSec", "Steps", "FinalMarking", "EndTime"|>

セマンティクス:
- 一回限り発火 (発火と同時に当該 wid の hooks 全消去)
- 例外は Quiet @ Check で捕捉、他 hook の発火を阻害しない
- 同じ wid に複数登録可、登録順に発火
- workflow が既完了なら登録時に即発火

### ClaudeUnregisterCompletionHooks[wid] → Association
wid に対する全 completion hook を削除。
→ <|"WorkflowId", "Removed" -> count|>

## Snapshot / Restore

### $ClaudeWorkflowSnapshotDir
型: String
初期値: `$ClaudeWorkingDirectory/workflow_snapshots`
ClaudeSnapshotWorkflow の既定保存親ディレクトリ。LLMGraphDAG 用の $ClaudeSnapshots とは別。

### ClaudeSnapshotWorkflow[wid, opts]
WorkflowNet を FormatVersion 2 でディレクトリ保存。保存内容: meta.wl + workflow.wl + llmgraph.wl + aux.wl。$iWorkflowAsyncJobs entry は含めない。
→ <|"WorkflowId", "SnapshotDir", "FormatVersion" -> 2, "SavedAt"|>
Options: "SnapshotDir" -> Automatic (= $ClaudeWorkflowSnapshotDir), "Description" -> ""

### ClaudeRestoreWorkflow[snapDir_String, opts]
ClaudeSnapshotWorkflow で保存された workflow を復元。FormatVersion 2 のみ対応。
→ <|"WorkflowId", "OriginalWid", "Restored" -> True, "FormatVersion", "SnapshotDir"|>
Options: "AsNewWorkflowId" -> True (新 wid 発行、元 wid は OriginalWid に保持)

AwaitingLLM エントリ: snapshot 時 Awaiting 状態だった transition は AwaitingLLMTransitions[awaitId] として復元されるが、元の callback closure と SessionSubmit タスクはカーネル再起動を跨げない。Restore は engine 側 timer を再仕掛けし、timeout 経過で自動的に ClaudeCompleteHandlerOutput を発火。fallback Payload に `"_timeout" -> True`, `"_handler" -> tname`, `"_restored" -> True` を付与。Timeout 解決順: `trans.RuntimeSpec.AwaitingLLMTimeout` > `wf.DefaultAwaitingLLMTimeout` > `$iRestoreFallbackTimeout` (デフォルト 0.1 秒)。

### ClaudeListWorkflowSnapshots[opts] → Dataset
$ClaudeWorkflowSnapshotDir 配下の snapshot 一覧。各エントリ: <|"SnapshotDir", "WorkflowId", "FormatVersion", "Description", "SavedAt"|>。
Options: "SnapshotDir" -> Automatic

## 関連パッケージ

- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) — phase API (DSL) から本 engine を呼び出す本体
- [claudecode](https://github.com/transreal/claudecode) — LLMGraphDAGCreate, $iSharedPollingTask 提供
- [NBAccess](https://github.com/transreal/NBAccess) — NBDirectiveDerivedPolicy (hard policy check)
- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — ClaudeRuntimeExecuteTransition adapter (Stage C)