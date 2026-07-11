# ClaudeOrchestrator RuntimeSession episode / Petri-net 統合仕様 v0.1

**Petri net は session の境界を管理し、agent の内部 turn/tool loop は worker runtime に閉じ込める**

- 日付: 2026-07-10
- ステータス: v0.1-r2 ドラフト（r1/r2 review 反映）
- 対象:
  - ClaudeOrchestrator_workflow.wl
  - 新規 ClaudeOrchestrator_session.wl
  - ClaudeRuntime.wl
  - 新規 ClaudeRuntime_session.wl
  - ClaudeRuntime_externalrunner.wl または新規 ClaudeRuntime_sessionrunner.wl
  - NBAccess.wl
- 関連仕様:
  - ClaudeOrchestrator_Runtime_StateGraph_Integration_Spec.md
  - claude_multi_agent_orchestration_spec.md
  - claude_orchestrator_conductor_policy_spec_v0_2.md
  - claude_orchestrator_conductor_policy_spec_v0_2_review.md
  - ClaudeRuntime_info/design/external_executor_task_placement_spec_v7_consolidated.md

---

## 0. 文書の目的

本仕様は、WorkerKind = "RuntimeSession" を ClaudeOrchestrator の Petri-net workflow へ導入する実装方法を定める。

採用する中核原則は次である。

> Petri net が管理するのは agent の各 turn や各 tool call ではない。Petri net は session episode の開始、外部観測待ち、checkpoint、budget interrupt、成果物境界、single commit、cancel/recovery を管理する。episode 内の model call、tool 選択、tool result の反復は worker runtime が所有する。

目的は次の四点である。

1. agent loop の実装詳細を Petri marking へ漏らさず、workflow の状態数を抑える。
2. ClaudeRuntime がすでに持つ conversation state、continuation、tool loop、turn budget を再利用する。
3. Orchestrator が privacy、environment、総 budget、artifact commit、approval、restore を強制できるようにする。
4. ClaudeRuntime、外部 process、将来の provider-native agent を同じ episode protocol で差し替え可能にする。

本仕様は learned workflow policy の実装仕様ではない。まず agent session substrate を作り、その後に workflow selection、異種 worker binding、学習型 policy を載せられる構造を目標とする。

### 0.1 review 反映方針

同フォルダの claude_orchestrator_runtime_session_episode_petri_spec_v0_1_review.md を反映した。主要変更は、単一 EpisodeActive place への統合、Attempt-scoped protocol、routine/boundary checkpoint 分離、in-kernel tick 契約、run/episode 間の budget・approval・completion 正本規定である。

review §3.2 の「multi-token join guard の engine 機構が存在しない」という現状認識だけは採用しない。現行 ClaudeEnabledTransitions は iEnumerateBindings 後に iEvaluateGuard を評価し、ClaudeFireTransition も consume 前に Guard を再評価している。したがって必要なのは新しい Guard 機構ではなく、pairing guard を必須 Function として net compiler が設定し、validator と交差 binding test で保証することである。

### 0.2 review 対応表

| review 指摘 | 対応 | 反映節 |
|---|---|---|
| P0 event 到達性 | 採用。単一 EpisodeActive + ControlState、全 state terminal/cancel matrix | §9.1–9.5 |
| P0 pairing guard | 問題意識は採用。新 engine 機構ではなく既存 Guard の必須利用と fail-closed validator | §9.4, §10.1 |
| P0 Attempt scope | 採用。command/event/cursor/spool を attempt-scoped 化 | §7.7–7.8, §8.1, §11.1 |
| P0 checkpoint と granularity | 採用。routine telemetry と boundary control に分離 | §7.5, §9.6 |
| P0 in-kernel execution | 採用。既存 Runtime tick が loop、session tick は搬送のみ | §11.5, §12.3 |
| P0 Runtime 新設機能の過小評価 | 採用。tool approval、budget suspend、effect journal、privacy state を新設と明記 | §2.2, §12, §23 |
| P0 budget/privacy 語彙 | 採用。conductor 名へ統一、PrivacyLabel [0,1] | §7.3–7.4, §16.4 |
| P1 delivery/clock/dedup/hash/quarantine/reconcile | 採用 | §7.9, §11, §13.1, §15.4 |
| P2 seat/Notebook/EffectClass/approval 正本 | 採用 | §13.3, §16.3, §17.3, §20.3 |
| r2 P0 synthetic terminal event | 採用。Runtime EventSeq と分離した evidence 付き合成 event | §7.7, §9.4, §11.2 |
| r2 P0 command rejection | 採用。CommandRejected と pending command supersede 経路 | §7.7, §9.3–9.5, §11.3 |
| r2 P1 start/stop/commit/expiry | 採用 | §7.8, §9, §13, §17, §18 |

---

## 1. 設計判断

### 1.1 採用する階層

~~~text
Conductor / Task planner
    TaskNodeSpec と WorkerKind を決める
              ↓
ClaudeOrchestrator Petri-net
    episode lease / boundary event / approval / budget / artifact commit
              ↓
RuntimeSession backend protocol
    start / poll / command / checkpoint / interrupt / recover
              ↓
Worker runtime
    model turns / tool loop / local memory / tool result feedback
              ↓
Isolated environment + NBAccess enforcement
~~~

Petri net と worker runtime の間は、同期関数呼出しではなく durable command/event protocol で接続する。

### 1.2 session と episode

- **Session**: worker runtime と環境、memory、backend handle の寿命。SessionId で識別する。
- **Episode**: Orchestrator が一つの TaskSpec を session へ委譲する実行単位。EpisodeId で識別する。
- **Turn**: episode 内部で model が応答する一回。Runtime 所有であり Petri token にしない。
- **Tool call**: episode 内部の tool invocation。Runtime 所有であり、approval が必要な境界を除き Petri token にしない。

MVP の既定は ReusePolicy = "Never"、すなわち 1 session = 1 episode とする。session 再利用は memory contamination、privacy label、累積 budget の規則が実証された後に opt-in で導入する。

### 1.3 Petri net に載せるもの

- episode の allocation と start
- session/environment/resource lease
- session から到着した control event
- 外部 observation / approval 待ち
- checkpoint ref の検証と記録
- budget interrupt と追加 grant
- artifact candidate の検証
- single committer による commit
- cancel、timeout、lost session、recovery
- terminal cleanup と resource release

### 1.4 Petri net に載せないもの

- prompt 構築の各段階
- model の各 turn
- token streaming chunk
- agent が内部で行う tool 選択
- pre-authorized tool の各 tool call/result
- internal reflection / chain-of-thought
- conversation message 一件ごとの状態
- heartbeat / progress 一件ごとの transition

内部 turn 数が 5 から 50 に増えても、外部 boundary event 数が同じなら Petri transition 数は原則増えないことを構造条件とする。

---

## 2. 現行実装との適合性

### 2.1 再利用できる資産

| 資産 | 現状 | 本仕様での利用 |
|---|---|---|
| ClaudeRuntime の ConversationState / TurnCount / ClaudeContinueTurn | ClaudeRuntime.wl に実装済み | session 内 turn loop の核 |
| AsyncToolExec と MaxToolIterations | Runtime 内部に実装済み | pre-authorized tool loop。Petri からは見せない |
| Runtime の CheckpointStack | in-memory 実装 | durable checkpoint schema へ昇格する素材 |
| WorkflowNet / token / resource place | workflow engine に実装済み | episode lease と concurrency control |
| ClaudeSubmitToken | 任意 place への外部 token 投入が可能 | session control event bridge |
| AwaitingLLMTransitions | atomic async transition を一回の callback で完了 | atomic な単発非同期作業では維持。session 複数イベントには使わない |
| external backend registry | launcher/status/killer を backend 名で登録可能 | external session runner の素材 |
| external job durable root / PID / recovery | ClaudeRuntime_externalrunner.wl | process identity、orphan recovery、ref-only I/O |
| NBAccess AccessSpec / PolicySnapshot | external executor 仕様に存在 | tool と environment の hard policy 入力 |
| TaskSpec / ArtifactSpec / single committer | multi-agent 仕様に存在 | episode 入力と成果物境界 |

主な現行コード根拠:

- ClaudeRuntime.wl:519 付近: BudgetsUsed、TurnCount、ConversationState、CheckpointStack。
- ClaudeRuntime.wl:1497 付近: tool loop と MaxToolIterations。
- ClaudeRuntime.wl:2552 付近: AsyncToolExec state machine。
- ClaudeRuntime.wl:3474 付近: ClaudeContinueTurn。
- ClaudeOrchestrator_workflow.wl:126 / 810 付近: 外部からの ClaudeSubmitToken。
- ClaudeOrchestrator_workflow.wl:1439–1484 付近: atomic AwaitingLLM 登録と timeout。
- ClaudeOrchestrator_workflow.wl:1886–1947 付近: callback 一回で output produce と await entry 削除。
- ClaudeRuntime_externalrunner.wl:1104 付近: orphan external job recovery。

### 2.2 不足するもの

1. RuntimeSession という公開 lifecycle API がない。
2. Runtime checkpoint は private/in-memory で、process 再起動後に復元できない。
3. Runtime budget は iteration count が中心で、cash/token/wall-clock/tool 種別の総量契約がない。
4. AwaitingLLMTransitions は「input を一度 consumeし、callback で一度 output を produce」する契約であり、同一 session から複数 boundary event を受ける用途に合わない。
5. workflow snapshot は backend handle、event cursor、command outbox を宣言的に復元しない。
6. session artifact の staging/validation/commit handshake がない。
7. event/command の重複配送を安全に扱う sequence/idempotency 契約がない。
8. tool 単位の pre-execution approval gate と ToolCallId-scoped permit は現行 Runtime tool loop にない。
9. BudgetExhausted は現行 Runtime では Failed 終了であり、grant 待ち suspend/resume state machine はない。
10. ToolCallId、effect journal、Runtime privacy label は新設であり、既存 loop 全経路の改修を要する。
11. AccessSpecHash は新設が必要。PolicySnapshot digest の canonical 化だけが既存。

### 2.3 非採用案

~~~text
各 ClaudeRunTurn を Petri transition にする
各 tool call を Place/Transition にする
同一 AwaitingLLM entry を複数 callback で再利用する
Runtime の ConversationState 全体を token payload に入れる
worker に target notebook/workspace への直接 commit を許す
process handle や Function closure を workflow snapshot に保存する
~~~

---

## 3. 不変条件

| ID | 不変条件 |
|---|---|
| I1 | model turn と通常 tool call は Petri marking に現れない |
| I2 | 全 episode は開始前に AccessSpecHash、PolicySnapshotHash、EnvironmentLeaseId、BudgetGrantId を固定する |
| I3 | Runtime は access と budget を自己拡張できない。変更は新しい Orchestrator command/grant が必要 |
| I4 | Petri token と command/event spool に raw conversation、secret、巨大 artifact 本文を入れない。ref と要約だけを入れる |
| I5 | Runtime は staging area にだけ書ける。target への反映は single committer transition だけが行う |
| I6 | control event は (EpisodeId, Attempt, EventSeq) で一意となり、重複配送しても token は一個だけになる |
| I7 | command は CommandId で冪等。再送で tool、課金、commit を二重実行しない |
| I8 | checkpoint は policy hash、budget counters、artifact manifest、tool journal を含み、secret 本体を含まない |
| I9 | non-idempotent tool の再開は journal で完了確認できるか、ユーザー承認がある場合に限る |
| I10 | session/environment/resource lease は terminal path のどれからでも高々一回だけ返却する |
| I11 | budget hard stop 後、Runtime は次の billable call/tool を開始しない |
| I12 | workflow restore は Function closure を復元せず、backend 名と record から poller/bridge を宣言的に再登録する |
| I13 | Failed/Cancelled/EnvironmentLost と Cancel/Stop は全 non-terminal ControlState から到達可能 |
| I14 | 全 lease は policy 上限時間内に Released または QuarantineReleased へ到達する |

---

## 4. 全体アーキテクチャ

~~~mermaid
flowchart LR
    TS["TaskSpec + WorkerKind=RuntimeSession"] --> PN["Episode supervisor Petri net"]
    PN -->|"StartEpisode command"| OB["Durable command outbox"]
    OB --> BE["Session backend"]
    BE --> RT["Worker runtime: internal turns + tool loop"]
    RT --> ENV["Isolated environment / staging area"]
    RT -->|"control events only"| IB["Durable event inbox"]
    IB --> BR["Session event bridge"]
    BR -->|"SessionEvent token"| PN
    PN --> VAL["Artifact validation"]
    VAL --> COM["Single committer"]
    COM --> TARGET["Notebook / files / ArtifactStore"]
~~~

高頻度の runtime trace と低頻度の orchestration control event は別 stream にする。

