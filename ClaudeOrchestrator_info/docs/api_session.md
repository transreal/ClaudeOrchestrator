# ClaudeOrchestrator_session API リファレンス

## 概要
`ClaudeOrchestrator`Session`` 名前空間。RuntimeSession episode 層の実装
(仕様: ClaudeOrchestrator_info/design/claude_orchestrator_runtime_session_episode_petri_spec_v0_1.md)。

依存規則 (§22): `ClaudeOrchestrator_session` は `ClaudeOrchestrator_workflow` に依存する。ロード順は workflow → session。`ClaudeRuntime` には依存しない (public backend spec のみ将来受け取る)。

現行スコープは Inc1 + Inc2 + Inc3 + Inc0 + Inc8 + IncC (conductor v0.2 の episode 層 primitive、§17 artifact validation/commit、§20/§21 TaskSpec 統合を含む)。

- Inc1: schema validator (fail-closed)、canonical hash (§7.9)、ID generator、SyntheticControlEvent (§7.7/§11.2.1)、RuntimeSession backend registry (§8.1)、MockRuntimeSession backend
- Inc2 (§9/§10): episode supervisor net builder、pairing Guard (§9.4)、StartEpisode executor、event bridge lite (`ClaudeRuntimeSessionPumpOnce`)、ActiveSessionEpisodes registry (§10.5)、watchdog 用 SyntheticControlEvent 注入 API
- Inc3 (§11): durable inbox/outbox spool、poll tick、outbox dispatch、recovery scan
- Inc8 (§17): ArtifactCandidate 検証、single commit の CommitReceipt 取得
- IncC (§20/§21): multi-agent TaskSpec role → conductor role 正規化、heterogeneous backend 選択、TaskNodeSpec → episode net compile、episode 終端まで駆動する driver、DAG plan runner、reuse-aware chain runner
- Inc0 (conductor v0.2 §13.2/§16.4/§19.3/§25.3): InferenceTrustDomain 解決、trust gate、CallContext、call ledger

バージョン: v0.2 (Inc1+Inc2+Inc3+Inc0+Inc8+IncC, 2026-07-11)

## canonical hash (§7.9)

### ClaudeSessionCanonicalize[expr] → Association|expr
hash 用 canonical form を返す。全階層で Association を KeySort し、DateObject を epoch ms へ正規化する。List の順序は保存する (set semantics の field は schema 側で事前 Sort)。

### ClaudeSessionCanonicalHash[expr] → String (64桁hex)
canonical form の WXF bytes に対する SHA256。key 順・timezone 表示に依存しない。

### ClaudeSessionObjectHash[obj, hashField] → String
obj から hashField と transport 系 field を除いた canonical hash (§7.9 手順1)。

### ClaudeSessionEventHash[event] → String
SessionControlEvent の EventHash を計算する。

### ClaudeSessionCommandHash[command] → String
SessionCommand の CommandHash を計算する。

### ClaudeSessionGrantHash[grant] → String
BudgetGrant の GrantHash を計算する。

### ClaudeSessionAccessSpecHash[accessSpec] → String
AccessSpec の canonical hash (Inc1 新設)。set semantics の field (AllowedDirectories 等) は Sort してから hash するため列挙順に依存しない。

### ClaudeSessionVerifyEventHash[event] → True|False
EventHash field が再計算値と一致すれば True。欠落・不一致は False (fail-closed)。

### ClaudeSessionVerifyCommandHash[command] → True|False
CommandHash field が再計算値と一致すれば True。

### ClaudeSessionVerifyStartSpecHashes[startSpec] → Association
AccessSpecHash と GrantHash が中身の再計算値と一致するか検査し `<|Valid, Errors|>` を返す。

## ID generator

### ClaudeSessionNewId[kind] → String
kind に応じた prefix 付き一意 ID。kind: "Session"|"Episode"|"Command"|"StartCommand"|"Event"|"Lease"|"Artifact"|"Checkpoint"|"ToolCall"|"BackendInstance"。

