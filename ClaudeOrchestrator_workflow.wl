(* ::Package:: *)

(* ::Title:: *)
(* ClaudeOrchestrator_workflow.wl *)

(* ::Subsection:: *)
(* 概要 *)

(* ════════════════════════════════════════════════════════════════════
   ClaudeOrchestrator_workflow.wl

   ClaudeOrchestrator`Workflow` 名前空間。
   真の multi-token Petri net (MTP) workflow engine。

   位置付け:
     - ClaudeOrchestrator.wl と並立する別ファイル
       (Orchestrator 本体は 9000+ 行のため独立ファイルに分離)
     - ClaudeOrchestrator が phase API (DSL) で本書 engine を呼び出す
     - ClaudeStateGraph` 名前空間 (ClaudeOrchestrator_stategraph.wl,
       2026-05-06 にリネーム; 旧名 ClaudeRuntime_stategraph.wl) は
       Stage B 後に本 engine の forwarding shim になる

   依存:
     - ClaudeCode`     : LLMGraphDAGCreate, $iSharedPollingTask
     - NBAccess`       : NBDirectiveDerivedPolicy (hard policy check)
     - ClaudeRuntime`  : 将来的に ClaudeRuntimeExecuteTransition (Stage C)

   設計確定文書:
     Workflow_Migration_StageB_Design_Notes.md

   段階移行:
     Stage A (完了):  本ファイル不在、stategraph.wl が独立稼働
     Stage B (本書):  WorkflowNet engine 新設、stategraph.wl は shim 化
     Stage C       :  stategraph.wl deprecated、PM API 切り替え

   バージョン: 2026-05-05 (Stage B Week 2c-2c)
              v0.8: completion hook 機構を追加。
                    workflow 完了時 (Sync 戻り値直前 / Async tick の
                    iMarkAsyncCompleted) に登録された hook を一回限り発火。
                    Public API:
                      ClaudeRegisterCompletionHook[wid, fn]
                      ClaudeUnregisterCompletionHooks[wid]
                    fn は <|"WorkflowId","Status","TerminationReason",
                          "Mode" -> "Sync"|"Async","ElapsedSec","Steps",
                          "FinalMarking","EndTime"|> を受け取る。
                    用途: Workflow Migration shim 経由の RunStateGraph
                    (OnGraphComplete callback) 互換、および将来の
                    event-driven な後段処理。
              v0.7: iExecuteTransition の "ClaudeRuntime" branch を本実装、
                    ClaudeRuntime`ClaudeRuntimeExecuteTransition[adapter,
                    contextPacket] を呼び出す。iBuildContextPacket helper で
                    AccessPolicy / RuntimeSpec / binding から context packet を
                    組み立て、DirectiveBundle / DirectivePrompt / Role /
                    AllowedCapabilities を伝播。PackageManager branch は
                    引き続き stub (Stage B Week 2 で本実装)。
              v0.6: ClaudeSnapshotWorkflow / ClaudeRestoreWorkflow /
                    ClaudeListWorkflowSnapshots (FormatVersion 2 専用、
                    v1 -> v2 自動変換は Stage B Week 2 で実装)、
                    ClaudeCleanupAsyncJob 公開 (手動 GC API)、
                    ClaudeCode`ClaudeRegisterPollingTick / 
                    ClaudeUnregisterPollingTick Public API への移行
                    (Private context $claudeProgress 直接アクセスを廃止)。
              v0.5: ClaudeRunWorkflow に "Async" -> True 実装、
                    ClaudeCode`iEnsureSharedPollingTask に寄生 (新規
                    ScheduledTask は作らない)、$iWorkflowAsyncJobs registry、
                    ClaudeWaitWorkflow / ClaudeAsyncJobInfo 公開、
                    Pause/Cancel が async runtime に対しても効くこと。
              v0.4: ClaudeWorkflowState / ClaudeWorkflowTrace 公開、
                    Pause / Resume / Cancel、Multiplicity > 1 サポート。
                    iFlattenBinding helper を導入し binding の List/単一を統一。
              v0.3 hotfix: ReplacePart Association 新規キー追加問題 (Append 使用)
              v0.2: Day 2 (Fire / Run)
              v0.1: Day 1 (skeleton)
                    PackageManager executor 本実装、shim、v1 snapshot 自動変換は
                    Stage B Week 2 以降。
   ════════════════════════════════════════════════════════════════════ *)

BeginPackage["ClaudeOrchestrator`Workflow`", {"ClaudeCode`"}];

(* ::Subsection:: *)
(* 公開 API usage *)

$WorkflowVersion::usage =
  "$WorkflowVersion はパッケージのバージョン文字列を返す。";

(* ── 型ビルダー ── *)

WorkflowToken::usage =
  "WorkflowToken[opts] は immutable な token Association を生成する。\n" <>
  "オプション: \"TokenId\" (Automatic), \"Kind\" (\"Task\"|\"Worker\"|\"Artifact\"|\n" <>
  "\"Approval\"|\"PackageTransaction\"|\"XSMSentinel\"), \"Payload\" (Association),\n" <>
  "\"PrivacyLabel\" (Real, 既定 0.0), \"ParentIds\" (List), \"CreatedBy\" (String).";

WorkflowPlace::usage =
  "WorkflowPlace[name, opts] は place Association を生成する。\n" <>
  "オプション: \"Capacity\" (Infinity), \"Visibility\" (\"Internal\"|\n" <>
  "\"UserVisible\"), \"AcceptedKinds\" (All | List), \"Description\" (String).";

WorkflowTransition::usage =
  "WorkflowTransition[name, opts] は transition Association を生成する。\n" <>
  "オプション: \"InputArcs\" (List of <|\"Place\"->...,\"Multiplicity\"->1,\n" <>
  "\"TokenKind\"->...|>), \"OutputArcs\" (同形式), \"Guard\" (Function|None),\n" <>
  "\"Executor\" (\"ClaudeRuntime\"|\"PackageManager\"|\"PureFunction\"|\"External\"),\n" <>
  "\"RuntimeSpec\" (Association), \"RetryPolicy\" (Association),\n" <>
  "\"AccessPolicy\" (Association), \"Timeout\" (Quantity|None), \"Priority\" (Integer).";

WorkflowNet::usage =
  "WorkflowNet[opts] は WorkflowNet 全体 Association を生成する。\n" <>
  "オプション: \"WorkflowId\" (Automatic), \"SourcePlace\" (String, 必須),\n" <>
  "\"FinalPlaces\" (List, 既定 {\"Done\"}), \"Places\" (Association),\n" <>
  "\"Transitions\" (Association), \"InitialMarking\" (Association),\n" <>
  "\"Description\" (String), \"ParentRuntime\" (String|Missing[]).";

(* ── 公開 API ── *)

ClaudeCreateWorkflowNet::usage =
  "ClaudeCreateWorkflowNet[spec_Association, opts:OptionsPattern[]] は\n" <>
  "WorkflowNet spec を validate し、WorkflowId を発行、内部 registry に\n" <>
  "登録した上で WorkflowId を返す。実行はまだ開始しない。\n" <>
  "Submit と Run は別ステップ。\n\n" <>
  "Options:\n" <>
  "  \"ValidateStrict\" -> True   (validation エラーを Throw)\n" <>
  "  \"Description\"    -> \"\"\n" <>
  "  \"ParentRuntime\"  -> Missing[]";

ClaudeSubmitToken::usage =
  "ClaudeSubmitToken[wid_String, token_Association, place_:Automatic] は\n" <>
  "token を WorkflowNet の指定 place に投入する (デフォルトは SourcePlace)。\n" <>
  "Token は immutable に保たれ、後続 transition で consume + produce される。\n" <>
  "place を明示すると multi-source workflow の各 place を直接 seed できる。";

ClaudeSubmitInputs::usage =
  "ClaudeSubmitInputs[wid_String, payload_Association, place_:Automatic] は\n" <>
  "payload を Kind=\"Task\" の Token として SourcePlace (または指定 place) に\n" <>
  "投入する糖衣。petri-multi-provider-generation skill の規約に従い、最初の\n" <>
  "worker が読む入力 (慣習的に <|\"Text\" -> ...|>) を 1 行で投入できる。\n\n" <>
  "ClaudeSubmitInputs[wid, <|\"Text\" -> text|>] は\n" <>
  "  ClaudeSubmitToken[wid,\n" <>
  "    WorkflowToken[\"Kind\" -> \"Task\", \"Payload\" -> <|\"Text\" -> text|>]]\n" <>
  "に等価。";

ClaudeBindAndSubmit::usage =
  "ClaudeBindAndSubmit[wid_String, vars__Symbol] or\n" <>
  "ClaudeBindAndSubmit[wid_String, varsList_List]\n\n" <>
  "Mathematica \:306e Global \:30b7\:30f3\:30dc\:30eb\:7fa4\:306e\:540d\:524d\:3068\:73fe\:5728\:5024\:304b\:3089 Payload\n" <>
  "Association \:3092\:69cb\:7bc9\:3057\:3001SourcePlace \:306e Token \:3068\:3057\:3066\:6295\:5165\:3059\:308b\:3002\n" <>
  "HoldRest \:5c5e\:6027\:3092\:6301\:3064\:3002\n\n" <>
  "Payload \:30ad\:30fc\:306f SymbolName \:3092\:305d\:306e\:307e\:307e\:7528\:3044\:308b\:3002Mathematica \:306f case-sensitive\:3001\n" <>
  "\:307e\:305f\:6f22\:5b57\:30fbUnicode \:306e\:5909\:6570\:540d\:3082\:8a31\:5bb9\:3055\:308c\:308b\:305f\:3081\:3001\:4f59\:8a08\:306a\:5909\:63db (case \:5909\:66f4\:7b49)\n" <>
  "\:306f\:884c\:308f\:306a\:3044\:3002\n\n" <>
  "## \:53ef\:5909\:9577\:5f62\:5f0f\n\n" <>
  "  text = \"...\";\n" <>
  "  ClaudeBindAndSubmit[wid, text]\n" <>
  "  -> Payload <|\"text\" -> text\:306e\:5024|>\n\n" <>
  "  title = \"...\"; text = \"...\";\n" <>
  "  ClaudeBindAndSubmit[wid, title, text]\n" <>
  "  -> Payload <|\"title\" -> title\:306e\:5024, \"text\" -> text\:306e\:5024|>\n\n" <>
  "  \:672c\:6587 = \"...\";\n" <>
  "  ClaudeBindAndSubmit[wid, \:672c\:6587]\n" <>
  "  -> Payload <|\"\:672c\:6587\" -> \:672c\:6587\:306e\:5024|>\n\n" <>
  "## List \:5f62\:5f0f (\:30d7\:30ed\:30b0\:30e9\:30de\:30d6\:30eb\:306b\:5909\:6570\:30ea\:30b9\:30c8\:3092\:69cb\:7bc9\:3057\:3066\:6e21\:3059\:5834\:5408\:7b49)\n\n" <>
  "  ClaudeBindAndSubmit[wid, {title, text}]\n" <>
  "  -> Payload <|\"title\" -> ..., \"text\" -> ...|>\n\n" <>
  "List \:5f62\:5f0f\:3082 HoldRest \:306e\:6069\:6075\:3067\:3001\:30ea\:30b9\:30c8\:5185\:306e\:5404 Symbol \:306f\:672a\:8a55\:4fa1\:306e\n" <>
  "\:307e\:307e\:6e21\:308b\:306e\:3067 SymbolName \:304c\:6b63\:3057\:304f\:53d6\:308c\:308b\:3002\n\n" <>
  "LLM \:751f\:6210\:306e worker handler \:306f\:540c\:540d\:306e\:30ad\:30fc\:3067 Lookup \:3059\:308c\:3070\:3088\:3044:\n" <>
  "  text = Lookup[binding[[\"Source\", \"Payload\"]], \"text\", \"\"]\n\n" <>
  "Association \:3092\:76f4\:63a5\:6e21\:3057\:305f\:3044\:3068\:304d\:306f ClaudeSubmitInputs[wid, payload] \:3092\:4f7f\:3046\:3002";

ClaudeApplyProposal::usage =
  "ClaudeApplyProposal[] / ClaudeApplyProposal[proposal_Association] は\n" <>
  "proposePetriNet が返す proposal Association の \"Code\" 文字列を ToExpression\n" <>
  "\:3067\:8a55\:4fa1\:3057\:3001\"BuilderName\" \:304c\:6307\:3059 net builder \:95a2\:6570 (\:4f8b: buildDualReviewNet) \:3092\n" <>
  "\:30bb\:30c3\:30b7\:30e7\:30f3\:306b\:5b9a\:7fa9\:3059\:308b\:3002\n\n" <>
  "**\:91cd\:8981**: proposal Association \:3092\:8fd4\:3059\:306e\:306f proposePetriNet[goal]\:3002\n" <>
  "reviewPetriProposal[goal] \:306f Column \:3092\:8fd4\:3059\:8868\:793a\:7528\:95a2\:6570\:3067\:3001Association \:306f\:8fd4\:3055\:306a\:3044\n" <>
  "\:305f\:3081 ClaudeApplyProposal \:306e\:5f15\:6570\:306b\:306f\:4f7f\:3048\:306a\:3044\:3002\n\n" <>
  "\:4f7f\:3044\:65b9:\n" <>
  "  proposal = proposePetriNet[goal];\n" <>
  "  builder  = ClaudeApplyProposal[proposal];\n" <>
  "  wid      = ClaudeCreateWorkflowNet[builder[]];\n" <>
  "  ClaudeBindAndSubmit[wid, text];\n" <>
  "  ClaudeRunWorkflow[wid, \"Async\" -> False]\n\n" <>
  "\:5f15\:6570\:306a\:3057\:7248 ClaudeApplyProposal[] \:306f Global`proposal \:3092\:53c2\:7167\:3059\:308b\n" <>
  "(\:4e0a\:8a18\:306e\:3088\:3046\:306b proposal = proposePetriNet[goal] \:3068\:4ee3\:5165\:3057\:305f\:5834\:5408\:306b\:6709\:52b9)\:3002\n\n" <>
  "\:8fd4\:308a\:5024: BuilderName \:304c\:6307\:3059 Symbol (\:4f8b: Global`buildDualReviewNet)\n" <>
  "       BuilderName \:672a\:6307\:5b9a\:306a\:3089 Null\:3001\:30a8\:30e9\:30fc\:6642\:306f $Failed\:3002";

ClaudeWorkflowStatus::usage =
  "ClaudeWorkflowStatus[wid_String] は WorkflowNet の現在の状態を\n" <>
  "Association で返す: <|\"Status\", \"CurrentMarking\", \"ElapsedSec\"|>.";

ClaudeWorkflowList::usage =
  "ClaudeWorkflowList[] は登録済みの全 WorkflowNet の wid と Status を\n" <>
  "Dataset で返す。";

ClaudeEnabledTransitions::usage =
  "ClaudeEnabledTransitions[wid_String] は現在 fire 可能な transition と\n" <>
  "binding の組合わせを Priority 降順で返す。\n" <>
  "戻り値: {<|\"Name\" -> ..., \"Binding\" -> <|place -> token|>,\n" <>
  "         \"Priority\" -> n|>, ...}";

ClaudeFireTransition::usage =
  "ClaudeFireTransition[wid, transitionName, binding, opts] は\n" <>
  "1 transition を 1 binding で fire する。\n" <>
  "NBAccess hard policy check -> guard -> capability の順で検証し、\n" <>
  "通れば input tokens を consume + output tokens を produce する。\n\n" <>
  "Options:\n" <>
  "  \"ForceAllow\" -> False  (テスト用、NBAccess check をバイパス)\n\n" <>
  "戻り値: <|\"Status\" -> \"Fired\"|\"Blocked\"|\"NeedsApproval\",\n" <>
  "         \"ConsumedTokens\" -> {tids}, \"ProducedTokens\" -> {tids},\n" <>
  "         \"ExecutorResult\" -> ..., \"Marking\" -> <|...|>|>";

ClaudeStepWorkflow::usage =
  "ClaudeStepWorkflow[wid, opts] は enabled transition から Priority 最優先の\n" <>
  "1 つを選んで fire する。Stuck (enabled なし) なら Status -> \"Stuck\" を返す。";

ClaudeRunWorkflow::usage =
  "ClaudeRunWorkflow[wid, opts] は sink 到達か enabled が空になるか\n" <>
  "MaxSteps 到達まで Step を反復する。\n\n" <>
  "Options:\n" <>
  "  \"Async\"    -> False    (True なら ClaudeCode`$iSharedPollingTask に\n" <>
  "                           寄生して非同期実行、即座に WorkflowId を返す)\n" <>
  "  \"MaxSteps\" -> 1000\n" <>
  "  \"MaxWait\"  -> Quantity[600, \"Seconds\"]\n" <>
  "  \"ForceAllow\" -> False\n\n" <>
  "Sync 戻り値: <|\"Status\", \"TerminationReason\", \"Steps\", \"ElapsedSec\",\n" <>
  "              \"FinalMarking\", \"StepLog\"|>\n" <>
  "Async 戻り値: <|\"WorkflowId\", \"Status\" -> \"Async-Started\",\n" <>
  "               \"PollKey\", \"StartTime\"|> (進捗は ClaudeAsyncJobInfo で確認)";

ClaudeWorkflowState::usage =
  "ClaudeWorkflowState[wid_String] は WorkflowNet 全体の現在の状態を返す。\n" <>
  "test や inspector から token の payload まで参照できる。\n" <>
  "戻り値: <|\"Tokens\" -> <|tid -> tokenAssoc, ...|>,\n" <>
  "         \"Marking\" -> <|placeName -> {tids}, ...|>,\n" <>
  "         \"Status\", \"WorkflowId\"|>";

ClaudeWorkflowTrace::usage =
  "ClaudeWorkflowTrace[wid_String] は workflow の実行 trace event リストを返す。\n" <>
  "戻り値: {<|\"Event\", \"Timestamp\", ...|>, ...}";

ClaudePauseWorkflow::usage =
  "ClaudePauseWorkflow[wid_String] は workflow の Status を \"Paused\" にする。\n" <>
  "Pause 中は ClaudeStepWorkflow / ClaudeRunWorkflow が \"Skipped\" を返す。";

ClaudeResumeWorkflow::usage =
  "ClaudeResumeWorkflow[wid_String] は \"Paused\" 状態を \"Running\" に戻す。\n" <>
  "Pause 中でないときは何もせず現在 Status を返す。";

ClaudeCancelWorkflow::usage =
  "ClaudeCancelWorkflow[wid_String] は workflow の Status を \"Cancelled\" にする。\n" <>
  "Cancel 後は再開できない (Resume は Paused のみ受け付ける)。\n" <>
  "Async 実行中の workflow に対しても効き、polling task entry もクリーンアップする。";

ClaudeWaitWorkflow::usage =
  "ClaudeWaitWorkflow[wid_String, opts] は async 起動した workflow が\n" <>
  "完了するまで block する (現スレッドで Pause しつつ進捗を polling)。\n" <>
  "完了の定義: Status \\[Element] {Done, Cancelled, Stuck, Failed,\n" <>
  "NeedsApproval, Blocked, MaxStepsReached, Timeout}。Paused はそのまま待つ\n" <>
  "(Resume されるか Cancel されるまで)。\n\n" <>
  "Options:\n" <>
  "  \"PollInterval\" -> Quantity[0.5, \"Seconds\"]\n" <>
  "  \"MaxWait\"      -> Quantity[600, \"Seconds\"]\n\n" <>
  "戻り値: <|\"WorkflowId\", \"Status\" -> \"Completed\"|\"WaitTimeout\",\n" <>
  "         \"AsyncJob\" -> ..., \"WorkflowStatus\" -> ..., \"FinalMarking\" -> ...|>";

ClaudeAsyncJobInfo::usage =
  "ClaudeAsyncJobInfo[wid_String] は async 実行中 / 完了直後の workflow の\n" <>
  "進捗情報 Association を返す。entry が無い場合は\n" <>
  "<|\"Status\" -> \"NotFound\", \"WorkflowId\" -> wid|> を返す。\n\n" <>
  "戻り値の主なキー:\n" <>
  "  Status (\"Running\"|\"Completed\"), TerminationReason,\n" <>
  "  StartTime, EndTime, Steps, MaxSteps, MaxWaitSec, StepLog, LastStepResult";

ClaudeCleanupAsyncJob::usage =
  "ClaudeCleanupAsyncJob[wid_String] は async job entry を $iWorkflowAsyncJobs\n" <>
  "registry から削除し、polling tick への登録も解除する手動 GC API。\n" <>
  "Completed entry を残し続けたくないときに明示的に呼ぶ。\n\n" <>
  "戻り値: <|\"Status\" -> \"Cleaned\"|\"NotFound\", \"WorkflowId\" -> wid|>";

(* === Z\:6848 (\:975e\:540c\:671f callback handler): Awaiting LLM \:6a5f\:69cb (2026-05-16) === *)

ClaudeCompleteHandlerOutput::usage =
  "ClaudeCompleteHandlerOutput[wid_String, awaitId_String, output_] \:306f\n" <>
  "AwaitingLLM \:72b6\:614b\:306b\:3042\:308b transition \:306e output token \:3092\:78ba\:5b9a\:7684\:306b produce \:3059\:308b\:3002\n" <>
  "\:975e\:540c\:671f LLM \:547c\:51fa\:3057\:306e callback \:304b\:3089\:547c\:3076\:3053\:3068\:3092\:60f3\:5b9a\:3057\:3066\:3044\:308b\:3002\n\n" <>
  "output \:306f Association \:3067\:3001\:6b21\:306e\:3044\:305a\:308c\:304b\:306e\:5f62\:5f0f\:3092\:8a31\:5bb9:\n" <>
  "  <|\"Payload\" -> <|...|>|>          (\:63a8\:5968)\n" <>
  "  <|... payload \:30ad\:30fc\:2026|>          (\"Payload\" \:30e9\:30c3\:30d1\:306a\:3057)\n\n" <>
  "\:8a72\:5f53 awaitId \:304c\:898b\:3064\:304b\:3089\:306a\:3044\:5834\:5408 (Cancel \:5f8c\:306e callback \:8fdf\:5ef6\:5230\:7740\:7b49) \:306f\n" <>
  "\:30b5\:30a4\:30ec\:30f3\:30c8\:306b $Failed \:304c\:8fd4\:3055\:308c\:308b (\:30e1\:30c3\:30bb\:30fc\:30b8\:306f\:51fa\:305d\:306a\:3044)\:3002\:4ed6\:306e Place \:3078\:306e\n" <>
  "\:4f1d\:64ad\:306f\:6b21\:306e polling tick \:304c\:62fe\:3046\:3002\n\n" <>
  "C (2026-05-17): timeout 機構との関係 \:2014 \n" <>
  "  transition.RuntimeSpec.AwaitingLLMTimeout または\n" <>
  "  wf.DefaultAwaitingLLMTimeout が指定されている場合、Awaiting branch 突入時に\n" <>
  "  engine が SessionSubmit[ScheduledTask[...]] で timeout タイマーを仕込む。\n" <>
  "  timeout 経過時にまだ AwaitingLLMTransitions[awaitId] が存在するなら、\n" <>
  "  自動的に ClaudeCompleteHandlerOutput が呼ばれ、output Payload に\n" <>
  "  '_timeout' -> True, '_handler' -> transitionName が追加される。\n" <>
  "  本関数は二重発火に対し silent discard (TransitionCallbackDiscarded を\n" <>
  "  Trace に残す) する設計のため、timeout 発火後に遅れた LLM 応答が到着しても\n" <>
  "  安全 (逆方向も同様)。\n\n" <>
  "\:623b\:308a\:5024: <|\"Status\" -> \"Completed\"|\"Discarded\"|\"NotFound\",\n" <>
  "         \"WorkflowId\", \"AwaitId\", \"TransitionName\",\n" <>
  "         \"ProducedTokens\", \"Marking\"|>";

ClaudeAwaitingTransitions::usage =
  "ClaudeAwaitingTransitions[wid_String] \:306f\:73fe\:5728 AwaitingLLM \:72b6\:614b\:306b\:3042\:308b\n" <>
  "transition \:306e\:4e00\:89a7\:3092 Dataset \:3067\:8fd4\:3059\:3002\:5404\:30a8\:30f3\:30c8\:30ea\:306f\n" <>
  "<|\"AwaitId\", \"TransitionName\", \"StartTime\", \"ElapsedSec\",\n" <>
  "  \"ConsumedIds\"|> \:3092\:542b\:3080\:3002";

$ClaudeCurrentWid::usage =
  "$ClaudeCurrentWid \:306f Awaiting handler \:5185\:3067\:53c2\:7167\:3067\:304d\:308b\:73fe\:5728\:306e WorkflowId\:3002\n" <>
  "iExecutePureFunction \:304c handler \:8a55\:4fa1\:4e2d\:306e\:307f Block \:3067\:52d5\:7684\:675f\:7e1b\:3059\:308b\:3002\n" <>
  "handler \:5916\:3067\:306f Missing[\"NotInHandler\"] \:3092\:8fd4\:3059\:3002";

$ClaudeCurrentTransition::usage =
  "$ClaudeCurrentTransition \:306f Awaiting handler \:5185\:3067\:53c2\:7167\:3067\:304d\:308b\:73fe\:5728\:306e\n" <>
  "transition \:540d\:3002handler \:5916\:3067\:306f Missing[\"NotInHandler\"] \:3092\:8fd4\:3059\:3002";

$ClaudeCurrentAwaitId::usage =
  "$ClaudeCurrentAwaitId \:306f Awaiting handler \:5185\:3067\:53c2\:7167\:3067\:304d\:308b\:73fe\:5728\:306e await ID\:3002\n" <>
  "ClaudeCompleteHandlerOutput \:306b\:6e21\:3059\:305f\:3081\:306b\:4f7f\:3046\:3002\n" <>
  "handler \:5916\:3067\:306f Missing[\"NotInHandler\"] \:3092\:8fd4\:3059\:3002";

$ClaudeCurrentBinding::usage =
  "$ClaudeCurrentBinding \:306f Awaiting handler \:5185\:3067\:53c2\:7167\:3067\:304d\:308b\:73fe\:5728\:306e\n" <>
  "binding Association\:3002closure \:304c\:52b9\:304b\:306a\:3044\:72b6\:6cc1\:3067\:306e fallback \:53c2\:7167\:7528\:3002";

(* === Completion hooks (Day 4d / Week 2c-2c) === *)

ClaudeRegisterCompletionHook::usage =
  "ClaudeRegisterCompletionHook[wid_String, fn_] は workflow が完了した時点\n" <>
  "(Sync の場合は ClaudeRunWorkflow の戻り値直前、Async の場合は\n" <>
  "iMarkAsyncCompleted 経由) で発火される hook 関数を登録する。\n" <>
  "fn は完了情報 Association を 1 引数として受け取る。\n\n" <>
  "発火時に渡される Association:\n" <>
  "  <|\"WorkflowId\", \"Status\", \"TerminationReason\",\n" <>
  "    \"Mode\" -> \"Sync\"|\"Async\", \"ElapsedSec\", \"Steps\",\n" <>
  "    \"FinalMarking\", \"EndTime\"|>\n\n" <>
  "セマンティクス:\n" <>
  "  - hook は一回限り発火 (発火と同時に当該 wid の hooks 全消去)\n" <>
  "  - 例外は Quiet @ Check で捕捉、他の hook の発火を阻害しない\n" <>
  "  - 同じ wid に複数登録可能、登録順に発火\n" <>
  "  - workflow が既に完了済みの場合は登録時に即発火する\n\n" <>
  "戻り値: <|\"WorkflowId\", \"HookCount\", \"FiredImmediately\"|>";

ClaudeUnregisterCompletionHooks::usage =
  "ClaudeUnregisterCompletionHooks[wid_String] は wid に対する全 completion\n" <>
  "hook を削除する。\n\n" <>
  "戻り値: <|\"WorkflowId\", \"Removed\" -> count|>";

(* === Snapshot / Restore (Day 4b) === *)

$ClaudeWorkflowSnapshotDir::usage =
  "$ClaudeWorkflowSnapshotDir は ClaudeSnapshotWorkflow が書き出す既定の\n" <>
  "snapshot 親ディレクトリ。LLMGraphDAG 用の $ClaudeSnapshots とは別。\n" <>
  "デフォルト: $ClaudeWorkingDirectory/workflow_snapshots";

ClaudeSnapshotWorkflow::usage =
  "ClaudeSnapshotWorkflow[wid_String, opts:OptionsPattern[]] は WorkflowNet\n" <>
  "を FormatVersion 2 でディレクトリに保存する。\n" <>
  "保存内容: meta.wl + workflow.wl + llmgraph.wl (Day 4b では空) +\n" <>
  "         aux.wl (Day 4b では空)。\n" <>
  "$iWorkflowAsyncJobs entry は snapshot に含めない (restore 後 async は\n" <>
  "再度 ClaudeRunWorkflow で起動する設計)。\n\n" <>
  "Options:\n" <>
  "  \"SnapshotDir\" -> Automatic (= $ClaudeWorkflowSnapshotDir)\n" <>
  "  \"Description\" -> \"\"\n\n" <>
  "戻り値: <|\"WorkflowId\", \"SnapshotDir\", \"FormatVersion\" -> 2,\n" <>
  "         \"SavedAt\"|>";

ClaudeRestoreWorkflow::usage =
  "ClaudeRestoreWorkflow[snapDir_String, opts:OptionsPattern[]] は\n" <>
  "ClaudeSnapshotWorkflow で保存された workflow を復元する。\n" <>
  "Day 4b では FormatVersion 2 のみ対応 (v1 -> v2 自動変換は Stage B Week 2)。\n\n" <>
  "Options:\n" <>
  "  \"AsNewWorkflowId\" -> True  (新しい wid を発行、元 wid は OriginalWid に保持)\n\n" <>
  "D (2026-05-17): 復元時の AwaitingLLM エントリ取り扱い \[Dash]\n" <>
  "  snapshot 時に AwaitingLLM 状態だった transition は\n" <>
  "  AwaitingLLMTransitions[awaitId] として復元されるが、\n" <>
  "  元の callback (Function closure) と SessionSubmit タスクは\n" <>
  "  カーネル再起動を跨いで復元できない。\n" <>
  "  Restore は各エントリに engine 側 timer を再仕掛けし、\n" <>
  "  timeout 経過時に自動的に ClaudeCompleteHandlerOutput を発火する。\n" <>
  "  fallback Payload には _timeout=True, _handler=tname に加えて\n" <>
  "  _restored=True を付与し、後段 transition や completion hook が\n" <>
  "  この起源を識別できるようにする。\n" <>
  "  Timeout 解決順: trans.RuntimeSpec.AwaitingLLMTimeout >\n" <>
  "                  wf.DefaultAwaitingLLMTimeout >\n" <>
  "                  $iRestoreFallbackTimeout (デフォルト 0.1 秒)\n\n" <>
  "戻り値: <|\"WorkflowId\", \"OriginalWid\", \"Restored\" -> True,\n" <>
  "         \"FormatVersion\", \"SnapshotDir\"|>";

ClaudeListWorkflowSnapshots::usage =
  "ClaudeListWorkflowSnapshots[opts:OptionsPattern[]] は\n" <>
  "$ClaudeWorkflowSnapshotDir 配下の snapshot を Dataset で返す。\n" <>
  "各エントリ: <|\"SnapshotDir\", \"WorkflowId\", \"FormatVersion\",\n" <>
  "             \"Description\", \"SavedAt\"|>。\n\n" <>
  "Options:\n" <>
  "  \"SnapshotDir\" -> Automatic";

(* TODO Day 4c 以降で実装する API (公開予約) *)
(*
ClaudeRuntime`ClaudeRuntimeExecuteTransition (新規 adapter API、ClaudeRuntime.wl 側)
*)

(* === External executor (WolframScript) connection: Phase 3 === *)

ClaudeExternalJobPollTick::usage =
  "ClaudeExternalJobPollTick[] は AwaitingLLMTransitions に登録された External WolframScript job を走査し、status を読んで完了/失敗/timeout を処理する。\nCompleted -> ClaudeCompleteHandlerOutput で output ref token を produce (slot も OutputArc 経由で返却)。\nFailed/Expired -> RetryPolicy に従い同一 JobDir で再起動 (slot 保持) または terminal failure。\nRunning -> no-op。timeout は poller が単独所有する (External では AwaitingLLMTimeout を使わない: v7 C1)。\n返り値: <|\"Polled\"->_Integer, \"Results\"->{...}|>。";

$ClaudeExternalJobLauncher::usage =
  "$ClaudeExternalJobLauncher は External job を起動する関数フック。引数 jobSpec (Association) を受け取り <|\"Status\"->\"Launched\"|\"Failed\", \"JobID\", \"JobDir\", \"PID\", \"Reason\"|> を返す。既定 (Automatic) は未設定 Failure であり、Phase 4 runner が実装する。テストで差し替え可能。";

$ClaudeExternalJobStatusReader::usage =
  "$ClaudeExternalJobStatusReader は External job の status を読む関数フック。引数 awaitMeta を受け取り <|\"Status\"->\"Running\"|\"Completed\"|\"Failed\", \"OutputRef\", \"SourceVaultRef\", \"SummaryRef\", \"ErrorRef\"|> を返す。既定 (Automatic) は JobDir/status.json を読む (無ければ Running)。テストで差し替え可能。";

$ClaudeExternalJobKiller::usage =
  "$ClaudeExternalJobKiller は External job を強制終了する関数フック。引数 awaitMeta を受け取り pid.json 同一性確認後に kill する。既定 (Automatic) は best-effort no-op (Phase 4 で実装)。";

$ClaudeExternalCompletionHook::usage =
  "$ClaudeExternalCompletionHook は External job 完了後に呼ばれる注入点 (既定 None)。引数 <|\"WorkflowId\",\"AwaitId\",\"AwaitMeta\",\"Status\"|>。live 統合で Notebook 反映 (final action -> FinalActionQueue) を行うため externalrunner 側が設定する。workflow 本体は疎結合のまま。";

$ClaudeExternalBackends::usage =
  "$ClaudeExternalBackends は External job backend 別の launcher/status reader/killer registry (<|backend -> <|\"Launcher\",\"StatusReader\",\"Killer\"|>|>)。空 (未登録) のとき External executor は既存 WolframScript singleton hook ($ClaudeExternalJobLauncher 等) と完全に同一挙動になる (純加法)。ComfyUI など非 WolframScript backend を共存させるために使う。";

ClaudeRegisterExternalBackend::usage =
  "ClaudeRegisterExternalBackend[name_String, spec_Association] は External executor へ backend を登録する。spec は <|\"Launcher\"->fn[jobSpec], \"StatusReader\"->fn[awaitMeta], \"Killer\"->fn[awaitMeta]|> の一部または全部。jobSpec/awaitMeta の \"Backend\" がこの name に一致する job だけがこの backend に dispatch され、未登録 backend は既存 WolframScript フックへフォールバックする。返り <|\"Status\"->\"Registered\", \"Backend\"->name, \"Roles\"->{...}|>。";

ClaudeExternalBackends::usage =
  "ClaudeExternalBackends[] は登録済み External backend 名のリストを返す。";

ClaudeSubkernelPollTick::usage =
  "ClaudeSubkernelPollTick[] は AwaitingLLMTransitions の Subkernel job (AwaitKind=SubkernelTask) を走査し、future の非ブロッキング完了判定を行い、完了時に ClaudeCompleteHandlerOutput で結果を produce (slot は OutputArc で返却)。巨大結果は inline せず summary 化。";
$ClaudeSubkernelSubmit::usage =
  "$ClaudeSubkernelSubmit は Subkernel executor の submit 関数 (fn[HoldComplete[expr], accessSpec] -> <|\"Handle\"->_|> | None)。Automatic は ParallelSubmit[NBExecuteHeldExprSubkernelRaw[...]] (kernel/関数が利用可能なとき)。テストで mock 注入可。";
$ClaudeSubkernelPoll::usage =
  "$ClaudeSubkernelPoll は Subkernel job の非ブロッキング完了判定 (fn[handle] -> <|\"Done\"->_, \"Result\"->_|>)。Automatic は future の非ブロッキング poll。テストで mock 注入可。";
$ClaudeSubkernelResultInlineLimit::usage =
  "$ClaudeSubkernelResultInlineLimit は subkernel 結果を token payload に inline できる ByteCount 上限 (既定 64KB)。超過時は summary 化。";

(* ::Subsection:: *)
(* Private *)

Begin["`Private`"];

ClaudeOrchestrator`Workflow`$WorkflowVersion =
  "2026-05-16-async-handler-z-stage1";

(* バージョン履歴:
   2026-05-16 (async-handler-z-stage1): handler 内 LLM 呼出の非同期 callback
     化 (HANDOVER_Z_async_handler.md の Z 案、Phase 1-2 を実装)。
     - WorkflowNet \:306b "AwaitingLLMTransitions" \:30d5\:30a3\:30fc\:30eb\:30c9\:3092\:8ffd\:52a0\:3002
     - iExecutePureFunction \:3092 Block \:52d5\:7684\:675f\:7e1b\:3067 wrap:
       handler \:5185\:3067 $ClaudeCurrentWid / $ClaudeCurrentTransition /
       $ClaudeCurrentAwaitId / $ClaudeCurrentBinding \:3092\:53c2\:7167\:53ef\:80fd\:306b\:3057\:3001
       handler \:6238\:308a\:5024\:304c <|"Status" -> "AwaitingLLM", ...|> \:306e\:5834\:5408\:306f
       Awaiting \:30b9\:30c6\:30fc\:30bf\:30b9\:3092\:8fd4\:3059\:3002
     - ClaudeFireTransition \:306b Awaiting branch \:3092\:8ffd\:52a0: input \:30c8\:30fc\:30af\:30f3\:306f
       consume \:3059\:308b\:304c output \:306f produce \:305b\:305a AwaitingLLMTransitions \:306b
       \:8a18\:9332\:3002Trace \:306b "TransitionAwaiting" event \:3092\:6b8b\:3059\:3002
     - ClaudeCompleteHandlerOutput[wid, awaitId, output] Public API \:3092\:65b0\:8a2d:
       callback \:304b\:3089\:547c\:3070\:308c\:3066\:7559\:4fdd\:4e2d\:306e transition \:306e output token \:3092
       produce \:3059\:308b\:3002\:8a72\:5f53\:306a\:3044 awaitId \:306f silent no-op (Cancel \:5f8c\:306e
       \:8fc5\:96f7\:9632\:6b62)\:3002
     - ClaudeAwaitingTransitions[wid] \:3067\:73fe\:5728\:7559\:4fdd\:4e2d\:306e transition \:3092\:53d6\:5f97\:3002
     - iWorkflowAsyncTick / iRunWorkflowSync: AwaitingLLM \:304c\:6b8b\:3063\:3066\:3044\:308b\:9593\:306f
       Stuck \:5224\:5b9a\:3092\:6291\:5236\:3057\:3001polling \:7d99\:7d9a\:307e\:305f\:306f Pause \:5f85\:6a5f\:3068\:3059\:308b\:3002
     - ClaudeCancelWorkflow: AwaitingLLM \:5168\:30a8\:30f3\:30c8\:30ea\:3092\:30af\:30ea\:30a2\:3001Trace \:306b
       discard event \:3092\:6b8b\:3059\:3002
     \:5f8c\:65b9\:4e92\:63db\:6027: \:65e2\:5b58\:306e\:540c\:671f handler (\:6238\:308a\:5024 <|"Payload" -> ...|>) \:306f
     \:305d\:306e\:307e\:307e\:52d5\:4f5c\:3002Awaiting \:6a5f\:69cb\:306f handler \:304c\:660e\:793a\:7684\:306b
     <|"Status" -> "AwaitingLLM", ...|> \:3092\:8fd4\:3057\:305f\:5834\:5408\:306b\:9650\:5b9a\:3057\:3066
     \:767a\:52d5\:3059\:308b\:3002
   2026-05-10 (retry-policy-enforcement): handler 失敗の繰り返し暴走を
     抑止する RetryPolicy 適用ロジックを追加 (result8.nb で発見:
     WorkerChatGPT が atomic rollback 後に毎 tick 再 enabled となり、
     ChatGPT API を 25 回以上叩き続けるバグ)。
     - WorkflowNet に "TransitionFailureCounts" カウンタを追加。
     - ClaudeFireTransition: handler 失敗時に該当 transition の連続失敗
       回数を ++、成功時はリセット。Trace に AttemptCount を記録。
     - ClaudeEnabledTransitions: 連続失敗回数が
       (RetryPolicy.MaxRetries + 1) 以上に達した transition を enabled
       から除外。これは Imai 先生のご指摘の「同一呼び出しの繰り返しの
       最大制限」ガード。デフォルト MaxRetries = 0 なので、handler が
       1 回失敗したら以降そのまま除外される。
     - iRunWorkflowSync / iWorkflowAsyncTick の Switch から
       "HandlerFailed" 終端判定を撤去 (continue にする)。失敗カウンタ
       による除外で次 step は自然に "Stuck" に到達するため。
     全体バジェット (MaxSteps / MaxWait) は既存の通り機能。
   2026-05-10 (atomic-firing-rollback): handler 失敗時のトークン消費バグを
     修正 (result7.nb で発見)。詳細は前バージョン参照。
   2026-05-10 (handler-error-detection): iExecutePureFunction を罠 #16 と
     Bug 2 に対応して書き直し。
   2026-05-05: Stage B Week 2c-2c (shim 統合)。
*)

(* ::Subsubsection:: *)
(* Registry *)

(* registry: wid -> WorkflowNet Association *)
If[!AssociationQ[$iWorkflowNets],
  $iWorkflowNets = <||>];

(* async job registry: wid -> async job 状態 Association.
   Status: "Running" | "Completed". 完了後は TerminationReason / EndTime が
   ある。entry はクリーンアップ時に KeyDrop する。
   ClaudeRunWorkflow[..., "Async" -> True] で起動。  *)
If[!AssociationQ[$iWorkflowAsyncJobs],
  $iWorkflowAsyncJobs = <||>];

(* completion hooks registry (Week 2c-2c): wid -> List of fn.
   workflow 完了時に一回限り発火される。発火と同時に当該 wid のエントリを
   KeyDrop して再入を防ぐ。Sync は iRunWorkflowSync 戻り値直前、Async は
   iMarkAsyncCompleted で発火される。*)
If[!AssociationQ[$iWorkflowCompletionHooks],
  $iWorkflowCompletionHooks = <||>];

(* ID generators *)
iGenerateWorkflowId[] :=
  "wf-" <> ToString[UnixTime[]] <> "-" <>
    IntegerString[RandomInteger[{16^^100000, 16^^FFFFFF}], 16];

iGenerateTokenId[] :=
  "tok-" <> ToString[UnixTime[]] <> "-" <>
    IntegerString[RandomInteger[{0, 9999}], 10, 4];

iCurrentTime[] := AbsoluteTime[];

(* ::Subsubsection:: *)
(* 型ビルダー *)

Options[WorkflowToken] = {
  "TokenId"      -> Automatic,
  "Kind"         -> "Task",
  "Payload"      -> <||>,
  "PrivacyLabel" -> 0.0,
  "ParentIds"    -> {},
  "CreatedBy"    -> "user"};

WorkflowToken[opts:OptionsPattern[]] :=
  Module[{tid},
    tid = OptionValue["TokenId"] /. Automatic :> iGenerateTokenId[];
    <|
      "TokenId"      -> tid,
      "Kind"         -> OptionValue["Kind"],
      "Payload"      -> OptionValue["Payload"],
      "PrivacyLabel" -> OptionValue["PrivacyLabel"],
      "ParentIds"    -> OptionValue["ParentIds"],
      "CreatedAt"    -> iCurrentTime[],
      "CreatedBy"    -> OptionValue["CreatedBy"],
      "Trace"        -> {}
    |>
  ];

Options[WorkflowPlace] = {
  "Capacity"      -> Infinity,
  "Visibility"    -> "Internal",
  "AcceptedKinds" -> All,
  "Description"   -> ""};

WorkflowPlace[name_String, opts:OptionsPattern[]] :=
  <|
    "Name"          -> name,
    "TokenIds"      -> {},
    "Capacity"      -> OptionValue["Capacity"],
    "Visibility"    -> OptionValue["Visibility"],
    "AcceptedKinds" -> OptionValue["AcceptedKinds"],
    "Description"   -> OptionValue["Description"]
  |>;

Options[WorkflowTransition] = {
  "InputArcs"    -> {},
  "OutputArcs"   -> {},
  "Guard"        -> None,
  "Executor"     -> "PureFunction",
  "RuntimeSpec"  -> <||>,
  "RetryPolicy"  -> <|"MaxRetries" -> 0, "Backoff" -> "None"|>,
  "AccessPolicy" -> <||>,
  "Timeout"      -> None,
  "Priority"     -> 0,
  "Description"  -> ""};

WorkflowTransition[name_String, opts:OptionsPattern[]] :=
  <|
    "Name"         -> name,
    "InputArcs"    -> OptionValue["InputArcs"],
    "OutputArcs"   -> OptionValue["OutputArcs"],
    "Guard"        -> OptionValue["Guard"],
    "Executor"     -> OptionValue["Executor"],
    "RuntimeSpec"  -> OptionValue["RuntimeSpec"],
    "RetryPolicy"  -> OptionValue["RetryPolicy"],
    "AccessPolicy" -> OptionValue["AccessPolicy"],
    "Timeout"      -> OptionValue["Timeout"],
    "Priority"     -> OptionValue["Priority"],
    "Description"  -> OptionValue["Description"]
  |>;

Options[WorkflowNet] = {
  "WorkflowId"     -> Automatic,
  "SourcePlace"    -> "Start",
  "FinalPlaces"    -> {"Done"},
  "Places"         -> <||>,
  "Transitions"    -> <||>,
  "InitialMarking" -> <||>,
  "Description"    -> "",
  "ParentRuntime"  -> Missing[],
  (* C (2026-05-17): workflow デフォルトの AwaitingLLM timeout 秒数。
     transition.RuntimeSpec.AwaitingLLMTimeout > この値 > なし (None) の
     優先順序で resolve される。値が NumericQ かつ > 0 のときのみ有効。
     None (default) ならエンジンは timeout を仕込まず、現状の挙動と完全互換。 *)
  "DefaultAwaitingLLMTimeout" -> None};

WorkflowNet[opts:OptionsPattern[]] :=
  Module[{wid},
    wid = OptionValue["WorkflowId"] /. Automatic :> iGenerateWorkflowId[];
    <|
      "WorkflowId"     -> wid,
      "FormatVersion"  -> 2,
      "SourcePlace"    -> OptionValue["SourcePlace"],
      "FinalPlaces"    -> OptionValue["FinalPlaces"],
      "Places"         -> OptionValue["Places"],
      "Transitions"    -> OptionValue["Transitions"],
      "Tokens"         -> <||>,
      "InitialMarking" -> OptionValue["InitialMarking"],
      "Workers"        -> <||>,
      "Policy"         -> <|
                            "MaxParallelFirings" -> Infinity,
                            "FairnessRule"       -> "Priority"
                          |>,
      "Trace"          -> {},
      "Status"         -> "Idle",
      (* TransitionFailureCounts: transition 名 -> 連続失敗回数。
         handler 失敗 (atomic firing rollback) のたびに ++ し、
         RetryPolicy の MaxRetries+1 回に達した transition は
         enabled から除外される (iEnumerateBindings で参照)。
         成功発火時はリセットされる。
         キーが存在しない transition は失敗 0 回として扱う。 *)
      "TransitionFailureCounts" -> <||>,
      (* AwaitingLLMTransitions (2026-05-16, Z\:6848): handler \:304c
         \:975e\:540c\:671f LLM \:547c\:51fa\:3057\:3092\:6295\:3052\:3066 <|"Status" -> "AwaitingLLM"|> \:3092
         \:8fd4\:3057\:305f\:5834\:5408\:306b\:3001input \:30c8\:30fc\:30af\:30f3\:306f consume \:3057\:305f\:307e\:307e output \:3092
         produce \:3057\:305a\:306b\:7559\:4fdd\:3055\:308c\:308b transition \:306e registry\:3002
         awaitId -> <|
           "AwaitId"           -> awaitId,
           "TransitionName"    -> tname,
           "Binding"            -> binding,
           "ConsumedIds"        -> {tid, ...},
           "PartialPayload"    -> <|...|>,
           "StartTime"          -> AbsoluteTime
         |>
         callback \:304b\:3089 ClaudeCompleteHandlerOutput[wid, awaitId, output] \:304c
         \:547c\:3070\:308c\:308b\:3068\:3001\:8a72\:5f53\:30a8\:30f3\:30c8\:30ea\:3092\:53d6\:308a\:51fa\:3057\:3066 produce \:3057\:3001
         \:305d\:306e\:30a8\:30f3\:30c8\:30ea\:3092\:524a\:9664\:3059\:308b\:3002 *)
      "AwaitingLLMTransitions" -> <||>,
      (* C (2026-05-17): workflow デフォルトの AwaitingLLM timeout (秒)。
         transition 個別の AwaitingLLMTimeout が無い場合のみ使う。
         None または非数値なら timeout を仕込まない (現状互換)。 *)
      "DefaultAwaitingLLMTimeout" -> OptionValue["DefaultAwaitingLLMTimeout"],
      "Metadata"       -> <|
                            "CreatedAt"     -> iCurrentTime[],
                            "Description"   -> OptionValue["Description"],
                            "ParentRuntime" -> OptionValue["ParentRuntime"]
                          |>
    |>
  ];

(* ::Subsubsection:: *)
(* Validation *)

iValidateWorkflowNet[wf_Association] :=
  Module[{errors = {}, places, transitions, source, finals, allPlaceNames},
    
    (* 1. 必須キーチェック *)
    Do[
      If[!KeyExistsQ[wf, k],
        AppendTo[errors, "MissingKey: " <> k]
      ],
      {k, {"WorkflowId", "SourcePlace", "FinalPlaces", "Places",
           "Transitions", "InitialMarking", "Status"}}
    ];
    
    If[errors =!= {}, Return[<|"Valid" -> False, "Errors" -> errors|>]];
    
    places       = wf[["Places"]];
    transitions  = wf[["Transitions"]];
    source       = wf[["SourcePlace"]];
    finals       = wf[["FinalPlaces"]];
    allPlaceNames = Keys[places];
    
    (* 2. SourcePlace は Places 内に存在する *)
    If[!MemberQ[allPlaceNames, source],
      AppendTo[errors,
        "SourcePlaceNotFound: " <> source <>
        " (available: " <> StringRiffle[allPlaceNames, ", "] <> ")"]
    ];
    
    (* 3. FinalPlaces は全て Places 内に存在する *)
    Scan[
      If[!MemberQ[allPlaceNames, #],
        AppendTo[errors, "FinalPlaceNotFound: " <> #]
      ]&,
      finals
    ];
    
    (* 4. 各 Transition の InputArcs / OutputArcs の Place 参照を検証 *)
    KeyValueMap[
      Function[{tname, trans},
        Scan[
          With[{p = Lookup[#, "Place", None]},
            If[p === None || !MemberQ[allPlaceNames, p],
              AppendTo[errors,
                "TransitionInputArcInvalid: " <> tname <> " -> " <> ToString[p]]
            ]
          ]&,
          Lookup[trans, "InputArcs", {}]
        ];
        Scan[
          With[{p = Lookup[#, "Place", None]},
            If[p === None || !MemberQ[allPlaceNames, p],
              AppendTo[errors,
                "TransitionOutputArcInvalid: " <> tname <> " -> " <> ToString[p]]
            ]
          ]&,
          Lookup[trans, "OutputArcs", {}]
        ];
        
        (* 5. Executor の許容値 *)
        With[{exec = Lookup[trans, "Executor", "PureFunction"]},
          If[!MemberQ[
              {"ClaudeRuntime", "PackageManager", "PureFunction", "External", "Subkernel"}, exec],
            AppendTo[errors,
              "TransitionExecutorInvalid: " <> tname <> " -> " <> ToString[exec]]
          ]
        ]
      ],
      transitions
    ];
    
    (* 6. InitialMarking の place 参照検証 *)
    KeyValueMap[
      Function[{p, tokens},
        If[!MemberQ[allPlaceNames, p],
          AppendTo[errors, "InitialMarkingPlaceNotFound: " <> p]
        ]
      ],
      wf[["InitialMarking"]]
    ];
    
    (* 7. WF-net 制約: 弧の不足チェック (warning レベル、Stage B では errors にしない) *)
    (* Stage B Week 2 で connectivity check を追加予定 *)
    
    If[errors === {},
      <|"Valid" -> True,  "Errors" -> {}|>,
      <|"Valid" -> False, "Errors" -> errors|>
    ]
  ];

(* ::Subsubsection:: *)
(* ClaudeCreateWorkflowNet *)

Options[ClaudeCreateWorkflowNet] = {
  "ValidateStrict" -> True,
  "Description"    -> "",
  "ParentRuntime"  -> Missing[]};

ClaudeCreateWorkflowNet[spec_Association, opts:OptionsPattern[]] :=
  Module[{wf, validation, wid},
    
    (* 1. spec が WorkflowNet 由来でなければ補完 *)
    wf = If[KeyExistsQ[spec, "FormatVersion"],
      spec,
      WorkflowNet @@ Normal @ Join[
        spec,
        <|"Description"   -> OptionValue["Description"],
          "ParentRuntime" -> OptionValue["ParentRuntime"]|>
      ]
    ];
    
    (* 2. validation *)
    validation = iValidateWorkflowNet[wf];
    If[!validation[["Valid"]],
      If[OptionValue["ValidateStrict"],
        Throw[
          $Failed,
          "WorkflowNetInvalid: " <>
          StringRiffle[validation[["Errors"]], "; "]
        ],
        Message[ClaudeCreateWorkflowNet::invalid, validation[["Errors"]]];
      ]
    ];
    
    (* 3. registry に登録 *)
    wid = wf[["WorkflowId"]];
    AssociateTo[$iWorkflowNets, wid -> wf];
    
    (* 4. wid を返す *)
    wid
  ];

ClaudeCreateWorkflowNet::invalid =
  "WorkflowNet validation failed (non-strict mode): `1`";

(* ::Subsubsection:: *)
(* ClaudeSubmitToken *)

ClaudeSubmitToken[wid_String, token_Association, place_:Automatic] :=
  Module[{wf, target, capacity, currentTokens, tid},
    
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    
    wf = $iWorkflowNets[wid];
    target = If[place === Automatic,
      wf[["SourcePlace"]],
      place
    ];
    
    (* 0. target place 存在確認 *)
    If[!KeyExistsQ[wf[["Places"]], target],
      Throw[$Failed,
        "PlaceNotFound: " <> target <>
        " (available: " <> StringRiffle[Keys[wf[["Places"]]], ", "] <> ")"]
    ];
    
    (* 1. token に TokenId が無ければ生成 *)
    tid = Lookup[token, "TokenId", iGenerateTokenId[]];
    
    (* 2. capacity check *)
    capacity = wf[["Places", target, "Capacity"]];
    currentTokens = wf[["Places", target, "TokenIds"]];
    If[capacity =!= Infinity && Length[currentTokens] >= capacity,
      Throw[$Failed,
        "PlaceCapacityExceeded: " <> target <>
        " (capacity " <> ToString[capacity] <> ")"]
    ];
    
    (* 3. AcceptedKinds check *)
    With[{kinds = wf[["Places", target, "AcceptedKinds"]]},
      If[kinds =!= All && !MemberQ[kinds, token[["Kind"]]],
        Throw[$Failed,
          "TokenKindRejected: " <> target <> " accepts " <> ToString[kinds] <>
          ", got " <> ToString[token[["Kind"]]]]
      ]
    ];
    
    (* 4. Token registry に追加、target place の TokenIds に追加 *)
    (* IMPORTANT: ReplacePart は Association の新規キー追加を反映しないため、
                  Tokens registry への新規 token id 追加には Append を使う。
                  existing key path (Places の TokenIds、Status、Trace) は
                  ReplacePart で OK。*)
    Module[{newWf, tokenAssoc},
      tokenAssoc = Append[token, "TokenId" -> tid];
      
      (* Tokens registry: 新規キー追加 -> Append で *)
      newWf = ReplacePart[wf,
        "Tokens" -> Append[wf[["Tokens"]], tid -> tokenAssoc]];
      
      (* Places の TokenIds、Status、Trace: existing path -> ReplacePart で *)
      newWf = ReplacePart[newWf,
        {{"Places", target, "TokenIds"} -> Append[currentTokens, tid],
         {"Status"}                      -> If[wf[["Status"]] === "Idle",
                                              "Running", wf[["Status"]]],
         {"Trace"}                       -> Append[wf[["Trace"]],
           <|"Event"     -> "TokenSubmitted",
             "TokenId"   -> tid,
             "Place"     -> target,
             "Timestamp" -> iCurrentTime[]|>]}
      ];
      
      AssociateTo[$iWorkflowNets, wid -> newWf]
    ];
    
    <|"WorkflowId" -> wid,
      "TokenId"    -> tid,
      "Place"      -> target,
      "Marking"    -> iComputeCurrentMarking[wid]|>
  ];

(* ::Subsubsection:: *)
(* ClaudeSubmitInputs / ClaudeBindAndSubmit (\:5165\:529b\:5909\:6570\:8336\:539a\:30d8\:30eb\:30d1\:30fc) *)

(* \[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]
   reviewPetriProposal / proposePetriNet \:7b49\:3067 LLM \:306b net \:3092\:63d0\:6848\:3055\:305b\:308b\:5834\:5408\:3001
   petri-multi-provider-generation skill \:306e\:898f\:7d04\:306b\:3088\:308a\:751f\:6210 net \:306e\:6700\:521d\:306e
   worker \:306f Lookup[binding[["Source", "Payload"]], "Text", ""] \:3092\:8aad\:3080\:3002
   \:3057\:305f\:304c\:3063\:3066\:30e6\:30fc\:30b6\:306f Mathematica \:5909\:6570 text \:306e\:5024\:3092
   "Text" \:30ad\:30fc\:4ed8\:304d\:3067 Source Token Payload \:306b\:6295\:5165\:3057\:306a\:3051\:308c\:3070\:306a\:3089\:306a\:3044\:3002

   ClaudeSubmitToken[wid,
     WorkflowToken["Kind" -> "Task", "Payload" -> <|"Text" -> text|>]]
   \:3092\:6bce\:56de\:66f8\:304f\:306e\:306f\:30dc\:30a4\:30e9\:30fc\:30d7\:30ec\:30fc\:30c8\:306a\:306e\:3067\:3001\:6b21\:306e 2 \:7a2e\:985e\:306e\:8336\:539a\:30d8\:30eb\:30d1\:30fc\:3092
   \:516c\:958b\:3059\:308b\:3002

   ClaudeSubmitInputs[wid, payload]  : Association \:3092\:76f4\:63a5\:6295\:5165
   ClaudeBindAndSubmit[wid, vars__]   : HoldRest \:3067 Symbol \:540d \:2192 \:30ad\:30fc\:540d\:5909\:63db
   \[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine] *)

ClaudeSubmitInputs[wid_String, payload_Association, place_:Automatic] :=
  ClaudeSubmitToken[wid,
    WorkflowToken["Kind" -> "Task", "Payload" -> payload],
    place];

(* ClaudeBindAndSubmit \:306f Symbol \:540d\:3092\:305d\:306e\:307e\:307e Payload \:30ad\:30fc\:306b\:3059\:308b\:3002
   Mathematica \:306f case-sensitive\:3001\:307e\:305f\:6f22\:5b57\:3084 Unicode \:306e\:5909\:6570\:540d\:3082\:8a31\:5bb9\:3055\:308c\:308b\:305f\:3081\:3001
   \:4f59\:8a08\:306a\:5909\:63db (\:5148\:982d\:5927\:6587\:5b57\:5316\:7b49) \:306f\:884c\:308f\:305a SymbolName \:30ed\:30fc\:30c7\:30fc\:30bf\:3092\:7dad\:6301\:3059\:308b\:3002

   \:4f8b:
     text   -> "text"
     title  -> "title"
     \:672c\:6587   -> "\:672c\:6587"
     srcCode -> "srcCode"
   \:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:5074\:306e LLM \:751f\:6210\:30cf\:30f3\:30c9\:30e9\:306f\:540c\:540d\:306e\:30ad\:30fc\:3067 Lookup \:3059\:308c\:3070\:3088\:3044\:3002

   2 \:5f62\:5f0f\:3092\:53d7\:3051\:4ed8\:3051\:308b:
     ClaudeBindAndSubmit[wid, v1, v2, ...]    (* \:53ef\:5909\:9577 *)
     ClaudeBindAndSubmit[wid, {v1, v2, ...}]  (* List \:7248: \:5909\:6570\:8d4a\:6e21\:3057\:53ef\:80fd *)
   \:30d1\:30bf\:30fc\:30f3\:306f vars__Symbol \:3068 varsList_List \:3067\:6392\:4ed6\:7684\:3001\:66d6\:6627\:3055\:7121\:3057\:3002 *)
SetAttributes[ClaudeBindAndSubmit, HoldRest];

(* List \:7248: ClaudeBindAndSubmit[wid, {var1, var2, ...}]\:3002
   \:5909\:6570 vars = {a, b, c} \:3092\:7d4c\:7531\:3057\:3066\:6e21\:3059\:5834\:5408\:3082\:3053\:308c\:3092\:7d4c\:7531\:3002
   Cases \:306e\:30ec\:30d9\:30eb\:306f Infinity (List \:5185\:90e8\:306e Symbol \:307e\:3067\:8d70\:67fb)\:3002 *)
ClaudeBindAndSubmit[wid_String, varsList_List] :=
  Module[{bindings},
    bindings = Association @ Cases[
      Hold[varsList],
      HoldPattern[v_Symbol] :>
        (SymbolName[Unevaluated[v]] -> v),
      Infinity];
    If[Length[bindings] === 0,
      Throw[$Failed,
        "ClaudeBindAndSubmit: no bindable Symbol in list"]];
    ClaudeSubmitToken[wid,
      WorkflowToken["Kind" -> "Task", "Payload" -> bindings]]
  ];

(* \:53ef\:5909\:9577\:7248: ClaudeBindAndSubmit[wid, var1, var2, ...]\:3002
   __Symbol \:306b\:3088\:308a\:3001List \:5f15\:6570\:3068\:306f\:5b8c\:5168\:306b\:6392\:4ed6\:3002 *)
ClaudeBindAndSubmit[wid_String, vars__Symbol] :=
  Module[{bindings},
    bindings = Association @ Cases[
      Hold[vars],
      HoldPattern[v_Symbol] :>
        (SymbolName[Unevaluated[v]] -> v),
      {1}];
    If[Length[bindings] === 0,
      Throw[$Failed,
        "ClaudeBindAndSubmit: no bindable Symbol in arguments"]];
    ClaudeSubmitToken[wid,
      WorkflowToken["Kind" -> "Task", "Payload" -> bindings]]
  ];

(* \[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]
   ClaudeApplyProposal:
   reviewPetriProposal / proposePetriNet \:7b49\:304c\:8fd4\:3059 proposal Association \:306e
   "Code" \:6587\:5b57\:5217\:3092 ToExpression \:3067\:8a55\:4fa1\:3057\:3001"BuilderName" \:304c\:6307\:3059 net builder
   \:95a2\:6570 (\:4f8b: buildDualReviewNet) \:3092\:30bb\:30c3\:30b7\:30e7\:30f3\:306b\:5b9a\:7fa9\:3059\:308b\:3002

   \:5b9f\:88c5\:30e1\:30e2 (Wolfram trap \:56de\:907f):
   - ToExpression \:306e\:8a55\:4fa1\:5931\:6557\:6642\:306b\:30e1\:30c3\:30bb\:30fc\:30b8\:3092\:6291\:5236\:3057\:3064\:3064\:7d50\:679c\:3092\:898b\:308b\:305f\:3081
     Check \:306f\:4f7f\:308f\:305a (trap #16 \:56de\:907f)\:3001Quiet \:306e\:307f\:3092\:4f7f\:7528\:3059\:308b\:3002
   - Symbol[name] \:306f\:30e6\:30fc\:30b6\:306e current context (\:901a\:5e38 Global`) \:306b\:30b7\:30f3\:30dc\:30eb\:3092
     \:4f5c\:308b\:304c\:3001ToExpression \:3082\:540c\:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:3067\:5b9a\:7fa9\:3059\:308b\:306e\:3067\:6574\:5408\:3059\:308b\:3002
   \[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine]\[HorizontalLine] *)

