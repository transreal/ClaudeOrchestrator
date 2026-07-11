(* ::Package:: *)

(* ::Title:: *)
(* ClaudeOrchestrator_session.wl *)

(* ::Subsection:: *)
(* 概要 *)

(* ════════════════════════════════════════════════════════════════════
   ClaudeOrchestrator_session.wl

   ClaudeOrchestrator`Session` 名前空間。
   RuntimeSession episode 層の実装 (仕様:
   ClaudeOrchestrator_info/design/
     claude_orchestrator_runtime_session_episode_petri_spec_v0_1.md)。

   本ファイルの現行スコープは Inc1 + Inc2:

   Inc1:
     - §7   schema validator (fail-closed)
     - §7.9 canonical hash (共通 recursive canonicalizer + WXF + SHA256)
     - ID generator (SessionId/EpisodeId/CommandId/... と
       決定論 SessionEvent token id §10.3)
     - §7.7/§11.2.1 SyntheticControlEvent (Source × Type 検査、
       EvidenceRef / SyntheticBaseEventSeq)
     - §8.1 RuntimeSession backend registry
     - MockRuntimeSession backend
       (決定論 event script、(EpisodeId, Attempt, StartCommandId) 冪等 start)

   Inc2 (§9/§10):
     - episode supervisor net builder (単一 EpisodeActive place +
       ControlState、event × ControlState 到達性行列)
     - §9.4 pairing Guard (既存 WorkflowTransition Guard に Function 設定、
       SessionEvents 消費 transition の Guard 欠落は build 時 fail-closed)
     - StartEpisode 用 "RuntimeSession" executor (workflow engine の seam
       $ClaudeRuntimeSessionExecutor へ注入)
     - HandleStartFailure / HandleCommandRejected / HandleTerminalEvent /
       QueueSessionCommand / CleanupAndRelease (lease 一回返却)
     - ActiveSessionEpisodes registry (§10.5 pending seam へ注入。
       正本は EpisodeActive の lease token、registry は導出 index)
     - event bridge lite: ClaudeRuntimeSessionPumpOnce (§11.2 の
       「一度に一個の未適用 event」規約。durable spool 化は Inc3)
     - watchdog 用 SyntheticControlEvent 注入 API

   Inc3 以降 (durable inbox/outbox / poll tick / recovery) も本ファイルに
   追加していく。

   依存規則 (§22):
     ClaudeOrchestrator_session -> ClaudeOrchestrator_workflow
       (ロード順は workflow → session とすること)
     ClaudeRuntime には依存しない (public backend spec のみ将来受け取る)

   バージョン: v0.2 (Inc1+Inc2, 2026-07-11)
   ════════════════════════════════════════════════════════════════════ *)

BeginPackage["ClaudeOrchestrator`Session`", {"ClaudeOrchestrator`Workflow`"}];

(* ::Subsection:: *)
(* 公開 API usage *)

$ClaudeSessionModuleVersion::usage =
  "$ClaudeSessionModuleVersion は本モジュールのバージョン文字列。";

(* ── canonical hash (§7.9) ── *)

ClaudeSessionCanonicalize::usage =
  "ClaudeSessionCanonicalize[expr] は hash 用の canonical form を返す。\n" <>
  "全階層で Association を KeySort し、DateObject を epoch ms へ正規化する。\n" <>
  "List の順序は保存する (set semantics の field は schema 側で事前 Sort)。";

ClaudeSessionCanonicalHash::usage =
  "ClaudeSessionCanonicalHash[expr] は canonical form の WXF bytes に対する\n" <>
  "SHA256 を 64 桁 hex 文字列で返す。key 順・timezone 表示に依存しない。";

ClaudeSessionObjectHash::usage =
  "ClaudeSessionObjectHash[obj, hashField] は obj から hashField と\n" <>
  "transport 系 field を除いた canonical hash を返す (§7.9 手順 1)。";

ClaudeSessionEventHash::usage =
  "ClaudeSessionEventHash[event] は SessionControlEvent の EventHash を計算する。";

ClaudeSessionCommandHash::usage =
  "ClaudeSessionCommandHash[command] は SessionCommand の CommandHash を計算する。";

ClaudeSessionGrantHash::usage =
  "ClaudeSessionGrantHash[grant] は BudgetGrant の GrantHash を計算する。";

ClaudeSessionAccessSpecHash::usage =
  "ClaudeSessionAccessSpecHash[accessSpec] は AccessSpec の canonical hash を\n" <>
  "返す (Inc1 新設)。set semantics の field (AllowedDirectories 等) は\n" <>
  "Sort してから hash するため列挙順に依存しない。";

ClaudeSessionVerifyEventHash::usage =
  "ClaudeSessionVerifyEventHash[event] は EventHash field が再計算値と\n" <>
  "一致すれば True。欠落・不一致は False (fail-closed)。";

ClaudeSessionVerifyCommandHash::usage =
  "ClaudeSessionVerifyCommandHash[command] は CommandHash field が再計算値と\n" <>
  "一致すれば True。";

ClaudeSessionVerifyStartSpecHashes::usage =
  "ClaudeSessionVerifyStartSpecHashes[startSpec] は AccessSpecHash と\n" <>
  "GrantHash が中身の再計算値と一致するか検査し <|Valid, Errors|> を返す。";

(* ── ID generator ── *)

ClaudeSessionNewId::usage =
  "ClaudeSessionNewId[kind] は kind に応じた prefix 付き一意 ID を返す。\n" <>
  "kind: \"Session\"|\"Episode\"|\"Command\"|\"StartCommand\"|\"Event\"|\n" <>
  "\"Lease\"|\"Artifact\"|\"Checkpoint\"|\"ToolCall\"|\"BackendInstance\"。";

ClaudeSessionEventTokenId::usage =
  "ClaudeSessionEventTokenId[event] は SessionEvent token の決定論 ID を返す\n" <>
  "(§10.3)。Source==Runtime は (EpisodeId, Attempt, EventSeq, EventHash)、\n" <>
  "synthetic は (EpisodeId, Attempt, Source, EventId, EventHash) から生成し\n" <>
  "名前空間 prefix (sevt-/ssyn-) で衝突を防ぐ。";

(* ── schema validator (§7) ── *)

ClaudeSessionValidate::usage =
  "ClaudeSessionValidate[schema, obj] は obj を schema に対して fail-closed に\n" <>
  "検証し <|\"Valid\"->True|False, \"Schema\"->schema, \"Errors\"->{...}|> を返す。\n" <>
  "schema: \"SessionStartSpec\"|\"EnvironmentSpec\"|\"BudgetGrant\"|\n" <>
  "\"BudgetSnapshot\"|\"CheckpointPolicy\"|\"RuntimeCheckpointManifest\"|\n" <>
  "\"ArtifactContract\"|\"ArtifactCandidate\"|\"SessionControlEvent\"|\n" <>
  "\"SessionCommand\"|\"EventCursor\"。";

ClaudeSessionValidateEventBatch::usage =
  "ClaudeSessionValidateEventBatch[events, cursor] は PollEvents で得た\n" <>
  "Runtime event 列を cursor (<|Attempt, EventSeq|>) に対して検証する。\n" <>
  "schema/hash/Attempt/EventSeq 連番を fail-closed で検査し、最初の違反で\n" <>
  "停止して <|Valid, Errors, NextCursor|> を返す (gap は適用しない §11.2)。";

(* ── backend registry (§8.1) ── *)

ClaudeRegisterRuntimeSessionBackend::usage =
  "ClaudeRegisterRuntimeSessionBackend[name, backend] は RuntimeSession\n" <>
  "backend (ProtocolVersion/Capabilities/StartEpisode/PollEvents/SendCommand/\n" <>
  "Inspect/Recover/Dispose) を検証して登録する。protocol 違反は Failure。";

ClaudeUnregisterRuntimeSessionBackend::usage =
  "ClaudeUnregisterRuntimeSessionBackend[name] は登録済み backend を除去する。";

ClaudeRuntimeSessionBackends::usage =
  "ClaudeRuntimeSessionBackends[] は登録済み backend 名の一覧を返す。";

ClaudeRuntimeSessionBackendInfo::usage =
  "ClaudeRuntimeSessionBackendInfo[name] は backend の Function 本体を含まない\n" <>
  "info (ProtocolVersion/Capabilities/ContractFns) を返す。";

(* ── MockRuntimeSession backend ── *)

ClaudeMockRuntimeSessionBackendSpec::usage =
  "ClaudeMockRuntimeSessionBackendSpec[opts] は決定論 event script を返す\n" <>
  "mock backend Association を生成する。ClaudeRegisterRuntimeSessionBackend\n" <>
  "に渡して使う。\n" <>
  "オプション:\n" <>
  "  \"EventScript\" -> Automatic | {template..}  (template は\n" <>
  "     <|\"Type\"->.., \"PayloadRefs\"->.., \"BudgetSnapshot\"->..,\n" <>
  "       \"PrivacyLabel\"->..|> の部分指定。EventSeq/ID/hash は自動付与)\n" <>
  "  \"AckEvents\" -> True       command 受理時に CommandAccepted event を追加\n" <>
  "  \"TerminalOnCancel\" -> True  Cancel 受理時に Cancelled event を追加\n" <>
  "  \"FailStart\" -> False      StartEpisode を常に Failed にする\n" <>
  "  \"ValidateEvents\" -> True  materialize した event を schema 検証\n" <>
  "契約 (Inc1 での近似): mock の「emit 済み tip」は PollEvents で取得済みの\n" <>
  "最大 EventSeq とし、SendCommand の ExpectedAfterEventSeq はこれと照合する。\n" <>
  "Cancel は seq 照合を免除 (Attempt 不一致は常に Rejected(StaleAttempt))。";

ClaudeMockRuntimeSessionReset::usage =
  "ClaudeMockRuntimeSessionReset[] は mock backend の内部状態 (全 handle /\n" <>
  "start 冪等 index) をクリアする。テスト用。";

ClaudeSessionStartSpecTemplate::usage =
  "ClaudeSessionStartSpecTemplate[opts] は schema 検証を通る最小の\n" <>
  "SessionStartSpec を生成する (AccessSpecHash / GrantHash は自動計算)。\n" <>
  "オプション: \"WorkflowId\"/\"TaskId\"/\"SessionId\"/\"EpisodeId\"/\n" <>
  "\"StartCommandId\" (Automatic で自動発行), \"Attempt\"->1,\n" <>
  "\"Backend\"->\"MockRuntimeSession\", \"PrivacyLabel\"->1.0,\n" <>
  "\"GoalRef\"->\"mock-goal\", \"ReusePolicy\"->\"Never\"。テストと Inc2 用。";

(* ── Inc2: episode supervisor net ── *)

ClaudeCreateRuntimeSessionEpisodeNet::usage =
  "ClaudeCreateRuntimeSessionEpisodeNet[startSpec, opts] は §9 の episode\n" <>
  "supervisor net を生成し、slot/Task token を投入して\n" <>
  "<|WorkflowId, EpisodeId, SessionId, Backend|> を返す。startSpec は\n" <>
  "schema/hash 検証を fail-closed で通過する必要がある。\n" <>
  "オプション: \"SessionSlots\"->1, \"EnvironmentSlots\"->1, \"Validate\"->True。";

ClaudeStartRuntimeSessionEpisode::usage =
  "ClaudeStartRuntimeSessionEpisode[wid] は enabled transition が尽きるまで\n" <>
  "step し (Allocate → StartEpisode)、episode を Running まで進める。";

ClaudeRuntimeSessionPumpOnce::usage =
  "ClaudeRuntimeSessionPumpOnce[wid, episodeId] は backend を poll し、\n" <>
  "未適用の control event を一個だけ SessionEvents place へ投入する (§11.2)。\n" <>
  "schema/hash 違反は quarantine。戻り Status: Deposited|Duplicate|\n" <>
  "NoNewEvents|NoActiveLease|Quarantined 等。適用は ClaudeStepWorkflow が行う。";

ClaudeRuntimeSessionCancel::usage =
  "ClaudeRuntimeSessionCancel[wid, episodeId, reason] は Cancel command\n" <>
  "request を投入する。全 non-terminal ControlState から受理される (I13)。";

ClaudeRuntimeSessionProvideObservation::usage =
  "ClaudeRuntimeSessionProvideObservation[wid, episodeId, observationRef] は\n" <>
  "AwaitingObservation の episode へ ProvideObservation command request を\n" <>
  "投入する。";

ClaudeRuntimeSessionInjectSyntheticTerminal::usage =
  "ClaudeRuntimeSessionInjectSyntheticTerminal[wid, episodeId, type,\n" <>
  "evidenceRef] は watchdog/recovery 用の SyntheticControlEvent\n" <>
  "(Source=OrchestratorWatchdog、type は Failed|Cancelled|EnvironmentLost)\n" <>
  "を生成・検証して SessionEvents へ投入する (§11.2.1)。Runtime が沈黙・\n" <>
  "死亡した episode を terminal へ導く安全網。";

ClaudeRuntimeSessionEpisodeInfo::usage =
  "ClaudeRuntimeSessionEpisodeInfo[wid, episodeId] は episode の現在\n" <>
  "ControlState / LastAppliedEventSeq / PendingCommand / HandleRef 等を返す。";

ClaudeRuntimeSessionEpisodes::usage =
  "ClaudeRuntimeSessionEpisodes[wid] は workflow 上の episode 一覧を返す。";

ClaudeSessionActiveEpisodes::usage =
  "ClaudeSessionActiveEpisodes[] は ActiveSessionEpisodes 導出 index\n" <>
  "(poll/recovery 対象) を返す。正本は EpisodeActive の lease token (§10.5)。";

ClaudeSessionQuarantine::usage =
  "ClaudeSessionQuarantine[] は schema/hash 違反等で隔離した event の\n" <>
  "記録一覧を返す (§11.4 の in-memory 版 + spool quarantine 記録)。";

(* ── Inc8: artifact validation / single commit (§17) ── *)

ClaudeSessionValidateArtifactCandidate::usage =
  "ClaudeSessionValidateArtifactCandidate[candidate, contract, sessionLabel]\n" <>
  "は ArtifactCandidate を ArtifactContract に対して検証する (§17.1)。\n" <>
  "schema / type 一致 / staging root 包含 / byte 上限 / privacy 単調 / \n" <>
  "provenance / RequiredChecks / (Files の) base revision を検査し\n" <>
  "<|\"Valid\", \"Errors\", \"Repairable\"|> を返す。fail-closed。";

ClaudeRuntimeSessionArtifactReceipt::usage =
  "ClaudeRuntimeSessionArtifactReceipt[wid, episodeId] は commit 済み\n" <>
  "artifact の CommitReceipt (§17.3: CommitId/TargetRef/NewRevision/\n" <>
  "ContentHash 等) を返す。未 commit なら None。";

(* ── Inc3: durable event bridge / command outbox (§11) ── *)

$ClaudeSessionSpoolRoot::usage =
  "$ClaudeSessionSpoolRoot は episode spool の root directory。未設定時は\n" <>
  "FileNameJoin[{$UserBaseDirectory, \"ClaudeOrchestrator\", \"session-spool\"}]。\n" <>
  "layout (§11.1): <root>/<session-id>/<episode-id>/attempts/<attempt>/\n" <>
  "{inbox, outbox, delivery-index.wxf, command-index.wxf} + episode-meta.json。";

ClaudeRuntimeSessionPollTick::usage =
  "ClaudeRuntimeSessionPollTick[] は全 active episode について outbox\n" <>
  "dispatch と event pump を一回行う (§11.5 契約: 搬送のみ。model/tool/\n" <>
  "NotebookWrite を行わない。soft 200ms 超過分は次 tick へ、再入は\n" <>
  "SkippedBusy)。Petri の発火は行わない (engine の step/async tick が担当)。";

ClaudeRuntimeSessionDispatchOutbox::usage =
  "ClaudeRuntimeSessionDispatchOutbox[wid, episodeId] は attempt-local\n" <>
  "outbox の未 ack command を backend へ送る (§11.3)。transport retry は\n" <>
  "同一 CommandId。Rejected は Bridge CommandRejected synthetic event に\n" <>
  "正規化して inbox へ置く (§11.2.1)。";

ClaudeRecoverRuntimeSessions::usage =
  "ClaudeRecoverRuntimeSessions[] は active episode を backend Recover で\n" <>
  "検査し、LostUnrecoverable は genuine event recheck の後に\n" <>
  "Source=RecoveryScan の synthetic terminal を注入して lease release へ\n" <>
  "導く (§15.2 / Inc3 受け入れ「silent/dead Runtime でも lease release」)。";

ClaudeRuntimeSessionEnablePolling::usage =
  "ClaudeRuntimeSessionEnablePolling[] は ClaudeCode` の shared polling\n" <>
  "tick に ClaudeRuntimeSessionPollTick を登録する (§11.5)。ClaudeCode 未\n" <>
  "ロード環境では ClaudeCodeUnavailable を返し何もしない。";

ClaudeSessionEpisodeSpoolInfo::usage =
  "ClaudeSessionEpisodeSpoolInfo[sessionId, episodeId, attempt] は spool 上の\n" <>
  "delivery-index / command-index / inbox・outbox ファイル一覧を返す (検査用)。";

(* ── Inc0 (conductor v0.2 Inc0A/0B の episode 層 primitive) ── *)

ClaudeSessionResolveTrustDomain::usage =
  "ClaudeSessionResolveTrustDomain[modelEntry] は model/backend entry から\n" <>
  "InferenceTrustDomain を解決する (conductor v0.2 §13.2)。優先順:\n" <>
  "InferenceTrustDomain (canonical) > TrustDomain (legacy) > Class 内の\n" <>
  "Local/Cloud > provider label 分類。**ExecutionLocation は見ない**\n" <>
  "(claudecode は Local プロセスでも推論は Cloud)。不明は\n" <>
  "Missing[\"Unknown\"] (gate 側で fail-closed)。";

ClaudeSessionTrustGateQ::usage =
  "ClaudeSessionTrustGateQ[privacyLabel, domain] は cloud 境界 (0.5) 以上の\n" <>
  "label で InferenceTrustDomain が Local|Private と確認できる場合のみ True。\n" <>
  "不明 domain・非数値 label は fail-closed で False (§16.4 / Inc0 受け入れ\n" <>
  "「private 由来 session が cloud trust gate を迂回しない」)。";

ClaudeSessionMakeCallContext::usage =
  "ClaudeSessionMakeCallContext[fields] は provider call 発行時に固定する\n" <>
  "immutable な CallContext (§19.3) を返す。CallId は自動発行。Provider/\n" <>
  "Model は必須、RunId/WorkflowId/TaskId/SessionId/EpisodeId/Attempt/\n" <>
  "TurnIndex/ToolCallId/ReservationId は任意。mutable global に依存しない。";

ClaudeSessionLedgerRecord::usage =
  "ClaudeSessionLedgerRecord[callContext, usage] は usage/cost を CallId で\n" <>
  "ledger に記録する。completion 順が逆転しても帰属は CallContext 固定\n" <>
  "なので壊れない (Inc0 受け入れ)。同一 CallId の再記録は上書き\n" <>
  "(Status->Updated)。usage: InTokens/OutTokens/CacheReadTokens/CostUSD/\n" <>
  "CostSource (Provider|Estimated|Unknown)。";

ClaudeSessionCallLog::usage =
  "ClaudeSessionCallLog[] は ledger 記録の一覧 (LoggedAt 順) を返す。";

ClaudeSessionCallAggregate::usage =
  "ClaudeSessionCallAggregate[keyField, keyValue] は CallContext の keyField\n" <>
  "(\"EpisodeId\"/\"RunId\"/\"WorkflowId\" 等) が keyValue の call を集計する。\n" <>
  "CostUSD は数値のみ合算し、unknown cost は 0 扱いせず\n" <>
  "UnknownCostCalls として別掲する (§25.3)。";

ClaudeSessionCallLogReset::usage =
  "ClaudeSessionCallLogReset[] は ledger をクリアする。テスト用。";

Begin["`Private`"];

$ClaudeSessionModuleVersion = "v0.2 (Inc1+Inc2, 2026-07-11)";

(* ::Subsection:: *)
(* 語彙 (enum) *)

$iEventSources = {"Runtime", "OrchestratorWatchdog", "RecoveryScan", "Bridge"};

$iRuntimeEventTypes = {
  "ObservationRequired", "ApprovalRequired", "CheckpointCreated",
  "BudgetInterrupt", "ArtifactProposed", "Completed", "Failed",
  "Cancelled", "EnvironmentLost", "CommandAccepted"};

$iSyntheticTerminalTypes = {"Failed", "EnvironmentLost", "Cancelled"};

$iCommandTypes = {
  "ProvideObservation", "GrantScopedApproval", "GrantBudget",
  "RequestCheckpoint", "AcceptArtifact", "RepairArtifact",
  "Stop", "Cancel", "Ping"};