### ClaudeSessionEventTokenId[event] → String
SessionEvent token の決定論 ID (§10.3)。Source==Runtime は (EpisodeId, Attempt, EventSeq, EventHash)、synthetic は (EpisodeId, Attempt, Source, EventId, EventHash) から生成し、名前空間 prefix (sevt-/ssyn-) で衝突を防ぐ。

## schema validator (§7)

### ClaudeSessionValidate[schema, obj] → Association
obj を schema に対して fail-closed に検証し `<|"Valid"->True|False, "Schema"->schema, "Errors"->{...}|>` を返す。schema: "SessionStartSpec"|"EnvironmentSpec"|"BudgetGrant"|"BudgetSnapshot"|"CheckpointPolicy"|"RuntimeCheckpointManifest"|"ArtifactContract"|"ArtifactCandidate"|"SessionControlEvent"|"SessionCommand"|"EventCursor"。

### ClaudeSessionValidateEventBatch[events, cursor] → Association
PollEvents で得た Runtime event 列を cursor (`<|Attempt, EventSeq|>`) に対して検証する。schema/hash/Attempt/EventSeq 連番を fail-closed で検査し、最初の違反で停止して `<|Valid, Errors, NextCursor|>` を返す (gap は適用しない §11.2)。

## backend registry (§8.1)

### ClaudeRegisterRuntimeSessionBackend[name, backend] → backend|Failure
RuntimeSession backend (ProtocolVersion/Capabilities/StartEpisode/PollEvents/SendCommand/Inspect/Recover/Dispose) を検証して登録する。protocol 違反は Failure。

### ClaudeUnregisterRuntimeSessionBackend[name]
登録済み backend を除去する。

### ClaudeRuntimeSessionBackends[] → {name...}
登録済み backend 名の一覧。

### ClaudeRuntimeSessionBackendInfo[name] → Association
backend の Function 本体を含まない info (ProtocolVersion/Capabilities/ContractFns)。

## MockRuntimeSession backend

### ClaudeMockRuntimeSessionBackendSpec[opts] → Association
決定論 event script を返す mock backend Association を生成する。`ClaudeRegisterRuntimeSessionBackend` に渡して使う。
Options: "EventScript" -> Automatic (template は `<|"Type"->.., "PayloadRefs"->.., "BudgetSnapshot"->.., "PrivacyLabel"->..|>` の部分指定。EventSeq/ID/hash は自動付与), "AckEvents" -> True (command 受理時に CommandAccepted event を追加), "TerminalOnCancel" -> True (Cancel 受理時に Cancelled event を追加), "FailStart" -> False (StartEpisode を常に Failed にする), "ValidateEvents" -> True (materialize した event を schema 検証)
契約 (Inc1 での近似): mock の「emit 済み tip」は PollEvents で取得済みの最大 EventSeq とし、SendCommand の ExpectedAfterEventSeq はこれと照合する。Cancel は seq 照合を免除 (Attempt 不一致は常に Rejected(StaleAttempt))。

### ClaudeMockRuntimeSessionReset[]
mock backend の内部状態 (全 handle / start 冪等 index) をクリアする。テスト用。

### ClaudeSessionStartSpecTemplate[opts] → Association (SessionStartSpec)
schema 検証を通る最小の SessionStartSpec を生成する (AccessSpecHash / GrantHash は自動計算)。
Options: "WorkflowId"/"TaskId"/"SessionId"/"EpisodeId"/"StartCommandId" -> Automatic (自動発行), "Attempt" -> 1, "Backend" -> "MockRuntimeSession", "PrivacyLabel" -> 1.0, "GoalRef" -> "mock-goal", "ReusePolicy" -> "Never"
テストと Inc2 用。

## episode supervisor net (Inc2, §9/§10)