ClaudeApplyProposal::badtype =
  "ClaudeApplyProposal: \:5f15\:6570\:306e Head \:304c `1` \:3060\:304c\:3001Association \:304c\:5fc5\:8981\:3002\n" <>
  "proposal Association \:3092\:8fd4\:3059\:306e\:306f proposePetriNet[goal]\:3002\n" <>
  "reviewPetriProposal[goal] \:306f Column \:3092\:8fd4\:3059\:8868\:793a\:7528\:95a2\:6570\:3067 Association \:3092\:8fd4\:3055\:306a\:3044\:3002\n" <>
  "\:6b63\:3057\:3044\:4f7f\:3044\:65b9:\n" <>
  "  proposal = proposePetriNet[goal];\n" <>
  "  builder  = ClaudeApplyProposal[proposal];";

ClaudeApplyProposal::nocode =
  "ClaudeApplyProposal: proposal[\"Code\"] \:304c\:6587\:5b57\:5217\:3067\:306f\:306a\:3044 (Head: `1`)\:3002\n" <>
  "proposal \:306e\:751f\:6210\:306b\:5931\:6557\:3057\:3066\:3044\:308b\:53ef\:80fd\:6027\:304c\:3042\:308b\:3002\n" <>
  "proposal[\"IsErrorResponse\"] \:3068 proposal[\"RawResponse\"] \:3092\:78ba\:8a8d\:3057\:3066\:304f\:3060\:3055\:3044\:3002";

ClaudeApplyProposal::nosym =
  "ClaudeApplyProposal: Global`proposal \:304c\:5b9a\:7fa9\:3055\:308c\:3066\:3044\:306a\:3044\:3002\n" <>
  "`proposal = proposePetriNet[goal]` \:3092\:5148\:306b\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002";