$iIsolationLevels = {
  "ExternalProcess", "Container", "WorkspaceOverlay", "CooperativeKernel"};

(* §7.2 / §11.1: "Redacted" は MVP enum に含めない *)
$iConfidentialHandlingValues = {"EncryptedBundle", "ReferenceOnly"};

$iCommitModes       = {"ArtifactStore", "Notebook", "Files"};
$iReusePolicies     = {"Never", "SameWorkflowSameTrust"};
$iCostSources       = {"Provider", "Estimated", "Unknown"};
$iUnknownCostPolicies = {"Reject", "RequireApproval", "AllowUnmetered"};
$iCheckpointStorage = {"EncryptedBundle", "ReferenceOnly"};

(* ::Subsection:: *)
(* canonical hash (§7.9) *)

(* transport/delivery 系は hash 対象から除外する (§7.9 手順 1) *)
$iTransportKeys = {
  "Delivered", "DeliveredAt", "DeliveryStatus", "FetchedAt",
  "TransportMeta"};

iCanon[a_Association] := KeySort[Map[iCanon, a]];
iCanon[l_List]        := Map[iCanon, l];
iCanon[d_DateObject]  :=
  <|"__CanonicalDateMs" -> Round[1000 * AbsoluteTime[d]]|>;
iCanon[x_]            := x;

ClaudeSessionCanonicalize[expr_] := iCanon[expr];

(* canonical WXF bytes → SHA256。Hash は String に対して標準 digest を
   返すことが保証されているため、bytes は Base64 文字列へ落としてから
   hash する (ByteArray を式として hash する曖昧さを避ける)。 *)
ClaudeSessionCanonicalHash[expr_] :=
  IntegerString[
    Hash[BaseEncode[BinarySerialize[iCanon[expr]], "Base64"], "SHA256"],
    16, 64];

ClaudeSessionObjectHash[obj_Association, hashField_String] :=
  ClaudeSessionCanonicalHash[
    KeyDrop[obj, Join[{hashField}, $iTransportKeys]]];

ClaudeSessionEventHash[ev_Association] :=
  ClaudeSessionObjectHash[ev, "EventHash"];

ClaudeSessionCommandHash[cmd_Association] :=
  ClaudeSessionObjectHash[cmd, "CommandHash"];

ClaudeSessionGrantHash[grant_Association] :=
  ClaudeSessionObjectHash[grant, "GrantHash"];

(* set semantics の field は Sort してから hash (§7.9 手順 3) *)
$iAccessSpecSetKeys = {
  "AccessList", "AllowedCapabilities", "AllowedDirectories",
  "AllowedNetworkTargets", "AllowedExternalCommands",
  "CredentialRefs", "SecretRefs", "ConfidentialSymbols",
  "AllowedHeads", "ApprovalHeads", "DeniedHeads"};

iNormalizeSetFields[a_Association, setKeys_List] :=
  Association @ KeyValueMap[
    Function[{k, v},
      k -> Which[
        MemberQ[setKeys, k] && ListQ[v], Sort[v],
        AssociationQ[v], iNormalizeSetFields[v, setKeys],
        True, v]],
    a];

ClaudeSessionAccessSpecHash[accessSpec_Association] :=
  ClaudeSessionCanonicalHash[
    iNormalizeSetFields[accessSpec, $iAccessSpecSetKeys]];

ClaudeSessionVerifyEventHash[ev_Association] :=
  Module[{h = Lookup[ev, "EventHash", None]},
    StringQ[h] && h === ClaudeSessionEventHash[ev]];

ClaudeSessionVerifyCommandHash[cmd_Association] :=
  Module[{h = Lookup[cmd, "CommandHash", None]},
    StringQ[h] && h === ClaudeSessionCommandHash[cmd]];

ClaudeSessionVerifyStartSpecHashes[startSpec_Association] :=
  Module[{errs = {}, access, grant},
    access = Lookup[startSpec, "Access", <||>];
    grant  = Lookup[startSpec, "BudgetGrant", <||>];
    If[!AssociationQ[Lookup[access, "AccessSpec", None]] ||
       Lookup[access, "AccessSpecHash", None] =!=
         ClaudeSessionAccessSpecHash[Lookup[access, "AccessSpec", <||>]],
      AppendTo[errs, "AccessSpecHash mismatch"]];
    If[!AssociationQ[grant] ||
       Lookup[grant, "GrantHash", None] =!= ClaudeSessionGrantHash[grant],
      AppendTo[errs, "GrantHash mismatch"]];
    <|"Valid" -> errs === {}, "Errors" -> errs|>
  ];

(* ::Subsection:: *)
(* ID generator *)

$iIdPrefixes = <|
  "Session" -> "ses", "Episode" -> "epi", "Command" -> "cmd",
  "StartCommand" -> "scmd", "Event" -> "evt", "Lease" -> "lease",
  "Artifact" -> "art", "Checkpoint" -> "ckpt", "ToolCall" -> "tool",
  "BackendInstance" -> "bki"|>;

ClaudeSessionNewId[kind_String] :=
  Module[{pfx = Lookup[$iIdPrefixes, kind, Missing["UnknownKind"]]},
    If[MissingQ[pfx],
      Failure["UnknownIdKind",
        <|"Kind" -> kind, "Known" -> Keys[$iIdPrefixes]|>],
      pfx <> "-" <> ToLowerCase[StringDelete[CreateUUID[], "-"]]]
  ];

ClaudeSessionEventTokenId[ev_Association] :=
  Module[{src = Lookup[ev, "Source", "Runtime"]},
    If[src === "Runtime",
      "sevt-" <> StringTake[
        ClaudeSessionCanonicalHash[{
          Lookup[ev, "EpisodeId", ""], Lookup[ev, "Attempt", 0],
          Lookup[ev, "EventSeq", 0], Lookup[ev, "EventHash", ""]}], 24],
      "ssyn-" <> StringTake[
        ClaudeSessionCanonicalHash[{
          Lookup[ev, "EpisodeId", ""], Lookup[ev, "Attempt", 0], src,
          Lookup[ev, "EventId", ""], Lookup[ev, "EventHash", ""]}], 24]
    ]
  ];

(* ::Subsection:: *)
(* validator 基盤 *)

iStrQ[x_]        := StringQ[x] && StringLength[x] > 0;
iIntGEQ[m_][x_]  := IntegerQ[x] && x >= m;
iNumGEQ[m_][x_]  := NumericQ[x] && x >= m;
iBoolQ[x_]       := x === True || x === False;
iPrivacyQ[x_]    := NumericQ[x] && 0 <= x <= 1;
iListOfStrQ[x_]  := ListQ[x] && AllTrue[x, StringQ];
iNoneOr[pred_][x_] := x === None || TrueQ[Quiet @ pred[x]];

iFieldErr[obj_Association, key_String, pred_, desc_String] :=
  Module[{v = Lookup[obj, key, Missing["AbsentField"]]},
    Which[
      v === Missing["AbsentField"], {"Missing field: " <> key},
      TrueQ[Quiet @ pred[v]], {},
      True, {"Invalid " <> key <> " (expected " <> desc <> ")"}
    ]
  ];