### ClaudeCreateRuntimeSessionEpisodeNet[startSpec, opts] → Association
§9 の episode supervisor net (単一 EpisodeActive place + ControlState、event × ControlState 到達性行列) を生成し、slot/Task token を投入して `<|WorkflowId, EpisodeId, SessionId, Backend|>` を返す。startSpec は schema/hash 検証を fail-closed で通過する必要がある。
Options: "SessionSlots" -> 1, "EnvironmentSlots" -> 1, "Validate" -> True

### ClaudeStartRuntimeSessionEpisode[wid] → workflow state
enabled transition が尽きるまで step し (Allocate → StartEpisode)、episode を Running まで進める。

### ClaudeRuntimeSessionPumpOnce[wid, episodeId] → Association
backend を poll し、未適用の control event を一個だけ SessionEvents place へ投入する (§11.2)。schema/hash 違反は quarantine。戻り Status: Deposited|Duplicate|NoNewEvents|NoActiveLease|Quarantined 等。適用は `ClaudeStepWorkflow` が行う。

### ClaudeRuntimeSessionCancel[wid, episodeId, reason]
Cancel command request を投入する。全 non-terminal ControlState から受理される (I13)。

### ClaudeRuntimeSessionProvideObservation[wid, episodeId, observationRef]
AwaitingObservation の episode へ ProvideObservation command request を投入する。

### ClaudeRuntimeSessionInjectSyntheticTerminal[wid, episodeId, type, evidenceRef]
watchdog/recovery 用の SyntheticControlEvent (Source=OrchestratorWatchdog、type は Failed|Cancelled|EnvironmentLost) を生成・検証して SessionEvents へ投入する (§11.2.1)。Runtime が沈黙・死亡した episode を terminal へ導く安全網。

### ClaudeRuntimeSessionEpisodeInfo[wid, episodeId] → Association
episode の現在 ControlState / LastAppliedEventSeq / PendingCommand / HandleRef 等。

### ClaudeRuntimeSessionEpisodes[wid] → {episode...}
workflow 上の episode 一覧。

### ClaudeSessionActiveEpisodes[] → {episode...}
ActiveSessionEpisodes 導出 index (poll/recovery 対象)。正本は EpisodeActive の lease token (§10.5)。

### ClaudeSessionQuarantine[] → {record...}
schema/hash 違反等で隔離した event の記録一覧 (§11.4 の in-memory 版 + spool quarantine 記録)。

## artifact validation / single commit (Inc8, §17)

### ClaudeSessionValidateArtifactCandidate[candidate, contract, sessionLabel] → Association
ArtifactCandidate を ArtifactContract に対して検証する (§17.1)。schema / type 一致 / staging root 包含 / byte 上限 / privacy 単調 / provenance / RequiredChecks / (Files の) base revision を検査し `<|"Valid", "Errors", "Repairable"|>` を返す。fail-closed。

### ClaudeRuntimeSessionArtifactReceipt[wid, episodeId] → Association|None
commit 済み artifact の CommitReceipt (§17.3: CommitId/TargetRef/NewRevision/ContentHash 等)。未 commit なら None。

## conductor task node integration (IncC, §20/§21)

### ClaudeSessionMapRole[role] → "solve"|"plan"|"verify"|"synthesize"|"__SingleCommitter__"|Failure
multi-agent TaskSpec role を conductor role へ正規化する (§20.2)。Explore/Draft->solve, Plan->plan, Verify->verify, Reduce->synthesize, Commit->"__SingleCommitter__" (session にしない)。既に conductor role ならそのまま。未知は Failure (silent 縮退しない)。

### ClaudeSessionResolveBackend[requirement] → String|Failure
登録済み backend から §20.3 の heterogeneous binding で 1 つ選ぶ。requirement: `<|"PreferredBackend"->_, "RequiredCapabilities"->{..}, "IsolationRequired"->_, "SeatProbe"->fn|>`。capability/isolation で filter し、seat 可用性で rank。無ければ Failure (§20.3 silent に起動しない)。