(* \[HorizontalLine]\[HorizontalLine] \:5f15\:6570\:306a\:3057\:7248: Global`proposal \:3092\:81ea\:52d5\:53c2\:7167 \[HorizontalLine]\[HorizontalLine]
   \:30e6\:30fc\:30b6\:304c `proposal = proposePetriNet[goal]` \:3068\:4ee3\:5165\:3057\:305f\:5834\:5408\:3001
   \:5f15\:6570\:306a\:3057\:7248\:3067 Global`proposal \:3092\:81ea\:52d5\:53c2\:7167\:3067\:304d\:308b\:3002

   \:5b9f\:88c5\:30e1\:30e2: ValueQ[sym] (sym \:306f Module \:5c40\:6240\:5909\:6570) \:306f\:5e38\:306b True \:3092\:8fd4\:3059\:305f\:3081\:3001
   Global`proposal \:3092\:76f4\:63a5\:53c2\:7167\:3059\:308b\:5fc5\:8981\:304c\:3042\:308b\:3002Quiet \:3067 newsym \:30e1\:30c3\:30bb\:30fc\:30b8\:3092\:6291\:5236\:3002 *)
ClaudeApplyProposal[] :=
  Module[{p},
    If[!Quiet[ValueQ[Global`proposal]],
      Message[ClaudeApplyProposal::nosym];
      Return[$Failed, Module]];
    p = Global`proposal;
    Which[
      AssociationQ[p],
        ClaudeApplyProposal[p],
      True,
        Message[ClaudeApplyProposal::badtype, Head[p]];
        $Failed]];

(* \[HorizontalLine]\[HorizontalLine] \:660e\:793a\:7684 Association \:6e21\:3057 \[HorizontalLine]\[HorizontalLine] *)
ClaudeApplyProposal[proposal_Association] :=
  Module[{code, builderName},
    code = Lookup[proposal, "Code", None];
    If[!StringQ[code],
      Message[ClaudeApplyProposal::nocode, Head[code]];
      Return[$Failed, Module]];

    (* \:30b3\:30fc\:30c9\:3092\:8a55\:4fa1\:3057\:3066\:95a2\:6570\:7fa4\:3092\:5b9a\:7fa9 *)
    Quiet @ ToExpression[code];

    (* BuilderName \:304c\:3042\:308c\:3070 Symbol \:3068\:3057\:3066\:8fd4\:3059 *)
    builderName = Lookup[proposal, "BuilderName", None];
    If[StringQ[builderName] && StringLength[builderName] > 0,
      Symbol[builderName],
      Null]
  ];

(* \[HorizontalLine]\[HorizontalLine] \:305d\:308c\:4ee5\:5916 (Grid \:7b49) \[HorizontalLine]\[HorizontalLine] *)
ClaudeApplyProposal[other_] := (
  Message[ClaudeApplyProposal::badtype, Head[other]];
  $Failed
);

iComputeCurrentMarking[wid_String] :=
  Module[{wf},
    wf = $iWorkflowNets[wid];
    Association @@ KeyValueMap[
      Function[{pname, pdata}, pname -> pdata[["TokenIds"]]],
      wf[["Places"]]
    ]
  ];

(* ::Subsubsection:: *)
(* ClaudeWorkflowStatus *)

ClaudeWorkflowStatus[wid_String] :=
  Module[{wf},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[<|"Status" -> "NotFound", "WorkflowId" -> wid|>]
    ];
    
    wf = $iWorkflowNets[wid];
    <|
      "WorkflowId"     -> wid,
      "Status"         -> wf[["Status"]],
      "CurrentMarking" -> iComputeCurrentMarking[wid],
      "TokenCount"     -> Length[wf[["Tokens"]]],
      "ElapsedSec"     -> iCurrentTime[] - wf[["Metadata", "CreatedAt"]],
      "FormatVersion"  -> wf[["FormatVersion"]]
    |>
  ];

(* ::Subsubsection:: *)
(* ClaudeWorkflowList *)

ClaudeWorkflowList[] :=
  Dataset @ KeyValueMap[
    Function[{wid, wf},
      <|"WorkflowId"   -> wid,
        "Status"       -> wf[["Status"]],
        "TokenCount"   -> Length[wf[["Tokens"]]],
        "Description"  -> wf[["Metadata", "Description"]],
        "ElapsedSec"   -> iCurrentTime[] - wf[["Metadata", "CreatedAt"]]|>
    ],
    $iWorkflowNets
  ];

(* ::Subsubsection:: *)
(* ClaudeEnabledTransitions *)

ClaudeEnabledTransitions[wid_String] :=
  Module[{wf, transitions, places, tokens, enabledList,
          failCounts, retryLimitFor},

    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[{}]
    ];

    wf          = $iWorkflowNets[wid];
    transitions = wf[["Transitions"]];
    places      = wf[["Places"]];
    tokens      = wf[["Tokens"]];
    failCounts  = Lookup[wf, "TransitionFailureCounts", <||>];

    (* retryLimitFor[tname]: 当該 transition の総試行回数の上限。
       MaxRetries は「リトライ回数」の意味なので、実際の試行回数の上限は
       MaxRetries + 1。RetryPolicy が無い transition はデフォルト 1 回
       のみ (MaxRetries = 0)。 *)
    retryLimitFor[tname_String] :=
      Module[{trans, policy, maxRetries},
        trans = Lookup[transitions, tname, <||>];
        policy = Lookup[trans, "RetryPolicy", <||>];
        maxRetries = Lookup[policy, "MaxRetries", 0];
        If[!IntegerQ[maxRetries] || maxRetries < 0, maxRetries = 0];
        maxRetries + 1
      ];

    (* 各 transition について enabled な binding を全列挙。
       連続失敗カウントが retryLimitFor 以上に達した transition は除外
       (handler が繰り返し失敗するパターンの暴走防止)。 *)
    enabledList = Flatten[
      KeyValueMap[
        Function[{tname, trans},
          If[Lookup[failCounts, tname, 0] >= retryLimitFor[tname],
            {},  (* 失敗上限到達: 除外 *)
            With[{bindings = iEnumerateBindings[trans, places, tokens]},
              Map[
                Function[binding,
                  If[iEvaluateGuard[trans, binding] === True,
                    <|"Name"     -> tname,
                      "Binding"  -> binding,
                      "Priority" -> Lookup[trans, "Priority", 0]|>,
                    Nothing
                  ]
                ],
                bindings
              ]
            ]
          ]
        ],
        transitions
      ],
      1
    ];

    (* Priority 降順でソート (FIFO は同順位内で挿入順を維持) *)
    SortBy[enabledList, -#[["Priority"]] &]
  ];

(* ::Subsubsection:: *)
(* iEnumerateBindings: input arc を満たす token 組合わせを全列挙 *)

iEnumerateBindings[trans_Association, places_Association, tokens_Association] :=
  Module[{inputArcs, bindingsPerArc},
    
    inputArcs = Lookup[trans, "InputArcs", {}];
    
    If[Length[inputArcs] === 0,
      Return[{<||>}]    (* input なし transition は常に enabled (1 binding) *)
    ];
    
    (* 各 arc について、その arc を満たすトークン候補を列挙 *)
    bindingsPerArc = Map[
      Function[arc,
        Module[{p, kindFilter, multiplicity, tokenIds, candidates, combos},
          p            = arc[["Place"]];
          kindFilter   = Lookup[arc, "TokenKind", All];
          multiplicity = Lookup[arc, "Multiplicity", 1];
          
          (* Multiplicity は正整数のみ *)
          If[!IntegerQ[multiplicity] || multiplicity < 1,
            Return[{}, Module]
          ];
          
          tokenIds = Lookup[places, p, <|"TokenIds" -> {}|>][["TokenIds"]];
          
          candidates = Select[
            tokenIds,
            (kindFilter === All ||
             Lookup[tokens, #, <||>][["Kind"]] === kindFilter) &
          ];
          
          (* Multiplicity 個の token を組合わせとして全列挙 *)
          combos = Subsets[candidates, {multiplicity}];
          
          (* binding[[p]] の形式:
               Multiplicity = 1: 単一 token Association (後方互換)
               Multiplicity > 1: List of token Associations *)
          Map[
            Function[idCombo,
              If[multiplicity === 1,
                <|p -> tokens[First[idCombo]]|>,
                <|p -> Map[tokens, idCombo]|>
              ]
            ],
            combos
          ]
        ]
      ],
      inputArcs
    ];
    
    (* どこかの arc に候補ゼロがあれば enabled binding なし *)
    If[AnyTrue[bindingsPerArc, Length[#] === 0 &],
      Return[{}]
    ];
    
    (* 各 arc から 1 つずつ binding を選ぶ全組合わせ *)
    Map[
      Function[combo, Apply[Join, combo]],
      Tuples[bindingsPerArc]
    ]
  ];

(* ::Subsubsection:: *)
(* iFlattenBinding: binding の各 value (単一 token / List of tokens) を平坦化 *)

iFlattenBinding[binding_Association] :=
  Flatten[
    Map[
      Function[v,
        Which[
          AssociationQ[v],          {v},      (* 単一 token *)
          ListQ[v],                 v,        (* List of tokens *)
          True,                     {v}       (* 防御 *)
        ]
      ],
      Values[binding]
    ],
    1
  ];

(* ::Subsubsection:: *)
(* iEvaluateGuard *)

iEvaluateGuard[trans_Association, binding_Association] :=
  Module[{guard},
    guard = Lookup[trans, "Guard", None];
    Which[
      guard === None,                  True,
      Head[guard] === Function,        TrueQ[Quiet @ guard[binding]],
      True,                            True
    ]
  ];

(* ::Subsubsection:: *)
(* iCheckNBAccessClearance: 簡易 hard policy check (Day 2 stub) *)

iCheckNBAccessClearance[trans_Association, binding_Association] :=
  Module[{accessPolicy, deniedHeads, approvalHeads, payloads, heads},
    
    accessPolicy  = Lookup[trans, "AccessPolicy", <||>];
    deniedHeads   = Lookup[accessPolicy, "DeniedHeads", {}];
    approvalHeads = Lookup[accessPolicy, "ApprovalHeads", {}];
    
    If[Length[deniedHeads] === 0 && Length[approvalHeads] === 0,
      Return[<|"Decision" -> "Allow"|>]
    ];
    
    payloads = Map[Lookup[#, "Payload", <||>] &, iFlattenBinding[binding]];
    heads    = Union @@ Map[iExtractHeadsFromExpr, payloads];
    
    Which[
      Length @ Intersection[heads, deniedHeads] > 0,
        <|"Decision" -> "Deny",
          "Reason"   -> "Forbidden head in payload: " <>
                        StringRiffle[
                          Intersection[heads, deniedHeads], ", "]|>,
      
      Length @ Intersection[heads, approvalHeads] > 0,
        <|"Decision" -> "NeedsApproval",
          "Reason"   -> "Approval head in payload: " <>
                        StringRiffle[
                          Intersection[heads, approvalHeads], ", "]|>,
      
      True,
        <|"Decision" -> "Allow"|>
    ]
  ];

iExtractHeadsFromExpr[expr_] :=
  Module[{heads},
    heads = Cases[
      expr,
      h_Symbol[___] :> SymbolName[h],
      {0, Infinity},
      Heads -> True
    ];
    DeleteDuplicates[heads]
  ];

(* ::Subsubsection:: *)
(* ClaudeFireTransition *)

Options[ClaudeFireTransition] = {
  "ForceAllow" -> False    (* テスト用、NBAccess check をバイパス *)
};

ClaudeFireTransition[wid_String, transitionName_String,
                     binding_Association, opts:OptionsPattern[]] :=
  Module[{wf, trans, nbDecision, guardOK, consumedTokens, producedTokens,
          executorResult, newWf},
    
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    
    wf    = $iWorkflowNets[wid];
    trans = Lookup[wf[["Transitions"]], transitionName, None];
    
    If[trans === None,
      Throw[$Failed, "TransitionNotFound: " <> transitionName]
    ];
    
    (* 0. Workflow Status check (Paused / Cancelled / Done は受け付けない) *)
    If[MemberQ[{"Paused", "Cancelled", "Done"}, wf[["Status"]]],
      Return[<|"Status"         -> "Skipped",
               "Reason"         -> "WorkflowNotRunnable: " <> wf[["Status"]],
               "TransitionName" -> transitionName,
               "WorkflowStatus" -> wf[["Status"]]|>]
    ];
    
    (* 1. NBAccess hard policy check (最優先) *)
    If[!OptionValue["ForceAllow"],
      nbDecision = iCheckNBAccessClearance[trans, binding];
      Switch[nbDecision[["Decision"]],
        "Deny",
          Return[<|"Status" -> "Blocked",
                   "Reason" -> nbDecision[["Reason"]],
                   "TransitionName" -> transitionName|>],
        "NeedsApproval",
          Return[<|"Status"         -> "NeedsApproval",
                   "Reason"         -> nbDecision[["Reason"]],
                   "TransitionName" -> transitionName,
                   "Binding"        -> binding|>],
        "Allow",
          Null
      ]
    ];
    
    (* 2. Guard 再評価 *)
    guardOK = iEvaluateGuard[trans, binding];
    If[!guardOK,
      Return[<|"Status" -> "Blocked",
               "Reason" -> "GuardFailed",
               "TransitionName" -> transitionName|>]
    ];
    
    (* 3. Input tokens consume (Multiplicity > 1 にも対応) *)
    consumedTokens = iFlattenBinding[binding];

    (* 4. Executor 実行
       Z\:6848 (2026-05-16): handler \:5185\:3067 wid \:3092\:53c2\:7167\:53ef\:80fd\:306b\:3059\:308b\:305f\:3081
       \:3053\:3053\:3067 Block \:3067 $ClaudeCurrentWid \:3092\:675f\:7e1b\:3002\:4ed6\:306e
       $ClaudeCurrentTransition / $ClaudeCurrentAwaitId / $ClaudeCurrentBinding \:306f
       iExecutePureFunction \:5185\:3067\:8ffd\:52a0\:675f\:7e1b\:3055\:308c\:308b\:3002 *)
    executorResult = Block[{$ClaudeCurrentWid = wid},
      iExecuteTransition[trans, binding]
    ];

    (* 4b. handler 失敗時の Petri net atomic firing 原則 (重要):
       handler が Failed (== iExecutePureFunction が <|"Status" -> "Failed", ...|>
       を返した) の場合、トークンは消費しない (atomic firing rollback)。
       この transition はそもそも fire しなかったとして扱う。

       理由: 標準的な Petri net 意味論では、transition の発火は atomic
       (input consume と output produce が同時) であり、handler が失敗した
       なら fire そのものが起きていない。

       具体的に防ぎたいバグ (result7.nb で観測):
         - handler が $Failed を返す
         - 旧コードはそれでも input を消費し、空 Payload の output token を
           produce していた
         - 結果、AND-merge の下流が「両方揃った」と誤判定して発火
         - peer review が「ChatGPT 失敗だが Done」と誤報告
       修正後: handler 失敗 → input token は input place に残る → 下流の
       AND-merge は永遠に enabled しない → workflow は正しく該当 place で
       deadlock する (incomplete を可視化)。

       同時に TransitionFailureCounts の該当 transition の連続失敗回数を
       ++ することで、上限到達時に enabled から除外する (result8.nb で
       観測された無限再発火を防ぐ)。

       Trace には TransitionFailed を残す (観測のため)。 *)
    If[Lookup[executorResult, "Status", "Success"] === "Failed",
      Module[{prevCount, newCount, failCounts},
        failCounts = Lookup[wf, "TransitionFailureCounts", <||>];
        prevCount  = Lookup[failCounts, transitionName, 0];
        newCount   = prevCount + 1;
        newWf = ReplacePart[wf,
          "TransitionFailureCounts" ->
            Append[failCounts, transitionName -> newCount]];
        newWf = ReplacePart[newWf,
          "Trace" -> Append[newWf[["Trace"]],
            <|"Event"           -> "TransitionFailed",
              "TransitionName"  -> transitionName,
              "ConsumedIds"     -> {},      (* atomic rollback *)
              "ProducedIds"     -> {},
              "ExecutorStatus"  -> "Failed",
              "ExecutorReason"  -> Lookup[executorResult, "Reason", ""],
              "AttemptCount"    -> newCount,
              "AttemptedConsumeIds" ->
                Map[#[["TokenId"]] &, consumedTokens],
              "Timestamp"       -> iCurrentTime[]|>]];
        AssociateTo[$iWorkflowNets, wid -> newWf];
        Return[<|"Status"          -> "HandlerFailed",
                 "TransitionName"  -> transitionName,
                 "Reason"          -> Lookup[executorResult, "Reason", ""],
                 "AttemptCount"    -> newCount,
                 "ConsumedTokens"  -> {},
                 "ProducedTokens"  -> {},
                 "ExecutorResult"  -> executorResult,
                 "Marking"         -> iComputeCurrentMarking[wid]|>]
      ]
    ];

    (* === Z\:6848 (2026-05-16): Awaiting branch === 
       handler \:304c <|"Status" -> "AwaitingLLM", ...|> \:3092\:8fd4\:3057\:305f\:5834\:5408\:3001
       iExecutePureFunction \:306f <|"Status" -> "Awaiting", "AwaitId" -> aid,
       "Output" -> handlerOutput, "PartialPayload" -> ...|> \:3092\:8fd4\:3057\:3066\:3044\:308b\:3002
       \:3053\:306e branch \:3067:
         - input token \:306f consume \:3059\:308b (\:4ed6 transition \:3092\:30d6\:30ed\:30c3\:30af)
         - producedTokens \:306f \:4f5c\:3089\:306a\:3044
         - AwaitingLLMTransitions[awaitId] \:306b\:8a18\:9332
         - failure counter \:306f\:30ea\:30bb\:30c3\:30c8 (\:4eca\:56de\:306f\:3068\:308a\:3042\:3048\:305a\:300c\:6210\:529f\:30b9\:30bf\:30fc\:30c8\:300d\:6271\:3044)
         - Trace \:306b TransitionAwaiting \:3092\:6b8b\:3059
       callback \:304c\:5230\:7740\:3057\:305f\:3089 ClaudeCompleteHandlerOutput \:3067 produce \:3055\:308c\:308b\:3002 *)
    If[Lookup[executorResult, "Status", "Success"] === "Awaiting",
      Module[{awaitId, partialPayload, consumedIds, awaitingEntry,
              existingAwait, failCounts},
        awaitId        = Lookup[executorResult, "AwaitId",
                          iGenerateAwaitId[wid]];
        partialPayload = Lookup[executorResult, "PartialPayload", <||>];
        consumedIds    = Map[#[["TokenId"]] &, consumedTokens];

        awaitingEntry = <|
          "AwaitId"        -> awaitId,
          "TransitionName" -> transitionName,
          "Binding"        -> binding,
          "ConsumedIds"    -> consumedIds,
          "PartialPayload" -> partialPayload,
          "StartTime"      -> iCurrentTime[]
        |>;

        (* AwaitingLLMTransitions \:30d5\:30a3\:30fc\:30eb\:30c9\:3092 backward compat \:3068\:3057\:3066\:624b\:52d5\:4fdd\:8a3c\:3002 *)
        newWf = iEnsureAwaitingLLMField[wf];
        existingAwait = Lookup[newWf, "AwaitingLLMTransitions", <||>];

        (* 1. Input tokens \:3092 input places \:304b\:3089\:524a\:9664 (consume) *)
        newWf = iConsumeTokensForAwaiting[newWf, trans, consumedTokens];

        (* 2. AwaitingLLMTransitions \:306b\:8ffd\:52a0 *)
        newWf = ReplacePart[newWf,
          "AwaitingLLMTransitions" ->
            Append[existingAwait, awaitId -> awaitingEntry]];

        (* 3. Trace event *)
        newWf = ReplacePart[newWf,
          "Trace" -> Append[newWf[["Trace"]],
            <|"Event"           -> "TransitionAwaiting",
              "TransitionName"  -> transitionName,
              "AwaitId"         -> awaitId,
              "ConsumedIds"     -> consumedIds,
              "Timestamp"       -> iCurrentTime[]|>]];

        (* 4. \:5931\:6557\:30ab\:30a6\:30f3\:30bf\:306f\:30ea\:30bb\:30c3\:30c8 (\:542c\:304f\:6210\:529f\:624b\:524d\:306b retry \:3092\:9632\:3050) *)
        failCounts = Lookup[newWf, "TransitionFailureCounts", <||>];
        newWf = ReplacePart[newWf,
          "TransitionFailureCounts" ->
            KeyDrop[failCounts, transitionName]];

        AssociateTo[$iWorkflowNets, wid -> newWf];

        (* === C (2026-05-17): AwaitingLLMTimeout の発火タイマー ===
           解決優先順序:
             1. trans.RuntimeSpec.AwaitingLLMTimeout (transition 個別)
             2. wf.DefaultAwaitingLLMTimeout         (workflow 全体)
             3. なし (timeout を仕込まない)
           値は秒数。NumericQ かつ > 0 のときのみ有効。
           timeout 経過後にまだ AwaitingLLMTransitions[awaitId] が存在する
           なら、ClaudeCompleteHandlerOutput で fallback Payload を発火。
           fallback Payload は元の partialPayload に
             "_timeout"  -> True
             "_handler"  -> transitionName
           を追加するだけで、その他のキーは保持する。
           ClaudeCompleteHandlerOutput は二重発火に対し silent discard
           (TransitionCallbackDiscarded を Trace に残す) するので、
           LLM 応答が後から到着しても安全。 *)
        With[{tmoTrans = Lookup[trans[["RuntimeSpec"]], "AwaitingLLMTimeout", Automatic],
              tmoWf    = Lookup[newWf, "DefaultAwaitingLLMTimeout", None]},
          Module[{effectiveTmo},
            effectiveTmo = Which[
              (* v7 C1: External/Subkernel の async job は AwaitingLLM の成功扱い
                 timeout を使わない (孤児/誤完了回避)。timeout は poller が単独所有。 *)
              MemberQ[{"ExternalWolframScriptJob", "SubkernelTask"},
                Lookup[If[AssociationQ[partialPayload], partialPayload, <||>],
                  "AwaitKind", ""]], None,
              NumericQ[tmoTrans] && tmoTrans > 0, N[tmoTrans],
              NumericQ[tmoWf]    && tmoWf    > 0, N[tmoWf],
              True, None];
            If[NumericQ[effectiveTmo],
              With[{wid1 = wid, aid1 = awaitId, tname = transitionName,
                    dur = effectiveTmo,
                    pp = If[AssociationQ[partialPayload], partialPayload, <||>]},
                SessionSubmit[ScheduledTask[
                  Quiet @ Check[
                    ClaudeCompleteHandlerOutput[wid1, aid1,
                      <|"Payload" ->
                          Append[pp,
                            <|"_timeout" -> True, "_handler" -> tname|>]|>],
                    Null],
                  {dur, 1}]]]]]];

        Return[<|"Status"         -> "Awaiting",
                 "TransitionName" -> transitionName,
                 "AwaitId"        -> awaitId,
                 "ConsumedTokens" -> consumedIds,
                 "ProducedTokens" -> {},
                 "ExecutorResult" -> executorResult,
                 "Marking"        -> iComputeCurrentMarking[wid]|>]
      ]
    ];

    (* 5. Output tokens produce *)
    producedTokens = iProduceOutputTokens[trans, binding, executorResult];

    (* 6. WorkflowNet 更新。成功発火時は当該 transition の失敗カウンタを
       リセット (連続失敗ではなくなったため)。 *)
    newWf = iApplyFireToWorkflow[
      wf, trans, consumedTokens, producedTokens, executorResult];
    newWf = ReplacePart[newWf,
      "TransitionFailureCounts" ->
        KeyDrop[Lookup[newWf, "TransitionFailureCounts", <||>],
                transitionName]];

    AssociateTo[$iWorkflowNets, wid -> newWf];

    <|"Status"          -> "Fired",
      "TransitionName"  -> transitionName,
      "ConsumedTokens"  -> Map[#[["TokenId"]] &, consumedTokens],
      "ProducedTokens"  -> Map[#[["TokenId"]] &, producedTokens],
      "ExecutorResult"  -> executorResult,
      "Marking"         -> iComputeCurrentMarking[wid]|>
  ];

(* ::Subsubsection:: *)
(* iExecuteTransition *)

iExecuteTransition[trans_Association, binding_Association] :=
  Module[{executor},
    executor = Lookup[trans, "Executor", "PureFunction"];
    Switch[executor,
      "PureFunction",
        iExecutePureFunction[trans, binding],
      "ClaudeRuntime",
        (* Day 4c: stub から本実装に切替 *)
        iExecuteClaudeRuntimeBranch[trans, binding],
      "PackageManager",
        (* Stage B Week 2 で本実装、現状は stub *)
        <|"Status"  -> "Stub",
          "Reason"  -> "PackageManager executor: Stage B Week 2 で実装",
          "Output"  -> binding|>,
      "External",
        (* Phase 3: WolframScript backend を AwaitingLLM 機構へ接続 *)
        iExecuteExternalBranch[trans, binding],
      "Subkernel",
        (* Phase 3.5: subkernel backend を AwaitingLLM 機構へ接続 *)
        iExecuteSubkernelBranch[trans, binding],
      _,
        <|"Status"  -> "Failed",
          "Reason"  -> "UnknownExecutor: " <> ToString[executor]|>
    ]
  ];

(* === Z\:6848 (async-handler) \:7528 \:52d5\:7684\:30b9\:30b3\:30fc\:30d7\:30b7\:30f3\:30dc\:30eb\:521d\:671f\:5024 (2026-05-16) ===
   handler \:5916\:3067\:53c2\:7167\:3055\:308c\:305f\:3068\:304d\:3001Missing[] \:3067\:6e08\:307e\:305b\:308b\:305f\:3081
   \:30c8\:30c3\:30d7\:30ec\:30d9\:30eb (Global / package context) \:3067\:521d\:671f\:5024\:3092\:4e0e\:3048\:3066\:304a\:304f\:3002
   iExecutePureFunction \:5185\:3067 Block \:3067\:4e0a\:66f8\:304d\:3057\:3066 handler \:8a55\:4fa1\:3059\:308b\:3002 *)
If[!ValueQ[$ClaudeCurrentWid],
  $ClaudeCurrentWid = Missing["NotInHandler"]];
If[!ValueQ[$ClaudeCurrentTransition],
  $ClaudeCurrentTransition = Missing["NotInHandler"]];
If[!ValueQ[$ClaudeCurrentAwaitId],
  $ClaudeCurrentAwaitId = Missing["NotInHandler"]];
If[!ValueQ[$ClaudeCurrentBinding],
  $ClaudeCurrentBinding = Missing["NotInHandler"]];

(* === Z\:6848 helper: AwaitingLLM \:30bb\:30f3\:30c1\:30cd\:30eb\:691c\:51fa === *)

(* handler \:6238\:308a\:5024\:304c "AwaitingLLM" \:30b9\:30c6\:30fc\:30bf\:30b9\:3092\:8fd4\:3057\:3066\:3044\:308b\:304b\:3092\:5224\:5b9a\:3002
   \:5bfe\:8c61: Association \:3067 "Status" \:30ad\:30fc \:304c "AwaitingLLM" (\:7570\:5165\:6587\:5b57\:3082\:8a31\:5bb9)\:3002
   \:6238\:308a\:5024: True | False *)
iIsAwaitingHandlerOutput[output_] :=
  AssociationQ[output] &&
  KeyExistsQ[output, "Status"] &&
  StringQ[output[["Status"]]] &&
  ToLowerCase[output[["Status"]]] === "awaitingllm";

(* await ID generator. wid \:3068\:7d44\:307f\:5408\:308f\:305b\:3066\:30b0\:30ed\:30fc\:30d0\:30eb\:306b\:30e6\:30cb\:30fc\:30af\:3002 *)
iGenerateAwaitId[wid_String] :=
  "await-" <> wid <> "-" <> ToString[UnixTime[]] <> "-" <>
    IntegerString[RandomInteger[{16^^1000, 16^^FFFF}], 16];

(* AwaitingLLMTransitions \:30d5\:30a3\:30fc\:30eb\:30c9\:304c\:65e7 WorkflowNet \:306b\:7121\:3044\:5834\:5408\:306e
   backward-compat helper\:3002\:8aad\:307f\:8fbc\:307f\:6e08\:307f net \:3092\:4e0a\:66f8\:304d\:3057\:3066\:8fd4\:3059\:3002 *)
iEnsureAwaitingLLMField[wf_Association] :=
  If[KeyExistsQ[wf, "AwaitingLLMTransitions"],
    wf,
    Append[wf, "AwaitingLLMTransitions" -> <||>]
  ];

iExecutePureFunction[trans_Association, binding_Association] :=
  Module[{handler, output, succeeded, prevML, isCallable,
          widForBlock, tnameForBlock, awaitIdForBlock},
    handler = Lookup[trans[["RuntimeSpec"]], "Handler", Identity];

    (* handler が呼び出し可能か判定。
       Function (純関数) と Symbol (DownValues 持ち、または Identity) を許容。
       これは Bug 2 (旧コードは Head[handler] === Function だけ判定し、
       Symbol handler が素通しで binding がそのまま output になっていた) の修正。 *)
    isCallable = Which[
      Head[handler] === Function,                      True,
      handler === Identity,                            False,  (* Identity は素通し扱い *)
      Head[handler] === Symbol && Length[DownValues[handler]] > 0, True,
      True,                                            False
    ];

    (* Z\:6848 (2026-05-16): \:52d5\:7684\:30b9\:30b3\:30fc\:30d7\:7528\:306e\:5024\:3092\:6e96\:5099\:3002
       wid \:3068 transition \:540d\:306f trans \:304b\:3089\:53d6\:308a\:3001\:73fe\:72b6\:3067\:306f registry \:898b\:308a\:51fa\:3057\:3067\n       \:300c\:3069\:306e wid \:306b\:5c5e\:3059\:308b trans \:304b\:300d\:3092\:540c\:5b9a\:3059\:308b\:624b\:6bb5\:304c\:306a\:3044\:305f\:3081\:3001\:30b3\:30fc\:30eb\:5143\:3067 wid \:3092\n       \:4f1d\:3048\:308b\:9802\:3050\:306e\:4ed5\:7d44\:307f\:3092\:4f7f\:3046\:3002\:73fe\:4ed8 (Day 4d): $ClaudeCurrentWid \:306f\n       ClaudeFireTransition \:304c iExecuteTransition \:3092\:547c\:3076\:524d\:306b Block \:3067\:52d5\:7684\:675f\:7e1b\:3059\:308b\:3068\:3044\:3046\n       \:8a2d\:8a08\:306b\:5909\:66f4\:3057\:305f (\:4e0b\:8a18\:4e0b\:898f)\:3002\:3088\:3063\:3066\:3053\:3053\:3067\:306f Block \:3057\:306a\:3044\:3002
       transition \:540d\:3060\:3051 Block \:3059\:308b\:3002 *)
    tnameForBlock   = Lookup[trans, "Name", "?"];
    (* wid \:306f ClaudeFireTransition \:304c Block[{$ClaudeCurrentWid = wid}, ...] \:3057\:305f
       \:4e0a\:3067 iExecuteTransition \:3092\:547c\:3076\:3088\:3046\:306b\:3057\:3066\:3044\:308b\:305f\:3081\:3001\:3053\:3053\:3067\:306f
       \:898b\:3048\:308b\:3082\:306e\:3092\:305d\:306e\:307e\:307e\:4f7f\:3046\:3002awaitId \:306f\:4e88\:5099\:767a\:884c\:3057\:3066\:304a\:304d
       handler \:5185\:3067\:5229\:7528\:3067\:304d\:308b\:3088\:3046\:306b\:3059\:308b\:3002 *)
    widForBlock     = $ClaudeCurrentWid;
    awaitIdForBlock = If[
      StringQ[widForBlock],
      iGenerateAwaitId[widForBlock],
      Missing["NotInHandler"]];

    Which[
      isCallable,
        (* 罠 #16 回避: Quiet@Check は使わず、フラグ変数で成否を取る。
           Block で $MessageList を局所化し、メッセージが出たかも検知する。
           Z \:6848: \:52d5\:7684\:30b9\:30b3\:30fc\:30d7\:3082 Block \:3067\:4e00\:7dd2\:306b\:675f\:7e1b\:3002 *)
        succeeded = True;
        Block[{
          $MessageList = {},
          prevML$ = $MessageList,
          $ClaudeCurrentTransition = tnameForBlock,
          $ClaudeCurrentAwaitId    = awaitIdForBlock,
          $ClaudeCurrentBinding    = binding
        },
          output = Quiet[
            Check[
              handler[binding],
              (succeeded = False; $Failed)
            ]
          ];
          (* メッセージが出ていれば失敗扱いとする (handler が握り潰しても
             ここで検知できる)。
             Z \:6848: \:305f\:3060\:3057 handler \:5185\:3067 ClaudeQueryAsync \:3092\:8d77\:52d5\:3057\:3066\:3044\:308b\:9014\:4e2d\:3067
             \:30e1\:30c3\:30bb\:30fc\:30b8\:304c\:51fa\:308b\:30b1\:30fc\:30b9\:304c\:3042\:308b\:305f\:3081\:3001AwaitingLLM \:30b9\:30c6\:30fc\:30bf\:30b9\:3092\:8fd4\:3057\:305f\n             \:5834\:5408\:306f\:30e1\:30c3\:30bb\:30fc\:30b8\:691c\:51fa\:306f\:30b9\:30ad\:30c3\:30d7\:3059\:308b\:3002 *)
          If[!iIsAwaitingHandlerOutput[output] &&
             Length[$MessageList] > 0, succeeded = False];
        ],
      handler === Identity,
        output = binding; succeeded = True,
      True,
        output = binding; succeeded = True
    ];

    (* output 自身が $Failed の場合も明示的に失敗 *)
    If[output === $Failed, succeeded = False];

    (* === Z \:6848 (2026-05-16): AwaitingLLM \:30bb\:30f3\:30c1\:30cd\:30eb\:5224\:5b9a ===
       handler \:304c <|"Status" -> "AwaitingLLM"|> \:3092\:8fd4\:3057\:305f\:3089\:3001\:4e0a\:4f4d\:306b
       Awaiting \:30b9\:30c6\:30fc\:30bf\:30b9\:3092\:8fd4\:3059\:3002awaitIdForBlock \:3092\:4f7f\:3063\:305f\:306e\:306f
       handler \:3060\:304b\:3089\:3001\:305d\:306e await ID \:3092\:4e0a\:4f4d\:3082\:540c\:3058\:3082\:306e\:3068\:3057\:3066\:4f7f\:3046\:3002 *)
    Which[
      iIsAwaitingHandlerOutput[output],
        <|"Status"         -> "Awaiting",
          "Output"         -> output,
          "AwaitId"        -> awaitIdForBlock,
          "PartialPayload" -> Lookup[output, "Payload", <||>]|>,
      !succeeded,
        <|"Status" -> "Failed", "Reason" -> "HandlerError"|>,
      True,
        <|"Status" -> "Success", "Output" -> output|>
    ]
  ];

(* ::Subsubsection:: *)
(* ClaudeRuntime executor branch (Day 4c)
   runtime-orchestrator-boundary 準拠: 1 turn 内で完結する純関数的実行のみ。
   multi-turn / retry / approval / commit ordering は呼び元の Workflow が担う。 *)

iBuildContextPacket[trans_Association, binding_Association] :=
  Module[{accessPolicy, runtimeSpec},
    accessPolicy = Lookup[trans, "AccessPolicy", <||>];
    runtimeSpec  = Lookup[trans, "RuntimeSpec",  <||>];
    
    <|"TransitionName"      -> Lookup[trans, "Name", "?"],
      "Binding"              -> binding,
      "InputTokens"          -> iFlattenBinding[binding],
      "Role"                 -> Lookup[accessPolicy, "Role", "Compute"],
      "DirectiveBundle"      -> Lookup[accessPolicy, "DirectiveBundle", <||>],
      "DirectivePrompt"      -> Lookup[accessPolicy, "DirectivePrompt", ""],
      "AllowedCapabilities"  -> Lookup[accessPolicy, "AllowedCapabilities", {}],
      "OutputSchema"         -> Lookup[runtimeSpec, "OutputSchema", None],
      "Model"                -> Lookup[runtimeSpec, "Model", Automatic]|>
  ];

iExecuteClaudeRuntimeBranch[trans_Association, binding_Association] :=
  Module[{adapter, contextPacket, result},
    adapter = Lookup[trans[["RuntimeSpec"]], "Adapter", None];
    
    (* adapter が未指定 → エラー *)
    If[!AssociationQ[adapter],
      Return[<|"Status" -> "Failed",
               "Reason" -> "MissingAdapter: RuntimeSpec[\"Adapter\"] " <>
                           "must be an Association of stage functions"|>]
    ];
    
    (* ClaudeRuntime`ClaudeRuntimeExecuteTransition が定義済みかチェック。
       未ロード時は明示的エラー (Day 4c 以降の ClaudeRuntime.wl が必要)。 *)
    If[!ValueQ[ClaudeRuntime`ClaudeRuntimeExecuteTransition] &&
       Length[DownValues[ClaudeRuntime`ClaudeRuntimeExecuteTransition]] === 0,
      Return[<|"Status" -> "Failed",
               "Reason" -> "ClaudeRuntimeExecuteTransition unavailable: " <>
                           "ClaudeRuntime.wl Day 4c 以降が必要"|>]
    ];
    
    contextPacket = iBuildContextPacket[trans, binding];
    
    result = Quiet @ Check[
      ClaudeRuntime`ClaudeRuntimeExecuteTransition[adapter, contextPacket],
      <|"Status" -> "Failed",
        "Reason" -> "ExceptionInClaudeRuntimeExecuteTransition"|>
    ];
    
    (* ClaudeRuntime 側は <|Status, Output, Proposal, Validation, ExecResult|>
       を返す。Workflow 側で iProduceOutputTokens が baseOutput["Payload"] /
       baseOutput を見るので、Output をそのまま渡す。
       Proposal / Validation / ExecResult は Trace 用の付加情報として保持。 *)
    If[AssociationQ[result],
      result,
      <|"Status" -> "Failed",
        "Reason" -> "InvalidExecutorResult: not an Association"|>
    ]
  ];

(* ::Subsubsection:: *)
(* iProduceOutputTokens *)

iProduceOutputTokens[trans_Association, binding_Association,
                     executorResult_Association] :=
  Module[{outputArcs, parentIds, baseOutput},
    outputArcs = Lookup[trans, "OutputArcs", {}];
    parentIds  = Map[#[["TokenId"]] &, iFlattenBinding[binding]];
    baseOutput = Lookup[executorResult, "Output", <||>];
    
    Map[
      Function[arc,
        Module[{kind, payload},
          kind = Lookup[arc, "TokenKind", "Artifact"];
          
          (* output payload は executor 結果を継承、ただし binding 由来でも OK *)
          payload = Which[
            AssociationQ[baseOutput] && KeyExistsQ[baseOutput, "Payload"],
              baseOutput[["Payload"]],
            AssociationQ[baseOutput],
              baseOutput,
            True,
              <||>
          ];
          
          WorkflowToken[
            "Kind"      -> kind,
            "Payload"   -> payload,
            "ParentIds" -> parentIds,
            "CreatedBy" -> trans[["Name"]]
          ]
        ]
      ],
      outputArcs
    ]
  ];

(* ::Subsubsection:: *)
(* iApplyFireToWorkflow *)

iApplyFireToWorkflow[wf_Association, trans_Association,
                     consumedTokens_List, producedTokens_List,
                     executorResult_Association] :=
  Module[{newWf, consumedIds, finalReached},
    newWf       = wf;
    consumedIds = Map[#[["TokenId"]] &, consumedTokens];
    
    (* 1. Consumed tokens を input places から削除 *)
    Scan[
      Function[arc,
        With[{p = arc[["Place"]]},
          newWf = ReplacePart[newWf,
            {"Places", p, "TokenIds"} ->
              DeleteCases[
                newWf[["Places", p, "TokenIds"]],
                Alternatives @@ consumedIds]
          ]
        ]
      ],
      trans[["InputArcs"]]
    ];
    
    (* 2. Token registry から consumed を削除 *)
    newWf = ReplacePart[newWf,
      "Tokens" -> KeyDrop[newWf[["Tokens"]], consumedIds]
    ];
    
    (* 3. Produced tokens を output places に追加、registry にも追加 *)
    (* IMPORTANT: ReplacePart は Association の新規キー追加を反映しないため、
                  Tokens registry への新規 token 追加には Append を使う。
                  Places の TokenIds (existing key path) は ReplacePart で OK。*)
    MapIndexed[
      Function[{arc, idx},
        With[{p = arc[["Place"]],
              tok = producedTokens[[idx[[1]]]]},
          
          (* Places の TokenIds: existing path *)
          newWf = ReplacePart[newWf,
            {"Places", p, "TokenIds"} ->
              Append[newWf[["Places", p, "TokenIds"]], tok[["TokenId"]]]];
          
          (* Tokens registry: 新規キー追加 -> Append で *)
          newWf = ReplacePart[newWf,
            "Tokens" -> Append[newWf[["Tokens"]], tok[["TokenId"]] -> tok]]
        ]
      ],
      trans[["OutputArcs"]]
    ];
    
    (* 4. Trace 追加 *)
    newWf = ReplacePart[newWf,
      "Trace" -> Append[newWf[["Trace"]],
        <|"Event"           -> "TransitionFired",
          "TransitionName"  -> trans[["Name"]],
          "ConsumedIds"     -> consumedIds,
          "ProducedIds"     -> Map[#[["TokenId"]] &, producedTokens],
          "ExecutorStatus"  -> Lookup[executorResult, "Status", "Unknown"],
          "Timestamp"       -> iCurrentTime[]|>]];
    
    (* 5. Final places 到達チェック *)
    finalReached = AnyTrue[wf[["FinalPlaces"]],
      Length[newWf[["Places", #, "TokenIds"]]] > 0 &];
    
    If[finalReached,
      newWf = ReplacePart[newWf, "Status" -> "Done"]
    ];
    
    newWf
  ];

(* ::Subsubsection:: *)
(* Z\:6848 (2026-05-16) Awaiting-LLM helper \:7fa4 *)

(* iConsumeTokensForAwaiting: input \:30c8\:30fc\:30af\:30f3\:306e\:307f consume \:3057\:3001
   output \:306f produce \:3057\:306a\:3044\:3002Trace \:8ffd\:52a0\:3082\:3053\:3053\:3067\:306f\:3057\:306a\:3044
   (\:547c\:3076\:5074\:304c TransitionAwaiting \:3092\:8ffd\:8a18\:3059\:308b)\:3002 *)
iConsumeTokensForAwaiting[wf_Association, trans_Association,
                          consumedTokens_List] :=
  Module[{newWf, consumedIds},
    newWf       = wf;
    consumedIds = Map[#[["TokenId"]] &, consumedTokens];

    (* 1. Consumed tokens を input places から削除 *)
    Scan[
      Function[arc,
        With[{p = arc[["Place"]]},
          newWf = ReplacePart[newWf,
            {"Places", p, "TokenIds"} ->
              DeleteCases[
                newWf[["Places", p, "TokenIds"]],
                Alternatives @@ consumedIds]
          ]
        ]
      ],
      trans[["InputArcs"]]
    ];

    (* 2. Token registry から consumed を削除 *)
    newWf = ReplacePart[newWf,
      "Tokens" -> KeyDrop[newWf[["Tokens"]], consumedIds]
    ];

    newWf
  ];

(* iApplyCompletedHandlerOutput: AwaitingLLMTransitions \:30a8\:30f3\:30c8\:30ea\:304b\:3089
   produce \:30d5\:30a7\:30fc\:30ba\:3092\:5b8c\:4e86\:3055\:305b\:308b helper\:3002
   wf \:306b\:5bfe\:3057 (place TokenIds \:306b\:8ffd\:52a0, Tokens registry \:306b\:8ffd\:52a0,
   AwaitingLLMTransitions \:304b\:3089\:8a72\:5f53 entry \:3092\:524a\:9664, Trace \:306b
   TransitionCompleted \:3092\:8ffd\:8a18, Final places \:5230\:9054\:30c1\:30a7\:30c3\:30af) \:3092\:9069\:7528\:3057\:305f
   \:65b0\:3057\:3044 wf \:3092\:8fd4\:3059\:3002\:4f75\:305b\:3066 producedTokens \:3092\:8fd4\:3059\:3002 *)
iApplyCompletedHandlerOutput[wf_Association, trans_Association,
                             awaitId_String, finalOutput_Association] :=
  Module[{newWf, awaiting, binding, producedTokens, parentIds, finalReached,
          synthetic, outputArcs, basePayload, payloadFromOutput},
    newWf    = iEnsureAwaitingLLMField[wf];
    awaiting = Lookup[newWf[["AwaitingLLMTransitions"]], awaitId,
                       Missing["NoSuchAwaiting"]];

    If[MissingQ[awaiting],
      Return[<|"Status" -> "NotFound", "AwaitId" -> awaitId|>]
    ];

    binding    = Lookup[awaiting, "Binding", <||>];
    parentIds  = Lookup[awaiting, "ConsumedIds", {}];
    outputArcs = Lookup[trans, "OutputArcs", {}];

    (* finalOutput \:306f Association\:3002 "Payload" \:30ad\:30fc\:304c\:3042\:308c\:3070\:305d\:308c\:3092
       Payload \:3068\:3057\:3066\:4f7f\:3046\:3002\:306a\:3051\:308c\:3070 finalOutput \:81ea\:4f53\:3092 Payload \:6271\:3044\:3002 *)
    basePayload = Which[
      KeyExistsQ[finalOutput, "Payload"] &&
        AssociationQ[finalOutput[["Payload"]]],
        finalOutput[["Payload"]],
      AssociationQ[finalOutput],
        finalOutput,
      True,
        <||>
    ];

    (* synthetic executorResult \:3092 iProduceOutputTokens \:7d4c\:7531\:3067\:6e21\:3057
       \:30d1\:30b9\:3092\:63c3\:3048\:308b\:3002 *)
    synthetic = <|"Status" -> "Completed", "Output" ->
      <|"Payload" -> basePayload|>|>;

    producedTokens = iProduceOutputTokens[trans, binding, synthetic];

    (* Produced tokens \:3092 output places + Tokens registry \:306b\:8ffd\:52a0\:3002
       iApplyFireToWorkflow \:3068\:540c\:3058\:30d1\:30bf\:30fc\:30f3\:3060\:304c input consume \:306f
       \:3057\:306a\:3044 (\:3059\:3067\:306b Awaiting branch \:3067\:6e08)\:3002 *)
    MapIndexed[
      Function[{arc, idx},
        With[{p = arc[["Place"]], tok = producedTokens[[idx[[1]]]]},
          newWf = ReplacePart[newWf,
            {"Places", p, "TokenIds"} ->
              Append[newWf[["Places", p, "TokenIds"]], tok[["TokenId"]]]];
          newWf = ReplacePart[newWf,
            "Tokens" ->
              Append[newWf[["Tokens"]], tok[["TokenId"]] -> tok]]
        ]
      ],
      outputArcs
    ];

    (* AwaitingLLMTransitions \:304b\:3089\:8a72\:5f53 entry \:3092\:524a\:9664 *)
    newWf = ReplacePart[newWf,
      "AwaitingLLMTransitions" ->
        KeyDrop[newWf[["AwaitingLLMTransitions"]], awaitId]];

    (* Trace event TransitionCompleted *)
    newWf = ReplacePart[newWf,
      "Trace" -> Append[newWf[["Trace"]],
        <|"Event"           -> "TransitionCompleted",
          "TransitionName"  -> trans[["Name"]],
          "AwaitId"         -> awaitId,
          "ConsumedIds"     -> parentIds,
          "ProducedIds"     -> Map[#[["TokenId"]] &, producedTokens],
          "DurationSec"     ->
            iCurrentTime[] - Lookup[awaiting, "StartTime", iCurrentTime[]],
          "Timestamp"       -> iCurrentTime[]|>]];

    (* Final places 到達チェック *)
    finalReached = AnyTrue[wf[["FinalPlaces"]],
      Length[newWf[["Places", #, "TokenIds"]]] > 0 &];
    If[finalReached,
      newWf = ReplacePart[newWf, "Status" -> "Done"]];

    <|"NewWf"           -> newWf,
      "ProducedTokens"  -> producedTokens,
      "TransitionName"  -> trans[["Name"]],
      "FinalReached"    -> finalReached|>
  ];

(* ::Subsubsection:: *)
(* ClaudeCompleteHandlerOutput (Public) *)

ClaudeCompleteHandlerOutput[wid_String, awaitId_String,
                            output_Association] :=
  Module[{wf, awaiting, trans, transName, applied, newWf, marking,
          asyncInfo, asyncCompleted = False},

    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[<|"Status"     -> "NotFound",
               "WorkflowId" -> wid,
               "Reason"     -> "WorkflowNotFound"|>]
    ];

    wf       = iEnsureAwaitingLLMField[$iWorkflowNets[wid]];
    awaiting = Lookup[wf[["AwaitingLLMTransitions"]], awaitId,
                       Missing["NoSuchAwaiting"]];

    (* \:8a72\:5f53\:30a8\:30f3\:30c8\:30ea\:304c\:7121\:3044 (Cancel \:6e08\:307f\:307e\:305f\:306f\:5b8c\:4e86\:6e08\:307f) \:306a\:3089
       silent discard\:3002Trace \:306b\:306f\:4e00\:5fdc\:8a18\:9332\:3057\:3066\:304a\:304f\:3002 *)
    If[MissingQ[awaiting],
      newWf = ReplacePart[wf,
        "Trace" -> Append[wf[["Trace"]],
          <|"Event"      -> "TransitionCallbackDiscarded",
            "AwaitId"    -> awaitId,
            "Reason"     -> "NoSuchAwaiting",
            "Timestamp"  -> iCurrentTime[]|>]];
      AssociateTo[$iWorkflowNets, wid -> newWf];
      Return[<|"Status"     -> "Discarded",
               "WorkflowId" -> wid,
               "AwaitId"    -> awaitId,
               "Reason"     -> "NoSuchAwaiting"|>]
    ];

    transName = Lookup[awaiting, "TransitionName", "?"];
    trans     = Lookup[wf[["Transitions"]], transName, None];

    If[trans === None,
      newWf = ReplacePart[wf,
        "AwaitingLLMTransitions" ->
          KeyDrop[wf[["AwaitingLLMTransitions"]], awaitId]];
      newWf = ReplacePart[newWf,
        "Trace" -> Append[newWf[["Trace"]],
          <|"Event"     -> "TransitionCallbackDiscarded",
            "AwaitId"   -> awaitId,
            "TransitionName" -> transName,
            "Reason"    -> "TransitionDisappeared",
            "Timestamp" -> iCurrentTime[]|>]];
      AssociateTo[$iWorkflowNets, wid -> newWf];
      Return[<|"Status"     -> "Discarded",
               "WorkflowId" -> wid,
               "AwaitId"    -> awaitId,
               "Reason"     -> "TransitionDisappeared"|>]
    ];

    (* Workflow Status \:30c1\:30a7\:30c3\:30af: Cancelled / Done \:306e\:5834\:5408\:306f
       silent discard\:3001\:4f46\:3057 entry \:3092\:30af\:30ea\:30a2 *)
    If[MemberQ[{"Cancelled"}, wf[["Status"]]],
      newWf = ReplacePart[wf,
        "AwaitingLLMTransitions" ->
          KeyDrop[wf[["AwaitingLLMTransitions"]], awaitId]];
      newWf = ReplacePart[newWf,
        "Trace" -> Append[newWf[["Trace"]],
          <|"Event"     -> "TransitionCallbackDiscarded",
            "AwaitId"   -> awaitId,
            "TransitionName" -> transName,
            "Reason"    -> "WorkflowCancelled",
            "Timestamp" -> iCurrentTime[]|>]];
      AssociateTo[$iWorkflowNets, wid -> newWf];
      Return[<|"Status"     -> "Discarded",
               "WorkflowId" -> wid,
               "AwaitId"    -> awaitId,
               "Reason"     -> "WorkflowCancelled"|>]
    ];

    (* \:6700\:5f8c\:306e\:4ef6: \:5e38\:8ecc\:306e produce \:3092\:9069\:7528 *)
    applied = iApplyCompletedHandlerOutput[wf, trans, awaitId, output];

    If[!AssociationQ[applied] || !KeyExistsQ[applied, "NewWf"],
      Return[<|"Status"     -> "Discarded",
               "WorkflowId" -> wid,
               "AwaitId"    -> awaitId,
               "Reason"     -> "ApplyFailed"|>]
    ];

    newWf = applied[["NewWf"]];
    AssociateTo[$iWorkflowNets, wid -> newWf];

    marking = iComputeCurrentMarking[wid];

    (* Async \:30b8\:30e7\:30d6\:304c\:8d70\:3063\:3066\:3044\:3066 final place \:306b\:5230\:9054\:3057\:305f\:306a\:3089\:3001
       \:3053\:3053\:3067\:5b8c\:4e86\:30de\:30fc\:30af\:3092\:4ed8\:3051\:308b (\:6b21\:306e tick \:3092\:5f85\:305f\:305a\:306b)\:3002
       Stuck \:3060\:3063\:305f\:5834\:5408\:306e\:51e6\:7406\:306f tick \:5074\:306b\:4efb\:305b\:308b\:3002 *)
    If[applied[["FinalReached"]] &&
       KeyExistsQ[$iWorkflowAsyncJobs, wid] &&
       Lookup[$iWorkflowAsyncJobs[wid], "Status", "Completed"] =!= "Completed",
      iMarkAsyncCompleted[wid, "ReachedFinalPlace"];
      asyncCompleted = True
    ];

    <|"Status"          -> "Completed",
      "WorkflowId"      -> wid,
      "AwaitId"         -> awaitId,
      "TransitionName"  -> transName,
      "ProducedTokens"  -> Map[#[["TokenId"]] &, applied[["ProducedTokens"]]],
      "FinalReached"    -> applied[["FinalReached"]],
      "AsyncCompleted"  -> asyncCompleted,
      "Marking"         -> marking|>
  ];

(* ::Subsubsection:: *)
(* ClaudeAwaitingTransitions (Public) *)

ClaudeAwaitingTransitions[wid_String] :=
  Module[{wf, awaiting, rows, now},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[Dataset[{}]]
    ];
    wf = iEnsureAwaitingLLMField[$iWorkflowNets[wid]];
    awaiting = Lookup[wf, "AwaitingLLMTransitions", <||>];
    now      = iCurrentTime[];

    rows = KeyValueMap[
      Function[{aid, entry},
        <|"AwaitId"         -> aid,
          "TransitionName"  -> Lookup[entry, "TransitionName", "?"],
          "StartTime"       -> Lookup[entry, "StartTime", Missing[]],
          "ElapsedSec"      -> now - Lookup[entry, "StartTime", now],
          "ConsumedIds"     -> Lookup[entry, "ConsumedIds", {}]|>
      ],
      awaiting
    ];

    Dataset[rows]
  ];

(* ::Subsubsection:: *)
(* ClaudeStepWorkflow *)

Options[ClaudeStepWorkflow] = Options[ClaudeFireTransition];

ClaudeStepWorkflow[wid_String, opts:OptionsPattern[]] :=
  Module[{wf, enabled, chosen, result},
    
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[<|"Status" -> "NotFound", "WorkflowId" -> wid|>]
    ];
    
    wf = $iWorkflowNets[wid];
    
    (* Workflow Status check (Paused / Cancelled / Done なら enabled を計算しない) *)
    If[MemberQ[{"Paused", "Cancelled", "Done"}, wf[["Status"]]],
      Return[<|"Status"         -> "Skipped",
               "Reason"         -> "WorkflowNotRunnable: " <> wf[["Status"]],
               "WorkflowStatus" -> wf[["Status"]]|>]
    ];
    
    enabled = ClaudeEnabledTransitions[wid];
    
    If[Length[enabled] === 0,
      Return[<|"Status" -> "Stuck", "Reason" -> "NoEnabledTransitions"|>]
    ];
    
    (* Priority 降順でソート済み、先頭を選ぶ *)
    chosen = First[enabled];
    
    result = ClaudeFireTransition[
      wid, chosen[["Name"]], chosen[["Binding"]], opts];
    
    Append[result, "ChosenTransition" -> chosen[["Name"]]]
  ];

(* ::Subsubsection:: *)
(* ClaudeRunWorkflow (sync + async, Day 4a) *)

Options[ClaudeRunWorkflow] = Join[
  Options[ClaudeStepWorkflow],
  {"MaxSteps" -> 1000,
   "MaxWait"  -> Quantity[600, "Seconds"],
   "Async"    -> False}
];

ClaudeRunWorkflow[wid_String, opts:OptionsPattern[]] :=
  If[TrueQ[OptionValue["Async"]],
    iRunWorkflowAsync[wid, opts],
    iRunWorkflowSync[wid, opts]
  ];

(* === Sync 実装 (Day 2 から維持) === *)

iRunWorkflowSync[wid_String, opts:OptionsPattern[ClaudeRunWorkflow]] :=
  Module[{maxSteps, maxWaitSec, startTime, steps, stepResult, status,
          terminationReason, traceLog},
    
    maxSteps   = OptionValue[ClaudeRunWorkflow, {opts}, "MaxSteps"];
    maxWaitSec = QuantityMagnitude @
                 UnitConvert[
                   OptionValue[ClaudeRunWorkflow, {opts}, "MaxWait"],
                   "Seconds"];
    startTime  = iCurrentTime[];
    steps      = 0;
    traceLog   = {};
    terminationReason = "MaxStepsReached";
    
    Catch[
      While[steps < maxSteps,
        
        (* timeout チェック *)
        If[iCurrentTime[] - startTime >= maxWaitSec,
          terminationReason = "Timeout";
          Throw["TimeoutBreak"]
        ];
        
        stepResult = ClaudeStepWorkflow[wid,
          FilterRules[{opts}, Options[ClaudeStepWorkflow]]];
        steps++;
        
        AppendTo[traceLog, <|
          "Step"   -> steps,
          "Status" -> stepResult[["Status"]],
          "Trans"  -> Lookup[stepResult, "ChosenTransition", Missing[]]
        |>];
        
        (* step 結果による終了判定。
           "HandlerFailed" は終了判定にしない (= continue)。理由は
           iWorkflowAsyncTick と同じ: 失敗カウンタは ClaudeFireTransition で
           ++ 済みで、上限到達済みなら ClaudeEnabledTransitions が次 step で
           除外し、他に enabled が無ければ次 step が "Stuck" になる。
           Z\:6848 (2026-05-16): "Stuck" \:5224\:5b9a\:6642\:306b AwaitingLLMTransitions \:304c
           \:6b8b\:3063\:3066\:3044\:308b\:306a\:3089 callback \:3092\:5f85\:3064\:3002Pause[0.2] \:3057\:3066\:30eb\:30fc\:30d7\:3092\:7d99\:7d9a\:3002 *)
        Switch[stepResult[["Status"]],
          "Stuck",
            Module[{wfNow, hasAw},
              wfNow = If[KeyExistsQ[$iWorkflowNets, wid],
                iEnsureAwaitingLLMField[$iWorkflowNets[wid]], <||>];
              hasAw = AssociationQ[wfNow] &&
                Length[Lookup[wfNow, "AwaitingLLMTransitions", <||>]] > 0;
              If[hasAw,
                (* callback \:5230\:7740\:3092\:5f85\:3064 idle wait *)
                Pause[0.2],
                terminationReason = "Stuck";
                Throw["StuckBreak"]
              ]
            ],
          "Failed",
            terminationReason = "Failed";
            Throw["FailedBreak"],
          "NeedsApproval",
            terminationReason = "NeedsApproval";
            Throw["ApprovalBreak"],
          "Blocked",
            terminationReason = "Blocked";
            Throw["BlockedBreak"],
          "Skipped",
            terminationReason = "Skipped";
            Throw["SkippedBreak"],
          "Awaiting",
            (* fire \:6210\:529f\:3060\:304c\:5b8c\:4e86\:5f85\:3061\:3002\:30eb\:30fc\:30d7\:3092\:7d99\:7d9a\:3057\:3066\:4ed6\:306e enabled \:3092\n               \:53d6\:308a\:306b\:884c\:304f\:3002\:4ed6\:304c\:7121\:304f Stuck \:306b\:306a\:308c\:3070\:4e0a\:8a18 hasAw \:3067\:5f85\:6a5f\:3002 *)
            Null
        ];
        
        (* Done になっていればループ抜ける *)
        status = ClaudeWorkflowStatus[wid];
        If[status[["Status"]] === "Done",
          terminationReason = "ReachedFinalPlace";
          Throw["DoneBreak"]
        ]
      ]
    ];
    
    status = ClaudeWorkflowStatus[wid];
    
    Module[{result, finalMarking},
      finalMarking = iComputeCurrentMarking[wid];
      result = <|"WorkflowId"        -> wid,
        "Status"             -> status[["Status"]],
        "TerminationReason"  -> terminationReason,
        "Steps"              -> steps,
        "ElapsedSec"         -> iCurrentTime[] - startTime,
        "FinalMarking"       -> finalMarking,
        "StepLog"            -> traceLog|>;
      
      (* completion hooks 発火 (Week 2c-2c) *)
      iFireCompletionHooks[wid, <|
        "WorkflowId"        -> wid,
        "Status"            -> status[["Status"]],
        "TerminationReason" -> terminationReason,
        "Mode"              -> "Sync",
        "ElapsedSec"        -> iCurrentTime[] - startTime,
        "Steps"             -> steps,
        "FinalMarking"      -> finalMarking,
        "EndTime"           -> iCurrentTime[]
      |>];
      
      result
    ]
  ];

(* === Async 実装 (Day 4a 新規) ===
   $claudeProgress に寄生して 1 tick で 1 step 進める。Pause/Cancel は
   workflow の Status を見てそれぞれ「skip」「cleanup」する。
   完了で entry を Status -> "Completed" にして $claudeProgress からは
   外す。完全な entry の cleanup は次の tick または ClaudeWaitWorkflow が行う。 *)

iRunWorkflowAsync[wid_String, opts:OptionsPattern[ClaudeRunWorkflow]] :=
  Module[{maxSteps, maxWaitSec, forceAllow, info},
    
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    
    (* 既に async ジョブが走っていたら拒否 *)
    If[KeyExistsQ[$iWorkflowAsyncJobs, wid] &&
       Lookup[$iWorkflowAsyncJobs[wid], "Status", "Completed"] =!= "Completed",
      Return[<|"WorkflowId" -> wid,
               "Status"     -> "AlreadyAsyncRunning",
               "Reason"     -> "previous async job still running",
               "AsyncJob"   -> $iWorkflowAsyncJobs[wid]|>]
    ];
    
    maxSteps   = OptionValue[ClaudeRunWorkflow, {opts}, "MaxSteps"];
    maxWaitSec = QuantityMagnitude @
                 UnitConvert[
                   OptionValue[ClaudeRunWorkflow, {opts}, "MaxWait"],
                   "Seconds"];
    forceAllow = TrueQ @ OptionValue[ClaudeRunWorkflow, {opts}, "ForceAllow"];
    
    info = <|
      "WorkflowId"        -> wid,
      "Status"            -> "Running",
      "StartTime"         -> iCurrentTime[],
      "EndTime"           -> Missing[],
      "MaxSteps"          -> maxSteps,
      "MaxWaitSec"        -> maxWaitSec,
      "ForceAllow"        -> forceAllow,
      "Steps"             -> 0,
      "StepLog"           -> {},
      "LastStepResult"    -> Missing[],
      "TerminationReason" -> Missing[]
    |>;
    
    AssociateTo[$iWorkflowAsyncJobs, wid -> info];
    
    iRegisterAsyncWorkflowTick[wid];
    
    <|"WorkflowId" -> wid,
      "Status"     -> "Async-Started",
      "PollKey"    -> iAsyncPollKey[wid],
      "StartTime"  -> info[["StartTime"]]|>
  ];

(* ::Subsubsection:: *)
(* Async tick / lifecycle helpers *)

iAsyncPollKey[wid_String] := "wf-async-" <> wid;

(* ClaudeCode の Public API 経由で polling tick を登録/解除する。
   Day 4a までは ClaudeCode`Private`$claudeProgress に直接書き込んで
   いたが、Day 4b で Public API への移行を完了。 *)
iRegisterAsyncWorkflowTick[wid_String] :=
  Module[{key, tickFn},
    key    = iAsyncPollKey[wid];
    tickFn = Function[{}, iWorkflowAsyncTick[wid]];
    ClaudeCode`ClaudeRegisterPollingTick[key, tickFn,
      "Phase"  -> "wf-async",
      "Caller" -> "Workflow"];
  ];