~~~text
Runtime trace:
  turns, model usage, tool calls, local progress, heartbeat
  -> Runtime-owned trace store

Control event:
  observation required, approval required, checkpoint created,
  budget interrupt, artifact proposed, completed, failed
  -> durable inbox -> Petri SessionEvent token
~~~

Orchestrator は runtime trace の ref と集計値を記録するが、各 trace event を transition に変換しない。

---

## 5. 責務境界

### 5.1 ClaudeOrchestrator

- TaskSpec から episode supervisor net を生成する
- session/backend/environment/resource の候補を選ぶ
- access/policy/budget snapshot を固定する
- SessionStartSpec を作る
- command outbox と event inbox を所有する
- control event を Petri token へ一回だけ投入する
- boundary event を決定論に route する
- approval と budget extension を所有する
- checkpoint ref の hash/schema を検証して記録する
- artifact candidate を検証し single committer を発火する
- cancel/recovery/lease release を所有する

### 5.2 Worker runtime

- model/provider との複数 turn interaction
- conversation memory と必要な圧縮
- pre-authorized tool の選択と実行
- tool result を次の model turn に戻す loop
- local turn/tool/token/time/cost guard
- safe point での checkpoint 生成
- staging area への成果物生成
- control event の発行
- command の冪等受理
- cancel/budget interrupt 時の停止と最終 checkpoint

### 5.3 NBAccess / environment enforcement

- tool call ごとの AccessSpec 検査
- filesystem/network/external command の allowlist 強制
- credential/secret ref の解決と非露出
- scoped approval の適用
- privacy label の伝播
- staging root 外への書込み拒否

### 5.4 Conductor / planner

- WorkerKind = "RuntimeSession" を選ぶ
- TaskNodeSpec、ExpectedArtifactType、AccessList、必要 capability を宣言する
- episode の内部 turn/tool topology を生成しない
- provider/model/backend を明示しても Orchestrator の trust/budget gate を迂回しない

---

## 6. 識別子と相関

| ID | 寿命 | 発行主体 | 用途 |
|---|---|---|---|
| WorkflowId | workflow 全体 | Workflow engine | Petri net |
| RunId | conductor run | Conductor | 複数 child/episode の集約 |
| TaskId | TaskNodeSpec | Planner/Orchestrator | DAG 上の論理 task |
| SessionId | worker session | Orchestrator | backend/environment/memory の寿命 |
| EpisodeId | task 委譲一回 | Orchestrator | budget/access/artifact 契約単位 |
| Attempt | retry/resume | Orchestrator | episode 実行試行 |
| CommandId | command 一件 | Orchestrator | command 冪等性 |
| EventId / EventSeq | event | Runtime | dedup、gap/replay 検出 |
| ToolCallId | tool effect | Runtime | non-idempotent effect journal |
| ArtifactId | artifact candidate | Runtime/ArtifactStore | validation/commit |
| LeaseId | resource lease | Orchestrator | exactly-once release |

SessionId と EpisodeId を同じ値にしない。MVP で 1:1 でも別 field とする。

---

## 7. データモデル

### 7.1 SessionStartSpec

~~~wl
<|
  "SchemaVersion" -> 1,
  "WorkflowId" -> _String, "RunId" -> None | _String,
  "TaskId" -> _String, "SessionId" -> _String,
  "EpisodeId" -> _String, "Attempt" -> 1,

  "Backend" -> _String,
  "Worker" -> <|
    "Provider" -> _String, "Model" -> _String,
    "RuntimeProfile" -> _String, "AdapterFactory" -> _String
  |>,

  "Task" -> <|
    "GoalRef" -> _, "InputArtifactRefs" -> {___},
    "ExpectedArtifactType" -> _String,
    "OutputSchema" -> _Association,
    "DeterministicChecks" -> {___String}
  |>,

  "Access" -> <|
    "AccessList" -> {___}, "AccessSpec" -> _Association,
    "AccessSpecHash" -> _String,
    "PolicySnapshotRef" -> _,
    "PolicySnapshotHash" -> _String,
    "PrivacyLabel" -> _?NumericQ,
    "AllowedCapabilities" -> {___String}
  |>,

  "Environment" -> EnvironmentSpec,
  "BudgetGrant" -> BudgetGrant,
  "CheckpointPolicy" -> CheckpointPolicy,
  "ArtifactContract" -> ArtifactContract,
  "ReusePolicy" -> "Never" | "SameWorkflowSameTrust",
  "CreatedAt" -> _DateObject
|>
~~~

GoalRef と input は原則 ref-only とする。小さい public text の inline も size/privacy gate を通す。

### 7.2 EnvironmentSpec

~~~wl
<|
  "IsolationLevel" ->
      "ExternalProcess" | "Container" | "WorkspaceOverlay" |
      "CooperativeKernel",
  "EnvironmentLeaseId" -> _String,
  "BaseSnapshotRef" -> _,
  "ReadOnlyInputRoots" -> {___String},
  "WritableStagingRoot" -> _String,
  "FinalTargetRefs" -> {___},
  "AllowedDirectories" -> {___String},
  "AllowedNetworkTargets" -> {___String},
  "AllowedExternalCommands" -> {___String},
  "CredentialRefs" -> {___}, "SecretRefs" -> {___},
  "ConfidentialHandling" ->
      "EncryptedBundle" | "ReferenceOnly",
  "CleanupPolicy" -> _Association
|>
~~~

FinalTargetRefs は runtime の writable path に含めない。CooperativeKernel は OS sandbox ではない。private data、外部 command、非冪等 write がある episode では policy が ExternalProcess 以上を要求できるようにする。

### 7.3 BudgetGrant

~~~wl
<|
  "BudgetGrantId" -> _String, "Version" -> 1,
  "Objective" -> "CompleteWithinBudget",
  "HardLimits" -> <|
    "MaxTurns" -> _Integer, "MaxCalls" -> _Integer,
    "MaxToolCalls" -> _Integer,
    "MaxInputTokens" -> _Integer, "MaxOutputTokens" -> _Integer,
    "MaxContextTokensPerStep" -> _Integer,
    "MaxWallClockSeconds" -> _?NumericQ,
    "MaxIdleSeconds" -> _?NumericQ,
    "MaxBytesWritten" -> _Integer,
    "MaxNetworkRequests" -> _Integer,
    "MaxCostUSD" -> None | _?NumericQ
  |>,
  "SoftThresholds" -> <|
    "WarnFraction" -> 0.8, "CheckpointFraction" -> 0.9
  |>,
  "UnknownCostPolicy" ->
      "Reject" | "RequireApproval" | "AllowUnmetered",
  "IssuedAt" -> _DateObject, "GrantHash" -> _String
|>
~~~

Runtime は action 発行前に local guard を行い、Orchestrator は control event と provider usage を別 ledger で検算する。

### 7.4 BudgetSnapshot

control event は delta ではなく累積値を含む。

~~~wl
<|
  "Turns" -> _, "Calls" -> _, "ToolCalls" -> _,
  "InputTokens" -> _, "OutputTokens" -> _,
  "WallClockSeconds" -> _, "IdleSeconds" -> _,
  "BytesWritten" -> _, "NetworkRequests" -> _,
  "ActualUSD" -> None | _, "ReservedUSD" -> None | _,
  "CostSource" -> "Provider" | "Estimated" | "Unknown",
  "BudgetGrantId" -> _, "BudgetGrantVersion" -> _
|>
~~~

Turns、Calls、ToolCalls、InputTokens、OutputTokens、WallClockSeconds、BytesWritten、NetworkRequests、ActualUSD は同一 EpisodeId の attempt を跨いで単調非減少とする。ReservedUSD は予約・精算で増減できる。IdleSeconds は「現在連続して実行可能なのに進捗がない時間」であり、進捗発生、外部 observation/approval 待ちへの遷移、attempt 終了で 0 に戻る非単調 gauge とする。累積 idle が必要な場合は別 field TotalIdleSeconds を使い、attempt を跨いで単調非減少にする。

run ledger との canonical 名は conductor v0.2 に合わせる。MaxCalls は billable model/provider call 数、MaxTurns は conversation turn 数、MaxToolCalls は tool effect 数であり、互いに代替しない。

### 7.5 CheckpointPolicy と manifest

~~~wl
CheckpointPolicy = <|
  "Enabled" -> True,
  "Routine" -> <|
    "AtEpisodeStart" -> True,
    "AfterToolCalls" -> 5,
    "EverySeconds" -> 300,
    "EmitControlEvent" -> False
  |>,
  "Boundary" -> <|
    "BeforeNonIdempotentTool" -> True,
    "AtSoftBudgetThreshold" -> True,
    "OnInterrupt" -> True,
    "OnExplicitRequest" -> True,
    "EmitControlEvent" -> True
  |>,
  "MaxRetained" -> 5,
  "Storage" -> "EncryptedBundle" | "ReferenceOnly",
  "RequireHashVerification" -> True
|>;

RuntimeCheckpointManifest = <|
  "SchemaVersion" -> 1,
  "SessionId" -> _, "EpisodeId" -> _, "Attempt" -> _,
  "CheckpointId" -> _, "CreatedAt" -> _,
  "RuntimeProfile" -> _, "AdapterFactory" -> _,
  "ConversationStateRef" -> _,
  "ConversationSummaryRef" -> _,
  "ToolJournalRef" -> _,
  "EnvironmentSnapshotRef" -> _,
  "ArtifactStagingManifestRef" -> _,
  "BudgetSnapshot" -> _Association,
  "LastEventSeq" -> _Integer,
  "PendingCommandIds" -> {___String},
  "AccessSpecHash" -> _String,
  "PolicySnapshotHash" -> _String,
  "BudgetGrantId" -> _String,
  "BudgetGrantVersion" -> _Integer,
  "PrivacyLabel" -> _?NumericQ,
  "ContentHash" -> _String
|>;
~~~

checkpoint は safe point で作る。adapter Function、ProcessObject、credential 本体、raw secret は保存しない。adapter は AdapterFactory 名から再構築する。

routine checkpoint は Runtime journal に保存し、Petri event にしない。次の control event の LatestCheckpointRef/LatestRoutineCheckpointRef に piggyback する。boundary checkpoint だけが CheckpointCreated control event となり、Petri net が hash/policy/budget を確定する。この分離により routine checkpoint 頻度を上げても control transition 数は増えない。

### 7.6 ArtifactContract / ArtifactCandidate

~~~wl
ArtifactContract = <|
  "ExpectedArtifactType" -> _String,
  "OutputSchema" -> _Association,
  "AllowedStagingRoot" -> _String,
  "MaxArtifactBytes" -> _Integer,
  "RequiredChecks" -> {___String},
  "CommitTargetRef" -> _,
  "BaseRevision" -> None | _String,
  "CommitMode" -> "ArtifactStore" | "Notebook" | "Files",
  "RequireProvenance" -> True
|>;

ArtifactCandidate = <|
  "ArtifactId" -> _String,
  "SessionId" -> _, "EpisodeId" -> _,
  "ArtifactType" -> _String, "ArtifactRef" -> _,
  "ManifestRef" -> _, "ContentHash" -> _String,
  "ByteCount" -> _Integer, "OutputSchemaVersion" -> _,
  "PrivacyLabel" -> _?NumericQ,
  "Provenance" -> <|
    "InputRefs" -> {___}, "ToolJournalRef" -> _,
    "Model" -> _, "RuntimeTraceRef" -> _
  |>,
  "SelfChecks" -> _Association,
  "BaseRevision" -> None | _String
|>;
~~~

### 7.7 SessionControlEvent

~~~wl
<|
  "SchemaVersion" -> 1,
  "EventId" -> _String,
  "Source" ->
      "Runtime" | "OrchestratorWatchdog" | "RecoveryScan" | "Bridge",
  "EventSeq" -> None | _Integer,
  "SyntheticBaseEventSeq" -> None | _Integer,
  "SessionId" -> _String, "EpisodeId" -> _String,
  "Attempt" -> _Integer,
  "BackendInstanceId" -> None | _String,
  "Type" ->
      "ObservationRequired" | "ApprovalRequired" |
      "CheckpointCreated" | "BudgetInterrupt" |
      "ArtifactProposed" | "Completed" | "Failed" |
      "Cancelled" | "EnvironmentLost" |
      "CommandAccepted" | "CommandRejected",
  "SupersedesThroughSeq" -> None | _Integer,
  "EvidenceRef" -> None | _,
  "PayloadRefs" -> _Association,
  "LatestCheckpointRef" -> None | _,
  "BudgetSnapshot" -> _Association,
  "AccessSpecHash" -> _String,
  "PolicySnapshotHash" -> _String,
  "PrivacyLabel" -> _?NumericQ,
  "CreatedAt" -> _DateObject, "EventHash" -> _String
