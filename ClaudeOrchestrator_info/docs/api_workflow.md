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
Options: "WorkflowId" -> Automatic, "SourcePlace" -> 必須 (String), "FinalPlaces" -> {"Done"} (List), "Places" -> <||> (Association), "Transitions" -> <||> (Association), "InitialMarking" -> <||> (Association), "Description" -> "" (String), "ParentRuntime" -> Missing[] (String|Missing[]), "DefaultAwaitingLLMTimeout" -> None (2026-05-17; NumericQ かつ > 0 のとき全 transition のデフォルト AwaitingLLM timeout 秒数。trans.RuntimeSpec.AwaitingLLMTimeout が優先)

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
Status を "Cancelled" にする。再開不可。Async 実行中にも効き polling task entry もクリーンアップする。

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

## External executor フック

外部 WolframScript ジョブ (Phase 4.A) との接続ポーリング関数とフック変数。実体は `ClaudeRuntime_externalrunner.wl` が `ClaudeWireExternalRunner[]` 経由で差し込む。

### ClaudeExternalJobPollTick[] → Association
`AwaitingLLMTransitions` に登録された External WolframScript job を走査し、status を読んで完了/失敗/timeout を処理する。Completed → `ClaudeCompleteHandlerOutput` で output ref token を produce (slot も OutputArc 経由で返却)。Failed/Expired → `RetryPolicy` に従い再起動または terminal failure。Running → no-op。timeout は poller が単独所有 (External では `AwaitingLLMTimeout` を使わない: v7 C1)。
返り値: `<|"Polled"->_Integer, "Results"->{...}|>`

### $ClaudeExternalJobLauncher
型: Function | Automatic, 初期値: Automatic (未設定 Failure)
External job を起動する関数フック。`fn[jobSpec] → <|"Status"->"Launched"|"Failed", "JobID", "JobDir", "PID", "Reason"|>`。`ClaudeRuntime_externalrunner.wl` が `ClaudeWireExternalRunner[]` で差し込む。テストで mock 注入可。

### $ClaudeExternalJobStatusReader
型: Function | Automatic, 初期値: Automatic (JobDir/status.json 読み、無ければ Running)
External job の status を読む関数フック。`fn[awaitMeta] → <|"Status"->"Running"|"Completed"|"Failed", "OutputRef", "SourceVaultRef", "SummaryRef", "ErrorRef"|>`。テストで mock 注入可。

### $ClaudeExternalJobKiller
型: Function | Automatic, 初期値: Automatic (best-effort no-op、Phase 4 で実装)
External job を強制終了する関数フック。`fn[awaitMeta]`。pid.json 同一性確認後に kill。テストで mock 注入可。

### $ClaudeExternalCompletionHook
型: Function | None, 初期値: None
External job 完了後に呼ばれる注入点。`fn[<|"WorkflowId","AwaitId","AwaitMeta","Status"|>]`。live 統合 (Notebook 反映 final action enqueue) のため `ClaudeRuntime_externalrunner.wl` 側が設定する。workflow 本体は疎結合のまま。

### $ClaudeExternalBackends
型: Association, 初期値: <||>
External job backend 別の launcher/status reader/killer registry (`<|backend -> <|"Launcher","StatusReader","Killer"|>|>`)。空 (未登録) のとき External executor は既存 WolframScript singleton フック ($ClaudeExternalJobLauncher 等) と完全に同一挙動になる (純加法)。ComfyUI など非 WolframScript backend を共存させるために使う。

### ClaudeRegisterExternalBackend[name_String, spec_Association] → Association
External executor へ backend を登録する。spec は `<|"Launcher"->fn[jobSpec], "StatusReader"->fn[awaitMeta], "Killer"->fn[awaitMeta]|>` の一部または全部。jobSpec/awaitMeta の "Backend" がこの name に一致する job だけがこの backend に dispatch され、未登録 backend は既存 WolframScript フックへフォールバックする。
→ <|"Status"->"Registered", "Backend"->name, "Roles"->{...}|>

### ClaudeExternalBackends[] → List
登録済み External backend 名のリストを返す。

## Subkernel executor フック