iUnregisterAsyncWorkflowTick[wid_String] :=
  ClaudeCode`ClaudeUnregisterPollingTick[iAsyncPollKey[wid]];

(* async job entry を完全に消し去る。手動 GC API。
   Public 公開: ClaudeCleanupAsyncJob[wid] と等価。
   Cancel / NotFound / 完了直後の cleanup でも使える。 *)
ClaudeCleanupAsyncJob[wid_String] :=
  Module[{found},
    iUnregisterAsyncWorkflowTick[wid];
    found = KeyExistsQ[$iWorkflowAsyncJobs, wid];
    If[found,
      $iWorkflowAsyncJobs = KeyDrop[$iWorkflowAsyncJobs, wid];
      <|"Status" -> "Cleaned", "WorkflowId" -> wid|>,
      <|"Status" -> "NotFound", "WorkflowId" -> wid|>
    ]
  ];

(* 内部別名 (互換性のため残す) *)
iCleanupAsyncJob[wid_String] := ClaudeCleanupAsyncJob[wid];

(* async job を「完了」状態に遷移させる。
   entry は $iWorkflowAsyncJobs に残し、ClaudeAsyncJobInfo / ClaudeWaitWorkflow
   から TerminationReason を読めるようにする。
   $claudeProgress からは外して polling tick から外す。
   Week 2c-2c: completion hooks も発火する。 *)
iMarkAsyncCompleted[wid_String, reason_String] :=
  Module[{info, finalMarking, wfStatus, completionInfo, startTime},
    iUnregisterAsyncWorkflowTick[wid];
    
    If[!KeyExistsQ[$iWorkflowAsyncJobs, wid], Return[]];
    
    info = $iWorkflowAsyncJobs[wid];
    AssociateTo[$iWorkflowAsyncJobs,
      wid -> Append[info, <|
        "Status"            -> "Completed",
        "TerminationReason" -> reason,
        "EndTime"           -> iCurrentTime[]
      |>]
    ];
    
    (* completion hooks 発火 (Week 2c-2c) *)
    startTime    = Lookup[info, "StartTime", iCurrentTime[]];
    finalMarking = If[KeyExistsQ[$iWorkflowNets, wid],
      iComputeCurrentMarking[wid], <||>];
    wfStatus     = If[KeyExistsQ[$iWorkflowNets, wid],
      Lookup[ClaudeWorkflowStatus[wid], "Status", "?"],
      "Unknown"];
    completionInfo = <|
      "WorkflowId"        -> wid,
      "Status"            -> wfStatus,
      "TerminationReason" -> reason,
      "Mode"              -> "Async",
      "ElapsedSec"        -> iCurrentTime[] - startTime,
      "Steps"             -> Lookup[info, "Steps", 0],
      "FinalMarking"      -> finalMarking,
      "EndTime"           -> iCurrentTime[]
    |>;
    iFireCompletionHooks[wid, completionInfo];
  ];

(* ::Subsubsection:: *)
(* Completion hooks (Week 2c-2c) *)

(* iFireCompletionHooks: 一回限り発火。発火と同時に当該 wid の hooks を
   消去して再入を防ぐ。各 hook 内の例外は Quiet @ Check で隔離する。 *)
iFireCompletionHooks[wid_String, completionInfo_Association] :=
  Module[{hooks},
    hooks = Lookup[$iWorkflowCompletionHooks, wid, {}];
    If[Length[hooks] === 0, Return[]];
    
    (* 再入防止: 発火前に hooks を消去 *)
    KeyDropFrom[$iWorkflowCompletionHooks, wid];
    
    (* 各 hook を順次発火 *)
    Do[
      Quiet @ Check[hook[completionInfo], Null],
      {hook, hooks}
    ];
  ];

(* Public API: ClaudeRegisterCompletionHook *)

ClaudeRegisterCompletionHook[wid_String, fn_] :=
  Module[{existing, status, finalMarking, completionInfo,
          alreadyDoneStatus},
    
    (* workflow が既に完了済みかチェック (Done/Cancelled/Failed) *)
    If[KeyExistsQ[$iWorkflowNets, wid],
      status = Lookup[ClaudeWorkflowStatus[wid], "Status", "?"];
      alreadyDoneStatus = MemberQ[
        {"Done", "Cancelled", "Failed"}, status];
      
      If[alreadyDoneStatus,
        finalMarking = iComputeCurrentMarking[wid];
        completionInfo = <|
          "WorkflowId"        -> wid,
          "Status"            -> status,
          "TerminationReason" -> Switch[status,
            "Done",      "ReachedFinalPlace",
            "Cancelled", "Cancelled",
            "Failed",    "Failed",
            _,           status],
          "Mode"              -> "Immediate",
          "ElapsedSec"        -> 0,
          "Steps"             -> 0,
          "FinalMarking"      -> finalMarking,
          "EndTime"           -> iCurrentTime[]
        |>;
        Quiet @ Check[fn[completionInfo], Null];
        Return[<|
          "WorkflowId"       -> wid,
          "HookCount"        -> 0,
          "FiredImmediately" -> True
        |>]
      ]
    ];
    
    (* 通常登録 *)
    existing = Lookup[$iWorkflowCompletionHooks, wid, {}];
    AssociateTo[$iWorkflowCompletionHooks,
      wid -> Append[existing, fn]];
    
    <|
      "WorkflowId"       -> wid,
      "HookCount"        -> Length[existing] + 1,
      "FiredImmediately" -> False
    |>
  ];

(* Public API: ClaudeUnregisterCompletionHooks *)

ClaudeUnregisterCompletionHooks[wid_String] :=
  Module[{count},
    count = Length[Lookup[$iWorkflowCompletionHooks, wid, {}]];
    KeyDropFrom[$iWorkflowCompletionHooks, wid];
    <|
      "WorkflowId" -> wid,
      "Removed"    -> count
    |>
  ];

(* polling tick で 1 回呼ばれる本体。1 tick = 1 step (Pause 中は何もしない) *)
iWorkflowAsyncTick[wid_String] :=
  Module[{wf, info, stepResult, status},
    
    (* entry が消えていたらクリーンアップ *)
    If[!KeyExistsQ[$iWorkflowAsyncJobs, wid],
      iUnregisterAsyncWorkflowTick[wid];
      Return[]
    ];
    
    info = $iWorkflowAsyncJobs[wid];
    
    (* 既に completed のものは tick から外す *)
    If[Lookup[info, "Status", "Running"] === "Completed",
      iUnregisterAsyncWorkflowTick[wid];
      Return[]
    ];
    
    (* workflow 自体が消えていたら abandoned 完了 *)
    If[!KeyExistsQ[$iWorkflowNets, wid],
      iMarkAsyncCompleted[wid, "WorkflowDisappeared"];
      Return[]
    ];
    
    wf = $iWorkflowNets[wid];
    
    (* workflow Status による分岐:
       - Cancelled / Done: 完了
       - Paused: tick はスキップ (継続待機)、Resume されるか
                 Cancel されるまで何もしない *)
    Switch[wf[["Status"]],
      "Cancelled", iMarkAsyncCompleted[wid, "Cancelled"]; Return[],
      "Done",      iMarkAsyncCompleted[wid, "ReachedFinalPlace"]; Return[],
      "Paused",    Return[]
    ];
    
    (* timeout / max steps チェック (step 実行前) *)
    If[(iCurrentTime[] - info[["StartTime"]]) >= info[["MaxWaitSec"]],
      iMarkAsyncCompleted[wid, "Timeout"];
      Return[]
    ];
    If[info[["Steps"]] >= info[["MaxSteps"]],
      iMarkAsyncCompleted[wid, "MaxStepsReached"];
      Return[]
    ];
    
    (* 1 step fire (例外は Quiet @ Check で捕まえる) *)
    stepResult = Quiet @ Check[
      ClaudeStepWorkflow[wid, "ForceAllow" -> info[["ForceAllow"]]],
      <|"Status" -> "Failed", "Reason" -> "ExceptionInTick"|>
    ];
    
    (* info を更新 *)
    AssociateTo[$iWorkflowAsyncJobs, wid -> Append[info, <|
      "Steps"          -> info[["Steps"]] + 1,
      "LastStepResult" -> stepResult,
      "StepLog"        -> Append[info[["StepLog"]], <|
        "Step"      -> info[["Steps"]] + 1,
        "Status"    -> Lookup[stepResult, "Status", "?"],
        "Trans"     -> Lookup[stepResult, "ChosenTransition", Missing[]],
        "Timestamp" -> iCurrentTime[]
      |>]
    |>]];
    
    (* step 結果による終了判定。
       "HandlerFailed" は終了判定にしない (= continue) — その transition の
       attempts は ClaudeFireTransition 内で ++ 済みで、上限到達済みなら
       ClaudeEnabledTransitions が次 tick で除外し、他に enabled が無ければ
       次 tick が "Stuck" になる。retry 余力があるか、別の transition が
       enabled なら次 tick で継続する。
       Z\:6848 (2026-05-16): "Stuck" \:3060\:3063\:305f\:5834\:5408\:3001AwaitingLLMTransitions \:304c
       \:6b8b\:3063\:3066\:3044\:308c\:3070\:300c\:672c\:5f53\:306b\:8a70\:307e\:3063\:305f\:300d\:3068\:306f\:8a00\:3048\:305a\:3001callback \:5230\:7740\:3092\:5f85\:3064 idle \:3068\n       \:305b\:3088\:3002\:3088\:3063\:3066 Stuck \:3092 Complete \:306b\:5909\:3048\:305a\:3001\:6b21 tick \:3092\:5f85\:3064 (Return)\:3002 *)
    Module[{stepStatus, wfAfter, hasAwaiting},
      stepStatus  = Lookup[stepResult, "Status", "?"];
      wfAfter     = If[KeyExistsQ[$iWorkflowNets, wid],
        iEnsureAwaitingLLMField[$iWorkflowNets[wid]], <||>];
      hasAwaiting = AssociationQ[wfAfter] &&
        Length[Lookup[wfAfter, "AwaitingLLMTransitions", <||>]] > 0;

      Switch[stepStatus,
        "Stuck",
          If[hasAwaiting,
            (* idle wait: callback \:5230\:7740\:307e\:3067\:6b21 tick \:3082 skip *)
            Return[],
            iMarkAsyncCompleted[wid, "Stuck"]; Return[]
          ],
        "Failed",        iMarkAsyncCompleted[wid, "Failed"]; Return[],
        "NeedsApproval", iMarkAsyncCompleted[wid, "NeedsApproval"]; Return[],
        "Blocked",       iMarkAsyncCompleted[wid, "Blocked"]; Return[],
        "Awaiting",      Null   (* \:6b21 tick \:3082 fire \:53ef\:80fd\:3001\:305d\:306e\:307e\:307e\:9032\:3080 *)
      ];
    ];
    
    (* fire 後に Done になったか *)
    status = ClaudeWorkflowStatus[wid];
    If[Lookup[status, "Status", "?"] === "Done",
      iMarkAsyncCompleted[wid, "ReachedFinalPlace"];
      Return[]
    ];
  ];

(* ::Subsubsection:: *)
(* ClaudeWaitWorkflow / ClaudeAsyncJobInfo *)

Options[ClaudeWaitWorkflow] = {
  "PollInterval" -> Quantity[0.5, "Seconds"],
  "MaxWait"      -> Quantity[600, "Seconds"]
};

ClaudeWaitWorkflow[wid_String, opts:OptionsPattern[]] :=
  Module[{intervalSec, maxWaitSec, startTime, completed, finalInfo,
          finalStatus, finalMarking, fineGrainStep, microStepCount},
    
    intervalSec = QuantityMagnitude @
                  UnitConvert[OptionValue["PollInterval"], "Seconds"];
    maxWaitSec  = QuantityMagnitude @
                  UnitConvert[OptionValue["MaxWait"], "Seconds"];
    startTime   = iCurrentTime[];
    completed   = False;
    
    (* Stage 1.7 (2026-05-17): \:7d30\:5208\:307f Pause + SessionSubmit slot \:5316\:3002
       rule 95-D \:6e96\:62e0: Wolfram \:306e Pause \:306f\:30ab\:30fc\:30cd\:30eb\:8a55\:4fa1\:3092\:30b9\:30ea\:30fc\:30d7\:3055\:305b\:308b\:3060\:3051\:3067\:3001
       \:30d5\:30ed\:30f3\:30c8\:30a8\:30f3\:30c9\:30e1\:30c3\:30bb\:30fc\:30b8\:30eb\:30fc\:30d7\:3068 SessionSubmit \:30ad\:30e5\:30fc\:306f Pause \:5883\:754c\:3067
       \:6700\:5927 1 \:30b9\:30ed\:30c3\:30c8\:3057\:304b\:6d88\:5316\:3055\:308c\:306a\:3044\:3002\:5f93\:3063\:3066 Pause[3] \:30921\:56de\:547c\:3076\:3088\:308a\:3001
       Pause[0.05] \:309260\:56de\:7e70\:308a\:8fd4\:3057\:305f\:65b9\:304c\:3001handler \:306e\:975e\:540c\:671f LLM \:547c\:3073\:51fa\:3057\:304c
       \:751f\:6210\:3059\:308b SessionSubmit \:30b9\:30bf\:30c3\:30af\:3092\:6d88\:5316\:3067\:304d\:308b\:3002 *)
    fineGrainStep  = 0.05;
    microStepCount = Max[Round[intervalSec / fineGrainStep], 1];
    
    While[!completed && (iCurrentTime[] - startTime) < maxWaitSec,
      (* \:7d30\:5208\:307f Pause \:30eb\:30fc\:30d7\:3002\:5404 Pause \:5883\:754c\:3067 SessionSubmit \:3092 1 \:30b9\:30ed\:30c3\:30c8\:3060\:3051\:6d88\:5316\:3067\:304d\:308b\:3002 *)
      Do[
        Pause[fineGrainStep];
        (* \:5404 microstep \:3067\:5b8c\:4e86\:30c1\:30a7\:30c3\:30af *)
        Which[
          !KeyExistsQ[$iWorkflowAsyncJobs, wid],
            completed = True; Break[],
          Lookup[$iWorkflowAsyncJobs[wid], "Status", "Running"] === "Completed",
            completed = True; Break[]
        ],
        {microStepCount}
      ];
      
      (* MaxWait \:30c1\:30a7\:30c3\:30af\:306f\:5916\:5074\:30eb\:30fc\:30d7\:3067 *)
      If[(iCurrentTime[] - startTime) >= maxWaitSec, Break[]];
    ];
    
    finalInfo    = Lookup[$iWorkflowAsyncJobs, wid, Missing["JobNotFound"]];
    finalStatus  = If[KeyExistsQ[$iWorkflowNets, wid],
      Lookup[ClaudeWorkflowStatus[wid], "Status", "Unknown"],
      "Unknown"];
    finalMarking = If[KeyExistsQ[$iWorkflowNets, wid],
      iComputeCurrentMarking[wid], <||>];
    
    <|"WorkflowId"     -> wid,
      "Status"          -> If[completed, "Completed", "WaitTimeout"],
      "AsyncJob"        -> finalInfo,
      "WorkflowStatus"  -> finalStatus,
      "FinalMarking"    -> finalMarking|>
  ];

ClaudeAsyncJobInfo[wid_String] :=
  If[KeyExistsQ[$iWorkflowAsyncJobs, wid],
    $iWorkflowAsyncJobs[wid],
    <|"Status" -> "NotFound", "WorkflowId" -> wid|>
  ];

(* ::Subsubsection:: *)
(* Snapshot / Restore / List (Day 4b) *)

(* デフォルト snapshot 親ディレクトリ。LLMGraphDAG 用の $ClaudeSnapshots とは分離。 *)
If[!ValueQ[$ClaudeWorkflowSnapshotDir],
  $ClaudeWorkflowSnapshotDir =
    Quiet @ Check[
      FileNameJoin[{ClaudeCode`$ClaudeWorkingDirectory, "workflow_snapshots"}],
      FileNameJoin[{Directory[], "workflow_snapshots"}]
    ]
];