|>
~~~

Heartbeat と Progress は runtime telemetry event であり、Petri control event にはしない。

Source = "Runtime" の event だけが EventSeq を持つ。Runtime が沈黙・死亡して event を発行できない場合、OrchestratorWatchdog/RecoveryScan は EventSeq = None、SyntheticBaseEventSeq = 現在 lease の LastAppliedEventSeq、EvidenceRef 必須の SyntheticControlEvent を作れる。合成 terminal Type は Failed / EnvironmentLost / Cancelled に限定する。

Bridge は backend SendCommand の同期戻り値 Rejected を CommandRejected event に正規化する。CommandRejected も EventSeq = None で、SyntheticBaseEventSeq、CommandId、Reason、ObservedRuntimeEventSeq を EvidenceRef/ PayloadRefs に持つ。

合成 event の EventId/Hash は Runtime event namespace と分離し、source、episode、attempt、synthetic base、type、evidence hash から決定論生成する。

schema validator は Source と Type の組合せも検査する。Runtime は通常 control event と CommandAccepted だけ、Bridge は CommandRejected だけ、OrchestratorWatchdog/RecoveryScan は terminal type だけを発行できる。backend から受信した payload が非 Runtime Source を自己申告しても synthetic event として受理せず quarantine する。

### 7.8 SessionCommand

~~~wl
<|
  "SchemaVersion" -> 1, "CommandId" -> _String,
  "SessionId" -> _String, "EpisodeId" -> _String,
  "Attempt" -> _Integer,
  "ExpectedAfterEventSeq" -> _Integer,
  "Type" ->
      "ProvideObservation" | "GrantScopedApproval" |
      "GrantBudget" | "RequestCheckpoint" |
      "AcceptArtifact" | "RepairArtifact" |
      "Stop" | "Cancel" | "Ping",
  "PayloadRefs" -> _Association,
  "BudgetGrant" -> None | _Association,
  "ScopedPermitRef" -> None | _,
  "IssuedAt" -> _DateObject, "CommandHash" -> _String
|>
~~~

Runtime は同じ CommandId を再受信した場合、前回の ack を返し effect を再実行しない。

ExpectedAfterEventSeq は参考値ではなく optimistic concurrency precondition である。Runtime は自分が emit 済みの最新 EventSeq がこの値に一致し、Attempt も一致する場合だけ command を受理する。不一致は Rejected(StaleContext) または Rejected(StaleAttempt)。Orchestrator は最新 event を取り込み、旧 command を Superseded と記録して新しい CommandId で意図を再評価する。

Cancel と Stop は安全側の例外として Attempt 一致だけを必須とし、stale EventSeq でも受理する。Stop は safe checkpoint 後の graceful close、Cancel は即時停止である。backend が Stop を二回 Rejected した場合は Cancel へ昇格する。Attempt 不一致はいずれも常に拒否する。

### 7.9 canonical hash

EventHash、CommandHash、GrantHash、ContentHash、AccessSpecHash、PolicySnapshotHash は共通関数で計算する。

~~~text
1. hash 自身、transport timestamp、delivery status を対象から除く
2. Association を全階層で KeySort
3. set semantics の field だけを schema 指定で Sort
4. schema/version を含む canonical WXF bytes を生成
5. SHA256
~~~

NBAccess の PolicySnapshot canonical digest を前例として流用し、AccessSpec 用 canonical hash を Inc1 で新設する。EventHash は完全性検出であり、真正性は同一 OS user と spool ACL に依存する。HMAC/署名は remote backend 導入時の必須拡張とする。

---

## 8. RuntimeSession backend protocol

### 8.1 backend registry

~~~wl
ClaudeRegisterRuntimeSessionBackend[name_String, backend_Association]
ClaudeRuntimeSessionBackends[]
ClaudeRuntimeSessionBackendInfo[name_String]
~~~

backend Association:

~~~wl
<|
  "ProtocolVersion" -> 1,
  "Capabilities" -> {
    "Checkpoint", "Resume", "Interrupt", "ExternalProcess",
    "ToolLoop", "EventReplay", "NotebookCommit"
  },
  "StartEpisode" -> fn,
  "PollEvents" -> fn,
  "SendCommand" -> fn,
  "Inspect" -> fn,
  "Recover" -> fn,
  "Dispose" -> fn
|>
~~~

必須 contract:

~~~wl
StartEpisode[startSpec] ->
  <|"Status" -> "Started" | "AlreadyStarted" | "Failed",
    "SessionId" -> _, "EpisodeId" -> _,
    "HandleRef" -> _, "BackendInstanceId" -> _,
    "InitialEventCursor" -> <|"Attempt"->_Integer, "EventSeq"->0|>,
    "PIDRef" -> None | _|>

PollEvents[handleRef, cursor] ->
  <|"Status" -> "OK" | "Unavailable" | "Lost",
    "Events" -> {SessionControlEvent...},
    "NextCursor" -> <|"Attempt"->_Integer, "EventSeq"->_Integer|>,
    "HeartbeatAt" -> None | _DateObject|>

SendCommand[handleRef, command] ->
  <|"Status" -> "Accepted" | "AlreadyAccepted" |
                  "Rejected" | "Unavailable",
    "CommandId" -> _, "Reason" -> _|>

Recover[episodeRecord] ->
  <|"Status" -> "Reattached" | "ResumedFromCheckpoint" |
                  "NeedsRestartApproval" | "LostUnrecoverable" | "Failed",
    "HandleRef" -> _, "ResumedCheckpointRef" -> _|>

Dispose[handleRef, cleanupPolicy] ->
  <|"Status" -> "Disposed" | "AlreadyDisposed" | "Quarantined"|>
~~~

### 8.2 wiring

ClaudeRuntime は Orchestrator へ依存して自己登録してはならない。ClaudeRuntime context の ClaudeRuntimeSessionBackendSpec[] が backend Association を返し、claudecode.wl または専用 wiring module が登録する。snapshot には Function を保存せず backend 名だけを保存する。

初期 backend:

| Backend | 用途 | 制約 |
|---|---|---|
| MockRuntimeSession | unit/integration test | 決定論 event script |
| ClaudeRuntimeInKernel | MVP、read-only、小規模 | hard isolation/OS kill なし |
| ClaudeRuntimeExternalProcess | tool 付き本番 session | durable job root、PID identity、cancel/recover |

NotebookCommit capability は headless backend では False/欠落とする。CommitMode = "Notebook" の task は FrontEnd と completion-aware FinalActionQueue が利用可能な committer backend が別に存在する場合だけ受理する。worker session backend 自身に NotebookWrite を与える意味ではない。

---

## 9. Petri-net episode supervisor

### 9.1 単一 EpisodeActive place

~~~mermaid
flowchart TD
    R["EpisodeRequested"] --> A["AllocateEpisode"]
    S["SessionSlots"] --> A
    E["EnvironmentSlots"] --> A
    A --> AL["EpisodeAllocated"]
    AL --> ST["StartEpisode"]
    ST --> SR["EpisodeStartResults"]
    SR -->|"Started/AlreadyStarted"| ACT["EpisodeActive<br/>ControlState in token"]
    SR -->|"retryable start failure"| AL
    SR -->|"terminal start failure"| FAIL["EpisodeFailed"]
    EV["SessionEvents"] --> ROUTE["Guarded event transitions"]
    ACT --> ROUTE
    ROUTE -->|"Observation/Approval/Checkpoint/Budget"| ACT
    ROUTE -->|"ArtifactProposed"| ACT
    ROUTE -->|"Completed"| DONE["EpisodeCompleted"]
    ROUTE -->|"retryable Failed/Lost"| ACT
    ROUTE -->|"terminal Failed/Cancelled"| FAIL
    ACT --> V["ValidateArtifact"]
    V -->|"repair command"| ACT
    V -->|"pass + CommitPermit"| C["SingleCommitter"]
    C -->|"AcceptArtifact command"| ACT
    ACT -->|"Recovering: resume from checkpoint"| AL
    DONE --> CLP["CleanupPending"]
    FAIL --> CLP
    CLP --> CL["CleanupAndRelease"]
    CL --> REL["LeasesReleased"]
~~~

lease token は Start 後から terminal event まで常に EpisodeActive に置く。AwaitingObservation、AwaitingApproval、CheckpointReview、BudgetReview、CommandPending、ArtifactReview、Closing は place ではなく immutable な次世代 SessionLease token の ControlState で表す。これにより Runtime の terminal event と Cancel が全 active state から同じ transition 群へ到達できる。

### 9.2 places と ControlState

| Place | Token kind | 意味 |
|---|---|---|
| EpisodeRequested | Task | TaskSpec と要求 profile |
| SessionSlots / EnvironmentSlots | ResourceSlot | 同時 session/process 上限 |
| EpisodeAllocated | SessionLease | start 前。ID、backend、access、budget、environment を固定 |
| EpisodeStartResults | SessionLease | backend start の Started/AlreadyStarted/Failed 結果と全 lease ref |
| EpisodeActive | SessionLease | start 後の全 non-terminal control state |
| SessionEvents | SessionEvent | bridge が投入した control event |
| CommitPermits | CommitPermit | single committer のみ consume |
| EpisodeCompleted / EpisodeFailed | Artifact / Failure | terminal |
| CleanupPending | SessionLease | backend dispose と lease release |

ControlState enum:

~~~text
Starting
Running
AwaitingObservation
AwaitingApproval
CheckpointReview
BudgetReview
CommandPending
ArtifactReview
CommitReady
Closing
Cancelling
Recovering
~~~

ControlState を上書き mutation せず、各 transition は親 lease を consume して新しい SessionLease token を EpisodeActive に produce する。LastAppliedEventSeq、LatestCheckpointRef、PendingCommandId、PendingCommandOriginState、ArtifactCandidateRef、CommitReceiptRef もこの token が正本である。

### 9.3 transitions

| Transition | Executor | 主な処理 |
|---|---|---|
| AllocateEpisode | PureFunction | ID、candidate gate、Access/Environment/Budget、lease |
| StartEpisode | RuntimeSession | idempotent start。backend semantic outcome を StartResult として produce |
| AcceptStartedEpisode | PureFunction | Started/AlreadyStarted を EpisodeActive(Running)へ |
| HandleStartFailure | PureFunction | Failed を retryable なら EpisodeAllocated、terminal なら EpisodeFailed へ |
| HandleObservationRequired / HandleApprovalRequired | PureFunction | event 検証と ControlState 更新 |
| RecordCheckpoint | PureFunction | boundary checkpoint の manifest/hash/policy/budget 整合検査 |
| HandleBudgetInterrupt | PureFunction | stop/degrade/extension approval |
| QueueSessionCommand | PureFunction | durable outbox atomic write |
| AcknowledgeSessionCommand | PureFunction | CommandId 照合後 ControlState 更新 |
| HandleCommandRejected | PureFunction | Bridge の CommandRejected を適用し pending command を Superseded、origin/new event state へ |
| HandleArtifactProposed | PureFunction | candidate ref/staging 範囲検査 |
| ValidateArtifact | Runtime/PureFunction | deterministic check 優先 |
| CommitArtifact | PackageManager/FinalActionQueue | single commit |
| HandleCompleted | PureFunction | commit receipt、final counters、expected artifact を照合 |
| HandleTerminalEvent | PureFunction | Failed/Cancelled/EnvironmentLost を全 ControlState から terminal へ |
| CancelActiveEpisode | PureFunction | 全 ControlState から Cancel command を queue |
| CancelBeforeStart | PureFunction | EpisodeRequested/EpisodeAllocated を start せず terminal へ |
| HandleFailure | PureFunction | retry/idempotency/checkpoint/budget 分岐 |
| CleanupAndRelease | PureFunction/External | dispose、cleanup、lease 一回返却 |

### 9.4 event/lease pairing Guard

~~~wl
sameEpisodeQ =
  event["EpisodeId"] === lease["EpisodeId"] &&
  event["SessionId"] === lease["SessionId"] &&
  event["Attempt"] === lease["Attempt"];

normalSeqQ =
  event["Source"] === "Runtime" &&
  IntegerQ[event["EventSeq"]] &&
  event["EventSeq"] === lease["LastAppliedEventSeq"] + 1;

terminalPreemptQ =
  event["Source"] === "Runtime" &&
  MemberQ[{"Failed", "Cancelled", "EnvironmentLost"}, event["Type"]] &&
  IntegerQ[event["EventSeq"]] &&
  event["EventSeq"] > lease["LastAppliedEventSeq"] + 1 &&
  event["SupersedesThroughSeq"] === event["EventSeq"] - 1;