iEnumErr[obj_, key_, values_List] :=
  iFieldErr[obj, key, MemberQ[values, #] &,
    "one of " <> StringRiffle[values, "|"]];

iPrefixErrs[prefix_String, errs_List] :=
  Map[(prefix <> ": " <> #) &, errs];

(* ::Subsection:: *)
(* schema validators (§7) *)

(* ── EnvironmentSpec (§7.2) ── *)

iValidateEnvironmentSpec[env_Association] :=
  Flatten @ {
    iEnumErr[env, "IsolationLevel", $iIsolationLevels],
    iFieldErr[env, "EnvironmentLeaseId", iStrQ, "non-empty String"],
    iFieldErr[env, "ReadOnlyInputRoots", iListOfStrQ, "list of String"],
    iFieldErr[env, "WritableStagingRoot", iStrQ, "non-empty String"],
    iFieldErr[env, "FinalTargetRefs", ListQ, "List"],
    iFieldErr[env, "AllowedDirectories", iListOfStrQ, "list of String"],
    iFieldErr[env, "AllowedNetworkTargets", iListOfStrQ, "list of String"],
    iFieldErr[env, "AllowedExternalCommands", iListOfStrQ, "list of String"],
    iFieldErr[env, "CredentialRefs", ListQ, "List"],
    iFieldErr[env, "SecretRefs", ListQ, "List"],
    iEnumErr[env, "ConfidentialHandling", $iConfidentialHandlingValues],
    iFieldErr[env, "CleanupPolicy", AssociationQ, "Association"]
  };

(* ── BudgetGrant (§7.3, conductor 語彙) ── *)

$iHardLimitIntKeys = {
  "MaxTurns", "MaxCalls", "MaxToolCalls", "MaxInputTokens",
  "MaxOutputTokens", "MaxContextTokensPerStep", "MaxBytesWritten",
  "MaxNetworkRequests"};

$iHardLimitNumKeys = {"MaxWallClockSeconds", "MaxIdleSeconds"};

iValidateBudgetGrant[grant_Association] :=
  Module[{errs, hard},
    errs = Flatten @ {
      iFieldErr[grant, "BudgetGrantId", iStrQ, "non-empty String"],
      iFieldErr[grant, "Version", iIntGEQ[1], "Integer >= 1"],
      iFieldErr[grant, "Objective", iStrQ, "non-empty String"],
      iFieldErr[grant, "HardLimits", AssociationQ, "Association"],
      iFieldErr[grant, "SoftThresholds", AssociationQ, "Association"],
      iEnumErr[grant, "UnknownCostPolicy", $iUnknownCostPolicies],
      iFieldErr[grant, "IssuedAt", DateObjectQ, "DateObject"],
      iFieldErr[grant, "GrantHash", iStrQ, "non-empty String"]
    };
    hard = Lookup[grant, "HardLimits", <||>];
    If[AssociationQ[hard],
      errs = Flatten @ {errs,
        Map[iFieldErr[hard, #, iIntGEQ[0], "Integer >= 0"] &,
          $iHardLimitIntKeys],
        Map[iFieldErr[hard, #, iNumGEQ[0], "numeric >= 0"] &,
          $iHardLimitNumKeys],
        iFieldErr[hard, "MaxCostUSD", iNoneOr[iNumGEQ[0]],
          "None or numeric >= 0"]}];
    Module[{soft = Lookup[grant, "SoftThresholds", <||>]},
      If[AssociationQ[soft],
        errs = Flatten @ {errs,
          iFieldErr[soft, "WarnFraction",
            (NumericQ[#] && 0 < # <= 1) &, "numeric in (0,1]"],
          iFieldErr[soft, "CheckpointFraction",
            (NumericQ[#] && 0 < # <= 1) &, "numeric in (0,1]"]}]];
    errs
  ];

(* ── BudgetSnapshot (§7.4, conductor 語彙) ── *)

$iSnapshotCounterKeys = {
  "Turns", "Calls", "ToolCalls", "InputTokens", "OutputTokens",
  "WallClockSeconds", "IdleSeconds", "BytesWritten", "NetworkRequests"};

iValidateBudgetSnapshot[snap_Association] :=
  Flatten @ {
    Map[iFieldErr[snap, #, iNumGEQ[0], "numeric >= 0"] &,
      $iSnapshotCounterKeys],
    iFieldErr[snap, "ActualUSD", iNoneOr[iNumGEQ[0]],
      "None or numeric >= 0"],
    iFieldErr[snap, "ReservedUSD", iNoneOr[iNumGEQ[0]],
      "None or numeric >= 0"],
    iEnumErr[snap, "CostSource", $iCostSources],
    iFieldErr[snap, "BudgetGrantId", StringQ, "String"],
    iFieldErr[snap, "BudgetGrantVersion", iIntGEQ[1], "Integer >= 1"]
  };

(* ── CheckpointPolicy (§7.5, routine/boundary 二層) ── *)

iValidateCheckpointPolicy[pol_Association] :=
  Module[{errs, routine, boundary},
    errs = Flatten @ {
      iFieldErr[pol, "Enabled", iBoolQ, "True|False"],
      iFieldErr[pol, "Routine", AssociationQ, "Association"],
      iFieldErr[pol, "Boundary", AssociationQ, "Association"],
      iFieldErr[pol, "MaxRetained", iIntGEQ[1], "Integer >= 1"],
      iEnumErr[pol, "Storage", $iCheckpointStorage],
      iFieldErr[pol, "RequireHashVerification", iBoolQ, "True|False"]
    };
    routine = Lookup[pol, "Routine", <||>];
    If[AssociationQ[routine],
      errs = Flatten @ {errs,
        iFieldErr[routine, "AtEpisodeStart", iBoolQ, "True|False"],
        iFieldErr[routine, "AfterToolCalls", iNoneOr[iIntGEQ[1]],
          "None or Integer >= 1"],
        iFieldErr[routine, "EverySeconds", iNoneOr[iNumGEQ[0]],
          "None or numeric >= 0"],
        If[Lookup[routine, "EmitControlEvent", Missing["AbsentField"]] =!=
             False,
          {"Routine.EmitControlEvent must be False (granularity invariant §7.5/§9.6)"},
          {}]}];
    boundary = Lookup[pol, "Boundary", <||>];
    If[AssociationQ[boundary],
      errs = Flatten @ {errs,
        Map[iFieldErr[boundary, #, iBoolQ, "True|False"] &,
          {"BeforeNonIdempotentTool", "AtSoftBudgetThreshold",
           "OnInterrupt", "OnExplicitRequest"}],
        If[Lookup[boundary, "EmitControlEvent", Missing["AbsentField"]] =!=
             True,
          {"Boundary.EmitControlEvent must be True (§7.5)"},
          {}]}];
    errs
  ];

(* ── RuntimeCheckpointManifest (§7.5) ── *)

iValidateCheckpointManifest[mf_Association] :=
  Module[{errs},
    errs = Flatten @ {
      iFieldErr[mf, "SchemaVersion", # === 1 &, "1"],
      iFieldErr[mf, "SessionId", iStrQ, "non-empty String"],
      iFieldErr[mf, "EpisodeId", iStrQ, "non-empty String"],
      iFieldErr[mf, "Attempt", iIntGEQ[1], "Integer >= 1"],
      iFieldErr[mf, "CheckpointId", iStrQ, "non-empty String"],
      iFieldErr[mf, "CreatedAt", DateObjectQ, "DateObject"],
      iFieldErr[mf, "RuntimeProfile", StringQ, "String"],
      iFieldErr[mf, "AdapterFactory", StringQ, "String"],
      iFieldErr[mf, "BudgetSnapshot", AssociationQ, "Association"],
      iFieldErr[mf, "LastEventSeq", iIntGEQ[0], "Integer >= 0"],
      iFieldErr[mf, "PendingCommandIds", iListOfStrQ, "list of String"],
      iFieldErr[mf, "AccessSpecHash", iStrQ, "non-empty String"],
      iFieldErr[mf, "PolicySnapshotHash", iStrQ, "non-empty String"],
      iFieldErr[mf, "BudgetGrantId", iStrQ, "non-empty String"],
      iFieldErr[mf, "BudgetGrantVersion", iIntGEQ[1], "Integer >= 1"],
      iFieldErr[mf, "PrivacyLabel", iPrivacyQ, "numeric in [0,1]"],
      iFieldErr[mf, "ContentHash", iStrQ, "non-empty String"]
    };
    If[AssociationQ[Lookup[mf, "BudgetSnapshot", None]],
      errs = Flatten @ {errs,
        iPrefixErrs["BudgetSnapshot",
          iValidateBudgetSnapshot[mf[["BudgetSnapshot"]]]]}];
    errs
  ];

(* ── ArtifactContract / ArtifactCandidate (§7.6) ── *)

iValidateArtifactContract[c_Association] :=
  Flatten @ {
    iFieldErr[c, "ExpectedArtifactType", iStrQ, "non-empty String"],
    iFieldErr[c, "OutputSchema", AssociationQ, "Association"],
    iFieldErr[c, "AllowedStagingRoot", iStrQ, "non-empty String"],
    iFieldErr[c, "MaxArtifactBytes", iIntGEQ[1], "Integer >= 1"],
    iFieldErr[c, "RequiredChecks", iListOfStrQ, "list of String"],
    If[KeyExistsQ[c, "CommitTargetRef"], {},
      {"Missing field: CommitTargetRef"}],
    iFieldErr[c, "BaseRevision", iNoneOr[StringQ], "None or String"],
    iEnumErr[c, "CommitMode", $iCommitModes],
    iFieldErr[c, "RequireProvenance", iBoolQ, "True|False"]
  };

iValidateArtifactCandidate[a_Association] :=
  Module[{errs},
    errs = Flatten @ {
      iFieldErr[a, "ArtifactId", iStrQ, "non-empty String"],
      iFieldErr[a, "SessionId", iStrQ, "non-empty String"],
      iFieldErr[a, "EpisodeId", iStrQ, "non-empty String"],
      iFieldErr[a, "ArtifactType", iStrQ, "non-empty String"],
      If[KeyExistsQ[a, "ArtifactRef"], {}, {"Missing field: ArtifactRef"}],
      If[KeyExistsQ[a, "ManifestRef"], {}, {"Missing field: ManifestRef"}],
      iFieldErr[a, "ContentHash", iStrQ, "non-empty String"],
      iFieldErr[a, "ByteCount", iIntGEQ[0], "Integer >= 0"],
      If[KeyExistsQ[a, "OutputSchemaVersion"], {},
        {"Missing field: OutputSchemaVersion"}],
      iFieldErr[a, "PrivacyLabel", iPrivacyQ, "numeric in [0,1]"],
      iFieldErr[a, "Provenance", AssociationQ, "Association"],
      iFieldErr[a, "SelfChecks", AssociationQ, "Association"],
      iFieldErr[a, "BaseRevision", iNoneOr[StringQ], "None or String"]
    };
    Module[{prov = Lookup[a, "Provenance", <||>]},
      If[AssociationQ[prov],
        errs = Flatten @ {errs,
          Map[
            If[KeyExistsQ[prov, #], {},
              {"Provenance: Missing field: " <> #}] &,
            {"InputRefs", "ToolJournalRef", "Model", "RuntimeTraceRef"}]}]];
    errs
  ];

(* ── SessionControlEvent (§7.7 + §11.2.1 SyntheticControlEvent) ── *)

iValidateSyntheticCommon[ev_Association] :=
  Flatten @ {
    If[Lookup[ev, "EventSeq", None] =!= None,
      {"EventSeq must be None for synthetic Source"}, {}],
    iFieldErr[ev, "SyntheticBaseEventSeq", iIntGEQ[0], "Integer >= 0"],
    Module[{er = Lookup[ev, "EvidenceRef", Missing["AbsentField"]]},
      If[er === Missing["AbsentField"] || er === None,
        {"EvidenceRef required for synthetic Source"}, {}]]
  };

iValidateControlEvent[ev_Association] :=
  Module[{errs, src, type},
    errs = Flatten @ {
      iFieldErr[ev, "SchemaVersion", # === 1 &, "1"],
      iFieldErr[ev, "EventId", iStrQ, "non-empty String"],
      iFieldErr[ev, "SessionId", iStrQ, "non-empty String"],
      iFieldErr[ev, "EpisodeId", iStrQ, "non-empty String"],
      iFieldErr[ev, "Attempt", iIntGEQ[1], "Integer >= 1"],
      iFieldErr[ev, "BackendInstanceId", iStrQ, "non-empty String"],
      iEnumErr[ev, "Source", $iEventSources],
      iFieldErr[ev, "Type", iStrQ, "non-empty String"],
      iFieldErr[ev, "PayloadRefs", AssociationQ, "Association"],
      iFieldErr[ev, "BudgetSnapshot", AssociationQ, "Association"],
      iFieldErr[ev, "AccessSpecHash", StringQ, "String"],
      iFieldErr[ev, "PolicySnapshotHash", StringQ, "String"],
      iFieldErr[ev, "PrivacyLabel", iPrivacyQ, "numeric in [0,1]"],
      iFieldErr[ev, "CreatedAt", DateObjectQ, "DateObject"],
      iFieldErr[ev, "EventHash", iStrQ, "non-empty String"],
      If[!MatchQ[Lookup[ev, "SupersedesThroughSeq", None],
           None | _Integer],
        {"Invalid SupersedesThroughSeq (expected None or Integer)"}, {}]
    };
    src  = Lookup[ev, "Source", None];
    type = Lookup[ev, "Type", None];
    Which[
      src === "Runtime",
        errs = Flatten @ {errs,
          If[!MemberQ[$iRuntimeEventTypes, type],
            {"Type not allowed for Source=Runtime: " <> ToString[type]},
            {}],
          iFieldErr[ev, "EventSeq", iIntGEQ[1], "Integer >= 1"],
          If[Lookup[ev, "SyntheticBaseEventSeq", None] =!= None,
            {"SyntheticBaseEventSeq must be None/absent for Runtime Source"},
            {}]},
      src === "Bridge",
        errs = Flatten @ {errs,
          If[type =!= "CommandRejected",
            {"Bridge Source may only emit CommandRejected"}, {}],
          iValidateSyntheticCommon[ev],
          If[!KeyExistsQ[Lookup[ev, "PayloadRefs", <||>], "CommandId"],
            {"CommandRejected requires PayloadRefs[\"CommandId\"]"}, {}]},
      MemberQ[{"OrchestratorWatchdog", "RecoveryScan"}, src],
        errs = Flatten @ {errs,
          If[!MemberQ[$iSyntheticTerminalTypes, type],
            {"Source " <> src <> " may only emit terminal Types (" <>
             StringRiffle[$iSyntheticTerminalTypes, "|"] <> ")"}, {}],
          iValidateSyntheticCommon[ev]},
      True,
        Null  (* Source エラーは記録済み *)
    ];
    errs
  ];

(* ── SessionCommand (§7.8) ── *)

iValidateCommand[cmd_Association] :=
  Module[{errs},
    errs = Flatten @ {
      iFieldErr[cmd, "SchemaVersion", # === 1 &, "1"],
      iFieldErr[cmd, "CommandId", iStrQ, "non-empty String"],
      iFieldErr[cmd, "SessionId", iStrQ, "non-empty String"],
      iFieldErr[cmd, "EpisodeId", iStrQ, "non-empty String"],
      iFieldErr[cmd, "Attempt", iIntGEQ[1], "Integer >= 1"],
      iFieldErr[cmd, "ExpectedAfterEventSeq", iIntGEQ[0], "Integer >= 0"],
      iEnumErr[cmd, "Type", $iCommandTypes],
      iFieldErr[cmd, "PayloadRefs", AssociationQ, "Association"],
      iFieldErr[cmd, "BudgetGrant", iNoneOr[AssociationQ],
        "None or Association"],
      iFieldErr[cmd, "IssuedAt", DateObjectQ, "DateObject"],
      iFieldErr[cmd, "CommandHash", iStrQ, "non-empty String"]
    };
    If[Lookup[cmd, "Type", None] === "GrantBudget",
      Module[{g = Lookup[cmd, "BudgetGrant", None]},
        If[!AssociationQ[g],
          AppendTo[errs, "GrantBudget requires BudgetGrant Association"],
          errs = Flatten @ {errs,
            iPrefixErrs["BudgetGrant", iValidateBudgetGrant[g]]}]]];
    errs
  ];

(* ── EventCursor (§8.1) ── *)

iValidateCursor[cur_Association] :=
  Flatten @ {
    iFieldErr[cur, "Attempt", iIntGEQ[1], "Integer >= 1"],
    iFieldErr[cur, "EventSeq", iIntGEQ[0], "Integer >= 0"]
  };

(* ── SessionStartSpec (§7.1) ── *)

iValidateStartSpec[startSpec_Association] :=
  Module[{errs, worker, task, access},
    errs = Flatten @ {
      iFieldErr[startSpec, "SchemaVersion", # === 1 &, "1"],
      iFieldErr[startSpec, "WorkflowId", iStrQ, "non-empty String"],
      iFieldErr[startSpec, "RunId", iNoneOr[iStrQ], "None or String"],
      iFieldErr[startSpec, "TaskId", iStrQ, "non-empty String"],
      iFieldErr[startSpec, "SessionId", iStrQ, "non-empty String"],
      iFieldErr[startSpec, "EpisodeId", iStrQ, "non-empty String"],
      iFieldErr[startSpec, "Attempt", iIntGEQ[1], "Integer >= 1"],
      iFieldErr[startSpec, "Backend", iStrQ, "non-empty String"],
      iFieldErr[startSpec, "Worker", AssociationQ, "Association"],
      iFieldErr[startSpec, "Task", AssociationQ, "Association"],
      iFieldErr[startSpec, "Access", AssociationQ, "Association"],
      iFieldErr[startSpec, "Environment", AssociationQ, "Association"],
      iFieldErr[startSpec, "BudgetGrant", AssociationQ, "Association"],
      iFieldErr[startSpec, "CheckpointPolicy", AssociationQ, "Association"],
      iFieldErr[startSpec, "ArtifactContract", AssociationQ, "Association"],
      iEnumErr[startSpec, "ReusePolicy", $iReusePolicies],
      iFieldErr[startSpec, "CreatedAt", DateObjectQ, "DateObject"]
    };
    worker = Lookup[startSpec, "Worker", <||>];
    If[AssociationQ[worker],
      errs = Flatten @ {errs,
        iPrefixErrs["Worker", Flatten @ Map[
          iFieldErr[worker, #, StringQ, "String"] &,
          {"Provider", "Model", "RuntimeProfile", "AdapterFactory"}]]}];
    task = Lookup[startSpec, "Task", <||>];
    If[AssociationQ[task],
      errs = Flatten @ {errs,
        iPrefixErrs["Task", Flatten @ {
          If[KeyExistsQ[task, "GoalRef"], {}, {"Missing field: GoalRef"}],
          iFieldErr[task, "InputArtifactRefs", ListQ, "List"],
          iFieldErr[task, "ExpectedArtifactType", iStrQ,
            "non-empty String"],
          iFieldErr[task, "OutputSchema", AssociationQ, "Association"],
          iFieldErr[task, "DeterministicChecks", iListOfStrQ,
            "list of String"]}]}];
    access = Lookup[startSpec, "Access", <||>];
    If[AssociationQ[access],
      errs = Flatten @ {errs,
        iPrefixErrs["Access", Flatten @ {
          iFieldErr[access, "AccessList", ListQ, "List"],
          iFieldErr[access, "AccessSpec", AssociationQ, "Association"],
          iFieldErr[access, "AccessSpecHash", iStrQ, "non-empty String"],
          If[KeyExistsQ[access, "PolicySnapshotRef"], {},
            {"Missing field: PolicySnapshotRef"}],
          iFieldErr[access, "PolicySnapshotHash", iStrQ,
            "non-empty String"],
          iFieldErr[access, "PrivacyLabel", iPrivacyQ,
            "numeric in [0,1]"],
          iFieldErr[access, "AllowedCapabilities", iListOfStrQ,
            "list of String"]}]}];
    If[AssociationQ[Lookup[startSpec, "Environment", None]],
      errs = Flatten @ {errs, iPrefixErrs["Environment",
        iValidateEnvironmentSpec[startSpec[["Environment"]]]]}];
    If[AssociationQ[Lookup[startSpec, "BudgetGrant", None]],
      errs = Flatten @ {errs, iPrefixErrs["BudgetGrant",
        iValidateBudgetGrant[startSpec[["BudgetGrant"]]]]}];
    If[AssociationQ[Lookup[startSpec, "CheckpointPolicy", None]],
      errs = Flatten @ {errs, iPrefixErrs["CheckpointPolicy",
        iValidateCheckpointPolicy[startSpec[["CheckpointPolicy"]]]]}];
    If[AssociationQ[Lookup[startSpec, "ArtifactContract", None]],
      errs = Flatten @ {errs, iPrefixErrs["ArtifactContract",
        iValidateArtifactContract[startSpec[["ArtifactContract"]]]]}];
    errs
  ];

(* ── dispatcher ── *)

ClaudeSessionValidate[schema_String, obj_] :=
  Module[{errs},
    If[!AssociationQ[obj],
      Return[<|"Valid" -> False, "Schema" -> schema,
               "Errors" -> {"NotAnAssociation"}|>]];
    errs = Switch[schema,
      "SessionStartSpec",          iValidateStartSpec[obj],
      "EnvironmentSpec",           iValidateEnvironmentSpec[obj],
      "BudgetGrant",               iValidateBudgetGrant[obj],
      "BudgetSnapshot",            iValidateBudgetSnapshot[obj],
      "CheckpointPolicy",          iValidateCheckpointPolicy[obj],
      "RuntimeCheckpointManifest", iValidateCheckpointManifest[obj],
      "ArtifactContract",          iValidateArtifactContract[obj],
      "ArtifactCandidate",         iValidateArtifactCandidate[obj],
      "SessionControlEvent",       iValidateControlEvent[obj],
      "SessionCommand",            iValidateCommand[obj],
      "EventCursor",               iValidateCursor[obj],
      _,                           {"UnknownSchema: " <> schema}
    ];
    <|"Valid" -> errs === {}, "Schema" -> schema, "Errors" -> errs|>
  ];

(* ── event batch validation (§11.2: gap は fail-closed) ── *)

ClaudeSessionValidateEventBatch[events_List, cursor_Association] :=
  Module[{errs = {}, curCheck, att, expectSeq, next, stop = False},
    curCheck = ClaudeSessionValidate["EventCursor", cursor];
    If[!curCheck[["Valid"]],
      Return[<|"Valid" -> False,
               "Errors" -> Prepend[curCheck[["Errors"]], "InvalidCursor"],
               "NextCursor" -> cursor|>]];
    att       = cursor[["Attempt"]];
    expectSeq = cursor[["EventSeq"]] + 1;
    next      = cursor;
    Do[
      If[!stop,
        Module[{ev = events[[i]], v, tag},
          tag = "Event " <> ToString[i] <> ": ";
          v = ClaudeSessionValidate["SessionControlEvent", ev];
          Which[
            !v[["Valid"]],
              errs = Join[errs,
                Map[(tag <> #) &, v[["Errors"]]]]; stop = True,
            Lookup[ev, "Source", None] =!= "Runtime",
              AppendTo[errs,
                tag <> "non-Runtime Source in poll batch"]; stop = True,
            !ClaudeSessionVerifyEventHash[ev],
              AppendTo[errs, tag <> "EventHash mismatch"]; stop = True,
            Lookup[ev, "Attempt", None] =!= att,
              AppendTo[errs, tag <> "Attempt mismatch"]; stop = True,
            Lookup[ev, "EventSeq", None] =!= expectSeq,
              AppendTo[errs,
                tag <> "EventSeq gap (expected " <> ToString[expectSeq] <>
                ", got " <> ToString[Lookup[ev, "EventSeq", None]] <> ")"];
              stop = True,
            True,
              expectSeq = expectSeq + 1;
              next = <|"Attempt" -> att,
                       "EventSeq" -> ev[["EventSeq"]]|>
          ]
        ]
      ],
      {i, Length[events]}
    ];
    <|"Valid" -> errs === {}, "Errors" -> errs, "NextCursor" -> next|>
  ];

(* ::Subsection:: *)
(* backend registry (§8.1) *)

If[!AssociationQ[$iRuntimeSessionBackends],
  $iRuntimeSessionBackends = <||>];

$iBackendRequiredFns = {
  "StartEpisode", "PollEvents", "SendCommand",
  "Inspect", "Recover", "Dispose"};

iCallableQ[f_] :=
  MatchQ[f, _Function] ||
  (MatchQ[f, _Symbol] && Length[DownValues[f]] > 0);

ClaudeRegisterRuntimeSessionBackend[name_String, backend_Association] :=
  Module[{errs = {}},
    If[Lookup[backend, "ProtocolVersion", None] =!= 1,
      AppendTo[errs, "ProtocolVersion must be 1"]];
    If[!iListOfStrQ[Lookup[backend, "Capabilities", None]],
      AppendTo[errs, "Capabilities must be a list of String"]];
    Scan[
      Function[fnName,
        If[!iCallableQ[Lookup[backend, fnName, None]],
          AppendTo[errs,
            "Missing or non-callable contract fn: " <> fnName]]],
      $iBackendRequiredFns];
    If[errs =!= {},
      Failure["InvalidBackend",
        <|"MessageTemplate" -> "backend `1` rejected",
          "MessageParameters" -> {name},
          "Backend" -> name, "Errors" -> errs|>],
      AssociateTo[$iRuntimeSessionBackends, name -> backend];
      <|"Status" -> "Registered", "Backend" -> name,
        "Capabilities" -> Lookup[backend, "Capabilities", {}]|>
    ]
  ];

ClaudeUnregisterRuntimeSessionBackend[name_String] :=
  If[KeyExistsQ[$iRuntimeSessionBackends, name],
    ($iRuntimeSessionBackends = KeyDrop[$iRuntimeSessionBackends, name];
     <|"Status" -> "Unregistered", "Backend" -> name|>),
    <|"Status" -> "NotRegistered", "Backend" -> name|>
  ];

ClaudeRuntimeSessionBackends[] := Keys[$iRuntimeSessionBackends];

ClaudeRuntimeSessionBackendInfo[name_String] :=
  Module[{b = Lookup[$iRuntimeSessionBackends, name,
            Missing["NoSuchBackend"]]},
    If[MissingQ[b],
      Failure["NoSuchBackend", <|"Backend" -> name,
        "Known" -> Keys[$iRuntimeSessionBackends]|>],
      <|"Backend" -> name,
        "ProtocolVersion" -> Lookup[b, "ProtocolVersion", None],
        "Capabilities" -> Lookup[b, "Capabilities", {}],
        "ContractFns" ->
          Select[$iBackendRequiredFns,
            iCallableQ[Lookup[b, #, None]] &]|>
    ]
  ];

(* ::Subsection:: *)
(* MockRuntimeSession backend *)

If[!AssociationQ[$iMockRuntimeSessions],
  $iMockRuntimeSessions = <||>];
If[!AssociationQ[$iMockRuntimeSessionStarts],
  $iMockRuntimeSessionStarts = <||>];
If[!AssociationQ[$iMockRuntimeSessionEpisodes],
  $iMockRuntimeSessionEpisodes = <||>];

ClaudeMockRuntimeSessionReset[] := (
  $iMockRuntimeSessions        = <||>;
  $iMockRuntimeSessionStarts   = <||>;
  $iMockRuntimeSessionEpisodes = <||>;
  <|"Status" -> "Reset"|>
);

iMockDefaultBudgetSnapshot[startSpec_Association, seq_Integer] :=
  Module[{g = Lookup[startSpec, "BudgetGrant", <||>]},
    <|"Turns" -> seq, "Calls" -> seq, "ToolCalls" -> 0,
      "InputTokens" -> 0, "OutputTokens" -> 0,
      "WallClockSeconds" -> 0., "IdleSeconds" -> 0.,
      "BytesWritten" -> 0, "NetworkRequests" -> 0,
      "ActualUSD" -> None, "ReservedUSD" -> None,
      "CostSource" -> "Unknown",
      "BudgetGrantId" -> Lookup[g, "BudgetGrantId", "grant-unknown"],
      "BudgetGrantVersion" -> Lookup[g, "Version", 1]|>
  ];

iMockMaterializeEvent[startSpec_Association, template_Association,
                      seq_Integer, backendInstanceId_String] :=
  Module[{access = Lookup[startSpec, "Access", <||>], ev},
    ev = <|
      "SchemaVersion" -> 1,
      "EventId"   -> ClaudeSessionNewId["Event"],
      "EventSeq"  -> seq,
      "SessionId" -> Lookup[startSpec, "SessionId", "ses-unknown"],
      "EpisodeId" -> Lookup[startSpec, "EpisodeId", "epi-unknown"],
      "Attempt"   -> Lookup[startSpec, "Attempt", 1],
      "BackendInstanceId" -> backendInstanceId,
      "Source"    -> "Runtime",
      "Type"      -> Lookup[template, "Type", "Completed"],
      "SupersedesThroughSeq" ->
        Lookup[template, "SupersedesThroughSeq", None],
      "PayloadRefs" -> Lookup[template, "PayloadRefs", <||>],
      "LatestCheckpointRef" ->
        Lookup[template, "LatestCheckpointRef", None],
      "BudgetSnapshot" -> Lookup[template, "BudgetSnapshot",
        iMockDefaultBudgetSnapshot[startSpec, seq]],
      "AccessSpecHash" -> Lookup[access, "AccessSpecHash", ""],
      "PolicySnapshotHash" -> Lookup[access, "PolicySnapshotHash", ""],
      "PrivacyLabel" -> Lookup[template, "PrivacyLabel",
        Lookup[access, "PrivacyLabel", 1.0]],
      "CreatedAt" -> DateObject[]
    |>;
    Append[ev, "EventHash" -> ClaudeSessionEventHash[ev]]
  ];

iMockNextSeq[st_Association] :=
  If[st[["Events"]] === {}, 1,
    Max[Map[#[["EventSeq"]] &, st[["Events"]]]] + 1];

iMockStartEpisode[mockOpts_Association, startSpec_Association] :=
  Module[{epi, att, scmd, startKey, epiKey, handleRef, bki, script,
          events, vErrs},
    If[TrueQ @ Lookup[mockOpts, "FailStart", False],
      Return[<|"Status" -> "Failed",
               "Reason" -> "MockConfiguredStartFailure"|>]];
    epi  = Lookup[startSpec, "EpisodeId", None];
    att  = Lookup[startSpec, "Attempt", 1];
    scmd = Lookup[startSpec, "StartCommandId", "(no-start-command-id)"];
    If[!StringQ[epi],
      Return[<|"Status" -> "Failed", "Reason" -> "MissingEpisodeId"|>]];
    startKey = {epi, att, scmd};
    epiKey   = {epi, att};

    (* (EpisodeId, Attempt, StartCommandId) 冪等 (§10.1) *)
    If[KeyExistsQ[$iMockRuntimeSessionStarts, startKey],
      Module[{h = $iMockRuntimeSessionStarts[startKey], st},
        st = Lookup[$iMockRuntimeSessions, h, <||>];
        Return[<|"Status" -> "AlreadyStarted",
          "SessionId" -> Lookup[st, "SessionId", None],
          "EpisodeId" -> epi,
          "HandleRef" -> h,
          "BackendInstanceId" -> Lookup[st, "BackendInstanceId", None],
          "InitialEventCursor" ->
            <|"Attempt" -> att, "EventSeq" -> 0|>,
          "PIDRef" -> None|>]
      ]];

    (* 同一 (EpisodeId, Attempt) を異なる StartCommandId で二重起動する
       のは orchestrator 側のバグ → 起動しない (fail-closed) *)
    If[KeyExistsQ[$iMockRuntimeSessionEpisodes, epiKey],
      Return[<|"Status" -> "Failed",
               "Reason" -> "EpisodeAlreadyActiveWithDifferentStartCommandId"|>]];

    handleRef = "mockh-" <> ToLowerCase[StringDelete[CreateUUID[], "-"]];
    bki       = ClaudeSessionNewId["BackendInstance"];
    script    = Lookup[mockOpts, "EventScript", Automatic];
    If[script === Automatic, script = {<|"Type" -> "Completed"|>}];

    events = MapIndexed[
      iMockMaterializeEvent[startSpec, #1, First[#2], bki] &,
      script];

    If[TrueQ @ Lookup[mockOpts, "ValidateEvents", True],
      vErrs = Flatten @ Map[
        Function[ev,
          Module[{v = ClaudeSessionValidate["SessionControlEvent", ev]},
            If[v[["Valid"]], {}, v[["Errors"]]]]],
        events];
      If[vErrs =!= {},
        Return[<|"Status" -> "Failed",
                 "Reason" -> "MockScriptProducedInvalidEvents",
                 "Errors" -> Take[vErrs, UpTo[8]]|>]]];

    AssociateTo[$iMockRuntimeSessions, handleRef -> <|
      "SessionId" -> Lookup[startSpec, "SessionId", "ses-unknown"],
      "EpisodeId" -> epi, "Attempt" -> att,
      "BackendInstanceId" -> bki,
      "StartSpec" -> startSpec,
      "Events" -> events,
      "FetchedSeq" -> 0,
      "AcceptedCommands" -> <||>,
      "Disposed" -> False,
      "Options" -> mockOpts|>];
    AssociateTo[$iMockRuntimeSessionStarts, startKey -> handleRef];
    AssociateTo[$iMockRuntimeSessionEpisodes, epiKey -> handleRef];

    <|"Status" -> "Started",
      "SessionId" -> Lookup[startSpec, "SessionId", "ses-unknown"],
      "EpisodeId" -> epi,
      "HandleRef" -> handleRef,
      "BackendInstanceId" -> bki,
      "InitialEventCursor" -> <|"Attempt" -> att, "EventSeq" -> 0|>,
      "PIDRef" -> None|>
  ];

iMockPollEvents[handleRef_, cursor_Association] :=
  Module[{st, att, seq, evs, nextSeq},
    st = Lookup[$iMockRuntimeSessions, handleRef, Missing["NoHandle"]];
    If[MissingQ[st],
      Return[<|"Status" -> "Lost", "Events" -> {},
               "NextCursor" -> cursor, "HeartbeatAt" -> None|>]];
    If[TrueQ[st[["Disposed"]]],
      Return[<|"Status" -> "Unavailable", "Events" -> {},
               "NextCursor" -> cursor, "HeartbeatAt" -> None|>]];
    att = Lookup[cursor, "Attempt", None];
    seq = Lookup[cursor, "EventSeq", None];
    If[att =!= st[["Attempt"]] || !IntegerQ[seq] || seq < 0,
      Return[<|"Status" -> "OK", "Events" -> {},
               "NextCursor" ->
                 <|"Attempt" -> st[["Attempt"]],
                   "EventSeq" -> st[["FetchedSeq"]]|>,
               "HeartbeatAt" -> DateObject[]|>]];
    evs = Select[st[["Events"]], #[["EventSeq"]] > seq &];
    nextSeq = If[evs === {}, seq,
      Max[Map[#[["EventSeq"]] &, evs]]];
    AssociateTo[st, "FetchedSeq" -> Max[st[["FetchedSeq"]], nextSeq]];
    AssociateTo[$iMockRuntimeSessions, handleRef -> st];
    <|"Status" -> "OK", "Events" -> evs,
      "NextCursor" -> <|"Attempt" -> att, "EventSeq" -> nextSeq|>,
      "HeartbeatAt" -> DateObject[]|>
  ];

iMockSendCommand[handleRef_, cmd_Association] :=
  Module[{st, v, cid, expSeq, ackSeq, ev},
    st = Lookup[$iMockRuntimeSessions, handleRef, Missing["NoHandle"]];
    If[MissingQ[st] || TrueQ[st[["Disposed"]]],
      Return[<|"Status" -> "Unavailable",
               "CommandId" -> Lookup[cmd, "CommandId", None],
               "Reason" -> "NoSuchHandle"|>]];
    v = ClaudeSessionValidate["SessionCommand", cmd];
    If[!v[["Valid"]],
      Return[<|"Status" -> "Rejected",
               "CommandId" -> Lookup[cmd, "CommandId", None],
               "Reason" -> "InvalidCommand: " <>
                 StringRiffle[Take[v[["Errors"]], UpTo[3]], "; "]|>]];
    cid = cmd[["CommandId"]];
    If[KeyExistsQ[st[["AcceptedCommands"]], cid],
      Return[<|"Status" -> "AlreadyAccepted", "CommandId" -> cid,
               "Reason" -> "DuplicateCommandId"|>]];
    (* Inc3 テスト用: 常に Rejected を返す設定 (CommandRejected 経路の検証) *)
    If[TrueQ @ Lookup[st[["Options"]], "RejectCommands", False],
      Return[<|"Status" -> "Rejected", "CommandId" -> cid,
               "Reason" -> "MockConfiguredReject"|>]];
    (* Attempt 不一致は常に拒否 (§7.8。Cancel も例外なし) *)
    If[cmd[["Attempt"]] =!= st[["Attempt"]],
      Return[<|"Status" -> "Rejected", "CommandId" -> cid,
               "Reason" -> "StaleAttempt"|>]];
    (* ExpectedAfterEventSeq は optimistic concurrency precondition。
       Cancel だけ stale context を許す (§7.8)。 *)
    expSeq = cmd[["ExpectedAfterEventSeq"]];
    If[cmd[["Type"]] =!= "Cancel" && expSeq =!= st[["FetchedSeq"]],
      Return[<|"Status" -> "Rejected", "CommandId" -> cid,
               "Reason" -> "StaleContext"|>]];

    AssociateTo[st, "AcceptedCommands" ->
      Append[st[["AcceptedCommands"]],
        cid -> <|"Type" -> cmd[["Type"]],
                 "AcceptedAt" -> DateObject[]|>]];

    If[TrueQ @ Lookup[st[["Options"]], "AckEvents", True],
      ackSeq = iMockNextSeq[st];
      ev = iMockMaterializeEvent[st[["StartSpec"]],
        <|"Type" -> "CommandAccepted",
          "PayloadRefs" -> <|"CommandId" -> cid|>|>,
        ackSeq, st[["BackendInstanceId"]]];
      AssociateTo[st, "Events" -> Append[st[["Events"]], ev]]];

    If[cmd[["Type"]] === "Cancel" &&
       TrueQ @ Lookup[st[["Options"]], "TerminalOnCancel", True],
      Module[{cSeq, cEv},
        cSeq = iMockNextSeq[st];
        cEv = iMockMaterializeEvent[st[["StartSpec"]],
          <|"Type" -> "Cancelled",
            "PayloadRefs" -> <|"CommandId" -> cid|>|>,
          cSeq, st[["BackendInstanceId"]]];
        AssociateTo[st, "Events" -> Append[st[["Events"]], cEv]]]];

    AssociateTo[$iMockRuntimeSessions, handleRef -> st];
    <|"Status" -> "Accepted", "CommandId" -> cid, "Reason" -> None|>
  ];

iMockInspect[handleRef_] :=
  Module[{st = Lookup[$iMockRuntimeSessions, handleRef,
            Missing["NoHandle"]]},
    If[MissingQ[st],
      Failure["NoSuchHandle", <|"HandleRef" -> handleRef|>],
      <|"HandleRef" -> handleRef,
        "SessionId" -> st[["SessionId"]],
        "EpisodeId" -> st[["EpisodeId"]],
        "Attempt" -> st[["Attempt"]],
        "BackendInstanceId" -> st[["BackendInstanceId"]],
        "EventCount" -> Length[st[["Events"]]],
        "FetchedSeq" -> st[["FetchedSeq"]],
        "AcceptedCommandIds" -> Keys[st[["AcceptedCommands"]]],
        "Disposed" -> st[["Disposed"]]|>
    ]
  ];

iMockRecover[episodeRecord_Association] :=
  Module[{h = Lookup[episodeRecord, "HandleRef", None], st},
    st = If[StringQ[h],
      Lookup[$iMockRuntimeSessions, h, Missing["NoHandle"]],
      Missing["NoHandle"]];
    If[!MissingQ[st] && !TrueQ[st[["Disposed"]]],
      <|"Status" -> "Reattached", "HandleRef" -> h,
        "ResumedCheckpointRef" -> None|>,
      <|"Status" -> "LostUnrecoverable", "HandleRef" -> None,
        "ResumedCheckpointRef" -> None|>
    ]
  ];

iMockDispose[handleRef_, cleanupPolicy_] :=
  Module[{st = Lookup[$iMockRuntimeSessions, handleRef,
            Missing["NoHandle"]]},
    Which[
      MissingQ[st],           <|"Status" -> "AlreadyDisposed"|>,
      TrueQ[st[["Disposed"]]], <|"Status" -> "AlreadyDisposed"|>,
      True,
        AssociateTo[st, "Disposed" -> True];
        AssociateTo[$iMockRuntimeSessions, handleRef -> st];
        <|"Status" -> "Disposed"|>
    ]
  ];

Options[ClaudeMockRuntimeSessionBackendSpec] = {
  "EventScript"      -> Automatic,
  "AckEvents"        -> True,
  "TerminalOnCancel" -> True,
  "FailStart"        -> False,
  "RejectCommands"   -> False,
  "ValidateEvents"   -> True};

ClaudeMockRuntimeSessionBackendSpec[opts:OptionsPattern[]] :=
  Module[{mockOpts},
    mockOpts = <|
      "EventScript"      -> OptionValue["EventScript"],
      "AckEvents"        -> OptionValue["AckEvents"],
      "TerminalOnCancel" -> OptionValue["TerminalOnCancel"],
      "FailStart"        -> OptionValue["FailStart"],
      "RejectCommands"   -> OptionValue["RejectCommands"],
      "ValidateEvents"   -> OptionValue["ValidateEvents"]|>;
    <|
      "ProtocolVersion" -> 1,
      "Capabilities" -> {
        "ToolLoop", "EventReplay", "Checkpoint", "Resume", "Interrupt"},
      "StartEpisode" ->
        Function[startSpec, iMockStartEpisode[mockOpts, startSpec]],
      "PollEvents" ->
        Function[{h, cursor}, iMockPollEvents[h, cursor]],
      "SendCommand" ->
        Function[{h, cmd}, iMockSendCommand[h, cmd]],
      "Inspect" ->
        Function[h, iMockInspect[h]],
      "Recover" ->
        Function[rec, iMockRecover[rec]],
      "Dispose" ->
        Function[{h, pol}, iMockDispose[h, pol]]
    |>
  ];

(* ::Subsection:: *)
(* StartSpec template (テスト / Inc2 用) *)

Options[ClaudeSessionStartSpecTemplate] = {
  "WorkflowId"     -> Automatic,
  "TaskId"         -> Automatic,
  "SessionId"      -> Automatic,
  "EpisodeId"      -> Automatic,
  "StartCommandId" -> Automatic,
  "Attempt"        -> 1,
  "Backend"        -> "MockRuntimeSession",
  "PrivacyLabel"   -> 1.0,
  "GoalRef"        -> "mock-goal",
  "ReusePolicy"    -> "Never"};

iAutoOr[v_, generator_] := If[v === Automatic, generator, v];

ClaudeSessionStartSpecTemplate[opts:OptionsPattern[]] :=
  Module[{stagingRoot, accessSpec, grant0, grant, checkpointPolicy,
          contract, env},
    stagingRoot = FileNameJoin[{$TemporaryDirectory,
      "claude-mock-staging"}];
    accessSpec = <|
      "ExecutionRole" -> "MockWorker",
      "MayAccessFileSystem" -> "None",
      "MayWriteNotebook" -> False,
      "MayUseNetwork" -> False,
      "AllowedDirectories" -> {},
      "AllowedNetworkTargets" -> {},
      "AllowedExternalCommands" -> {},
      "CredentialRefs" -> {}, "SecretRefs" -> {},
      "ConfidentialHandling" -> "ReferenceOnly"|>;
    grant0 = <|
      "BudgetGrantId" -> ClaudeSessionNewId["Command"] <> "-grant",
      "Version" -> 1,
      "Objective" -> "CompleteWithinBudget",
      "HardLimits" -> <|
        "MaxTurns" -> 100, "MaxCalls" -> 100, "MaxToolCalls" -> 100,
        "MaxInputTokens" -> 1000000, "MaxOutputTokens" -> 1000000,
        "MaxContextTokensPerStep" -> 200000,
        "MaxWallClockSeconds" -> 3600., "MaxIdleSeconds" -> 600.,
        "MaxBytesWritten" -> 100000000, "MaxNetworkRequests" -> 100,
        "MaxCostUSD" -> None|>,
      "SoftThresholds" ->
        <|"WarnFraction" -> 0.8, "CheckpointFraction" -> 0.9|>,
      "UnknownCostPolicy" -> "Reject",
      "IssuedAt" -> DateObject[]|>;
    grant = Append[grant0, "GrantHash" -> ClaudeSessionGrantHash[grant0]];
    checkpointPolicy = <|
      "Enabled" -> True,
      "Routine" -> <|
        "AtEpisodeStart" -> True, "AfterToolCalls" -> 5,
        "EverySeconds" -> 300, "EmitControlEvent" -> False|>,
      "Boundary" -> <|
        "BeforeNonIdempotentTool" -> True,
        "AtSoftBudgetThreshold" -> True,
        "OnInterrupt" -> True, "OnExplicitRequest" -> True,
        "EmitControlEvent" -> True|>,
      "MaxRetained" -> 5,
      "Storage" -> "ReferenceOnly",
      "RequireHashVerification" -> True|>;
    contract = <|
      "ExpectedArtifactType" -> "MockArtifact",
      "OutputSchema" -> <||>,
      "AllowedStagingRoot" -> stagingRoot,
      "MaxArtifactBytes" -> 1000000,
      "RequiredChecks" -> {},
      "CommitTargetRef" -> None,
      "BaseRevision" -> None,
      "CommitMode" -> "ArtifactStore",
      "RequireProvenance" -> True|>;
    env = <|
      "IsolationLevel" -> "CooperativeKernel",
      "EnvironmentLeaseId" -> ClaudeSessionNewId["Lease"],
      "BaseSnapshotRef" -> None,
      "ReadOnlyInputRoots" -> {},
      "WritableStagingRoot" -> stagingRoot,
      "FinalTargetRefs" -> {},
      "AllowedDirectories" -> {stagingRoot},
      "AllowedNetworkTargets" -> {},
      "AllowedExternalCommands" -> {},
      "CredentialRefs" -> {}, "SecretRefs" -> {},
      "ConfidentialHandling" -> "ReferenceOnly",
      "CleanupPolicy" -> <|"DeleteStagingOnDispose" -> True|>|>;
    <|
      "SchemaVersion" -> 1,
      "WorkflowId" -> iAutoOr[OptionValue["WorkflowId"],
        "wf-" <> ToLowerCase[StringDelete[CreateUUID[], "-"]]],
      "RunId" -> None,
      "TaskId" -> iAutoOr[OptionValue["TaskId"],
        "task-" <> ToLowerCase[StringDelete[CreateUUID[], "-"]]],
      "SessionId" -> iAutoOr[OptionValue["SessionId"],
        ClaudeSessionNewId["Session"]],
      "EpisodeId" -> iAutoOr[OptionValue["EpisodeId"],
        ClaudeSessionNewId["Episode"]],
      "Attempt" -> OptionValue["Attempt"],
      "StartCommandId" -> iAutoOr[OptionValue["StartCommandId"],
        ClaudeSessionNewId["StartCommand"]],
      "Backend" -> OptionValue["Backend"],
      "Worker" -> <|
        "Provider" -> "mock", "Model" -> "mock-model",
        "RuntimeProfile" -> "mock", "AdapterFactory" -> "mock"|>,
      "Task" -> <|
        "GoalRef" -> OptionValue["GoalRef"],
        "InputArtifactRefs" -> {},
        "ExpectedArtifactType" -> "MockArtifact",
        "OutputSchema" -> <||>,
        "DeterministicChecks" -> {}|>,
      "Access" -> <|
        "AccessList" -> {},
        "AccessSpec" -> accessSpec,
        "AccessSpecHash" -> ClaudeSessionAccessSpecHash[accessSpec],
        "PolicySnapshotRef" -> None,
        "PolicySnapshotHash" ->
          ClaudeSessionCanonicalHash[<|"Policy" -> "mock-empty"|>],
        "PrivacyLabel" -> OptionValue["PrivacyLabel"],
        "AllowedCapabilities" -> {}|>,
      "Environment" -> env,
      "BudgetGrant" -> grant,
      "CheckpointPolicy" -> checkpointPolicy,
      "ArtifactContract" -> contract,
      "ReusePolicy" -> OptionValue["ReusePolicy"],
      "CreatedAt" -> DateObject[]
    |>
  ];

(* ::Subsection:: *)
(* Inc2: episode supervisor net (§9/§10) *)

(* ── registry / quarantine ──
   ActiveSessionEpisodes は §10.5 のとおり「poll/recovery 対象の導出 index」。
   正本は EpisodeActive place の SessionLease token であり、registry は
   transition handler が同じ箇所で更新する。 *)

If[!AssociationQ[$iActiveSessionEpisodes],
  $iActiveSessionEpisodes = <||>];   (* key: {wid, episodeId} *)
If[!ListQ[$iSessionQuarantineLog],
  $iSessionQuarantineLog = {}];

ClaudeSessionActiveEpisodes[] := $iActiveSessionEpisodes;
ClaudeSessionQuarantine[]     := $iSessionQuarantineLog;

iSesQuarantine[reason_String, payload_] := (
  AppendTo[$iSessionQuarantineLog,
    <|"Reason" -> reason, "Payload" -> payload, "At" -> DateObject[]|>];
  <|"Status" -> "Quarantined", "Reason" -> reason|>);

iSesAnyActiveEpisodeQ[wid_String] :=
  AnyTrue[Keys[$iActiveSessionEpisodes],
    ListQ[#] && Length[#] >= 1 && #[[1]] === wid &];

iSesSetEpisodeState[wid_, episodeId_, newState_String] :=
  Module[{k = {wid, episodeId}},
    If[KeyExistsQ[$iActiveSessionEpisodes, k],
      AssociateTo[$iActiveSessionEpisodes,
        k -> Append[$iActiveSessionEpisodes[k], "State" -> newState]]]
  ];

iSesRegistryStateFor[cs_] := Which[
  MemberQ[{"Running", "CheckpointReview"}, cs], "Running",
  MemberQ[{"Cancelling", "Closing", "Completed", "Failed",
           "Cancelled", "EnvironmentLost", "Closed"}, cs], "Closing",
  True, "Suspended"];

(* ── 語彙 ── *)

$iSesTerminalEventTypes = {"Failed", "Cancelled", "EnvironmentLost"};

(* command 発行を許す ControlState (§9.5 の command 行)。
   Cancel/Stop は I13 により全 non-terminal state から可 *)
$iSesCommandAllowedStates = <|
  "Cancel" -> All, "Stop" -> All,
  "ProvideObservation"  -> {"AwaitingObservation"},
  "GrantScopedApproval" -> {"AwaitingApproval"},
  "GrantBudget"         -> {"BudgetReview"},
  "RequestCheckpoint"   -> {"Running"},
  "AcceptArtifact"      -> {"ArtifactReview"},
  "RepairArtifact"      -> {"ArtifactReview"},
  "Ping"                -> {"Running"}|>;

(* CommandAccepted 適用後の ControlState (§9.5)。未掲載は Origin へ戻す *)
$iSesCommandResumeState = <|
  "ProvideObservation"  -> "Running",
  "GrantScopedApproval" -> "Running",
  "GrantBudget"         -> "Running",
  "RequestCheckpoint"   -> "Running",
  "AcceptArtifact"      -> "Closing",
  "RepairArtifact"      -> "Running",
  "Stop"                -> "Closing",
  "Cancel"              -> "Cancelling"|>;

(* ── binding アクセサ ── *)

iSesLeaseOf[binding_Association] :=
  Lookup[Lookup[binding, "EpisodeActive", <||>], "Payload", <||>];

iSesEventOf[binding_Association] :=
  Lookup[Lookup[binding, "SessionEvents", <||>], "Payload", <||>];

(* ── §9.4 pairing Guard 本体 ──
   sameEpisodeQ ∧ (normalSeqQ ∨ terminalPreemptQ ∨ synthetic) ∧ sameHashQ
   (hash 照合は Runtime source のみ。synthetic は SyntheticBaseEventSeq
    照合で置き換える §11.2.1)。 *)

iSesPairingOKQ[lease_Association, ev_Association] :=
  Module[{src, sameEp, seqOK, hashOK, lastSeq},
    src     = Lookup[ev, "Source", None];
    lastSeq = Lookup[lease, "LastAppliedEventSeq", 0];
    sameEp =
      Lookup[ev, "EpisodeId", "?e"]  === Lookup[lease, "EpisodeId", "?l"] &&
      Lookup[ev, "SessionId", "?e"]  === Lookup[lease, "SessionId", "?l"] &&
      Lookup[ev, "Attempt", -1]      === Lookup[lease, "Attempt", -2];
    Which[
      !TrueQ[sameEp], False,
      src === "Runtime",
        seqOK =
          Lookup[ev, "EventSeq", None] === lastSeq + 1 ||
          (MemberQ[$iSesTerminalEventTypes, Lookup[ev, "Type", None]] &&
           IntegerQ[Lookup[ev, "EventSeq", None]] &&
           Lookup[ev, "EventSeq", None] > lastSeq + 1 &&
           Lookup[ev, "SupersedesThroughSeq", None] ===
             Lookup[ev, "EventSeq", None] - 1);
        hashOK =
          Lookup[ev, "AccessSpecHash", "?e"] ===
            Lookup[lease, "AccessSpecHash", "?l"] &&
          Lookup[ev, "PolicySnapshotHash", "?e"] ===
            Lookup[lease, "PolicySnapshotHash", "?l"];
        TrueQ[seqOK && hashOK],
      MemberQ[{"OrchestratorWatchdog", "RecoveryScan", "Bridge"}, src],
        TrueQ[
          Lookup[ev, "EventSeq", "?"] === None &&
          Lookup[ev, "SyntheticBaseEventSeq", None] === lastSeq],
      True, False
    ]
  ];

(* Guard/handler ファクトリ。Guard は列挙時と fire 直前の二回評価されるため
   純関数・副作用なしとする (§10.1)。 *)

iSesMakeEventGuard[allowedTypes_List, allowedStates_, extraQ_] :=
  With[{types = allowedTypes, states = allowedStates, extra = extraQ},
    Function[binding,
      Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding]},
        TrueQ[
          MemberQ[types, Lookup[ev, "Type", None]] &&
          (states === All ||
           MemberQ[states, Lookup[lease, "ControlState", None]]) &&
          iSesPairingOKQ[lease, ev] &&
          (extra === None || TrueQ[Quiet @ extra[lease, ev]])]
      ]
    ]
  ];

iSesApplyEvent[lease_Association, ev_Association, nextState_String] :=
  Module[{l2, src = Lookup[ev, "Source", "Runtime"]},
    l2 = Append[lease, {
      "ControlState" -> nextState,
      (* SyntheticControlEvent は Runtime sequence を消費しない (§11.2.1) *)
      "LastAppliedEventSeq" ->
        If[src === "Runtime",
          Lookup[ev, "EventSeq", Lookup[lease, "LastAppliedEventSeq", 0]],
          Lookup[lease, "LastAppliedEventSeq", 0]],
      "LastEvent" -> <|
        "Type" -> Lookup[ev, "Type", None],
        "EventId" -> Lookup[ev, "EventId", None],
        "EventSeq" -> Lookup[ev, "EventSeq", None],
        "Source" -> src|>,
      "LastBudgetSnapshot" -> Lookup[ev, "BudgetSnapshot", <||>]}];
    If[Lookup[ev, "LatestCheckpointRef", None] =!= None,
      l2 = Append[l2,
        "LatestCheckpointRef" -> Lookup[ev, "LatestCheckpointRef", None]]];
    l2
  ];

iSesMakeEventHandler[nextStateFn_] :=
  With[{nsf = nextStateFn},
    Function[binding,
      Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding],
              next, l2, wid = $ClaudeCurrentWid},
        next = nsf[lease, ev];
        l2 = iSesApplyEvent[lease, ev, next];
        If[StringQ[wid],
          iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
            iSesRegistryStateFor[next]]];
        <|"Payload" -> l2|>
      ]
    ]
  ];

(* ── 個別 handler ── *)

iSesAllocateHandler = Function[binding,
  Module[{ss},
    ss = Lookup[
      Lookup[Lookup[binding, "EpisodeRequested", <||>], "Payload", <||>],
      "StartSpec", <||>];
    <|"Payload" -> <|
      "StartSpec" -> ss,
      "EpisodeId" -> Lookup[ss, "EpisodeId", None],
      "SessionId" -> Lookup[ss, "SessionId", None],
      "Attempt"   -> Lookup[ss, "Attempt", 1],
      "Backend"   -> Lookup[ss, "Backend", None],
      "AccessSpecHash" ->
        Lookup[Lookup[ss, "Access", <||>], "AccessSpecHash", None],
      "PolicySnapshotHash" ->
        Lookup[Lookup[ss, "Access", <||>], "PolicySnapshotHash", None],
      "ControlState" -> "Starting",
      "LastAppliedEventSeq" -> 0,
      "PendingCommand" -> None,
      "HandleRef" -> None,
      "BackendInstanceId" -> None,
      "LatestCheckpointRef" -> None,
      "StatusDetail" -> None|>|>
  ]];

(* "RuntimeSession" executor 本体 (engine seam へ注入 §10.1)。
   StartEpisode だけを行い session loop を同期実行しない。
   backend Failed は engine レベルの Failed にせず ControlState=StartFailed の
   lease を produce し、HandleStartFailure が terminal へ導く。 *)
iSesExecuteRuntimeSessionBranch[trans_Association, binding_Association] :=
  Module[{lease, backendName, backend, res, l2, wid = $ClaudeCurrentWid},
    lease = Lookup[Lookup[binding, "EpisodeAllocated", <||>],
      "Payload", <||>];
    backendName = Lookup[lease, "Backend", None];
    backend = Lookup[$iRuntimeSessionBackends, backendName,
      Missing["NoBackend"]];
    If[MissingQ[backend],
      Return[<|"Status" -> "Failed",
               "Reason" -> "UnknownSessionBackend: " <>
                 ToString[backendName]|>]];
    res = Quiet @ Check[
      backend[["StartEpisode"]][Lookup[lease, "StartSpec", <||>]],
      <|"Status" -> "Failed", "Reason" -> "StartEpisodeException"|>];
    If[!AssociationQ[res],
      res = <|"Status" -> "Failed", "Reason" -> "InvalidStartResult"|>];
    Switch[Lookup[res, "Status", None],
      "Started" | "AlreadyStarted",
        l2 = Append[lease, {
          "ControlState" -> "Running",
          "HandleRef" -> Lookup[res, "HandleRef", None],
          "BackendInstanceId" -> Lookup[res, "BackendInstanceId", None],
          "StartStatus" -> Lookup[res, "Status", None]}];
        If[StringQ[wid],
          AssociateTo[$iActiveSessionEpisodes,
            {wid, Lookup[lease, "EpisodeId", None]} -> <|
              "SessionId" -> Lookup[lease, "SessionId", None],
              "Attempt" -> Lookup[lease, "Attempt", 1],
              "Backend" -> backendName,
              "HandleRef" -> Lookup[res, "HandleRef", None],
              "State" -> "Running"|>]];
        <|"Status" -> "Success", "Output" -> <|"Payload" -> l2|>|>,
      _,
        l2 = Append[lease, {
          "ControlState" -> "StartFailed",
          "StatusDetail" ->
            ToString[Lookup[res, "Reason", "StartFailed"]]}];
        <|"Status" -> "Success", "Output" -> <|"Payload" -> l2|>|>
    ]
  ];

iSesStartFailureHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding]},
    <|"Payload" -> Append[lease, {"ControlState" -> "Failed",
        "StatusDetail" -> Lookup[lease, "StatusDetail", "StartFailed"]}]|>
  ]];

iSesCompletedHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding], l2,
          wid = $ClaudeCurrentWid},
    l2 = iSesApplyEvent[lease, ev, "Completed"];
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Closing"]];
    <|"Payload" -> l2|>
  ]];

iSesTerminalHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding],
          cs, l2, wid = $ClaudeCurrentWid},
    cs = Switch[Lookup[ev, "Type", None],
      "Cancelled", "Cancelled",
      "EnvironmentLost", "EnvironmentLost",
      _, "Failed"];
    l2 = Append[iSesApplyEvent[lease, ev, cs],
      "StatusDetail" -> Lookup[ev, "Type", None]];
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Closing"]];
    <|"Payload" -> l2|>
  ]];

iSesAckHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding],
          pend, resume, l2, wid = $ClaudeCurrentWid},
    pend = Lookup[lease, "PendingCommand", <||>];
    If[!AssociationQ[pend], pend = <||>];
    resume = Lookup[$iSesCommandResumeState, Lookup[pend, "Type", None],
      Lookup[pend, "OriginControlState", "Running"]];
    l2 = iSesApplyEvent[lease, ev, resume];
    l2 = Append[l2, {"PendingCommand" -> None,
      "LastAcceptedCommand" -> pend}];
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        iSesRegistryStateFor[resume]]];
    <|"Payload" -> l2|>
  ]];

iSesRejectHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding],
          pend, origin, l2, wid = $ClaudeCurrentWid},
    pend = Lookup[lease, "PendingCommand", <||>];
    If[!AssociationQ[pend], pend = <||>];
    origin = Lookup[pend, "OriginControlState", "Running"];
    l2 = iSesApplyEvent[lease, ev, origin];
    l2 = Append[l2, {
      "PendingCommand" -> None,
      "SupersededCommands" ->
        Append[Lookup[lease, "SupersededCommands", {}],
          Append[pend, "Reason" ->
            Lookup[Lookup[ev, "PayloadRefs", <||>], "Reason", None]]]}];
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        iSesRegistryStateFor[origin]]];
    <|"Payload" -> l2|>
  ]];

(* QueueSessionCommand (§11.3): command request を SessionCommand に組み立て、
   durable outbox へ temp → atomic rename で書いてから ControlState を
   CommandPending にする。送信は poll tick / DispatchOutbox が行い、
   transport retry は同一 CommandId を使う。Rejected は Bridge が
   CommandRejected synthetic event に正規化する (§11.2.1)。 *)
iSesQueueCommandHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], req, cmd0, cmd, l2,
          wid = $ClaudeCurrentWid, reqType},
    req = Lookup[Lookup[binding, "CommandRequests", <||>],
      "Payload", <||>];
    reqType = Lookup[req, "Type", None];
    cmd0 = <|
      "SchemaVersion" -> 1,
      "CommandId" -> ClaudeSessionNewId["Command"],
      "SessionId" -> Lookup[lease, "SessionId", None],
      "EpisodeId" -> Lookup[lease, "EpisodeId", None],
      "Attempt" -> Lookup[lease, "Attempt", 1],
      "ExpectedAfterEventSeq" -> Lookup[lease, "LastAppliedEventSeq", 0],
      "Type" -> reqType,
      "PayloadRefs" -> Lookup[req, "PayloadRefs", <||>],
      "BudgetGrant" -> Lookup[req, "BudgetGrant", None],
      "ScopedPermitRef" -> None,
      "IssuedAt" -> DateObject[]|>;
    cmd = Append[cmd0, "CommandHash" -> ClaudeSessionCommandHash[cmd0]];
    Quiet @ Check[iSesOutboxPut[lease, cmd], $Failed];
    l2 = Append[lease, {
      "ControlState" -> "CommandPending",
      "PendingCommand" -> <|
        "CommandId" -> Lookup[cmd, "CommandId", None],
        "Type" -> reqType,
        "OriginControlState" ->
          Lookup[lease, "ControlState", "Running"]|>}];
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Suspended"]];
    <|"Payload" -> l2|>
  ]];

(* CleanupAndRelease: backend dispose (冪等) + registry 除去 + slot 一回返却 *)
iSesCleanupHandler = Function[binding,
  Module[{lease, backend, wid = $ClaudeCurrentWid},
    lease = Lookup[Lookup[binding, "CleanupPending", <||>],
      "Payload", <||>];
    backend = Lookup[$iRuntimeSessionBackends,
      Lookup[lease, "Backend", None], Missing["NoBackend"]];
    If[!MissingQ[backend] && Lookup[lease, "HandleRef", None] =!= None,
      Quiet @ Check[
        backend[["Dispose"]][Lookup[lease, "HandleRef", None], <||>],
        Null]];
    If[StringQ[wid],
      $iActiveSessionEpisodes = KeyDrop[$iActiveSessionEpisodes,
        {{wid, Lookup[lease, "EpisodeId", None]}}]];
    <|"Payload" -> Append[lease, "ControlState" -> "Closed"]|>
  ]];

(* ── Inc8: artifact validation / single commit (§17) ── *)

(* ArtifactCandidate 検証 (§17.1)。deterministic。sessionLabel は privacy
   単調検査用 (candidate は session label 以上 §16.4)。 *)
ClaudeSessionValidateArtifactCandidate[candidate_Association,
    contract_Association, sessionLabel_:0.0] :=
  Module[{errs = {}, sv, root, ref, refPath, checks, self},
    sv = ClaudeSessionValidate["ArtifactCandidate", candidate];
    If[!sv[["Valid"]],
      errs = Join[errs, Map["schema: " <> # &, sv[["Errors"]]]]];
    (* type 一致 *)
    If[Lookup[candidate, "ArtifactType", None] =!=
       Lookup[contract, "ExpectedArtifactType", None],
      AppendTo[errs, "ArtifactType mismatch"]];
    (* staging root 包含 (ArtifactRef が String path のとき) *)
    root = Lookup[contract, "AllowedStagingRoot", None];
    ref = Lookup[candidate, "ArtifactRef", None];
    If[StringQ[ref] && StringQ[root],
      refPath = ExpandFileName[ref];
      If[!StringStartsQ[
           If[$OperatingSystem === "Windows", ToLowerCase[refPath],
             refPath],
           If[$OperatingSystem === "Windows",
             ToLowerCase[ExpandFileName[root]],
             ExpandFileName[root]]],
        AppendTo[errs, "ArtifactRef outside AllowedStagingRoot"]]];
    (* byte 上限 *)
    If[IntegerQ[Lookup[contract, "MaxArtifactBytes", None]] &&
       Lookup[candidate, "ByteCount", Infinity] >
         contract[["MaxArtifactBytes"]],
      AppendTo[errs, "ByteCount exceeds MaxArtifactBytes"]];
    (* privacy 単調: candidate label >= session label (§16.4) *)
    If[NumericQ[Lookup[candidate, "PrivacyLabel", None]] &&
       NumericQ[sessionLabel] &&
       candidate[["PrivacyLabel"]] < sessionLabel,
      AppendTo[errs, "PrivacyLabel below session label (taint)"]];
    (* provenance *)
    If[TrueQ[Lookup[contract, "RequireProvenance", False]] &&
       !AssociationQ[Lookup[candidate, "Provenance", None]],
      AppendTo[errs, "Provenance required"]];
    (* RequiredChecks が SelfChecks で True *)
    checks = Lookup[contract, "RequiredChecks", {}];
    self = Lookup[candidate, "SelfChecks", <||>];
    If[ListQ[checks],
      Scan[
        Function[c,
          If[Lookup[self, c, False] =!= True,
            AppendTo[errs, "RequiredCheck not satisfied: " <> c]]],
        checks]];
    <|"Valid" -> errs === {}, "Errors" -> errs,
      (* schema/type/staging/privacy 違反は hard、それ以外は repair 可 *)
      "Repairable" ->
        errs =!= {} &&
        !AnyTrue[errs,
          StringContainsQ[#,
            "schema" | "mismatch" | "outside" | "taint"] &]|>
  ];

(* HandleArtifactProposed 用: candidate を lease に格納して ArtifactReview へ *)
iSesArtifactProposedHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], ev = iSesEventOf[binding], l2,
          cand, wid = $ClaudeCurrentWid},
    cand = Lookup[Lookup[ev, "PayloadRefs", <||>],
      "ArtifactCandidate", <||>];
    l2 = Append[iSesApplyEvent[lease, ev, "ArtifactReview"],
      "ArtifactCandidate" -> cand];
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Suspended"]];
    <|"Payload" -> l2|>
  ]];

(* validation verdict (guard から呼ぶ。純関数) *)
iSesArtifactVerdict[lease_Association] :=
  Module[{ss = Lookup[lease, "StartSpec", <||>]},
    ClaudeSessionValidateArtifactCandidate[
      Lookup[lease, "ArtifactCandidate", <||>],
      Lookup[ss, "ArtifactContract", <||>],
      Lookup[Lookup[ss, "Access", <||>], "PrivacyLabel", 0.0]]
  ];

(* pass: CommitReady + CommitPermit *)
iSesArtifactPassHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], wid = $ClaudeCurrentWid},
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Suspended"]];
    (* CommitReady lease と CommitPermit token は同一 payload を共有する
       (permit は EpisodeId で pair される)。 *)
    <|"Payload" -> Append[lease, {
      "ControlState" -> "CommitReady",
      "ArtifactValidation" -> <|"Valid" -> True|>}]|>
  ]];

iSesArtifactRepairHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], v = iSesArtifactVerdict[
            iSesLeaseOf[binding]], wid = $ClaudeCurrentWid},
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Running"]];
    <|"Payload" -> Append[lease, {
      "ControlState" -> "Running",
      "ArtifactCandidate" -> None,
      "LastArtifactRepairFeedback" -> Lookup[v, "Errors", {}]}]|>
  ]];

iSesArtifactRejectHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], v = iSesArtifactVerdict[
            iSesLeaseOf[binding]], wid = $ClaudeCurrentWid},
    If[StringQ[wid],
      iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
        "Closing"]];
    <|"Payload" -> Append[lease, {
      "ControlState" -> "Failed",
      "StatusDetail" -> "ArtifactInvalid",
      "ArtifactErrors" -> Lookup[v, "Errors", {}]}]|>
  ]];

(* commit 実体 (§17.3)。ArtifactStore = content-addressed deposit (冪等)、
   Files = atomic rename + base revision CAS、Notebook = capability gate。
   commit target/artifact 本文は staging から読む。receipt を durable 保存。 *)
iSesArtifactContentPath[wid_, episodeId_] :=
  FileNameJoin[{iSesSpoolRoot[], "commit-receipts",
    ToString[episodeId] <> ".wxf"}];