(* D (2026-05-17): ClaudeRestoreWorkflow が AwaitingLLM entry に timer を
   再仕掛けする際、transition / workflow どちらにも AwaitingLLMTimeout が
   指定されていなかった場合に使う最終手段の timeout 秒数。
   既定値 0.1 秒 (即座に _restored=True / _timeout=True で fallback 発火)。
   ユーザは Restore 前にこの変数を上書きして調整できる (例: 60.0 秒に伸ばす)。 *)
If[!NumericQ[$iRestoreFallbackTimeout],
  $iRestoreFallbackTimeout = 0.1];

iEnsureSnapshotRoot[snapRoot_String] :=
  If[!DirectoryQ[snapRoot],
    Quiet @ CreateDirectory[snapRoot, CreateIntermediateDirectories -> True];
  ];

iSnapshotDirName[wid_String] :=
  "snap-" <> wid <> "-" <> ToString[UnixTime[]];

Options[ClaudeSnapshotWorkflow] = {
  "SnapshotDir" -> Automatic,
  "Description" -> ""
};

ClaudeSnapshotWorkflow[wid_String, opts:OptionsPattern[]] :=
  Module[{wf, snapRoot, snapDir, meta, formatVersion = 2},
    
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    
    wf       = $iWorkflowNets[wid];
    snapRoot = OptionValue["SnapshotDir"] /. Automatic :>
                 $ClaudeWorkflowSnapshotDir;
    
    iEnsureSnapshotRoot[snapRoot];
    
    snapDir = FileNameJoin[{snapRoot, iSnapshotDirName[wid]}];
    Quiet @ CreateDirectory[snapDir];
    
    If[!DirectoryQ[snapDir],
      Throw[$Failed, "SnapshotDirCreationFailed: " <> snapDir]
    ];
    
    meta = <|
      "FormatVersion"   -> formatVersion,
      "Type"            -> "WorkflowNet",
      "WorkflowId"      -> wid,
      "Description"     -> OptionValue["Description"],
      "SavedAt"         -> iCurrentTime[],
      "WorkflowVersion" ->
        ClaudeOrchestrator`Workflow`$WorkflowVersion
    |>;
    
    Block[{$CharacterEncoding = "UTF-8"},
      Put[meta, FileNameJoin[{snapDir, "meta.wl"}]];
      Put[wf,   FileNameJoin[{snapDir, "workflow.wl"}]];
      (* Day 4b: llmgraph.wl と aux.wl は空の Association として保存 *)
      Put[<||>, FileNameJoin[{snapDir, "llmgraph.wl"}]];
      Put[<||>, FileNameJoin[{snapDir, "aux.wl"}]]
    ];
    
    <|"WorkflowId"    -> wid,
      "SnapshotDir"   -> snapDir,
      "FormatVersion" -> formatVersion,
      "SavedAt"       -> meta[["SavedAt"]]|>
  ];

Options[ClaudeRestoreWorkflow] = {
  "AsNewWorkflowId" -> True
};

ClaudeRestoreWorkflow[snapDir_String, opts:OptionsPattern[]] :=
  Module[{metaPath, wfPath, meta, wf, formatVersion, originalWid, newWid,
          restoredWf},
    
    If[!DirectoryQ[snapDir],
      Throw[$Failed, "SnapshotDirNotFound: " <> snapDir]
    ];
    
    metaPath = FileNameJoin[{snapDir, "meta.wl"}];
    wfPath   = FileNameJoin[{snapDir, "workflow.wl"}];
    
    If[!FileExistsQ[metaPath] || !FileExistsQ[wfPath],
      Throw[$Failed,
        "InvalidSnapshot: missing meta.wl or workflow.wl in " <> snapDir]
    ];
    
    Block[{$CharacterEncoding = "UTF-8"},
      meta = Get[metaPath];
      wf   = Get[wfPath]
    ];
    
    If[!AssociationQ[meta] || !AssociationQ[wf],
      Throw[$Failed,
        "CorruptedSnapshot: meta.wl or workflow.wl did not parse as Association"]
    ];
    
    formatVersion = Lookup[meta, "FormatVersion", 1];
    
    If[formatVersion =!= 2,
      Throw[$Failed,
        "UnsupportedFormatVersion: " <> ToString[formatVersion] <>
        " (Day 4b は v2 のみ対応、v1 -> v2 自動変換は Stage B Week 2)"]
    ];
    
    originalWid = Lookup[meta, "WorkflowId", Lookup[wf, "WorkflowId", "?"]];
    newWid      = If[TrueQ[OptionValue["AsNewWorkflowId"]],
                     iGenerateWorkflowId[],
                     originalWid];
    
    (* WorkflowId を新しいものに置き換えて registry に登録。
       既存 wid と衝突しないよう新規発行が原則 (AsNewWorkflowId デフォルト True)。
       既存 wid と同じ wid で復元したい場合は AsNewWorkflowId -> False で
       明示する (debug 用途、衝突時は上書きされる) *)
    restoredWf = ReplacePart[wf, "WorkflowId" -> newWid];
    AssociateTo[$iWorkflowNets, newWid -> restoredWf];

    (* === D (2026-05-17): AwaitingLLMTransitions の timer 再仕掛け ===
       Snapshot 時に存在した AwaitingLLM 状態の transition は、
       AwaitingLLMTransitions[awaitId] エントリとしてデータは保存されているが、
       元の callback (Function closure) と timeout ScheduledTask は
       カーネル再起動を跨いで復元できない。
       Restore 時に各エントリへ「engine 側の timer」を再仕掛けし、
       Q1 ご指示の通り「原の timeout 設定を復元、callback は復元不能だので
       _timeout=True で Payload 補完」する。
       Resolution:
         1. trans.RuntimeSpec.AwaitingLLMTimeout (transition 個別)
         2. wf.DefaultAwaitingLLMTimeout         (workflow 全体)
         3. $iRestoreFallbackTimeout (default 0.1s, 即座 fallback)
       fallback Payload には _timeout=True, _handler=tname に加えて
       _restored=True を入れ「Restore 経由の自動 completion」を示す。
       これにより、後段の transition / completion hook は
       「LLM 応答が届かなかった」を Payload から検出できる。 *)
    Module[{restoredAwaiting},
      restoredAwaiting = Lookup[restoredWf, "AwaitingLLMTransitions", <||>];
      If[AssociationQ[restoredAwaiting] && Length[restoredAwaiting] > 0,
        Scan[
          Function[entry,
            Module[{aid, tname, pp, trans, tmoTrans, tmoWf, effectiveTmo},
              aid    = Lookup[entry, "AwaitId", ""];
              tname  = Lookup[entry, "TransitionName", "?"];
              pp     = Lookup[entry, "PartialPayload", <||>];
              trans  = Lookup[restoredWf[["Transitions"]], tname, <||>];
              tmoTrans = Lookup[Lookup[trans, "RuntimeSpec", <||>],
                                 "AwaitingLLMTimeout", Automatic];
              tmoWf    = Lookup[restoredWf, "DefaultAwaitingLLMTimeout", None];
              effectiveTmo = Which[
                NumericQ[tmoTrans] && tmoTrans > 0, N[tmoTrans],
                NumericQ[tmoWf]    && tmoWf    > 0, N[tmoWf],
                True, $iRestoreFallbackTimeout];
              If[StringQ[aid] && aid =!= "",
                With[{wid1 = newWid, aid1 = aid, tname1 = tname,
                      dur = effectiveTmo,
                      pp1 = If[AssociationQ[pp], pp, <||>]},
                  SessionSubmit[ScheduledTask[
                    Quiet @ Check[
                      ClaudeCompleteHandlerOutput[wid1, aid1,
                        <|"Payload" ->
                            Append[pp1,
                              <|"_timeout"  -> True,
                                "_handler"  -> tname1,
                                "_restored" -> True|>]|>],
                      Null],
                    {dur, 1}]]]]]],
          Values[restoredAwaiting]]]];

    <|"WorkflowId"    -> newWid,
      "OriginalWid"   -> originalWid,
      "Restored"      -> True,
      "FormatVersion" -> formatVersion,
      "SnapshotDir"   -> snapDir|>
  ];

Options[ClaudeListWorkflowSnapshots] = {
  "SnapshotDir" -> Automatic
};

ClaudeListWorkflowSnapshots[opts:OptionsPattern[]] :=
  Module[{snapRoot, dirs, entries},
    snapRoot = OptionValue["SnapshotDir"] /. Automatic :>
                 $ClaudeWorkflowSnapshotDir;
    
    If[!DirectoryQ[snapRoot],
      Return[Dataset[{}]]
    ];
    
    dirs = FileNames["snap-*", snapRoot];
    
    entries = Map[
      Function[d,
        Module[{metaPath, meta},
          metaPath = FileNameJoin[{d, "meta.wl"}];
          If[FileExistsQ[metaPath],
            meta = Quiet @ Check[
              Block[{$CharacterEncoding = "UTF-8"}, Get[metaPath]],
              $Failed];
            If[AssociationQ[meta],
              <|"SnapshotDir"   -> d,
                "WorkflowId"    -> Lookup[meta, "WorkflowId", "?"],
                "FormatVersion" -> Lookup[meta, "FormatVersion", 1],
                "Description"   -> Lookup[meta, "Description", ""],
                "SavedAt"       -> Lookup[meta, "SavedAt", 0]|>,
              Nothing
            ],
            Nothing
          ]
        ]
      ],
      dirs
    ];
    
    Dataset[entries]
  ];

(* ::Subsubsection:: *)
(* ClaudeWorkflowState *)

ClaudeWorkflowState[wid_String] :=
  Module[{wf},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[<|"Status" -> "NotFound", "WorkflowId" -> wid|>]
    ];
    wf = $iWorkflowNets[wid];
    <|
      "WorkflowId" -> wid,
      "Status"     -> wf[["Status"]],
      "Tokens"     -> wf[["Tokens"]],
      "Marking"    -> iComputeCurrentMarking[wid]
    |>
  ];

(* ::Subsubsection:: *)
(* ClaudeWorkflowTrace *)

ClaudeWorkflowTrace[wid_String] :=
  Module[{wf},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Return[{}]
    ];
    wf = $iWorkflowNets[wid];
    wf[["Trace"]]
  ];

(* ::Subsubsection:: *)
(* ClaudePauseWorkflow / ClaudeResumeWorkflow / ClaudeCancelWorkflow *)

ClaudePauseWorkflow[wid_String] :=
  Module[{wf},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    wf = $iWorkflowNets[wid];
    
    (* Cancelled / Done は Pause しない *)
    If[MemberQ[{"Cancelled", "Done"}, wf[["Status"]]],
      Return[<|"Status"         -> wf[["Status"]],
               "Reason"         -> "CannotPauseTerminatedWorkflow",
               "WorkflowId"     -> wid|>]
    ];
    
    AssociateTo[$iWorkflowNets,
      wid -> ReplacePart[wf,
        {"Status" -> "Paused",
         "Trace"  -> Append[wf[["Trace"]],
           <|"Event"     -> "WorkflowPaused",
             "Timestamp" -> iCurrentTime[]|>]}]
    ];
    
    <|"Status" -> "Paused", "WorkflowId" -> wid|>
  ];

ClaudeResumeWorkflow[wid_String] :=
  Module[{wf},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    wf = $iWorkflowNets[wid];
    
    (* Paused からのみ Resume 可能 *)
    If[wf[["Status"]] =!= "Paused",
      Return[<|"Status"     -> wf[["Status"]],
               "Reason"     -> "NotPaused",
               "WorkflowId" -> wid|>]
    ];
    
    AssociateTo[$iWorkflowNets,
      wid -> ReplacePart[wf,
        {"Status" -> "Running",
         "Trace"  -> Append[wf[["Trace"]],
           <|"Event"     -> "WorkflowResumed",
             "Timestamp" -> iCurrentTime[]|>]}]
    ];
    
    <|"Status" -> "Running", "WorkflowId" -> wid|>
  ];