syntheticTerminalQ =
  MemberQ[{"OrchestratorWatchdog", "RecoveryScan"}, event["Source"]] &&
  MemberQ[{"Failed", "Cancelled", "EnvironmentLost"}, event["Type"]] &&
  event["EventSeq"] === None &&
  event["SyntheticBaseEventSeq"] === lease["LastAppliedEventSeq"] &&
  event["EvidenceRef"] =!= None;

syntheticCommandRejectedQ =
  event["Source"] === "Bridge" &&
  event["Type"] === "CommandRejected" &&
  event["EventSeq"] === None &&
  event["SyntheticBaseEventSeq"] === lease["LastAppliedEventSeq"] &&
  event["EvidenceRef"] =!= None &&
  lease["ControlState"] === "CommandPending";

sameHashQ =
  event["AccessSpecHash"] === lease["AccessSpecHash"] &&
  event["PolicySnapshotHash"] === lease["PolicySnapshotHash"];

stateAllowedQ =
  iSessionStateAllowsEventQ[lease["ControlState"], event["Type"], event["Source"]];

sameEpisodeQ && sameHashQ && stateAllowedQ &&
  (normalSeqQ || terminalPreemptQ ||
   syntheticTerminalQ || syntheticCommandRejectedQ)
~~~

net compiler はこの条件を WorkflowTransition の既存 Guard に Function として設定する。Guard の必須成分は identity/attempt pairing、Runtime sequence または許可 synthetic source、policy hash、§9.5 ControlState 行列の四つである。現行 engine は enabled binding 列挙時と fire 直前の二回 Guard を評価するため、不一致 binding は consume 前に除外できる。

pairing Guard は副作用なし、決定論、O(比較 field 数)とする。enabled binding 列挙時と fire 直前に同じ引数で評価した結果は一致しなければならない。Guard が None、非 Function、例外、非 True を返す場合は session event transition では fail-closed とする validator を追加する。Guard 内で trace を書かず、例外診断は compiler-generated wrapper の事前検査または event bridge の quarantine record に残す。

terminal preemption を使った transition は、LastAppliedEventSeq+1 から SupersedesThroughSeq までを Superseded として delivery-index に一括記録してから LastAppliedEventSeq を terminal EventSeq へ進める。

SyntheticControlEvent は Runtime sequence を消費せず、LastAppliedEventSeq を変更しない。適用後に到着した Runtime event は terminal episode を再開せず quarantine/late-events に監査保存する。

不一致 event は consume せず quarantine record へ送る。古い attempt の遅延 event が新 attempt を進めてはならない。複数 episode では全 lease/event 組合せ列挙が O(n^2) になり得るため、同時 session 数が増えた段階で InputArc の CorrelationKey prefilter を性能拡張として追加する。MVP の正しさは Guard が担う。

### 9.5 event × ControlState 到達性

| Event / command | 許可する現在 state | 次 state / terminal |
|---|---|---|
| ObservationRequired | Running | AwaitingObservation |
| ApprovalRequired | Running | AwaitingApproval |
| boundary CheckpointCreated | 全 ControlState | 元 state、または CheckpointReview 後に元 state |
| BudgetInterrupt | Running / CheckpointReview | BudgetReview |
| ArtifactProposed | Running | ArtifactReview |
| CommandAccepted | CommandPending | command 種別に応じ Running / Closing / Cancelling |
| CommandRejected(Source=Bridge) | CommandPending | PendingCommand を Superseded、OriginControlState または最新 Runtime event による state |
| Runtime boundary event | CommandPending | pending command を暗黙 Superseded にして event 本来の次 state |
| Completed | Closing、または artifact 不要 task の Running | EpisodeCompleted |
| Failed(Runtime/synthetic) | 全 ControlState | EpisodeFailed / Recovering |
| Cancelled(Runtime/synthetic) | 全 ControlState | EpisodeFailed(StatusDetail=Cancelled) |
| EnvironmentLost(Runtime/synthetic) | 全 ControlState | EpisodeFailed / Recovering |
| ProvideObservation command | AwaitingObservation | CommandPending(Origin=AwaitingObservation) |
| GrantScopedApproval command | AwaitingApproval | CommandPending(Origin=AwaitingApproval) |
| GrantBudget command | BudgetReview | CommandPending(Origin=BudgetReview) |
| RepairArtifact command | ArtifactReview | CommandPending(Origin=ArtifactReview) |
| AcceptArtifact command | CommitReady | CommandPending(Origin=CommitReady) |
| RequestCheckpoint command | Running / wait states | CommandPending(Origin=current) |
| Cancel command | 全 ControlState | Cancelling |
| Stop command | 全 ControlState | Closing |

不変条件 I13:

> Failed、Cancelled、EnvironmentLost は全 non-terminal state から消費可能であり、Cancel/Stop command は全 non-terminal state から発行可能でなければならない。

CommandPending 中に新しい Runtime boundary event が来た場合、ExpectedAfterEventSeq が既に stale なので pending command を Superseded として command-index に記録してから event を適用する。CommandRejected は Runtime EventSeq を進めず OriginControlState へ戻し、最新 event/counter を読んで同じ意図を再評価する。自動再発行は同一 CommandId を使わず、新しい precondition と CommandId を発行する。

### 9.6 granularity 条件

Nturn を内部 model turn 数、B を外部 boundary event 数とする。

~~~text
Tcontrol = O(1 + B)
d Tcontrol / d Nturn = 0  （B が不変の場合）
~~~

5-turn backend と 50-turn backend が同じ control event script を返したとき、workflow transition 列は一致しなければならない。

---

## 10. workflow engine の最小変更

### 10.1 Token kind / Executor

WorkflowToken は現行実装では Kind の自由文字列を許し、集中 validator を持たない。MVP は usage 文書と各 Place の AcceptedKinds に SessionLease、SessionEvent、ResourceSlot、BudgetGrant、ArtifactCandidate、CommitPermit、Failure を追加する。集中 validator を新設する場合はこの集合を初期 canonical 語彙とする。

WorkflowTransition の許容 Executor に "RuntimeSession" を追加する。

~~~wl
iExecuteRuntimeSessionBranch[trans_Association, binding_Association]
~~~

この branch は StartEpisode だけを行い、session loop を同期実行しない。StartSpec と StartCommandId を durable spool へ先に保存してから backend を呼ぶ。Start の retry は (EpisodeId, Attempt, StartCommandId) で冪等にし、process 起動後・Petri token 更新前に crash しても backend は AlreadyStarted を返す。

backend の Started / AlreadyStarted / Failed は engine handler 成否と区別し、正常に取得できた semantic StartResult として EpisodeStartResults place へ produce する。実体は全 lease ref を保持する次世代 SessionLease token の `StartResult` field であり、別 token に resource ownership を移して孤立させない。

~~~wl
"StartResult" -> <|
  "Status" -> "Started" | "AlreadyStarted" | "Failed",
  "HandleRef" -> None | _,
  "BackendInstanceId" -> None | _String,
  "Retryable" -> True | False,
  "FailureClass" -> None | _String,
  "EvidenceRef" -> None | _
|>
~~~

Failed を executor Status = Failed にして atomic rollback だけで終わらせない。HandleStartFailure が retryable/budget/attempt を評価し、retry なら全 resource lease を保持したまま EpisodeAllocated へ、terminal なら EpisodeFailed → CleanupPending へ進めて slot を返す。protocol/schema/transport 自体が壊れて StartResult を作れない場合だけ engine RetryPolicy の handler failure を使い、上限到達時は同じ terminal start failure record を合成する。

既存 Executor = "ClaudeRuntime" は一つの transition 内で閉じる単発 Runtime DAG/turn executor として維持する。新しい "RuntimeSession" は複数 boundary event を持つ長期 episode start 専用であり、既存 executor を deprecate しない。

session event transition は §9.4 の pairing Function を既存 Guard に必ず設定する。Guard は ClaudeEnabledTransitions の binding 列挙後と ClaudeFireTransition の consume 前に再評価される。session net validator は Guard 欠落、非 Function、評価例外を fail-closed で拒否する。

### 10.2 AwaitingLLMTransitions を転用しない

session は複数 control event を発行するため、現行 atomic await entry に格納しない。event bridge は公開 ClaudeSubmitToken[wid, eventToken, "SessionEvents"] を使う。

atomic operation と long-lived session lifecycle を一つの registry に混ぜない。

### 10.3 idempotent external submit

ClaudeSubmitToken に安定 TokenId の重複検査を追加する。ただし engine 側判定は「同じ TokenId が現在の Tokens/marking にある間」の二重投入防止に限定する。consume 後は現行 Tokens registry から消えるため、適用済み event の永続 dedup 正本は §11 の attempt-local delivery-index とする。

~~~text
同じ TokenId が workflow Tokens または marking に存在:
  Status -> Duplicate
  marking を変更しない
~~~

Runtime SessionEvent token ID は EpisodeId、Attempt、EventSeq、EventHash から決定論生成する。SyntheticControlEvent token ID は EpisodeId、Attempt、Source、EventId、EventHash から決定論生成し、EventSeq = None 同士を衝突させない。workflow trace 全走査を通常 dedup 経路にしない。

### 10.4 privacy と snapshot

SessionLease/SessionEvent 由来 token の PrivacyLabel は parent 最大値以上とする。Conductor v0.2 の iProduceOutputTokens 修正を前提 P0 とする。

workflow snapshot の aux sidecar に本文を含まない SessionAttachmentManifest を保存する。

~~~wl
<|"WorkflowId" -> _,
  "Episodes" -> {
    <|"SessionId" -> _, "EpisodeId" -> _, "Attempt" -> _,
      "Backend" -> _, "HandleRef" -> _,
      "LastAppliedEventSeq" -> _,
      "LatestCheckpointRef" -> _,
      "PendingCommandIds" -> {___},
      "EnvironmentLeaseId" -> _,
      "ResourceLeaseIds" -> {___},
      "BudgetLedgerRef" -> _, "SessionSpoolRef" -> _|>
  }|>
~~~

Function、ProcessObject、raw PID は保存しない。

### 10.5 legitimate session wait

EpisodeActive token が存在し、backend event を待っている状態を Stuck と判定してはならない。WorkflowNet に ref-only の ActiveSessionEpisodes registry を追加するか、同等の iHasPendingAsyncWorkQ hook を設ける。

~~~wl
"ActiveSessionEpisodes" -> <|
  episodeId -> <|
    "SessionId" -> _, "Attempt" -> _, "Backend" -> _,
    "HandleRef" -> _,
    "State" -> "Starting" | "Running" | "Suspended" | "Closing"
  |>
|>
~~~

async tick の pending 判定は AwaitingLLMTransitions だけでなく ActiveSessionEpisodes も見る。active entry がある間は workflow status を WaitingExternal または Running に保ち、enabled transition が一時的に無いことだけで Stuck/完了にしない。terminal cleanup 後にだけ entry を除く。

LastAppliedEventSeq と ControlState の正本は EpisodeActive の SessionLease token である。ActiveSessionEpisodes は poll/recovery 対象を列挙する導出 index に限定し、transition 適用時に同じ core 関数から更新する。restore 時は marking と SessionAttachmentManifest を照合し、marking から再構築する。registry を独立した状態正本にしない。

---

## 11. durable event bridge / command outbox

### 11.1 spool layout

~~~text
<session-root>/<session-id>/<episode-id>/
  start-spec.wxf.enc | start-spec.ref
  episode-meta.json
  attempts/<attempt>/
    inbox/<event-seq>-<event-id>.wxf
    synthetic-inbox/<source>-<event-id>.wxf
    outbox/<command-id>.wxf
    delivery-index.wxf
    command-index.wxf
    checkpoints/
    artifacts/
  runtime-trace.ref
  heartbeat.json
  cleanup.json
  quarantine/
~~~

平文 secret、raw prompt、raw response を標準保存しない。start-spec.wxf.enc と checkpoint の鍵管理は externalrunner の SourceVault crypto / SystemCredential backend を流用し、鍵を manifest に保存せず fail-closed とする。ConfidentialHandling = "Redacted" は MVP enum に含めず、必要なら Inc9 で実装してから追加する。

### 11.2 event delivery

ClaudeRuntimeSessionPollTick[] は次を行う。

1. active episode を列挙する。
2. backend PollEvents(handleRef, <|"Attempt"->a, "EventSeq"->n|>) を呼ぶ。
3. event hash、schema、ID、連番、policy hash を検証する。
4. event を inbox に temp → atomic rename で保存する。
5. Delivered = False event から安定 TokenId を作る。
6. ClaudeSubmitToken で SessionEvents place へ入れる。
7. ClaudeSubmitToken の戻り値と現在 marking（必要なら直近一件の trace entry）で TokenId を確認する。全 workflow trace を走査しない。
8. delivery index を Delivered = True にする。