iSesReadArtifactRefContent[ref_] :=
  Which[
    StringQ[ref] && FileExistsQ[ref],
      Quiet @ Check[Import[ref, "WXF"], $Failed],
    True, ref];   (* inline (小さい public) はそのまま *)

iSesDoCommit[lease_Association, cand_Association, contract_Association] :=
  Module[{mode, target, content, chash, receipt, path, prev},
    mode = Lookup[contract, "CommitMode", "ArtifactStore"];
    target = Lookup[contract, "CommitTargetRef", None];
    chash = Lookup[cand, "ContentHash", None];
    content = iSesReadArtifactRefContent[Lookup[cand, "ArtifactRef", None]];
    Switch[mode,
      "ArtifactStore",
        (* content-addressed: <target>/<ContentHash>.wxf。既存なら冪等 skip *)
        If[!StringQ[target],
          Return[<|"Status" -> "Failed",
            "Reason" -> "NoCommitTargetRef"|>]];
        path = FileNameJoin[{target, ToString[chash] <> ".wxf"}];
        If[!FileExistsQ[path],
          Quiet @ Check[
            iSesAtomicExport[path, content], Return[<|"Status" -> "Failed",
              "Reason" -> "DepositFailed"|>]]];
        receipt = <|"CommitId" -> ClaudeSessionNewId["Command"] <> "-commit",
          "ArtifactId" -> Lookup[cand, "ArtifactId", None],
          "TargetRef" -> path,
          "PreviousRevision" -> None,
          "NewRevision" -> chash,
          "CommittedAt" -> DateObject[],
          "ContentHash" -> chash|>;
        <|"Status" -> "Committed", "Receipt" -> receipt|>,
      "Files",
        (* base revision CAS: 現 target の hash が BaseRevision と一致する
           場合のみ atomic rename。不一致は conflict (上書きしない §17.3) *)
        If[!StringQ[target],
          Return[<|"Status" -> "Failed",
            "Reason" -> "NoCommitTargetRef"|>]];
        prev = If[FileExistsQ[target],
          iRtCanonicalHashSes[
            Quiet @ Check[Import[target, "WXF"], $Failed]], None];
        If[Lookup[contract, "BaseRevision", None] =!= None &&
           prev =!= Lookup[contract, "BaseRevision", None],
          Return[<|"Status" -> "Conflict",
            "Reason" -> "BaseRevisionConflict",
            "Expected" -> Lookup[contract, "BaseRevision", None],
            "Actual" -> prev|>]];
        Quiet @ Check[iSesAtomicExport[target, content],
          Return[<|"Status" -> "Failed", "Reason" -> "WriteFailed"|>]];
        receipt = <|"CommitId" -> ClaudeSessionNewId["Command"] <> "-commit",
          "ArtifactId" -> Lookup[cand, "ArtifactId", None],
          "TargetRef" -> target,
          "PreviousRevision" -> prev,
          "NewRevision" -> chash,
          "CommittedAt" -> DateObject[],
          "ContentHash" -> chash|>;
        <|"Status" -> "Committed", "Receipt" -> receipt|>,
      "Notebook",
        (* headless では NotebookCommit capability が無いと拒否 (§8.2/§17.3) *)
        <|"Status" -> "Failed",
          "Reason" -> "NotebookCommitRequiresCapableCommitter"|>,
      _,
        <|"Status" -> "Failed", "Reason" -> "UnknownCommitMode"|>
    ]
  ];

(* commit target 内 canonical hash (Files CAS 用) *)
iRtCanonicalHashSes[expr_] :=
  If[expr === $Failed, None, iSesEventHashBase[expr]];
iSesEventHashBase[expr_] :=
  IntegerString[
    Hash[BaseEncode[BinarySerialize[iCanon[expr]], "Base64"], "SHA256"],
    16, 64];

iSesCommitArtifactHandler = Function[binding,
  Module[{lease = iSesLeaseOf[binding], cand, ss, contract, res,
          receipt, l2, wid = $ClaudeCurrentWid, rpath},
    cand = Lookup[lease, "ArtifactCandidate", <||>];
    ss = Lookup[lease, "StartSpec", <||>];
    contract = Lookup[ss, "ArtifactContract", <||>];
    res = iSesDoCommit[lease, cand, contract];
    If[Lookup[res, "Status", None] === "Committed",
      receipt = Lookup[res, "Receipt", <||>];
      (* receipt を durable に保存してから terminal へ (§17.3:
         receipt 永続化成功後にのみ Completed) *)
      rpath = iSesArtifactContentPath[wid,
        Lookup[lease, "EpisodeId", None]];
      Quiet @ Check[iSesAtomicExport[rpath, receipt], Null];
      If[StringQ[wid],
        iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
          "Closing"]];
      (* 成功: ControlState=Committed で EpisodeActive に留め、
         FinalizeCommittedArtifact が terminal 化する (失敗時に terminal へ
         落とさないための二段構え §17.3) *)
      l2 = Append[lease, {
        "ControlState" -> "Committed",
        "CommitReceipt" -> receipt,
        "CommitReceiptRef" -> rpath}],
      (* commit 失敗/conflict → repair へ戻す (target は不変) *)
      If[StringQ[wid],
        iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
          "Running"]];
      l2 = Append[lease, {
        "ControlState" -> "Running",
        "ArtifactCandidate" -> None,
        "LastCommitFailure" -> res}]];
    <|"Payload" -> l2|>
  ]];