### ClaudeSessionCompileTaskNode[taskNodeSpec, opts] → Association|Failure
WorkerKind="RuntimeSession" の TaskNodeSpec を episode supervisor net に compile する (§20.1)。role mapping・SessionProfile 正規化・SessionStartSpec 構築 (iCondBuildSessionStartSpec)・backend resolve を行い `ClaudeCreateRuntimeSessionEpisodeNet` を呼ぶ。WorkerKind="LLMCall" は本経路の対象外 (Failure["NotRuntimeSession"]、既存 atomic 経路が担当)。
→ `<|WorkflowId, EpisodeId, SessionId, Backend, Role, StartSpec|>`

### ClaudeSessionBuildStartSpecFromTaskNode[taskNodeSpec, binding] → Association (SessionStartSpec)
TaskNodeSpec + binding から検証済み SessionStartSpec を構築する (§21.2 iCondBuildSessionStartSpec)。net を作らず spec だけ返す。

### ClaudeSessionRunEpisodeToCompletion[wid, episodeId, opts] → Association
compile + start 済みの episode net を、pump (§11.2 一個ずつ) + engine step で終端まで駆動する Conductor 向け driver。WorkflowStatus=="Done" もしくは進展が止まる (NoNewEvents/NoActiveLease 等) まで bounded に回す。搬送層しか触らない (model/tool/NotebookWrite なし、§11.5)。
→ `<|Status(Completed|Failed|Incomplete), WorkflowStatus, ControlState, Pumps, LastPump, Receipt|>`
Options: "MaxPumps" -> 200

### ClaudeSessionConductTaskNode[taskNodeSpec, opts] → Association
RuntimeSession TaskNode を compile → start → 終端まで駆動する end-to-end 配線。`ClaudeSessionCompileTaskNode` + `ClaudeStartRuntimeSessionEpisode` + `ClaudeSessionRunEpisodeToCompletion` を 1 呼び出しに束ねる。compile が Failure(NotRuntimeSession 等) ならそれを返す。
→ `<|Status, WorkflowId, EpisodeId, SessionId, Backend, Role, ControlState, Receipt, Run|>`
opts は Compile と Run の option を受ける。

### ClaudeSessionConductPlan[taskNodes, opts] → Association
複数の RuntimeSession TaskNode を DependsOn の DAG として実行する Conductor plan runner。topological order で逐次 `ClaudeSessionConductTaskNode` を回し、失敗ノードの依存先は "Skipped" にする (failure propagation)。依存ノードの commit receipt は依存先へ DepReceipts として渡す。循環依存は Failure。非 RuntimeSession (LLMCall 等) は skip 対象で status "NotRuntimeSession"。並列実行は本 MVP では非対応 (逐次 topo)。
→ `<|Status, Order, Nodes(TaskId→result), Receipts|>`
Options: "Parallel" -> False

### ClaudeSessionConductReuseChain[taskNodes, opts] → Association
backend §8.1 契約の ReuseEpisode を使い、ReusePolicy=SameWorkflowSameTrust かつ同一 trust domain の連続 episode で物理 session を自動再利用する reuse-aware chain runner (Inc10 の Petri→reuse auto-firing 配線)。backend contract のみ経由し `ClaudeRuntime` に直接依存しない (§22)。trust-key=WorkflowId|AccessSpecHash|PolicySnapshotHash 単位の pool を持ち、eligible なら backend[ReuseEpisode]、不可なら fresh StartEpisode。各 episode は backend PollEvents で終端まで駆動。backend が ReuseEpisode 非対応なら常に fresh。
→ `<|Status, Nodes, PhysicalSessions, ReuseCount|>`

## durable event bridge / command outbox (Inc3, §11)

### $ClaudeSessionSpoolRoot
型: String, 初期値: `FileNameJoin[{$UserBaseDirectory, "ClaudeOrchestrator", "session-spool"}]`
episode spool の root directory。layout (§11.1): `<root>/<session-id>/<episode-id>/attempts/<attempt>/{inbox, outbox, delivery-index.wxf, command-index.wxf}` + episode-meta.json。