crash 後は 4–8 を再実行する。attempt-local delivery-index が「取得済み・deposit 済み・適用済み」の永続 dedup 正本であり、engine TokenId dedup は deposit 中の補助防壁である。

同一 episode では一度に一個の未適用 control event だけを deposit する。Runtime event の applied は「event transition が SessionEvent token と EpisodeActive lease を consume し、LastAppliedEventSeq を進めた次世代 lease を produce した時点」である。SyntheticControlEvent は LastAppliedEventSeq を進めず、自身の EventId を synthetic delivery-index に Applied と記録する。Observation/approval が人間に解決された時点ではない。従って AwaitingObservation 中でも Runtime seq N は applied 済みであり、seq N+1 の Failed を搬入できる。

通常 event は EventSeq 順に適用する。Failed、Cancelled、EnvironmentLost は terminal preemption を許す。先行 event が schema/hash 不正で quarantine され進行不能な場合、terminal event は SupersedesThroughSeq を明示して適用できる。

preemption 適用時は LastAppliedEventSeq+1 .. SupersedesThroughSeq の各 seq について inbox/quarantine の event ref を列挙する。存在しない seq も MissingEventSeq として delivery-index に明記し、全区間を Superseded にしてから terminal seq を適用する。SupersedesThroughSeq = EventSeq-1 だけを検査して silent gap を許さない。

### 11.2.1 SyntheticControlEvent

次の根拠がある場合だけ合成 event を作れる。

- OrchestratorWatchdog: heartbeat が policy deadline を超え、同一 backend identity の fresh heartbeat/event が無い。
- RecoveryScan: backend Recover が LostUnrecoverable、または verified process identity が消失。
- Bridge: SendCommand の同期戻り値が Rejected。
- quarantine terminal evidence: Runtime terminal event は存在するが schema/hash 破損で通常適用不能。

合成 event を作れるのは orchestrator 内部の watchdog/recovery/bridge generator だけである。generator は durable evidence record を先に作り、その ref を event に格納する。quarantine terminal evidence は RecoveryScan source として生成する。adapter/backend の受信 payload から Source を転記して generator 権限を代用してはならない。

合成判定は episode spool の exclusive lock 内で「最新 Runtime inbox/event cursor 再確認 → synthetic event temp write → atomic rename」を行う。判定中に新しい genuine Runtime event が deposit された場合は合成を中止する。CommandRejected の作成を中止した場合は先着 Runtime event の transition が pending command を Superseded にする。

synthetic terminal 適用後に届いた Runtime event は quarantine/late-events に保存し、Petri net へ deposit しない。terminal episode を再開せず、backend identity、到着時刻、event hash を監査記録する。

### 11.3 command delivery

QueueSessionCommand transition は command を attempt-local outbox に temp → atomic rename で書き、EpisodeActive lease の ControlState を CommandPending にする。MVP は 1 episode につき未解決 command を一個に限定し、GrantBudget と RequestCheckpoint 等を同時発行しない。poll tick は:

1. 未送信または ack 未確認 command を列挙する。
2. backend SendCommand を呼ぶ。
3. Accepted/AlreadyAccepted/Rejected を command-index に記録する。
4. Runtime の CommandAccepted event を待つ。
5. Petri transition が SessionId/EpisodeId/Attempt/CommandId/ExpectedAfterEventSeq を照合して次 state へ戻す。

Rejected の場合は Bridge が EvidenceRef 付き CommandRejected synthetic event を作り、HandleCommandRejected が CommandPending lease を consumeする。旧 command を Superseded とし、OriginControlState または既に到着した最新 Runtime event の state へ戻す。Petri marking を poller が直接 mutation しない。

CommandPending 中に新 Runtime event が先に到着した場合、event transition が pending command を Superseded にして event を通常適用する。後から到着した CommandRejected/CommandAccepted は stale command response として監査保存だけ行う。

transport retry は同じ CommandId を使う。Runtime は Attempt 不一致を Rejected(StaleAttempt)、EventSeq 不一致を Rejected(StaleContext) とする。Stop は stale context 免除とし、二回拒否された場合は新しい Cancel command へ escalation する。

### 11.4 quarantine と有限解放

- event/schema/hash mismatch: episode spool の quarantine/events。
- command stale/rejected: quarantine/commands。
- identity 未確認 process: quarantine/processes。
- reservation/tool effect 未確定: quarantine/reconciliation。

ClaudeRecoverRuntimeSessions が再検証・reconcile の主体である。各 entry は Reason、FirstSeenAt、LastCheckedAt、RequiredEvidence、LeaseIds、ReservationIds、ExpiresAt を持つ。既定 quarantine 期限は 24 時間、秘密を含む staging retention は policy がより短い値を優先する。

期限までに provider/tool/process の確定情報を得られない場合は、cash reservation は保守的に実績扱い、non-idempotent effect は EffectUncertain、process は identity 未確認のため kill せず operator alert として閉じる。environment/resource lease は QuarantineReleased event を記録して高々一回返却する。I10 に加え、全 lease が policy 上限時間内に Released または QuarantineReleased へ到達することを運用不変条件 I14 とする。

### 11.5 poll tick 実行契約

ClaudeRuntimeInKernel の内部 loop は既存 Runtime の LLMGraph DAG onComplete、iAsyncExecutionTickFn、iAsyncToolExecTickFn が駆動する。ClaudeRuntimeSessionPollTick は event/command file I/O、schema/hash 検証、token deposit だけを行い、model call、tool execution、NotebookWrite、Dynamic/FrontEnd 操作を同期実行しない。

- tick 一回の soft wall-clock 上限: 200ms。超過時は残件を次 tick へ。
- process-global reentry guard: 前 tick 実行中なら新 tick は SkippedBusy。
- shared polling service に登録し、Runtime/external/session tick の起動・停止・診断を一元化。
- callback 内の同期 network/IMAP/process wait を禁止。
- notebook commit は poll tick でなく FinalActionQueue/committer が行う。

---

## 12. ClaudeRuntime session facade

### 12.1 Runtime 公開 API

~~~wl
ClaudeRuntimeOpenSession[startSpec_Association]
ClaudeRuntimeStartEpisode[sessionId_String, episodeSpec_Association]
ClaudeRuntimeSessionPoll[sessionId_String, cursor_Association]
ClaudeRuntimeSessionCommand[sessionId_String, command_Association]
ClaudeRuntimeSessionCheckpoint[sessionId_String, opts___Rule]
ClaudeRuntimeResumeSession[checkpointRef_, startSpec_Association]
ClaudeRuntimeStopSession[sessionId_String, reason_String]
ClaudeRuntimeSessionInfo[sessionId_String]
ClaudeRuntimeSessionBackendSpec[]
ClaudeRegisterRuntimeAdapterFactory[name_String, fn_]
~~~

Orchestrator は ClaudeRuntime Private symbols や $iClaudeRuntimes を直接参照しない。

### 12.2 現行 Runtime との mapping

| Session facade | 現行 Runtime の利用 |
|---|---|
| Open | adapter factory → CreateClaudeRuntime |
| StartEpisode | ClaudeRunTurn(runtimeId, initialInput) を一度起動 |
| internal continuation | Runtime 自身の ShouldContinue / ClaudeContinueTurn / tool loop |
| proposal approval boundary | 既存 Runtime AwaitingApproval を control event 化 |
| tool approval boundary | **新設** pre-execution tool gate が ToolCallId 付き ApprovalRequired を発行して suspend |
| budget boundary | **新設** suspend/grant/versioned limit update/resume state machine。既存 BudgetExhausted event は移行時の検出信号にのみ利用 |
| artifact boundary | final redacted result を staging artifact 化して ArtifactProposed |
| checkpoint | **新設** routine/boundary checkpoint export と durable manifest |
| resume | adapter factory で新 runtime を作り narrow state import |
| stop/cancel | Runtime cancel API + checkpoint + terminal event |

### 12.3 内部 loop

最初の turn だけを facade が起動し、以後の continuation は Runtime 内部で行う。Orchestrator が turn ごとに ClaudeContinueTurn を呼ばない。

ClaudeRuntimeInKernel ではこの継続を §11.5 の既存 Runtime async tick 群が駆動する。session poll tick は loop pump ではなく境界 event 搬送だけを担当する。

Runtime は次のときだけ control event を発行して pause する。

- 未許可 effect/tool の実行前
- 外部 observation がないと継続できない
- checkpoint の外部確定が必要
- 次の action が budget hard limit を超える
- artifact candidate の外部検証が必要
- terminal completion/failure/cancel

### 12.4 tool loop

pre-authorized tool call は Runtime 内で完結する。ただし各 call は:

1. ToolCallId と idempotency key を発行。
2. NBAccess で AccessSpec を検証。
3. budget reservation。
4. tool journal に Prepared を記録。
5. effect を実行。
6. result ref と usage を記録。
7. journal を Committed または Failed にする。

許可外 tool は実行せず ApprovalRequired を発行する。

ToolCallId 発行、pre-execution NBAccess gate、budget reservation、Prepared/Committed/Failed effect journal、privacy taint は現行 tool loop に存在しない新設機能であり、sync fallback と AsyncToolExec の全実行経路を共通 wrapper へ集約してから適用する。片方の経路だけを保護してはならない。

### 12.5 Runtime event journal

Runtime は control event を発行前に自身の durable journal に保存する。EventSeq は同一 attempt 内で単調増加する。MVP では Attempt が増えた場合に EventSeq を 1 から再開し、dedup key を (EpisodeId, Attempt, EventSeq) とする。

---

## 13. observation と approval

### 13.1 ObservationRequired

Runtime が外部情報を必要とするとき:

~~~wl
"PayloadRefs" -> <|
  "ObservationKind" ->
      "HumanInput" | "ExternalDependency" | "ArtifactReview" |
      "CredentialAvailability" | "EnvironmentChange",
  "QuestionRef" -> _,
  "ExpectedSchema" -> _,
  "ResumeHintRef" -> _,
  "ExpiresAt" -> _DateObject,
  "OnExpiry" -> "FinalizePartial" | "Fail" | "Cancel"
|>
~~~

Orchestrator は deterministic resolver、別 ExternalJob、人間入力のいずれかで observation ref を作り、ProvideObservation command を送る。

Runtime の MaxIdleSeconds は Runtime が実行可能なのに進捗がない時間だけを測る。AwaitingObservation/AwaitingApproval 中は Runtime idle clock を停止し、Orchestrator が ExpiresAt を所有する。期限切れは OnExpiry の transition を発火し、放棄 session が lease を無期限保持しない。

### 13.2 ApprovalRequired

approval event は action 実行前に発行する。

~~~wl
"PayloadRefs" -> <|
  "ToolCallId" -> _,
  "ActionSummaryRef" -> _,
  "RequestedEffectClasses" -> {___},
  "RequestedResourceRefs" -> {___},
  "ApprovalEligibility" ->
      "AskUserAllowed" | "HardDeny" | "RepairRequired",
  "ExpiresAt" -> _,
  "OnExpiry" -> "DenyAndRepair" | "DenyAndFail" | "Cancel"
|>
~~~

- HardDeny: approval UI を出さず failure/repair。
- AskUserAllowed: EpisodeActive lease を ControlState = AwaitingApproval にして滞留。
- Allow: GrantScopedApproval command。
- Deny: RepairArtifact または Stop command。
- ExpiresAt 到達: 新規 billable/tool action を開始せず、OnExpiry を正本として DenyAndRepair、DenyAndFail、Cancel のいずれかを一度だけ発火。OnExpiry 欠落・未知値は fail-closed の DenyAndFail とする。

grant は session 全体ではなく ToolCallId、resource、effect、期限を限定する。

### 13.3 approval と durable completion の階層正本

- run/workflow step の開始、frontier unlock、run-level budget extension: Conductor/Workflow approval が正本。
- episode 内の一 tool/action/artifact に対する承認: 本仕様の scoped approval が正本。
- episode approval は ApprovalId、ApprovalScope = "RuntimeSessionAction"、EpisodeId、ToolCallId を run-level PendingApprovals view に集約表示する。
- Conductor が存在する場合、ユーザーは ClaudeApproveWorkflow 系の統一 UI から dispatch し、ClaudeRuntimeSessionApprove は内部 delegate とする。
- Conductor 無しで episode net を直接使う場合だけ session API を公開入口にできる。

episode 完了の正本は commit receipt と Completed event、run 完了の正本は Conductor Finalize transition である。episode completion hook だけで run を成功にしない。run Finalize は全 child episode の terminal record と未解決 approval/lease が無いことを検査する。

---

## 14. budget 制御

### 14.1 二重 enforcement

~~~text
Runtime local guard:
  次の model/tool action の直前に即時停止できる

Orchestrator ledger:
  複数 session、provider usage、cash reservation、全 run 上限を統合する
~~~