ClaudeRuntimeSessionArtifactReceipt[wid_String, episodeId_String] :=
  Module[{leaseTok, outTok, payload},
    leaseTok = iSesFindLeaseToken[wid, episodeId];
    outTok = If[MissingQ[leaseTok],
      iSesFindOutcomeToken[wid, episodeId], Missing[]];
    payload = Which[
      !MissingQ[leaseTok], Lookup[leaseTok, "Payload", <||>],
      !MissingQ[outTok], Lookup[outTok, "Payload", <||>],
      True, <||>];
    Lookup[payload, "CommitReceipt", None]
  ];

(* ── transitions ── *)

iSesBuildEpisodeTransitions[] := <|
  "AllocateEpisode" -> WorkflowTransition["AllocateEpisode",
    "InputArcs" -> {
      <|"Place" -> "EpisodeRequested", "TokenKind" -> "Task"|>,
      <|"Place" -> "SessionSlots", "TokenKind" -> "ResourceSlot"|>,
      <|"Place" -> "EnvironmentSlots", "TokenKind" -> "ResourceSlot"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeAllocated", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "RuntimeSpec" -> <|"Handler" -> iSesAllocateHandler|>,
    "Priority" -> 5],

  "StartEpisode" -> WorkflowTransition["StartEpisode",
    "InputArcs" -> {
      <|"Place" -> "EpisodeAllocated", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "EpisodeStartResults", "TokenKind" -> "StartResult"|>},
    "Executor" -> "RuntimeSession",
    "Priority" -> 5],

  "HandleStartFailure" -> WorkflowTransition["HandleStartFailure",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeFailed", "TokenKind" -> "Failure"|>,
      <|"Place" -> "CleanupPending", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Lookup[iSesLeaseOf[b], "ControlState", None] === "StartFailed"],
    "RuntimeSpec" -> <|"Handler" -> iSesStartFailureHandler|>,
    "Priority" -> 8],

  "HandleObservationRequired" -> WorkflowTransition[
    "HandleObservationRequired",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"ObservationRequired"}, {"Running"},
      None],
    "RuntimeSpec" -> <|"Handler" ->
      iSesMakeEventHandler[Function[{l, e}, "AwaitingObservation"]]|>],

  "HandleApprovalRequired" -> WorkflowTransition["HandleApprovalRequired",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"ApprovalRequired"}, {"Running"}, None],
    "RuntimeSpec" -> <|"Handler" ->
      iSesMakeEventHandler[Function[{l, e}, "AwaitingApproval"]]|>],

  "RecordCheckpoint" -> WorkflowTransition["RecordCheckpoint",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"CheckpointCreated"}, All, None],
    "RuntimeSpec" -> <|"Handler" ->
      iSesMakeEventHandler[
        Function[{l, e}, Lookup[l, "ControlState", "Running"]]]|>],

  "HandleBudgetInterrupt" -> WorkflowTransition["HandleBudgetInterrupt",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"BudgetInterrupt"},
      {"Running", "CheckpointReview"}, None],
    "RuntimeSpec" -> <|"Handler" ->
      iSesMakeEventHandler[Function[{l, e}, "BudgetReview"]]|>],

  "HandleArtifactProposed" -> WorkflowTransition["HandleArtifactProposed",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"ArtifactProposed"}, {"Running"}, None],
    "RuntimeSpec" -> <|"Handler" -> iSesArtifactProposedHandler|>],

  (* Inc8: validation → 分岐 (pass/repair/reject)。validation は guard で
     評価 (純関数)。EpisodeActive lease のみを入力とする内部 transition。 *)
  "ValidateArtifact" -> WorkflowTransition["ValidateArtifact",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "CommitPermits", "TokenKind" -> "CommitPermit"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Lookup[iSesLeaseOf[b], "ControlState", None] === "ArtifactReview" &&
      TrueQ[iSesArtifactVerdict[iSesLeaseOf[b]][["Valid"]]]],
    "RuntimeSpec" -> <|"Handler" -> iSesArtifactPassHandler|>,
    "Priority" -> 7],

  "RepairArtifactRequest" -> WorkflowTransition["RepairArtifactRequest",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Module[{v = iSesArtifactVerdict[iSesLeaseOf[b]]},
        Lookup[iSesLeaseOf[b], "ControlState", None] ===
          "ArtifactReview" &&
        !TrueQ[v[["Valid"]]] && TrueQ[v[["Repairable"]]]]],
    "RuntimeSpec" -> <|"Handler" -> iSesArtifactRepairHandler|>,
    "Priority" -> 6],

  "RejectArtifact" -> WorkflowTransition["RejectArtifact",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeFailed", "TokenKind" -> "Failure"|>,
      <|"Place" -> "CleanupPending", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Module[{v = iSesArtifactVerdict[iSesLeaseOf[b]]},
        Lookup[iSesLeaseOf[b], "ControlState", None] ===
          "ArtifactReview" &&
        !TrueQ[v[["Valid"]]] && !TrueQ[v[["Repairable"]]]]],
    "RuntimeSpec" -> <|"Handler" -> iSesArtifactRejectHandler|>,
    "Priority" -> 8],

  (* single committer: CommitPermit token を消費 (一個のみ→一度だけ commit)。
     CommitReady lease と EpisodeId で pair する。commit 結果に関わらず
     出力は EpisodeActive lease のみ (成功=Committed / 失敗=Running)。
     失敗時に terminal へ落とさないため、terminal 化は別 transition。 *)
  "CommitArtifact" -> WorkflowTransition["CommitArtifact",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "CommitPermits", "TokenKind" -> "CommitPermit"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Module[{lease, permit},
        lease = iSesLeaseOf[b];
        permit = Lookup[Lookup[b, "CommitPermits", <||>],
          "Payload", <||>];
        Lookup[lease, "ControlState", None] === "CommitReady" &&
        Lookup[lease, "EpisodeId", "?l"] ===
          Lookup[permit, "EpisodeId", "?p"]]],
    "RuntimeSpec" -> <|"Handler" -> iSesCommitArtifactHandler|>,
    "Priority" -> 9],

  (* commit 成功 (ControlState=Committed) の episode を terminal 化。
     receipt durable 保存後にのみ Completed になる (§17.3)。 *)
  "FinalizeCommittedArtifact" ->
    WorkflowTransition["FinalizeCommittedArtifact",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeCompleted", "TokenKind" -> "Artifact"|>,
      <|"Place" -> "CleanupPending", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Lookup[iSesLeaseOf[b], "ControlState", None] === "Committed" &&
      AssociationQ[Lookup[iSesLeaseOf[b], "CommitReceipt", None]]],
    "RuntimeSpec" -> <|"Handler" ->
      Function[binding,
        Module[{lease = iSesLeaseOf[binding], wid = $ClaudeCurrentWid},
          If[StringQ[wid],
            iSesSetEpisodeState[wid, Lookup[lease, "EpisodeId", None],
              "Closing"]];
          <|"Payload" -> Append[lease, "ControlState" -> "Completed"]|>]]|>,
    "Priority" -> 10],

  "AcknowledgeSessionCommand" -> WorkflowTransition[
    "AcknowledgeSessionCommand",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"CommandAccepted"}, {"CommandPending"},
      Function[{l, e},
        Lookup[Lookup[e, "PayloadRefs", <||>], "CommandId", "?e"] ===
        Lookup[Lookup[l, "PendingCommand", <||>], "CommandId", "?l"]]],
    "RuntimeSpec" -> <|"Handler" -> iSesAckHandler|>],

  "HandleCommandRejected" -> WorkflowTransition["HandleCommandRejected",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"CommandRejected"}, {"CommandPending"},
      Function[{l, e},
        Lookup[e, "Source", None] === "Bridge" &&
        Lookup[Lookup[e, "PayloadRefs", <||>], "CommandId", "?e"] ===
        Lookup[Lookup[l, "PendingCommand", <||>], "CommandId", "?l"]]],
    "RuntimeSpec" -> <|"Handler" -> iSesRejectHandler|>],

  "HandleCompleted" -> WorkflowTransition["HandleCompleted",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeCompleted", "TokenKind" -> "Artifact"|>,
      <|"Place" -> "CleanupPending", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[{"Completed"},
      {"Running", "Closing", "Cancelling"}, None],
    "RuntimeSpec" -> <|"Handler" -> iSesCompletedHandler|>,
    "Priority" -> 9],

  "HandleTerminalEvent" -> WorkflowTransition["HandleTerminalEvent",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "SessionEvents", "TokenKind" -> "SessionEvent"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeFailed", "TokenKind" -> "Failure"|>,
      <|"Place" -> "CleanupPending", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> iSesMakeEventGuard[$iSesTerminalEventTypes, All, None],
    "RuntimeSpec" -> <|"Handler" -> iSesTerminalHandler|>,
    "Priority" -> 10],

  "QueueSessionCommand" -> WorkflowTransition["QueueSessionCommand",
    "InputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>,
      <|"Place" -> "CommandRequests", "TokenKind" -> "CommandRequest"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeActive", "TokenKind" -> "SessionLease"|>},
    "Executor" -> "PureFunction",
    "Guard" -> Function[b,
      Module[{lease, req, reqType, allowed},
        lease = iSesLeaseOf[b];
        req = Lookup[Lookup[b, "CommandRequests", <||>], "Payload", <||>];
        reqType = Lookup[req, "Type", None];
        allowed = Lookup[$iSesCommandAllowedStates, reqType, {}];
        TrueQ[
          Lookup[req, "EpisodeId", "?r"] ===
            Lookup[lease, "EpisodeId", "?l"] &&
          KeyExistsQ[$iSesCommandAllowedStates, reqType] &&
          (allowed === All ||
           MemberQ[allowed, Lookup[lease, "ControlState", None]]) &&
          Lookup[lease, "ControlState", None] =!= "StartFailed" &&
          (Lookup[lease, "PendingCommand", None] === None ||
           reqType === "Cancel")]
      ]],
    "RuntimeSpec" -> <|"Handler" -> iSesQueueCommandHandler|>,
    "Priority" -> 3],

  "CleanupAndRelease" -> WorkflowTransition["CleanupAndRelease",
    "InputArcs" -> {
      <|"Place" -> "CleanupPending", "TokenKind" -> "SessionLease"|>},
    "OutputArcs" -> {
      <|"Place" -> "EpisodeClosed", "TokenKind" -> "EpisodeClosed"|>,
      <|"Place" -> "SessionSlots", "TokenKind" -> "ResourceSlot"|>,
      <|"Place" -> "EnvironmentSlots", "TokenKind" -> "ResourceSlot"|>},
    "Executor" -> "PureFunction",
    "RuntimeSpec" -> <|"Handler" -> iSesCleanupHandler|>,
    "Priority" -> 9]
|>;

(* ── net builder ── *)

Options[ClaudeCreateRuntimeSessionEpisodeNet] = {
  "SessionSlots" -> 1,
  "EnvironmentSlots" -> 1,
  "Validate" -> True};

