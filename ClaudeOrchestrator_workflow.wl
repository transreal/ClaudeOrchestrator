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

(* ::Subsection:: *)
(* Private *)

Begin["`Private`"];

ClaudeOrchestrator`Workflow`$WorkflowVersion =
  "2026-05-10-retry-policy-enforcement";

(* バージョン履歴:
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
  "ParentRuntime"  -> Missing[]};

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
              {"ClaudeRuntime", "PackageManager", "PureFunction", "External"}, exec],
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

    (* 4. Executor 実行 *)
    executorResult = iExecuteTransition[trans, binding];

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
        <|"Status"  -> "Stub",
          "Reason"  -> "External executor: 後続フェーズで実装",
          "Output"  -> binding|>,
      _,
        <|"Status"  -> "Failed",
          "Reason"  -> "UnknownExecutor: " <> ToString[executor]|>
    ]
  ];

iExecutePureFunction[trans_Association, binding_Association] :=
  Module[{handler, output, succeeded, prevML, isCallable},
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

    Which[
      isCallable,
        (* 罠 #16 回避: Quiet@Check は使わず、フラグ変数で成否を取る。
           Block で $MessageList を局所化し、メッセージが出たかも検知する。 *)
        succeeded = True;
        Block[{$MessageList = {}, prevML$ = $MessageList},
          output = Quiet[
            Check[
              handler[binding],
              (succeeded = False; $Failed)
            ]
          ];
          (* メッセージが出ていれば失敗扱いとする (handler が握り潰しても
             ここで検知できる)。 *)
          If[Length[$MessageList] > 0, succeeded = False];
        ],
      handler === Identity,
        output = binding; succeeded = True,
      True,
        output = binding; succeeded = True
    ];

    (* output 自身が $Failed の場合も明示的に失敗 *)
    If[output === $Failed, succeeded = False];

    If[!succeeded,
      <|"Status" -> "Failed", "Reason" -> "HandlerError"|>,
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
           除外し、他に enabled が無ければ次 step が "Stuck" になる。 *)
        Switch[stepResult[["Status"]],
          "Stuck",
            terminationReason = "Stuck";
            Throw["StuckBreak"],
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
            Throw["SkippedBreak"]
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
       enabled なら次 tick で継続する。 *)
    Switch[Lookup[stepResult, "Status", "?"],
      "Stuck",         iMarkAsyncCompleted[wid, "Stuck"]; Return[],
      "Failed",        iMarkAsyncCompleted[wid, "Failed"]; Return[],
      "NeedsApproval", iMarkAsyncCompleted[wid, "NeedsApproval"]; Return[],
      "Blocked",       iMarkAsyncCompleted[wid, "Blocked"]; Return[]
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
          finalStatus, finalMarking},
    
    intervalSec = QuantityMagnitude @
                  UnitConvert[OptionValue["PollInterval"], "Seconds"];
    maxWaitSec  = QuantityMagnitude @
                  UnitConvert[OptionValue["MaxWait"], "Seconds"];
    startTime   = iCurrentTime[];
    completed   = False;
    
    While[!completed && (iCurrentTime[] - startTime) < maxWaitSec,
      Pause[intervalSec];
      
      Which[
        !KeyExistsQ[$iWorkflowAsyncJobs, wid],
          completed = True,
        Lookup[$iWorkflowAsyncJobs[wid], "Status", "Running"] === "Completed",
          completed = True
      ];
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
  Module[{wf, prevStatus},
    If[!KeyExistsQ[$iWorkflowNets, wid],
      Throw[$Failed, "WorkflowNotFound: " <> wid]
    ];
    wf         = $iWorkflowNets[wid];
    prevStatus = wf[["Status"]];
    
    AssociateTo[$iWorkflowNets,
      wid -> ReplacePart[wf,
        {"Status" -> "Cancelled",
         "Trace"  -> Append[wf[["Trace"]],
           <|"Event"          -> "WorkflowCancelled",
             "PreviousStatus" -> prevStatus,
             "Timestamp"      -> iCurrentTime[]|>]}]
    ];
    
    (* async ジョブが走っていたら即時に完了状態へ。
       次の SharedPollingTask tick を待たずに ClaudeWaitWorkflow が
       Completed を見られるようにする。 *)
    If[KeyExistsQ[$iWorkflowAsyncJobs, wid] &&
       Lookup[$iWorkflowAsyncJobs[wid], "Status", "Completed"] =!= "Completed",
      iMarkAsyncCompleted[wid, "Cancelled"]
    ];
    
    <|"Status" -> "Cancelled", "WorkflowId" -> wid|>
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