Runtime が Orchestrator poll を待たずに暴走しないため local guard は必須である。一方、Runtime 自己申告だけに依存しないため Orchestrator ledger も必須である。

### 14.2 action reservation

billable action の前に Runtime は worst-case または policy quantile を予約する。

~~~text
ActualUSD + ReservedUSD + NewReservationUSD <= MaxCostUSD
UsedCounter[k] + ReservedCounter[k] + NewReservation[k] <= HardLimits[k]
~~~

成立しない場合は action を開始せず、safe checkpoint を作って BudgetInterrupt を発行する。

### 14.3 BudgetInterrupt

~~~wl
"PayloadRefs" -> <|
  "LimitKind" -> "Turns" | "ToolCalls" | "Tokens" |
                 "Cash" | "WallClock" | "Bytes" | "UnknownCost",
  "PendingActionSummaryRef" -> _,
  "MinimumAdditionalGrant" -> _,
  "DegradeOptions" -> {"CheaperModel", "DisableTool", "FinalizePartial"},
  "LatestCheckpointRef" -> _
|>
~~~

Orchestrator の分岐:

1. StopAndFinalizePartial
2. DegradeAndContinue
3. RequireApprovalForExtension
4. DenyAndFail

追加 grant は version を増やし、差分ではなく新しい累積上限を送る。

### 14.4 hard cap の意味

provider が最大 output token を強制でき、worst-case 単価が分かる場合だけ strict cash bound とする。P95 見積しかない場合は ProbabilisticIssuanceCap と記録する。既発行 call の timeout/cancel は課金を取り消さない。

### 14.5 session 再利用時

将来 session を再利用する場合は episode hard limit、session cumulative hard limit、run aggregate hard limitを全て満たす必要がある。新 episode で counter を無条件 reset しない。

episode BudgetSnapshot は conductor run ledger の子台帳である。run ledger が予算の外側上限と provider usage reconciliation を所有し、episode ledger は自 episode の action 発行 guard を所有する。同じ usage event を CallId/ReservationId で dedup し、episode → run の一方向集約とする。

---

## 15. checkpoint と recovery

### 15.1 checkpoint 作成

Runtime:

1. 新しい billable/tool action を止める。
2. in-flight tool を safe point まで待つか、cancel-safe なものだけ cancel。
3. tool journal を flush。
4. conversation state、environment overlay、artifact staging manifest を ref 化。
5. manifest hash を作る。
6. temp → atomic rename で保存。
7. boundary checkpoint なら CheckpointCreated event を発行。routine checkpoint は journal と LatestRoutineCheckpointRef だけを更新。

Orchestrator:

1. ref が episode spool/staging policy 内にあることを確認。
2. schema、hash、Session/Episode/Attempt、policy hash を確認。
3. BudgetSnapshot が ledger より後退していないことを確認。
4. LatestCheckpointRef を次世代 SessionLease token に記録。

### 15.2 workflow restore

1. WorkflowNet と SessionAttachmentManifest を読む。
2. backend registry を通常 package load で再構築。
3. command outbox / event inbox を scan。
4. backend Recover(episodeRecord) を呼ぶ。
5. alive + identity verified なら reattach。
6. dead + valid checkpoint なら Attempt + 1 で resume。
7. checkpoint なしで non-idempotent effect の可能性があれば NeedsRestartApproval。ApprovalId、ExpiresAt、OnExpiry を持つ durable approval record を作り、期限切れ時は OnExpiry = DenyAndFail（明示 policy がより厳しければそれ）を一度だけ適用する。
8. unrecoverable なら EnvironmentLost/Failed event を投入。

### 15.3 tool effect journal

~~~text
Prepared:
  effect 実行有無が不明。自動再実行禁止。

Committed:
  result ref を再利用し、再実行しない。

FailedBeforeEffect:
  retry policy が許せば再実行可能。

Compensated:
  compensation 済み。新 attempt で再計画可能。
~~~

Prepared の non-idempotent tool がある checkpoint は自動 resume せず approval を要求する。

### 15.4 resume 時の reservation reconciliation

Attempt+1 を起動する前に checkpoint の ReservedUSD/各 ReservedCounter と tool/call journal を照合する。

- provider usage event 到着済み: ActualUSD/実績 counter へ精算し予約を解放。
- FailedBeforeEffect または発行前停止を証明: 予約を解放。
- Committed effect: result/usage ref を再利用し二重発行しない。
- Prepared または in-flight で実行有無不明: reservation を Held のまま継承。
- reconciliation timeout まで不明: policy に従い保守的に actual 扱い、または operator approval。0 扱いは禁止。

ReservedUSD は attempt 境界で reset せず、ReservationId ごとに reconcile する。累積 counter と ActualUSD は checkpoint と run ledger の大きい方を採用し、後退を許さない。

### 15.5 互換性

SchemaVersion、Runtime version、AdapterFactory version、model/provider version を記録する。major schema 不一致は silent migration せず、明示 migrator または failure にする。

---

## 16. environment isolation と access policy

### 16.1 environment lease

episode 開始前に Orchestrator が次を固定する。

- unique staging directory
- base snapshot/reference
- allowed read roots
- writable staging root
- network allowlist
- external command allowlist
- cleanup policy
- isolation level

### 16.2 書込み境界

Runtime が書けるのは WritableStagingRoot のみ。次は禁止する。

- target package file への直接 write
- target notebook への NotebookWrite
- EvaluationNotebook[] 依存
- final artifact ref の差替え
- staging root 外への temporary file

例外は single committer transition だけである。

### 16.3 ToolPolicy

~~~wl
<|
  "Tool" -> "ReadFile",
  "EffectClass" -> "FileRead",
  "ResourcePattern" -> _,
  "Decision" -> "Permit" | "NeedsApproval" | "Deny",
  "MaxCalls" -> _, "MaxBytes" -> _,
  "NetworkTargets" -> {___}
|>
~~~

Runtime が別名 tool を登録して policy を迂回しないよう、最終判断は NBAccess の canonical effect class で行う。

session 語彙から NBAccess への対応:

| Session tool intent | NBAccess canonical / AccessSpec |
|---|---|
| PureCompute | PureComputation |
| FileRead | ReadOnlyFileSystem + MayAccessFileSystem = "ReadOnly" |
| FileWriteStaging | **新設** ScopedFileSystemMutation + MayAccessFileSystem = "ScopedReadWrite" + AllowedDirectories = {WritableStagingRoot} |
| Network | NetworkAccess + AllowedNetworkTargets |
| ExternalCommand | ExternalProcess + AllowedExternalCommands |
| NotebookWrite | NotebookMutation。worker では Deny、committer だけ Ask/Permit |
| Desktop | DesktopAction。worker/headless では Deny |
| CredentialUse | CredentialRefs/SecretRefs を NBAccess が scoped resolve。secret 本体は Runtime に渡さない |

canonical 語彙は NBAccess 側を正本とする。ScopedFileSystemMutation、WritableStagingRoot と ToolCallId 単位 scoped permit は NBAccess の新設範囲であり、現行機能とみなさない。全 filesystem tool は実 path を canonicalize した後、symlink/reparse traversal を含め staging root 内包を検査する。

### 16.4 privacy taint

- PrivacyLabel は conductor/NBAccess と同一の 0.0 以上 1.0 以下の scale を用い、大きいほど private とする。
- cloud 境界は既定 0.5。unknown/欠落/非数値は 1.0 へ fail-closed。
- 混在 input の label は Max、worker clearance/trust ceiling との比較も同じ向きで行う。
- session memory の privacy label は読んだ input/artifact/tool result の最大値へ単調増加する。
- session 再利用時は label を下げない。
- event、checkpoint、artifact candidate はその時点の session label 以上を持つ。
- cloud backend は InferenceTrustDomain gate を通る。
- raw private trace は cloud tuner/evaluator に渡さない。

---

## 17. artifact boundary と single commit

### 17.1 ArtifactProposed handshake

Runtime は final target を変更せず、staging artifact を作って ArtifactProposed event を発行し、SuspendedForArtifactDecision になる。

Orchestrator は次を検査する。

1. ArtifactContract の type/schema
2. ref が許可 staging root 内か
3. content hash / byte limit
4. privacy label
5. provenance と input refs
6. deterministic checks
7. base revision / optimistic concurrency
8. forbidden effect または secret 混入

### 17.2 validation failure

- repair 可能かつ budget が残る: verifier feedback ref を作り RepairArtifact command。
- policy violation が scoped approval で解決可能: approval。
- hard violation: terminal failure。

Runtime は repair command で内部 loop を再開する。Petri net は repair の各 turn を管理しない。

### 17.3 commit

validation pass 後に CommitPermit token を一個だけ作る。CommitPermit は CommitId、ArtifactId、validated content hash、base revision、target ref に束縛した single-use token とする。commit transition は成功・失敗を問わず commit 試行開始時に permit を consume し、同じ permit の再利用を拒否する。失敗後の再試行は artifact/base revision を再検証し、新しい CommitId と CommitPermit を発行する。

- Notebook: FinalActionQueue / fixed target notebook
- Files: PackageManager または専用 committer、atomic rename、base revision CAS
- ArtifactStore: content-addressed deposit

現行 workflow engine の PackageManager executor branch は stub である。Files commit にそれを使う場合、Inc8 の依存作業として実装する。代替は明示登録された専用 committer Function であり、stub を成功扱いしない。

CommitMode = "Notebook" は FrontEndAvailable、NotebookCommit capability、固定 TargetNotebook、completion-aware FinalActionQueue の全条件を要求する。headless/session runner 自身は Notebook mode を実行しない。

commit receipt:

~~~wl
<|
  "CommitId" -> _, "ArtifactId" -> _, "TargetRef" -> _,
  "PreviousRevision" -> _, "NewRevision" -> _,
  "CommittedAt" -> _, "ContentHash" -> _
|>
~~~

receipt 永続化成功後にのみ成功 path へ進む。completion hook だけに依存しない。

Notebook commit の API contract は「enqueue 成功」ではなく、FinalAction 実行完了、書込み結果/新 revision の検証、CommitReceipt の durable 保存までを非同期 committer job として待てることを要求する。enqueue receipt を commit receipt と呼ばない。

commit 成功後 AcceptArtifact command に CommitReceiptRef を付ける。Runtime は最終 checkpoint/trace を閉じて Completed event を発行する。Completed transition は durable CommitReceipt を再読込検証してから terminal token を作る。commit 失敗時は RepairArtifact または Stop を送る。

CommitReceipt の durable 保存後、AcceptArtifact/Completed より前に Runtime が回復不能になった場合は `CommittedButSessionLost` terminal record を作る。ArtifactDisposition は `CommittedValid`、CommitReceiptRef は必須とし、target を rollback しない。Conductor は同じ ArtifactContract を未達として再生成・再 commit してはならず、receipt と target revision の照合後に成果物を受理するか、session 後処理だけを別 episode として計画する。

---

## 18. failure、cancel、timeout

### 18.1 failure taxonomy

~~~text
RuntimeTransient
ProviderRateLimit
ToolTransient
ToolEffectUncertain
BudgetInterrupted
ApprovalDenied
PolicyViolation
CheckpointInvalid
EnvironmentLost
ArtifactInvalid
CommitConflict
CommitFailed
CommittedButSessionLost
BackendUnavailable
SessionLostUnrecoverable
Cancelled
~~~

PolicyViolation、secret leak risk、hard deny は別 worker への silent fallback を行わない。

terminal 処理では durable CommitReceiptRef の存在を先に検査する。receipt と target revision が一致する場合、Runtime loss を通常の SessionLostUnrecoverable に潰さず CommittedButSessionLost とし、artifact disposition を CommittedValid に固定する。

### 18.2 retry 条件

自動 retry は全条件 AND:

~~~text
failure が retryable
budget が残る
valid checkpoint がある、または start 前 failure
未確定 non-idempotent effect がない
access/policy snapshot が有効
Attempt < MaxAttempts
~~~

retry は新 Attempt として行う。古い attempt の event は pairing guard で除外する。

### 18.3 cancel protocol

1. Orchestrator が Cancel command を durable outbox に書く。
2. Runtime は新 action を止める。
3. checkpoint policy が許せば最終 checkpoint。
4. in-flight cancel-safe tool/model call を cancel。
5. Cancelled event を発行。
6. Orchestrator が backend dispose。
7. process identity を確認し、grace 後も残る場合だけ kill。
8. cleanup を検証して resource lease を返す。

ack が無いまま kill した session は Quarantined とし、reconciliation と orphan recovery が終わるまで cash/environment lease を即時解放しない。

### 18.4 timeout ownership

- model/tool 個別 timeout: Runtime
- episode wall-clock/idle timeout: Runtime local guard + Orchestrator watchdog
- process kill grace: external backend
- workflow MaxWait: Orchestrator UI/wait API