ClaudeCreateRuntimeSessionEpisodeNet[startSpec_Association,
                                     opts:OptionsPattern[]] :=
  Module[{v, hv, backendName, places, transitions, badGuards, wid, label,
          isoReq, isoActual, isoOK},
    If[TrueQ[OptionValue["Validate"]],
      v = ClaudeSessionValidate["SessionStartSpec", startSpec];
      If[!v[["Valid"]],
        Return[Failure["InvalidStartSpec",
          <|"Errors" -> Take[v[["Errors"]], UpTo[8]]|>]]];
      hv = ClaudeSessionVerifyStartSpecHashes[startSpec];
      If[!hv[["Valid"]],
        Return[Failure["StartSpecHashMismatch",
          <|"Errors" -> hv[["Errors"]]|>]]]];
    backendName = Lookup[startSpec, "Backend", None];
    If[!KeyExistsQ[$iRuntimeSessionBackends, backendName],
      Return[Failure["UnknownSessionBackend",
        <|"Backend" -> backendName,
          "Known" -> Keys[$iRuntimeSessionBackends]|>]]];

    (* Inc7 (§20.3): RequiredIsolation を満たさない environment を弾く。
       CooperativeKernel が hard isolation 必須 task に選ばれないための
       fail-closed gate。SessionProfile.IsolationRequired または
       Task-level RequiredIsolation を、実 Environment.IsolationLevel と
       照合する (NBAccess の順序判定を使う。未ロードなら等値比較)。 *)
    isoReq = Lookup[
      Lookup[startSpec, "SessionProfile", <||>],
      "IsolationRequired",
      Lookup[startSpec, "RequiredIsolation", None]];
    isoActual = Lookup[Lookup[startSpec, "Environment", <||>],
      "IsolationLevel", None];
    If[StringQ[isoReq],
      isoOK = If[Names["NBAccess`NBIsolationSatisfiedQ"] =!= {},
        TrueQ[Quiet @ Check[
          Symbol["NBAccess`NBIsolationSatisfiedQ"][isoReq, isoActual],
          False]],
        isoReq === isoActual];
      If[!isoOK,
        Return[Failure["IsolationRequirementNotMet",
          <|"Required" -> isoReq, "Actual" -> isoActual|>]]]];

    places = <|
      "EpisodeRequested" -> WorkflowPlace["EpisodeRequested",
        "AcceptedKinds" -> {"Task"}],
      "SessionSlots" -> WorkflowPlace["SessionSlots",
        "AcceptedKinds" -> {"ResourceSlot"}],
      "EnvironmentSlots" -> WorkflowPlace["EnvironmentSlots",
        "AcceptedKinds" -> {"ResourceSlot"}],
      "EpisodeAllocated" -> WorkflowPlace["EpisodeAllocated",
        "AcceptedKinds" -> {"SessionLease"}],
      "EpisodeActive" -> WorkflowPlace["EpisodeActive",
        "AcceptedKinds" -> {"SessionLease"}],
      "EpisodeStartResults" -> WorkflowPlace["EpisodeStartResults",
        "AcceptedKinds" -> {"StartResult"}],
      "SessionEvents" -> WorkflowPlace["SessionEvents",
        "AcceptedKinds" -> {"SessionEvent"}],
      "CommandRequests" -> WorkflowPlace["CommandRequests",
        "AcceptedKinds" -> {"CommandRequest"}],
      "CleanupPending" -> WorkflowPlace["CleanupPending",
        "AcceptedKinds" -> {"SessionLease"}],
      "CommitPermits" -> WorkflowPlace["CommitPermits",
        "AcceptedKinds" -> {"CommitPermit"}],
      "EpisodeCompleted" -> WorkflowPlace["EpisodeCompleted",
        "AcceptedKinds" -> {"Artifact"}],
      "EpisodeFailed" -> WorkflowPlace["EpisodeFailed",
        "AcceptedKinds" -> {"Failure"}],
      "EpisodeClosed" -> WorkflowPlace["EpisodeClosed",
        "AcceptedKinds" -> {"EpisodeClosed"}]|>;

    transitions = iSesBuildEpisodeTransitions[];

    (* session net validator (§10.1): SessionEvents を consume する
       transition の Guard 欠落/非 Function は build 時に fail-closed *)
    badGuards = Select[Values[transitions],
      Function[t,
        AnyTrue[Lookup[t, "InputArcs", {}],
          Function[a, Lookup[a, "Place", None] === "SessionEvents"]] &&
        Head[Lookup[t, "Guard", None]] =!= Function]];
    If[badGuards =!= {},
      Return[Failure["SessionNetGuardMissing",
        <|"Transitions" -> Map[Lookup[#, "Name", "?"] &, badGuards]|>]]];

    wid = ClaudeCreateWorkflowNet[<|
      "SourcePlace" -> "EpisodeRequested",
      "FinalPlaces" -> {"EpisodeClosed"},
      "Places" -> places,
      "Transitions" -> transitions,
      "Description" ->
        "RuntimeSession episode supervisor (Inc2, EpisodeId " <>
        ToString[Lookup[startSpec, "EpisodeId", "?"]] <> ")"|>];

    (* Inc3 (§11.1): episode spool dir と meta を先に永続化 *)
    iSesWriteEpisodeMeta[startSpec, wid];

    label = Lookup[Lookup[startSpec, "Access", <||>], "PrivacyLabel", 1.0];
    Do[ClaudeSubmitToken[wid,
        WorkflowToken["Kind" -> "ResourceSlot",
          "Payload" -> <|"Slot" -> i|>], "SessionSlots"],
      {i, OptionValue["SessionSlots"]}];
    Do[ClaudeSubmitToken[wid,
        WorkflowToken["Kind" -> "ResourceSlot",
          "Payload" -> <|"Slot" -> i|>], "EnvironmentSlots"],
      {i, OptionValue["EnvironmentSlots"]}];
    ClaudeSubmitToken[wid,
      WorkflowToken["Kind" -> "Task",
        "Payload" -> <|"StartSpec" -> startSpec|>,
        "PrivacyLabel" -> label],
      "EpisodeRequested"];

    <|"WorkflowId" -> wid,
      "EpisodeId" -> Lookup[startSpec, "EpisodeId", None],
      "SessionId" -> Lookup[startSpec, "SessionId", None],
      "Backend" -> backendName|>
  ];

(* ── driver / view / bridge lite ── *)

ClaudeStartRuntimeSessionEpisode[wid_String, maxSteps_Integer:16] :=
  Module[{n = 0, r = <||>},
    While[n < maxSteps,
      r = ClaudeStepWorkflow[wid];
      If[Lookup[r, "Status", None] =!= "Fired", Break[]];
      n++];
    <|"Steps" -> n, "LastStatus" -> Lookup[r, "Status", None],
      "WorkflowId" -> wid|>
  ];

iSesFindLeaseToken[wid_String, episodeId_String] :=
  Module[{state = ClaudeWorkflowState[wid], tokens, leases},
    tokens = Lookup[state, "Tokens", <||>];
    leases = Select[Values[tokens],
      Lookup[#, "Kind", None] === "SessionLease" &&
      Lookup[Lookup[#, "Payload", <||>], "EpisodeId", None] ===
        episodeId &];
    If[leases === {}, Missing["NoLease"], First[leases]]
  ];

iSesFindOutcomeToken[wid_String, episodeId_String] :=
  Module[{state = ClaudeWorkflowState[wid], tokens, byKind, hit},
    tokens = Lookup[state, "Tokens", <||>];
    byKind = Function[kind,
      Select[Values[tokens],
        Lookup[#, "Kind", None] === kind &&
        Lookup[Lookup[#, "Payload", <||>], "EpisodeId", None] ===
          episodeId &]];
    (* 成果/失敗 record を EpisodeClosed marker より優先して返す *)
    hit = Join[byKind["Artifact"], byKind["Failure"],
      byKind["EpisodeClosed"]];
    If[hit === {}, Missing["NoOutcome"], First[hit]]
  ];

ClaudeRuntimeSessionEpisodeInfo[wid_String, episodeId_String] :=
  Module[{leaseTok, outTok, payload, src},
    leaseTok = iSesFindLeaseToken[wid, episodeId];
    outTok = If[MissingQ[leaseTok],
      iSesFindOutcomeToken[wid, episodeId], Missing[]];
    payload = Which[
      !MissingQ[leaseTok], Lookup[leaseTok, "Payload", <||>],
      !MissingQ[outTok],   Lookup[outTok, "Payload", <||>],
      True, <||>];
    src = Which[
      !MissingQ[leaseTok], "Lease",
      !MissingQ[outTok], "Outcome",
      True, "NotFound"];
    <|"EpisodeId" -> episodeId,
      "SourceToken" -> src,
      "ControlState" -> Lookup[payload, "ControlState", None],
      "LastAppliedEventSeq" ->
        Lookup[payload, "LastAppliedEventSeq", None],
      "PendingCommand" -> Lookup[payload, "PendingCommand", None],
      "HandleRef" -> Lookup[payload, "HandleRef", None],
      "BackendInstanceId" -> Lookup[payload, "BackendInstanceId", None],
      "StatusDetail" -> Lookup[payload, "StatusDetail", None],
      "Registry" ->
        Lookup[$iActiveSessionEpisodes, Key[{wid, episodeId}], None],
      "WorkflowStatus" ->
        Lookup[ClaudeWorkflowState[wid], "Status", None]|>
  ];

ClaudeRuntimeSessionEpisodes[wid_String] :=
  Module[{state = ClaudeWorkflowState[wid], tokens},
    tokens = Lookup[state, "Tokens", <||>];
    DeleteDuplicates @ Flatten @ {
      Map[Lookup[Lookup[#, "Payload", <||>], "EpisodeId", Nothing] &,
        Select[Values[tokens],
          Lookup[#, "Kind", None] === "SessionLease" &]],
      Map[#[[2]] &,
        Select[Keys[$iActiveSessionEpisodes],
          ListQ[#] && Length[#] === 2 && #[[1]] === wid &]]}
  ];

iSesResolveBackendForLease[lease_Association] :=
  Lookup[$iRuntimeSessionBackends, Lookup[lease, "Backend", None],
    Missing["NoBackend"]];

(* Inc3 (§11.2): durable spool 経由の event delivery。
   手順: poll → 検証 → inbox temp→rename → 安定 TokenId → deposit →
   delivery-index 更新。crash 後の再実行は inbox FileExistsQ /
   delivery-index / engine TokenId dedup により冪等 (effectively-once)。
   一度に一個の未適用 event だけを deposit する。 *)
ClaudeRuntimeSessionPumpOnce[wid_String, episodeId_String] :=
  Module[{leaseTok, lease, backend, attDir, idx, res, pollStatus,
          applied, nextSeq, inboxEvs, quarSeqs, synCand, runCand, cand,
          tok, sub, tid},
    leaseTok = iSesFindLeaseToken[wid, episodeId];
    If[MissingQ[leaseTok], Return[<|"Status" -> "NoActiveLease"|>]];
    lease = Lookup[leaseTok, "Payload", <||>];
    backend = iSesResolveBackendForLease[lease];
    If[MissingQ[backend], Return[<|"Status" -> "NoBackend"|>]];
    If[Lookup[lease, "HandleRef", None] === None,
      Return[<|"Status" -> "NotStarted"|>]];
    attDir  = iSesAttemptDirOf[lease];
    idx     = iSesReadDeliveryIndex[attDir];
    applied = Lookup[lease, "LastAppliedEventSeq", 0];
    nextSeq = applied + 1;

    (* 1-4: poll + durable save (取得 cursor は LastFetchedSeq) *)
    res = Quiet @ Check[
      backend[["PollEvents"]][Lookup[lease, "HandleRef", None],
        <|"Attempt" -> Lookup[lease, "Attempt", 1],
          "EventSeq" -> Lookup[idx, "LastFetchedSeq", 0]|>],
      <|"Status" -> "Unavailable"|>];
    pollStatus = If[AssociationQ[res],
      Lookup[res, "Status", "PollFailed"], "PollFailed"];
    If[pollStatus === "OK",
      Module[{newMax = Lookup[idx, "LastFetchedSeq", 0]},
        Scan[
          Function[ev,
            If[Lookup[ev, "Source", "Runtime"] === "Runtime" &&
               IntegerQ[Lookup[ev, "EventSeq", None]],
              newMax = Max[newMax, Lookup[ev, "EventSeq", 0]];
              Module[{p = iSesInboxEventPath[attDir, ev], vv},
                If[!FileExistsQ[p] &&
                   !MemberQ[Map[Lookup[#, "EventSeq", None] &,
                      Lookup[idx, "Quarantined", {}]],
                     Lookup[ev, "EventSeq", None]],
                  vv = ClaudeSessionValidate["SessionControlEvent", ev];
                  Which[
                    !vv[["Valid"]],
                      iSesQuarantine["InvalidEventSchema",
                        <|"Errors" -> Take[vv[["Errors"]], UpTo[6]],
                          "Event" -> ev|>];
                      idx["Quarantined"] = Append[
                        Lookup[idx, "Quarantined", {}],
                        <|"EventSeq" -> Lookup[ev, "EventSeq", None],
                          "EventId" -> Lookup[ev, "EventId", None],
                          "Reason" -> "InvalidEventSchema"|>],
                    !ClaudeSessionVerifyEventHash[ev],
                      iSesQuarantine["EventHashMismatch", ev];
                      idx["Quarantined"] = Append[
                        Lookup[idx, "Quarantined", {}],
                        <|"EventSeq" -> Lookup[ev, "EventSeq", None],
                          "EventId" -> Lookup[ev, "EventId", None],
                          "Reason" -> "EventHashMismatch"|>],
                    True,
                      Quiet @ Check[iSesAtomicExport[p, ev], $Failed]
                  ]
                ]
              ]
            ]],
          Lookup[res, "Events", {}]];
        idx["LastFetchedSeq"] = newMax;
        iSesWriteDeliveryIndex[attDir, idx]]];

    (* 5: deposit 候補を一個選ぶ *)
    inboxEvs = iSesListInboxEvents[attDir];
    quarSeqs = Map[Lookup[#, "EventSeq", None] &,
      Lookup[idx, "Quarantined", {}]];
    synCand = SelectFirst[inboxEvs,
      (Lookup[#, "Source", "Runtime"] =!= "Runtime" &&
       Lookup[#, "SyntheticBaseEventSeq", -1] === applied &&
       !KeyExistsQ[Lookup[idx, "Deposited", <||>],
         ClaudeSessionEventTokenId[#]]) &];
    runCand = SelectFirst[inboxEvs,
      Lookup[#, "EventSeq", None] === nextSeq &];
    cand = Which[
      !MissingQ[synCand], synCand,
      !MissingQ[runCand], runCand,
      True,
        (* terminal preemption (§11.2): 中間が quarantine されていても
           SupersedesThroughSeq 明示の terminal は先行適用できる *)
        SelectFirst[
          SortBy[
            Select[inboxEvs,
              (MemberQ[$iSesTerminalEventTypes,
                 Lookup[#, "Type", None]] &&
               IntegerQ[Lookup[#, "EventSeq", None]] &&
               Lookup[#, "EventSeq", 0] > nextSeq &&
               Lookup[#, "SupersedesThroughSeq", None] ===
                 Lookup[#, "EventSeq", 0] - 1) &],
            Lookup[#, "EventSeq", Infinity] &],
          True &]
    ];

    If[MissingQ[cand],
      Which[
        MemberQ[quarSeqs, nextSeq],
          Return[<|"Status" -> "BlockedByQuarantinedEvent",
                   "EventSeq" -> nextSeq, "PollStatus" -> pollStatus|>],
        Lookup[idx, "LastFetchedSeq", 0] > applied,
          (* §11.2: gap は適用せず再取得 (cursor を applied へ巻き戻す) *)
          idx["LastFetchedSeq"] = applied;
          iSesWriteDeliveryIndex[attDir, idx];
          Return[<|"Status" -> "GapDetected",
                   "ExpectedSeq" -> nextSeq,
                   "PollStatus" -> pollStatus|>],
        pollStatus =!= "OK",
          Return[<|"Status" -> pollStatus|>],
        True,
          Return[<|"Status" -> "NoNewEvents",
                   "PollStatus" -> pollStatus|>]
      ]];

    (* 6-8: deposit + delivery-index 更新 (Superseded 監査含む) *)
    If[Lookup[cand, "Source", "Runtime"] === "Runtime" &&
       Lookup[cand, "EventSeq", 0] > nextSeq,
      idx["Superseded"] = Append[Lookup[idx, "Superseded", {}],
        <|"FromSeq" -> nextSeq,
          "ThroughSeq" -> Lookup[cand, "EventSeq", 0] - 1,
          "ByEventId" -> Lookup[cand, "EventId", None]|>]];
    tid = ClaudeSessionEventTokenId[cand];
    tok = WorkflowToken[
      "TokenId" -> tid,
      "Kind" -> "SessionEvent",
      "Payload" -> cand,
      "PrivacyLabel" -> Lookup[cand, "PrivacyLabel", 1.0]];
    sub = ClaudeSubmitToken[wid, tok, "SessionEvents"];
    idx["Deposited"] = Append[Lookup[idx, "Deposited", <||>],
      tid -> <|"EventSeq" -> Lookup[cand, "EventSeq", None],
               "At" -> AbsoluteTime[]|>];
    iSesWriteDeliveryIndex[attDir, idx];
    <|"Status" ->
        If[Lookup[sub, "Status", None] === "Duplicate",
          "Duplicate", "Deposited"],
      "EventSeq" -> Lookup[cand, "EventSeq", None],
      "Type" -> Lookup[cand, "Type", None],
      "TokenId" -> tid,
      "PollStatus" -> pollStatus|>
  ];

iSesDepositCommandRequest[wid_String, episodeId_String, type_String,
                          payloadRefs_Association] :=
  Module[{tok, sub},
    tok = WorkflowToken["Kind" -> "CommandRequest",
      "Payload" -> <|"EpisodeId" -> episodeId, "Type" -> type,
        "PayloadRefs" -> payloadRefs|>];
    sub = ClaudeSubmitToken[wid, tok, "CommandRequests"];
    <|"Status" -> "Requested", "Type" -> type,
      "TokenId" -> Lookup[sub, "TokenId", None]|>
  ];

ClaudeRuntimeSessionCancel[wid_String, episodeId_String,
                           reason_String:"UserCancel"] :=
  iSesDepositCommandRequest[wid, episodeId, "Cancel",
    <|"Reason" -> reason|>];

ClaudeRuntimeSessionProvideObservation[wid_String, episodeId_String,
                                       observationRef_] :=
  iSesDepositCommandRequest[wid, episodeId, "ProvideObservation",
    <|"ObservationRef" -> observationRef|>];

Options[ClaudeRuntimeSessionInjectSyntheticTerminal] = {
  "Source" -> "OrchestratorWatchdog",   (* または "RecoveryScan" *)
  "RecheckBackend" -> True};

ClaudeRuntimeSessionInjectSyntheticTerminal[wid_String,
    episodeId_String, type_String, evidenceRef_,
    opts:OptionsPattern[]] :=
  Module[{leaseTok, lease, src, ev0, ev, v, tok, sub, backend, probe,
          attDir, idx, applied},
    If[!MemberQ[$iSesTerminalEventTypes, type],
      Return[Failure["InvalidSyntheticType",
        <|"Type" -> type, "Allowed" -> $iSesTerminalEventTypes|>]]];
    If[evidenceRef === None,
      Return[Failure["EvidenceRefRequired", <||>]]];
    src = OptionValue["Source"];
    If[!MemberQ[{"OrchestratorWatchdog", "RecoveryScan"}, src],
      Return[Failure["InvalidSyntheticSource", <|"Source" -> src|>]]];
    leaseTok = iSesFindLeaseToken[wid, episodeId];
    If[MissingQ[leaseTok],
      Return[Failure["NoActiveLease", <|"EpisodeId" -> episodeId|>]]];
    lease = Lookup[leaseTok, "Payload", <||>];
    applied = Lookup[lease, "LastAppliedEventSeq", 0];

    (* §11.2.1: 合成前に genuine Runtime event の有無を再確認。
       生きている Runtime の新 event が見えたら合成を中止する。 *)
    If[TrueQ[OptionValue["RecheckBackend"]],
      backend = iSesResolveBackendForLease[lease];
      If[!MissingQ[backend] &&
         Lookup[lease, "HandleRef", None] =!= None,
        probe = Quiet @ Check[
          backend[["PollEvents"]][Lookup[lease, "HandleRef", None],
            <|"Attempt" -> Lookup[lease, "Attempt", 1],
              "EventSeq" -> applied|>],
          <|"Status" -> "Unavailable"|>];
        If[AssociationQ[probe] &&
           Lookup[probe, "Status", None] === "OK" &&
           Lookup[probe, "Events", {}] =!= {},
          Return[<|"Status" -> "AbortedGenuineEventPresent",
                   "PendingEvents" ->
                     Length[Lookup[probe, "Events", {}]]|>]]]];

    ev0 = <|
      "SchemaVersion" -> 1,
      "EventId" -> ClaudeSessionNewId["Event"],
      "EventSeq" -> None,
      "SessionId" -> Lookup[lease, "SessionId", "ses-unknown"],
      "EpisodeId" -> episodeId,
      "Attempt" -> Lookup[lease, "Attempt", 1],
      "BackendInstanceId" ->
        Replace[Lookup[lease, "BackendInstanceId", None],
          Except[_String] -> "backend-unknown"],
      "Source" -> src,
      "Type" -> type,
      "SyntheticBaseEventSeq" -> applied,
      "EvidenceRef" -> evidenceRef,
      "SupersedesThroughSeq" -> None,
      "PayloadRefs" -> <||>,
      "BudgetSnapshot" -> Lookup[lease, "LastBudgetSnapshot", <||>],
      "AccessSpecHash" ->
        Replace[Lookup[lease, "AccessSpecHash", None],
          Except[_String] -> ""],
      "PolicySnapshotHash" ->
        Replace[Lookup[lease, "PolicySnapshotHash", None],
          Except[_String] -> ""],
      "PrivacyLabel" -> 1.0,
      "CreatedAt" -> DateObject[]|>;
    ev = Append[ev0, "EventHash" -> ClaudeSessionEventHash[ev0]];
    v = ClaudeSessionValidate["SessionControlEvent", ev];
    If[!v[["Valid"]],
      Return[Failure["InvalidSyntheticEvent",
        <|"Errors" -> v[["Errors"]]|>]]];

    (* durable 化: inbox に syn file を残し、delivery-index に記録 *)
    attDir = iSesAttemptDirOf[lease];
    Quiet @ Check[
      iSesAtomicExport[iSesInboxEventPath[attDir, ev], ev], $Failed];

    tok = WorkflowToken[
      "TokenId" -> ClaudeSessionEventTokenId[ev],
      "Kind" -> "SessionEvent",
      "Payload" -> ev,
      "PrivacyLabel" -> 1.0];
    sub = ClaudeSubmitToken[wid, tok, "SessionEvents"];
    idx = iSesReadDeliveryIndex[attDir];
    idx["Deposited"] = Append[Lookup[idx, "Deposited", <||>],
      ClaudeSessionEventTokenId[ev] ->
        <|"EventSeq" -> None, "Synthetic" -> True,
          "At" -> AbsoluteTime[]|>];
    iSesWriteDeliveryIndex[attDir, idx];
    <|"Status" ->
        If[Lookup[sub, "Status", None] === "Duplicate",
          "Duplicate", "Deposited"],
      "Type" -> type, "Source" -> src,
      "TokenId" -> Lookup[sub, "TokenId", None]|>
  ];

(* ::Subsection:: *)
(* Inc3: durable event bridge / command outbox (§11) *)

(* ── spool paths / atomic I/O ── *)

iSesSpoolRoot[] :=
  If[StringQ[$ClaudeSessionSpoolRoot] && $ClaudeSessionSpoolRoot =!= "",
    $ClaudeSessionSpoolRoot,
    FileNameJoin[{$UserBaseDirectory, "ClaudeOrchestrator",
      "session-spool"}]];

iSesEnsureDir[dir_String] := (
  If[!DirectoryQ[dir],
    Quiet @ CreateDirectory[dir, CreateIntermediateDirectories -> True]];
  dir);

iSesEpisodeDir[sid_, epi_] :=
  FileNameJoin[{iSesSpoolRoot[], ToString[sid], ToString[epi]}];

iSesAttemptDir[sid_, epi_, att_] :=
  FileNameJoin[{iSesEpisodeDir[sid, epi], "attempts", ToString[att]}];

iSesAttemptDirOf[lease_Association] :=
  iSesAttemptDir[Lookup[lease, "SessionId", "ses-unknown"],
    Lookup[lease, "EpisodeId", "epi-unknown"],
    Lookup[lease, "Attempt", 1]];

(* temp → atomic rename (externalrunner の status write と同型) *)
iSesAtomicExport[path_String, expr_] :=
  Module[{tmp},
    iSesEnsureDir[DirectoryName[path]];
    tmp = path <> ".tmp-" <> ToString[$ProcessID] <> "-" <>
      ToString[RandomInteger[999999]];
    Export[tmp, expr, "WXF"];
    If[FileExistsQ[path], Quiet @ DeleteFile[path]];
    RenameFile[tmp, path];
    path
  ];

iSesWXFImport[path_String] :=
  If[FileExistsQ[path],
    Quiet @ Check[Import[path, "WXF"], $Failed],
    $Failed];

iSesWriteEpisodeMeta[startSpec_Association, wid_String] :=
  Quiet @ Check[
    Module[{dir, meta, tmp, path},
      dir = iSesEnsureDir[iSesEpisodeDir[
        Lookup[startSpec, "SessionId", "ses-unknown"],
        Lookup[startSpec, "EpisodeId", "epi-unknown"]]];
      meta = <|
        "SchemaVersion" -> 1, "WorkflowId" -> wid,
        "SessionId" -> Lookup[startSpec, "SessionId", None],
        "EpisodeId" -> Lookup[startSpec, "EpisodeId", None],
        "Attempt" -> Lookup[startSpec, "Attempt", 1],
        "Backend" -> Lookup[startSpec, "Backend", None],
        "CreatedAt" -> DateString[TimeZoneConvert[Now, 0],
          "ISODateTime"]|>;
      path = FileNameJoin[{dir, "episode-meta.json"}];
      tmp = path <> ".tmp-" <> ToString[$ProcessID];
      Export[tmp, meta, "JSON"];
      If[FileExistsQ[path], Quiet @ DeleteFile[path]];
      RenameFile[tmp, path];
      path],
    $Failed];

(* ── delivery-index / command-index (attempt-local dedup 正本 §10.3) ── *)

iSesDeliveryIndexPath[attDir_] :=
  FileNameJoin[{attDir, "delivery-index.wxf"}];

iSesReadDeliveryIndex[attDir_] :=
  Module[{r = iSesWXFImport[iSesDeliveryIndexPath[attDir]]},
    If[AssociationQ[r], r,
      <|"SchemaVersion" -> 1, "LastFetchedSeq" -> 0,
        "Deposited" -> <||>, "Superseded" -> {},
        "Quarantined" -> {}|>]];

iSesWriteDeliveryIndex[attDir_, idx_Association] :=
  Quiet @ Check[iSesAtomicExport[iSesDeliveryIndexPath[attDir], idx],
    $Failed];

iSesCommandIndexPath[attDir_] :=
  FileNameJoin[{attDir, "command-index.wxf"}];

iSesReadCommandIndex[attDir_] :=
  Module[{r = iSesWXFImport[iSesCommandIndexPath[attDir]]},
    If[AssociationQ[r], r, <||>]];

iSesWriteCommandIndex[attDir_, idx_Association] :=
  Quiet @ Check[iSesAtomicExport[iSesCommandIndexPath[attDir], idx],
    $Failed];

(* ── inbox / outbox ── *)

iSesInboxEventPath[attDir_, ev_Association] :=
  If[Lookup[ev, "Source", "Runtime"] === "Runtime",
    FileNameJoin[{attDir, "inbox",
      IntegerString[Lookup[ev, "EventSeq", 0], 10, 6] <> "-" <>
        ToString[Lookup[ev, "EventId", "noid"]] <> ".wxf"}],
    FileNameJoin[{attDir, "inbox",
      "syn-" <> ToString[Lookup[ev, "EventId", "noid"]] <> ".wxf"}]];

iSesListInboxEvents[attDir_] :=
  Select[
    Map[iSesWXFImport,
      Sort @ FileNames["*.wxf", FileNameJoin[{attDir, "inbox"}]]],
    AssociationQ];

iSesOutboxPut[lease_Association, cmd_Association] :=
  Module[{attDir = iSesAttemptDirOf[lease], cid, cIdx},
    cid = Lookup[cmd, "CommandId", "cmd-unknown"];
    iSesAtomicExport[
      FileNameJoin[{attDir, "outbox", cid <> ".wxf"}], cmd];
    cIdx = iSesReadCommandIndex[attDir];
    If[!KeyExistsQ[cIdx, cid],
      cIdx[cid] = <|"Status" -> "Queued",
        "Type" -> Lookup[cmd, "Type", None],
        "QueuedAt" -> AbsoluteTime[]|>;
      iSesWriteCommandIndex[attDir, cIdx]];
    cid
  ];

(* Rejected → Bridge CommandRejected synthetic event へ正規化 (§11.2.1) *)
iSesWriteCommandRejectedEvent[lease_Association, attDir_, cid_,
                              reason_] :=
  Module[{ev0, ev},
    ev0 = <|
      "SchemaVersion" -> 1,
      "EventId" -> ClaudeSessionNewId["Event"],
      "EventSeq" -> None,
      "SessionId" -> Lookup[lease, "SessionId", "ses-unknown"],
      "EpisodeId" -> Lookup[lease, "EpisodeId", "epi-unknown"],
      "Attempt" -> Lookup[lease, "Attempt", 1],
      "BackendInstanceId" ->
        Replace[Lookup[lease, "BackendInstanceId", None],
          Except[_String] -> "backend-unknown"],
      "Source" -> "Bridge",
      "Type" -> "CommandRejected",
      "SyntheticBaseEventSeq" ->
        Lookup[lease, "LastAppliedEventSeq", 0],
      "EvidenceRef" -> "spool://command-index/" <> ToString[cid],
      "SupersedesThroughSeq" -> None,
      "PayloadRefs" -> <|"CommandId" -> cid, "Reason" -> reason,
        "ObservedRuntimeEventSeq" ->
          Lookup[lease, "LastAppliedEventSeq", 0]|>,
      "BudgetSnapshot" -> Lookup[lease, "LastBudgetSnapshot", <||>],
      "AccessSpecHash" ->
        Replace[Lookup[lease, "AccessSpecHash", None],
          Except[_String] -> ""],
      "PolicySnapshotHash" ->
        Replace[Lookup[lease, "PolicySnapshotHash", None],
          Except[_String] -> ""],
      "PrivacyLabel" -> 1.0,
      "CreatedAt" -> DateObject[]|>;
    ev = Append[ev0, "EventHash" -> ClaudeSessionEventHash[ev0]];
    Quiet @ Check[
      iSesAtomicExport[iSesInboxEventPath[attDir, ev], ev], $Failed];
    ev
  ];

(* ── outbox dispatch (§11.3 手順 1-3) ── *)

ClaudeRuntimeSessionDispatchOutbox[wid_String, episodeId_String] :=
  Module[{leaseTok, lease, backend, attDir, cIdx, pending,
          accepted = 0, rejected = 0, unavailable = 0},
    leaseTok = iSesFindLeaseToken[wid, episodeId];
    If[MissingQ[leaseTok], Return[<|"Status" -> "NoActiveLease"|>]];
    lease = Lookup[leaseTok, "Payload", <||>];
    backend = iSesResolveBackendForLease[lease];
    If[MissingQ[backend], Return[<|"Status" -> "NoBackend"|>]];
    attDir = iSesAttemptDirOf[lease];
    cIdx = iSesReadCommandIndex[attDir];
    pending = Select[Keys[cIdx],
      MemberQ[{"Queued", "Sent"},
        Lookup[Lookup[cIdx, #, <||>], "Status", None]] &];
    Scan[
      Function[cid,
        Module[{cmd, res},
          cmd = iSesWXFImport[
            FileNameJoin[{attDir, "outbox", cid <> ".wxf"}]];
          If[!AssociationQ[cmd],
            cIdx[cid] = Append[Lookup[cIdx, cid, <||>],
              {"Status" -> "Failed", "Reason" -> "OutboxFileMissing"}],
            res = Quiet @ Check[
              backend[["SendCommand"]][
                Lookup[lease, "HandleRef", None], cmd],
              <|"Status" -> "Unavailable",
                "Reason" -> "SendCommandException"|>];
            If[!AssociationQ[res],
              res = <|"Status" -> "Unavailable",
                "Reason" -> "InvalidSendResult"|>];
            Switch[Lookup[res, "Status", None],
              "Accepted" | "AlreadyAccepted",
                accepted++;
                cIdx[cid] = Append[Lookup[cIdx, cid, <||>],
                  {"Status" -> "Accepted",
                   "AckStatus" -> Lookup[res, "Status", None],
                   "SentAt" -> AbsoluteTime[]}],
              "Rejected",
                rejected++;
                cIdx[cid] = Append[Lookup[cIdx, cid, <||>],
                  {"Status" -> "Rejected",
                   "Reason" -> Lookup[res, "Reason", None],
                   "SentAt" -> AbsoluteTime[]}];
                iSesWriteCommandRejectedEvent[lease, attDir, cid,
                  Lookup[res, "Reason", None]],
              _,
                unavailable++;
                cIdx[cid] = Append[Lookup[cIdx, cid, <||>],
                  {"Status" -> "Queued",
                   "LastError" -> Lookup[res, "Status", "Unavailable"]}]
            ]
          ]
        ]],
      pending];
    iSesWriteCommandIndex[attDir, cIdx];
    <|"Status" -> "OK", "Pending" -> Length[pending],
      "Accepted" -> accepted, "Rejected" -> rejected,
      "Unavailable" -> unavailable|>
  ];

(* ── poll tick (§11.5) ── *)

If[!ValueQ[$iSessionTickBusy], $iSessionTickBusy = False];
If[!IntegerQ[$iSessionTickRotor], $iSessionTickRotor = 0];

ClaudeRuntimeSessionPollTick[] :=
  Module[{t0, processed = 0, deferred = 0, result},
    If[TrueQ[$iSessionTickBusy],
      Return[<|"Status" -> "SkippedBusy"|>]];
    $iSessionTickBusy = True;
    result = Quiet @ Check[
      Module[{keys},
        t0 = AbsoluteTime[];
        (* 200ms soft budget で defer した episode が次 tick も先頭の
           episode に食われて starve しないよう、開始位置を rotate する *)
        keys = Keys[$iActiveSessionEpisodes];
        If[keys =!= {},
          keys = RotateLeft[keys,
            Mod[$iSessionTickRotor, Length[keys]]]];
        Scan[
          Function[k,
            If[AbsoluteTime[] - t0 > 0.2,
              deferred++,
              Module[{wid = k[[1]], epi = k[[2]]},
                Quiet @ ClaudeRuntimeSessionDispatchOutbox[wid, epi];
                Quiet @ ClaudeRuntimeSessionPumpOnce[wid, epi];
                processed++]]],
          keys];
        $iSessionTickRotor = $iSessionTickRotor + Max[processed, 1];
        <|"Status" -> "OK", "Processed" -> processed,
          "Deferred" -> deferred,
          "ElapsedSec" -> AbsoluteTime[] - t0|>],
      <|"Status" -> "TickError"|>];
    $iSessionTickBusy = False;
    result
  ];

ClaudeRuntimeSessionEnablePolling[] :=
  If[Names["ClaudeCode`ClaudeRegisterPollingTick"] === {},
    <|"Status" -> "ClaudeCodeUnavailable"|>,
    Quiet @ Check[
      (Symbol["ClaudeCode`ClaudeRegisterPollingTick"][
         "SessionEpisodeBridge", ClaudeRuntimeSessionPollTick];
       <|"Status" -> "Registered"|>),
      <|"Status" -> "RegistrationFailed"|>]];

(* ── recovery scan (§15.2 / Inc3) ── *)

ClaudeRecoverRuntimeSessions[] :=
  Module[{results = {}},
    Scan[
      Function[k,
        Module[{wid = k[[1]], epi = k[[2]], leaseTok, lease, backend,
                rec, inj},
          leaseTok = iSesFindLeaseToken[wid, epi];
          If[MissingQ[leaseTok],
            AppendTo[results, <|"WorkflowId" -> wid, "EpisodeId" -> epi,
              "Status" -> "NoLease"|>],
            lease = Lookup[leaseTok, "Payload", <||>];
            backend = iSesResolveBackendForLease[lease];
            rec = If[MissingQ[backend],
              <|"Status" -> "Failed", "Reason" -> "NoBackend"|>,
              Quiet @ Check[
                backend[["Recover"]][<|
                  "HandleRef" -> Lookup[lease, "HandleRef", None],
                  "EpisodeId" -> epi,
                  "Attempt" -> Lookup[lease, "Attempt", 1]|>],
                <|"Status" -> "Failed",
                  "Reason" -> "RecoverException"|>]];
            Switch[Lookup[rec, "Status", None],
              "Reattached" | "ResumedFromCheckpoint",
                (* Inc6b: 再接続できた episode は Recovering → Running *)
                iSesSetEpisodeState[wid, epi, "Running"];
                AppendTo[results, <|"WorkflowId" -> wid,
                  "EpisodeId" -> epi,
                  "Status" -> Lookup[rec, "Status", None]|>],
              "LostUnrecoverable" | "Failed",
                inj = ClaudeRuntimeSessionInjectSyntheticTerminal[
                  wid, epi, "EnvironmentLost",
                  "recover://" <> ToString[Lookup[rec, "Status", "?"]],
                  "Source" -> "RecoveryScan"];
                AppendTo[results, <|"WorkflowId" -> wid,
                  "EpisodeId" -> epi,
                  "Status" -> "SyntheticInjected",
                  "Inject" ->
                    If[AssociationQ[inj],
                      Lookup[inj, "Status", None], inj]|>],
              _,
                AppendTo[results, <|"WorkflowId" -> wid,
                  "EpisodeId" -> epi,
                  "Status" -> Lookup[rec, "Status", "Unknown"]|>]
            ]
          ]
        ]],
      Keys[$iActiveSessionEpisodes]];
    results
  ];

(* ── spool 検査 view ── *)

ClaudeSessionEpisodeSpoolInfo[sid_String, epi_String,
                              att_Integer:1] :=
  Module[{attDir = iSesAttemptDir[sid, epi, att]},
    <|"AttemptDir" -> attDir,
      "DeliveryIndex" -> iSesReadDeliveryIndex[attDir],
      "CommandIndex" -> iSesReadCommandIndex[attDir],
      "InboxFiles" -> Map[FileNameTake,
        Sort @ FileNames["*.wxf", FileNameJoin[{attDir, "inbox"}]]],
      "OutboxFiles" -> Map[FileNameTake,
        Sort @ FileNames["*.wxf", FileNameJoin[{attDir, "outbox"}]]]|>
  ];

(* ::Subsection:: *)
(* Inc0: trust 分離 gate + CallContext ledger (conductor Inc0A/0B primitive) *)

(* provider label → InferenceTrustDomain 分類。
   SourceVault_promptrouter の iClassifyProviderTrustDomain と同じ語彙
   (canonical はあちら。ここは backend binding 用の自己完結 mirror)。
   lmstudio は remote endpoint も指せるため label だけでは分類しない。 *)
iSesClassifyProviderLabel[label_String] :=
  Module[{lc = ToLowerCase[StringTrim[label]]},
    Which[
      MemberQ[{"chatgptcodex", "codex", "chatgptcodexcli",
               "chatgpt codex cli", "chatgpt-codex", "chatgpt codex",
               "cloudllm", "cloud llm", "claudecodecli",
               "claude code cli", "claudecode", "anthropic",
               "openai"}, lc], "Cloud",
      MemberQ[{"privatellm", "private llm", "private"}, lc], "Private",
      MemberQ[{"localonly", "local only", "local",
               "localonlyllm"}, lc], "Local",
      True, Missing["UnclassifiedTrustDomain"]]];

ClaudeSessionResolveTrustDomain[raw_Association] :=
  Module[{itd, td, cls, label},
    (* ExecutionLocation は意図的に見ない (conductor v0.2 §13.2) *)
    itd = Lookup[raw, "InferenceTrustDomain", Missing["NotProvided"]];
    If[StringQ[itd], Return[itd]];
    td = Lookup[raw, "TrustDomain", Missing["NotProvided"]];
    If[StringQ[td], Return[td]];
    cls = Lookup[raw, "Class", Missing["NoClass"]];
    If[StringQ[cls],
      Which[
        StringContainsQ[cls, "Local"], Return["Local"],
        StringContainsQ[cls, "Cloud"], Return["Cloud"]]];
    label = SelectFirst[
      {Lookup[raw, "Provider", Null], Lookup[raw, "ProviderLabel", Null],
       Lookup[raw, "Route", Null], Lookup[raw, "Model", Null]},
      StringQ, Null];
    If[StringQ[label],
      iSesClassifyProviderLabel[label],
      Missing["Unknown"]]
  ];

ClaudeSessionResolveTrustDomain[_] := Missing["Unknown"];

(* cloud 境界は conductor/NBAccess と同一の 0.5 (§16.4) *)
$iSesCloudPrivacyBoundary = 0.5;

ClaudeSessionTrustGateQ[privacyLabel_, domain_] :=
  Which[
    !NumericQ[privacyLabel], False,               (* fail-closed *)
    privacyLabel < $iSesCloudPrivacyBoundary, True,
    MemberQ[{"Local", "Private"}, domain], True,
    True, False                                   (* Cloud/不明は遮断 *)
  ];

(* ── CallContext (§19.3) + request-scoped 帰属 ledger ── *)

$iSesCallContextOptionalKeys = {
  "RunId", "WorkflowId", "TaskId", "SessionId", "EpisodeId",
  "Attempt", "TurnIndex", "ToolCallId", "ReservationId"};

ClaudeSessionMakeCallContext[fields_Association] :=
  Module[{errs = {}, ctx},
    If[!iStrQ[Lookup[fields, "Provider", None]],
      AppendTo[errs, "Provider (String) is required"]];
    If[!iStrQ[Lookup[fields, "Model", None]],
      AppendTo[errs, "Model (String) is required"]];
    If[errs =!= {},
      Return[Failure["InvalidCallContext", <|"Errors" -> errs|>]]];
    ctx = <|
      "CallId" -> "call-" <>
        ToLowerCase[StringDelete[CreateUUID[], "-"]],
      "Provider" -> fields[["Provider"]],
      "Model" -> fields[["Model"]],
      "IssuedAt" -> AbsoluteTime[]|>;
    Scan[
      Function[k,
        ctx = Append[ctx, k -> Lookup[fields, k, None]]],
      $iSesCallContextOptionalKeys];
    ctx
  ];

If[!AssociationQ[$iSessionCallLog], $iSessionCallLog = <||>];

ClaudeSessionCallLogReset[] := ($iSessionCallLog = <||>;
  <|"Status" -> "Reset"|>);

ClaudeSessionLedgerRecord[ctx_Association, usage_Association] :=
  Module[{cid = Lookup[ctx, "CallId", None], existed},
    If[!iStrQ[cid],
      Return[Failure["MissingCallId", <||>]]];
    existed = KeyExistsQ[$iSessionCallLog, cid];
    AssociateTo[$iSessionCallLog, cid -> <|
      "CallContext" -> ctx,
      "Usage" -> usage,
      "LoggedAt" -> AbsoluteTime[]|>];
    <|"Status" -> If[existed, "Updated", "Recorded"],
      "CallId" -> cid|>
  ];

ClaudeSessionCallLog[] :=
  SortBy[Values[$iSessionCallLog], Lookup[#, "LoggedAt", 0] &];

ClaudeSessionCallAggregate[keyField_String, keyValue_] :=
  Module[{entries, usages, numCost},
    entries = Select[Values[$iSessionCallLog],
      Lookup[Lookup[#, "CallContext", <||>], keyField, None] ===
        keyValue &];
    usages = Map[Lookup[#, "Usage", <||>] &, entries];
    numCost = Select[Map[Lookup[#, "CostUSD", None] &, usages],
      NumericQ];
    <|"Calls" -> Length[entries],
      "InTokens" -> Total[Select[
        Map[Lookup[#, "InTokens", 0] &, usages], NumericQ]],
      "OutTokens" -> Total[Select[
        Map[Lookup[#, "OutTokens", 0] &, usages], NumericQ]],
      "CacheReadTokens" -> Total[Select[
        Map[Lookup[#, "CacheReadTokens", 0] &, usages], NumericQ]],
      "CostUSD" -> Total[numCost],
      (* unknown cost は 0 扱いせず別掲 (§25.3 fail-open 防止) *)
      "UnknownCostCalls" -> Count[usages,
        u_ /; !NumericQ[Lookup[u, "CostUSD", None]]]|>
  ];

(* ::Subsection:: *)
(* Inc6b: workflow snapshot attachment + restore (§10.4/§15.2) *)

(* SessionAttachmentManifest: 本文なし (Function/ProcessObject/raw PID を
   含まない ref のみ I12/I4)。正本は lease token、これは導出 record *)
iSesBuildAttachmentManifest[wid_String] :=
  Module[{keys, eps},
    keys = Select[Keys[$iActiveSessionEpisodes],
      ListQ[#] && Length[#] === 2 && #[[1]] === wid &];
    eps = Map[
      Function[k,
        Module[{epi = k[[2]], leaseTok, lease, reg, ss},
          leaseTok = iSesFindLeaseToken[wid, epi];
          lease = If[MissingQ[leaseTok], <||>,
            Lookup[leaseTok, "Payload", <||>]];
          reg = Lookup[$iActiveSessionEpisodes, Key[k], <||>];
          ss = Lookup[lease, "StartSpec", <||>];
          <|"SessionId" -> Lookup[lease, "SessionId",
              Lookup[reg, "SessionId", None]],
            "EpisodeId" -> epi,
            "Attempt" -> Lookup[lease, "Attempt",
              Lookup[reg, "Attempt", 1]],
            "Backend" -> Lookup[lease, "Backend",
              Lookup[reg, "Backend", None]],
            "HandleRef" -> Lookup[lease, "HandleRef",
              Lookup[reg, "HandleRef", None]],
            "LastAppliedEventSeq" ->
              Lookup[lease, "LastAppliedEventSeq", 0],
            "LatestCheckpointRef" ->
              Lookup[lease, "LatestCheckpointRef", None],
            "PendingCommandIds" ->
              If[AssociationQ[Lookup[lease, "PendingCommand", None]],
                {Lookup[Lookup[lease, "PendingCommand", <||>],
                   "CommandId", "?"]}, {}],
            "EnvironmentLeaseId" ->
              Lookup[Lookup[ss, "Environment", <||>],
                "EnvironmentLeaseId", None],
            "ResourceLeaseIds" -> {},
            "BudgetLedgerRef" -> None,
            "SessionSpoolRef" -> iSesEpisodeDir[
              Lookup[lease, "SessionId", "ses-unknown"], epi]|>
        ]],
      keys];
    <|"SessionAttachmentManifest" ->
        <|"WorkflowId" -> wid, "Episodes" -> eps|>|>
  ];

(* restore: manifest から ActiveSessionEpisodes を Recovering で再登録。
   その後の reattach/resume/terminal 分岐は ClaudeRecoverRuntimeSessions
   (§15.2 手順 4-8) が行う *)
iSesRestoreAttachments[newWid_String, aux_Association] :=
  Module[{man, eps, n = 0},
    man = Lookup[aux, "SessionAttachmentManifest", <||>];
    If[!AssociationQ[man], Return[0]];
    eps = Lookup[man, "Episodes", {}];
    Scan[
      Function[ep,
        Module[{epi = Lookup[ep, "EpisodeId", None]},
          If[StringQ[epi],
            AssociateTo[$iActiveSessionEpisodes,
              {newWid, epi} -> <|
                "SessionId" -> Lookup[ep, "SessionId", None],
                "Attempt" -> Lookup[ep, "Attempt", 1],
                "Backend" -> Lookup[ep, "Backend", None],
                "HandleRef" -> Lookup[ep, "HandleRef", None],
                "State" -> "Recovering"|>];
            n++]]],
      eps];
    n
  ];

(* ── engine seam への注入 (§10.1 / §10.5 / §10.4 / §15.2) ── *)

ClaudeOrchestrator`Workflow`$ClaudeRuntimeSessionExecutor =
  Function[{trans, binding},
    iSesExecuteRuntimeSessionBranch[trans, binding]];

ClaudeOrchestrator`Workflow`$ClaudeWorkflowExternalPendingQ =
  Function[wid, iSesAnyActiveEpisodeQ[wid]];

ClaudeOrchestrator`Workflow`$ClaudeWorkflowSnapshotAuxFn =
  Function[wid, iSesBuildAttachmentManifest[wid]];

ClaudeOrchestrator`Workflow`$ClaudeWorkflowRestoreAuxFn =
  Function[{wid, aux}, iSesRestoreAttachments[wid, aux]];

End[];  (* `Private` *)

EndPackage[];

Print[Style["ClaudeOrchestrator_session.wl (Inc1+Inc2) がロードされました。",
  Bold]];
Print["
  -- Inc1 --
  ClaudeSessionValidate[schema, obj]           → §7 schema validator (fail-closed)
  ClaudeSessionValidateEventBatch[evs, cursor] → event 連番/hash 検査
  ClaudeSessionCanonicalHash / AccessSpecHash / EventHash / CommandHash / GrantHash
  ClaudeSessionVerifyEventHash / VerifyCommandHash / VerifyStartSpecHashes
  ClaudeSessionNewId[kind] / ClaudeSessionEventTokenId[event]
  ClaudeRegisterRuntimeSessionBackend / Backends[] / BackendInfo
  ClaudeMockRuntimeSessionBackendSpec[opts] / ClaudeMockRuntimeSessionReset[]
  ClaudeSessionStartSpecTemplate[opts]         → 検証済み StartSpec 雛形
  -- Inc2 --
  ClaudeCreateRuntimeSessionEpisodeNet[spec]   → episode supervisor net (§9)
  ClaudeStartRuntimeSessionEpisode[wid]        → Allocate → StartEpisode
  ClaudeRuntimeSessionPumpOnce[wid, epi]       → event を一個 deposit (§11.2)
  ClaudeRuntimeSessionCancel / ProvideObservation
  ClaudeRuntimeSessionInjectSyntheticTerminal  → watchdog 合成 terminal
  ClaudeRuntimeSessionEpisodeInfo / Episodes / ActiveEpisodes / Quarantine
"];