サブカーネル並列実行 (`ParallelSubmit` 経由) との接続フック。`AwaitKind=SubkernelTask` の transition を走査・完了処理する。

### ClaudeSubkernelPollTick[] → _
`AwaitingLLMTransitions` の Subkernel job (`AwaitKind=SubkernelTask`) を走査し、future の非ブロッキング完了判定を行い、完了時に `ClaudeCompleteHandlerOutput` で結果を produce (slot は OutputArc で返却)。巨大結果 (`$ClaudeSubkernelResultInlineLimit` 超) は inline せず summary 化。

### $ClaudeSubkernelSubmit
型: Function | Automatic, 初期値: Automatic
Subkernel executor の submit 関数。`fn[HoldComplete[expr], accessSpec] → <|"Handle"->_|> | None`。`Automatic` は `ParallelSubmit[NBExecuteHeldExprSubkernelRaw[...]]` (kernel/関数が利用可能なとき)。テストで mock 注入可。

### $ClaudeSubkernelPoll
型: Function | Automatic, 初期値: Automatic
Subkernel job の非ブロッキング完了判定。`fn[handle] → <|"Done"->_, "Result"->_|>`。`Automatic` は future の非ブロッキング poll。テストで mock 注入可。

### $ClaudeSubkernelResultInlineLimit
型: Integer, 初期値: 65536 (64KB)
subkernel 結果を token payload に inline できる `ByteCount` 上限。超過時は summary 化。

## External held expr job 投入

### ClaudeSubmitExternalHeldExprJob[HoldComplete[expr], opts] → Association
承認済みの held expression を External executor (WolframScript ジョブ) へ 1 遷移 WorkflowNet として投入する (2026-06-12)。内部で 1 遷移 WorkflowNet を作成し `$ClaudeExternalJobLauncher` 経由で起動する。`ClaudeRuntime_externalrunner.wl` の `"ApprovedHeldExpr"` ハンドラと連携。
Options:
- `"Handler" -> "ApprovedHeldExpr"`
- `"Timeout" -> 3600`
- `"BootstrapFiles" -> {}` (子プロセスで先行ロードするパッケージリスト)
- `"NotifyNotebook" -> None` (完了 summary の書込先 NotebookObject)
- `"AccessSpec" -> Automatic` (Automatic = WolframScriptTask role)
- `"MaxRetries" -> 0`

返り値 (成功): `<|"Status"->"Submitted", "JobID", "JobDir", "WorkflowId", "Head"|>`
返り値 (失敗): `<|"Status"->"Failed", "Reason"|>`

## StateGraph Shim 互換層

旧 `LLMStateGraph*` / `RunStateGraph` API を WorkflowNet engine 経由で動作させる forwarding 層 (Stage C-1, 2026-05-06)。新規コードは WorkflowNet API を直接使い、この shim を経由しないこと。

### $UseLegacyStategraph
型: Boolean, 初期値: False
`False` (既定) なら新実装 (`ClaudeOrchestrator`Workflow`` 経由)、`True` なら legacy stategraph 実装を使う。旧名 `$UseWorkflowShim` とは逆の意味 (`$UseLegacyStategraph = !$UseWorkflowShim`)。Stage D で削除予定。

### $UseWorkflowShim
`$UseLegacyStategraph` の旧名 (deprecated alias)。意味が逆になるため新規コードでは使わないこと。

### $WorkflowShimVersion
型: String
shim 互換層のバージョン文字列。

### ClaudeWorkflowFromStateGraph[graph] → Association
LLMStateGraph 形式の `graph` (Nodes/Edges/InitialNode/TerminalNodes) を WorkflowNet 構造に変換して返す (登録はしない)。対応 Node 型: Stage / Compute / Decision / Terminal / ParallelSubgraph。制約: nodeId に `"__"` (二重 underscore) を含めないこと。

### ClaudeCreateWorkflowFromStateGraph[graph, opts] → String (WorkflowId)
`ClaudeWorkflowFromStateGraph` + `ClaudeCreateWorkflowNet` を一括実行して WorkflowId を返す。Options: `"Description"->""`, `"ValidateStrict"->True`。