同じ timeout を engine timer と backend poller の二者が成功 callback として処理しない。session timeout は BudgetInterrupt または terminal failure event とする。

---

## 19. persistence と observability

### 19.1 正本

~~~text
Petri marking + immutable workflow trace:
  orchestration control state の正本

Runtime control event journal:
  backend event の正本

Command outbox:
  Orchestrator command の正本

Provider/tool usage event:
  budget accounting の正本

SessionView / EpisodeRecord:
  上記から再構築できる派生 view
~~~

mutable な EpisodeRecord 一個だけを唯一の正本にしない。

### 19.2 EpisodeView

~~~wl
<|
  "WorkflowId" -> _, "RunId" -> _, "TaskId" -> _,
  "SessionId" -> _, "EpisodeId" -> _, "Attempt" -> _,
  "ControlState" -> _, "Backend" -> _, "IsolationLevel" -> _,
  "LastAppliedEventSeq" -> _, "LastHeartbeatAt" -> _,
  "LatestCheckpointRef" -> _,
  "BudgetSnapshot" -> _, "BudgetRemaining" -> _,
  "PendingApproval" -> _, "PendingCommandIds" -> _,
  "ArtifactCandidateRef" -> _, "CommitReceiptRef" -> _,
  "RuntimeTraceRef" -> _, "PrivacyLabel" -> _,
  "Warnings" -> {___}
|>
~~~

### 19.3 CallContext

episode 内の provider call は次を持つ。

~~~wl
<|
  "RunId" -> _, "WorkflowId" -> _, "TaskId" -> _,
  "SessionId" -> _, "EpisodeId" -> _, "Attempt" -> _,
  "TurnIndex" -> _, "ToolCallId" -> None | _,
  "Provider" -> _, "Model" -> _, "ReservationId" -> _
|>
~~~

Orchestrator は各 call を transition にしないが、ledger 帰属は失わない。

### 19.4 retention

- Orchestrator trace: control event の type、ID、counter、ref
- Runtime trace: model/tool の監査可能な summary と usage
- raw chain-of-thought: 保存しない
- raw prompt/response: policy が明示許可した場合だけ encrypted/ref-only
- free text error: redaction 後の ref

---

## 20. Conductor / TaskSpec 統合

### 20.1 TaskNodeSpec 拡張

~~~wl
<|
  "TaskId" -> _, "Role" -> _, "Goal" -> _,
  "Inputs" -> _, "Outputs" -> _, "Capabilities" -> _,
  "DependsOn" -> _, "ExpectedArtifactType" -> _,
  "WorkerKind" -> "RuntimeSession",
  "SessionProfile" -> <|
    "Backend" -> Automatic | _String,
    "ReusePolicy" -> "Never",
    "IsolationRequired" -> "ExternalProcess" | "CooperativeKernel",
    "ToolPolicyRef" -> _, "BudgetGrantRef" -> _,
    "EnvironmentSpecRef" -> _,
    "CheckpointPolicyRef" -> _
  |>
|>
~~~

WorkerKind = "LLMCall" は従来の atomic AwaitingLLM transition に compile する。WorkerKind = "RuntimeSession" は本仕様の episode supervisor subnet に compile する。TaskNode 一個を turn 数だけ複製しない。

SessionProfile の canonical field は本仕様の ToolPolicyRef / BudgetGrantRef / EnvironmentSpecRef / CheckpointPolicyRef とする。conductor の予約語 TurnBudget / ToolPolicy / EnvironmentRef は compiler adapter でこれらへ正規化し、次版で語彙を統一する。

### 20.2 role mapping

本仕様は既存 TaskSpec role を受け、Conductor compile 時に次へ正規化する。

| multi-agent TaskSpec | conductor role | episode の扱い |
|---|---|---|
| Explore | solve | read/retrieval session |
| Plan | plan | planning artifact |
| Draft | solve | draft artifact |
| Verify | verify | checker/tool session |
| Reduce | synthesize | artifact synthesis |
| Commit | なし | worker session にせず single committer transition |

未知 role は general/solve へ silent 縮退せず validation error または明示 domain mapping を要求する。

### 20.3 heterogeneous binding

resolver は次を filter/rank する。

- required tools/capabilities
- privacy / InferenceTrustDomain
- isolation level
- checkpoint/resume capability
- environment availability
- SeatBroker / license probe が返す現在の process/subkernel seat availability
- budget/cost/latency
- model family と過去 domain success

worker の異種性は model 名だけでなく tool/environment/session capability を含む。

SessionSlots/EnvironmentSlots は静的定数だけにしない。external Wolfram process は SeatBroker または SourceVault diagnostics の seat probe から lease token を発行し、process start 成功時に占有、verified dispose/recovery 後に返却する。席不足時は policy が許せば in-kernel/subkernel backend へ明示降格し、許さなければ EpisodeRequested で待機する。silent に 5 本目等を起動しない。

### 20.4 replan boundary

episode 内の局所 repair は Runtime が行う。Task DAG を変える replan は episode terminal failure、または artifact validation failure が局所 repair 不能と判定された場合だけ Conductor/RunController が行う。

---

## 21. 公開 API 案

### 21.1 Orchestrator

~~~wl
ClaudeCreateRuntimeSessionEpisodeNet[taskSpec_Association, opts___Rule]
ClaudeStartRuntimeSessionEpisode[wid_String, opts___Rule]
ClaudeRuntimeSessionEpisodeInfo[wid_String, episodeId_String]
ClaudeRuntimeSessionEpisodes[wid_String]
ClaudeRuntimeSessionPollTick[]
ClaudeRuntimeSessionApprove[wid_String, episodeId_String, approvalId_String]
ClaudeRuntimeSessionDeny[wid_String, episodeId_String, approvalId_String]
ClaudeRuntimeSessionGrantBudget[wid_String, episodeId_String, grant_Association]
ClaudeRuntimeSessionProvideObservation[wid_String, episodeId_String, observationRef_]
ClaudeRuntimeSessionRequestCheckpoint[wid_String, episodeId_String]
ClaudeRuntimeSessionCancel[wid_String, episodeId_String, reason_String]
ClaudeRecoverRuntimeSessions[opts___Rule]

ClaudeRegisterRuntimeSessionBackend[name_String, backend_Association]
ClaudeRuntimeSessionBackends[]
ClaudeRuntimeSessionBackendInfo[name_String]
~~~

ユーザー API は command を backend へ直接送らず、必ず Petri transition/outbox を経由する。

### 21.2 core internal

~~~wl
iCondBuildSessionStartSpec[taskSpec_, requirement_, binding_]
iCondValidateSessionEvent[event_, lease_]
iCondQueueSessionCommand[lease_, command_]
iCondDepositSessionEvent[wid_, event_]
iCondResolveSessionBoundary[event_, lease_]
iCondValidateCheckpoint[manifest_, lease_]
iCondValidateArtifactCandidate[candidate_, contract_]
iCondReleaseLeaseOnce[leaseId_]
~~~

### 21.3 compatibility

- 既存 ClaudeRunOrchestration は変更しない。
- 既存 LLMCall workflow は変更しない。
- AwaitingLLMTransitions と external job poller は維持する。
- RuntimeSession は新 WorkerKind/Executor を使うときだけ有効な純加法とする。
- 既存 LLMCall worker の ArtifactSpec(Status + inline Payload)を episode 入力に使う場合、size/privacy gate 後に Payload を ArtifactStore へ materialize し、ArtifactRef/ContentHash/PrivacyLabel を持つ ArtifactCandidate-compatible ref へ変換する adapter を一箇所だけ設ける。episode 出力を legacy inline ArtifactSpec へ逆変換することは既定禁止とする。

---

## 22. ファイル分割

| ファイル | 追加内容 |
|---|---|
| ClaudeOrchestrator_workflow.wl | Token kind、RuntimeSession executor、idempotent submit、snapshot aux hook |
| 新規 ClaudeOrchestrator_session.wl | backend registry、episode net、event bridge、command outbox、views/API |
| ClaudeRuntime.wl | narrow checkpoint import/export hook、budget/trace 不足分 |
| 新規 ClaudeRuntime_session.wl | session facade、state mapping、event journal、adapter factory registry |
| ClaudeRuntime_externalrunner.wl | process identity/recovery primitive 再利用 |
| 新規 ClaudeRuntime_sessionrunner.wl | long-lived external session process、command/event spool |
| NBAccess.wl | session ToolPolicy、staging root、scoped ToolCallId permit |
| claudecode.wl / wiring file | backend spec と poll tick の登録、UI facade |
| ClaudeOrchestrator_observability.wl | EpisodeView、budget/control event 集計 |
| test codes | session/runtime/runner tests |

依存規則:

~~~text
ClaudeOrchestrator_session -> ClaudeOrchestrator_workflow
ClaudeOrchestrator_session -> public ClaudeRuntime backend spec only
ClaudeRuntime_session -X-> ClaudeOrchestrator
NBAccess -X-> Runtime / Orchestrator
snapshot -X-> Function / ProcessObject
~~~

---

## 23. 実装インクリメント

### Inc0: 前提安全修正

- privacy taint 単調伝播
- ExecutionLocation / InferenceTrustDomain 分離
- immutable CallContext
- provider usage/cost の request-scoped 帰属

本 Inc0 は conductor v0.2 Inc0A + Inc0B に対応する。conductor Inc0C の run reservation ledger/status/counter は本仕様 Inc5 の episode ledger と親子接続し、Inc0D の run-level approval-resume/durable Finalize は §13.3/§17 の episode-level approval/commit receipt と階層化する。同じ機構を別正本として二重実装しない。

受け入れ:

- private artifact 由来 session が cloud trust gate を迂回しない。
- session 内 call の Run/Workflow/Task/Session/Episode 帰属が completion 順に依存しない。

### Inc1: schema と MockRuntimeSession

- §7 schema validator
- backend registry
- event/command hash と ID generator
- AccessSpec canonical hash と共通 recursive canonicalizer
- Attempt-scoped command/event/cursor schema
- Runtime event と名前空間を分けた SyntheticControlEvent、EvidenceRef、SyntheticBaseEventSeq
- event script を返す mock backend

受け入れ:

- invalid schema/policy hash/event gap を fail-closed で拒否。
- 同じ StartCommandId を二回送っても一 session だけ作る。

### Inc2: episode supervisor net

- net builder
- 単一 EpisodeActive place、SessionLease/SessionEvent/resource places
- RuntimeSession executor branch
- 既存 WorkflowTransition Guard を使う pairing
- event × ControlState routing/terminal/cancel transitions（stateAllowedQ を Guard に含める）
- EpisodeStartResults、HandleStartFailure、HandleCommandRejected

受け入れ:

- 5-turn mock と 50-turn mock の workflow transition 列が一致。
- control event が来るまで legitimate waiting と認識され、Stuck 終端にならない。
- 複数 episode の event が誤 pairing されない。
- 交差 binding は Guard 段階で除外され、どの token も consume されない。
- 全 ControlState から Failed/Cancelled/EnvironmentLost/Cancel が到達可能。

### Inc3: durable inbox/outbox と dedup

- spool layout
- poll tick
- idempotent ClaudeSubmitToken
- command outbox/ack
- replay/recovery
- watchdog/recovery scan による synthetic terminal event と genuine event 競合時の spool lock/recheck
- tick reentry guard と shared polling service 登録

受け入れ:

- event 保存後/token 投入前 crash、token 投入後/index 更新前 crash の双方で token は一個。
- command ack 保存前 crash でも effect は一回。
- EventSeq gap は後続 event を適用せず再取得する。
- stale attempt command を Rejected(StaleAttempt) にする。
- terminal preemption で superseded event が監査記録される。
- command reject または先着 Runtime boundary event で CommandPending が必ず解消される。
- silent/dead Runtime でも evidence 付き synthetic terminal event により lease release へ到達する。

### Inc4: ClaudeRuntime in-kernel facade

- public session API
- existing Runtime turn/tool loop mapping
- adapter factory registry
- control event journal
- read-only/cooperative backend
- 既存 Runtime async tick による loop pump と event-only session poll tick
- pre-execution tool approval gate、ToolCallId、Runtime privacy state

受け入れ:

- Orchestrator は $iClaudeRuntimes と Private symbols を参照しない。
- 10 tool iteration が内部で完結し、Petri には boundary event だけが現れる。
- 許可外 tool は pre-execution gate で未実行のまま AwaitingApproval になり、既存 proposal approval と区別される。
- session poll tick は 200ms 上限、再入時 SkippedBusy、同期 model/tool/NotebookWrite を行わない。

### Inc5: budget dual enforcement