ClaudeCancelWorkflow[wid_String] :=
  Module[{wf, prevStatus, awaitingIds, discardEvents},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    wf         = iEnsureAwaitingLLMField[$iWorkflowNets[wid]];
    prevStatus = wf[["Status"]];

    (* Z\:6848 (2026-05-16): AwaitingLLMTransitions \:30af\:30ea\:30a2 + discard \:30c8\:30ec\:30fc\:30b9 *)
    awaitingIds   = Keys[Lookup[wf, "AwaitingLLMTransitions", <||>]];
    discardEvents = Map[
      <|"Event"           -> "TransitionCallbackDiscarded",
        "AwaitId"         -> #,
        "TransitionName"  -> Lookup[wf[["AwaitingLLMTransitions", #]],
                              "TransitionName", "?"],
        "Reason"          -> "WorkflowCancelled",
        "Timestamp"       -> iCurrentTime[]|> &,
      awaitingIds
    ];

    AssociateTo[$iWorkflowNets,
      wid -> ReplacePart[wf,
        {"Status"                  -> "Cancelled",
         "AwaitingLLMTransitions"  -> <||>,
         "Trace"                   -> Join[wf[["Trace"]], discardEvents,
           {<|"Event"          -> "WorkflowCancelled",
              "PreviousStatus" -> prevStatus,
              "DiscardedAwait" -> Length[awaitingIds],
              "Timestamp"      -> iCurrentTime[]|>}]}]
    ];

    (* async ジョブが走っていたら即時に完了状態へ。
       次の SharedPollingTask tick を待たずに ClaudeWaitWorkflow が
       Completed を見られるようにする。 *)
    If[KeyExistsQ[$iWorkflowAsyncJobs, wid] &&
       Lookup[$iWorkflowAsyncJobs[wid], "Status", "Completed"] =!= "Completed",
      iMarkAsyncCompleted[wid, "Cancelled"]
    ];

    <|"Status" -> "Cancelled", "WorkflowId" -> wid,
      "DiscardedAwaitingCount" -> Length[awaitingIds]|>
  ];

(* ::Subsubsection:: *)
(* TODO Stage B Week 2 以降のスタブ宣言 *)

(*
   以下は Stage B Week 2 以降で実装する。Stage B 設計仕様書 §3 / §4 / §5 を参照。

   iExecuteTransition の Executor "PackageManager" 本実装
     - ClaudePackageManager の transaction API 接続
     - Day 4c では stub のまま (PM の transaction API が深いため)

   shim:
     LLMStateGraphCreate / Status / State / Trace / Cancel / List /
     RecordHistory / Snapshot / Restore / ListSnapshots / RunStateGraph
     iConvertXSMToWorkflowNet (StateGraphEdge -> Transition)
     iParallelSubgraphToANDSplitJoin

   v1 -> v2 snapshot 自動変換
     iRestoreFromV1 / iConvertXSMSnapshotToMTP
*)

(* ::Subsection:: *)
(* External executor (WolframScript) connection: Phase 3 *)

(* ────────────────────────────────────────────────────────
   設計 (v7 §3, §7, §8, M1):
   - External transition は fire 時に runner を launch し AwaitingLLM を返す
     (AwaitingLLMTimeout は設定しない; timeout は poller が単独所有)。
   - resource-place slot は net 構築で External transition の InputArcs と
     OutputArcs に WolframScriptSlots place を加えることで表現する。
     fire 時に slot を consume、ClaudeCompleteHandlerOutput (terminal 完了) 時に
     OutputArcs 経由で返却。retry 中は complete しないので slot は保持される。
   - launcher / status reader / killer は差し替え可能なフック
     (本体の実 runner は Phase 4)。
   ──────────────────────────────────────────────────────── *)

If[! ValueQ[$ClaudeExternalJobLauncher],      $ClaudeExternalJobLauncher = Automatic];
If[! ValueQ[$ClaudeExternalJobStatusReader],  $ClaudeExternalJobStatusReader = Automatic];
If[! ValueQ[$ClaudeExternalJobKiller],        $ClaudeExternalJobKiller = Automatic];
If[! ValueQ[$ClaudeExternalCompletionHook],   $ClaudeExternalCompletionHook = None];

(* 既定 launcher: Phase 4 runner 未配線時は安全に Failed (atomic rollback で
   input/slot token は消費されない)。 *)
iDefaultExternalLauncher[jobSpec_Association] :=
  <|"Status" -> "Failed",
    "Reason" -> "ExternalRunnerNotConfigured: Phase 4 runner / $ClaudeExternalJobLauncher 未設定"|>;

(* 既定 status reader: JobDir/status.json を読む。無ければ Running。 *)
iDefaultExternalStatusReader[awaitMeta_Association] :=
  Module[{dir, f, raw},
    dir = Lookup[awaitMeta, "JobDir", None];
    If[! StringQ[dir], Return[<|"Status" -> "Running"|>]];
    f = FileNameJoin[{dir, "status.json"}];
    If[! FileExistsQ[f], Return[<|"Status" -> "Running"|>]];
    raw = Quiet @ Check[Import[f, "RawJSON"], $Failed];
    If[AssociationQ[raw], raw, <|"Status" -> "Running"|>]
  ];

(* 既定 killer: best-effort no-op (Phase 4 で pid.json 同一性確認 + kill)。 *)
iDefaultExternalKiller[awaitMeta_Association] := Null;

(* ── backend dispatch registry (純加法) ──
   $ClaudeExternalBackends が空のときは下のフォールバック (= 従来の singleton hook 挙動)
   と完全に同一。jobSpec/awaitMeta の "Backend" が登録 backend に一致したときだけ、
   その backend の launcher/reader/killer へ dispatch する。
   これにより WolframScript external dispatch (ClaudeEval) を壊さず ComfyUI 等を共存させる。 *)
If[! AssociationQ[$ClaudeExternalBackends], $ClaudeExternalBackends = <||>];

iExternalFallbackLauncher[]     := If[$ClaudeExternalJobLauncher === Automatic,
                                     iDefaultExternalLauncher, $ClaudeExternalJobLauncher];
iExternalFallbackStatusReader[] := If[$ClaudeExternalJobStatusReader === Automatic,
                                     iDefaultExternalStatusReader, $ClaudeExternalJobStatusReader];
iExternalFallbackKiller[]       := If[$ClaudeExternalJobKiller === Automatic,
                                     iDefaultExternalKiller, $ClaudeExternalJobKiller];

(* spec/awaitMeta の Backend (既定 WolframScript) に対応する role 関数。無ければ Missing。 *)
iExternalBackendFn[spec_Association, role_String] :=
  Module[{b = Lookup[spec, "Backend", "WolframScript"], be},
    be = If[AssociationQ[$ClaudeExternalBackends], Lookup[$ClaudeExternalBackends, b, Missing[]], Missing[]];
    If[AssociationQ[be] && KeyExistsQ[be, role] && be[role] =!= Automatic, be[role], Missing[]]];
iExternalBackendFn[_, _] := Missing[];

(* resolve は dispatcher 関数を返す。引数 (jobSpec/awaitMeta) の Backend で分岐し、
   未登録なら従来フォールバックへ委譲する。呼び出し側 (launcher[jobSpec] 等) は不変。 *)
iExternalResolveLauncher[] := Function[js,
  With[{fn = iExternalBackendFn[If[AssociationQ[js], js, <||>], "Launcher"]},
    If[MissingQ[fn], iExternalFallbackLauncher[][js], fn[js]]]];
iExternalResolveStatusReader[] := Function[am,
  With[{fn = iExternalBackendFn[If[AssociationQ[am], am, <||>], "StatusReader"]},
    If[MissingQ[fn], iExternalFallbackStatusReader[][am], fn[am]]]];
iExternalResolveKiller[] := Function[am,
  With[{fn = iExternalBackendFn[If[AssociationQ[am], am, <||>], "Killer"]},
    If[MissingQ[fn], iExternalFallbackKiller[][am], fn[am]]]];

ClaudeRegisterExternalBackend[name_String, spec_Association] :=
  Module[{cur = If[AssociationQ[$ClaudeExternalBackends], $ClaudeExternalBackends, <||>],
          entry},
    entry = KeyTake[spec, {"Launcher", "StatusReader", "Killer"}];
    $ClaudeExternalBackends = Append[cur, name -> Join[Lookup[cur, name, <||>], entry]];
    <|"Status" -> "Registered", "Backend" -> name, "Roles" -> Keys[entry]|>];
ClaudeRegisterExternalBackend[___] :=
  <|"Status" -> "Error", "Reason" -> "BadArguments"|>;

ClaudeExternalBackends[] :=
  If[AssociationQ[$ClaudeExternalBackends], Keys[$ClaudeExternalBackends], {}];

(* External executor branch: launch して AwaitingLLM を返す。
   ClaudeFireTransition の Awaiting branch がこれを拾い、input(+slot) を consume し
   AwaitingLLMTransitions に AwaitMeta (PartialPayload) を記録する。 *)
iExecuteExternalBranch[trans_Association, binding_Association] :=
  Module[{opts, backend, handler, wid, awaitId, timeout, jobSpec,
          launcher, launched, awaitMeta},
    (* ExecutorOptions は RuntimeSpec 配下を正とし、top-level も後方互換で見る
       (WorkflowTransition の Options に ExecutorOptions は無いため RuntimeSpec に置く)。 *)
    opts    = Lookup[Lookup[trans, "RuntimeSpec", <||>], "ExecutorOptions",
                Lookup[trans, "ExecutorOptions", <||>]];
    backend = Lookup[opts, "Backend", "WolframScript"];
    handler = Lookup[opts, "Handler", Missing["NoHandler"]];
    wid     = $ClaudeCurrentWid;
    awaitId = If[StringQ[wid], iGenerateAwaitId[wid],
                "await-ext-" <> ToString[UnixTime[]]];
    (* Timeout は RuntimeSpec > transition top-level > ExecutorOptions の順で解決 *)
    timeout = SelectFirst[
      {Lookup[Lookup[trans, "RuntimeSpec", <||>], "Timeout", None],
       Lookup[trans, "Timeout", None],
       Lookup[opts, "Timeout", None]},
      NumericQ, 3600];

    jobSpec = <|
      "WorkflowID"     -> wid,
      "TransitionName" -> Lookup[trans, "Name", "?"],
      "AwaitId"        -> awaitId,
      "Backend"        -> backend,
      "Handler"        -> handler,
      "Binding"        -> binding,
      "Inputs"         -> iFlattenBinding[binding],
      "Timeout"        -> timeout,
      "AccessSpec"     -> Lookup[trans[["RuntimeSpec"]], "AccessSpec", <||>],
      (* 2026-06-12 (external dispatch): ExecutorOptions から launcher へ渡す
         追加 field (純加法)。BootstrapFiles は run.wls の子プロセス先行ロード、
         ConfidentialHandling / CredentialRefs は manifest へ。 *)
      "BootstrapFiles"       -> Lookup[opts, "BootstrapFiles", {}],
      "ConfidentialHandling" -> Lookup[opts, "ConfidentialHandling", "ReferenceOnly"],
      "CredentialRefs"       -> Lookup[opts, "CredentialRefs", {}]
    |>;

    launcher = iExternalResolveLauncher[];
    launched = Quiet @ Check[launcher[jobSpec],
      <|"Status" -> "Failed", "Reason" -> "LauncherException"|>];

    If[! AssociationQ[launched] || Lookup[launched, "Status", ""] =!= "Launched",
      Return[<|"Status" -> "Failed",
        "Reason" -> "ExternalLaunchFailed: " <>
          ToString[Lookup[launched, "Reason", "unknown"]]|>]];

    awaitMeta = <|
      "AwaitKind" -> "ExternalWolframScriptJob",
      "JobID"     -> Lookup[launched, "JobID", awaitId],
      "JobDir"    -> Lookup[launched, "JobDir", None],
      "PID"       -> Lookup[launched, "PID", None],
      "Handler"   -> handler,
      "Backend"   -> backend,
      "Timeout"   -> timeout,
      "Attempt"   -> 0,
      (* 2026-06-12 (external dispatch): 完了 summary の書込先 notebook。
         親メモリ内 (awaitMeta) のみで保持し、manifest / 子プロセスへは渡さない。 *)
      "NotifyNotebook" -> Lookup[opts, "NotifyNotebook", None]
    |>;

    (* PartialPayload に AwaitMeta を格納 -> AwaitingLLMTransitions entry に保存され、
       poller / snapshot から参照可能。AwaitingLLMTimeout は設定しない (v7 C1)。 *)
    <|"Status"         -> "Awaiting",
      "AwaitId"        -> awaitId,
      "Output"         -> <|"Payload" -> awaitMeta|>,
      "PartialPayload" -> awaitMeta|>
  ];

(* ─── poller ─── *)

ClaudeExternalJobPollTick[] :=
  Module[{results = {}},
    Scan[
      Function[wid,
        Module[{wf, awaiting},
          wf = Lookup[$iWorkflowNets, wid, None];
          If[AssociationQ[wf] &&
             ! MemberQ[{"Cancelled", "Done", "Paused"}, Lookup[wf, "Status", ""]],
            awaiting = Lookup[wf, "AwaitingLLMTransitions", <||>];
            KeyValueMap[
              Function[{aid, entry},
                Module[{pp},
                  pp = Lookup[entry, "PartialPayload", <||>];
                  If[AssociationQ[pp] &&
                     Lookup[pp, "AwaitKind", ""] === "ExternalWolframScriptJob",
                    AppendTo[results, iExternalPollOne[wid, aid, entry, pp]]]
                ]],
              awaiting]
          ]
        ]],
      Keys[$iWorkflowNets]];
    <|"Polled" -> Length[results], "Results" -> results|>
  ];

iExternalPollOne[wid_String, aid_String, entry_Association, awaitMeta_Association] :=
  Module[{reader, status, st, elapsed, timeout, startT},
    startT  = Lookup[entry, "StartTime", iCurrentTime[]];
    timeout = Lookup[awaitMeta, "Timeout", Infinity];
    elapsed = iCurrentTime[] - startT;
    (* timeout を最優先で判定 (poller が単独所有) *)
    If[NumericQ[timeout] && timeout > 0 && elapsed > timeout,
      Return[iExternalHandleTimeout[wid, aid, entry, awaitMeta]]];
    reader = iExternalResolveStatusReader[];
    status = Quiet @ Check[reader[awaitMeta], <|"Status" -> "Running"|>];
    If[! AssociationQ[status], status = <|"Status" -> "Running"|>];
    st = Lookup[status, "Status", "Running"];
    Switch[st,
      "Completed",          iExternalComplete[wid, aid, awaitMeta, status],
      "Failed" | "Expired", iExternalFailOrRetry[wid, aid, entry, awaitMeta, status],
      _,                    <|"AwaitId" -> aid, "Action" -> "NoOp", "Status" -> st|>
    ]
  ];

(* Completed: output は ref のみ payload に載せる (v7 §7.3 / §10.1)。
   ClaudeCompleteHandlerOutput が OutputArcs を produce -> result place に ref token、
   slot place に slot token (= slot 返却)。 *)
iExternalComplete[wid_String, aid_String, awaitMeta_Association, status_Association] :=
  Module[{},
    ClaudeCompleteHandlerOutput[wid, aid, <|"Payload" -> <|
      "Status"         -> "Completed",
      "JobID"          -> Lookup[awaitMeta, "JobID", aid],
      "OutputRef"      -> Lookup[status, "OutputRef", None],
      "SourceVaultRef" -> Lookup[status, "SourceVaultRef", None],
      "SummaryRef"     -> Lookup[status, "SummaryRef", None]
    |>|>];
    (* completion hook (live 統合): 完了後に Notebook 反映等を行う注入点。
       workflow は疎結合のまま; 反映ロジックは externalrunner 側が設定する
       (final action 構築 -> FinalActionQueue enqueue)。 *)
    If[$ClaudeExternalCompletionHook =!= None,
      Quiet @ Check[
        $ClaudeExternalCompletionHook[<|
          "WorkflowId" -> wid, "AwaitId" -> aid,
          "AwaitMeta" -> awaitMeta, "Status" -> status|>],
        Null]];
    <|"AwaitId" -> aid, "Action" -> "Completed"|>];

(* Failed/Expired: RetryPolicy に従い retry (slot 保持) か terminal failure。 *)
iExternalFailOrRetry[wid_String, aid_String, entry_Association,
                     awaitMeta_Association, status_Association] :=
  Module[{wf, trans, retryPolicy, maxRetries, attempt},
    wf      = Lookup[$iWorkflowNets, wid, <||>];
    trans   = Lookup[Lookup[wf, "Transitions", <||>],
                Lookup[entry, "TransitionName", "?"], <||>];
    retryPolicy = Lookup[Lookup[trans, "RuntimeSpec", <||>], "RetryPolicy",
                    Lookup[trans, "RetryPolicy", <|"MaxRetries" -> 0|>]];
    maxRetries  = Lookup[retryPolicy, "MaxRetries", 0];
    attempt     = Lookup[awaitMeta, "Attempt", 0];
    If[IntegerQ[maxRetries] && attempt < maxRetries,
      iExternalRetry[wid, aid, entry, awaitMeta, attempt + 1],
      (* terminal failure: ref のみの failure payload。slot は OutputArc で返却。 *)
      ClaudeCompleteHandlerOutput[wid, aid, <|"Payload" -> <|
        "Status"            -> "Failed",
        "JobID"             -> Lookup[awaitMeta, "JobID", aid],
        "ErrorRef"          -> Lookup[status, "ErrorRef", None],
        "FailureSummaryRef" -> Lookup[status, "FailureSummaryRef", None]
      |>|>];
      <|"AwaitId" -> aid, "Action" -> "TerminalFailed", "Attempt" -> attempt|>
    ]
  ];

(* retry: 同一 JobDir/checkpoint から再起動。complete しないので slot は保持
   (awaiting entry を維持し Attempt++、StartTime をリセット)。input token は再消費しない。 *)
iExternalRetry[wid_String, aid_String, entry_Association,
               awaitMeta_Association, newAttempt_Integer] :=
  Module[{launcher, jobSpec, launched, newMeta, newEntry, wf},
    launcher = iExternalResolveLauncher[];
    jobSpec  = <|
      "WorkflowID" -> wid, "AwaitId" -> aid,
      (* 同一 JobID -> launcher が同一 JobDir を再利用 -> checkpoint resume (v7 §7.5) *)
      "JobID"      -> Lookup[awaitMeta, "JobID", None],
      "Backend"    -> Lookup[awaitMeta, "Backend", "WolframScript"],
      "Handler"    -> Lookup[awaitMeta, "Handler", Missing["NoHandler"]],
      "JobDir"     -> Lookup[awaitMeta, "JobDir", None],
      "Resume"     -> True,
      "Attempt"    -> newAttempt,
      "Timeout"    -> Lookup[awaitMeta, "Timeout", 3600]
    |>;
    launched = Quiet @ Check[launcher[jobSpec], <|"Status" -> "Failed"|>];
    If[! AssociationQ[launched] || Lookup[launched, "Status", ""] =!= "Launched",
      ClaudeCompleteHandlerOutput[wid, aid, <|"Payload" -> <|
        "Status" -> "Failed", "JobID" -> Lookup[awaitMeta, "JobID", aid],
        "ErrorRef" -> "RelaunchFailed"|>|>];
      Return[<|"AwaitId" -> aid, "Action" -> "RetryLaunchFailed",
        "Attempt" -> newAttempt|>]];
    newMeta = Join[awaitMeta, <|
      "Attempt" -> newAttempt,
      "PID"     -> Lookup[launched, "PID", Lookup[awaitMeta, "PID", None]],
      "JobDir"  -> Lookup[launched, "JobDir", Lookup[awaitMeta, "JobDir", None]]|>];
    newEntry = Join[entry, <|"PartialPayload" -> newMeta, "StartTime" -> iCurrentTime[]|>];
    wf = Lookup[$iWorkflowNets, wid, <||>];
    If[AssociationQ[wf] && KeyExistsQ[wf, "AwaitingLLMTransitions"],
      wf = ReplacePart[wf, {"AwaitingLLMTransitions", aid} -> newEntry];
      AssociateTo[$iWorkflowNets, wid -> wf]];
    <|"AwaitId" -> aid, "Action" -> "Retried", "Attempt" -> newAttempt|>
  ];

(* timeout: kill -> Expired として fail-or-retry へ。下流 token を成功 produce しない。 *)
iExternalHandleTimeout[wid_String, aid_String, entry_Association,
                       awaitMeta_Association] :=
  Module[{killer},
    killer = iExternalResolveKiller[];
    Quiet @ Check[killer[awaitMeta], Null];
    iExternalFailOrRetry[wid, aid, entry, awaitMeta,
      <|"Status" -> "Expired", "ErrorRef" -> "Timeout"|>]
  ];

(* ════════════════════════════════════════════════════════
   ClaudeSubmitExternalHeldExprJob (2026-06-12, ClaudeEval external dispatch)
   承認済み held expr を 1 遷移 WorkflowNet (In + Slots -> External -> Out + Slots)
   として External executor へ投入する公開 API。ジョブ lifecycle
   (poll / timeout / retry / kill / 完了反映) は既存エンジンが所有する。
   設計: ドキュメント/ClaudeEval_external_dispatch_design.md
   ════════════════════════════════════════════════════════ *)

ClaudeOrchestrator`Workflow`ClaudeSubmitExternalHeldExprJob::usage =
  "ClaudeSubmitExternalHeldExprJob[HoldComplete[expr], opts] は承認済み held expr を External executor (WolframScript ジョブ) へ 1 遷移 WorkflowNet として投入する。opts: \"Timeout\" (既定 3600 秒), \"BootstrapFiles\" (子プロセスで先行ロードするパッケージ), \"NotifyNotebook\" (完了 summary の書込先 NotebookObject), \"AccessSpec\" (Automatic = WolframScriptTask role), \"MaxRetries\" (既定 0), \"Handler\" (既定 \"ApprovedHeldExpr\")。返り値: <|\"Status\"->\"Submitted\", \"JobID\", \"JobDir\", \"WorkflowId\", \"Head\"|> または <|\"Status\"->\"Failed\", \"Reason\"|>。";

If[! AssociationQ[$iExtHeldExprNets], $iExtHeldExprNets = <||>];

(* HoldComplete[h[...]] / HoldComplete[h] の head 名 (非評価で取得) *)
iExtJobHeadName[held_HoldComplete] :=
  Replace[held, {
    HoldComplete[(h_Symbol)[___]] :> SymbolName[Unevaluated[h]],
    HoldComplete[h_Symbol]        :> SymbolName[Unevaluated[h]],
    _ :> $Failed}];
iExtJobHeadName[_] := $Failed;

Options[ClaudeOrchestrator`Workflow`ClaudeSubmitExternalHeldExprJob] = {
  "Handler"        -> "ApprovedHeldExpr",
  "Timeout"        -> 3600,
  "BootstrapFiles" -> {},
  "NotifyNotebook" -> None,
  "ResultRetriever"-> None,
  "AccessSpec"     -> Automatic,
  "MaxRetries"     -> 0
};

ClaudeOrchestrator`Workflow`ClaudeSubmitExternalHeldExprJob[
    held_HoldComplete,
    opts:OptionsPattern[
      ClaudeOrchestrator`Workflow`ClaudeSubmitExternalHeldExprJob]] :=
  Module[{headName, accessSpec, timeout, maxRetries, wid, stepR, wf,
          awaiting, meta, jobId, jobDir},
    (* 0. 自前 GC: 本 API が作った terminal ネットを registry から除去
       (engine に削除 API が無いため、自分が作ったネットだけ後始末する) *)
    Scan[Function[w,
      Module[{st = Lookup[Lookup[$iWorkflowNets, w, <||>], "Status", ""]},
        If[MemberQ[{"Done", "Cancelled"}, st],
          $iWorkflowNets    = KeyDrop[$iWorkflowNets, w];
          $iExtHeldExprNets = KeyDrop[$iExtHeldExprNets, w]]]],
      Keys[$iExtHeldExprNets]];

    headName = iExtJobHeadName[held];
    If[! StringQ[headName],
      Return[<|"Status" -> "Failed", "Reason" -> "UnsupportedHeldExprShape"|>]];

    timeout = OptionValue["Timeout"];
    If[! NumericQ[timeout] || timeout <= 0, timeout = 3600];
    maxRetries = OptionValue["MaxRetries"];
    If[! IntegerQ[maxRetries] || maxRetries < 0, maxRetries = 0];

    (* AccessSpec: 既定は WolframScriptTask role (v7 §13A.2)。
       NBAccess 未ロード時は空 (runner 側 cooperative guard はスキップされる)。 *)
    accessSpec = OptionValue["AccessSpec"];
    If[accessSpec === Automatic,
      accessSpec = If[Length[DownValues[NBAccess`NBMakeRuntimeAccessSpec]] > 0,
        Quiet @ Check[
          NBAccess`NBMakeRuntimeAccessSpec[
            <|"Caller" -> "ClaudeSubmitExternalHeldExprJob"|>,
            "WolframScriptTask"],
          <||>],
        <||>]];
    If[! AssociationQ[accessSpec], accessSpec = <||>];

    wid = Quiet @ Check[ClaudeCreateWorkflowNet[
      WorkflowNet[
        "SourcePlace" -> "In", "FinalPlaces" -> {"Out"},
        "Places" -> <|
          "In"    -> WorkflowPlace["In",    "AcceptedKinds" -> All],
          "Slots" -> WorkflowPlace["Slots", "AcceptedKinds" -> All],
          "Out"   -> WorkflowPlace["Out",   "AcceptedKinds" -> All]|>,
        "Transitions" -> <|
          "Run" -> WorkflowTransition["Run",
            "InputArcs"  -> {<|"Place" -> "In",    "Multiplicity" -> 1|>,
                             <|"Place" -> "Slots", "Multiplicity" -> 1|>},
            (* M1 (v7 review): slot 返却は OutputArc。terminal 完了時のみ produce。 *)
            "OutputArcs" -> {<|"Place" -> "Out",   "Multiplicity" -> 1|>,
                             <|"Place" -> "Slots", "Multiplicity" -> 1|>},
            "Executor"   -> "External",
            "RuntimeSpec" -> <|
              "Timeout"     -> timeout,
              "AccessSpec"  -> accessSpec,
              "RetryPolicy" -> <|"MaxRetries" -> maxRetries|>,
              "ExecutorOptions" -> <|
                "Backend"        -> "WolframScript",
                "Handler"        -> OptionValue["Handler"],
                "BootstrapFiles" -> OptionValue["BootstrapFiles"],
                "NotifyNotebook" -> OptionValue["NotifyNotebook"],
                "ResultRetriever"-> OptionValue["ResultRetriever"]|>|>]|>]],
      $Failed];
    If[! StringQ[wid],
      Return[<|"Status" -> "Failed", "Reason" -> "NetCreateFailed"|>]];

    ClaudeSubmitToken[wid, WorkflowToken["Kind" -> "Task",
      "Payload" -> <|
        "HeldExpr"       -> held,
        "AllowedHeads"   -> {headName},
        "TimeConstraint" -> Max[60, timeout - 60]|>]];
    ClaudeSubmitToken[wid, WorkflowToken["Kind" -> "Slot"], "Slots"];
    stepR = Quiet @ Check[ClaudeStepWorkflow[wid], $Failed];

    wf       = Lookup[$iWorkflowNets, wid, <||>];
    awaiting = Lookup[wf, "AwaitingLLMTransitions", <||>];
    If[! AssociationQ[awaiting] || Length[awaiting] === 0,
      (* fire できなかった (launcher 未配線 / 起動失敗等)。atomic rollback 済みなので
         ネットごと破棄する。 *)
      $iWorkflowNets = KeyDrop[$iWorkflowNets, wid];
      Return[<|"Status" -> "Failed", "Reason" -> "ExternalLaunchNotAwaiting",
        "StepResult" -> stepR|>]];
    meta   = Lookup[First[Values[awaiting]], "PartialPayload", <||>];
    jobId  = Lookup[meta, "JobID", None];
    jobDir = Lookup[meta, "JobDir", None];
    $iExtHeldExprNets[wid] = <|"JobID" -> jobId, "SubmittedAt" -> AbsoluteTime[]|>;
    <|"Status" -> "Submitted", "WorkflowId" -> wid, "JobID" -> jobId,
      "JobDir" -> jobDir, "Head" -> headName|>
  ];

(* ════════════════════════════════════════════════════════
   Subkernel executor (Phase 3.5): External と同じ AwaitingLLM + resource-place
   (SubkernelSlots) 機構を再利用。submit/poll は seam (既定 = ParallelSubmit +
   NBExecuteHeldExprSubkernelRaw / 非ブロッキング future poll、テストで mock 可)。
   巨大結果は token payload に inline せず summary 化 (main へ raw 返却しない)。
   ════════════════════════════════════════════════════════ *)

If[! ValueQ[$ClaudeSubkernelSubmit], $ClaudeSubkernelSubmit = Automatic];
If[! ValueQ[$ClaudeSubkernelPoll],   $ClaudeSubkernelPoll = Automatic];
If[! IntegerQ[$ClaudeSubkernelResultInlineLimit],
  $ClaudeSubkernelResultInlineLimit = 64*1024];

(* 既定 submit: ParallelSubmit[NBExecuteHeldExprSubkernelRaw[heldExpr, accessSpec]]。
   kernel 未起動 / 関数未ロードなら None (graceful fail)。 *)
SetAttributes[iDefaultSubkernelSubmit, HoldAllComplete];
iDefaultSubkernelSubmit[heldExpr_, accessSpec_] :=
  Module[{he},
    If[Length[DownValues[NBAccess`NBExecuteHeldExprSubkernelRaw]] === 0 ||
       Length[Kernels[]] === 0,
      Return[None]];
    he = heldExpr;  (* HoldComplete[expr] *)
    Quiet @ Check[
      <|"Handle" -> ParallelSubmit[
          NBAccess`NBExecuteHeldExprSubkernelRaw[he, accessSpec]]|>,
      None]
  ];

(* 既定 poll: 非ブロッキング future 完了判定。ClaudeRuntime の iPollFutureComplete
   が利用可能ならそれを使う。 *)
iDefaultSubkernelPoll[handle_Association] :=
  Module[{future, r},
    future = Lookup[handle, "Handle", None];
    If[future === None, Return[<|"Done" -> True, "Result" -> $Failed|>]];
    If[Length[DownValues[ClaudeRuntime`Private`iPollFutureComplete]] > 0,
      r = ClaudeRuntime`Private`iPollFutureComplete[future, 0.01];
      <|"Done" -> TrueQ[Lookup[r, "Completed", False]],
        "Result" -> Lookup[r, "Result", None]|>,
      (* fallback: WaitAll を極短 timeout で *)
      Module[{done},
        done = Quiet @ Check[
          TimeConstrained[WaitAll[future]; True, 0.01, False], False];
        If[TrueQ[done],
          <|"Done" -> True, "Result" -> Quiet[future]|>,
          <|"Done" -> False, "Result" -> None|>]]]
  ];

iSubkernelResolveSubmit[] :=
  If[$ClaudeSubkernelSubmit === Automatic, iDefaultSubkernelSubmit, $ClaudeSubkernelSubmit];
iSubkernelResolvePoll[] :=
  If[$ClaudeSubkernelPoll === Automatic, iDefaultSubkernelPoll, $ClaudeSubkernelPoll];

(* Subkernel executor branch: held expr を subkernel へ submit し AwaitingLLM を返す。 *)
iExecuteSubkernelBranch[trans_Association, binding_Association] :=
  Module[{rt, heldExpr, accessSpec, submit, submitted, wid, awaitId, timeout},
    rt = Lookup[trans, "RuntimeSpec", <||>];
    heldExpr   = Lookup[rt, "SubkernelExpr", Lookup[rt, "HeldExpr", Missing["NoExpr"]]];
    accessSpec = Lookup[rt, "AccessSpec", <||>];
    If[! MatchQ[heldExpr, _HoldComplete],
      Return[<|"Status" -> "Failed", "Reason" -> "NoSubkernelExpr (RuntimeSpec SubkernelExpr に HoldComplete[...] が必要)"|>]];
    submit = iSubkernelResolveSubmit[];
    submitted = Quiet @ Check[submit[heldExpr, accessSpec], None];
    If[! AssociationQ[submitted] || ! KeyExistsQ[submitted, "Handle"],
      Return[<|"Status" -> "Failed", "Reason" -> "SubkernelSubmitUnavailable"|>]];
    wid     = $ClaudeCurrentWid;
    awaitId = If[StringQ[wid], iGenerateAwaitId[wid], "await-sk-" <> ToString[UnixTime[]]];
    timeout = SelectFirst[{Lookup[rt, "Timeout", None], Lookup[trans, "Timeout", None]},
                NumericQ, None];
    With[{meta = <|"AwaitKind" -> "SubkernelTask",
                   "Handle" -> submitted["Handle"], "Timeout" -> timeout|>},
      <|"Status" -> "Awaiting", "AwaitId" -> awaitId,
        "Output" -> <|"Payload" -> <|"AwaitKind" -> "SubkernelTask"|>|>,
        "PartialPayload" -> meta|>]
  ];

(* subkernel 結果を payload 化 (巨大は summary)。 *)
iSubkernelResultPayload[result_] :=
  Module[{bytes},
    bytes = Quiet @ Check[ByteCount[result], "Unknown"];
    If[IntegerQ[bytes] && bytes <= $ClaudeSubkernelResultInlineLimit,
      <|"Status" -> "Completed", "Result" -> result, "ByteCount" -> bytes|>,
      <|"Status" -> "Completed", "Inlined" -> False, "ByteCount" -> bytes,
        "Head" -> Quiet @ Check[ToString[Head[result]], "?"]|>]
  ];

ClaudeSubkernelPollTick[] :=
  Module[{results = {}},
    Scan[
      Function[wid,
        Module[{wf, awaiting},
          wf = Lookup[$iWorkflowNets, wid, None];
          If[AssociationQ[wf] &&
             ! MemberQ[{"Cancelled", "Done", "Paused"}, Lookup[wf, "Status", ""]],
            awaiting = Lookup[wf, "AwaitingLLMTransitions", <||>];
            KeyValueMap[
              Function[{aid, entry},
                Module[{pp},
                  pp = Lookup[entry, "PartialPayload", <||>];
                  If[AssociationQ[pp] &&
                     Lookup[pp, "AwaitKind", ""] === "SubkernelTask",
                    AppendTo[results, iSubkernelPollOne[wid, aid, entry, pp]]]]],
              awaiting]]]],
      Keys[$iWorkflowNets]];
    <|"Polled" -> Length[results], "Results" -> results|>
  ];

iSubkernelPollOne[wid_String, aid_String, entry_Association, awaitMeta_Association] :=
  Module[{poll, st, elapsed, timeout, startT, result},
    startT  = Lookup[entry, "StartTime", iCurrentTime[]];
    timeout = Lookup[awaitMeta, "Timeout", Infinity];
    elapsed = iCurrentTime[] - startT;
    If[NumericQ[timeout] && timeout > 0 && elapsed > timeout,
      ClaudeCompleteHandlerOutput[wid, aid,
        <|"Payload" -> <|"Status" -> "Failed", "ErrorRef" -> "SubkernelTimeout"|>|>];
      Return[<|"AwaitId" -> aid, "Action" -> "Timeout"|>]];
    poll = iSubkernelResolvePoll[];
    st = Quiet @ Check[poll[awaitMeta], <|"Done" -> False|>];
    If[! AssociationQ[st] || ! TrueQ[Lookup[st, "Done", False]],
      Return[<|"AwaitId" -> aid, "Action" -> "NoOp"|>]];
    result = Lookup[st, "Result", None];
    If[result === $Failed,
      ClaudeCompleteHandlerOutput[wid, aid,
        <|"Payload" -> <|"Status" -> "Failed", "ErrorRef" -> "SubkernelEvalFailed"|>|>];
      <|"AwaitId" -> aid, "Action" -> "Failed"|>,
      ClaudeCompleteHandlerOutput[wid, aid,
        <|"Payload" -> iSubkernelResultPayload[result]|>];
      <|"AwaitId" -> aid, "Action" -> "Completed"|>]
  ];

(* ::Subsection:: *)
(* End *)

End[];
EndPackage[];
(* ════════════════════════════════════════════════════════════════════
   ════════════════════════════════════════════════════════════════════
                         Part 2: Workflow Shim
   以下は元 ClaudeOrchestrator_workflow_shim.wl の内容を統合したもの
   (2026-05-06、ファイル整理の一環として 1 ファイルに統合)。
   役割: ClaudeStateGraph` 名前空間の Public API (LLMStateGraphCreate 等)
         を本ファイル Part 1 の WorkflowNet engine に forwarding する
         dispatcher 互換層。
   名前空間: ClaudeOrchestrator`Workflow`Shim`
   依存: ClaudeOrchestrator`Workflow` (= 本ファイル Part 1)
   元ファイル分離期 (2026-04 〜 2026-05-06):
     - ClaudeOrchestrator_workflow.wl     (engine 本体、約 67KB)
     - ClaudeOrchestrator_workflow_shim.wl (shim、約 73KB)
   統合により:
     - ロード順序の問題が解消 (Part 1 → Part 2 が固定)
     - ClaudeOrchestrator.wl の自動ロード対象が 1 ファイル分減少
   ════════════════════════════════════════════════════════════════════
   ════════════════════════════════════════════════════════════════════ *)
(* ::Package:: *)
(* ::Title:: *)
(* ClaudeOrchestrator_workflow_shim.wl *)
(* ::Subsection:: *)
(* 概要 *)
(* ════════════════════════════════════════════════════════════════════
   ClaudeOrchestrator_workflow_shim.wl
   ClaudeOrchestrator`Workflow`Shim` 名前空間。
   旧 LLMStateGraph (ClaudeStateGraph` namespace) → 新 WorkflowNet
   (ClaudeOrchestrator`Workflow`) への変換ロジックを集約する。
   位置付け:
     - 既存 ClaudeOrchestrator_stategraph.wl は **触らない** (= 既存 36 + 35 + 40
       テストへの影響を遮断)
     - 本ファイルは新規 namespace で変換関数だけを提供
     - 動作確認後、Week 2c で ClaudeStateGraph` 名前空間の Public API を
       本 namespace の forwarding に切り替える
   段階移行 (Workflow_Migration_StageB_Design_Notes.md §4 参照):
     Week 2a:    Stage / Compute / Terminal Node + 単純 Edge を WorkflowNet に変換
     Week 2b:    Decision Node + ParallelSubgraph (AND-split/join) を追加
     Week 2c-1:  inner ノードのネスト解禁、命名 prefix scheme で衝突回避
     Week 2c-2a: Create / Status / State の Shim プレフィクス版 forwarding
     Week 2c-2b: Cancel / List / Trace / RecordHistory forwarding
     Week 2c-2c: RunStateGraph (sync/async 統一 API) forwarding
     Week 2c-2d: $UseWorkflowShim フラグ導入。stategraph.wl の dispatcher
                から本 shim を呼び出せるようにする (デフォルト OFF)。
     Week 2c-3 (本ファイル):
                ShimLLMStateGraphSnapshot / Restore / ListSnapshots を実装。
                v2 専用 (workflow.wl の ClaudeSnapshotWorkflow を呼ぶ)。
                v1 形式は読まない方針 (FormatVersion != 2 を渡されると
                明示的にエラー)。
     Week 2c-4:  既存 111 件テスト統合 (Stage B 受け入れ条件の最終ゲート)
   公開 API (Week 2a):
     ClaudeWorkflowFromStateGraph[graph]    — XSM graph を WorkflowNet 構造に変換
     ClaudeCreateWorkflowFromStateGraph[graph, opts]
                                            — 上記 + ClaudeCreateWorkflowNet で
                                              registry に登録、wid を返す
   依存:
     - ClaudeOrchestrator`Workflow` (WorkflowNet/WorkflowPlace/WorkflowTransition,
       ClaudeCreateWorkflowNet, ClaudeRunWorkflow,
       ClaudeRegisterCompletionHook (Week 2c-2c))
     - ClaudeCode` (なし、Week 2a では不要)
   バージョン: 2026-05-06 (Stage B Week 2c-3)
              v0.8: ShimLLMStateGraphSnapshot / Restore / ListSnapshots を
                    実装。workflow.wl の ClaudeSnapshotWorkflow / 
                    ClaudeRestoreWorkflow / ClaudeListWorkflowSnapshots を
                    呼び出す薄いラッパ。v2 専用 (FormatVersion 2 のみ)。
                    Restore に v1 ディレクトリ (FormatVersion != 2) を渡すと
                    明示的にエラー。stategraph 既存 v1 snapshot との互換性は
                    意図的に切り捨て (新規 snapshot は v2 のみで運用する方針、
                    Imai 先生の判断 2026-05-06)。
                    stategraph.wl の dispatcher も Snapshot 系に拡張する。
              v0.9: Stage C-1 (2026-05-06): $UseWorkflowShim のデフォルトを
                    True に切替。新規 5 ファイル 142/142 BothPass で
                    shim 等価性が完全実証されたため、新実装を default 経路
                    とする。旧実装を使う場合は明示的に False を設定。
              v0.7: $UseWorkflowShim フラグ導入 (Public、デフォルト False)。
                    stategraph.wl の dispatcher が本フラグを参照し、True なら
                    LLMStateGraphCreate / Status / State / Cancel / List /
                    Trace / RecordHistory / RunStateGraph が本 shim 経由で
                    動作する。Snapshot 系 (LLMStateGraphSnapshot/Restore/
                    ListSnapshots) は本フラグの対象外で、Week 2c-3 で別途
                    v1/v2 自動変換を実装する予定。
                    フラグ自体は本ファイルで定義し、stategraph.wl 側は
                    fully qualified (ClaudeOrchestrator`Workflow`Shim`
                    $UseWorkflowShim) で参照する。
              v0.6: ShimRunStateGraph 追加 (Sync/Async 統一 API)。
                    sgRid を ShimLLMStateGraphCreate で生成 → callback を
                    hook adapter で wrap し ClaudeRegisterCompletionHook に
                    登録 → ClaudeRunWorkflow を Sync/Async モードで起動。
                    Sync は polling 不要 (ClaudeRunWorkflow が完了まで
                    ブロック)、Async は polling tick (workflow.wl 側) で
                    進行。callback は workflow 側の completion hook 経由で
                    Sync/Async 両モードで発火される。
                    MaxTotalIterations -> MaxSteps の換算は ×5 (PSG 多用に
                    余裕を持たせる)。
                    戻り値: stategraph 互換 7 キー +
                           shim 拡張 (WorkflowId / WorkflowResult)。
              v0.6 hotfix1: iExtractGlobalState に Payload.Path フォールバック
                    注入。shim handler は Payload.Path のみ更新して
                    GlobalState.Path を更新しないため、ShimLLMStateGraphState
                    の戻り値で Path が常に空になる問題を修正。これは TS33 の
                    fail で発覚 (TS24/TS26 は iExtractStatus 経由で
                    Payload.Path を見ていたので隠れていた)。
              v0.6 hotfix2: hotfix1 だけでは不十分だった (TS33 still fail)。
                    初期 sentinel の GlobalState には "Path" -> {} が明示的に
                    含まれており、Join の右側 (gs) で payloadPath が
                    上書きされていた。gs を KeyDrop["Path"] してから
                    Join することで、Payload.Path が必ず採用されるよう
                    修正。`Payload.Path = source of truth、GlobalState.Path
                    はその投影` という方針を accessor 側で確定。
              v0.5: 旧 LLMStateGraph* API forwarding 第 2 弾。
                    残り 4 つの API を追加:
                      ShimLLMStateGraphCancel[sgRid]
                      ShimLLMStateGraphList[]
                      ShimLLMStateGraphTrace[sgRid]
                      ShimLLMStateGraphRecordHistory[sgRid]
                    $iSGRidWfMap (sgRid -> WorkflowNet 構造) を新設し、
                    Trace 変換時に transition の RuntimeSpec から
                    NodeId/NodeType を引いて XSM 形式に変換する。
                    Workflow event "TransitionFired" を nodeType に応じて
                    "NodeProcessed" / "DecisionMade" / "ParallelStarted" /
                    "ParallelJoined" に変換、Edge 系は "EdgeFired"。
                    RecordHistory は LLMGraph 統合せず、サマリ Association
                    を返すスケルトン (Stage C で本実装予定)。
              v0.4: 旧 LLMStateGraph* API forwarding 第 1 弾。
                    sgRid <-> wid mapping registry 新設、
                    Stage/Compute/Decision Node handler に Stages[nodeId]
                    [Output] 形式の格納を追加 (stategraph 互換性、shim native
                    key は維持)、forwarding 公開 API 3 つ追加:
                      ShimLLMStateGraphCreate[graph, opts]
                      ShimLLMStateGraphStatus[sgRid]
                      ShimLLMStateGraphState[sgRid]
                    stategraph.wl への組み込みは Week 2c-2d まで温存。
              v0.3: inner ノードのネスト解禁 (PSG の中の Decision / PSG)。
                    命名 prefix scheme: 親 PSG の ID を二重 underscore "__"
                    で区切って被せる (place_P__X_in など)。
                    全 helper / partial-net builder に prefix 引数を追加
                    (デフォルト ""、top-level 呼び出しは無修飾と等価)。
                    制約: nodeId に "__" を含めてはならない
                    (PSG の inner ID として使われたとき衝突する)。
              v0.2: Decision Node 変換 (handler 結果を
                    GlobalState["Decisions"][nodeId] に格納) +
                    ParallelSubgraph 変換 (AND-split / AND-join、
                    Multiplicity 機構を活用)。
                    inner ノードのネストはまだ未対応 (Week 2c-1 で解禁)。
              v0.1: Stage / Compute / Terminal Node + 単純 Edge のみ
   ════════════════════════════════════════════════════════════════════ *)
BeginPackage["ClaudeOrchestrator`Workflow`Shim`",
  {"ClaudeOrchestrator`Workflow`"}];

(* ::Subsection:: *)
(* 公開 API usage *)

$WorkflowShimVersion::usage =
  "$WorkflowShimVersion はパッケージのバージョン文字列を返す。";

$UseWorkflowShim::usage =
  "$UseWorkflowShim は ClaudeOrchestrator_stategraph.wl の Public API\n" <>
  "(LLMStateGraphCreate, LLMStateGraphStatus, LLMStateGraphState,\n" <>
  "LLMStateGraphCancel, LLMStateGraphList, LLMStateGraphTrace,\n" <>
  "LLMStateGraphRecordHistory, RunStateGraph) を shim 経由で実行するか、\n" <>
  "それとも従来の stategraph 実装で実行するかを切り替える Boolean フラグ。\n\n" <>
  "  True (Stage C-1 \\:4ee5\\:964d\\:306e\\:65e2\\:5b9a\\:5024): 本 shim 経由で WorkflowNet engine 上で実行\n" <>
  "  False             : 従来の stategraph 実装 (互換性確保用、明示設定で利用可)\n\n" <>
  "Week 2c-2d で導入、Stage B Week 2c-4 prelude で 142/142 BothPass 達成、\n" <>
  "Stage C-1 (2026-05-06) でデフォルトを True に切替。\n" <>
  "Snapshot 系 API (LLMStateGraphSnapshot/Restore/ListSnapshots) は\n" <>
  "Week 2c-3 で本フラグの対象に追加済 (shim 経路は v2 専用)。\n\n" <>
  "Stage C-3c (2026-05-06): \\:65b0\\:540d $UseLegacyStategraph \\:3092\\:5c0e\\:5165\\:3002\n" <>
  "$UseWorkflowShim \\:306f deprecated alias \\:3068\\:3057\\:3066\\:6b8b\\:308b\\:3002\n" <>
  "\\:65b0\\:898f\\:30b3\\:30fc\\:30c9\\:306f $UseLegacyStategraph (default = False) \\:3092\\:4f7f\\:7528\\:3057\\:3066\\:304f\\:3060\\:3055\\:3044\\:3002";

$UseLegacyStategraph::usage =
  "$UseLegacyStategraph (Stage C-3c, 2026-05-06 \\:5c0e\\:5165) \\:306f\n" <>
  "ClaudeOrchestrator_stategraph.wl \\:306e Public API \\:3092 legacy \\:5b9f\\:88c5\\:3067\n" <>
  "\\:5b9f\\:884c\\:3059\\:308b\\:304b\\:3001\\:65b0\\:5b9f\\:88c5 (ClaudeOrchestrator`Workflow` \\:7d4c\\:7531) \\:3067\n" <>
  "\\:5b9f\\:884c\\:3059\\:308b\\:304b\\:3092\\:5207\\:308a\\:66ff\\:3048\\:308b Boolean \\:30d5\\:30e9\\:30b0\\:3002\n\n" <>
  "  False (\\:65e2\\:5b9a\\:5024): \\:65b0\\:5b9f\\:88c5 (ClaudeOrchestrator`Workflow` \\:7d4c\\:7531)\n" <>
  "  True            : legacy \\:5b9f\\:88c5 (ClaudeOrchestrator_stategraph_legacy.wl \\:7d4c\\:7531)\n\n" <>
  "\\:65e7\\:540d $UseWorkflowShim \\:3068\\:306f\\:9006\\:306e\\:610f\\:5473\\:3092\\:6301\\:3064:\n" <>
  "  $UseLegacyStategraph = !$UseWorkflowShim\n\n" <>
  "\\:65b0\\:898f\\:30b3\\:30fc\\:30c9\\:306f\\:5fc5\\:305a\\:3053\\:3061\\:3089\\:3092\\:4f7f\\:7528\\:3059\\:308b\\:3053\\:3068\\:3002\n" <>
  "\\:65e7\\:540d\\:306f Stage D \\:3067\\:524a\\:9664\\:4e88\\:5b9a\\:3002";

ClaudeWorkflowFromStateGraph::usage =
  "ClaudeWorkflowFromStateGraph[graph_Association] は LLMStateGraph 形式の\n" <>
  "graph (Nodes/Edges/InitialNode/TerminalNodes) を WorkflowNet 構造に変換し、\n" <>
  "WorkflowNet Association を返す (ClaudeCreateWorkflowNet には登録しない)。\n\n" <>
  "対応 Node 型 (Week 2c-1):\n" <>
  "  Stage / Compute / Decision / Terminal /\n" <>
  "  ParallelSubgraph (inner に Stage/Compute/Decision/PSG を許容)\n\n" <>
  "制約: nodeId に \"__\" (二重 underscore) を含めないこと\n" <>
  "       (PSG inner のとき命名衝突する)\n\n" <>
  "戻り値: WorkflowNet Association";

ClaudeCreateWorkflowFromStateGraph::usage =
  "ClaudeCreateWorkflowFromStateGraph[graph_Association, opts:OptionsPattern[]]\n" <>
  "は ClaudeWorkflowFromStateGraph + ClaudeCreateWorkflowNet を一括実行し、\n" <>
  "WorkflowId を返す。Submit / Run は別ステップ (LLMStateGraphCreate の\n" <>
  "shim としては Week 2c で別途完成させる)。\n\n" <>
  "Options:\n" <>
  "  \"Description\" -> \"\"\n" <>
  "  \"ValidateStrict\" -> True";

(* ── Week 2c-2a: 旧 LLMStateGraph* API の forwarding ── *)

ShimLLMStateGraphCreate::usage =
  "ShimLLMStateGraphCreate[graph_Association, opts:OptionsPattern[]] は\n" <>
  "LLMStateGraphCreate と等価な動作を WorkflowNet 経由で行う forwarding API。\n" <>
  "WorkflowNet を生成・登録し、XSMSentinel token を投入してから、\n" <>
  "stategraph 形式の runtimeId (\"sg-...\") を返す。\n\n" <>
  "Options:\n" <>
  "  \"InitialContext\" -> <||>     (XSMSentinel token の GlobalState 初期値)\n" <>
  "  \"MaxTotalIterations\" -> 30\n\n" <>
  "戻り値: sgRid (String、\"sg-\" + wid 末尾 12 文字)";

ShimLLMStateGraphStatus::usage =
  "ShimLLMStateGraphStatus[sgRid_String] は LLMStateGraphStatus と同等の\n" <>
  "Association を返す forwarding API。内部で sgRid -> wid を解決し、\n" <>
  "ClaudeWorkflowStatus + ClaudeWorkflowState から stategraph 形式に変換する。\n\n" <>
  "戻り値のキー: RuntimeId / Status / CurrentNode / TotalIterations /\n" <>
  "             MaxTotalIterations / Path / ActiveSubDAGId / FailureReason /\n" <>
  "             StartTime / EndTime / ElapsedSec";

ShimLLMStateGraphState::usage =
  "ShimLLMStateGraphState[sgRid_String] は LLMStateGraphState と同等の\n" <>
  "GlobalState Association を返す forwarding API。\n" <>
  "stategraph 慣習の Stages[nodeId][Output] 構造も含まれる\n" <>
  "(shim native のフラット merge と両立)。";

(* ── Week 2c-2b: 残り 4 つの forwarding API ── *)

ShimLLMStateGraphCancel::usage =
  "ShimLLMStateGraphCancel[sgRid_String] は LLMStateGraphCancel と等価な\n" <>
  "動作を ClaudeCancelWorkflow 経由で行う forwarding API。\n" <>
  "内部で sgRid -> wid を解決し、wid に対する Cancel を呼ぶ。\n\n" <>
  "戻り値: sgRid (キャンセル成功)";

ShimLLMStateGraphList::usage =
  "ShimLLMStateGraphList[] は ShimLLMStateGraphCreate で登録された\n" <>
  "全 sgRid のリストを返す。LLMStateGraphList と等価。";

ShimLLMStateGraphTrace::usage =
  "ShimLLMStateGraphTrace[sgRid_String] は LLMStateGraphTrace と等価な\n" <>
  "trace event リストを返す forwarding API。\n" <>
  "ClaudeWorkflowTrace の TransitionFired event を nodeType に応じて\n" <>
  "stategraph 形式 (NodeProcessed / DecisionMade / ParallelStarted /\n" <>
  "ParallelJoined / EdgeFired) に変換する。\n" <>
  "先頭に GraphCreated event を prepend する。\n\n" <>
  "戻り値: List of Association ({\"Type\", \"Time\", \"NodeId\", ...})";

ShimLLMStateGraphRecordHistory::usage =
  "ShimLLMStateGraphRecordHistory[sgRid_String] は workflow の状態と\n" <>
  "trace を集約した Association を返す forwarding API。\n" <>
  "Week 2c-2b ではスケルトン実装 (LLMGraph への記録は Stage C で本実装)。\n\n" <>
  "戻り値: Association(RuntimeId, WorkflowId, Status, Path, Stages, Trace,\n" <>
  "                    TraceEventCount, Recorded, RecordedAt)";

(* ── Week 2c-2c: RunStateGraph (sync/async 統一 API) ── *)

ShimRunStateGraph::usage =
  "ShimRunStateGraph[graph_Association, opts:OptionsPattern[]] は\n" <>
  "RunStateGraph と等価な動作を WorkflowNet 経由で行う forwarding API。\n" <>
  "デフォルトは sync (Async -> False) で、ShimLLMStateGraphCreate で\n" <>
  "WorkflowNet を生成・token 投入後、ClaudeRunWorkflow Sync を呼び\n" <>
  "完了まで block して結果 Association を返す。\n" <>
  "Async -> True なら ClaudeRunWorkflow Async で起動し、sgRid だけを\n" <>
  "即返却する (LLMStateGraphCreate と同じ挙動)。\n\n" <>
  "OnGraphComplete callback は Sync/Async 両モードで発火される。\n" <>
  "内部で hook adapter を作り、ClaudeRegisterCompletionHook で登録する\n" <>
  "ことで、workflow 完了時 (Sync 戻り値直前または Async tick 完了検出時)\n" <>
  "に stategraph runtime 形式 Association を引数として callback が呼ばれる。\n\n" <>
  "Options:\n" <>
  "  \"Async\"              -> False        (sync で完了待ち)\n" <>
  "  \"MaxTotalIterations\" -> 30          (XSM ノード実行回数の上限)\n" <>
  "  \"MaxWait\"            -> 600          (Sync 時の上限秒)\n" <>
  "  \"PollInterval\"       -> 0.5          (Async 後段 ClaudeWaitWorkflow 用)\n" <>
  "  \"Profile\"            -> \"Generic\"\n" <>
  "  \"Notebook\"           -> Automatic\n" <>
  "  \"InitialContext\"     -> <||>\n" <>
  "  \"OnGraphComplete\"    -> None         (Function、Sync/Async 共通発火)\n" <>
  "  \"Description\"        -> \"\"\n\n" <>
  "MaxTotalIterations -> MaxSteps 換算は ×5 (PSG 多用ケースに余裕)。\n\n" <>
  "Sync 戻り値: <|\"RuntimeId\", \"Status\", \"GlobalState\", \"Path\",\n" <>
  "              \"ElapsedSec\", \"FailureReason\", \"Trace\",\n" <>
  "              \"WorkflowId\", \"WorkflowResult\"|>\n" <>
  "Async 戻り値: sgRid (String)";

(* ── Week 2c-3: Snapshot 系 forwarding ── *)

ShimLLMStateGraphSnapshot::usage =
  "ShimLLMStateGraphSnapshot[sgRid_String, opts:OptionsPattern[]] は\n" <>
  "LLMStateGraphSnapshot と等価な動作を WorkflowNet 経由で行う\n" <>
  "forwarding API。内部で sgRid -> wid を解決し、\n" <>
  "ClaudeSnapshotWorkflow を呼んで FormatVersion 2 で保存する。\n\n" <>
  "Options:\n" <>
  "  \"SnapshotDir\" -> Automatic   (= $ClaudeWorkflowSnapshotDir)\n" <>
  "  \"Description\" -> \"\"\n\n" <>
  "戻り値: <|\"RuntimeId\", \"WorkflowId\", \"SnapshotDir\",\n" <>
  "         \"FormatVersion\" -> 2, \"SavedAt\"|>";

ShimLLMStateGraphRestore::usage =
  "ShimLLMStateGraphRestore[snapDir_String, opts:OptionsPattern[]] は\n" <>
  "LLMStateGraphRestore と等価な動作を WorkflowNet 経由で行う\n" <>
  "forwarding API。ClaudeRestoreWorkflow を呼んで v2 として復元する。\n\n" <>
  "v1 形式 (FormatVersion != 2) の snapshot ディレクトリを渡された場合は\n" <>
  "明示的にエラー (Imai 先生の判断 2026-05-06、Week 2c-3 設計判断)。\n\n" <>
  "Options:\n" <>
  "  \"AsNewWorkflowId\" -> True  (新しい wid を発行、元 wid は OriginalWid に保持)\n\n" <>
  "戻り値: <|\"RuntimeId\" -> 新しい sgRid, \"WorkflowId\",\n" <>
  "         \"OriginalWid\", \"OriginalRuntimeId\",\n" <>
  "         \"Restored\" -> True, \"FormatVersion\" -> 2, \"SnapshotDir\"|>\n" <>
  "v1 を渡された場合: $Failed (Throw 経由)";

ShimLLMStateGraphListSnapshots::usage =
  "ShimLLMStateGraphListSnapshots[opts:OptionsPattern[]] は\n" <>
  "LLMStateGraphListSnapshots と等価な動作を WorkflowNet 経由で行う\n" <>
  "forwarding API。ClaudeListWorkflowSnapshots を呼んで v2 ディレクトリ\n" <>
  "($ClaudeWorkflowSnapshotDir 配下) を列挙する。\n\n" <>
  "stategraph 既存 v1 ディレクトリ ($ClaudeSnapshots 配下) は対象外。\n\n" <>
  "Options:\n" <>
  "  \"SnapshotDir\" -> Automatic\n\n" <>
  "戻り値: Dataset (各エントリ: SnapshotDir / WorkflowId / FormatVersion /\n" <>
  "                              Description / SavedAt)";

(* ::Subsection:: *)
(* Private *)

Begin["`Private`"];

ClaudeOrchestrator`Workflow`Shim`$WorkflowShimVersion =
  "2026-05-06-stage-C-3c";

(* $UseWorkflowShim / $UseLegacyStategraph: Public フラグ
   
   Stage C-1 (2026-05-06): $UseWorkflowShim のデフォルトを True に切替。
   Stage C-3c (2026-05-06): $UseLegacyStategraph (新名、default = False) を導入。
                            $UseWorkflowShim は deprecated alias として残る。
                            両者の関係: $UseLegacyStategraph = !$UseWorkflowShim
   
   実装方針:
     - $UseWorkflowShim は通常の OwnValue (= Set すると即座に値が入る)。
       dispatcher やテストはこのフラグを直接参照する。
     - $UseLegacyStategraph は SetDelayed (:=) で「常に !$UseWorkflowShim を返す」
       動的計算式として定義 (= Read 時に毎回計算)。
       Set 経路は TagSet hook で intercept し、$UseWorkflowShim の値を裏で更新。
     - これにより両フラグが常に整合した状態を維持。
   
   新規コードは $UseLegacyStategraph を使用すること。
   旧名の $UseWorkflowShim は Stage D で削除予定。 *)

If[!ValueQ[ClaudeOrchestrator`Workflow`Shim`$UseWorkflowShim],
  ClaudeOrchestrator`Workflow`Shim`$UseWorkflowShim = True];

(* $UseLegacyStategraph: Read は SetDelayed で動的計算、Set は TagSet hook で intercept *)
ClaudeOrchestrator`Workflow`Shim`$UseLegacyStategraph := 
  !TrueQ[ClaudeOrchestrator`Workflow`Shim`$UseWorkflowShim];

ClaudeOrchestrator`Workflow`Shim`$UseLegacyStategraph /:
  Set[ClaudeOrchestrator`Workflow`Shim`$UseLegacyStategraph, val_] :=
    (ClaudeOrchestrator`Workflow`Shim`$UseWorkflowShim = !TrueQ[val]; val);

(* ::Subsubsection:: *)
(* iPlaceInName / iPlaceOutName / iTransNodeName / iTransEdgeName 命名規則 *)

(* ::Subsubsection:: *)
(* 命名規則 helpers
   prefix は親 PSG の chain を表す。top-level なら "" (空)、
   PSG P の inner なら "P__"、PSG P の inner PSG Q の inner なら "P__Q__"。
   "__" (二重 underscore) を区切り文字として使う。
   nodeId に "__" を含めてはならない (制約)。 *)

iPlaceInName[nodeId_String, prefix_String:""]   :=
  "place_" <> prefix <> nodeId <> "_in";
iPlaceOutName[nodeId_String, prefix_String:""]  :=
  "place_" <> prefix <> nodeId <> "_out";
iTransNodeName[nodeId_String, prefix_String:""] :=
  "trans_" <> prefix <> nodeId <> "_handle";
iTransEdgeName[from_String, to_String, prefix_String:""] :=
  "edge_" <> prefix <> from <> "_to_" <> to;
iPSGSplitName[nodeId_String, prefix_String:""]  :=
  "psg_" <> prefix <> nodeId <> "_split";
iPSGJoinName[nodeId_String, prefix_String:""]   :=
  "psg_" <> prefix <> nodeId <> "_join";

(* nodeId 制約のチェック *)
iValidateNodeId[nodeId_String] :=
  If[StringContainsQ[nodeId, "__"],
    Throw[$Failed,
      "InvalidNodeId: \"" <> nodeId <> "\" contains \"__\". " <>
      "nodeId must not contain double underscore (reserved for PSG nesting)."]
  ];

(* ::Subsubsection:: *)
(* iNodeToPartialNet: 1 Node → places + transitions の部分 net *)

(* Stage / Compute Node:
     place_N_in (前段から token を受ける)
     place_N_out (handler 完了後の token 置き場)
     trans_N_handle (handler を Executor PureFunction で実行)
   Terminal Node:
     place_N_in のみ (sink、final places の 1 つ) *)

iNodeToPartialNet[node_Association, prefix_String:""] :=
  Module[{nodeId, type},
    nodeId = node[["Id"]];
    iValidateNodeId[nodeId];
    type   = node[["Type"]];
    
    Switch[type,
      "Stage" | "Compute",
        iStageOrComputeNodeToPartialNet[node, prefix],
      "Terminal",
        iTerminalNodeToPartialNet[node, prefix],
      "Decision",
        iDecisionNodeToPartialNet[node, prefix],
      "ParallelSubgraph",
        iParallelSubgraphToPartialNet[node, prefix],
      _,
        Throw[$Failed,
          "UnsupportedNodeType: " <> ToString[type] <>
          " (id=" <> nodeId <> "). Week 2c-1 supports " <>
          "Stage/Compute/Decision/Terminal/ParallelSubgraph."]
    ]
  ];

iStageOrComputeNodeToPartialNet[node_Association, prefix_String:""] :=
  Module[{nodeId = node[["Id"]],
          handler = Lookup[node, "Handler", Identity],
          type    = node[["Type"]]},
    
    <|"Places" -> <|
        iPlaceInName[nodeId, prefix] ->
          WorkflowPlace[iPlaceInName[nodeId, prefix]],
        iPlaceOutName[nodeId, prefix] ->
          WorkflowPlace[iPlaceOutName[nodeId, prefix]]
      |>,
      "Transitions" -> <|
        iTransNodeName[nodeId, prefix] ->
          WorkflowTransition[iTransNodeName[nodeId, prefix],
            "InputArcs"  -> {<|"Place" -> iPlaceInName[nodeId, prefix],
                                "Multiplicity" -> 1|>},
            "OutputArcs" -> {<|"Place" -> iPlaceOutName[nodeId, prefix],
                                "Multiplicity" -> 1,
                                "TokenKind"    -> "XSMSentinel"|>},
            "Executor"   -> "PureFunction",
            "RuntimeSpec" -> <|
              "Handler"  -> iMakeNodeHandler[nodeId, handler, type, prefix],
              "NodeId"   -> nodeId,
              "NodeType" -> type
            |>
          ]
      |>
    |>
  ];

iTerminalNodeToPartialNet[node_Association, prefix_String:""] :=
  Module[{nodeId = node[["Id"]]},
    <|"Places" -> <|
        iPlaceInName[nodeId, prefix] ->
          WorkflowPlace[iPlaceInName[nodeId, prefix],
            "Description" ->
              "Terminal node sink (status: " <>
              Lookup[node, "Status", "Done"] <> ")"]
      |>,
      "Transitions" -> <||>  (* Terminal は handler を持たない *)
    |>
  ];

(* ::Subsubsection:: *)
(* Decision Node (Week 2b)
   Stage / Compute Node とほぼ同じ構造だが、handler 戻り値
   <|"Pass" -> Bool, "Feedback" -> ..., ...|> を GlobalState["Decisions"]
   [nodeId] に隔離格納する。複数の Decision が衝突しない。 *)

iDecisionNodeToPartialNet[node_Association, prefix_String:""] :=
  Module[{nodeId = node[["Id"]],
          handler = Lookup[node, "Handler", Identity]},
    <|"Places" -> <|
        iPlaceInName[nodeId, prefix]  ->
          WorkflowPlace[iPlaceInName[nodeId, prefix]],
        iPlaceOutName[nodeId, prefix] ->
          WorkflowPlace[iPlaceOutName[nodeId, prefix]]
      |>,
      "Transitions" -> <|
        iTransNodeName[nodeId, prefix] ->
          WorkflowTransition[iTransNodeName[nodeId, prefix],
            "InputArcs"  -> {<|"Place" -> iPlaceInName[nodeId, prefix],
                                "Multiplicity" -> 1|>},
            "OutputArcs" -> {<|"Place" -> iPlaceOutName[nodeId, prefix],
                                "Multiplicity" -> 1,
                                "TokenKind"    -> "XSMSentinel"|>},
            "Executor"   -> "PureFunction",
            "RuntimeSpec" -> <|
              "Handler"  -> iMakeDecisionHandler[nodeId, handler, prefix],
              "NodeId"   -> nodeId,
              "NodeType" -> "Decision"
            |>
          ]
      |>
    |>
  ];

iMakeDecisionHandler[nodeId_String, handler_, prefix_String:""] :=
  Function[binding,
    Module[{inToken, gs, path, decisionResult,
            decisions, newGS, newPayload,
            stages, newStages},
      
      inToken = binding[[iPlaceInName[nodeId, prefix]]];
      gs      = Lookup[inToken[["Payload"]], "GlobalState", <||>];
      path    = Lookup[inToken[["Payload"]], "Path", {}];
      
      (* Handler 呼び出し (None / Identity は Pass=True とみなす) *)
      decisionResult = Which[
        handler === None || handler === Identity,
          <|"Pass" -> True|>,
        Head[handler] === Function,
          Quiet @ Check[
            handler[gs],
            <|"Pass" -> False, "Reason" -> "HandlerError"|>
          ],
        True,
          <|"Pass" -> True|>
      ];
      
      (* AssociationQ でなければデフォルト構造に正規化 *)
      If[!AssociationQ[decisionResult],
        decisionResult = <|"Pass" -> TrueQ[decisionResult]|>
      ];
      
      (* shim native: GlobalState["Decisions"][nodeId] に格納 *)
      decisions = Lookup[gs, "Decisions", <||>];
      newGS     = Append[gs, "Decisions" ->
        Append[decisions, nodeId -> decisionResult]];
      
      (* stategraph 互換: Stages[nodeId][Output] にも格納 (Week 2c-2a) *)
      stages    = Lookup[newGS, "Stages", <||>];
      newStages = Append[stages, nodeId -> <|
        "Output"  -> decisionResult,
        "EndTime" -> AbsoluteTime[]
      |>];
      newGS     = Append[newGS, "Stages" -> newStages];
      
      newPayload = Join[
        Lookup[inToken, "Payload", <||>],
        <|"GlobalState" -> newGS,
          "Path"        -> Append[path, nodeId]|>
      ];
      
      <|"Payload" -> newPayload|>
    ]
  ];

(* ::Subsubsection:: *)
(* ParallelSubgraph (Week 2b)
   設計確定文書 §4.3 の AND-split / AND-join。
   
   構造:
     place_PSG_in
       ↓ trans_PSG_split (1 input → N outputs、各 inner_X_in に同じ payload)
       ├→ place_X1_in → place_X1_out (各 inner DAG が独立に走る)
       ├→ place_X2_in → place_X2_out
       └→ ...
       ↓ trans_PSG_join (N inputs → 1 output、全 inner が完了するまで待つ)
     place_PSG_out
   
   制約 (Week 2b): inner ノードは Stage / Compute のみ。
                   Decision / 入れ子 PSG は Week 2c 以降。 *)

iParallelSubgraphToPartialNet[node_Association, prefix_String:""] :=
  Module[{nodeId, innerNodes, innerIds, innerPrefix, innerNets,
          allInnerPlaces, allInnerTrans, splitTrans, joinTrans,
          joinFn, outerPlaces, allowedInnerTypes},
    
    nodeId      = node[["Id"]];
    innerNodes  = Lookup[node, "InnerNodes", <||>];
    joinFn      = Lookup[node, "JoinFn", None];
    innerPrefix = prefix <> nodeId <> "__";    (* "P__" or "P__Q__" *)
    
    If[!AssociationQ[innerNodes] || Length[innerNodes] === 0,
      Throw[$Failed,
        "ParallelSubgraphMissingInnerNodes: " <> nodeId]
    ];
    
    innerIds = Keys[innerNodes];
    
    (* Inner Node を partial net に再帰的に展開。
       Week 2c-1 で Stage / Compute / Decision / ParallelSubgraph を許容
       (Terminal は inner として意味がないので除外)。 *)
    allowedInnerTypes = {"Stage", "Compute", "Decision",
                          "ParallelSubgraph"};
    
    innerNets = KeyValueMap[
      Function[{innerId, innerNode},
        Module[{innerType = Lookup[innerNode, "Type", "?"]},
          If[!MemberQ[allowedInnerTypes, innerType],
            Throw[$Failed,
              "PSGInnerNodeUnsupported: " <> nodeId <> "/" <> innerId <>
              " has Type=" <> innerType <>
              ". Allowed inner types: " <>
              StringRiffle[allowedInnerTypes, ", "]]
          ];
          (* 親 PSG の prefix を被せて再帰展開 *)
          iNodeToPartialNet[innerNode, innerPrefix]
        ]
      ],
      innerNodes
    ];
    
    allInnerPlaces = Join @@ Map[#[["Places"]] &, innerNets];
    allInnerTrans  = Join @@ Map[#[["Transitions"]] &, innerNets];
    
    (* trans_split: outer の place_in (prefix 付き) →
       各 inner の place_in (innerPrefix 付き)。
       Inner ノードの種類によって適切な place_in を選ぶ:
         Stage/Compute/Decision: place_<innerPrefix><innerId>_in
         PSG:                    place_<innerPrefix><innerId>_in
         (どちらも iPlaceInName[innerId, innerPrefix] と等価) *)
    splitTrans = WorkflowTransition[iPSGSplitName[nodeId, prefix],
      "InputArcs"  -> {<|"Place" -> iPlaceInName[nodeId, prefix],
                          "Multiplicity" -> 1|>},
      "OutputArcs" -> Map[
        Function[innerId,
          <|"Place"        -> iPlaceInName[innerId, innerPrefix],
            "Multiplicity" -> 1,
            "TokenKind"    -> "XSMSentinel"|>
        ],
        innerIds
      ],
      "Executor"    -> "PureFunction",
      "RuntimeSpec" -> <|
        "Handler"  -> iMakePSGSplitHandler[nodeId, prefix],
        "NodeId"   -> nodeId,
        "NodeType" -> "ParallelSubgraph-split"
      |>
    ];
    
    (* trans_join: 各 inner の place_out (innerPrefix 付き) → outer の place_out。
       全 inner の出口 place の token が揃うまで fire しない (古典 AND-join)。 *)
    joinTrans = WorkflowTransition[iPSGJoinName[nodeId, prefix],
      "InputArcs"  -> Map[
        Function[innerId,
          <|"Place"        -> iPlaceOutName[innerId, innerPrefix],
            "Multiplicity" -> 1|>
        ],
        innerIds
      ],
      "OutputArcs" -> {<|"Place"        -> iPlaceOutName[nodeId, prefix],
                          "Multiplicity" -> 1,
                          "TokenKind"    -> "XSMSentinel"|>},
      "Executor"    -> "PureFunction",
      "RuntimeSpec" -> <|
        "Handler"  -> iMakePSGJoinHandler[nodeId, innerIds, joinFn,
                                            prefix, innerPrefix],
        "NodeId"   -> nodeId,
        "NodeType" -> "ParallelSubgraph-join"
      |>
    ];
    
    outerPlaces = <|
      iPlaceInName[nodeId, prefix] ->
        WorkflowPlace[iPlaceInName[nodeId, prefix]],
      iPlaceOutName[nodeId, prefix] ->
        WorkflowPlace[iPlaceOutName[nodeId, prefix]]
    |>;
    
    <|"Places" -> Join[outerPlaces, allInnerPlaces],
      "Transitions" -> Join[
        <|iPSGSplitName[nodeId, prefix] -> splitTrans,
          iPSGJoinName[nodeId, prefix]  -> joinTrans|>,
        allInnerTrans
      ]
    |>
  ];

(* PSG split handler: 受け取った token の Payload をそのまま渡す。
   iProduceOutputTokens が各 output arc に同じ payload を持つ token を作る。 *)
iMakePSGSplitHandler[nodeId_String, prefix_String:""] :=
  Function[binding,
    Module[{inToken, payload, gs, path, newPayload},
      inToken = binding[[iPlaceInName[nodeId, prefix]]];
      payload = Lookup[inToken, "Payload", <||>];
      gs      = Lookup[payload, "GlobalState", <||>];
      path    = Lookup[payload, "Path", {}];
      
      (* split 時点で Path に nodeId を append (entry mark) *)
      newPayload = Append[payload,
        "Path" -> Append[path, nodeId <> ":split"]];
      
      <|"Payload" -> newPayload|>
    ]
  ];

(* PSG join handler: 全 inner の token を集約して 1 つの token を返す。
   innerPrefix は inner ノードの命名 prefix で、binding から各 inner の
   token を引き出すときに使う。 *)
iMakePSGJoinHandler[nodeId_String, innerIds_List, joinFn_,
                     prefix_String:"", innerPrefix_String:""] :=
  Function[binding,
    Module[{innerPayloads, innerGS, mergedGS, joinUpdate, finalGS,
            paths, finalPath, newPayload, effInnerPrefix},
      
      effInnerPrefix = If[innerPrefix === "",
        prefix <> nodeId <> "__",
        innerPrefix];
      
      (* 各 inner の Payload を取り出す *)
      innerPayloads = Association @@ Map[
        Function[innerId,
          innerId -> Lookup[
            Lookup[binding, iPlaceOutName[innerId, effInnerPrefix], <||>],
            "Payload", <||>]
        ],
        innerIds
      ];
      
      (* 各 inner の GlobalState を順次 Join (右側が優先) *)
      innerGS = Map[Lookup[#, "GlobalState", <||>] &, innerPayloads];
      mergedGS = Fold[Join, <||>, Values[innerGS]];
      
      (* JoinFn があれば呼んで GlobalState を追加更新。
         signature: joinFn[<|innerId -> innerPayload|>] -> Association *)
      joinUpdate = Which[
        joinFn === None || joinFn === Identity,
          <||>,
        Head[joinFn] === Function,
          Quiet @ Check[joinFn[innerPayloads], <||>],
        True,
          <||>
      ];
      
      finalGS = If[AssociationQ[joinUpdate],
        Join[mergedGS, joinUpdate],
        mergedGS];
      
      (* Path: 全 inner の Path を flatten + nodeId を末尾に *)
      paths = Map[Lookup[#, "Path", {}] &, Values[innerPayloads]];
      finalPath = Append[Flatten[paths], nodeId <> ":join"];
      
      newPayload = <|
        "GlobalState" -> finalGS,
        "Path"        -> finalPath
      |>;
      
      <|"Payload" -> newPayload|>
    ]
  ];

(* ::Subsubsection:: *)
(* iMakeNodeHandler: Node の Handler を transition handler に包む *)

(* XSMSentinel token は Payload に "GlobalState" / "Path" を持つ。
   Node handler は GlobalState (Association) を受け取り、追加で merge する
   Association を返すものと仮定 (= ClaudeOrchestrator_stategraph の Stage/Compute
   の handler 慣習)。*)

iMakeNodeHandler[nodeId_String, handler_, type_String,
                 prefix_String:""] :=
  Function[binding,
    Module[{inToken, gs, path, newGS, newPayload, mergedGS,
            stages, newStages, output},
      
      (* binding は <|place_in -> token|>。Multiplicity=1 なので単一 Association *)
      inToken = binding[[iPlaceInName[nodeId, prefix]]];
      gs      = Lookup[inToken[["Payload"]], "GlobalState", <||>];
      path    = Lookup[inToken[["Payload"]], "Path", {}];
      
      (* Handler 呼び出し。None / Identity の場合はパススルー *)
      newGS = Which[
        handler === None || handler === Identity,
          <||>,
        Head[handler] === Function,
          Quiet @ Check[handler[gs], <||>],
        True,
          <||>
      ];
      
      output = If[AssociationQ[newGS], newGS, <||>];
      
      (* shim native: GlobalState を直接 merge *)
      mergedGS = If[AssociationQ[newGS], Join[gs, newGS], gs];
      
      (* stategraph 互換: Stages[nodeId][Output] 形式にも格納 (Week 2c-2a) *)
      stages    = Lookup[mergedGS, "Stages", <||>];
      newStages = Append[stages, nodeId -> <|
        "Output"  -> output,
        "EndTime" -> AbsoluteTime[]
      |>];
      mergedGS  = Append[mergedGS, "Stages" -> newStages];
      
      newPayload = Join[
        Lookup[inToken, "Payload", <||>],
        <|"GlobalState" -> mergedGS,
          "Path"        -> Append[path, nodeId]|>
      ];
      
      <|"Payload" -> newPayload|>
    ]
  ];

(* ::Subsubsection:: *)
(* iEdgeToTransition: Edge → guard 付き transition *)

(* Edge は place_From_out → place_To_in に token を移動する transition。
   Guard は edge["Condition"] が True 以外なら GlobalState を見て評価。
   PayloadFn はある場合のみ GlobalState を更新する handler を作る。*)

iEdgeToTransition[edge_Association] :=
  Module[{from, to, condFn, payloadFn, priority},
    from      = edge[["From"]];
    to        = edge[["To"]];
    condFn    = Lookup[edge, "Condition", (True &)];
    payloadFn = Lookup[edge, "PayloadFn", (<||> &)];
    priority  = Lookup[edge, "Priority", 0];
    
    iTransEdgeName[from, to] -> WorkflowTransition[iTransEdgeName[from, to],
      "InputArcs"  -> {<|"Place" -> iPlaceOutName[from],
                          "Multiplicity" -> 1|>},
      "OutputArcs" -> {<|"Place" -> iPlaceInName[to],
                          "Multiplicity" -> 1,
                          "TokenKind"    -> "XSMSentinel"|>},
      "Guard"      -> iMakeEdgeGuard[from, condFn],
      "Executor"   -> "PureFunction",
      "RuntimeSpec" -> <|
        "Handler"   -> iMakeEdgePayloadHandler[from, payloadFn],
        "EdgeFrom"  -> from,
        "EdgeTo"    -> to
      |>,
      "Priority" -> priority
    ]
  ];

iMakeEdgeGuard[from_String, condFn_] :=
  If[condFn === (True &) || condFn === True,
    None,    (* True しか返さない条件は guard 無し扱い *)
    Function[binding,
      Module[{token, gs},
        token = Lookup[binding, iPlaceOutName[from], <||>];
        gs    = Lookup[Lookup[token, "Payload", <||>], "GlobalState", <||>];
        TrueQ @ Quiet @ Check[condFn[gs], False]
      ]
    ]
  ];

iMakeEdgePayloadHandler[from_String, payloadFn_] :=
  Function[binding,
    Module[{inToken, gs, edgeUpdate, mergedGS, newPayload},
      inToken = binding[[iPlaceOutName[from]]];
      gs      = Lookup[inToken[["Payload"]], "GlobalState", <||>];
      
      edgeUpdate = If[payloadFn === (<||> &),
        <||>,
        Quiet @ Check[payloadFn[gs], <||>]
      ];
      
      mergedGS   = If[AssociationQ[edgeUpdate],
                     Join[gs, edgeUpdate],
                     gs];
      newPayload = Join[
        Lookup[inToken, "Payload", <||>],
        <|"GlobalState" -> mergedGS|>
      ];
      
      <|"Payload" -> newPayload|>
    ]
  ];

(* ::Subsubsection:: *)
(* ClaudeWorkflowFromStateGraph (Public) *)

ClaudeWorkflowFromStateGraph[graph_Association] :=
  Module[{nodes, edges, initialNode, terminalNodes,
          partialNets, edgeTransitions, allPlaces, allTransitions,
          sourcePlace, finalPlaces},
    
    (* 1. graph の必須キー検証 *)
    nodes         = Lookup[graph, "Nodes", $Failed];
    edges         = Lookup[graph, "Edges", {}];
    initialNode   = Lookup[graph, "InitialNode", $Failed];
    terminalNodes = Lookup[graph, "TerminalNodes", {}];
    
    If[!AssociationQ[nodes],
      Throw[$Failed, "GraphMissingNodes: graph[\"Nodes\"] must be Association"]
    ];
    If[initialNode === $Failed || !KeyExistsQ[nodes, initialNode],
      Throw[$Failed, "GraphMissingInitialNode: " <> ToString[initialNode]]
    ];
    
    (* 2. 各 Node を partial net に展開 *)
    partialNets = Map[iNodeToPartialNet, Values[nodes]];
    
    (* 3. Edge を transition に変換 (Association of name -> transition) *)
    edgeTransitions = Association @@ Map[iEdgeToTransition, edges];
    
    (* 4. Places と Transitions を merge *)
    allPlaces = Join @@ Map[#[["Places"]] &, partialNets];
    allTransitions = Join[
      Join @@ Map[#[["Transitions"]] &, partialNets],
      edgeTransitions
    ];
    
    (* 5. SourcePlace = initial node の place_in
          FinalPlaces  = terminal nodes の place_in (各 terminal が単独 sink) *)
    sourcePlace = iPlaceInName[initialNode];
    finalPlaces = Map[iPlaceInName, terminalNodes];
    
    (* 6. WorkflowNet 構築 *)
    WorkflowNet[
      "SourcePlace" -> sourcePlace,
      "FinalPlaces" -> finalPlaces,
      "Places"      -> allPlaces,
      "Transitions" -> allTransitions,
      "Description" ->
        "Generated from LLMStateGraph (Shim Week 2a). " <>
        "Initial: " <> initialNode <>
        ", Terminal: " <> StringRiffle[terminalNodes, ", "]
    ]
  ];

(* ::Subsubsection:: *)
(* ClaudeCreateWorkflowFromStateGraph (Public) *)

Options[ClaudeCreateWorkflowFromStateGraph] = {
  "Description"    -> "",
  "ValidateStrict" -> True
};

ClaudeCreateWorkflowFromStateGraph[graph_Association,
                                   opts:OptionsPattern[]] :=
  Module[{wf},
    wf = ClaudeWorkflowFromStateGraph[graph];
    
    (* description が指定されていれば override *)
    If[OptionValue["Description"] =!= "",
      wf = Append[wf, "Description" -> OptionValue["Description"]]
    ];
    
    (* ClaudeOrchestrator`Workflow`ClaudeCreateWorkflowNet で登録 *)
    ClaudeOrchestrator`Workflow`ClaudeCreateWorkflowNet[wf,
      FilterRules[{opts},
        {"ValidateStrict"}]]
  ];

(* ::Subsubsection:: *)
(* Week 2c-2a: 旧 LLMStateGraph* API forwarding 機構 *)

(* sgRid <-> wid mapping registry *)

If[!AssociationQ[$iSGRidWidMap], $iSGRidWidMap = <||>];   (* sgRid -> wid *)
If[!AssociationQ[$iWidSGRidMap], $iWidSGRidMap = <||>];   (* wid -> sgRid *)
If[!AssociationQ[$iSGRidGraphMap], $iSGRidGraphMap = <||>]; (* sgRid -> 元 graph *)
If[!AssociationQ[$iSGRidOptsMap], $iSGRidOptsMap = <||>];  (* sgRid -> opts *)
If[!AssociationQ[$iSGRidWfMap], $iSGRidWfMap = <||>];     (* sgRid -> WorkflowNet 構造 (Week 2c-2b) *)

iRegisterSGRidMapping[sgRid_String, wid_String,
                      graph_Association, opts_List,
                      wf_Association] :=
  ($iSGRidWidMap   = Append[$iSGRidWidMap,   sgRid -> wid];
   $iWidSGRidMap   = Append[$iWidSGRidMap,   wid -> sgRid];
   $iSGRidGraphMap = Append[$iSGRidGraphMap, sgRid -> graph];
   $iSGRidOptsMap  = Append[$iSGRidOptsMap,  sgRid -> opts];
   $iSGRidWfMap    = Append[$iSGRidWfMap,    sgRid -> wf]);

iSGRidToWid[sgRid_String] :=
  Lookup[$iSGRidWidMap, sgRid, $Failed];

iWidToSGRid[wid_String] :=
  Lookup[$iWidSGRidMap, wid, $Failed];

(* iCurrentNodeFromState: workflow state から CurrentNode を逆算。
   sentinel token の Payload.Path の最後を採用 (Stage/Compute/Decision Node の
   handler で append される)。Path が空なら graph["InitialNode"] を返す。 *)

iCurrentNodeFromState[wid_String, graph_Association] :=
  Module[{state, tokens, sentinelTokens, lastToken, path},
    state = ClaudeOrchestrator`Workflow`ClaudeWorkflowState[wid];
    If[!AssociationQ[state],
      Return[Lookup[graph, "InitialNode", "?"]]];
    
    tokens = Lookup[state, "Tokens", <||>];
    sentinelTokens = Select[Values[tokens],
      Lookup[#, "Kind", ""] === "XSMSentinel" &];
    
    If[Length[sentinelTokens] === 0,
      Return[Lookup[graph, "InitialNode", "?"]]];
    
    (* 最も新しい sentinel token を採用 (CreatedAt が大きい) *)
    lastToken = First @ SortBy[sentinelTokens, -Lookup[#, "CreatedAt", 0] &];
    path = Lookup[Lookup[lastToken, "Payload", <||>], "Path", {}];
    
    If[Length[path] === 0,
      Lookup[graph, "InitialNode", "?"],
      Last[path]
    ]
  ];

(* iWorkflowStatusToSGStatus: workflow status を stategraph 形式に変換 *)

iWorkflowStatusToSGStatus[wfStatus_String] :=
  Switch[wfStatus,
    "Initialized", "Pending",
    "Running",     "Running",
    "Paused",      "Pending",   (* stategraph に Paused は無い *)
    "Done",        "Done",
    "Failed",      "Failed",
    "Cancelled",   "Cancelled",
    _,             wfStatus
  ];

(* iExtractStatus: ShimLLMStateGraphStatus 用、stategraph 形式の Status 構築 *)

iExtractStatus[sgRid_String] :=
  Module[{wid, graph, opts, wfStatus, wfState, currentNode,
          startTime, endTime, elapsedSec, failureReason,
          totalIterations, maxIter, path, lastToken, sentinelTokens},
    
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed,
      Return[Missing["RuntimeNotFound", sgRid]]];
    
    graph = Lookup[$iSGRidGraphMap, sgRid, <||>];
    opts  = Lookup[$iSGRidOptsMap,  sgRid, {}];
    
    wfStatus = ClaudeOrchestrator`Workflow`ClaudeWorkflowStatus[wid];
    If[!AssociationQ[wfStatus],
      Return[Missing["RuntimeNotFound", sgRid]]];
    
    wfState     = ClaudeOrchestrator`Workflow`ClaudeWorkflowState[wid];
    currentNode = iCurrentNodeFromState[wid, graph];
    
    (* sentinel token から Path を取得 *)
    sentinelTokens = Select[Values[Lookup[wfState, "Tokens", <||>]],
      Lookup[#, "Kind", ""] === "XSMSentinel" &];
    lastToken = If[Length[sentinelTokens] > 0,
      First @ SortBy[sentinelTokens, -Lookup[#, "CreatedAt", 0] &],
      <||>];
    path = Lookup[Lookup[lastToken, "Payload", <||>], "Path", {}];
    
    startTime     = Lookup[wfStatus, "CreatedAt", 0];
    endTime       = Lookup[wfStatus, "CompletedAt", None];
    elapsedSec    = If[endTime === None || !NumberQ[endTime],
      AbsoluteTime[] - startTime,
      endTime - startTime];
    failureReason = Lookup[wfStatus, "FailureReason", None];
    
    (* TotalIterations: workflow trace の transition fire 回数 *)
    totalIterations = Length @ Cases[
      Lookup[wfStatus, "TraceCount", 0]
       /. n_Integer :> Range[n], _Integer, Infinity];
    If[!IntegerQ[totalIterations], totalIterations = 0];
    
    maxIter = Lookup[opts, "MaxTotalIterations", 30];
    
    <|"RuntimeId"          -> sgRid,
      "Status"              -> iWorkflowStatusToSGStatus[
                                Lookup[wfStatus, "Status", "Unknown"]],
      "CurrentNode"         -> currentNode,
      "TotalIterations"     -> totalIterations,
      "MaxTotalIterations"  -> maxIter,
      "Path"                -> path,
      "ActiveSubDAGId"      -> None,    (* workflow 経由では使われない *)
      "FailureReason"       -> failureReason,
      "StartTime"           -> startTime,
      "EndTime"             -> endTime,
      "ElapsedSec"          -> elapsedSec,
      (* shim 拡張 *)
      "WorkflowId"          -> wid,
      "WorkflowStatus"      -> Lookup[wfStatus, "Status", "Unknown"]|>
  ];

(* iExtractGlobalState: ShimLLMStateGraphState 用、sentinel token から
   GlobalState を取り出す。stategraph の慣習である "Stages", "Path",
   "Accumulator", "InputContext" のキーを保証する。
   
   Path については shim handler が Payload.Path のみ更新して
   GlobalState.Path は更新しないため、Payload.Path をフォールバックとして
   注入する (Week 2c-2c hotfix1)。
   
   ただし初期 sentinel の GlobalState には "Path" -> {} が含まれているため、
   gs を KeyDrop["Path"] してから Join しないと右側優先で上書きされ
   payloadPath が採用されない (Week 2c-2c hotfix2)。
   Payload.Path が source of truth、GlobalState.Path はその投影として扱う。 *)

iExtractGlobalState[sgRid_String] :=
  Module[{wid, graph, opts, state, sentinelTokens, lastToken, gs,
          initialContext, payloadPath, gsWithoutPath},
    
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed,
      Return[Missing["RuntimeNotFound", sgRid]]];
    
    state = ClaudeOrchestrator`Workflow`ClaudeWorkflowState[wid];
    If[!AssociationQ[state],
      Return[Missing["RuntimeNotFound", sgRid]]];
    
    sentinelTokens = Select[Values[Lookup[state, "Tokens", <||>]],
      Lookup[#, "Kind", ""] === "XSMSentinel" &];
    
    If[Length[sentinelTokens] === 0,
      (* token がもう無い (= 全部消費されて produce されてない、ありえない)
         場合は initial context を返す *)
      opts = Lookup[$iSGRidOptsMap, sgRid, {}];
      initialContext = Lookup[opts, "InitialContext", <||>];
      Return[<|
        "Stages"        -> <||>,
        "Path"          -> {},
        "Accumulator"   -> <||>,
        "InputContext"  -> initialContext|>]
    ];
    
    lastToken     = First @ SortBy[sentinelTokens, -Lookup[#, "CreatedAt", 0] &];
    gs            = Lookup[Lookup[lastToken, "Payload", <||>], "GlobalState", <||>];
    payloadPath   = Lookup[Lookup[lastToken, "Payload", <||>], "Path", {}];
    
    (* hotfix2: gs から Path を抜いてから Join。これによって gs に
       残っている古い "Path" -> {} で payloadPath が上書きされない。
       Payload.Path が source of truth であることを accessor 側で確定する。 *)
    gsWithoutPath = KeyDrop[gs, "Path"];
    
    (* stategraph 形式の必須キーを保証 *)
    opts = Lookup[$iSGRidOptsMap, sgRid, {}];
    initialContext = Lookup[opts, "InitialContext", <||>];
    
    Join[
      <|"Stages"       -> <||>,
        "Path"         -> payloadPath,
        "Accumulator"  -> <||>,
        "InputContext" -> initialContext|>,
      gsWithoutPath   (* Path を含まないので上書きの心配なし *)
    ]
  ];

(* ::Subsubsection:: *)
(* Week 2c-2a Public API: ShimLLMStateGraphCreate / Status / State *)

Options[ShimLLMStateGraphCreate] = {
  "InitialContext"     -> <||>,
  "MaxTotalIterations" -> 30,
  (* Week 2c-2d: 元 LLMStateGraphCreate との互換性のために受け付ける
     (本 shim 内では即時実行ではないため、OnGraphComplete/Description は
     ShimRunStateGraph または ClaudeRegisterCompletionHook 経由で扱う) *)
  "Notebook"           -> Automatic,
  "OnGraphComplete"    -> None,
  "Description"        -> ""
};

ShimLLMStateGraphCreate[graph_Association, opts:OptionsPattern[]] :=
  Module[{wf, wid, sentinelToken, sgRid, initialNode, initialContext,
          callback, hookAdapter},
    
    initialNode    = Lookup[graph, "InitialNode", "?"];
    initialContext = OptionValue["InitialContext"];
    callback       = OptionValue["OnGraphComplete"];
    
    (* 1. WorkflowNet 構造を Association として捕捉 (Trace 変換時に
       transition から RuntimeSpec を引くため $iSGRidWfMap に保存する) *)
    wf = ClaudeWorkflowFromStateGraph[graph];
    
    (* 2. ClaudeCreateWorkflowNet で登録 *)
    wid = ClaudeOrchestrator`Workflow`ClaudeCreateWorkflowNet[wf];
    
    (* 3. XSMSentinel token を投入 *)
    sentinelToken = ClaudeOrchestrator`Workflow`WorkflowToken[
      "Kind"    -> "XSMSentinel",
      "Payload" -> <|
        "GlobalState" -> Join[
          <|"Stages"       -> <||>,
            "Path"         -> {},
            "Accumulator"  -> <||>,
            "InputContext" -> initialContext|>,
          (* InitialContext が <|"k" -> v|> 形式なら直接使う *)
          If[AssociationQ[initialContext], initialContext, <||>]
        ],
        "Path"        -> {}|>
    ];
    ClaudeOrchestrator`Workflow`ClaudeSubmitToken[wid, sentinelToken];
    
    (* 4. sgRid を生成 (stategraph 互換形式) *)
    sgRid = "sg-" <> StringTake[wid, -12];
    
    (* 5. mapping 登録 (wf も含む) *)
    iRegisterSGRidMapping[sgRid, wid, graph, {opts}, wf];
    
    (* 6. OnGraphComplete callback を completion hook で登録
          (Week 2c-2d 互換: LLMStateGraphCreate の OnGraphComplete を
           ShimLLMStateGraphCreate でも受けられるように。
           workflow が完了した時点で発火) *)
    If[callback =!= None && callback =!= Null,
      hookAdapter = iMakeStateGraphCallbackAdapter[sgRid, wid, callback];
      ClaudeOrchestrator`Workflow`ClaudeRegisterCompletionHook[wid,
        hookAdapter];
    ];
    
    sgRid
  ];

ShimLLMStateGraphStatus[sgRid_String] := iExtractStatus[sgRid];

ShimLLMStateGraphState[sgRid_String]  := iExtractGlobalState[sgRid];

(* ::Subsubsection:: *)
(* Week 2c-2b: Cancel / List / Trace / RecordHistory forwarding *)

ShimLLMStateGraphCancel[sgRid_String] :=
  Module[{wid, result},
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed,
      Return[Missing["RuntimeNotFound", sgRid]]];
    
    result = Catch[
      ClaudeOrchestrator`Workflow`ClaudeCancelWorkflow[wid],
      _String
    ];
    
    sgRid    (* 成功時は sgRid を返す (LLMStateGraphCancel 互換) *)
  ];

ShimLLMStateGraphList[] := Keys[$iSGRidWidMap];

(* iWorkflowEventToSGTraceEvent: ClaudeWorkflowTrace の event を
   stategraph trace 形式に変換する。
   workflow event のキー: "Event" / "Timestamp" / 他
   stategraph event のキー: "Type" / "Time" / 他
   transitions は wf[["Transitions"]] (sgRid から $iSGRidWfMap で引く)
   から transitionName -> RuntimeSpec を解決するために使う。 *)

iWorkflowEventToSGTraceEvent[event_Association,
                              transitions_Association] :=
  Module[{eventName, transName, trans, runtimeSpec,
          nodeId, nodeType, time},
    
    eventName = Lookup[event, "Event", ""];
    time      = Lookup[event, "Timestamp", 0];
    
    Switch[eventName,
      
      "TransitionFired",
        transName   = Lookup[event, "TransitionName", ""];
        trans       = Lookup[transitions, transName, <||>];
        runtimeSpec = Lookup[trans, "RuntimeSpec", <||>];
        nodeId      = Lookup[runtimeSpec, "NodeId", ""];
        nodeType    = Lookup[runtimeSpec, "NodeType", ""];
        
        Switch[nodeType,
          "Stage" | "Compute",
            <|"Type"            -> "NodeProcessed",
              "Time"            -> time,
              "NodeId"          -> nodeId,
              "NodeType"        -> nodeType,
              "TransitionName"  -> transName|>,
          "Decision",
            <|"Type"            -> "DecisionMade",
              "Time"            -> time,
              "NodeId"          -> nodeId,
              "TransitionName"  -> transName|>,
          "ParallelSubgraph-split",
            <|"Type"            -> "ParallelStarted",
              "Time"            -> time,
              "NodeId"          -> nodeId,
              "TransitionName"  -> transName|>,
          "ParallelSubgraph-join",
            <|"Type"            -> "ParallelJoined",
              "Time"            -> time,
              "NodeId"          -> nodeId,
              "TransitionName"  -> transName|>,
          _,
            (* Edge transitions は nodeType が空。
               XSM trace では edge 自体を表現する慣習がないが、
               trace の網羅性のため "EdgeFired" として残す *)
            <|"Type"            -> "EdgeFired",
              "Time"            -> time,
              "TransitionName"  -> transName|>
        ],
      
      "TokenSubmitted",
        <|"Type" -> "TokenSubmitted", "Time" -> time|>,
      
      "WorkflowPaused",
        <|"Type" -> "Paused", "Time" -> time|>,
      
      "WorkflowResumed",
        <|"Type" -> "Resumed", "Time" -> time|>,
      
      "WorkflowCancelled",
        <|"Type"           -> "Cancelled",
          "Time"           -> time,
          "PreviousStatus" -> Lookup[event, "PreviousStatus", ""]|>,
      
      _,
        (* 未知の event はそのまま Type/Time だけ rewrite *)
        <|"Type" -> eventName, "Time" -> time|>
    ]
  ];

iExtractTrace[sgRid_String] :=
  Module[{wid, graph, wf, wfTrace, transitions, sgTrace,
          firstTime},
    
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed, Return[{}]];
    
    graph       = Lookup[$iSGRidGraphMap, sgRid, <||>];
    wf          = Lookup[$iSGRidWfMap, sgRid, <||>];
    transitions = Lookup[wf, "Transitions", <||>];
    
    wfTrace = ClaudeOrchestrator`Workflow`ClaudeWorkflowTrace[wid];
    
    sgTrace = Map[
      iWorkflowEventToSGTraceEvent[#, transitions]&,
      wfTrace
    ];
    
    (* 先頭に "GraphCreated" event を prepend (LLMStateGraphCreate 慣習) *)
    firstTime = If[Length[wfTrace] > 0,
                   Lookup[First[wfTrace], "Timestamp", 0],
                   0];
    Prepend[sgTrace, <|
      "Type"        -> "GraphCreated",
      "Time"        -> firstTime,
      "InitialNode" -> Lookup[graph, "InitialNode", "?"]
    |>]
  ];

ShimLLMStateGraphTrace[sgRid_String] := iExtractTrace[sgRid];

(* ShimLLMStateGraphRecordHistory: Week 2c-2b ではスケルトン実装。
   workflow の status / state / trace を Association にまとめて返す。
   LLMGraph への記録は Stage C で本実装予定。 *)

ShimLLMStateGraphRecordHistory[sgRid_String] :=
  Module[{wid, status, state, trace},
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed, Return[Missing["RuntimeNotFound", sgRid]]];
    
    status = ShimLLMStateGraphStatus[sgRid];
    state  = ShimLLMStateGraphState[sgRid];
    trace  = ShimLLMStateGraphTrace[sgRid];
    
    <|
      "RuntimeId"        -> sgRid,
      "WorkflowId"       -> wid,
      "Status"           -> Lookup[status, "Status", "Unknown"],
      "Path"             -> Lookup[status, "Path", {}],
      "Stages"           -> Lookup[state, "Stages", <||>],
      "Trace"            -> trace,
      "TraceEventCount"  -> Length[trace],
      "Recorded"         -> True,
      "RecordedAt"       -> AbsoluteTime[],
      (* Stage C で本実装される時に設定: 実際の LLMGraph node ID 等 *)
      "LLMGraphNodeId"   -> Missing["NotYetImplemented"]
    |>
  ];

(* ::Subsubsection:: *)
(* Week 2c-2c: ShimRunStateGraph (sync/async 統一 API) *)

(* iMakeStateGraphCallbackAdapter: workflow の completion info を
   stategraph runtime 形式に変換して callback を呼ぶ adapter を作る。
   workflow.wl の completion hook は次の形式の Association を渡してくる:
     <|"WorkflowId", "Status", "TerminationReason",
       "Mode" -> "Sync"|"Async", "ElapsedSec", "Steps",
       "FinalMarking", "EndTime"|>
   stategraph callback が期待する形式 (元の RunStateGraph の callback は
   runtime Association を引数として受け取る) に変換する。 *)

iMakeStateGraphCallbackAdapter[sgRid_String, wid_String, callback_] :=
  Function[{wfCompletionInfo},
    Module[{sgState, sgStatus, runtimeAssoc},
      sgStatus = iExtractStatus[sgRid];
      sgState  = iExtractGlobalState[sgRid];
      runtimeAssoc = <|
        "RuntimeId"     -> sgRid,
        "Status"        -> Lookup[sgStatus, "Status", "?"],
        "GlobalState"   -> sgState,
        "Path"          -> Lookup[sgState, "Path", {}],
        "ElapsedSec"    -> Lookup[wfCompletionInfo, "ElapsedSec", 0],
        "FailureReason" -> Lookup[sgStatus, "FailureReason", None],
        (* shim 拡張 (元の callback には無いが、追加情報として有用) *)
        "WorkflowId"        -> wid,
        "TerminationReason" -> Lookup[wfCompletionInfo,
                                      "TerminationReason", "?"],
        "Mode"              -> Lookup[wfCompletionInfo, "Mode", "?"]
      |>;
      callback[runtimeAssoc]
    ]
  ];

Options[ShimRunStateGraph] = {
  "Async"              -> False,
  "MaxTotalIterations" -> 30,
  "MaxWait"            -> 600,
  "PollInterval"       -> 0.5,
  "Profile"            -> "Generic",
  "Notebook"           -> Automatic,
  "InitialContext"     -> <||>,
  "OnGraphComplete"    -> None,
  "Description"        -> ""
};

ShimRunStateGraph[graph_Association, opts:OptionsPattern[]] :=
  Module[{async, sgRid, wid, maxIter, maxWait, callback, hookAdapter,
          maxSteps, runResult, sgStatus, sgState, sgTrace, status,
          ttlReason, elapsed, failureReason, finalAssoc},
    
    async    = TrueQ[OptionValue["Async"]];
    maxIter  = OptionValue["MaxTotalIterations"];
    maxWait  = OptionValue["MaxWait"];
    callback = OptionValue["OnGraphComplete"];
    maxSteps = maxIter * 5;   (* PSG 多用ケースに余裕 *)
    
    (* 1. ShimLLMStateGraphCreate に委譲 (token 投入まで完了) *)
    sgRid = ShimLLMStateGraphCreate[graph,
      "InitialContext"     -> OptionValue["InitialContext"],
      "MaxTotalIterations" -> maxIter];
    
    If[!StringQ[sgRid], Return[$Failed]];
    
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed, Return[$Failed]];
    
    (* 2. callback が指定されていれば hook adapter を登録
          (Sync/Async 両モード共通、workflow.wl 側で両方発火される) *)
    If[callback =!= None && callback =!= Null,
      hookAdapter = iMakeStateGraphCallbackAdapter[sgRid, wid, callback];
      ClaudeOrchestrator`Workflow`ClaudeRegisterCompletionHook[wid,
        hookAdapter];
    ];
    
    (* 3. Async モード: workflow を Async 起動して sgRid を返す *)
    If[async,
      ClaudeOrchestrator`Workflow`ClaudeRunWorkflow[wid,
        "Async"    -> True,
        "MaxSteps" -> maxSteps,
        "MaxWait"  -> Quantity[maxWait, "Seconds"]];
      Return[sgRid]
    ];
    
    (* 4. Sync モード: ClaudeRunWorkflow Sync で完走 *)
    runResult = ClaudeOrchestrator`Workflow`ClaudeRunWorkflow[wid,
      "Async"    -> False,
      "MaxSteps" -> maxSteps,
      "MaxWait"  -> Quantity[maxWait, "Seconds"]];
    
    (* 5. 完了状態を shim 経由で取得
          (この時点で workflow の completion hook は発火済み) *)
    sgStatus  = iExtractStatus[sgRid];
    sgState   = iExtractGlobalState[sgRid];
    sgTrace   = iExtractTrace[sgRid];
    
    ttlReason = Lookup[runResult, "TerminationReason", "Unknown"];
    elapsed   = Lookup[runResult, "ElapsedSec",
                  Lookup[sgStatus, "ElapsedSec", 0]];
    
    (* 6. Status と FailureReason の決定 *)
    {status, failureReason} = Switch[ttlReason,
      "Timeout",
        Quiet @ Check[
          ClaudeOrchestrator`Workflow`ClaudeCancelWorkflow[wid],
          Null];
        {"TimedOut",
         "MaxWait (" <> ToString[maxWait] <> "s) exceeded"},
      "MaxStepsReached",
        Quiet @ Check[
          ClaudeOrchestrator`Workflow`ClaudeCancelWorkflow[wid],
          Null];
        {"TimedOut",
         "MaxSteps (" <> ToString[maxSteps] <> ") reached"},
      "ReachedFinalPlace",
        {"Done", None},
      "Failed",
        {"Failed",
         Lookup[sgStatus, "FailureReason",
           Lookup[runResult, "Reason", "Failed"]]},
      "Stuck",
        {"Stuck", "Stuck"},
      "Blocked",
        {"Blocked", "Blocked"},
      "NeedsApproval",
        {"NeedsApproval", "NeedsApproval"},
      _,
        {Lookup[sgStatus, "Status", "Unknown"],
         Lookup[sgStatus, "FailureReason", None]}
    ];
    
    finalAssoc = <|
      "RuntimeId"     -> sgRid,
      "Status"        -> status,
      "GlobalState"   -> sgState,
      "Path"          -> Lookup[sgState, "Path", {}],
      "ElapsedSec"    -> elapsed,
      "FailureReason" -> failureReason,
      "Trace"         -> sgTrace,
      (* shim 拡張キー *)
      "WorkflowId"      -> wid,
      "WorkflowResult"  -> runResult
    |>;
    
    finalAssoc
  ];

(* ::Subsubsection:: *)
(* Week 2c-3: ShimLLMStateGraphSnapshot / Restore / ListSnapshots *)

(* iRegisterRestoredSnapshot: Restore で得た新 wid に対して新 sgRid を発行し、
   registry に登録する。元の graph / opts / wf は復元できない (Snapshot から
   は workflow 構造のみ復元される) ため、最低限の placeholder を入れる。
   ShimLLMStateGraphState などの accessor は registry を頼って動くので、
   この helper で透過的に整合性を取る。 *)

iRegisterRestoredSnapshot[wid_String] :=
  Module[{newSGRid, wf, placeholderGraph, placeholderOpts},
    newSGRid = "sg-" <> StringTake[wid, -12];
    
    wf = If[KeyExistsQ[
      ClaudeOrchestrator`Workflow`Private`$iWorkflowNets, wid],
      ClaudeOrchestrator`Workflow`Private`$iWorkflowNets[wid],
      <||>];
    
    (* placeholder: 復元時には元 graph (XSM 形式) は失われている。
       accessor の Lookup は default 値を返すので、空 Association で OK *)
    placeholderGraph = <|"Type" -> "LLMStateGraph",
                          "Nodes" -> <||>,
                          "Edges" -> {},
                          "InitialNode" -> "?",
                          "TerminalNodes" -> {},
                          "_RestoredFromSnapshot" -> True|>;
    placeholderOpts = {};
    
    iRegisterSGRidMapping[newSGRid, wid, placeholderGraph,
                          placeholderOpts, wf];
    
    newSGRid
  ];

(* ShimLLMStateGraphSnapshot *)

Options[ShimLLMStateGraphSnapshot] = {
  "SnapshotDir" -> Automatic,
  "Description" -> ""
};

ShimLLMStateGraphSnapshot[sgRid_String, opts:OptionsPattern[]] :=
  Module[{wid, snapResult},
    wid = iSGRidToWid[sgRid];
    If[wid === $Failed,
      Return[Missing["RuntimeNotFound", sgRid]]];
    
    snapResult = Catch[
      ClaudeOrchestrator`Workflow`ClaudeSnapshotWorkflow[wid,
        "SnapshotDir" -> OptionValue["SnapshotDir"],
        "Description" -> OptionValue["Description"]],
      _
    ];
    
    If[!AssociationQ[snapResult],
      Return[<|"RuntimeId"     -> sgRid,
                "WorkflowId"    -> wid,
                "Status"        -> "Failed",
                "FailureReason" -> "ClaudeSnapshotWorkflow failed",
                "RawResult"     -> snapResult|>]];
    
    (* stategraph 形式の戻り値に整形 (RuntimeId を先頭に追加) *)
    Join[
      <|"RuntimeId" -> sgRid|>,
      snapResult   (* WorkflowId, SnapshotDir, FormatVersion, SavedAt *)
    ]
  ];

(* ShimLLMStateGraphRestore *)

Options[ShimLLMStateGraphRestore] = {
  "AsNewWorkflowId" -> True
};

ShimLLMStateGraphRestore[snapDir_String, opts:OptionsPattern[]] :=
  Module[{metaPath, meta, formatVersion, restoreResult, newWid, newSGRid,
          originalWid, originalRuntimeId},
    
    If[!DirectoryQ[snapDir],
      Return[<|"Restored"      -> False,
                "FailureReason" -> "SnapshotDirNotFound",
                "SnapshotDir"   -> snapDir|>]];
    
    (* meta.wl から FormatVersion を確認。v1 (FormatVersion != 2) なら
       明示的に拒否する (Imai 先生の判断 2026-05-06、Week 2c-3 設計) *)
    metaPath = FileNameJoin[{snapDir, "meta.wl"}];
    If[!FileExistsQ[metaPath],
      Return[<|"Restored"      -> False,
                "FailureReason" -> "MetaFileMissing",
                "SnapshotDir"   -> snapDir|>]];
    
    meta = Quiet @ Check[
      Block[{$CharacterEncoding = "UTF-8"}, Get[metaPath]],
      $Failed];
    
    If[!AssociationQ[meta],
      Return[<|"Restored"      -> False,
                "FailureReason" -> "MetaFileCorrupted",
                "SnapshotDir"   -> snapDir|>]];
    
    formatVersion = Lookup[meta, "FormatVersion", 1];
    
    If[formatVersion =!= 2,
      Return[<|"Restored"      -> False,
                "FailureReason" -> "UnsupportedFormatVersion: shim accepts v2 only (got v" <>
                                    ToString[formatVersion] <> ")",
                "SnapshotDir"   -> snapDir,
                "FormatVersion" -> formatVersion|>]];
    
    (* v2 確認後、ClaudeRestoreWorkflow に委譲 *)
    restoreResult = Catch[
      ClaudeOrchestrator`Workflow`ClaudeRestoreWorkflow[snapDir,
        "AsNewWorkflowId" -> OptionValue["AsNewWorkflowId"]],
      _
    ];
    
    If[!AssociationQ[restoreResult],
      Return[<|"Restored"      -> False,
                "FailureReason" -> "ClaudeRestoreWorkflow failed",
                "SnapshotDir"   -> snapDir,
                "RawResult"     -> restoreResult|>]];
    
    newWid      = Lookup[restoreResult, "WorkflowId", $Failed];
    originalWid = Lookup[restoreResult, "OriginalWid", "?"];
    
    (* 新 sgRid を発行して registry に登録 *)
    newSGRid = iRegisterRestoredSnapshot[newWid];
    
    (* 元の sgRid (もしあれば) を解決 *)
    originalRuntimeId = iWidToSGRid[originalWid];
    If[originalRuntimeId === $Failed,
      originalRuntimeId = Missing["NotInRegistry"]];
    
    <|"RuntimeId"         -> newSGRid,
      "WorkflowId"        -> newWid,
      "OriginalWid"       -> originalWid,
      "OriginalRuntimeId" -> originalRuntimeId,
      "Restored"          -> True,
      "FormatVersion"     -> 2,
      "SnapshotDir"       -> snapDir|>
  ];

(* ShimLLMStateGraphListSnapshots *)

Options[ShimLLMStateGraphListSnapshots] = {
  "SnapshotDir" -> Automatic
};

ShimLLMStateGraphListSnapshots[opts:OptionsPattern[]] :=
  ClaudeOrchestrator`Workflow`ClaudeListWorkflowSnapshots[
    "SnapshotDir" -> OptionValue["SnapshotDir"]];

(* ::Subsection:: *)
(* End *)

End[];
EndPackage[];