### ShimLLMStateGraphCreate[graph, opts] → String (sgRid)
`LLMStateGraphCreate` と等価。WorkflowNet を生成・登録し XSMSentinel token 投入後、`"sg-"` 接頭辞の runtimeId を返す。Options: `"InitialContext"-><||>`, `"MaxTotalIterations"->30`

### ShimLLMStateGraphStatus[sgRid] → Association
`LLMStateGraphStatus` と等価。返り値キー: RuntimeId / Status / CurrentNode / TotalIterations / MaxTotalIterations / Path / ActiveSubDAGId / FailureReason / StartTime / EndTime / ElapsedSec

### ShimLLMStateGraphState[sgRid] → Association
`LLMStateGraphState` と等価。GlobalState Association を返す (Stages[nodeId][Output] 構造も含む)。

### ShimLLMStateGraphCancel[sgRid] → sgRid
`LLMStateGraphCancel` と等価。`ClaudeCancelWorkflow` 経由でキャンセル。

### ShimLLMStateGraphList[] → List
`LLMStateGraphList` と等価。`ShimLLMStateGraphCreate` で登録された全 sgRid を返す。

### ShimLLMStateGraphTrace[sgRid] → List
`LLMStateGraphTrace` と等価。`ClaudeWorkflowTrace` の TransitionFired event を stategraph 形式 (NodeProcessed / DecisionMade / ParallelStarted / ParallelJoined / EdgeFired) に変換して返す。先頭に GraphCreated event を付加。

### ShimLLMStateGraphRecordHistory[sgRid] → Association
`LLMStateGraphRecordHistory` と等価。状態と trace を集約した Association を返す。返り値キー: RuntimeId, WorkflowId, Status, Path, Stages, Trace, TraceEventCount, Recorded, RecordedAt。

### ShimRunStateGraph[graph, opts] → Association (Sync) | sgRid (Async)
`RunStateGraph` と等価。`Async->False` (既定) は完了まで block して結果 Association を返す。`Async->True` は sgRid を即返却。OnGraphComplete callback は Sync/Async 両モードで発火。
Options: `"Async"->False`, `"MaxTotalIterations"->30`, `"MaxWait"->600`, `"PollInterval"->0.5`, `"Profile"->"Generic"`, `"Notebook"->Automatic`, `"InitialContext"-><||>`, `"OnGraphComplete"->None`, `"Description"->""`
Sync 返り値: `<|"RuntimeId", "Status", "GlobalState", "Path", "ElapsedSec", "FailureReason", "Trace", "WorkflowId", "WorkflowResult"|>`

### ShimLLMStateGraphSnapshot[sgRid, opts] → Association
`LLMStateGraphSnapshot` と等価。`ClaudeSnapshotWorkflow` 経由で FormatVersion 2 保存。Options: `"SnapshotDir"->Automatic`, `"Description"->""`
返り値: `<|"RuntimeId", "WorkflowId", "SnapshotDir", "FormatVersion"->2, "SavedAt"|>`

### ShimLLMStateGraphRestore[snapDir, opts] → Association
`LLMStateGraphRestore` と等価。`ClaudeRestoreWorkflow` 経由で v2 復元。v1 ディレクトリは $Failed (Throw)。Options: `"AsNewWorkflowId"->True`
返り値: `<|"RuntimeId", "WorkflowId", "OriginalWid", "OriginalRuntimeId", "Restored"->True, "FormatVersion"->2, "SnapshotDir"|>`

### ShimLLMStateGraphListSnapshots[opts] → Dataset
`LLMStateGraphListSnapshots` と等価。`$ClaudeWorkflowSnapshotDir` 配下の v2 snapshot を列挙 (stategraph v1 ディレクトリは対象外)。Options: `"SnapshotDir"->Automatic`

## 関連パッケージ

- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) — phase API (DSL) から本 engine を呼び出す本体
- [claudecode](https://github.com/transreal/claudecode) — LLMGraphDAGCreate, $iSharedPollingTask 提供
- [NBAccess](https://github.com/transreal/NBAccess) — NBDirectiveDerivedPolicy (hard policy check)
- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — ClaudeRuntimeExecuteTransition adapter (Stage C)