- BudgetGrant/BudgetSnapshot
- model/tool action reservation
- Orchestrator ledger reconciliation
- BudgetInterrupt/GrantBudget
- **新設** BudgetSuspended state、versioned grant 受理、limit 差替え、同一 episode resume

受け入れ:

- MaxToolCalls 到達後に追加 tool が一件も開始されない。
- unknown cash cost が MaxCostUSD 下で fail-open しない。
- stale BudgetGrant version を拒否。
- extension は同じ episode を再開し、別 session を暗黙起動しない。
- crash/resume の reservation を ReservationId 単位で reconcile し、不明を 0 にしない。

### Inc6: durable checkpoint/resume

- checkpoint manifest/export/import
- routine/boundary checkpoint 分離
- sync/async 全 tool 経路の effect journal
- workflow snapshot attachment
- reattach/resume decision

受け入れ:

- checkpoint 後に kernel を落としても valid ref から Attempt+1 で再開。
- Committed tool effect を再実行しない。
- Prepared non-idempotent effect は approval 無しに再実行しない。
- policy/budget counters は resume で後退しない。
- routine checkpoint 数は Petri transition 数を増やさない。

### Inc7: environment / access enforcement

- environment lease
- staging root
- ToolPolicy と scoped permit
- isolation requirement gate
- NBAccess ScopedFileSystemMutation、WritableStagingRoot、ToolCallId permit

受け入れ:

- runtime から target notebook/package への直接 write を拒否。
- allowed root 外 write、許可外 network/command を拒否。
- approval は ToolCallId 一件だけを解禁。
- CooperativeKernel が hard isolation 必須 task に選ばれない。

### Inc8: artifact validation / single commit

- ArtifactContract/Candidate
- deterministic validators
- CommitPermit
- commit receipt と Runtime ack
- CommitPermit の attempt ごとの consume と再検証後の再発行
- CommittedButSessionLost terminal record と CommittedValid artifact disposition
- PackageManager executor または専用 files committer の実装
- completion-aware FinalActionQueue と NotebookCommit capability gate

受け入れ:

- invalid artifact は target を変更しない。
- commit transition 以外に final write capability がない。
- duplicate ArtifactProposed/commit retry でも一度だけ commit。
- base revision conflict は上書きせず repair/failure へ。
- commit 後に Runtime が失われても target を rollback/重複生成せず、receipt から成果物を受理できる。
- 失敗した commit で消費した CommitPermit は再利用できない。

### Inc9: external process session runner

- long-lived runner
- command/event spool
- PID identity
- cancel/grace/kill
- orphan recovery
- encrypted/ref-only checkpoint/artifact
- SeatBroker/license probe と動的 SessionSlots

受け入れ:

- main kernel abort 後に alive session を reattach または checkpoint resume。
- 別 PID を誤 kill しない。
- orphan cleanup 後まで resource/cash reservation を二重解放しない。
- raw secret/prompt/artifact 本文が manifest/status に出ない。
- seat 飽和時に上限を超える process を起動せず、待機または明示降格する。

### Inc10: heterogeneous backend と session reuse

前提:

- Inc1–9 の safety test が green
- 1 episode/session の価値が確認済み
- memory contamination/privacy benchmark がある

受け入れ:

- 異なる trust domain 間で session reuse しない。
- 新 episode で累積 budget/privacy label が reset されない。

---

## 24. テスト仕様

### 24.1 unit

- 全 schema validator
- EventSeq/EventHash/CommandId dedup
- BudgetGrant version/hash
- event/lease pairing guard
- checkpoint manifest
- ArtifactContract/Candidate
- lease release idempotency
- backend capability filter
- pairing Guard の非 Function/例外/非 True fail-closed と二回評価の決定性
- SyntheticControlEvent の source/evidence/base sequence validator
- CommitPermit の CommitId/artifact/hash/base revision binding と single-use validator

### 24.2 Petri integration

1. start → 50 internal turns → artifact → commit → cleanup
2. observation required → observation command → resume
3. approval required → deny → repair/stop
4. checkpoint event → record → continue
5. budget interrupt → extension approval → same episode resume
6. artifact validation fail → repair → second candidate
7. commit conflict → target 不変
8. failed session → checkpoint resume
9. cancel → ack → cleanup
10. multiple sessions + limited slots
11. 全 ControlState × {Failed, Cancelled, EnvironmentLost} の到達性
12. 全 ControlState から Cancel → Cancelling → terminal → lease release
13. AwaitingObservation 中の Runtime 死亡 → EpisodeFailed/Recovering
14. observation/approval ExpiresAt → policy 指定 terminal
15. two episodes + crossed events が Guard で consume 前に除外
16. backend start の同期 Failed → StartResult → retryable 再配置または terminal failure
17. heartbeat loss → evidence 付き synthetic terminal event → failure/cleanup/lease release
18. synthetic terminal 適用後の遅延 Runtime event → terminal state 不変、late-events 監査保存
19. synthetic event 書込み直前に genuine event が到着 → lock 内 recheck で synthetic 作成中止
20. command 発行と Runtime boundary event の競合 → Rejected(StaleContext) または先着 event により旧 command を Superseded、新しい precondition/CommandId で再発行して完走。遅着 response は audit-only
21. CommandPending 中の terminal event → terminal/cleanup へ到達
22. Stop が二回 Rejected → Cancel へ昇格し terminal/cleanup へ到達
23. CommitReceipt 保存後に Runtime loss → CommittedButSessionLost、CommittedValid、重複 replan/commit 無し
24. commit failure 後に旧 CommitPermit で再 commit → 拒否、新 permit のみ許可

### 24.3 crash windows

- inbox write 前 crash
- inbox write 後/token submit 前 crash
- token submit 後/delivery mark 前 crash
- outbox write 後/send 前 crash
- send 後/ack 保存前 crash
- checkpoint manifest write 中 crash
- process start 後/handle 保存前 crash
- commit 成功後/receipt 保存前 crash
- cleanup 中 crash
- FinalAction 実行後/CommitReceipt 永続化前 crash
- CommitReceipt 永続化後/AcceptArtifact command 前 crash
- AcceptArtifact 後/Completed event 前 Runtime loss
- synthetic event lock 取得後/genuine event 到着 race

replay 後に event、command、tool effect、commit、lease release が一回であることを確認する。

### 24.4 safety

- session privacy label downgrade がない
- claudecode local process を local inference と誤認しない
- raw conversation/secret が Petri token に無い
- checkpoint に credential 本体が無い
- target direct write が拒否される
- out-of-scope tool は execution 前に止まる
- stale attempt event が新 attempt を進めない
- attempt 1 の残留 command が attempt 2 で Rejected(StaleAttempt)
- unknown cost が policy を迂回しない
- PrivacyLabel が [0,1] 外、欠落、非数値なら fail-closed
- AccessSpecHash/PolicySnapshotHash canonical 化が key 順に依存しない
- synthetic generator 以外が作った synthetic source event を拒否する
- Runtime event の EventSeq と synthetic event の EventId/hash 名前空間が衝突しない
- approval/NeedsRestartApproval の ExpiresAt で OnExpiry が一度だけ実行される

### 24.5 granularity

同じ control script を返す mock backend:

~~~text
Case A: InternalTurns = 5,  InternalToolCalls = 2
Case B: InternalTurns = 50, InternalToolCalls = 40
~~~

assert:

- workflow transition name sequence が一致
- Petri token 数が一致
- Runtime trace event 数だけが異なる
- turn/tool budget counters は異なり正しく集計される
- routine checkpoint 数は異なっても control transition 列は一致
- boundary checkpoint 数が異なる場合だけ O(1+B) の B として増える

実 CheckpointPolicy(Routine.AfterToolCalls=5、EverySeconds=300)でも同じ検査を行い、routine checkpoint を Petri event に変換していないことを確認する。

### 24.6 scheduler / resource / commit

- session poll tick 実行中の再入は SkippedBusy、event/token 重複なし
- in-kernel 10 tool iteration 中も各 session poll tick が 200ms soft limit 内
- tick 内に同期 network/model/tool/NotebookWrite がない
- SeatBroker 飽和時に新 process を起動せず待機または明示降格
- NotebookCommit capability 無しの headless backend は Notebook mode を拒否
- FinalAction 完了検証 → CommitReceipt durable 保存 → AcceptArtifact → Completed の順序
- quarantine entry が期限内に reconcile され lease が Released/QuarantineReleased へ到達

### 24.7 operational metrics

- event bridge p50/p95 delay
- event dedup/replay count
- command ack delay
- checkpoint size/time
- restore success rate
- orphan recovery time
- budget overshoot
- artifact commit conflict rate
- Petri control transitions per episode
- internal turns per control transition
- session startup overhead

---

## 25. 受け入れ条件

### 25.1 構造

~~~text
ClaudeRuntime が内部 turn/tool loop を所有する
ClaudeOrchestrator が session episode の境界を所有する
Petri net に turn/tool-call transition がない
Runtime は Orchestrator に依存しない
Orchestrator は Runtime Private symbols を参照しない
final target の mutation は single committer のみ
~~~

### 25.2 durability

~~~text
event は at-least-once 配送、Petri 適用は effectively-once
command は再送可能で effect は idempotent
restore 後に reattach/resume/fail のいずれかへ確定できる
checkpoint/tool journal から duplicate effect を防げる
lease は terminal path ごとに一回だけ返る
~~~

### 25.3 budget

~~~text
Runtime local hard limit と Orchestrator aggregate ledger の双方が動く
hard stop 後に新規 billable action を開始しない
grant extension は versioned command だけで可能
unknown cost は明示 policy 無しに 0 扱いしない
~~~

### 25.4 safety

~~~text
privacy taint は単調
AccessSpec/PolicySnapshot hash mismatch は fail-closed
tool approval は実行前・scoped
raw secret/conversation/artifact 本文を control plane に保存しない
cooperative enforcement を OS sandbox と表示しない
~~~

### 25.5 artifact

~~~text
Runtime は staging artifact だけを作る
candidate は schema/hash/provenance/privacy を持つ
validation pass と CommitPermit 無しに target は変わらない
commit receipt の durable 保存後だけ Completed になる
~~~

---

## 26. Go / No-Go gate

### 26.1 MVP Go

- tool/environment feedback が必要な反復 task が実在
- direct single call / fixed template では失敗する task set がある
- Runtime 内部 loop が failure を救済する仮説を deterministic check で測れる
- private/access/budget/commit boundary が要件

### 26.2 external session Go

- expected episode duration が in-kernel の安全範囲を超える
- hard cancel/recovery/isolation が必要
- checkpoint size/time が許容
- cooperative kernel では policy を満たさない task がある

### 26.3 session reuse Go

- 同一 workflow 内の複数 episode で memory reuse が成功率/費用を改善
- contamination test が green
- cumulative taint/budget enforcement が green
- cross-task memory retention policy が明示済み

### 26.4 No-Go / 停止

- RuntimeSession が単発 call と同じ結果を高い overhead で返すだけ
- tool feedback による failure rescue がない
- checkpoint が巨大・遅過ぎて recovery benefit を上回る
- event bridge/commit の不整合が解消できない
- cooperative environment しか使えず必要 isolation を満たせない
- artifact を staging/commit 境界へ分離できない workload

この場合、既存 LLMCall worker と固定 workflow を維持し、full session orchestration を一般化しない。

---

## 27. 非目標と将来拡張

### 27.1 v0.1 の非目標

- learned workflow policy
- cross-workflow session reuse
- agent 同士の自由会話
- raw chain-of-thought 保存
- turn 単位の Petri 可視化
- distributed exactly-once transaction の主張
- OS sandbox を cooperative NBAccess だけで代替
- arbitrary tool の自動許可

### 27.2 将来拡張

- container/VM backend
- provider-native agent backend
- session migration between machines
- shared read-only memory + per-session private memory
- 異種 worker 間の artifact handoff
- learned backend/session policy
- event-sourced global run reconstruction
- compensation workflow を持つ non-idempotent tool

---

## 28. 最終実装方針

本仕様の核心は、Petri-net engine に agent の内部 loop を移植することではない。

1. ClaudeRuntime の既存 turn/tool loop を RuntimeSession facade で包む。
2. Orchestrator と Runtime の間に durable command/event protocol を置く。
3. session control event だけを ClaudeSubmitToken で Petri net に入れる。
4. checkpoint、budget、approval、artifact commit を episode boundary として強制する。
5. internal trace と orchestration state を分離する。
6. external process backend と異種 worker は同じ protocol の追加 backend とする。

最初の実装は MockRuntimeSession と ClaudeRuntimeInKernel、ReusePolicy = "Never" から始める。安全・budget・artifact の受け入れ条件を通した後に external session runner を追加する。

これにより Petri net は agent のマイクロステップを逐一追う巨大 state machine にならず、長期 agent session を安全に監督する control plane になる。