### ClaudeRuntimeSessionPollTick[] → Association
全 active episode について outbox dispatch と event pump を一回行う (§11.5 契約: 搬送のみ。model/tool/NotebookWrite を行わない。soft 200ms 超過分は次 tick へ、再入は SkippedBusy)。Petri の発火は行わない (engine の step/async tick が担当)。

### ClaudeRuntimeSessionDispatchOutbox[wid, episodeId] → Association
attempt-local outbox の未 ack command を backend へ送る (§11.3)。transport retry は同一 CommandId。Rejected は Bridge CommandRejected synthetic event に正規化して inbox へ置く (§11.2.1)。

### ClaudeRecoverRuntimeSessions[] → Association
active episode を backend Recover で検査し、LostUnrecoverable は genuine event recheck の後に Source=RecoveryScan の synthetic terminal を注入して lease release へ導く (§15.2 / Inc3 受け入れ「silent/dead Runtime でも lease release」)。

### ClaudeRuntimeSessionEnablePolling[] → Automatic|"ClaudeCodeUnavailable"
`ClaudeCode`` の shared polling tick に `ClaudeRuntimeSessionPollTick` を登録する (§11.5)。ClaudeCode 未ロード環境では ClaudeCodeUnavailable を返し何もしない。

### ClaudeSessionEpisodeSpoolInfo[sessionId, episodeId, attempt] → Association
spool 上の delivery-index / command-index / inbox・outbox ファイル一覧 (検査用)。

## conductor primitive (Inc0, §13.2/§16.4/§19.3/§25.3)

### ClaudeSessionResolveTrustDomain[modelEntry] → "Local"|"Cloud"|"Private"|Missing["Unknown"]
model/backend entry から InferenceTrustDomain を解決する (conductor v0.2 §13.2)。優先順: InferenceTrustDomain (canonical) > TrustDomain (legacy) > Class 内の Local/Cloud > provider label 分類。**ExecutionLocation は見ない** (claudecode は Local プロセスでも推論は Cloud)。不明は `Missing["Unknown"]` (gate 側で fail-closed)。

### ClaudeSessionTrustGateQ[privacyLabel, domain] → True|False
cloud 境界 (0.5) 以上の label で InferenceTrustDomain が Local|Private と確認できる場合のみ True。不明 domain・非数値 label は fail-closed で False (§16.4 / Inc0 受け入れ「private 由来 session が cloud trust gate を迂回しない」)。

### ClaudeSessionMakeCallContext[fields] → Association (CallContext)
provider call 発行時に固定する immutable な CallContext (§19.3) を返す。CallId は自動発行。Provider/Model は必須、RunId/WorkflowId/TaskId/SessionId/EpisodeId/Attempt/TurnIndex/ToolCallId/ReservationId は任意。mutable global に依存しない。

### ClaudeSessionLedgerRecord[callContext, usage] → Association
usage/cost を CallId で ledger に記録する。completion 順が逆転しても帰属は CallContext 固定なので壊れない (Inc0 受け入れ)。同一 CallId の再記録は上書き (Status->Updated)。usage: InTokens/OutTokens/CacheReadTokens/CostUSD/CostSource (Provider|Estimated|Unknown)。

### ClaudeSessionCallLog[] → {record...}
ledger 記録の一覧 (LoggedAt 順)。

### ClaudeSessionCallAggregate[keyField, keyValue] → Association
CallContext の keyField ("EpisodeId"/"RunId"/"WorkflowId" 等) が keyValue の call を集計する。CostUSD は数値のみ合算し、unknown cost は0扱いせず UnknownCostCalls として別掲する (§25.3)。

### ClaudeSessionCallLogReset[]
ledger をクリアする。テスト用。

## $ClaudeSessionModuleVersion
型: String, 初期値: バージョン文字列
本モジュールのバージョン。