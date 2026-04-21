(* ClaudeOrchestrator.wl -- Multi-Agent Orchestration Layer
   
   責務: ClaudeRuntime (単一エージェント実行核) の上に乗る、
         タスク分解・並列 worker 配車・artifact 収集・reduction・
         single-committer commit の機構。
   
   設計上の不変条件 (claude_multi_agent_orchestration_spec.md より):
     1. ClaudeRuntime は 1 agent kernel のまま維持
     2. 並列 worker は artifact producer に限定 (NotebookWrite 禁止)
     3. 実 notebook への書き込みは single committer のみ
     4. worker 間の共有状態は明示的 artifact / JSON / Association のみ
     5. EvaluationNotebook[] / CreateNotebook[...] は deny
   
   依存:
     - ClaudeRuntime`     : CreateClaudeRuntime, ClaudeRunTurn,
                            ClaudeRuntimeState, ClaudeRuntimeStateFull,
                            ClaudeGetConversationMessages, ClaudeContinueTurn,
                            ClaudeRetryPolicy
     - ClaudeCode`        : ClaudeBuildRuntimeAdapter
                            (ただし orchestrator は adapter を直接
                             構築せず、worker ごとにラップする)
   
   Load:
     Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]
   
   撤去された Phase 31 ClaudeEvalDecomposed との違い:
     - 各 worker は notebook を直接触らない (strip された capability のみ)
     - committer は target notebook を With[{nb = ...}, ...] で HeldExpr に束縛
     - artifact は OutputSchema 準拠の Association として明示的に受け渡し
*)

BeginPackage["ClaudeOrchestrator`"];

(* ════════════════════════════════════════════════════════
   Public API
   ════════════════════════════════════════════════════════ *)

$ClaudeOrchestratorVersion::usage =
  "$ClaudeOrchestratorVersion はパッケージバージョン。";

ClaudePlanTasks::usage =
  "ClaudePlanTasks[input, opts] は親タスク input を TaskSpec DAG に分解する。\n" <>
  "opts: Planner -> fn (プランナー関数) | Automatic (mock を使う)\n" <>
  "        MaxTasks -> n (既定 10)\n" <>
  "戻り値: <|\"Tasks\" -> {<|\"TaskId\"->...,\"Role\"->...,\"Goal\"->...,\n" <>
  "                         \"Inputs\"->...,\"Outputs\"->...,\n" <>
  "                         \"Capabilities\"->...,\"DependsOn\"->...,\n" <>
  "                         \"ExpectedArtifactType\"->...,\n" <>
  "                         \"OutputSchema\"->...|>, ...}|>";

ClaudeValidateTaskSpec::usage =
  "ClaudeValidateTaskSpec[taskSpec] は TaskSpec の妥当性を検証し、\n" <>
  "<|\"Valid\"->True/False, \"Errors\"->{...}|> を返す。";

ClaudeSpawnWorkers::usage =
  "ClaudeSpawnWorkers[tasks, opts] は依存順に worker runtime を起動し、\n" <>
  "各 task の artifact を収集する (直列または順次)。\n" <>
  "opts: WorkerAdapterBuilder -> fn (Role -> TaskSpec を受け取り adapter を返す)\n" <>
  "        MaxParallelism -> n (現状 1。Stage 2 以降で拡張)\n" <>
  "戻り値: <|\"Artifacts\" -> <|taskId -> artifact, ...|>,\n" <>
  "           \"Failures\" -> {...}, \"Status\" -> \"Complete\"|\"Partial\"|\"Failed\"|>";

ClaudeCollectArtifacts::usage =
  "ClaudeCollectArtifacts[spawnResult] は spawnResult[\"Artifacts\"] を\n" <>
  "Dataset として返す (ノートブック上で確認しやすい形式)。";

ClaudeValidateArtifact::usage =
  "ClaudeValidateArtifact[artifact, outputSchema] は artifact の payload が\n" <>
  "OutputSchema を満たすか検証する。\n" <>
  "戻り値: <|\"Valid\"->True/False, \"Errors\"->{...}|>";

ClaudeReduceArtifacts::usage =
  "ClaudeReduceArtifacts[artifacts, opts] は複数 artifact を統合し、\n" <>
  "中間成果物 (ReducedArtifact) を返す。\n" <>
  "opts: Reducer -> fn (artifacts を受け取り ReducedArtifact を返す関数) | Automatic\n" <>
  "戻り値: <|\"ArtifactType\"->\"Reduced\", \"Payload\"->..., \"Sources\"->...|>";

ClaudeCommitArtifacts::usage =
  "ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts] は\n" <>
  "single committer runtime を起動し、reducedArtifact を target notebook に\n" <>
  "反映する。committer の HeldExpr は EvaluationNotebook[] / CreateNotebook[...]\n" <>
  "参照が targetNotebook に ReplaceAll で書換えられる (Stage 3.7 以降)。\n" <>
  "opts: CommitterAdapterBuilder -> fn | Automatic\n" <>
  "      CommitMode -> \"Direct\" (default) | \"Transactional\" (Stage 4)\n" <>
  "      Verifier -> fn[buffer, cells] -> True/False | Automatic\n" <>
  "Transactional モードでは shadow buffer に書いてから verify / flush し、\n" <>
  "失敗時は target notebook を無変更のまま rollback する (spec §12.3)。\n" <>
  "戻り値: <|\"Status\"->\"Committed\"|\"Failed\"|\"RolledBack\", \"Mode\"->..., \"Details\"->...|>";

ClaudeRunOrchestration::usage =
  "ClaudeRunOrchestration[input, opts] は Planning -> Spawn -> Reduce ->\n" <>
  "(optional) Commit の全フェーズを直列に回す。\n" <>
  "opts: TargetNotebook -> nb (Commit するなら指定)\n" <>
  "        Planner / WorkerAdapterBuilder / Reducer / CommitterAdapterBuilder\n" <>
  "        MaxTasks / MaxParallelism / Confirm (既定 False)\n" <>
  "戻り値: 4 フェーズの結果を束ねた Association";

ClaudeContinueBatch::usage =
  "ClaudeContinueBatch[runtimeId, batchInstructions, opts] は\n" <>
  "単一 runtime セッションを維持したまま、batchInstructions に\n" <>
  "含まれる prompt を ClaudeContinueTurn で順次投入する。\n" <>
  "notebook 共有問題を回避する現実解 (spec §17.1)。\n" <>
  "opts: WaitBetween -> Quantity[1, \"Seconds\"]\n" <>
  "戻り値: {<|\"Index\"->i, \"Prompt\"->..., \"Result\"->...|>, ...}";

$ClaudeOrchestratorRoles::usage =
  "$ClaudeOrchestratorRoles は許容 Role のリスト:\n" <>
  "{\"Explore\", \"Plan\", \"Draft\", \"Verify\", \"Reduce\", \"Commit\"}";

$ClaudeOrchestratorCapabilities::usage =
  "$ClaudeOrchestratorCapabilities は Role -> Capability リストの Association。";

$ClaudeOrchestratorDenyHeads::usage =
  "$ClaudeOrchestratorDenyHeads は worker が提案してはいけない head のリスト\n" <>
  "(NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess,\n" <>
  " SystemCredential など)。";

$ClaudeOrchestratorRealLLMEndpoint::usage =
  "$ClaudeOrchestratorRealLLMEndpoint (Task 2):\n" <>
  "  None      (既定): real LLM 統合テストをスキップ\n" <>
  "  \"ClaudeCode\": ClaudeCode`ClaudeQueryBg (\:540c\:671f\:7248) \:3092\:4f7f\:3046\n" <>
  "  \"CLI\"       : claude CLI を RunProcess で呼ぶ\n" <>
  "  fn[prompt]  : カスタム関数を使う\n" <>
  "環境変数 CLAUDE_ORCH_REAL_LLM でも opt-in 可能。";

$ClaudeOrchestratorRealLLMEndpoint = None;

$ClaudeOrchestratorCLICommand::usage =
  "$ClaudeOrchestratorCLICommand は CLI mode で起動する実行ファイル名/フルパス。\n" <>
  "  Automatic (既定): OS に応じて \"claude\" (Unix) / \"claude.cmd\" (Windows)\n" <>
  "  String: フルパスまたはコマンド名を明示\n" <>
  "環境変数 CLAUDE_ORCH_CLI_PATH でも上書き可能。";

$ClaudeOrchestratorCLICommand = Automatic;

ClaudeRealLLMAvailable::usage =
  "ClaudeRealLLMAvailable[] returns True if real-LLM integration is configured.\n" <>
  "Checks $ClaudeOrchestratorRealLLMEndpoint and env var CLAUDE_ORCH_REAL_LLM.";

ClaudeRealLLMQuery::usage =
  "ClaudeRealLLMQuery[prompt] runs prompt through the configured real-LLM endpoint.\n" <>
  "Returns response String or $Failed.";

ClaudeRealLLMDiagnose::usage =
  "ClaudeRealLLMDiagnose[prompt] は real LLM 呼び出しを実行し、\n" <>
  "診断情報 (endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否) を\n" <>
  "Association で返す。 W1-W3 等が失敗した際の切り分けに使用。";

ClaudeRealLLMDiagnosePlan::usage =
  "ClaudeRealLLMDiagnosePlan[input] は実 LLM planner パイプラインを走らせ、\n" <>
  "plan 結果と raw LLM 応答 head、 task count、 status、 error 情報を\n" <>
  "Association で返す。 W1 の失敗切り分け用。";

(* ════════════════════════════════════════════════════════
   Async orchestration API (v2026-04-20 non-blocking)
   ════════════════════════════════════════════════════════ *)

ClaudeRunOrchestrationAsync::usage =
  "ClaudeRunOrchestrationAsync[input, opts] は Plan \[Rule] Spawn \[Rule] Reduce \[Rule] Commit\n" <>
  "を DAG \:30b3\:30fc\:30eb\:30d0\:30c3\:30af\:30c1\:30a7\:30fc\:30f3\:3067\:975e\:540c\:671f\:5b9f\:884c\:3057\:3001orchJobId \:3092\:5373\:5ea7\:306b\:8fd4\:3059\:3002\n" <>
  "\:30d5\:30ed\:30f3\:30c8\:30a8\:30f3\:30c9\:3092\:30d6\:30ed\:30c3\:30af\:3057\:306a\:3044\:3002opts \:306f ClaudeRunOrchestration \:3068\:540c\:3058\:3002\n" <>
  "\:72b6\:614b\:306f ClaudeOrchestrationStatus / ClaudeOrchestrationResult \:3067\:53c2\:7167\:3002";

ClaudeOrchestrationStatus::usage =
  "ClaudeOrchestrationStatus[orchJobId] \:306f orchestration \:30b8\:30e7\:30d6\:306e\:73fe\:5728\:72b6\:614b\:3092\:8fd4\:3059\:3002\n" <>
  "\:8fd4\:5024\:4f8b: <|\"Status\"\[Rule]\"Planning\"|\"Spawning\"|\"Reducing\"|\"Committing\"|\"Done\"|\"Failed\",\n" <>
  "          \"Phase\"\[Rule]..., \"ElapsedSecs\"\[Rule]..., \"PlanJobId\"\[Rule]..., \"SpawnJobId\"\[Rule]...|>";

ClaudeOrchestrationResult::usage =
  "ClaudeOrchestrationResult[orchJobId] \:306f\:5b8c\:4e86\:6e08\:307f orchestration \:306e\:6700\:7d42\:7d50\:679c\n" <>
  "(ClaudeRunOrchestration \:3068\:540c\:5f62\:306e Association) \:3092\:8fd4\:3059\:3002\:672a\:5b8c\:4e86\:306a\:3089 Missing \:3092\:8fd4\:3059\:3002";

ClaudeOrchestrationWait::usage =
  "ClaudeOrchestrationWait[orchJobId, timeoutSec] \:306f orchestration \:5b8c\:4e86\:307e\:3067\:5f85\:6a5f\n" <>
  "\:3059\:308b (\:30c6\:30b9\:30c8\:30fb\:30b9\:30af\:30ea\:30d7\:30c8\:5c02\:7528\:3002\:5bfe\:8a71\:30bb\:30eb\:3067\:306f\:4f7f\:7528\:3092\:907f\:3051\:308b)\:3002\:65e2\:5b9a\:30bf\:30a4\:30e0\:30a2\:30a6\:30c8 300 \:79d2\:3002";

ClaudeOrchestrationCancel::usage =
  "ClaudeOrchestrationCancel[orchJobId] \:306f\:5b9f\:884c\:4e2d\:306e DAG \:3092\:4e2d\:6b62\:3057\:30ec\:30b8\:30b9\:30c8\:30ea\:304b\:3089\:9664\:53bb\:3059\:308b\:3002";

ClaudeOrchestrationJobs::usage =
  "ClaudeOrchestrationJobs[] \:306f\:73fe\:5728\:8ffd\:8de1\:4e2d\:306e orchestration \:30b8\:30e7\:30d6\:4e00\:89a7\:3092 Dataset \:3067\:8fd4\:3059\:3002";

$ClaudeOrchestratorAsyncMode::usage =
  "$ClaudeOrchestratorAsyncMode (True/False) \:306f $ClaudeEvalHook \:304c\:975e\:540c\:671f\:7d4c\:8def\n" <>
  "(ClaudeRunOrchestrationAsync) \:3068\:540c\:671f\:7d4c\:8def (ClaudeRunOrchestration) \:306e\:3069\:3061\:3089\:3092\n" <>
  "\:4f7f\:3046\:304b\:3092\:5236\:5fa1\:3059\:308b\:3002\:65e2\:5b9a True (\:975e\:540c\:671f)\:3002False \:306b\:3059\:308b\:3068\:65e7\:540c\:671f\:633b\:52d5\:306b\:623b\:308b\:3002";

$ClaudeOrchestratorAsyncMode = True;

Begin["`Private`"];

(* ── iL: $Language に基づく日英切替 ── *)
iL[ja_String, en_String] := If[$Language === "Japanese", ja, en];

$ClaudeOrchestratorVersion = "2026-04-20T19-default-eval-mode-auto";

(* ══════════════════════════════════════════════════════════════════════
   T08 (2026-04-19): Template inheritance + figure/image cell kinds +
                     voice preservation (reference text injection)
   
   \:30e6\:30fc\:30b6\:8981\:6c42 (test50.nb \:3092\:53d7\:3051\:3066):
     (1) slides-template.nb \:304b\:3089\:30b9\:30bf\:30a4\:30eb\:3092\:7d99\:627f\:3057\:305f\:3044
     (2) \:56f3\:30fb\:753b\:50cf\:30fb\:56f3\:8868\:3092\:9069\:5207\:306b\:633f\:5165\:3057\:305f\:3044 (\:7b87\:6761\:66f8\:304d\:30c6\:30ad\:30b9\:30c8\:3060\:3051\:3067\:306f\:898b\:65bc\:308a\:306a\:3044)
     (3) 2 \:6bb5\:7d44 Grid \:30ec\:30a4\:30a2\:30a6\:30c8 (Mathematica nb \:306f\:6a19\:6e96\:6a5f\:80fd\:304c\:306a\:3044)
     (4) \:30b5\:30f3\:30d7\:30eb\:30b9\:30e9\:30a4\:30c9\:306b\:5bc4\:305b\:305f\:8a00\:3044\:56de\:3057 (\:4f5c\:6210\:8005\:306e\:99b4\:67d3\:307f\:3092\:4fdd\:6301)
   
   \:539f\:5247 29 (T08 \:65b0\:8a2d): \:51fa\:529b\:5148\:306e\:30b9\:30bf\:30a4\:30eb\:7d99\:627f\:3092 caller \:306b\:52d5\:7684\:306b\:8a17\:3059
     \:30b9\:30bf\:30a4\:30eb\:66f8 (Normal use.nb \:7b49) \:306f\:74b0\:5883\:4f9d\:5b58\:306a\:306e\:3067 package \:5185\:306b\:57cb\:3081\:8fbc\:307e\:305a\:3001
     $ClaudeSlidesTemplatePath \:3067\:4e0a\:66f8\:304d\:53ef\:80fd\:306b\:3059\:308b\:3002CreateDocument \:306e
     StyleDefinitions \:30aa\:30d7\:30b7\:30e7\:30f3\:3067\:6e21\:305b\:3070\:3001committer \:81ea\:8eab\:306b\:5909\:66f4\:3092\:52a0\:3048\:305a\:306b
     \:7d99\:627f\:3067\:304d\:308b\:3002
   
   \:539f\:5247 30 (T08 \:65b0\:8a2d): SlideDraft \:306e Cell \:5f62\:5f0f\:306f Kind \:30d5\:30a3\:30fc\:30eb\:30c9\:3067\:62e1\:5f35
     \:300cText/Section/Subsection/...\:300d\:306e\:4f4d\:7f6e\:306b\:3001\:56f3\:3001\:753b\:50cf\:3001\:30b0\:30ea\:30c3\:30c9\:5c55\:958b\:3001
     Mathematica \:5f0f\:8a55\:4fa1\:7b49\:3092\:7b49\:4fa1\:306b\:6271\:3048\:308b\:3088\:3046\:300cKind\:300d\:30d5\:30a3\:30fc\:30eb\:30c9\:3092\:5c0e\:5165\:3059\:308b\:3002
     \:5f93\:6765\:306e Style + Content \:306f\:305d\:306e\:307e\:307e\:52d5\:304f (\:4e92\:63db\:6027\:4fdd\:6301)\:3002
  ══════════════════════════════════════════════════════════════════════ *)

ClearAll[$ClaudeSlidesTemplatePath];

$ClaudeSlidesTemplatePath::usage =
  "$ClaudeSlidesTemplatePath \:306f slide \:751f\:6210\:6642\:306b CreateDocument[..., StyleDefinitions -> v] \:306b\n" <>
  "\:6e21\:3059\:30c6\:30f3\:30d7\:30ec\:30fc\:30c8\:30d1\:30b9\:3002 String (\:30d5\:30a1\:30a4\:30eb\:30d1\:30b9) / StyleDefinitions \:306e\:5f15\:6570\n" <>
  "\:3068\:3057\:3066\:6709\:52b9\:306a\:5024\:3002\:672a\:8a2d\:5b9a\:306a\:3089 Global`$packageDirectory/Templates/slides-template.nb\n" <>
  "\:3092\:81ea\:52d5\:691c\:51fa\:3057\:3001\:305d\:308c\:3082\:306a\:3051\:308c\:3070\:30c6\:30f3\:30d7\:30ec\:30fc\:30c8\:306a\:3057\:3067\:4f5c\:308b\:3002";

(* ══════════════════════════════════════════════════════════════════════
   T07 (2026-04-19): Slide intent detection + style sanitization
   
   Phase 33 T06 に続く改修。test47.nb で明らかになった 3 問題を解決する:
     (A) Planner が 30 ページのスライド要求でも 1 task しか作らない
     (B) Worker の OutputSchema が汎用すぎて summary しか返らない
     (C) LLM が "Subsection (title slide)" のようなプローズ Style を
         返し、そのまま Cell[...] に流れて無効セルになる
   
   原則 24 (T07 新設): 入力から slide 生成意図を keyword/numeral で検出し、
                       planner/worker 双方に slide-aware なガイドを注入する。
                       これは原則 22 (content-based heuristic) の入力版。
   原則 25 (T07 新設): LLM が返す Style 文字列は Mathematica cell style の
                       allowlist で sanitize する。無効でもプローズから意味を
                       救出して最も近い基底 style にマッピングし、原則 23
                       (richness を保持) を守る。
   ══════════════════════════════════════════════════════════════════════ *)

ClearAll[iSanitizeCellStyle, iValidCellStyleQ, iDetectSlideIntent,
  iBuildSlidePlannerHint, iBuildSlideWorkerHint,
  iResolveTargetNotebook];

(* Mathematica の標準 cell style (Default.nb 由来) +
   SlideShow.nb 由来 + 本パッケージが吐くものを allowlist 化。 *)
$iValidCellStyles = {
  "Title", "Subtitle", "Subsubtitle",
  "Chapter", "Subchapter",
  "Section", "Subsection", "Subsubsection", "Subsubsubsection",
  "Text", "SmallText",
  "Item", "Subitem", "Subsubitem",
  "ItemNumbered", "SubitemNumbered", "SubsubitemNumbered",
  "ItemParagraph", "SubitemParagraph",
  "Input", "Output", "Code", "Program",
  "DisplayFormula", "DisplayFormulaNumbered",
  "EquationNumbered",
  "SectionInPresentation",
  "SubsectionInPresentation",
  "SubsubsectionInPresentation",
  "TextInPresentation",
  "SlideShowNavigationBar",
  "SlideShowHeader",
  "Print", "Message", "Author", "Affiliation",
  "Abstract", "Caption", "PageBreak"
};

iValidCellStyleQ[s_String] := MemberQ[$iValidCellStyles, s];
iValidCellStyleQ[_] := False;

iSanitizeCellStyle[raw_String] :=
  Module[{s = StringTrim[raw], base, lower, token},
    If[s === "", Return["Text", Module]];
    If[iValidCellStyleQ[s], Return[s, Module]];
    (* 括弧/修飾を除去して最初のトークンで試す *)
    base = First[
      StringSplit[s,
        RegularExpression["[\\s\\(\\)\\[\\]\\+/,:\\|]"]],
      s];
    base = StringTrim[base];
    If[iValidCellStyleQ[base], Return[base, Module]];
    (* プローズから意味救出 *)
    lower = ToLowerCase[s];
    token = Which[
      StringContainsQ[lower, "input"],        "Input",
      StringContainsQ[lower, "output"],       "Output",
      StringContainsQ[lower, "code"] ||
        StringContainsQ[lower, "program"],    "Code",
      StringContainsQ[lower, "subsubsection"],"Subsubsection",
      StringContainsQ[lower, "subsection"],   "Subsection",
      StringContainsQ[lower, "section"],      "Section",
      StringContainsQ[lower, "chapter"],      "Chapter",
      StringContainsQ[lower, "subtitle"],     "Subtitle",
      StringContainsQ[lower, "title"],        "Title",
      StringContainsQ[lower, "itemparagraph"] ||
        StringContainsQ[lower, "item paragraph"],
        "ItemParagraph",
      StringContainsQ[lower, "itemnumbered"] ||
        StringContainsQ[lower, "numbered"],
        "ItemNumbered",
      StringContainsQ[lower, "subitem"],      "Subitem",
      StringContainsQ[lower, "item"] ||
        StringContainsQ[lower, "bullet"],     "Item",
      StringContainsQ[lower, "presentation"] ||
        StringContainsQ[lower, "slide"] ||
        StringContainsQ[lower, "\:30b9\:30e9\:30a4\:30c9"],
        "TextInPresentation",
      StringContainsQ[lower, "text"],         "Text",
      True,                                   "Text"];
    token
  ];

iSanitizeCellStyle[s_] := iSanitizeCellStyle[ToString[s]];

(* ---- iDetectSlideIntent ----
   T07: 入力文字列から slide 生成意図を検出する。
   
   戻り値: <|"IsSlide" -> Bool, "PageCount" -> Integer|None,
            "Keywords" -> {...}|>
   --------------------------------------------------------------------- *)

iDetectSlideIntent[inputRaw_] :=
  Module[{input, lower, normalized, pageN = None, isSlide = False,
          kws = {}, countMatches},
    input = Which[
      StringQ[inputRaw], inputRaw,
      AssociationQ[inputRaw], ToString[Lookup[inputRaw, "Goal",
        ToString[inputRaw]]],
      True, ToString[inputRaw]];
    
    (* 全角数字 -> 半角数字 (Mathematica \:306f 16^^ \:3067 base-16 \:3092\:793a\:3059\:304c\:3001
       \:30b7\:30f3\:30d7\:30eb\:306b\:76f4\:63a5 StringReplace \:30eb\:30fc\:30eb\:30ea\:30b9\:30c8\:3067\:5bfe\:5fdc *)
    normalized = StringReplace[input, {
      "\:ff10" -> "0", "\:ff11" -> "1", "\:ff12" -> "2",
      "\:ff13" -> "3", "\:ff14" -> "4", "\:ff15" -> "5",
      "\:ff16" -> "6", "\:ff17" -> "7", "\:ff18" -> "8",
      "\:ff19" -> "9"}];
    
    lower = ToLowerCase[normalized];
    
    (* Keyword 検出 (日本語) *)
    If[StringContainsQ[normalized,
        "\:30b9\:30e9\:30a4\:30c9"] ||
       StringContainsQ[normalized,
        "\:30d7\:30ec\:30bc\:30f3"] ||
       StringContainsQ[normalized,
        "\:767a\:8868\:8cc7\:6599"],
      isSlide = True;
      AppendTo[kws, "slide-keyword-ja"]];
    
    (* Keyword 検出 (英語) *)
    If[AnyTrue[
        {"slide", "slides", "deck", "presentation", "powerpoint",
         "keynote"},
        StringContainsQ[lower, #] &],
      isSlide = True;
      AppendTo[kws, "slide-keyword-en"]];
    
    (* ページ数抽出 *)
    countMatches = Join[
      StringCases[normalized,
        n : (DigitCharacter..) ~~ Whitespace... ~~
          "\:30da\:30fc\:30b8" :> ToExpression[n]],
      StringCases[lower,
        n : (DigitCharacter..) ~~
          Whitespace... ~~ ("-" | "") ~~ Whitespace... ~~
          ("page" | "pages" | "slide" | "slides") :>
          ToExpression[n]]
    ];
    countMatches = Select[countMatches, IntegerQ[#] && # > 0 &];
    If[Length[countMatches] > 0,
      pageN = Max[countMatches];
      isSlide = True;
      AppendTo[kws, "page-count=" <> ToString[pageN]]];
    
    <|"IsSlide"   -> isSlide,
      "PageCount" -> pageN,
      "Keywords"  -> kws|>
  ];

(* ---- iResolveTargetNotebook ----
   T07b (2026-04-19 \:8ffd\:52a0): \:30b9\:30e9\:30a4\:30c9\:751f\:6210\:306a\:3069\:306e\:5927\:91cf\:66f8\:8fbc\:307f\:30bf\:30b9\:30af\:3067\:306f
   \:30e6\:30fc\:30b6\:306e\:4f5c\:696d notebook (EvaluationNotebook[]) \:3092\:7834\:58ca\:3057\:306a\:3044\:3088\:3046\:3001
   \:65b0\:898f notebook \:3092 CreateDocument[] \:3067\:751f\:6210\:3057 target \:3068\:3059\:308b\:3002
   
   \:4ed5\:69d8 (claude_multi_agent_orchestration_spec.md \:00a76.2): CreateNotebook
   \:306f committer \:3067\:306f Deny \:3060\:304c\:3001 \:30aa\:30fc\:30b1\:30b9\:30c8\:30ec\:30fc\:30b7\:30e7\:30f3\:5c64 (committer \:306e\:5916\:5074)
   \:304c\:4e8b\:524d\:306b notebook \:3092\:7528\:610f\:3057\:3066 targetNb \:3068\:3057\:3066\:6e21\:3059\:306e\:306f\:554f\:984c\:7121\:3057\:3002
   
   \:623b\:308a\:5024: <|"TargetNotebook" -> NotebookObject|None,
                  "Intent" -> <|...|>,
                  "CreatedNew" -> True|False|>
   --------------------------------------------------------------------- *)

iResolveTargetNotebook[task_, verbose_:False] :=
  Module[{intent, isSlide, targetNb, createdNew = False, isJa,
          templatePath, styleDefOpt, createdDoc},
    isJa    = $Language === "Japanese";
    intent  = iDetectSlideIntent[task];
    isSlide = TrueQ[intent["IsSlide"]];
    
    If[isSlide,
      (* T08: \:30c6\:30f3\:30d7\:30ec\:30fc\:30c8\:30d1\:30b9\:306e\:89e3\:6c7a
         1. $ClaudeSlidesTemplatePath \:304c\:8a2d\:5b9a\:6e08\:307f\:306a\:3089\:305d\:308c\:3092\:4f7f\:3046
         2. \:672a\:8a2d\:5b9a\:306a\:3089 Global`$packageDirectory/Templates/slides-template.nb
            \:3092\:691c\:51fa\:3057\:3001\:5b58\:5728\:3059\:308c\:3070\:4f7f\:3046
         3. \:3069\:3061\:3089\:3082\:306a\:3051\:308c\:3070\:30c6\:30f3\:30d7\:30ec\:30fc\:30c8\:306a\:3057\:3067 CreateDocument *)
      templatePath = Which[
        ValueQ[$ClaudeSlidesTemplatePath] &&
          (StringQ[$ClaudeSlidesTemplatePath] || 
            MatchQ[$ClaudeSlidesTemplatePath, _StyleDefinitions]),
          $ClaudeSlidesTemplatePath,
        StringQ[Quiet @ Check[Global`$packageDirectory, ""]] &&
          FileExistsQ[
            FileNameJoin[{Global`$packageDirectory, "Templates",
              "slides-template.nb"}]],
          FileNameJoin[{Global`$packageDirectory, "Templates",
            "slides-template.nb"}],
        True, None];
      
      styleDefOpt = If[templatePath =!= None,
        {StyleDefinitions -> templatePath}, {}];
      
      (* Slide-mode: CreateDocument \:3067\:65b0\:898f nb \:3092\:4f5c\:308b (\:30e6\:30fc\:30b6\:306e\:4f5c\:696d nb \:3092\:5b88\:308b)
         T08: template \:304c\:3042\:308c\:3070 StyleDefinitions \:3067\:7d99\:627f *)
      createdDoc = Quiet @ Check[
        CreateDocument[{},
          Sequence @@ Join[
            {WindowTitle -> If[isJa,
              "Claude \:751f\:6210 \:30b9\:30e9\:30a4\:30c9",
              "Claude-generated slides"]},
            styleDefOpt]],
        None];
      targetNb = createdDoc;
      
      If[MatchQ[targetNb, _NotebookObject],
        createdNew = True;
        Print[Style[
          If[isJa,
            "[ClaudeEval\:2192Orchestrator] \:30b9\:30e9\:30a4\:30c9\:751f\:6210\:30e2\:30fc\:30c9\:3092\:691c\:51fa\:3002\:65b0\:898f notebook \:306b\:30b3\:30df\:30c3\:30c8\:3057\:307e\:3059 (\:73fe\:5728\:306e notebook \:306f\:6e29\:5b58)\:3002" <>
              If[templatePath =!= None,
                " \:30c6\:30f3\:30d7\:30ec\:30fc\:30c8: " <> 
                  If[StringQ[templatePath], FileNameTake[templatePath], "(custom)"],
                " \:30c6\:30f3\:30d7\:30ec\:30fc\:30c8: \:306a\:3057"],
            "[ClaudeEval\:2192Orchestrator] Slide generation mode detected; committing to a new notebook (your current notebook is untouched)." <>
              If[templatePath =!= None,
                " Template: " <>
                  If[StringQ[templatePath], FileNameTake[templatePath], "(custom)"],
                " Template: none"]],
          RGBColor[0.1, 0.5, 0.2], Italic]],
        (* CreateDocument \:304c\:5931\:6557\:3057\:305f\:5834\:5408 (\:30d8\:30c3\:30c9\:30ec\:30b9\:7b49): EvaluationNotebook \:306b\:843d\:3068\:3059 *)
        targetNb = Quiet @ Check[EvaluationNotebook[], None];
        If[verbose && MatchQ[targetNb, _NotebookObject],
          Print[Style[
            If[isJa,
              "[ClaudeEval\:2192Orchestrator] CreateDocument \:5931\:6557\:3001 EvaluationNotebook \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002",
              "[ClaudeEval\:2192Orchestrator] CreateDocument failed, falling back to EvaluationNotebook."],
            RGBColor[0.8, 0.5, 0], Italic]]]],
      
      (* Non-slide: \:5f93\:6765\:306e\:6311\:52d5\:3092\:4fdd\:6301 *)
      targetNb = Quiet @ Check[EvaluationNotebook[], None]];
    
    If[!MatchQ[targetNb, _NotebookObject], targetNb = None];
    
    <|"TargetNotebook" -> targetNb,
      "Intent"         -> intent,
      "CreatedNew"     -> createdNew,
      "TemplatePath"   -> If[isSlide, templatePath, None]|>
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   Task 2: Real LLM Integration Support
   
   CI / mock-only \:74b0\:5883\:3067\:306f default disabled\:3002
   \:6709\:52b9\:5316\:65b9\:6cd5:
     $ClaudeOrchestratorRealLLMEndpoint = "ClaudeCode" | "CLI" | fn
     \:307e\:305f\:306f\:74b0\:5883\:5909\:6570 CLAUDE_ORCH_REAL_LLM = "ClaudeCode" | "CLI"
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

iRealLLMResolveEndpoint[] :=
  Module[{ep, envVar},
    ep = $ClaudeOrchestratorRealLLMEndpoint;
    envVar = Quiet @ Check[Environment["CLAUDE_ORCH_REAL_LLM"], None];
    Which[
      ep =!= None, ep,
      StringQ[envVar] && StringLength[envVar] > 0, envVar,
      True, None]
  ];

(* iResolveCLICommand: Windows \:3067\:306f claude.cmd \:3092\:9078\:629e (Task 2 / Task 4 \:5171\:7528)\:3002
   $ClaudeOrchestratorCLICommand \:304c String \:306a\:3089\:305d\:308c\:3092\:512a\:5148\:3001
   \:74b0\:5883\:5909\:6570 CLAUDE_ORCH_CLI_PATH \:6b21\:3001 Automatic \:306a\:3089 OS \:5224\:5b9a\:3002
   
   Windows + Automatic \:306e\:5834\:5408\:306f\:3055\:3089\:306b\:3001
   %APPDATA%\\npm\\claude.cmd \:304c\:5b58\:5728\:3059\:308c\:3070\:305d\:306e\:30d5\:30eb\:30d1\:30b9\:3092\:4f7f\:3046
   (kernel PATH \:306b npm \:304c\:306a\:304f\:3066\:3082\:8d77\:52d5\:3067\:304d\:308b\:3088\:3046\:306b)\:3002 *)
iResolveCLICommand[] :=
  Module[{v, envPath, appdata, candidate},
    v = $ClaudeOrchestratorCLICommand;
    envPath = Quiet @ Check[Environment["CLAUDE_ORCH_CLI_PATH"], None];
    Which[
      StringQ[v] && StringLength[v] > 0, v,
      StringQ[envPath] && StringLength[envPath] > 0, envPath,
      $OperatingSystem === "Windows",
        appdata = Quiet @ Check[Environment["APPDATA"], None];
        candidate = If[StringQ[appdata] && StringLength[appdata] > 0,
          FileNameJoin[{appdata, "npm", "claude.cmd"}],
          None];
        If[StringQ[candidate] && FileExistsQ[candidate],
          candidate, "claude.cmd"],
      True, "claude"]
  ];

(* iFixStdoutEncoding: Windows \:3067 RunProcess \:304c stdout \:3092 $SystemCharacterEncoding
   (CP932/Shift-JIS \:7b49) \:3067 decode \:3059\:308b\:305f\:3081\:306e\:5f8c\:65b9\:4e92\:63db\:7528 fallback\:3002
   T24 \:4ee5\:964d\:306e\:4e3b\:7d4c\:8def\:306f iRunCLIUTF8 (chcp 65001 + \:30d5\:30a1\:30a4\:30eb\:7d4c\:7531) \:3092\:4f7f\:3046\:306e\:3067
   \:3053\:306e\:30d8\:30eb\:30d1\:3092\:901a\:308b\:3053\:3068\:306f\:307b\:307c\:306a\:3044\:304c\:3001 \:7591\:3044\:8d64 \:6587\:5b57\:5316\:3051\:6642\:306e\:6700\:7d42 fallback \:3068\:3057\:3066\:6b8b\:3059\:3002 *)
iFixStdoutEncoding[s_String] :=
  Module[{bytes, decoded},
    If[$OperatingSystem =!= "Windows", Return[s, Module]];
    bytes = Quiet @ Check[
      StringToByteArray[s, $SystemCharacterEncoding], $Failed];
    If[bytes === $Failed || !ByteArrayQ[bytes], Return[s, Module]];
    decoded = Quiet @ Check[
      ByteArrayToString[bytes, "UTF-8"], $Failed];
    If[decoded === $Failed || !StringQ[decoded], s, decoded]
  ];

iFixStdoutEncoding[x_] := x;

(* iRunCLIUTF8: Windows \:3067\:78ba\:5b9f\:306b UTF-8 stdout \:3092\:53d6\:5f97\:3059\:308b\:305f\:3081\:306e CLI \:547c\:3073\:51fa\:3057\:3002
   claudecode.wl \:306e iMakeBat \:30d1\:30bf\:30fc\:30f3\:3092\:53c2\:8003 (rule 11 \:904b\:7528: \:30d5\:30a1\:30a4\:30eb\:30d5\:30a9\:30fc\:30de\:30c3\:30c8\:3092\:500b\:5225\:306b\:5b9f\:88c5)\:ff1a
     1. .bat \:30d5\:30a1\:30a4\:30eb\:3092 ASCII \:3067\:66f8\:304d\:3001 \:5148\:982d\:3067 chcp 65001 \:3092\:5b9f\:884c\:3057\:3066
        \:30b3\:30f3\:30bd\:30fc\:30eb\:30b3\:30fc\:30c9\:30da\:30fc\:30b8\:3092 UTF-8 \:306b\:3059\:308b
     2. prompt \:3092 UTF-8 \:30d0\:30a4\:30c8\:3067\:30d5\:30a1\:30a4\:30eb\:306b\:66f8\:304f
     3. claude \:3092 stdin \:30ea\:30c0\:30a4\:30ec\:30af\:30c8\:3067\:8d77\:52d5\:3001 stdout \:3092\:30d5\:30a1\:30a4\:30eb\:306b\:30ea\:30c0\:30a4\:30ec\:30af\:30c8
     4. stdout \:30d5\:30a1\:30a4\:30eb\:3092\:30d0\:30a4\:30c8\:5217\:3068\:3057\:3066\:8aad\:307f\:3001 UTF-8 \:3067 decode
   \:3053\:308c\:3067 Mathematica \:306e\:30c7\:30d5\:30a9\:30eb\:30c8\:6587\:5b57\:30b3\:30fc\:30c9\:30da\:30fc\:30b8\:3092\:5b8c\:5168\:306b\:30d0\:30a4\:30d1\:30b9\:3067\:304d\:308b\:3002
   
   \:975e Windows \:74b0\:5883\:3067\:306f stdin \:7d4c\:7531\:306e\:30b7\:30f3\:30d7\:30eb\:306a RunProcess \:3067\:3088\:3044 (UTF-8 \:304c\:65e2\:5b9a)\:3002 *)
iRunCLIUTF8[cli_String, prompt_String] :=
  Module[{tmpBase, promptFile, outFile, batFile, bc, strm, runRes,
          exitCode, stdoutText, stderrText, workDir},
    (* Rule 51: $TemporaryDirectory \:306f\:4f7f\:308f\:305a\:3001
       ClaudeCode`$ClaudeWorkingDirectory \:3092\:4f7f\:3046\:3002
       \:3053\:308c\:306b\:3088\:308a Claude CLI \:306e --add-dir \:30a2\:30af\:30bb\:30b9\:6a29\:5236\:5fa1\:4e0b\:306b\:51fa\:305b\:308b\:3002
       ClaudeCode \:304c\:30ed\:30fc\:30c9\:3055\:308c\:3066\:3044\:306a\:3044 \:304a\:3088\:3073 CLI fork \:5185\:3067\:306f
       $HomeDirectory/"Claude Working" \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3059\:308b\:3002 *)
    workDir = Quiet @ Check[
      If[StringQ[ClaudeCode`$ClaudeWorkingDirectory] &&
         StringLength[ClaudeCode`$ClaudeWorkingDirectory] > 0,
        ClaudeCode`$ClaudeWorkingDirectory,
        FileNameJoin[{$HomeDirectory, "Claude Working"}]],
      FileNameJoin[{$HomeDirectory, "Claude Working"}]];
    If[!DirectoryQ[workDir],
      Quiet @ Check[CreateDirectory[workDir], Null]];
    (* \:6700\:7d42 fallback: CreateDirectory \:3082\:5931\:6557\:3057\:305f\:3089\:65e7\:52d5\:4f5c ($TemporaryDirectory) *)
    If[!DirectoryQ[workDir], workDir = $TemporaryDirectory];
    tmpBase = FileNameJoin[{workDir,
      "orch_cli_" <> ToString[UnixTime[]] <> "_" <>
      ToString[RandomInteger[99999]]}];
    promptFile = tmpBase <> "_prompt.txt";
    outFile    = tmpBase <> "_out.txt";
    batFile    = tmpBase <> "_run.bat";
    
    (* prompt \:3092 UTF-8 \:30d0\:30a4\:30c8\:3067\:30d5\:30a1\:30a4\:30eb\:306b *)
    strm = Quiet @ Check[
      OpenWrite[promptFile, BinaryFormat -> True], $Failed];
    If[strm === $Failed,
      Return[<|"StdOut" -> "", "StdErr" -> "OpenWrite failed",
               "ExitCode" -> -1|>]];
    Quiet @ BinaryWrite[strm,
      ExportString[prompt, "Text", CharacterEncoding -> "UTF-8"]];
    Quiet @ Close[strm];
    
    Which[
      $OperatingSystem === "Windows",
        (* Windows: bat \:30d5\:30a1\:30a4\:30eb\:7d4c\:7531\:3067 chcp 65001 + \:30ea\:30c0\:30a4\:30ec\:30af\:30c8 *)
        bc = "@echo off\r\n" <>
             "chcp 65001 > nul\r\n" <>
             "\"" <> cli <> "\" -p --output-format json" <>
             " < \"" <> promptFile <> "\" > \"" <> outFile <> "\" 2>&1\r\n";
        strm = Quiet @ Check[
          OpenWrite[batFile, BinaryFormat -> True], $Failed];
        If[strm === $Failed,
          Quiet @ DeleteFile[promptFile];
          Return[<|"StdOut" -> "", "StdErr" -> "bat OpenWrite failed",
                   "ExitCode" -> -1|>]];
        Quiet @ BinaryWrite[strm,
          ExportString[bc, "Text", CharacterEncoding -> "ASCII"]];
        Quiet @ Close[strm];
        runRes = Quiet @ Check[
          RunProcess[{"cmd", "/c", batFile}, All, ""], $Failed],
      True,
        (* Unix: stdin \:7d4c\:7531\:306e\:30b7\:30f3\:30d7\:30eb\:306a\:547c\:3073\:51fa\:3057 *)
        runRes = Quiet @ Check[
          RunProcess[{cli, "-p", "--output-format", "json"}, All, prompt],
          $Failed]];
    
    exitCode = If[AssociationQ[runRes],
      Lookup[runRes, "ExitCode", -1], -1];
    stderrText = If[AssociationQ[runRes],
      Lookup[runRes, "StandardError", ""], ""];
    
    (* stdout \:3092\:5fa9\:5143 *)
    stdoutText = Which[
      (* Windows: outFile \:3092 UTF-8 \:3067\:8aad\:307f\:76f4\:3059 *)
      $OperatingSystem === "Windows",
        If[FileExistsQ[outFile],
          Quiet @ Check[
            Import[outFile, "Text", CharacterEncoding -> "UTF-8"], ""],
          ""],
      (* Unix: runRes \:306e StandardOutput *)
      AssociationQ[runRes],
        Lookup[runRes, "StandardOutput", ""],
      True, ""];
    
    (* \:30af\:30ea\:30fc\:30f3\:30a2\:30c3\:30d7 *)
    Quiet @ DeleteFile /@ Select[
      {promptFile, outFile, batFile}, FileExistsQ];
    
    <|"StdOut"   -> If[StringQ[stdoutText], stdoutText, ""],
      "StdErr"   -> If[StringQ[stderrText], stderrText, ""],
      "ExitCode" -> exitCode|>
  ];

iRunCLIUTF8[___] := <|"StdOut" -> "", "StdErr" -> "InvalidArguments",
                      "ExitCode" -> -1|>;

(* iUnwrapLLMResponse: LLM \:8fd4\:308a\:5024\:306e JSON \:30e9\:30c3\:30d1\:30fc\:3092\:307b\:3069\:304d\:3001\:5b9f\:30c6\:30ad\:30b9\:30c8\:3092\:53d6\:308b\:3002
   Claude CLI (--output-format json) \:306f {"type":"result", "result":"\:5b9f\:5fdc\:7b54"}\:3001
   \:4ed6 {"content":[{"type":"text","text":"..."}]} \:7b49\:3002
   \:30e9\:30c3\:30d7\:3067\:306a\:3044\:3082\:306e\:306f\:305d\:306e\:307e\:307e\:8fd4\:3059\:3002 *)
iUnwrapLLMResponse[resp_] :=
  Module[{parsed, content, first},
    Which[
      StringQ[resp],
        parsed = Quiet @ Check[
          Developer`ReadRawJSONString[resp], Null];
        Which[
          (* Claude CLI: <|"type"->"result", "result"->String|> *)
          AssociationQ[parsed] &&
            StringQ[Lookup[parsed, "result", None]],
            Lookup[parsed, "result", resp],
          (* Content array: <|"content"->{<|"type","text","text"|>,...}|> *)
          AssociationQ[parsed] &&
            ListQ[Lookup[parsed, "content", None]] &&
            Length[Lookup[parsed, "content", {}]] > 0,
            content = Lookup[parsed, "content", {}];
            first = First[content, <||>];
            If[AssociationQ[first] &&
               StringQ[Lookup[first, "text", None]],
              Lookup[first, "text", resp], resp],
          (* \:30e9\:30c3\:30d7\:3058\:3083\:306a\:3044 = \:672c\:5f53\:306e JSON \:5fdc\:7b54 or \:5e73\:6587\:5b57\:5217 *)
          True, resp],
      AssociationQ[resp] &&
        StringQ[Lookup[resp, "result", None]],
        Lookup[resp, "result", ""],
      AssociationQ[resp] &&
        StringQ[Lookup[resp, "text", None]],
        Lookup[resp, "text", ""],
      True, ToString[resp]]
  ];

ClaudeRealLLMAvailable[] := iRealLLMResolveEndpoint[] =!= None;

ClaudeRealLLMQuery[prompt_String] :=
  Module[{ep = iRealLLMResolveEndpoint[], res},
    Which[
      ep === None,
        $Failed,
      ep === "ClaudeCode" || ep === "claude-code",
        (* T27: ClaudeQuery \:306f\:975e\:540c\:671f (job id \:304c\:8fd4\:308b) \:306a\:306e\:3067\:540c\:671f\:7248\:306e
           ClaudeQueryBg \:3092\:4f7f\:3046\:3002 Fallback -> False (default) \:3067
           Claude Code CLI \:3092 RunProcess \:7d4c\:7531\:3067\:540c\:671f\:547c\:3073\:51fa\:3057\:3002 *)
        res = Quiet @ Check[
          ClaudeCode`ClaudeQueryBg[prompt],
          $Failed];
        If[res === $Failed, $Failed, iUnwrapLLMResponse[res]],
      ep === "CLI" || ep === "cli",
        res = iRunCLIUTF8[iResolveCLICommand[], prompt];
        If[!AssociationQ[res] || Lookup[res, "ExitCode", -1] =!= 0,
          $Failed,
          iUnwrapLLMResponse[Lookup[res, "StdOut", ""]]],
      MatchQ[ep, _Function | _Symbol],
        res = Quiet @ Check[ep[prompt], $Failed];
        If[res === $Failed, $Failed, iUnwrapLLMResponse[res]],
      True, $Failed]
  ];

ClaudeRealLLMQuery[_] := $Failed;

(* ClaudeRealLLMDiagnose: real LLM \:547c\:3073\:51fa\:3057\:306e\:5207\:308a\:5206\:3051\:7528\:3002
   CLI \:5b9f\:884c\:3001 JSON parse \:6210\:7acb\:3001 unwrap \:7d50\:679c\:3092\:5168\:3066\:898b\:3048\:308b\:5f62\:3067\:8fd4\:3059\:3002 *)
ClaudeRealLLMDiagnose[prompt_String] :=
  Module[{ep, cli, res, unwrapped, parsedJson, stdout},
    ep = iRealLLMResolveEndpoint[];
    cli = iResolveCLICommand[];
    Which[
      ep === None,
        <|"Status" -> "NoEndpoint",
          "Hint" -> "Set $ClaudeOrchestratorRealLLMEndpoint first."|>,
      ep === "CLI" || ep === "cli",
        res = iRunCLIUTF8[cli, prompt];
        If[!AssociationQ[res],
          Return[<|"Status"   -> "RunProcessFailed",
                   "Endpoint" -> ep,
                   "CLI"      -> cli,
                   "Note"     -> "iRunCLIUTF8 returned non-Association."|>]];
        stdout = Lookup[res, "StdOut", ""];
        unwrapped = iUnwrapLLMResponse[stdout];
        parsedJson = Quiet @ Check[
          Developer`ReadRawJSONString[unwrapped], $Failed];
        <|"Status"      -> "OK",
          "Endpoint"    -> ep,
          "CLI"         -> cli,
          "ExitCode"    -> Lookup[res, "ExitCode", -1],
          "StdOutHead"  -> StringTake[stdout, UpTo[300]],
          "StdErrHead"  -> StringTake[
            Lookup[res, "StdErr", ""], UpTo[200]],
          "Unwrapped"   -> StringTake[
            If[StringQ[unwrapped], unwrapped, ToString[unwrapped]],
            UpTo[300]],
          "UnwrapKind"  -> Which[
            unwrapped === stdout, "NoUnwrap",
            StringLength[If[StringQ[unwrapped], unwrapped, ""]] <
              StringLength[stdout], "Unwrapped",
            True, "Other"],
          "JSONParsed"  -> AssociationQ[parsedJson]|>,
      ep === "ClaudeCode" || ep === "claude-code",
        (* T27: ClaudeQueryBg \:3067\:540c\:671f\:53d6\:5f97\:3002 *)
        res = Quiet @ Check[
          ClaudeCode`ClaudeQueryBg[prompt], $Failed];
        <|"Status"      -> "OK",
          "Endpoint"    -> ep,
          "ResponseHead" -> StringTake[
            If[StringQ[res], res, ToString[res]], UpTo[300]]|>,
      MatchQ[ep, _Function | _Symbol],
        res = Quiet @ Check[ep[prompt], $Failed];
        <|"Status"   -> "OK",
          "Endpoint" -> "Custom",
          "ResponseHead" -> StringTake[
            If[StringQ[res], res, ToString[res]], UpTo[300]]|>,
      True, <|"Status" -> "UnknownEndpoint", "Endpoint" -> ep|>]
  ];

ClaudeRealLLMDiagnose[_] :=
  <|"Status" -> "InvalidInput"|>;

(* ClaudeRealLLMDiagnosePlan: planner \:30d1\:30a4\:30d7\:30e9\:30a4\:30f3\:3092\:5b9f LLM \:3067\:5b9f\:884c\:3057\:3001
   \:305d\:306e\:7d50\:679c\:3068 raw \:5fdc\:7b54\:3092\:898b\:3048\:308b\:5f62\:3067\:8fd4\:3059 (W1 \:306e\:5207\:308a\:5206\:3051\:7528)\:3002 *)
ClaudeRealLLMDiagnosePlan[input_String] :=
  Module[{plan, tasksList, status, err, raw, rawStr, extracted, parsed},
    If[iRealLLMResolveEndpoint[] === None,
      Return[<|"Status" -> "NoEndpoint"|>]];
    plan = ClaudePlanTasks[input,
      "Planner"       -> "LLM",
      "QueryFunction" -> ClaudeRealLLMQuery,
      "MaxTasks"      -> 3];
    tasksList = Lookup[plan, "Tasks", {}];
    status = Lookup[plan, "Status", "Unknown"];
    err = Lookup[plan, "Error", None];
    raw = Lookup[plan, "RawResponse", ""];
    rawStr = If[StringQ[raw], raw, ToString[raw]];
    (* \:8ffd\:52a0\:8a3a\:65ad: \:62bd\:51fa\:3068 parse \:3092\:5358\:72ec\:3067\:8a66\:3057\:3066\:30b9\:30c6\:30c3\:30d7\:5225\:306b\:30c1\:30a7\:30c3\:30af *)
    extracted = iExtractJSONFromResponse[rawStr];
    parsed = iParseJSON[extracted];
    <|"PlanStatus"      -> status,
      "TaskCount"       -> Length[tasksList],
      "Error"           -> err,
      "RawResponseHead" -> StringTake[rawStr, UpTo[800]],
      "ExtractedHead"   -> StringTake[
        If[StringQ[extracted], extracted, ToString[extracted]],
        UpTo[400]],
      "ExtractedParseable" -> (parsed =!= $Failed),
      "ParsedTasksKey"     -> If[AssociationQ[parsed],
        KeyExistsQ[parsed, "Tasks"], Missing["NotAssoc"]],
      "FirstTaskId"     -> If[Length[tasksList] > 0,
        Lookup[First[tasksList], "TaskId", None], None],
      "FirstTaskRole"   -> If[Length[tasksList] > 0,
        Lookup[First[tasksList], "Role", None], None],
      "FirstTaskGoal"   -> If[Length[tasksList] > 0,
        Lookup[First[tasksList], "Goal", None], None]|>
  ];

ClaudeRealLLMDiagnosePlan[_] := <|"Status" -> "InvalidInput"|>;

(* ════════════════════════════════════════════════════════
   1. Role / Capability 定義 (spec §10)
   ════════════════════════════════════════════════════════ *)

$ClaudeOrchestratorRoles = {
  "Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"
};

(* Role ごとの allowed capability。
   worker (Explore/Plan/Draft/Verify/Reduce) は一切 notebook に
   書き込めない。committer のみ NotebookWrite を許可する。
   
   Capability は現状「意図のラベル」であり、実際の拒否は
   $ClaudeOrchestratorDenyHeads と worker adapter の
   validation 層で強制する。 *)
$ClaudeOrchestratorCapabilities = <|
  "Explore" -> {"ReadNotebookSnapshot", "ReadArtifacts", "StructuredOutput"},
  "Plan"    -> {"ReadArtifacts", "StructuredOutput"},
  "Draft"   -> {"ReadArtifacts", "StructuredOutput"},
  "Verify"  -> {"ReadArtifacts", "StructuredOutput"},
  "Reduce"  -> {"ReadArtifacts", "StructuredOutput"},
  "Commit"  -> {"ReadArtifacts", "StructuredOutput", "NotebookWrite"}
|>;

(* worker が提案したら必ず拒否する head。
   committer だけは NotebookWrite / Cell / CellPrint / NBAccess の
   書き込み API を許可される。
   
   EvaluationNotebook[] は committer では置換するため Deny リスト
   には入れず、代わりに iRewriteCommitterHeldExpr で書き換える。 *)
$ClaudeOrchestratorDenyHeads = {
  "NotebookWrite",
  "CreateNotebook",
  "DocumentNotebook",
  "NotebookPut",
  "NotebookClose",
  "NotebookSave",
  "NotebookDelete",
  "Export",
  "Put",
  "PutAppend",
  "DeleteFile",
  "DeleteDirectory",
  "CreateDirectory",
  "RenameFile",
  "CopyFile",
  "RunProcess",
  "StartProcess",
  "ExternalEvaluate",
  "SystemCredential",
  "URLRead",
  "URLExecute",
  "URLFetch",
  "ClaudeAttach",
  "SelectionEvaluate",
  "CellPrint"
};

(* Committer の場合は一部を許可する差分リスト *)
$iCommitterAllowedHeads = {
  "NotebookWrite",
  "Export",           (* 画像保存等に必要 *)
  "Put", "PutAppend"  (* ログ書き込みに必要 *)
};

(* ════════════════════════════════════════════════════════
   2. TaskSpec schema (spec §7)
   ════════════════════════════════════════════════════════ *)

$iTaskSpecRequiredKeys = {
  "TaskId", "Role", "Goal", "Inputs", "Outputs",
  "Capabilities", "DependsOn", "ExpectedArtifactType", "OutputSchema"
};

ClaudeValidateTaskSpec[taskSpec_Association] :=
  Module[{errs = {}, tasks, allIds, missingKeys, tid, role, deps,
          roleStr},
    tasks = Lookup[taskSpec, "Tasks", None];
    If[!ListQ[tasks],
      AppendTo[errs, iL["Tasks \:30ad\:30fc\:304c\:30ea\:30b9\:30c8\:3067\:306a\:3044",
                         "Tasks key is not a list"]];
      Return[<|"Valid" -> False, "Errors" -> errs|>]];
    
    If[Length[tasks] === 0,
      Return[<|"Valid" -> True, "Errors" -> {},
               "Note" -> "Empty task list"|>]];
    
    (* 各タスクのキー検査 *)
    allIds = {};
    Do[
      If[!AssociationQ[t],
        AppendTo[errs,
          iL["\:30bf\:30b9\:30af\:304c Association \:3067\:306a\:3044",
             "Task is not an Association"]];
        Continue[]];
      missingKeys = Complement[$iTaskSpecRequiredKeys, Keys[t]];
      If[Length[missingKeys] > 0,
        AppendTo[errs,
          iL["\:30bf\:30b9\:30af ", "Task "] <>
          ToString[Lookup[t, "TaskId", "?"]] <>
          iL[" \:306b\:5fc5\:9808\:30ad\:30fc\:304c\:4e0d\:8db3: ",
             " is missing required keys: "] <>
          StringRiffle[missingKeys, ", "]]];
      tid = Lookup[t, "TaskId", ""];
      AppendTo[allIds, tid];
      role = Lookup[t, "Role", ""];
      roleStr = If[StringQ[role], role, ToString[role]];
      If[!MemberQ[$ClaudeOrchestratorRoles, roleStr],
        AppendTo[errs,
          "TaskId \"" <> tid <> "\" " <>
          iL["\:306e Role \:304c\:4e0d\:6b63: ", "has invalid Role: "] <>
          roleStr]],
      {t, tasks}];
    
    (* 依存関係検査 *)
    Do[
      If[AssociationQ[t],
        tid = Lookup[t, "TaskId", ""];
        deps = Lookup[t, "DependsOn", {}];
        If[!ListQ[deps],
          AppendTo[errs,
            "TaskId \"" <> tid <> "\" " <>
            iL["\:306e DependsOn \:304c\:30ea\:30b9\:30c8\:3067\:306a\:3044",
               "has non-list DependsOn"]],
          Do[
            If[!MemberQ[allIds, d],
              AppendTo[errs,
                "TaskId \"" <> tid <> "\" " <>
                iL["\:306e\:4f9d\:5b58\:5148 ", "depends on "] <>
                "\"" <> ToString[d] <> "\" " <>
                iL["\:304c\:5b58\:5728\:3057\:306a\:3044", "which doesn't exist"]]],
            {d, deps}]]],
      {t, tasks}];
    
    <|"Valid" -> (Length[errs] === 0), "Errors" -> errs|>
  ];

ClaudeValidateTaskSpec[_] :=
  <|"Valid" -> False,
    "Errors" -> {iL["TaskSpec \:304c Association \:3067\:306a\:3044",
                    "TaskSpec is not an Association"]}|>;

(* ── 依存関係順トポロジカルソート ── *)
iTopologicalSortTasks[tasks_List] :=
  Module[{remaining = tasks, sorted = {}, done = {}, ready, progress},
    While[Length[remaining] > 0,
      ready = Select[remaining,
        Function[t, AllTrue[Lookup[t, "DependsOn", {}],
                            MemberQ[done, #] &]]];
      If[Length[ready] === 0,
        (* 循環依存 → エラー *)
        Return[$Failed]];
      progress = ready;
      sorted = Join[sorted, progress];
      done = Join[done, Map[Lookup[#, "TaskId", ""] &, progress]];
      remaining = Complement[remaining, progress]];
    sorted
  ];

(* ════════════════════════════════════════════════════════
   3. ClaudePlanTasks (spec §17.1)
   ════════════════════════════════════════════════════════ *)

Options[ClaudePlanTasks] = {
  "Planner"       -> Automatic,
  "MaxTasks"      -> 10,
  "QueryFunction" -> Automatic
};

ClaudePlanTasks[input_, opts:OptionsPattern[]] :=
  Module[{planner, maxTasks, queryFn, result, validation},
    planner  = OptionValue["Planner"];
    maxTasks = OptionValue["MaxTasks"];
    queryFn  = OptionValue["QueryFunction"];
    
    (* "LLM" \:6307\:5b9a: LLM-backed planner \:3092\:4f7f\:7528 (Stage 2) *)
    If[planner === "LLM",
      result = iLLMPlannerFn[input,
        <|"MaxTasks" -> maxTasks, "QueryFunction" -> queryFn|>];
      If[!AssociationQ[result] || !KeyExistsQ[result, "Tasks"],
        Return[<|"Tasks" -> {},
                 "Status" -> "Failed",
                 "Error"  -> Lookup[result, "Error",
                   iL["LLM planner \:304c\:5931\:6557",
                      "LLM planner failed"]]|>]];
      (* iLLMPlannerFn \:304c\:65e2\:306b Status="Failed" \:3092\:8fd4\:3057\:3066\:3044\:308c\:3070\:305d\:306e\:307e\:307e\:8fd4\:3059 *)
      If[Lookup[result, "Status", ""] === "Failed",
        Return[result]];
      validation = ClaudeValidateTaskSpec[result];
      If[!TrueQ[validation["Valid"]],
        Return[<|"Tasks" -> Lookup[result, "Tasks", {}],
                 "Status" -> "InvalidPlan",
                 "ValidationErrors" -> validation["Errors"]|>]];
      Return[Append[result, "Status" -> "Planned"]]];
    
    If[planner === Automatic,
      (* Stage 1 \:306e\:65e2\:5b9a: \:5358\:4e00 Explore \:30bf\:30b9\:30af\:3092\:8fd4\:3059 minimum planner\:3002
         \:672c\:683c\:7684\:306a planner \:306f caller \:304c\:4f9b\:7d66\:3059\:308b\:3002 *)
      planner = iDefaultPlanner];
    
    If[!MatchQ[planner, _Function | _Symbol],
      Return[<|"Tasks" -> {},
               "Status" -> "Failed",
               "Error"  -> iL["Planner \:304c\:95a2\:6570\:3067\:306f\:306a\:3044",
                              "Planner is not a function"]|>]];
    
    result = planner[input, <|"MaxTasks" -> maxTasks|>];
    
    If[!AssociationQ[result] || !KeyExistsQ[result, "Tasks"],
      Return[<|"Tasks" -> {},
               "Status" -> "Failed",
               "Error"  -> iL["Planner \:304c\:4e0d\:6b63\:306a\:5f62\:5f0f\:3092\:8fd4\:3057\:305f",
                              "Planner returned invalid format"]|>]];
    
    validation = ClaudeValidateTaskSpec[result];
    If[!TrueQ[validation["Valid"]],
      Return[<|"Tasks" -> Lookup[result, "Tasks", {}],
               "Status" -> "InvalidPlan",
               "ValidationErrors" -> validation["Errors"]|>]];
    
    Append[result, "Status" -> "Planned"]
  ];

(* ── 既定プランナー (Stage 1):
   入力を単一の Explore タスクに丸める。
   本番では caller 側で LLM ベースの planner を渡す。
   
   T07: slide \:5fc5\:5408\:3044\:3092\:691c\:51fa\:3057\:305f\:5834\:5408\:306f Draft task \:3092\:5165\:308c\:305f\:308a
        \:3063\:3068\:3057\:305f\:5206\:89e3\:3092\:8fd4\:3059 (LLM \:306a\:3057\:3067\:3082\:300c30 \:30da\:30fc\:30b8\:8981\:6c42\:300d\:306b
        \:8fd1\:3044\:5f62\:3067\:5fdc\:3048\:308b\:3088\:3046\:306b)\:3002 *)
iDefaultPlanner[input_, _Association] :=
  Module[{intent, pageN},
    intent = iDetectSlideIntent[input];
    pageN  = Lookup[intent, "PageCount", None];
    If[TrueQ[intent["IsSlide"]],
      <|
        "Tasks" -> {
          <|
            "TaskId"               -> "t1",
            "Role"                 -> "Explore",
            "Goal"                 -> "\:30b9\:30e9\:30a4\:30c9\:4f5c\:6210\:8cc7\:6599\:306e\:8abf\:67fb\:3068\:6574\:7406: " <>
              ToString[input],
            "Inputs"               -> {},
            "Outputs"              -> {"exploreResult"},
            "Capabilities"         ->
              $ClaudeOrchestratorCapabilities["Explore"],
            "DependsOn"            -> {},
            "ExpectedArtifactType" -> "ExploreSummary",
            "OutputSchema"         -> <|
              "Summary"   -> "String",
              "KeyPoints" -> "List[String]"|>
          |>,
          <|
            "TaskId"               -> "t2",
            "Role"                 -> "Draft",
            "Goal"                 ->
              If[IntegerQ[pageN] && pageN > 0,
                ToString[pageN] <>
                  " \:30da\:30fc\:30b8\:306e SlideDraft \:3092\:751f\:6210: ",
                "SlideDraft \:3092\:751f\:6210: "] <>
              ToString[input],
            "Inputs"               -> {"exploreResult"},
            "Outputs"              -> {"slideDraft"},
            "Capabilities"         ->
              $ClaudeOrchestratorCapabilities["Draft"],
            "DependsOn"            -> {"t1"},
            "ExpectedArtifactType" -> "SlideDraft",
            "OutputSchema"         -> <|
              "SlideDraft" -> "List[Association]"|>
          |>
        }
      |>,
      (* \:901a\:5e38\:30bf\:30b9\:30af: \:5f93\:6765\:901a\:308a 1 task *)
      <|
        "Tasks" -> {
          <|
            "TaskId"               -> "t1",
            "Role"                 -> "Explore",
            "Goal"                 -> ToString[input],
            "Inputs"               -> {},
            "Outputs"              -> {"exploreResult"},
            "Capabilities"         ->
              $ClaudeOrchestratorCapabilities["Explore"],
            "DependsOn"            -> {},
            "ExpectedArtifactType" -> "ExploreSummary",
            "OutputSchema"         -> <|
              "Summary"   -> "String",
              "KeyPoints" -> "List[String]"|>
          |>
        }
      |>]
  ];

(* ════════════════════════════════════════════════════════
   3b. LLM-backed Planner (Stage 2)
   
   ClaudeCode`ClaudeQueryBg (同期版) を使って LLM にタスク分解を依頼し、
   JSON 形式の TaskSpec を得る。プロンプトは本パッケージ内に閉じる
   (rule 11 §3: 基盤パッケージの $claudeMathPromptPrefix 非汚染)。
   
   使い方:
     ClaudePlanTasks[input, "Planner" -> "LLM"]
     ClaudePlanTasks[input, "Planner" -> "LLM",
       "QueryFunction" -> myQueryFn,
       "MaxTasks" -> 5]
   ════════════════════════════════════════════════════════ *)

(* ── JSON パース共通ユーティリティ ── *)

(* LLM \:5fdc\:7b54\:304b\:3089 JSON \:30d6\:30ed\:30c3\:30af\:3092\:62bd\:51fa\:3002
   ```json ... ``` \:30d5\:30a7\:30f3\:30b9 / \:751f JSON / \:30c6\:30ad\:30b9\:30c8\:6df7\:5728\:306e\:3044\:305a\:308c\:306b\:3082\:5bfe\:5fdc\:3002 *)
iExtractJSONFromResponse[response_String] :=
  Module[{fenced, braceStart, braceEnd, bracketStart, bracketEnd,
          bPos, sPos},
    (* 1. ```json ... ``` \:30d5\:30a7\:30f3\:30b9\:3092\:63a2\:3059 (Shortest \:3067\:6700\:77ed\:4e00\:81f4) *)
    fenced = StringCases[response,
      "```json" ~~ Whitespace ... ~~ Shortest[j__] ~~ "```" :> j,
      1];
    If[Length[fenced] > 0,
      Return[StringTrim[First[fenced]]]];
    
    (* 1b. \:8a00\:8a9e\:30bf\:30b0\:304c JSON / json / javascript \:306a\:3069 *)
    fenced = StringCases[response,
      "```" ~~ ("JSON" | "json" | "javascript" | "js") ~~
        Whitespace ... ~~ Shortest[j__] ~~ "```" :> j,
      1];
    If[Length[fenced] > 0,
      Return[StringTrim[First[fenced]]]];
    
    (* 2. ``` ... ``` (\:8a00\:8a9e\:6307\:5b9a\:306a\:3057) \:3092\:63a2\:3059 *)
    fenced = StringCases[response,
      "```" ~~ Whitespace ... ~~ Shortest[j__] ~~ "```" :> j,
      1];
    If[Length[fenced] > 0 &&
       StringContainsQ[StringTrim[First[fenced]], "{"],
      Return[StringTrim[First[fenced]]]];
    
    (* 3. { \:3068 [ \:306e\:6700\:521d\:306e\:4f4d\:7f6e\:3092\:6bd4\:8f03\:3057\:3001\:5148\:306b\:51fa\:73fe\:3059\:308b\:65b9\:3092\:512a\:5148 *)
    braceStart   = StringPosition[response, "{", 1];
    bracketStart = StringPosition[response, "[", 1];
    bPos = If[Length[braceStart] > 0, braceStart[[1, 1]], Infinity];
    sPos = If[Length[bracketStart] > 0, bracketStart[[1, 1]], Infinity];
    
    (* [ \:304c { \:3088\:308a\:65e9\:304f\:51fa\:308b \:2192 \:914d\:5217\:3068\:3057\:3066\:62bd\:51fa *)
    If[sPos < bPos && Length[bracketStart] > 0,
      bracketEnd = StringPosition[response, "]"];
      If[Length[bracketEnd] > 0,
        Return[StringTake[response,
          {sPos, bracketEnd[[-1, 2]]}]]]];
    
    (* { \:304c\:5148 \:2192 \:30aa\:30d6\:30b8\:30a7\:30af\:30c8\:3068\:3057\:3066\:62bd\:51fa *)
    If[bPos < Infinity,
      braceEnd = StringPosition[response, "}"];
      If[Length[braceEnd] > 0,
        Return[StringTake[response,
          {bPos, braceEnd[[-1, 2]]}]]]];
    
    (* [ \:306e\:307f\:3042\:308b\:5834\:5408 *)
    If[sPos < Infinity,
      bracketEnd = StringPosition[response, "]"];
      If[Length[bracketEnd] > 0,
        Return[StringTake[response,
          {sPos, bracketEnd[[-1, 2]]}]]]];
    
    (* fallback *)
    response
  ];

(* JSON \:6587\:5b57\:5217 \:2192 Association\:3002
   T25: Developer`ReadRawJSONString \:3092\:512a\:5148\:3057\:3001 ImportString \:3092 fallback \:306b\:3059\:308b\:3002
   \:3055\:3089\:306b JSON \:62bd\:51fa\:3092\:8907\:6570\:56de\:8a66\:3057\:3066 parseable \:306a\:3082\:306e\:3092\:63a1\:7528\:3002 *)
iParseJSON[jsonStr_String] :=
  Module[{trimmed, result},
    trimmed = StringTrim[jsonStr];
    If[StringLength[trimmed] === 0, Return[$Failed, Module]];
    (* \:7b2c 1 \:6ed1: Developer`ReadRawJSONString (\:65e5\:672c\:8a9e\:542b\:3080 JSON \:306b\:5f37\:3044) *)
    result = Quiet @ Check[
      Developer`ReadRawJSONString[trimmed], $Failed];
    If[result =!= $Failed &&
       (AssociationQ[result] || ListQ[result]),
      Return[result, Module]];
    (* \:7b2c 2 \:6ed1: ImportString "RawJSON" *)
    result = Quiet @ Check[
      ImportString[trimmed, "RawJSON"], $Failed];
    If[result =!= $Failed &&
       (AssociationQ[result] || ListQ[result]),
      Return[result, Module]];
    $Failed
  ];

iParseJSON[_] := $Failed;

(* ── Planner プロンプト ── *)

$iPlannerSystemPrompt =
"You are a task planner for a Mathematica/Wolfram Language orchestration system.
Given a user's request, decompose it into a set of independent or dependent tasks.

RULES:
1. Each task MUST have these exact keys:
   TaskId, Role, Goal, Inputs, Outputs, Capabilities, DependsOn,
   ExpectedArtifactType, OutputSchema
2. Valid Roles: Explore, Plan, Draft, Verify, Reduce
   (Commit is reserved for the system)
3. DependsOn lists TaskIds that must complete before this task runs
4. OutputSchema maps key names to type strings:
   \"String\", \"Integer\", \"Real\", \"List\", \"List[String]\",
   \"List[Association]\", \"Association\"
5. Keep the number of tasks minimal (prefer 2-5)
6. Tasks should be parallelizable where possible

Respond with ONLY a JSON object in this exact format:
```json
{
  \"Tasks\": [
    {
      \"TaskId\": \"t1\",
      \"Role\": \"Explore\",
      \"Goal\": \"description of what to do\",
      \"Inputs\": [],
      \"Outputs\": [\"outputName\"],
      \"Capabilities\": [\"ReadArtifacts\", \"StructuredOutput\"],
      \"DependsOn\": [],
      \"ExpectedArtifactType\": \"Summary\",
      \"OutputSchema\": {\"Summary\": \"String\", \"KeyPoints\": \"List[String]\"}
    }
  ]
}
```

Do NOT include any text outside the JSON block.";

(* Stage 3.5c: \:65e5\:672c\:8a9e\:6700\:9069\:5316\:30d7\:30ed\:30f3\:30d7\:30c8\:3002
   $Language === "Japanese" \:6642\:306b iPlannerBuildPrompt \:304c\:9078\:629e\:3059\:308b\:3002
   \:91cd\:8981: Goal \:30d5\:30a3\:30fc\:30eb\:30c9\:306f\:65e5\:672c\:8a9e\:3067\:8a18\:8ff0\:3055\:305b\:3001 worker \:306b
         \:65e5\:672c\:8a9e\:5165\:529b\:3092\:81ea\:7136\:306b\:6e21\:305b\:308b\:3088\:3046\:306b\:3059\:308b\:3002 *)
$iPlannerSystemPromptJa =
"\:3042\:306a\:305f\:306f Mathematica / Wolfram Language \:306e\:30aa\:30fc\:30b1\:30b9\:30c8\:30ec\:30fc\:30b7\:30e7\:30f3\:7cfb\:5411\:3051\:306e
\:30bf\:30b9\:30af\:30d7\:30e9\:30f3\:30ca\:30fc\:3067\:3059\:3002 \:30e6\:30fc\:30b6\:306e\:8981\:6c42\:3092\:3001 \:72ec\:7acb\:307e\:305f\:306f\:4f9d\:5b58\:95a2\:4fc2\:3092\:6301\:3064
\:8907\:6570\:306e\:30bf\:30b9\:30af\:306b\:5206\:89e3\:3057\:3066\:304f\:3060\:3055\:3044\:3002

\:30eb\:30fc\:30eb:
1. \:5404\:30bf\:30b9\:30af\:306b\:306f\:5fc5\:305a\:6b21\:306e\:30ad\:30fc\:3092\:5168\:3066\:542b\:3081\:308b\:3053\:3068:
   TaskId, Role, Goal, Inputs, Outputs, Capabilities, DependsOn,
   ExpectedArtifactType, OutputSchema
2. \:6709\:52b9\:306a Role: Explore (\:8abf\:67fb), Plan (\:8a08\:753b), Draft (\:8349\:7a3f),
   Verify (\:691c\:8a3c), Reduce (\:7d71\:5408)
   (Commit \:306f\:30b7\:30b9\:30c6\:30e0\:5c02\:7528)
3. DependsOn \:306f\:5148\:884c\:5b8c\:4e86\:3055\:305b\:308b\:3079\:304d TaskId \:306e\:914d\:5217
4. Goal \:30d5\:30a3\:30fc\:30eb\:30c9\:306f\:30e6\:30fc\:30b6\:306e\:8a00\:8a9e (\:65e5\:672c\:8a9e\:5fdc\:7b54\:53ef) \:3067\:8a18\:8ff0\:3057\:3001
   \:30bf\:30b9\:30af\:5185\:5bb9\:3092\:5177\:4f53\:7684\:306b\:7d50\:679c\:3092\:60f3\:50cf\:3067\:304d\:308b\:5f62\:3067\:8a18\:3059
5. OutputSchema \:306f\:30ad\:30fc\:540d \:2192 \:578b\:6587\:5b57\:5217\:306e\:30de\:30c3\:30d7:
   \"String\", \"Integer\", \"Real\", \"List\", \"List[String]\",
   \"List[Association]\", \"Association\"
6. \:30bf\:30b9\:30af\:6570\:306f\:6700\:5c0f\:5c0f\:9650 (\:63a8\:5968 2-5 \:500b)
7. \:53ef\:80fd\:306a\:9650\:308a\:3001 \:30bf\:30b9\:30af\:306f\:4e26\:5217\:5b9f\:884c\:53ef\:80fd\:306b\:69cb\:6210\:3059\:308b
8. \:30bf\:30b9\:30af\:306f notebook \:3092\:76f4\:63a5\:64cd\:4f5c\:3057\:306a\:3044 (\:6700\:7d42\:7684\:306a notebook \:53cd\:6620\:306f
   \:30b7\:30b9\:30c6\:30e0\:5074 committer \:304c\:884c\:3046)\:3002 \:5404 worker \:306f artifact \:3092\:8fd4\:3059\:3060\:3051\:3002

\:5fdc\:7b54\:5f62\:5f0f: \:6b21\:306e JSON \:30aa\:30d6\:30b8\:30a7\:30af\:30c8 \:306e\:307f \:3092 ```json ... ``` \:3067\:56f2\:3093\:3067\:8fd4\:3059\:3002
JSON \:30d6\:30ed\:30c3\:30af\:306e\:5916\:5074\:306b\:8aac\:660e\:6587\:7b49\:3092\:7f6e\:304b\:306a\:3044\:3053\:3068\:3002
```json
{
  \"Tasks\": [
    {
      \"TaskId\": \"t1\",
      \"Role\": \"Explore\",
      \"Goal\": \"\:8abf\:67fb\:5185\:5bb9\:306e\:5177\:4f53\:7684\:306a\:8a18\:8ff0\",
      \"Inputs\": [],
      \"Outputs\": [\"output\:540d\"],
      \"Capabilities\": [\"ReadArtifacts\", \"StructuredOutput\"],
      \"DependsOn\": [],
      \"ExpectedArtifactType\": \"Summary\",
      \"OutputSchema\": {\"Summary\": \"String\", \"KeyPoints\": \"List[String]\"}
    }
  ]
}
```

\:5177\:4f53\:4f8b: \"\:91cf\:5b50\:30b3\:30f3\:30d4\:30e5\:30fc\:30bf\:306e\:73fe\:72b6\:3092\:8abf\:3079\:3001 \:8981\:7d04\:3057\:3001 3 \:884c\:30b9\:30e9\:30a4\:30c9\:6848\:3092\:4f5c\:308b\" \:2192
  t1 (Explore: \:6700\:65b0\:52d5\:5411\:8abf\:67fb) \:2192 t2 (Reduce: 3 \:884c\:8981\:7d04) \:2192 t3 (Plan: \:30b9\:30e9\:30a4\:30c9\:69cb\:6210\:6848)";

iPlannerBuildPrompt[input_, plannerOpts_Association] :=
  Module[{maxTasks, prompt, basePrompt, isJa, intent, slideHint},
    maxTasks = Lookup[plannerOpts, "MaxTasks", 10];
    isJa     = $Language === "Japanese";
    basePrompt = If[isJa,
      $iPlannerSystemPromptJa,
      $iPlannerSystemPrompt];
    
    (* T07: slide \:5fc5\:5408\:3044\:304b\:3069\:3046\:304b\:3092\:30c1\:30a7\:30c3\:30af\:3057\:3001 hint \:3092\:8ffd\:52a0 *)
    intent = iDetectSlideIntent[input];
    slideHint = "";
    If[TrueQ[intent["IsSlide"]],
      slideHint = iBuildSlidePlannerHint[intent, isJa]];
    
    prompt = basePrompt <> "\n\n" <>
      If[isJa,
        "\:30bf\:30b9\:30af\:6570\:306e\:4e0a\:9650: " <> ToString[maxTasks] <> "\n\n",
        "Maximum number of tasks: " <> ToString[maxTasks] <> "\n\n"] <>
      slideHint <>
      If[isJa,
        "\:30e6\:30fc\:30b6\:306e\:8981\:6c42:\n",
        "USER REQUEST:\n"] <>
      ToString[input];
    prompt
  ];

(* ---- iBuildSlidePlannerHint ----
   T07: slide \:5fc5\:5408\:3044\:6642\:306f planner \:306b\:5bfe\:3057\:3066\:660e\:793a\:7684\:306b:
     (a) Draft task \:3092\:5fc5\:305a\:5165\:308c\:308b (page-by-page \:4ee5\:5916\:3082\:53ef)
     (b) OutputSchema \:306b "SlideDraft" -> "List[Association]" \:3092\:8981\:6c42
     (c) \:30da\:30fc\:30b8\:6570\:306e\:76ee\:5b89\:3092\:63d0\:793a (goal / schema \:3068\:3082\:306b\:56fa\:6709)
     (d) slide-aware \:306a\:5206\:89e3\:4f8b (Outline -> Draft) \:3092\:793a\:3059
   \:3053\:308c\:306b\:3088\:308a\:3001 LLM \:304c\:300c2-5 \:30bf\:30b9\:30af\:306b\:6291\:3048\:3066\:300d\:3068\:3044\:3046\:6307\:793a\:306b\:5f15\:304d\:305a\:3089\:308c\:3066
   slide \:751f\:6210\:3092\:5358\:4e00 Explore \:306b\:4e38\:3081\:3066\:3057\:307e\:3046\:4e8b\:614b\:3092\:56de\:907f\:3059\:308b\:3002
   --------------------------------------------------------------------- *)

iBuildSlidePlannerHint[intent_Association, isJa_] :=
  Module[{pageN, pagePart},
    pageN = Lookup[intent, "PageCount", None];
    pagePart = If[IntegerQ[pageN] && pageN > 0,
      If[isJa,
        "\:30e6\:30fc\:30b6\:306f " <> ToString[pageN] <>
          " \:30da\:30fc\:30b8\:76f8\:5f53\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:660e\:793a\:7684\:306b\:8981\:6c42\:3057\:3066\:3044\:307e\:3059\:3002",
        "The user explicitly requested approximately " <>
          ToString[pageN] <> " pages/slides."],
      If[isJa,
        "\:30da\:30fc\:30b8\:6570\:306f\:660e\:793a\:3055\:308c\:3066\:3044\:307e\:305b\:3093\:304c\:3001 \:5341\:5206\:306a\:7dcf\:91cf\:3092\:78ba\:4fdd\:3057\:3066\:4e0b\:3055\:3044\:3002",
        "No explicit page count; ensure sufficient total coverage."]];
    
    If[isJa,
      "\:3010\:91cd\:8981: \:30b9\:30e9\:30a4\:30c9/\:30d7\:30ec\:30bc\:30f3\:30c6\:30fc\:30b7\:30e7\:30f3\:751f\:6210\:30bf\:30b9\:30af\:306e\:5834\:5408\:306e\:8ffd\:52a0\:898f\:5247\:3011\n" <>
      pagePart <> "\n" <>
      "\:3053\:306e\:7a2e\:985e\:306e\:30bf\:30b9\:30af\:306f\:300c\:6700\:5c0f\:9650 2-5 \:30bf\:30b9\:30af\:300d\:306e\:901a\:5e38\:898f\:5247\:3088\:308a\:3082\:7dcf\:91cf\:3092\:512a\:5148\:3057\:307e\:3059\:3002\n" <>
      "\:63a8\:5968\:3059\:308b\:5206\:89e3:\n" <>
      "  t1: Explore (Role=Explore) \:2014 \:9858\:66f8\:306e\:8981\:6c42\:30fb\:53c2\:8003\:8cc7\:6599\:306e\:6574\:7406\n" <>
      "  t2: Outline (Role=Plan)    \:2014 \:5168\:30b9\:30e9\:30a4\:30c9\:306e\:30a2\:30a6\:30c8\:30e9\:30a4\:30f3(Title/Subtitle/BodyOutline)\n" <>
      "  t3: Draft   (Role=Draft)   \:2014 \:5168 " <>
        If[IntegerQ[pageN], ToString[pageN], "N"] <>
        " \:30da\:30fc\:30b8\:306e\:8a73\:7d30 SlideDraft \:3092\:751f\:6210\n" <>
      "  t4: Verify  (Role=Verify)  \:2014 \:30da\:30fc\:30b8\:6570\:30fb\:6f0f\:308c\:306a\:3069\:306e\:691c\:8a3c (\:4efb\:610f)\n\n" <>
      "Draft \:30bf\:30b9\:30af\:306e OutputSchema \:306b\:306f\:5fc5\:305a\:6b21\:3092\:542b\:3081\:3066\:4e0b\:3055\:3044:\n" <>
      "  \"SlideDraft\": \"List[Association]\"\n" <>
      "\:305d\:3057\:3066 Goal \:3067 LLM \:306b\:300c\:5404\:8981\:7d20\:306f\n" <>
      "  <|\"Page\"->N, \"SlideKind\"->\"Cover-Section\"|\"Content\"|\"Summary\"|...,\n" <>
      "    \"Cells\"->{<|\"Style\"->\"Section\"|\"Subsection\"|\"Text\"|\"ItemParagraph\"|\n" <>
      "                         \"ItemNumbered\"|\"Subtitle\"|\"SubsubsectionInPresentation\",\n" <>
      "                \"Content\"->...|>, ...}|>\n" <>
      "\:306e\:5f62\:5f0f\:3067\" \:3068\:660e\:793a\:3059\:308b\:3053\:3068\:3002 Style \:306f Mathematica \:6709\:52b9\:540d\:79f0\:306e\:307f\n" <>
      "\:4f7f\:3046 (\:62ec\:5f27\:3084\:65e5\:672c\:8a9e\:3092\:6dfb\:3048\:306a\:3044)\:3002\n\n",
      
      "[IMPORTANT: Additional rules for slide/presentation tasks]\n" <>
      pagePart <> "\n" <>
      "For slide tasks, prefer total coverage over the usual 'keep it to 2-5 tasks' rule.\n" <>
      "Recommended decomposition:\n" <>
      "  t1: Explore (Role=Explore) \:2014 organize requirements & reference material\n" <>
      "  t2: Outline (Role=Plan)    \:2014 full slide outline (Title/Subtitle/BodyOutline)\n" <>
      "  t3: Draft   (Role=Draft)   \:2014 produce full SlideDraft for ALL " <>
        If[IntegerQ[pageN], ToString[pageN], "N"] <> " pages\n" <>
      "  t4: Verify  (Role=Verify)  \:2014 check page count & omissions (optional)\n\n" <>
      "The Draft task's OutputSchema MUST include:\n" <>
      "  \"SlideDraft\": \"List[Association]\"\n" <>
      "And the Draft task's Goal MUST instruct the LLM to emit each element as:\n" <>
      "  <|\"Page\"->N, \"SlideKind\"->\"Cover-Section\"|\"Content\"|\"Summary\"|...,\n" <>
      "    \"Cells\"->{<|\"Style\"->\"Section\"|\"Subsection\"|\"Text\"|\"ItemParagraph\"|\n" <>
      "                         \"ItemNumbered\"|\"Subtitle\"|\"SubsubsectionInPresentation\",\n" <>
      "                \"Content\"->...|>, ...}|>\n" <>
      "Use ONLY valid Mathematica cell style names for Style (no parens, no prose).\n\n"]
  ];

(* LLM planner の本体。ClaudeCode`ClaudeQueryBg (同期版公開 API) を使用。 *)
iLLMPlannerFn[input_, plannerOpts_Association] :=
  Module[{prompt, queryFn, response, jsonStr, parsed, maxTasks,
          tasks, tasksList},
    queryFn  = Lookup[plannerOpts, "QueryFunction", Automatic];
    maxTasks = Lookup[plannerOpts, "MaxTasks", 10];
    
    prompt = iPlannerBuildPrompt[input, plannerOpts];
    
    (* LLM \:306b\:554f\:3044\:5408\:308f\:305b *)
    response = If[queryFn === Automatic,
      (* T27: \:516c\:958b API ClaudeQueryBg (\:540c\:671f) \:3092\:4f7f\:7528\:3002
         ClaudeQuery \:306f\:975e\:540c\:671f\:306a\:306e\:3067 Bg \:306b\:5909\:66f4\:3057\:3066 string \:3092\:78ba\:5b9f\:306b\:8fd4\:3059\:3002 *)
      Quiet @ Check[
        ClaudeCode`ClaudeQueryBg[prompt],
        $Failed],
      (* caller \:6307\:5b9a\:306e query \:95a2\:6570 *)
      Quiet @ Check[queryFn[prompt], $Failed]];
    
    If[!StringQ[response] || response === $Failed,
      Return[<|"Tasks" -> {},
               "Status" -> "Failed",
               "Error"  -> iL["LLM \:304b\:3089\:306e\:5fdc\:7b54\:304c\:53d6\:5f97\:3067\:304d\:306a\:304b\:3063\:305f",
                              "Failed to get response from LLM"]|>]];
    
    (* JSON \:62bd\:51fa\:30fb\:30d1\:30fc\:30b9 *)
    jsonStr = iExtractJSONFromResponse[response];
    parsed  = iParseJSON[jsonStr];
    
    If[parsed === $Failed || !AssociationQ[parsed],
      Return[<|"Tasks" -> {},
               "Status" -> "Failed",
               "Error"  -> iL["LLM \:5fdc\:7b54\:306e JSON \:30d1\:30fc\:30b9\:306b\:5931\:6557",
                              "Failed to parse JSON from LLM response"],
               "RawResponse" -> StringTake[response, UpTo[500]]|>]];
    
    (* Tasks \:30ad\:30fc\:306e\:53d6\:5f97 *)
    tasksList = Lookup[parsed, "Tasks", None];
    If[tasksList === None,
      (* \:914d\:5217\:304c\:76f4\:63a5\:8fd4\:3063\:305f\:5834\:5408 *)
      If[ListQ[parsed],
        tasksList = parsed,
        Return[<|"Tasks" -> {},
                 "Status" -> "Failed",
                 "Error"  -> iL["Tasks \:30ad\:30fc\:304c\:898b\:3064\:304b\:3089\:306a\:3044",
                                "No Tasks key found in LLM response"]|>]]];
    
    If[!ListQ[tasksList],
      Return[<|"Tasks" -> {},
               "Status" -> "Failed",
               "Error"  -> iL["Tasks \:304c\:30ea\:30b9\:30c8\:3067\:306f\:306a\:3044",
                              "Tasks is not a list"]|>]];
    
    (* MaxTasks \:5236\:9650 *)
    If[Length[tasksList] > maxTasks,
      tasksList = Take[tasksList, maxTasks]];
    
    (* \:5404\:30bf\:30b9\:30af\:3092 Association \:5316 (JSON \:304b\:3089\:306e\:30d1\:30fc\:30b9\:7d50\:679c\:304c
       Rule \:30ea\:30b9\:30c8\:306e\:5834\:5408\:304c\:3042\:308b) *)
    tasksList = Map[
      If[AssociationQ[#], #, Association[#]] &,
      tasksList];
    
    (* \:4e0d\:8db3\:30ad\:30fc\:306e\:88dc\:5b8c *)
    tasksList = Map[iNormalizeTaskSpec, tasksList];
    
    <|"Tasks" -> tasksList|>
  ];

(* TaskSpec \:306e\:4e0d\:8db3\:30ad\:30fc\:3092\:30c7\:30d5\:30a9\:30eb\:30c8\:5024\:3067\:88dc\:5b8c *)
iNormalizeTaskSpec[task_Association] :=
  Module[{t = task},
    If[!KeyExistsQ[t, "TaskId"],
      t["TaskId"] = "t" <> ToString[RandomInteger[99999]]];
    If[!KeyExistsQ[t, "Role"],     t["Role"] = "Explore"];
    If[!KeyExistsQ[t, "Goal"],     t["Goal"] = ""];
    If[!KeyExistsQ[t, "Inputs"],   t["Inputs"] = {}];
    If[!KeyExistsQ[t, "Outputs"],  t["Outputs"] = {}];
    If[!KeyExistsQ[t, "Capabilities"],
      t["Capabilities"] = Lookup[$ClaudeOrchestratorCapabilities,
        t["Role"], {}]];
    If[!KeyExistsQ[t, "DependsOn"], t["DependsOn"] = {}];
    If[!KeyExistsQ[t, "ExpectedArtifactType"],
      t["ExpectedArtifactType"] = "Generic"];
    If[!KeyExistsQ[t, "OutputSchema"],
      t["OutputSchema"] = <|"Summary" -> "String"|>];
    (* OutputSchema \:3082 Association \:5316 *)
    If[!AssociationQ[t["OutputSchema"]],
      t["OutputSchema"] = If[ListQ[t["OutputSchema"]],
        Association[t["OutputSchema"]],
        <|"Summary" -> "String"|>]];
    t
  ];

(* ════════════════════════════════════════════════════════
   4. Worker Adapter (spec §9, §10)
   
   既存の ClaudeCode`ClaudeBuildRuntimeAdapter をベースにしつつ、
   以下を上書きする:
     - ValidateProposal: $ClaudeOrchestratorDenyHeads を強制
     - ExecuteProposal: deny された head が来たら実行させない
     - BuildContext: notebook ではなく「artifact + snapshot」を渡す
   
   Stage 1 ではさらに簡易化し、既存の adapter から NotebookWrite 系を
   strip した minimal adapter を組み立てる。
   ════════════════════════════════════════════════════════ *)

(* HeldExpr に deny head が含まれるかをシンボル名文字列で検出。
   HeldExpr は HoldComplete[...] で渡されることを想定。
   
   シンボルシャドウを避けるため、Lookup/Cases で head 名を
   文字列として取り出してから比較する。 *)
iHeldExprContainsDenyHead[HoldComplete[expr_], denyList_List] :=
  Module[{syms, names},
    syms = Cases[Unevaluated[expr], s_Symbol :> s,
      {0, Infinity}, Heads -> True];
    names = Map[SymbolName, syms];
    AnyTrue[denyList, MemberQ[names, #] &]
  ];

iHeldExprContainsDenyHead[_, _] := False;

(* iValidateWorkerProposal: worker 用 proposal 検証。
   deny head を含んでいたら Deny を返す。 *)
iValidateWorkerProposal[proposal_Association, contextPacket_,
    role_String] :=
  Module[{held, denyList, hit},
    held = Lookup[proposal, "HeldExpr", None];
    If[held === None || !MatchQ[held, HoldComplete[_]],
      (* 提案がなければ何も検証しない (text-only 応答は許容) *)
      Return[<|
        "Decision"           -> "Permit",
        "ReasonClass"        -> "NoProposal",
        "VisibleExplanation" -> "",
        "SanitizedExpr"      -> None
      |>]];
    
    denyList = $ClaudeOrchestratorDenyHeads;
    (* committer だけ一部許可 *)
    If[role === "Commit",
      denyList = Complement[denyList, $iCommitterAllowedHeads]];
    
    hit = iHeldExprContainsDenyHead[held, denyList];
    If[hit,
      Return[<|
        "Decision"    -> "Deny",
        "ReasonClass" -> "ForbiddenHead",
        "VisibleExplanation" ->
          iL["worker \:306f NotebookWrite / CreateNotebook / RunProcess \:7b49\:3092\:5229\:7528\:3067\:304d\:306a\:3044\:3002artifact \:5f62\:5f0f\:3067\:5fdc\:7b54\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
             "Worker cannot use NotebookWrite / CreateNotebook / RunProcess etc. Respond with an artifact instead."],
        "SanitizedExpr" -> None
      |>]];
    
    <|
      "Decision"           -> "Permit",
      "ReasonClass"        -> "OK",
      "VisibleExplanation" -> "",
      "SanitizedExpr"      -> held
    |>
  ];

(* iExtractArtifactFromTurn: runtime の最終ターンから artifact 構造を
   取り出す。 LastExecutionResult に RawResult として Association が
   残っていればそれを採用。文字列の場合は Summary フィールドに格納。 *)
iExtractArtifactFromTurn[runtimeId_String, task_Association] :=
  Module[{st, msgs, last, raw, text, artifactType, proposalPayload,
          lastExecResult, redactedResult,
          convState, lastExecRes, lastProposal},
    st = ClaudeRuntime`ClaudeRuntimeStateFull[runtimeId];
    If[!AssociationQ[st],
      Return[<|"TaskId"      -> Lookup[task, "TaskId", "?"],
               "Status"      -> "Failed",
               "ArtifactType" -> "Error",
               "Payload"     -> <||>,
               "Diagnostics" -> <|"Error" -> "RuntimeNotFound"|>|>]];
    
    (* v2026-04-20 T04: \:4e8c\:91cd Lookup \:3092 Association \:30ac\:30fc\:30c9\:4ed8\:304d\:306b\:5206\:89e3\:3002
       st \:306e\:30ad\:30fc\:304c\:5b58\:5728\:3057\:3066\:5024\:304c None \:306e\:5834\:5408\:3001
       \:5916\:5074 Lookup \:306f default \:3067\:306f\:306a\:304f None \:3092\:8fd4\:3059\:306e\:3067\:3001
       \:5185\:5074\:304c Lookup[None, ...] \:306b\:306a\:308a Lookup::invrl \:304c\:767a\:751f\:3057\:3066\:3044\:305f\:3002
       AssociationQ \:30c1\:30a7\:30c3\:30af\:3067\:5b89\:5168\:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3059\:308b\:3002 *)
    convState = Lookup[st, "ConversationState", <||>];
    If[!AssociationQ[convState], convState = <||>];
    msgs = Lookup[convState, "Messages", {}];
    If[!ListQ[msgs], msgs = {}];
    last = If[Length[msgs] > 0, Last[msgs], <||>];
    If[!AssociationQ[last], last = <||>];
    
    lastExecRes = Lookup[st, "LastExecutionResult", <||>];
    If[!AssociationQ[lastExecRes], lastExecRes = <||>];
    raw = Lookup[lastExecRes, "RawResult", None];
    
    text = Lookup[last, "TextResponse", ""];
    artifactType = Lookup[task, "ExpectedArtifactType", "Generic"];
    
    (* Fallback 1: \:6700\:7d42\:30e1\:30c3\:30bb\:30fc\:30b8\:306e ExecutionResult.RedactedResult \:304b\:3089 *)
    lastExecResult = Lookup[last, "ExecutionResult", None];
    redactedResult = If[AssociationQ[lastExecResult],
      Lookup[lastExecResult, "RedactedResult", None],
      None];
    
    (* Fallback 2: LastProposal \:306e ArtifactPayload \:304b\:3089
       (LLM worker adapter / mock worker \:306e ParseProposal \:304c\:8a2d\:5b9a) *)
    lastProposal = Lookup[st, "LastProposal", <||>];
    If[!AssociationQ[lastProposal], lastProposal = <||>];
    proposalPayload = Lookup[lastProposal, "ArtifactPayload", None];
    
    (* Association \:306a\:3089\:305d\:306e\:307e\:307e payload *)
    Which[
      AssociationQ[raw],
        <|"TaskId"      -> Lookup[task, "TaskId", "?"],
          "Status"      -> "Success",
          "ArtifactType" -> artifactType,
          "Payload"     -> raw,
          "Diagnostics" -> <|"Source" -> "ExecutionResult"|>|>,
      StringQ[raw] && raw =!= "",
        <|"TaskId"      -> Lookup[task, "TaskId", "?"],
          "Status"      -> "Success",
          "ArtifactType" -> artifactType,
          "Payload"     -> <|"Summary" -> raw|>,
          "Diagnostics" -> <|"Source" -> "StringResult"|>|>,
      AssociationQ[redactedResult],
        (* Fallback 1: \:6700\:7d42\:30e1\:30c3\:30bb\:30fc\:30b8\:304b\:3089 *)
        <|"TaskId"      -> Lookup[task, "TaskId", "?"],
          "Status"      -> "Success",
          "ArtifactType" -> artifactType,
          "Payload"     -> redactedResult,
          "Diagnostics" -> <|"Source" -> "MessageRedacted"|>|>,
      AssociationQ[proposalPayload],
        (* Fallback 2: ParseProposal \:304b\:3089\:306e ArtifactPayload *)
        <|"TaskId"      -> Lookup[task, "TaskId", "?"],
          "Status"      -> "Success",
          "ArtifactType" -> artifactType,
          "Payload"     -> proposalPayload,
          "Diagnostics" -> <|"Source" -> "ProposalFallback"|>|>,
      StringQ[text] && text =!= "",
        <|"TaskId"      -> Lookup[task, "TaskId", "?"],
          "Status"      -> "Success",
          "ArtifactType" -> artifactType,
          "Payload"     -> <|"Summary" -> text|>,
          "Diagnostics" -> <|"Source" -> "TextResponse"|>|>,
      True,
        <|"TaskId"      -> Lookup[task, "TaskId", "?"],
          "Status"      -> "Failed",
          "ArtifactType" -> artifactType,
          "Payload"     -> <||>,
          "Diagnostics" -> <|"Error" -> "NoOutput"|>|>
    ]
  ];

(* iMakeMinimalAdapter: adapter を mock / test 向けに構築する。
   ClaudeBuildRuntimeAdapter が使えない環境 (テスト等) でも動く
   最小限の adapter。本番では caller が ClaudeBuildRuntimeAdapter を
   ラップして渡す想定。 *)
iMakeMinimalAdapter[role_String, queryFn_, task_Association] := <|
  "SyncProvider" -> True,
  
  "BuildContext" -> Function[{input, convState},
    <|
      "Input"        -> input,
      "Role"         -> role,
      "Task"         -> task,
      "Capabilities" -> Lookup[$ClaudeOrchestratorCapabilities, role, {}]
    |>],
  
  "QueryProvider" -> Function[{ctx, convState},
    Module[{response},
      response = queryFn[ctx];
      <|"response" -> response|>]],
  
  "ParseProposal" -> Function[{raw},
    (* \:65e2\:5b9a: harmless \:306a HeldExpr \:3092\:8fd4\:3057 TextOnly repair loop \:3092\:56de\:907f\:3002
       v2026-04-18T01 fix: ArtifactPayload \:3082\:5fc5\:305a\:542b\:3081\:308b\:3053\:3068 \:2014
       \:3053\:308c\:304c\:306a\:3044\:3068 ClaudeSpawnWorkers \:306e runtime-\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:7d4c\:8def\:304c
       Lookup[parsed, "ArtifactPayload", None] \:3067 None \:3092\:5f97\:3066 \:3059\:3079\:3066\:306e worker \:304c
       "Failed" \:306b\:306a\:308b\:3002 *)
    Module[{text},
      text = If[StringQ[raw], raw,
                If[AssociationQ[raw], Lookup[raw, "response", ""], ""]];
      <|"HeldExpr"        -> HoldComplete[True],
        "TextResponse"    -> text,
        "HasProposal"     -> True,
        "ArtifactPayload" -> <|"Summary" -> text|>|>]],
  
  "ValidateProposal" -> Function[{prop, ctx},
    iValidateWorkerProposal[prop, ctx, role]],
  
  "ExecuteProposal" -> Function[{prop, val},
    <|"Success"   -> True,
      "RawResult" -> None,
      "Error"     -> None|>],
  
  "RedactResult" -> Function[{res, ctx},
    <|"RedactedResult" -> Lookup[res, "RawResult", None],
      "Summary"        -> ""|>],
  
  "ShouldContinue" -> Function[{red, convState, turnCount}, False]
|>;

(* ════════════════════════════════════════════════════════
   4b. LLM-backed Worker Adapter Builder (Stage 2)
   
   ClaudeCode`ClaudeQueryBg (同期版公開 API) を使って各 worker の LLM 呼び出しを
   行う adapter を構築する。ValidateProposal は orchestrator の
   iValidateWorkerProposal に委譲し、NotebookWrite 系 deny を強制する。
   
   worker は notebook を直接触らず、artifact (Association) を
   structured output として返す。LLM 応答から JSON を抽出して
   artifact payload にする。
   
   使い方:
     ClaudeSpawnWorkers[tasksSpec,
       "WorkerAdapterBuilder" -> "LLM",
       "QueryFunction" -> myQueryFn]
   ════════════════════════════════════════════════════════ *)

$iWorkerSystemPromptTemplate =
"You are a worker agent with role: {{ROLE}}.

YOUR TASK:
{{GOAL}}

OUTPUT REQUIREMENTS:
You must respond with a JSON object matching this schema:
{{OUTPUT_SCHEMA}}

{{DEPENDENCY_SECTION}}

RULES:
1. Respond ONLY with a JSON object (inside ```json ... ``` fences).
2. You MUST NOT use NotebookWrite, CreateNotebook, RunProcess,
   ExternalEvaluate, SystemCredential, or any file I/O operations.
3. Your output is an artifact that will be passed to downstream tasks.
4. Be concise and precise. Focus only on your assigned task.
5. All keys from the OutputSchema must be present in your response.";

iWorkerBuildSystemPrompt[role_String, task_Association,
    depArtifacts_Association, referenceText_:None] :=
  Module[{prompt, goalStr, schemaStr, depSection, schema, intent,
          slideHint, isJa},
    isJa      = $Language === "Japanese";
    goalStr   = ToString[Lookup[task, "Goal", ""]];
    schema    = Lookup[task, "OutputSchema", <||>];
    schemaStr = ToString[schema, InputForm];
    
    depSection = If[Length[depArtifacts] > 0,
      "DEPENDENCY ARTIFACTS (outputs from previous tasks):\n" <>
        StringJoin[
          KeyValueMap[
            Function[{tid, art},
              "- TaskId " <> tid <> ": " <>
              ToString[Lookup[art, "Payload", <||>], InputForm] <> "\n"],
            depArtifacts]],
      "No dependency artifacts."];
    
    (* T07: slide \:5fc5\:5408\:3044\:306e worker \:306b\:306f slide-aware hint \:3092\:6ce8\:5165\:3002 *)
    intent    = iDetectWorkerSlideIntent[task, depArtifacts];
    slideHint = If[TrueQ[intent["IsSlide"]],
      (* T08: referenceText \:3082 worker hint \:306b\:6e21\:3059 (voice \:4fdd\:6301) *)
      iBuildSlideWorkerHint[intent, schema, isJa, referenceText],
      ""];
    
    prompt = StringReplace[$iWorkerSystemPromptTemplate, {
      "{{ROLE}}"           -> role,
      "{{GOAL}}"           -> goalStr,
      "{{OUTPUT_SCHEMA}}"  -> schemaStr,
      "{{DEPENDENCY_SECTION}}" -> depSection
    }];
    
    If[slideHint =!= "",
      prompt = prompt <> "\n\n" <> slideHint];
    
    prompt
  ];

(* ---- iDetectWorkerSlideIntent ----
   T07: worker \:30ec\:30d9\:30eb\:306e slide \:5fc5\:5408\:3044\:691c\:51fa\:3002 Goal / OutputSchema /
   DepArtifacts \:3092\:8907\:5408\:7684\:306b\:898b\:308b\:3002
   
   Slide-trigger:
     (a) Goal \:6587\:5b57\:5217\:3067 iDetectSlideIntent[Goal] \:304c IsSlide
     (b) OutputSchema \:306e\:30ad\:30fc\:306b (Slide|Outline|Draft|Pages?|Sections?)
         \:304c\:542b\:307e\:308c\:3066\:3044\:308b\:304b\:3001 value \:304c "List[Association]"
     (c) \:4f9d\:5b58 artifact \:306e payload \:306b Page \:30ad\:30fc\:3092\:6301\:3064 List[Assoc] \:304c\:3042\:308b
   --------------------------------------------------------------------- *)

ClearAll[iDetectWorkerSlideIntent];

iDetectWorkerSlideIntent[task_Association,
    depArtifacts_Association] :=
  Module[{goal, fromGoal, schema, schemaTriggers, depTriggers,
          combinedPageN = None, isSlide = False, kws = {}},
    goal     = ToString[Lookup[task, "Goal", ""]];
    schema   = Lookup[task, "OutputSchema", <||>];
    fromGoal = iDetectSlideIntent[goal];
    If[TrueQ[fromGoal["IsSlide"]],
      isSlide = True;
      If[IntegerQ[fromGoal["PageCount"]],
        combinedPageN = fromGoal["PageCount"]];
      kws = Join[kws, Lookup[fromGoal, "Keywords", {}]]];
    
    (* Schema \:30ad\:30fc\:540d\:306b slide-like \:306a\:540d\:524d\:304c\:3042\:308b\:304b *)
    schemaTriggers = If[AssociationQ[schema],
      Select[Keys[schema],
        StringQ[#] &&
          StringMatchQ[#,
            RegularExpression[
              "(?i).*(slide|outline|draft|pages?|sections?).*"]] &],
      {}];
    If[Length[schemaTriggers] > 0,
      isSlide = True;
      AppendTo[kws, "schema-key:" <>
        StringRiffle[schemaTriggers, ","]]];
    
    (* DepArtifacts \:5185\:3067 SlideDraft / SlideOutline \:306e payload \:304c\:3042\:308b\:304b *)
    depTriggers = Flatten[KeyValueMap[
      Function[{tid, art},
        Module[{p = If[AssociationQ[art],
          Lookup[art, "Payload", <||>], <||>]},
          If[!AssociationQ[p], p = <||>];
          Select[Keys[p],
            StringQ[#] &&
              StringMatchQ[#,
                RegularExpression[
                  "(?i).*(slide|outline|draft).*"]] &]]],
      depArtifacts]];
    If[Length[depTriggers] > 0,
      isSlide = True;
      AppendTo[kws, "dep-artifact:" <>
        StringRiffle[DeleteDuplicates @ depTriggers, ","]]];
    
    <|"IsSlide"   -> isSlide,
      "PageCount" -> combinedPageN,
      "Keywords"  -> kws|>
  ];

(* ---- iBuildSlideWorkerHint ----
   T07: worker \:304c slide \:5fc5\:5408\:3044\:306e\:3068\:304d\:3001 \:5177\:4f53\:7684\:306a SlideDraft
   \:5f62\:5f0f\:3068\:6709\:52b9 Style \:306e\:5236\:7d04\:3092\:6307\:793a\:3059\:308b\:3002 \:3053\:308c\:306b\:3088\:308a
   LLM \:304c Summary \:3067\:306f\:306a\:304f \:30da\:30fc\:30b8\:6bce\:306e\:69cb\:9020\:5316 SlideDraft \:3092\:8fd4\:3057\:3001
   \:304b\:3064 Style \:304c "Subsection (title slide)" \:306e\:3088\:3046\:306a\:30d7\:30ed\:30fc\:30ba\:306b\:306a\:3089\:306a\:3044\:3002 *)

iBuildSlideWorkerHint[intent_Association, schema_, isJa_,
    referenceText_:None] :=
  Module[{pageN, pagePart, validStylesList, schemaHint, t08Hint,
          refHint, baseHint},
    pageN = Lookup[intent, "PageCount", None];
    pagePart = If[IntegerQ[pageN] && pageN > 0,
      If[isJa,
        "\:5b8c\:6210\:30b9\:30e9\:30a4\:30c9\:6570: \:5c11\:306a\:304f\:3068\:3082 " <> ToString[pageN] <>
          " \:30da\:30fc\:30b8\:3002 SlideDraft \:306e\:9577\:3055\:3092\:3053\:308c\:672a\:6e80\:306b\:3057\:306a\:3044\:3053\:3068\:3002",
        "Target page count: at least " <> ToString[pageN] <>
          " pages. Do NOT return a SlideDraft shorter than this."],
      If[isJa,
        "\:30da\:30fc\:30b8\:6570\:306f\:5341\:5206\:78ba\:4fdd\:3059\:308b\:3053\:3068 (\:6700\:4f4e 10 \:30da\:30fc\:30b8\:76ee\:5b89)\:3002",
        "Ensure sufficient page count (at least 10 as a rule of thumb)."]];
    
    validStylesList = StringRiffle[
      Take[$iValidCellStyles, Min[Length[$iValidCellStyles], 28]],
      ", "];
    
    schemaHint = If[AssociationQ[schema] && Length[schema] > 0,
      If[isJa,
        "\:6307\:5b9a\:3055\:308c\:305f OutputSchema: " <>
          ToString[schema, InputForm] <> "\n" <>
        "\:3053\:306e schema \:306e\:5168\:30ad\:30fc\:3092\:542b\:3080 JSON \:3092\:8fd4\:3059\:3053\:3068\:3002",
        "Required OutputSchema: " <> ToString[schema, InputForm] <> "\n" <>
        "Return JSON containing ALL keys from this schema."],
      ""];
    
    baseHint = If[isJa,
      "[T07 SLIDE-MODE \:6ce8\:5165]\n" <>
      "\:3053\:306e\:30bf\:30b9\:30af\:306f\:30b9\:30e9\:30a4\:30c9\:751f\:6210\:3067\:3042\:308b\:3068\:5224\:5b9a\:3055\:308c\:307e\:3057\:305f\:3002\n" <>
      pagePart <> "\n\n" <>
      schemaHint <> "\n\n" <>
      "\:3010SlideDraft / Slides \:306a\:3069\:306e\:30b9\:30e9\:30a4\:30c9 list \:3092\:8fd4\:3059\:5834\:5408\:306e\:5f62\:5f0f\:3011\n" <>
      "\:5404\:8981\:7d20\:306f\:6b21\:306e Association \:3068\:3059\:308b:\n" <>
      "  {\n" <>
      "    \"Page\": <integer>,\n" <>
      "    \"SlideKind\": \"Cover\" | \"Section\" | \"Content\" | \"Summary\" | ...,\n" <>
      "    \"Cells\": [\n" <>
      "      { \"Style\": \"<valid-style>\", \"Content\": \"<text>\" },\n" <>
      "      ... (\:4e00\:30da\:30fc\:30b8\:3042\:305f\:308a 3-10 cells \:7a0b\:5ea6)\n" <>
      "    ]\n" <>
      "  }\n\n" <>
      "\:3010Style \:306b\:4f7f\:3048\:308b\:306e\:306f\:4ee5\:4e0b\:306e Mathematica \:6709\:52b9\:540d\:79f0\:306e\:307f\:3011\n" <>
      "  " <> validStylesList <> ", ...\n" <>
      "\:793a\:7d22\:7684\:306b\:8a71\:30b9\:30c8\:3046\:3068: \"Title\", \"Section\", \"Subsection\", \"Text\",\n" <>
      "\"ItemParagraph\", \"ItemNumbered\", \"Subtitle\", \"Subsubsection\",\n" <>
      "\"SubsubsectionInPresentation\", \"Code\", \"Input\"\n\n" <>
      "\:3010\:7981\:6b62\:3011\n" <>
      "- Style \:306b\:62ec\:5f27\:3084\:65e5\:672c\:8a9e\:3092\:6dfb\:3048\:306a\:3044 (\:4f8b: \"Subsection (title slide)\",\n" <>
      "  \"Subsection + Item/Subitem \:7fa4\" \:306f\:7121\:52b9)\n" <>
      "- Style \:306f\:5358\:4e00\:306e\:6709\:52b9\:540d\:79f0\:6587\:5b57\:5217\:306e\:307f\n" <>
      "- Summary / KeyPoints \:3060\:3051\:3092\:8fd4\:3055\:306a\:3044 (\:5168\:30da\:30fc\:30b8\:306e\:5c55\:958b\:304c\:5fc5\:9808)\n" <>
      "- \:5404 Cells \:5185\:8981\:7d20\:306b\:306f\:5fc5\:305a \"Style\" \:3068 \"Content\" \:306e\:4e21\:65b9\:3092\:542b\:3081\:308b\n",
      
      "[T07 SLIDE-MODE INJECTION]\n" <>
      "This task has been detected as a slide/presentation generation task.\n" <>
      pagePart <> "\n\n" <>
      schemaHint <> "\n\n" <>
      "[Format for returning a SlideDraft / Slides list]\n" <>
      "Each element must be an Association shaped like:\n" <>
      "  {\n" <>
      "    \"Page\": <integer>,\n" <>
      "    \"SlideKind\": \"Cover\" | \"Section\" | \"Content\" | \"Summary\" | ...,\n" <>
      "    \"Cells\": [\n" <>
      "      { \"Style\": \"<valid-style>\", \"Content\": \"<text>\" },\n" <>
      "      ... (3-10 cells per page)\n" <>
      "    ]\n" <>
      "  }\n\n" <>
      "[Style values MUST be one of these valid Mathematica cell styles]\n" <>
      "  " <> validStylesList <> ", ...\n" <>
      "Common picks: \"Title\", \"Section\", \"Subsection\", \"Text\",\n" <>
      "\"ItemParagraph\", \"ItemNumbered\", \"Subtitle\", \"Subsubsection\",\n" <>
      "\"SubsubsectionInPresentation\", \"Code\", \"Input\"\n\n" <>
      "[Prohibited]\n" <>
      "- Do NOT add parentheses or prose to Style (e.g., \"Subsection (title slide)\",\n" <>
      "  \"Subsection + Item/Subitem group\" are INVALID)\n" <>
      "- Style must be a single valid style-name string\n" <>
      "- Do NOT return only Summary / KeyPoints (full page expansion is required)\n" <>
      "- Each Cells inner element MUST include BOTH \"Style\" and \"Content\"\n"];
    
    (* T08: \:56f3/\:753b\:50cf/\:30b0\:30ea\:30c3\:30c9\:306e\:6c42\:5fc3\:2014\"Kind\"\:30d5\:30a3\:30fc\:30eb\:30c9\:3067\:62e1\:5f35\:3002
       \:7b87\:6761\:66f8\:304d\:30c6\:30ad\:30b9\:30c8\:3060\:3051\:3067\:306f\:898b\:65bc\:308a\:304c\:60aa\:3044\:306e\:3067\:3001
       \:9069\:5207\:306a\:7b87\:6240\:3067 figure \:3092\:633f\:5165\:3059\:308b\:3088\:3046 LLM \:306b\:793a\:3059\:3002 *)
    t08Hint = If[isJa,
      "\n\:3010T08 Kind \:62e1\:5f35: \:56f3\:3084\:56f3\:8868\:306e\:633f\:5165\:3011\n" <>
      "Cells \:306e\:5185\:90e8\:8981\:7d20\:306f\:3001\:30c6\:30ad\:30b9\:30c8\:30bb\:30eb\:306e\:307f\:306a\:3089\:305a {\"Kind\": ...} \:3067\n" <>
      "\:56f3\:30fb\:753b\:50cf\:30fb\:30b3\:30fc\:30c9\:3092\:5165\:308c\:3089\:308c\:307e\:3059\:3002\:8aac\:660e\:304c\:56f3\:306e\:307b\:3046\:304c\:308f\:304b\:308a\:3084\:3059\:3044\n" <>
      "\:30da\:30fc\:30b8\:3067\:306f\:7a4d\:6975\:7684\:306b\:4f7f\:3063\:3066\:304f\:3060\:3055\:3044:\n\n" <>
      "  (a) Mathematica \:30b3\:30fc\:30c9\:30bb\:30eb (\:30e6\:30fc\:30b6\:304c\:8a55\:4fa1\:3057\:3066\:56f3\:3092\:51fa\:3059):\n" <>
      "      { \"Kind\": \"Input\", \"Content\": \"Plot[Sin[x], {x, 0, 2 Pi}]\" }\n\n" <>
      "  (b) \:4e8b\:524d\:8a55\:4fa1\:6e08\:307f\:306e\:56f3 (commit \:6642\:306b\:30b7\:30b9\:30c6\:30e0\:304c\:8a55\:4fa1):\n" <>
      "      { \"Kind\": \"Graphics\", \"HeldExpression\": \"Plot3D[Sin[x y], {x,-1,1}, {y,-1,1}]\" }\n\n" <>
      "  (c) \:30d5\:30a1\:30a4\:30eb\:304b\:3089\:756b\:50cf\:3092\:633f\:5165 (\:7d76\:5bfe\:30d1\:30b9\:3001\:30e6\:30fc\:30b6\:306b\:5b58\:5728\:3092\:78ba\:8a8d\:6e08\:307f\:306e\:6642):\n" <>
      "      { \"Kind\": \"ImagePath\", \"Path\": \"/path/to/fig.png\" }\n\n" <>
      "  (d) 2 \:5217 Grid (Mathematica \:306f\:6bb5\:7d44\:306a\:3057\:3001Grid \:304c\:5b9f\:7528\:7684):\n" <>
      "      { \"Kind\": \"Grid2Col\",\n" <>
      "        \"Left\":  { \"Kind\": \"Input\", \"Content\": \"Plot[...]\" },\n" <>
      "        \"Right\": { \"Style\": \"Text\", \"Content\": \"\:3053\:306e\:56f3\:306e\:89e3\:8aac\" } }\n\n" <>
      "\:3010\:56f3\:3092\:5165\:308c\:308b\:3079\:304d\:5834\:9762\:3011\n" <>
      "- \:30c7\:30fc\:30bf\:306e\:8996\:899a\:5316\:304c\:672c\:8cea\:7684\:306b\:91cd\:8981\:306a\:30c8\:30d4\:30c3\:30af (\:30b0\:30e9\:30d5\:3001\:5bfe\:8868\:3001\:30c0\:30a4\:30a2\:30b0\:30e9\:30e0\:3001\:30a2\:30fc\:30ad\:30c6\:30af\:30c1\:30e3\:56f3)\n" <>
      "- \:6982\:5ff5\:9593\:306e\:95a2\:4fc2\:3092\:793a\:3059\:3068\:304d (\:7bc0\:9593\:306e\:65e2\:5b9a\:4f4d\:7f6e/\:5909\:63db\:95a2\:4fc2/\:30b7\:30fc\:30b1\:30f3\:30b9\:56f3)\n" <>
      "- Mathematica \:306e\:8a08\:7b97\:30b5\:30f3\:30d7\:30eb\:3092\:793a\:3059\:3068\:304d (Plot/Plot3D/Manipulate/Graphics \:306a\:3069)\n" <>
      "- \:30cb\:30e5\:30fc\:30b9\:7a0b\:5ea6\:306e\:56f3\:50cf (\:8a08\:7b97\:3067\:751f\:6210\:3067\:304d\:306a\:3044\:5834\:5408\:306f\:30d1\:30b9\:304c\:78ba\:5b9f\:306a\:3068\:304d\:306e\:307f ImagePath)\n" <>
      "- \:4e00\:65b9\:3067 \:5358\:7d14\:306a\:7b87\:6761\:66f8\:304d\:3060\:3051\:3067\:8db3\:308a\:308b\:30da\:30fc\:30b8\:3067 \:610f\:5473\:3082\:306a\:304f\:56f3\:3092\:6dfb\:3048\:308b\:306e\:306f NG\:3002\n\n",
      
      "\n[T08 Kind extension: figures, images, Grid]\n" <>
      "Cells entries are not limited to text cells. With {\"Kind\": ...},\n" <>
      "you can embed figures, images, and code:\n\n" <>
      "  (a) Mathematica code cell (the user evaluates to see a figure):\n" <>
      "      { \"Kind\": \"Input\", \"Content\": \"Plot[Sin[x], {x, 0, 2 Pi}]\" }\n\n" <>
      "  (b) Pre-evaluated graphics (system evaluates at commit time):\n" <>
      "      { \"Kind\": \"Graphics\", \"HeldExpression\": \"Plot3D[Sin[x y], {x,-1,1}, {y,-1,1}]\" }\n\n" <>
      "  (c) Import an image from an absolute path (only if you are SURE it exists):\n" <>
      "      { \"Kind\": \"ImagePath\", \"Path\": \"/path/to/fig.png\" }\n\n" <>
      "  (d) Two-column Grid (Mathematica lacks native multi-column; Grid is the workaround):\n" <>
      "      { \"Kind\": \"Grid2Col\",\n" <>
      "        \"Left\":  { \"Kind\": \"Input\", \"Content\": \"Plot[...]\" },\n" <>
      "        \"Right\": { \"Style\": \"Text\", \"Content\": \"Explanation of this figure\" } }\n\n" <>
      "[When to include figures]\n" <>
      "- Topics where visualization is essentially important (graphs, tables, diagrams, architecture)\n" <>
      "- Inter-concept relationships (state machines, transforms, sequence diagrams)\n" <>
      "- Mathematica demonstrations (Plot/Plot3D/Manipulate/Graphics examples)\n" <>
      "- Nuanced figures (only use ImagePath if paths are certain; otherwise skip)\n" <>
      "- Do NOT add meaningless figures to pages where a bullet list already suffices.\n\n"];
    
    (* T08: voice preservation \:2014 caller \:304c ReferenceText \:3092\:6e21\:305b\:3070
       \:30e6\:30fc\:30b6\:306e\:305d\:308c\:307e\:3067\:306e\:8a00\:3044\:56de\:3057/\:8a9e\:8abf\:3092\:5c11\:306a\:304f\:3068\:3082\:307e\:306d\:308b\:3088\:3046 LLM \:306b\:6307\:793a\:3002 *)
    refHint = If[StringQ[referenceText] && StringLength[referenceText] > 0,
      If[isJa,
        "\n\:3010\:8a00\:3044\:56de\:3057\:306e\:8981\:6c42\:2014\:30b5\:30f3\:30d7\:30eb\:3092\:53c2\:8003\:306b\:3011\n" <>
        "\:4ee5\:4e0b\:306f\:3053\:306e\:4f5c\:6210\:8005\:306e\:904e\:53bb\:30b9\:30e9\:30a4\:30c9\:304b\:3089\:306e\:6298\:63a2\:6587\:3067\:3059\:3002\:8a9e\:8abf\:30fb\:8a00\:3044\:56de\:3057\:30fb\n" <>
        "\:30c6\:30f3\:30b7\:30e7\:30f3\:3092\:3067\:304d\:308b\:3060\:3051\:8fd1\:3065\:3051\:3066\:304f\:3060\:3055\:3044 (\:7d20\:6750\:3092\:65b0\:3057\:304f\:66f8\:304d\:76f4\:3059\:3088\:308a\:3082\:3001\n" <>
        "\:305d\:306e\:307e\:307e\:306e\:8a9e\:611f\:3092\:5c3a\:91cd\:3059\:308b):\n\n",
        "\n[Voice preservation requirement \:2014 match this author's samples]\n" <>
        "Below are excerpts from this author's previous slides. Please match their tone,\n" <>
        "phrasing, and tension as closely as possible (do not rewrite freshly; respect\n" <>
        "their register):\n\n"] <>
      "====\n" <> StringTake[referenceText, UpTo[4000]] <>
      If[StringLength[referenceText] > 4000,
        "\n...(truncated)\n", "\n"] <> "====\n\n" <>
      If[isJa,
        "\:3068\:304f\:306b\:4ee5\:4e0b\:306f\:6ce8\:610f:\n" <>
        "- \:3088\:304f\:4f7f\:3046\:63a5\:7d9a\:8a9e/\:8ecd\:7684\:8a9e\:5f59\:3092\:53d6\:308a\:8fbc\:3080\n" <>
        "- \:5bfe\:6bd4\:30fb\:8a3c\:62e0\:306e\:63d0\:793a\:306e\:30bf\:30a4\:30df\:30f3\:30b0\:3092\:771f\:4f3c\:308b\n" <>
        "- Item / Text \:306e\:9577\:3055\:611f\:30fb\:5204\:5448\:306e\:6fc3\:6de1\:3092\:5408\:308f\:305b\:308b\n\n",
        "Specifically:\n" <>
        "- Reuse their favored connectives and technical vocabulary.\n" <>
        "- Mirror the timing of contrast/evidence-presentation.\n" <>
        "- Match the length and density of their Item/Text cells.\n\n"],
      ""];
    
    (* \:7d50\:5408 *)
    baseHint <> t08Hint <> refHint
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   Task 3: Generic Retry Helper (spec \:00a712.1 retry policy \:3092\:4e00\:822c\:5316)
   
   Worker JSON retry (Stage 3.5a) \:3068\:540c\:3058\:67a0\:7d44\:307f\:3092 reducer / committer \:3067\:3082
   \:5229\:7528\:3067\:304d\:308b\:3088\:3046\:306b\:62bd\:8c61\:5316\:3059\:308b\:30d8\:30eb\:30d1\:30fc\:3002
   
   fn[arg] \:3092\:7e70\:308a\:8fd4\:3057\:547c\:3073\:3001 classifier \:3067\:7d50\:679c\:3092\:5206\:985e\:3057\:3001
   "Retryable" \:306a\:3089\:518d\:8a66\:884c\:3001 "Success" / "Permanent" \:306a\:3089\:505c\:6b62\:3059\:308b\:3002
   
   API:
     iRetryableInvoke[fn, arg, opts] \:2192 <|
       "Result" -> \:6700\:7d42\:7d50\:679c,
       "Classification" -> "Success" | "Retryable" | "Permanent",
       "Attempts" -> N,
       "History" -> {<|"Attempt", "Result", "Classification"|>, ...}|>
   
   \:30aa\:30d7\:30b7\:30e7\:30f3:
     "MaxAttempts"  -> 1 (\:65e2\:5b9a\:3001\:518d\:8a66\:884c\:306a\:3057)
     "Classifier"   -> Automatic (\:7d50\:679c\:304c $Failed / Missing / Status=Failed \:3092 Retryable)
                       | fn[result] -> "Success" | "Retryable" | "Permanent"
     "ArgTransform" -> None (\:6bce\:56de\:540c\:3058 arg) | fn[arg, lastResult, attempt] -> newArg
     "DelayBetween" -> 0 (\:79d2)
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

iDefaultRetryClassify[result_] :=
  Which[
    result === $Failed, "Retryable",
    MissingQ[result],   "Retryable",
    AssociationQ[result] && Lookup[result, "Status", ""] === "Failed",
      "Retryable",
    AssociationQ[result] && Lookup[result, "Status", ""] === "RolledBack",
      "Retryable",
    AssociationQ[result] && KeyExistsQ[result, "Error"] &&
        Lookup[result, "Error", None] =!= None,
      "Retryable",
    True, "Success"];

Options[iRetryableInvoke] = {
  "MaxAttempts"   -> 1,
  "Classifier"    -> Automatic,
  "ArgTransform"  -> None,
  "DelayBetween"  -> 0
};

iRetryableInvoke[fn_, arg_, opts:OptionsPattern[]] :=
  Module[{maxAttempts, classifier, argTransform, delay,
          attempt = 0, result = Null, lastResult = None,
          classification = "Retryable", effectiveArg, history = {}},
    maxAttempts   = Max[1, OptionValue["MaxAttempts"]];
    classifier    = OptionValue["Classifier"];
    argTransform  = OptionValue["ArgTransform"];
    delay         = OptionValue["DelayBetween"];
    
    effectiveArg = arg;
    Do[
      attempt++;
      If[attempt > 1 && argTransform =!= None,
        effectiveArg = Quiet @ Check[
          argTransform[arg, lastResult, attempt], arg]];
      
      result = Quiet @ Check[fn[effectiveArg], $Failed];
      lastResult = result;
      
      classification = If[classifier === Automatic,
        iDefaultRetryClassify[result],
        Quiet @ Check[
          With[{c = classifier[result]},
            If[MemberQ[{"Success", "Retryable", "Permanent"}, c],
              c, "Retryable"]],
          "Retryable"]];
      
      AppendTo[history, <|"Attempt" -> attempt,
                          "Result" -> result,
                          "Classification" -> classification|>];
      
      If[classification === "Success" || classification === "Permanent",
        Break[]];
      
      If[delay > 0 && attempt < maxAttempts, Pause[delay]],
      {maxAttempts}];
    
    <|"Result"         -> lastResult,
      "Classification" -> classification,
      "Attempts"       -> attempt,
      "History"        -> history|>
  ];

(* iLLMWorkerAdapterBuilder: LLM を使う worker adapter を構築。
   iMakeMinimalAdapter を拡張し、QueryProvider を実 LLM 呼び出しに、
   ParseProposal を JSON 抽出に、ExecuteProposal を artifact 格納に置換する。
   
   Stage 3.5a (JSON \:518d\:8a66\:884c):
     QueryProvider \:306f\:5fdc\:7b54\:5f8c\:306b JSON \:62bd\:51fa\:30fb\:30b9\:30ad\:30fc\:30de\:691c\:8a3c\:3092 dry-run \:3057\:3001
     \:5931\:6557\:6642\:306f\:662f\:6b63\:30d7\:30ed\:30f3\:30d7\:30c8\:3067\:6700\:5927 JSONRetryMax \:56de\:307e\:3067\:518d\:8a66\:884c\:3059\:308b\:3002
     "JSONRetryMax" -> 1 (\:65e2\:5b9a) \:306f\:518d\:8a66\:884c\:306a\:3057\:3002\:5b9f\:7528\:7684\:306b\:306f 2 \:307e\:305f\:306f 3 \:3092\:63a8\:5968\:3002 *)
Options[iLLMWorkerAdapterBuilder] = {
  "QueryFunction" -> Automatic,
  "Model"         -> Automatic,
  "JSONRetryMax"  -> 1,
  "ReferenceText" -> None    (* T08: slide voice preservation *)
};

iLLMWorkerAdapterBuilder[role_String, task_Association,
    depArtifacts_Association, opts:OptionsPattern[]] :=
  Module[{queryFn, workerPrompt, outputSchema, adapter, jsonRetryMax,
          schemaKeys, refText},
    queryFn      = OptionValue["QueryFunction"];
    outputSchema = Lookup[task, "OutputSchema", <||>];
    jsonRetryMax = Max[1, OptionValue["JSONRetryMax"]];
    refText      = OptionValue["ReferenceText"];
    schemaKeys   = If[AssociationQ[outputSchema], Keys[outputSchema], {}];
    (* T08: refText \:3092 worker prompt builder \:306b\:6e21\:3059 *)
    workerPrompt = iWorkerBuildSystemPrompt[role, task, depArtifacts,
      refText];
    
    adapter = <|
      "SyncProvider" -> True,
      
      "BuildContext" -> Function[{input, convState},
        <|
          "Input"               -> input,
          "Role"                -> role,
          "Task"                -> task,
          "Capabilities"        -> Lookup[$ClaudeOrchestratorCapabilities, role, {}],
          "DependencyArtifacts" -> depArtifacts,
          "WorkerPrompt"        -> workerPrompt
        |>],
      
      "QueryProvider" -> Function[{ctx, convState},
        Module[{prompt, basePrompt, response, inputGoal, attempt = 0,
                lastResponse = "", jsonStr, parsedTest, missing,
                isValid = False, retryPrompt},
          inputGoal = If[AssociationQ[ctx["Input"]],
            Lookup[ctx["Input"], "Goal", ToString[ctx["Input"]]],
            ToString[ctx["Input"]]];
          basePrompt = Lookup[ctx, "WorkerPrompt", ""] <> "\n\n" <>
            "Execute the task now. Input: " <> inputGoal;
          
          (* \:521d\:56de\:30fb\:518d\:8a66\:884c\:30eb\:30fc\:30d7\:3002 attempt \:306f\:30d6\:30ed\:30c3\:30af\:5148\:982d\:3067\:30a4\:30f3\:30af\:30ea\:30e1\:30f3\:30c8\:3057\:3001
             Break \:3092\:542b\:3081\:3066 attempt \:306f\:5e38\:306b\:300c\:5b9f\:969b\:306b\:884c\:3063\:305f LLM \:547c\:3073\:51fa\:3057\:56de\:6570\:300d\:306b\:4e00\:81f4\:3055\:305b\:308b\:3002 *)
          Do[
            attempt++;
            prompt = If[attempt === 1,
              basePrompt,
              (* \:518d\:8a66\:884c\:30d7\:30ed\:30f3\:30d7\:30c8: \:524d\:56de\:5fdc\:7b54\:3092\:63d0\:793a\:3057\:3001\:53b3\:683c\:306a JSON \:3092\:8981\:6c42 *)
              retryPrompt = "Your previous response could not be parsed as a valid JSON object" <>
                If[Length[schemaKeys] > 0,
                  " or was missing required keys.\n\nRequired JSON keys: " <>
                    StringRiffle[schemaKeys, ", "],
                  "."] <>
                "\n\nYour previous response was:\n" <>
                StringTake[ToString[lastResponse], UpTo[800]] <>
                "\n\nPlease respond ONLY with a single JSON object inside ```json ... ``` fences.\n" <>
                "Do NOT include any text outside the JSON block.\n\n" <>
                "Original task:\n" <> basePrompt;
              retryPrompt];
            
            lastResponse = If[queryFn === Automatic,
              (* T27: \:540c\:671f\:7248 ClaudeQueryBg \:3092\:4f7f\:7528 *)
              Quiet @ Check[
                ClaudeCode`ClaudeQueryBg[prompt],
                ""],
              Quiet @ Check[queryFn[prompt], ""]];
            If[!StringQ[lastResponse], lastResponse = ""];
            
            (* dry-run: JSON \:30d1\:30fc\:30b9 + \:5fc5\:9808\:30ad\:30fc\:691c\:8a3c *)
            jsonStr = iExtractJSONFromResponse[lastResponse];
            parsedTest = iParseJSON[jsonStr];
            If[AssociationQ[parsedTest],
              missing = If[Length[schemaKeys] > 0,
                Complement[schemaKeys, Keys[parsedTest]], {}];
              If[Length[missing] === 0,
                isValid = True;
                Break[]]],
            {jsonRetryMax}];
          
          response = lastResponse;
          <|"response" -> response,
            "Attempts" -> attempt,
            "JSONValid" -> isValid|>
        ]],
      
      "ParseProposal" -> Function[{raw},
        Module[{responseText, jsonStr, parsed, payload},
          responseText = If[StringQ[raw], raw,
            If[AssociationQ[raw], Lookup[raw, "response", ""], ""]];
          
          (* JSON \:62bd\:51fa\:3092\:8a66\:307f\:308b *)
          jsonStr = iExtractJSONFromResponse[responseText];
          parsed  = iParseJSON[jsonStr];
          
          If[AssociationQ[parsed],
            (* JSON \:304c\:53d6\:308c\:305f: artifact payload \:3068\:3057\:3066\:4fdd\:6301 *)
            payload = parsed;
            <|"HeldExpr"     -> HoldComplete[True],
              "TextResponse" -> responseText,
              "HasProposal"  -> True,
              "ArtifactPayload" -> payload|>,
            (* JSON \:304c\:53d6\:308c\:306a\:304b\:3063\:305f: \:30c6\:30ad\:30b9\:30c8\:5fdc\:7b54\:3068\:3057\:3066\:6271\:3046 *)
            <|"HeldExpr"     -> HoldComplete[True],
              "TextResponse" -> responseText,
              "HasProposal"  -> True,
              "ArtifactPayload" -> <|"Summary" -> responseText|>|>
          ]
        ]],
      
      "ValidateProposal" -> Function[{prop, ctx},
        iValidateWorkerProposal[prop, ctx, role]],
      
      "ExecuteProposal" -> Function[{prop, val},
        Module[{payload},
          If[Lookup[val, "Decision", "Deny"] === "Deny",
            <|"Success" -> False, "RawResult" -> None,
              "Error" -> "DeniedByValidator"|>,
            payload = Lookup[prop, "ArtifactPayload",
              <|"Summary" -> Lookup[prop, "TextResponse", ""]|>];
            <|"Success"   -> True,
              "RawResult" -> payload,
              "Error"     -> None|>
          ]]],
      
      "RedactResult" -> Function[{res, ctx},
        <|"RedactedResult" -> Lookup[res, "RawResult", None],
          "Summary"        -> ""|>],
      
      "ShouldContinue" -> Function[{red, convState, turnCount}, False]
    |>;
    
    adapter
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   4c. Stage 3.5b: \:4e26\:5217\:914d\:8eca (iSpawnWorkersDAG)
   
   LLMGraphDAGCreate \:3092\:4f7f\:3063\:3066 worker \:7fa4\:3092 sync \:30ce\:30fc\:30c9\:7fa4\:3068\:3057\:3066
   \:914d\:8eca\:3059\:308b\:3002 \:5404\:30cf\:30f3\:30c9\:30e9\:306f adapter \:3092\:76f4\:63a5\:547c\:3073\:51fa\:3057
   (BuildContext \:2192 QueryProvider \:2192 ParseProposal)\:3001 artifact \:3092\:8fd4\:3059\:3002
   ClaudeRunTurn \:3092\:4ecb\:3055\:306a\:3044\:306e\:3067 nested DAG \:554f\:984c\:304c\:8d77\:304d\:306a\:3044\:3002
   
   \:30b9\:30c1\:30e5\:30d6\:74b0\:5883\:3067\:306f\:5168 sync \:306a\:306e\:3067 LLMGraphDAGCreate \:304c\:5373\:5ea7\:306b
   \:5b8c\:4e86\:3059\:308b\:3002\:672c\:756a\:74b0\:5883\:3067\:3082\:3001 worker \:5168\:3066\:304c sync \:306a\:3089
   ScheduledTask \:306e\:5358\:4e00\:30c6\:30a3\:30c3\:30af\:5185\:3067\:5b8c\:4e86\:3059\:308b\:3002
   maxConcurrency \:306f sync \:7528\:306e\:8ad6\:7406\:7684\:5e76\:5217\:5ea6 (\:5b9f\:884c\:9806\:5e8f\:30d2\:30f3\:30c8)\:3002
   
   \:6700\:7d42 wait loop \:306f production \:74b0\:5883\:3067\:306e DAG \:5b8c\:4e86\:3092\:30dd\:30fc\:30ea\:30f3\:30b0\:3059\:308b\:305f\:3081\:3002
   stub \:74b0\:5883\:3067\:306f onComplete \:304c\:540c\:671f\:7684\:306b\:547c\:3070\:308c\:3001 completed=True \:306b\:306a\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

(* iCollectDepArtifactsFromJob: DAG \:30b8\:30e7\:30d6\:5185\:306e\:4f9d\:5b58\:30ce\:30fc\:30c9\:304b\:3089
   artifact \:3092\:96c6\:3081\:3001 prevArtifacts (\:73fe\:5728\:30b8\:30e7\:30d6\:5916\:306e\:84c4\:7a4d) \:3068
   \:7d50\:5408\:3057\:3066\:8fd4\:3059\:3002 *)
iCollectDepArtifactsFromJob[job_Association, deps_List,
    prevArtifacts_Association] :=
  Module[{nodes = Lookup[job, "nodes", <||>], result, n, art},
    result = prevArtifacts;  (* \:30b8\:30e7\:30d6\:5916\:306e\:84c4\:7a4d\:3092\:30d9\:30fc\:30b9\:306b *)
    Do[
      n = Lookup[nodes, d, <||>];
      art = Lookup[n, "result", None];
      If[AssociationQ[art],
        result[d] = art],
      {d, deps}];
    Association @@ Map[# -> Lookup[result, #, <||>] &, deps]
  ];

(* iRunSingleWorkerSync: \:5358\:4e00 worker \:30bf\:30b9\:30af\:3092 adapter \:76f4\:63a5\:547c\:3073\:51fa\:3057\:3067
   \:5b9f\:884c\:3001 artifact \:3092\:8fd4\:3059\:3002 DAG \:30cf\:30f3\:30c9\:30e9\:304b\:3089\:3082\:3001 \:7e26\:5217\:30d1\:30b9\:306e
   fallback \:304b\:3089\:3082\:5229\:7528\:53ef\:80fd\:3002 *)
iRunSingleWorkerSync[task_Association, builder_, queryFn_,
    depArtifacts_Association, jsonRetryMax_Integer,
    refText_:None] :=
  Module[{role, taskId, adapter, ctxPacket, queryResp, parsed,
          payload, input, schemaValidation, artifact},
    role   = Lookup[task, "Role", "Explore"];
    taskId = Lookup[task, "TaskId", ""];
    
    adapter = Which[
      builder === "LLM",
        iLLMWorkerAdapterBuilder[role, task, depArtifacts,
          "QueryFunction" -> queryFn,
          "JSONRetryMax"  -> jsonRetryMax,
          "ReferenceText" -> refText],   (* T08 *)
      builder === Automatic,
        iMakeMinimalAdapter[role,
          Function[ctx, "[stub worker response for " <> taskId <> "]"],
          task],
      True,
        builder[role, task, depArtifacts]];
    
    If[!AssociationQ[adapter],
      Return[<|"TaskId" -> taskId, "Status" -> "Failed",
               "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Error"],
               "Payload" -> <||>,
               "Diagnostics" -> <|"Error" -> "AdapterBuilderFailed"|>|>]];
    
    input = <|
      "Goal"   -> Lookup[task, "Goal", ""],
      "Role"   -> role,
      "TaskId" -> taskId,
      "DependencyArtifacts" -> depArtifacts,
      "OutputSchema" -> Lookup[task, "OutputSchema", <||>]
    |>;
    
    ctxPacket = Quiet @ Check[adapter["BuildContext"][input, <||>], <||>];
    queryResp = Quiet @ Check[adapter["QueryProvider"][ctxPacket, <||>], None];
    parsed = Quiet @ Check[adapter["ParseProposal"][queryResp], None];
    payload = If[AssociationQ[parsed],
      Lookup[parsed, "ArtifactPayload", None], None];
    
    artifact = If[AssociationQ[payload],
      <|"TaskId" -> taskId,
        "Status" -> "Success",
        "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Generic"],
        "Payload" -> payload,
        "Diagnostics" -> <|"Source" -> "DAGWorkerDirect"|>|>,
      <|"TaskId" -> taskId, "Status" -> "Failed",
        "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Error"],
        "Payload" -> <||>,
        "Diagnostics" -> <|"Error" -> "NoArtifactPayload"|>|>];
    
    (* Schema \:691c\:8a3c (\:7e26\:5217\:30d1\:30b9\:3068\:540c\:3058\:30ed\:30b8\:30c3\:30af) *)
    If[Lookup[artifact, "Status", ""] === "Success" &&
       AssociationQ[Lookup[task, "OutputSchema", None]] &&
       Length[Lookup[task, "OutputSchema", <||>]] > 0,
      schemaValidation = ClaudeValidateArtifact[artifact,
        Lookup[task, "OutputSchema", <||>]];
      If[AssociationQ[schemaValidation] &&
         !TrueQ[Lookup[schemaValidation, "Valid", False]],
        artifact = Join[artifact,
          <|"SchemaWarnings" -> Lookup[schemaValidation, "Errors", {}]|>]]];
    
    artifact
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iLaunchSingleWorker: worker \:30bf\:30b9\:30af\:306e deferred sync \:8d77\:52d5\:95a2\:6570 (v2026-04-20 T02)
   
   builder === "LLM" && queryFn === Automatic && jsonRetryMax === 1 \:306e\:5834\:5408\:306e\:307f
   adapter \:306e QueryProvider \:3092\:30d0\:30a4\:30d1\:30b9\:3057\:3066 CLI \:3092\:76f4\:63a5\:975e\:540c\:671f\:8d77\:52d5\:3059\:308b\:3002
   \:305d\:308c\:4ee5\:5916\:306f iRunSingleWorkerSync \:306b fallback\:3002
   
   BuildContext \:3092\:547c\:3093\:3067 WorkerPrompt + inputGoal \:3092\:5fa9\:5143\:3057\:3001\:5b8c\:5168\:306a prompt \:3092
   \:7d44\:307f\:7acb\:3066\:3066\:304b\:3089 iMakeBat \:2192 RunProcess\:3002 parseFn \:306f adapter \:3092\:53c2\:7167\:3059\:308b
   closure \:306b\:3057\:3001 ParseProposal \:3068 schema validation \:3092 tick \:5916\:3067\:884c\:3046\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iLaunchSingleWorker[task_Association, builder_, queryFn_,
    depArtifacts_Association, jsonRetryMax_Integer,
    refText_:None] :=
  Module[{role, taskId, adapter, ctxPacket, input, prompt,
          inputGoal, workerPrompt, workDir, uniqueTag,
          promptFile, outFile, batFile, proc},
    role   = Lookup[task, "Role", "Explore"];
    taskId = Lookup[task, "TaskId", ""];
    
    (* \:5bfe\:8c61\:5916: "LLM" builder + Automatic queryFn + jsonRetryMax=1 \:3053\:306e\:5834\:5408\:306e\:307f deferred \:5316 *)
    If[builder =!= "LLM" || queryFn =!= Automatic || jsonRetryMax =!= 1,
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    (* adapter \:3092 builder \:3067\:69cb\:7bc9\:3057\:3001BuildContext \:3067\:30d7\:30ed\:30f3\:30d7\:30c8\:3092\:5fa9\:5143 *)
    adapter = Quiet @ Check[
      iLLMWorkerAdapterBuilder[role, task, depArtifacts,
        "QueryFunction" -> queryFn,
        "JSONRetryMax"  -> jsonRetryMax,
        "ReferenceText" -> refText],
      $Failed];
    If[!AssociationQ[adapter],
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    input = <|
      "Goal"   -> Lookup[task, "Goal", ""],
      "Role"   -> role,
      "TaskId" -> taskId,
      "DependencyArtifacts" -> depArtifacts,
      "OutputSchema" -> Lookup[task, "OutputSchema", <||>]
    |>;
    
    ctxPacket = Quiet @ Check[adapter["BuildContext"][input, <||>], <||>];
    If[!AssociationQ[ctxPacket],
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    (* iLLMWorkerAdapterBuilder \:306e QueryProvider \:521d\:56de\:30d7\:30ed\:30f3\:30d7\:30c8\:3068\:540c\:5f62 *)
    inputGoal = If[AssociationQ[Lookup[ctxPacket, "Input", None]],
      Lookup[Lookup[ctxPacket, "Input", <||>], "Goal",
        ToString[Lookup[ctxPacket, "Input", ""]]],
      ToString[Lookup[ctxPacket, "Input", ""]]];
    workerPrompt = Lookup[ctxPacket, "WorkerPrompt", ""];
    prompt = workerPrompt <> "\n\n" <>
      "Execute the task now. Input: " <> inputGoal;
    
    If[!StringQ[prompt] || StringLength[prompt] === 0,
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    workDir = Quiet @ Check[
      ClaudeCode`$ClaudeWorkingDirectory, $TemporaryDirectory];
    If[!StringQ[workDir] || !DirectoryQ[workDir],
      workDir = $TemporaryDirectory];
    
    uniqueTag = taskId <> "_" <> ToString[Floor[AbsoluteTime[]]] <>
      "_" <> ToString[RandomInteger[999999]];
    promptFile = FileNameJoin[{workDir,
      "orch_worker_prompt_" <> uniqueTag <> ".txt"}];
    outFile = FileNameJoin[{workDir,
      "orch_worker_out_" <> uniqueTag <> ".txt"}];
    
    Quiet @ Check[
      Export[promptFile, prompt, "Text",
        CharacterEncoding -> "UTF-8"], $Failed];
    If[!FileExistsQ[promptFile],
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    batFile = Quiet @ Check[
      ClaudeCode`iMakeBat[promptFile, outFile, {}, False, {}],
      $Failed];
    If[!StringQ[batFile] || !FileExistsQ[batFile],
      Quiet @ DeleteFile[promptFile];
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    proc = Quiet @ Check[
      RunProcess[{"cmd", "/c", batFile},
        ProcessDirectory -> workDir,
        "Process"],
      $Failed];
    If[proc === $Failed || !MatchQ[proc, _ProcessObject],
      Quiet @ DeleteFile[promptFile];
      Quiet @ DeleteFile[batFile];
      Return[iRunSingleWorkerSync[task, builder, queryFn,
        depArtifacts, jsonRetryMax, refText]]];
    
    (* runState: parseFn closure \:306b adapter \:3068 task \:3092\:6355\:6349\:3055\:305b\:308b *)
    With[{tsk = task, adp = adapter},
      <|"proc"       -> proc,
        "outFile"    -> outFile,
        "batFile"    -> batFile,
        "promptFile" -> promptFile,
        "startTime"  -> AbsoluteTime[],
        "timeout"    -> 1200,
        "parseFn"    -> Function[{raw},
          iParseWorkerResult[tsk, adp, raw]]|>]
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iParseWorkerResult: iLaunchSingleWorker \:306e parseFn \:672c\:4f53
   
   adapter["ParseProposal"] \:3067 raw -> artifactPayload \:3092\:5f97\:3001\:7e26\:5217\:30d1\:30b9\:3068\:540c\:3058
   \:30b9\:30ad\:30fc\:30de\:691c\:8a3c\:3092\:884c\:3046\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iParseWorkerResult[task_Association, adapter_Association,
    raw_String] :=
  Module[{taskId, parsed, payload, artifact, schemaValidation,
          pseudoQueryResp},
    taskId = Lookup[task, "TaskId", ""];
    
    (* adapter \:306e ParseProposal \:306f raw \:304b Association\:ff08"response" \:30ad\:30fc\:4ed8\:304d\:ff09\:3092\:53d7\:3051\:53d6\:308b\:3002
       QueryProvider \:306f\:672c\:6765\:3001<|"response"->..., "Attempts"->..., "JSONValid"->...|> \:3092
       \:8fd4\:3059\:306e\:3067\:3001\:540c\:3058\:5f62\:306b\:307e\:3068\:3081\:3066\:6e21\:3059\:3002 *)
    pseudoQueryResp = <|
      "response"  -> raw,
      "Attempts"  -> 1,
      "JSONValid" -> True|>;
    
    parsed  = Quiet @ Check[
      adapter["ParseProposal"][pseudoQueryResp], None];
    payload = If[AssociationQ[parsed],
      Lookup[parsed, "ArtifactPayload", None], None];
    
    artifact = If[AssociationQ[payload],
      <|"TaskId" -> taskId,
        "Status" -> "Success",
        "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Generic"],
        "Payload" -> payload,
        "Diagnostics" -> <|"Source" -> "DAGWorkerDeferred"|>|>,
      <|"TaskId" -> taskId, "Status" -> "Failed",
        "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Error"],
        "Payload" -> <||>,
        "Diagnostics" -> <|"Error" -> "NoArtifactPayload"|>|>];
    
    (* Schema \:691c\:8a3c *)
    If[Lookup[artifact, "Status", ""] === "Success" &&
       AssociationQ[Lookup[task, "OutputSchema", None]] &&
       Length[Lookup[task, "OutputSchema", <||>]] > 0,
      schemaValidation = ClaudeValidateArtifact[artifact,
        Lookup[task, "OutputSchema", <||>]];
      If[AssociationQ[schemaValidation] &&
         !TrueQ[Lookup[schemaValidation, "Valid", False]],
        artifact = Join[artifact,
          <|"SchemaWarnings" -> Lookup[schemaValidation, "Errors", {}]|>]]];
    
    artifact
  ];

(* iSpawnWorkersDAG: \:4e26\:5217\:914d\:8eca\:30e1\:30a4\:30f3\:3002
   sortedTasks \:306f topologicalSort \:6e08\:307f\:3002 *)
iSpawnWorkersDAG[sortedTasks_List, builder_, queryFn_,
    cfg_Association] :=
  Module[{nodes = <||>, jobId, completed = False, completedJob = None,
          maxParallel, jsonRetryMax, verbose, prevArtifacts,
          artifacts, failures, n, art, status, t, tid, deps,
          maxWaitSec = 60, waited = 0, step = 0.05, dagAvail,
          sessionTag, refText},
    maxParallel  = Lookup[cfg, "MaxParallelism", 1];
    jsonRetryMax = Lookup[cfg, "JSONRetryMax", 1];
    verbose      = TrueQ[Lookup[cfg, "Verbose", False]];
    prevArtifacts = Lookup[cfg, "ArtifactAccumulator", <||>];
    refText       = Lookup[cfg, "ReferenceText", None];  (* T08 *)
    (* Phase 33 Task 2a: SessionTag \:3092\:751f\:6210\:3057 context \:3078\:6ce8\:5165\:3002
       cfg \:304b\:3089 "SessionTag" \:3092\:53d7\:3051\:53d6\:308b\:3053\:3068\:3082\:3067\:304d\:3001\:672a\:6307\:5b9a\:306a\:3089\:81ea\:52d5\:751f\:6210\:3059\:308b\:3002
       NotebookLLMGraph \:306e subset \:62bd\:51fa\:304c\:3053\:306e SessionTag \:3092\:30ad\:30fc\:306b\:4f7f\:3046\:3002 *)
    sessionTag = Lookup[cfg, "SessionTag",
      "orch-" <> ToString[Floor[AbsoluteTime[]]] <>
        "-" <> ToString[RandomInteger[99999]]];
    
    (* LLMGraphDAGCreate \:304c\:5b9f\:88c5\:3055\:308c\:3066\:3044\:308b\:304b\:78ba\:8a8d (\:30c6\:30b9\:30c8\:74b0\:5883
       \:3067\:306f stub \:3001 \:672c\:756a\:74b0\:5883\:3067\:306f claudecode \:306e\:5b9f\:88c5)\:3002 *)
    dagAvail = Quiet @ Check[
      ValueQ[ClaudeCode`LLMGraphDAGCreate] ||
        Length[DownValues[ClaudeCode`LLMGraphDAGCreate]] > 0,
      False];
    If[!dagAvail,
      (* DAG \:7121\:3057: \:7e26\:5217\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af *)
      Return[iSpawnWorkersFallback[sortedTasks, builder, queryFn,
        cfg, prevArtifacts]]];
    
    (* \:30ce\:30fc\:30c9\:69cb\:7bc9 *)
    Do[
      tid  = Lookup[t, "TaskId", ""];
      deps = Lookup[t, "DependsOn", {}];
      With[{ttask = t, ttid = tid, tdeps = deps,
            tbuilder = builder, tqueryFn = queryFn,
            tjsonRetry = jsonRetryMax,
            tprevArtifacts = prevArtifacts,
            trefText = refText},
        nodes[ttid] = ClaudeCode`iLLMGraphNode[
          ttid, "sync", "worker", tdeps,
          Function[{job},
            iRunSingleWorkerSync[ttask, tbuilder, tqueryFn,
              iCollectDepArtifactsFromJob[job, tdeps, tprevArtifacts],
              tjsonRetry, trefText]]]],    (* T08 *)
      {t, sortedTasks}];
    
    If[verbose,
      Print["  [dag-spawn] ", Length[nodes],
        " nodes, MaxParallelism=", maxParallel]];
    
    (* DAG \:8d77\:52d5 *)
    jobId = Quiet @ Check[
      ClaudeCode`LLMGraphDAGCreate[<|
        "nodes"          -> nodes,
        "taskDescriptor" -> <|
          "name"           -> "ClaudeSpawnWorkers (DAG)",
          "categoryMap"    -> <|"worker" -> "sync"|>,
          "maxConcurrency" -> <|"sync" -> maxParallel|>
        |>,
        "context"    -> <|"orchestratorJob" -> "spawn-dag",
          "SessionTag" -> sessionTag|>,
        "onComplete" -> Function[{job},
          completedJob = job;
          completed = True]
      |>],
      $Failed];
    
    If[jobId === $Failed,
      Return[iSpawnWorkersFallback[sortedTasks, builder, queryFn,
        cfg, prevArtifacts]]];
    
    (* \:5b8c\:4e86\:5f85\:6a5f (sync stub \:74b0\:5883\:3067\:306f\:5373\:6642 completed=True) *)
    While[!completed && waited < maxWaitSec,
      Pause[step]; waited += step];
    
    If[!completed || !AssociationQ[completedJob],
      Return[<|
        "Artifacts" -> prevArtifacts,
        "Failures"  -> {<|"Error" -> "DAGTimeout", "JobId" -> jobId|>},
        "Status"    -> "Failed"|>]];
    
    (* artifact \:7d44\:307f\:7acb\:3066 *)
    artifacts = prevArtifacts;
    failures  = {};
    Do[
      tid = Lookup[t, "TaskId", ""];
      n   = Lookup[Lookup[completedJob, "nodes", <||>], tid, <||>];
      art = Lookup[n, "result", None];
      If[AssociationQ[art],
        artifacts[tid] = art;
        If[Lookup[art, "Status", ""] =!= "Success",
          AppendTo[failures,
            <|"TaskId" -> tid,
              "Error"  -> "ArtifactExtractionFailed",
              "Details"-> Lookup[art, "Diagnostics", <||>]|>]],
        artifacts[tid] = <|"TaskId" -> tid, "Status" -> "Failed",
          "ArtifactType" -> Lookup[t, "ExpectedArtifactType", "Error"],
          "Payload" -> <||>,
          "Diagnostics" -> <|"NodeStatus" -> Lookup[n, "status", "?"],
                              "NodeError"  -> Lookup[n, "error", "?"]|>|>;
        AppendTo[failures, <|"TaskId" -> tid, "Error" -> "DAGNodeFailed"|>]],
      {t, sortedTasks}];
    
    status = Which[
      Length[failures] === 0, "Complete",
      Length[artifacts] > Length[prevArtifacts], "Partial",
      True, "Failed"];
    
    <|"Artifacts" -> artifacts,
      "Failures"  -> failures,
      "Status"    -> status,
      "DAGJobId"  -> jobId|>
  ];

(* iSpawnWorkersFallback: DAG \:4e0d\:53ef\:6642\:306b\:7e26\:5217\:5b9f\:884c\:3059\:308b
   \:30df\:30cb\:30de\:30eb\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af (Schema validation \:7b49\:306f\:7701\:7565\:3001
   ClaudeSpawnWorkers \:672c\:4f53\:306e\:30ed\:30b8\:30c3\:30af\:306b\:6238\:308b\:65b9\:304c\:5b89\:5168)\:3002 *)
iSpawnWorkersFallback[sortedTasks_List, builder_, queryFn_,
    cfg_Association, prevArtifacts_Association] :=
  Module[{artifacts = prevArtifacts, failures = {}, t, tid, deps,
          dArt, art, jsonRetryMax, refText},
    jsonRetryMax = Lookup[cfg, "JSONRetryMax", 1];
    refText      = Lookup[cfg, "ReferenceText", None];  (* T08 *)
    Do[
      tid  = Lookup[t, "TaskId", ""];
      deps = Lookup[t, "DependsOn", {}];
      dArt = Association @@ Map[
        # -> Lookup[artifacts, #, <||>] &, deps];
      art = iRunSingleWorkerSync[t, builder, queryFn, dArt,
        jsonRetryMax, refText];   (* T08 *)
      artifacts[tid] = art;
      If[Lookup[art, "Status", ""] =!= "Success",
        AppendTo[failures, <|"TaskId" -> tid,
          "Error" -> Lookup[Lookup[art, "Diagnostics", <||>],
            "Error", "FallbackFailed"]|>]],
      {t, sortedTasks}];
    <|"Artifacts" -> artifacts,
      "Failures"  -> failures,
      "Status"    -> If[Length[failures] === 0, "Complete",
        If[Length[artifacts] > Length[prevArtifacts], "Partial", "Failed"]],
      "DAGJobId"  -> "fallback-no-dag"|>
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   Task 4: True Parallelism via CLI Nodes
   
   Stage 3.5b \:306e LLMGraphDAGCreate sync \:30ce\:30fc\:30c9\:306f\:5358\:4e00 kernel \:5185\:306e\:64ec\:4f3c\:4e26\:5217\:3002
   \:672c\:5f53\:306e\:4e26\:5217\:306f\:5225 OS \:30d7\:30ed\:30bb\:30b9\:3067 Claude CLI \:3092\:8d77\:52d5\:3057\:3001 stdout
   JSON \:3092\:56de\:53ce\:3059\:308b\:3053\:3068\:3067\:9054\:6210\:3059\:308b\:3002
   
   \"ParallelismMode\" -> \"CLIFork\" \:3067\:6709\:52b9\:5316\:3002 \"CLICommand\" \:30d5\:30c3\:30af\:3067
   \:5b9f\:969b\:306e CLI \:547c\:3073\:51fa\:3057\:3092\:62bd\:8c61\:5316\:3057\:3001\:30c6\:30b9\:30c8\:3067\:306f\:30e2\:30c3\:30af\:95a2\:6570\:3092\:6e21\:3059\:3002
   
   Automatic \:306e\:5834\:5408:
     RunProcess[{\"claude\", \"-p\", prompt, \"--output-format\", \"json\"}] \:3092\:547c\:3073
     \:3001 stdout / ExitCode \:3092 Association \:3068\:3057\:3066\:8fd4\:3059\:3002
     Claude CLI \:304c PATH \:306b\:306a\:3051\:308c\:3070 ExitCode=\:975e0 \:3067 Failed\:3002
   
   \:4f9d\:5b58\:3092\:8003\:616e\:3057\:305f\:30d0\:30c3\:30c1\:30f3\:30b0:
     trace: \:540c\:3058 batch \:5185\:306e\:30bf\:30b9\:30af\:306f\:76f8\:4e92\:306b\:4f9d\:5b58\:3057\:306a\:3044\:305f\:3081
     \:5b8c\:5168\:4e26\:5217\:5316\:53ef\:80fd\:3002\:30d0\:30c3\:30c1\:306e\:7d42\:4e86\:3092\:5f85\:3063\:3066\:6b21\:306e batch \:3078\:9032\:3080\:3002
     (\:73fe\:72b6\:306f synchronous: \:5358\:4e00 kernel \:5185\:3067\:9806\:6b21 RunProcess\:3002 \:5c06\:6765
      ParallelMap / ProcessObject async \:306b\:5dee\:66ff\:3048\:53ef\:80fd\:306a\:69cb\:9020\:306b\:3057\:3066\:304a\:304f)\:3002
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

(* iTaskToCLIPrompt: task + depArtifacts \:304b\:3089 CLI \:30d7\:30ed\:30f3\:30d7\:30c8\:6587\:5b57\:5217\:3092\:751f\:6210\:3002
   iWorkerBuildSystemPrompt \:3092\:518d\:5229\:7528\:3059\:308b\:3053\:3068\:3067 worker adapter \:3068\:540c\:7b49
   \:306e\:6307\:793a\:3092 CLI \:3078\:6e21\:3059\:3002 *)
iTaskToCLIPrompt[task_Association, depArtifacts_Association] :=
  Module[{role, prompt, goalStr},
    role = Lookup[task, "Role", "Explore"];
    goalStr = Lookup[task, "Goal", ""];
    prompt = iWorkerBuildSystemPrompt[role, task, depArtifacts];
    prompt <> "\n\nTask input: " <> goalStr
  ];

(* iDefaultCLICommand: RunProcess \:7d4c\:7531\:3067 Claude CLI \:3092\:547c\:3076\:3002
   claude CLI \:304c\:4e0d\:53ef\:306a\:3089 ExitCode != 0 \:3068\:306a\:308a Failed \:5206\:985e\:3055\:308c\:308b\:3002 *)
iDefaultCLICommand[prompt_String, task_Association] :=
  Module[{result},
    result = iRunCLIUTF8[iResolveCLICommand[], prompt];
    If[!AssociationQ[result],
      Return[<|"StdOut" -> "", "StdErr" -> "claude CLI unavailable",
               "ExitCode" -> 127|>]];
    result
  ];

(* iRunSingleWorkerCLI: CLI \:3067 single worker \:3092\:5b9f\:884c\:3057\:3066 artifact \:3092\:8fd4\:3059\:3002
   iRunSingleWorkerSync \:306e CLI \:7248\:3002 CLICommand \:306f
   fn[prompt, task] -> <|StdOut, ExitCode|>\:3002 *)
iRunSingleWorkerCLI[task_Association, depArtifacts_Association,
    cliCmd_, jsonRetryMax_Integer] :=
  Module[{role, taskId, prompt, cliResult, jsonStr, parsed, payload,
          artifact, invokeWrapper, invokeResult},
    role   = Lookup[task, "Role", "Explore"];
    taskId = Lookup[task, "TaskId", ""];
    prompt = iTaskToCLIPrompt[task, depArtifacts];
    
    (* Task 3 \:306e iRetryableInvoke \:3067 CLI \:547c\:3073\:51fa\:3057\:3092 wrap\:3002
       ExitCode=0 \:304b\:3064 JSON parseable \:306a\:3089 Success\:3001 \:305d\:308c\:4ee5\:5916\:306f Retryable\:3002 *)
    invokeWrapper = Function[p,
      Module[{res = Quiet @ Check[cliCmd[p, task], $Failed]},
        res]];
    invokeResult = iRetryableInvoke[invokeWrapper, prompt,
      "MaxAttempts" -> jsonRetryMax,
      "Classifier" -> Function[r,
        Which[
          !AssociationQ[r], "Retryable",
          Lookup[r, "ExitCode", -1] =!= 0, "Retryable",
          True, "Success"]]];
    cliResult = Lookup[invokeResult, "Result", <||>];
    
    If[!AssociationQ[cliResult] ||
       Lookup[cliResult, "ExitCode", -1] =!= 0,
      Return[<|"TaskId"       -> taskId,
               "Status"       -> "Failed",
               "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Error"],
               "Payload"      -> <||>,
               "Diagnostics"  -> <|
                 "Error"    -> "CLIInvocationFailed",
                 "ExitCode" -> Lookup[cliResult, "ExitCode", -1],
                 "StdErr"   -> Lookup[cliResult, "StdErr", ""],
                 "Attempts" -> Lookup[invokeResult, "Attempts", 1]|>|>]];
    
    (* stdout \:304b\:3089 JSON \:62bd\:51fa\:3002 CLI --output-format json \:306e wrapper \:3092
       \:307b\:3069\:3044\:3066\:304b\:3089 iExtractJSONFromResponse \:306b\:6e21\:3059\:3002 *)
    jsonStr = iExtractJSONFromResponse[
      iUnwrapLLMResponse[Lookup[cliResult, "StdOut", ""]]];
    parsed  = iParseJSON[jsonStr];
    payload = If[AssociationQ[parsed], parsed, None];
    
    artifact = If[AssociationQ[payload],
      <|"TaskId"       -> taskId,
        "Status"       -> "Success",
        "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Generic"],
        "Payload"      -> payload,
        "Diagnostics"  -> <|"Source"   -> "CLIFork",
                            "Attempts" -> Lookup[invokeResult, "Attempts", 1]|>|>,
      <|"TaskId"       -> taskId,
        "Status"       -> "Failed",
        "ArtifactType" -> Lookup[task, "ExpectedArtifactType", "Error"],
        "Payload"      -> <||>,
        "Diagnostics"  -> <|"Error"   -> "NoJSONInCLIOutput",
                            "StdOut"  -> Lookup[cliResult, "StdOut", ""]|>|>];
    
    (* Schema \:691c\:8a3c (sync \:3068\:540c\:3058\:30ed\:30b8\:30c3\:30af) *)
    If[Lookup[artifact, "Status", ""] === "Success" &&
       AssociationQ[Lookup[task, "OutputSchema", None]] &&
       Length[Lookup[task, "OutputSchema", <||>]] > 0,
      Module[{schemaValidation},
        schemaValidation = ClaudeValidateArtifact[artifact,
          Lookup[task, "OutputSchema", <||>]];
        If[AssociationQ[schemaValidation] &&
           !TrueQ[Lookup[schemaValidation, "Valid", False]],
          artifact = Join[artifact,
            <|"SchemaWarnings" -> Lookup[schemaValidation, "Errors", {}]|>]]]];
    
    artifact
  ];

(* iSpawnWorkersCLIFork: CLI \:30d1\:30e9\:30ec\:30ea\:30ba\:30e0\:30e1\:30a4\:30f3\:3002
   sortedTasks \:306f topological\:3002 \:540c\:3058 batch (= \:540c\:3058 dep \:30ec\:30d9\:30eb) \:5185\:306f
   \:76f8\:4e92\:4f9d\:5b58\:3057\:306a\:3044\:305f\:3081\:4e26\:5217\:5316\:53ef\:80fd\:3002 \:73fe\:72b6 Map \:3067 sequential\:3001
   \:5c06\:6765 ParallelMap \:3078\:5dee\:66ff\:3048\:53ef\:80fd\:306a\:5f62\:306b\:3059\:308b\:3002 *)
iSpawnWorkersCLIFork[sortedTasks_List, cliCmd_, cfg_Association,
    prevArtifacts_Association] :=
  Module[{artifacts = prevArtifacts, failures = {}, jsonRetryMax,
          verbose, effCliCmd, t, tid, deps, dArt, art},
    jsonRetryMax = Lookup[cfg, "JSONRetryMax", 1];
    verbose      = TrueQ @ Lookup[cfg, "Verbose", False];
    effCliCmd    = If[cliCmd === Automatic, iDefaultCLICommand, cliCmd];
    
    Do[
      tid  = Lookup[t, "TaskId", ""];
      deps = Lookup[t, "DependsOn", {}];
      dArt = Association @@ Map[
        # -> Lookup[artifacts, #, <||>] &, deps];
      
      If[verbose,
        Print["  [cli-fork] spawning task ", tid, " (role=",
              Lookup[t, "Role", "Explore"], ")"]];
      
      art = iRunSingleWorkerCLI[t, dArt, effCliCmd, jsonRetryMax];
      artifacts[tid] = art;
      If[Lookup[art, "Status", ""] =!= "Success",
        AppendTo[failures, <|"TaskId" -> tid,
          "Error" -> Lookup[Lookup[art, "Diagnostics", <||>],
            "Error", "CLIForkFailed"]|>]],
      {t, sortedTasks}];
    
    <|"Artifacts" -> artifacts,
      "Failures"  -> failures,
      "Status"    -> If[Length[failures] === 0, "Complete",
        If[Length[artifacts] > Length[prevArtifacts], "Partial", "Failed"]],
      "Mode"      -> "CLIFork",
      "DAGJobId"  -> "cli-fork-no-dag"|>
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   5. ClaudeSpawnWorkers (spec §17.2)
   
   Stage 1 実装:
     - タスクを DependsOn で topological sort
     - 各タスクを単一 runtime で直列に起動
     - worker runtime は NotebookWrite を deny される adapter を使う
     - artifact を収集
   
   Stage 3.5b: MaxParallelism > 1 \:307e\:305f\:306f UseDAG -> True \:3067
              iSpawnWorkersDAG \:7d4c\:7531\:306e\:4e26\:5217\:914d\:8eca\:306b\:5207\:308a\:66ff\:308f\:308b\:3002
   ════════════════════════════════════════════════════════ *)

Options[ClaudeSpawnWorkers] = {
  "WorkerAdapterBuilder" -> Automatic,
  "MaxParallelism"       -> 1,
  "ArtifactAccumulator"  -> <||>,
  "QueryFunction"        -> Automatic,
  "JSONRetryMax"         -> 1,
  "UseDAG"               -> Automatic,
  "Verbose"              -> False,
  "ParallelismMode"      -> "Sync",   (* Task 4: "Sync" | "CLIFork" *)
  "CLICommand"           -> Automatic,(* Task 4: fn[prompt, task] -> <|StdOut,ExitCode|> *)
  "ReferenceText"        -> None      (* T08: slide voice preservation *)
};

ClaudeSpawnWorkers[tasksSpec_Association, opts:OptionsPattern[]] :=
  Module[{tasks, sorted, builder, artifacts, failures, prevArtifacts,
          verbose, taskId, artifact, adapter, runtimeId, input,
          role, depArtifacts, inputPacket, status, queryFn,
          schemaValidation, jsonRetryMax, maxParallel, useDag,
          dagResult, parallelMode, cliCommand, cliResult, refText},
    tasks    = Lookup[tasksSpec, "Tasks", {}];
    verbose  = TrueQ[OptionValue["Verbose"]];
    builder  = OptionValue["WorkerAdapterBuilder"];
    queryFn  = OptionValue["QueryFunction"];
    prevArtifacts = OptionValue["ArtifactAccumulator"];
    jsonRetryMax  = Max[1, OptionValue["JSONRetryMax"]];
    maxParallel   = Max[1, OptionValue["MaxParallelism"]];
    useDag        = OptionValue["UseDAG"];
    parallelMode  = OptionValue["ParallelismMode"];
    cliCommand    = OptionValue["CLICommand"];
    refText       = OptionValue["ReferenceText"];  (* T08 *)
    
    If[!ListQ[tasks] || Length[tasks] === 0,
      Return[<|
        "Artifacts" -> prevArtifacts,
        "Failures"  -> {},
        "Status"    -> "Complete",
        "Note"      -> "No tasks to spawn"
      |>]];
    
    sorted = iTopologicalSortTasks[tasks];
    If[sorted === $Failed,
      Return[<|
        "Artifacts" -> prevArtifacts,
        "Failures"  -> {<|"Error" -> "CyclicDependency"|>},
        "Status"    -> "Failed"
      |>]];
    
    (* Task 4: CLIFork \:30e2\:30fc\:30c9 \:2014 \:5225\:30d7\:30ed\:30bb\:30b9\:3067 Claude CLI \:3092\:8d77\:52d5 *)
    If[parallelMode === "CLIFork",
      cliResult = iSpawnWorkersCLIFork[sorted, cliCommand,
        <|"JSONRetryMax" -> jsonRetryMax,
          "Verbose"      -> verbose|>,
        prevArtifacts];
      Return[cliResult]];
    
    (* Stage 3.5b: \:4e26\:5217\:5b9f\:884c\:30d1\:30b9 \:2014 LLMGraphDAGCreate \:3092\:4f7f\:7528\:3057\:3066
       sync \:30ce\:30fc\:30c9\:7fa4\:3068\:3057\:3066 worker \:3092\:914d\:8eca\:3059\:308b\:3002\:5404\:30cf\:30f3\:30c9\:30e9\:306f
       adapter \:306e BuildContext \:2192 QueryProvider \:2192 ParseProposal \:3092
       \:76f4\:63a5\:547c\:3073\:3001 artifact \:3092\:7d44\:307f\:7acb\:3066\:308b (runtime \:3092\:7d4c\:7531\:3057\:306a\:3044
       \:306e\:3067 nested DAG \:554f\:984c\:3092\:56de\:907f)\:3002
       UseDAG \:2192 Automatic \:306e\:3068\:304d\:306f MaxParallelism > 1 \:3067\:81ea\:52d5\:6709\:52b9\:5316\:3001
       True/False \:660e\:8a18\:3067\:5f37\:5236\:5207\:308a\:66ff\:3048\:3002
       
       \:91cd\:8981: Return[...] \:306f\:73fe\:5728\:306e Module (ClaudeSpawnWorkers \:306e Module) \:304b\:3089
             \:8131\:51fa\:3055\:305b\:308b\:305f\:3081\:3001\:5165\:308c\:5b50 Module \:306b\:5305\:307e\:306a\:3044\:3002 *)
    Module[{shouldUseDag = Which[
        useDag === True, True,
        useDag === False, False,
        True, maxParallel > 1]},
      If[TrueQ[shouldUseDag] && Length[sorted] > 0,
        dagResult = iSpawnWorkersDAG[sorted, builder, queryFn,
          <|"MaxParallelism"      -> maxParallel,
            "JSONRetryMax"        -> jsonRetryMax,
            "Verbose"             -> verbose,
            "ArtifactAccumulator" -> prevArtifacts,
            "ReferenceText"       -> refText|>]]];  (* T08 *)
    If[ValueQ[dagResult] && AssociationQ[dagResult],
      Return[dagResult]];
    
    artifacts = prevArtifacts;
    failures  = {};
    
    Do[
      taskId = Lookup[t, "TaskId", ""];
      role   = Lookup[t, "Role", "Explore"];
      If[verbose,
        Print["  [spawn] ", taskId, " (role=", role, ") ",
          StringTake[ToString[Lookup[t, "Goal", ""]], UpTo[60]]]];
      
      (* \:4f9d\:5b58 artifact \:3092\:53ce\:96c6 *)
      depArtifacts = Association @@ Map[
        # -> Lookup[artifacts, #, <||>] &,
        Lookup[t, "DependsOn", {}]];
      
      (* worker \:7528 adapter \:3092\:69cb\:7bc9 *)
      adapter = Which[
        builder === "LLM",
          (* Stage 2 + 3.5a: LLM-backed worker (JSON \:518d\:8a66\:884c\:5bfe\:5fdc) *)
          iLLMWorkerAdapterBuilder[role, t, depArtifacts,
            "QueryFunction" -> queryFn,
            "JSONRetryMax"  -> jsonRetryMax,
            "ReferenceText" -> refText],    (* T08 *)
        builder === Automatic,
          iMakeMinimalAdapter[role,
            Function[ctx, "[stub worker response for " <> taskId <> "]"],
            t],
        True,
          builder[role, t, depArtifacts]];
      
      If[!AssociationQ[adapter],
        AppendTo[failures,
          <|"TaskId" -> taskId, "Error" -> "AdapterBuilderFailed"|>];
        artifacts[taskId] = <|"TaskId" -> taskId, "Status" -> "Failed",
          "ArtifactType" -> Lookup[t, "ExpectedArtifactType", "Error"],
          "Payload" -> <||>,
          "Diagnostics" -> <|"Error" -> "AdapterBuilderFailed"|>|>;
        Continue[]];
      
      (* runtime \:3092\:751f\:6210\:3057\:5358\:4e00\:30bf\:30fc\:30f3\:5b9f\:884c *)
      runtimeId = Quiet @ Check[
        ClaudeRuntime`CreateClaudeRuntime[adapter],
        $Failed];
      
      If[runtimeId === $Failed || !StringQ[runtimeId],
        (* Stage 2i: runtime \:4f5c\:6210\:5931\:6557\:6642\:306f adapter \:3092\:76f4\:63a5\:547c\:3093\:3067
           ArtifactPayload \:3092\:53d6\:308b fallback \:3002CreateClaudeRuntime \:304c
           \:4f55\:3089\:304b\:306e\:7406\:7531\:3067\:5931\:6557\:3057\:305f\:5834\:5408\:3067\:3082 worker \:306e artifact \:3092\:53ce\:96c6\:3067\:304d\:308b\:3002 *)
        AppendTo[failures,
          <|"TaskId" -> taskId, "Error" -> "CreateRuntimeFailed"|>];
        Module[{fbInput, ctxPacket, queryResp, parsed, payload,
                fbArtifact},
          fbInput = <|
            "Goal"   -> Lookup[t, "Goal", ""],
            "Role"   -> role,
            "TaskId" -> taskId|>;
          ctxPacket = Quiet @ Check[
            adapter["BuildContext"][fbInput, <||>], <||>];
          queryResp = Quiet @ Check[
            adapter["QueryProvider"][ctxPacket, <||>], None];
          parsed = Quiet @ Check[
            adapter["ParseProposal"][queryResp], None];
          payload = If[AssociationQ[parsed],
            Lookup[parsed, "ArtifactPayload", None], None];
          fbArtifact = If[AssociationQ[payload],
            <|"TaskId"      -> taskId,
              "Status"      -> "Success",
              "ArtifactType" -> Lookup[t, "ExpectedArtifactType", "Generic"],
              "Payload"     -> payload,
              "Diagnostics" -> <|"Source" -> "AdapterFallbackRuntimeMissing"|>|>,
            <|"TaskId" -> taskId, "Status" -> "Failed",
              "ArtifactType" -> Lookup[t, "ExpectedArtifactType", "Error"],
              "Payload" -> <||>,
              "Diagnostics" -> <|"Error" -> "CreateRuntimeFailed"|>|>];
          artifacts[taskId] = fbArtifact;
          (* Stage 2: schema validation \:3082 fallback artifact \:306b\:9069\:7528\:3059\:308b *)
          If[Lookup[fbArtifact, "Status", ""] === "Success" &&
             AssociationQ[Lookup[t, "OutputSchema", None]] &&
             Length[Lookup[t, "OutputSchema", <||>]] > 0,
            Module[{sv},
              sv = ClaudeValidateArtifact[fbArtifact,
                Lookup[t, "OutputSchema", <||>]];
              If[AssociationQ[sv] && !TrueQ[Lookup[sv, "Valid", False]],
                artifacts[taskId] = Join[fbArtifact,
                  <|"SchemaWarnings" -> Lookup[sv, "Errors", {}]|>]]]]];
        Continue[]];
      
      input = <|
        "Goal"             -> Lookup[t, "Goal", ""],
        "Role"             -> role,
        "TaskId"           -> taskId,
        "DependencyArtifacts" -> depArtifacts,
        "OutputSchema"     -> Lookup[t, "OutputSchema", <||>]
      |>;
      
      Module[{runResult},
        runResult = Quiet[
          Check[ClaudeRuntime`ClaudeRunTurn[runtimeId, input],
                $Failed]];
        If[runResult === $Failed,
          AppendTo[failures,
            <|"TaskId" -> taskId, "Error" -> "RunTurnFailed"|>]]];
      
      (* artifact \:62bd\:51fa\:306f\:5e38\:306b\:5b9f\:884c *)
      artifact = iExtractArtifactFromTurn[runtimeId, t];
      
      (* Stage 2e: artifact \:62bd\:51fa\:304c Failed \:306e\:5834\:5408\:306e\:6700\:7d42 fallback \:2014
         adapter \:306e BuildContext \:2192 QueryProvider \:2192 ParseProposal \:3092\:76f4\:63a5\:547c\:3073
         ArtifactPayload \:3092\:62fe\:3046\:3002NBAccess \:306e head \:30c1\:30a7\:30c3\:30af\:3084 AutoEval
         \:9632\:5fa1\:7b49\:306b\:3088\:308a runtime \:7d4c\:7531\:3067 ExecuteProposal \:306b\:5230\:9054\:3057\:306a\:3044
         \:5834\:5408\:3067\:3082 artifact \:3092\:53d6\:5f97\:53ef\:80fd\:306b\:3059\:308b\:3002 *)
      If[Lookup[artifact, "Status", "Failed"] =!= "Success" &&
         AssociationQ[adapter] &&
         KeyExistsQ[adapter, "ParseProposal"] &&
         KeyExistsQ[adapter, "QueryProvider"] &&
         KeyExistsQ[adapter, "BuildContext"],
        Module[{ctxPacket, queryResp, parsed, payload},
          ctxPacket = Quiet @ Check[
            adapter["BuildContext"][input, <||>], <||>];
          queryResp = Quiet @ Check[
            adapter["QueryProvider"][ctxPacket, <||>], None];
          parsed = Quiet @ Check[
            adapter["ParseProposal"][queryResp], None];
          payload = If[AssociationQ[parsed],
            Lookup[parsed, "ArtifactPayload", None], None];
          If[AssociationQ[payload],
            artifact = <|"TaskId"      -> taskId,
                         "Status"      -> "Success",
                         "ArtifactType" -> Lookup[t, "ExpectedArtifactType", "Generic"],
                         "Payload"     -> payload,
                         "Diagnostics" -> <|"Source" -> "AdapterDirectFallback"|>|>]]];
      
      (* Stage 2: artifact \:306e OutputSchema \:691c\:8a3c (round-trip validation)
         \:69cb\:6587\:7684\:306b\:5165\:308c\:5b50 If \:3092\:907f\:3051\:3001\:30d5\:30e9\:30c3\:30c8\:306a\:5358\:4f53\:6587\:3067\:8a18\:8ff0\:3059\:308b\:3002 *)
      schemaValidation = None;
      If[Lookup[artifact, "Status", "Failed"] === "Success" &&
         AssociationQ[Lookup[t, "OutputSchema", None]] &&
         Length[Lookup[t, "OutputSchema", <||>]] > 0,
        schemaValidation = ClaudeValidateArtifact[artifact,
          Lookup[t, "OutputSchema", <||>]]];
      
      (* \:691c\:8a3c\:5931\:6557\:6642\:306e\:307f SchemaWarnings \:3092\:8ffd\:52a0 (Join \:3067\:78ba\:5b9f\:306a merge) *)
      If[AssociationQ[schemaValidation] &&
         !TrueQ[Lookup[schemaValidation, "Valid", False]] &&
         AssociationQ[artifact],
        artifact = Join[artifact,
          <|"SchemaWarnings" -> Lookup[schemaValidation, "Errors", {}]|>]];
      
      (* verbose \:30ed\:30b0\:306f\:5225\:306e If \:3068\:3057\:3066\:72ec\:7acb\:3055\:305b\:308b *)
      If[verbose && AssociationQ[schemaValidation] &&
         !TrueQ[Lookup[schemaValidation, "Valid", False]],
        Print["    [warn] ", taskId, " schema mismatch: ",
          Lookup[schemaValidation, "Errors", {}]]];
      
      artifacts[taskId] = artifact;
      
      If[Lookup[artifact, "Status", "Failed"] =!= "Success",
        AppendTo[failures,
          <|"TaskId" -> taskId,
            "Error"  -> "ArtifactExtractionFailed",
            "Details"-> Lookup[artifact, "Diagnostics", <||>]|>]],
      {t, sorted}];
    
    status = Which[
      Length[failures] === 0, "Complete",
      Length[artifacts] > Length[prevArtifacts], "Partial",
      True, "Failed"];
    
    <|
      "Artifacts" -> artifacts,
      "Failures"  -> failures,
      "Status"    -> status
    |>
  ];

(* ════════════════════════════════════════════════════════
   6. ClaudeCollectArtifacts (spec §17.3)
   ════════════════════════════════════════════════════════ *)

ClaudeCollectArtifacts[spawnResult_Association] :=
  Module[{artifacts = Lookup[spawnResult, "Artifacts", <||>], rows},
    If[!AssociationQ[artifacts] || Length[artifacts] === 0,
      Return[Dataset[{}]]];
    rows = Map[
      Function[a,
        <|
          "TaskId"       -> Lookup[a, "TaskId", "?"],
          "Status"       -> Lookup[a, "Status", "?"],
          "ArtifactType" -> Lookup[a, "ArtifactType", "?"],
          "Summary"      -> iArtifactShortSummary[a]
        |>],
      Values[artifacts]];
    Dataset[rows]
  ];

ClaudeCollectArtifacts[_] := Dataset[{}];

iArtifactShortSummary[a_Association] :=
  Module[{p = Lookup[a, "Payload", <||>], s},
    s = Which[
      AssociationQ[p] && KeyExistsQ[p, "Summary"],
        ToString[p["Summary"]],
      AssociationQ[p] && Length[p] > 0,
        "[" <> ToString[Length[p]] <> " keys]",
      True, ""];
    StringTake[s, UpTo[80]]
  ];

(* ════════════════════════════════════════════════════════
   7. ClaudeValidateArtifact
   ════════════════════════════════════════════════════════ *)

ClaudeValidateArtifact[artifact_Association, outputSchema_Association] :=
  Module[{errs = {}, payload, missing, mismatched},
    payload = Lookup[artifact, "Payload", <||>];
    If[!AssociationQ[payload],
      Return[<|"Valid" -> False,
               "Errors" -> {iL["Payload \:304c Association \:3067\:306a\:3044",
                                "Payload is not an Association"]}|>]];
    
    missing = Complement[Keys[outputSchema], Keys[payload]];
    If[Length[missing] > 0,
      AppendTo[errs,
        iL["\:5fc5\:9808\:30ad\:30fc\:4e0d\:8db3: ", "Missing keys: "] <>
        StringRiffle[missing, ", "]]];
    
    (* 型の一致は緩くチェック: "String", "List[String]" 等 *)
    mismatched = {};
    KeyValueMap[
      Function[{k, schemaType},
        If[KeyExistsQ[payload, k],
          If[!iMatchesSchemaType[payload[k], schemaType],
            AppendTo[mismatched, k <> " (expected " <> schemaType <> ")"]]]],
      outputSchema];
    If[Length[mismatched] > 0,
      AppendTo[errs,
        iL["\:578b\:4e0d\:4e00\:81f4: ", "Type mismatch: "] <>
        StringRiffle[mismatched, ", "]]];
    
    <|"Valid" -> (Length[errs] === 0), "Errors" -> errs|>
  ];

ClaudeValidateArtifact[_, _] :=
  <|"Valid" -> False,
    "Errors" -> {iL["artifact \:307e\:305f\:306f schema \:304c Association \:3067\:306a\:3044",
                    "artifact or schema is not an Association"]}|>;

iMatchesSchemaType[val_, "String"] := StringQ[val];
iMatchesSchemaType[val_, "Integer"] := IntegerQ[val];
iMatchesSchemaType[val_, "Real"] := NumericQ[val];
iMatchesSchemaType[val_, "List[String]"] :=
  ListQ[val] && AllTrue[val, StringQ];
iMatchesSchemaType[val_, "List[Association]"] :=
  ListQ[val] && AllTrue[val, AssociationQ];
iMatchesSchemaType[val_, "Association"] := AssociationQ[val];
iMatchesSchemaType[val_, "List"] := ListQ[val];
iMatchesSchemaType[_, _] := True;  (* 未知の type は緩く許容 *)

(* ════════════════════════════════════════════════════════
   8. ClaudeReduceArtifacts (spec §17.4)
   ════════════════════════════════════════════════════════ *)

Options[ClaudeReduceArtifacts] = {
  "Reducer"       -> Automatic,
  "QueryFunction" -> Automatic,
  "RetryMax"      -> 1    (* Task 3: reducer \:81ea\:4f53\:306e\:518d\:8a66\:884c\:56de\:6570 *)
};

ClaudeReduceArtifacts[artifacts_Association, opts:OptionsPattern[]] :=
  Module[{reducer, queryFn, retryMax, result, retryWrapper,
          invokeResult, finalResult},
    reducer  = OptionValue["Reducer"];
    queryFn  = OptionValue["QueryFunction"];
    retryMax = Max[1, OptionValue["RetryMax"]];
    
    (* "LLM" \:6307\:5b9a: LLM-backed reducer (Stage 2.5) *)
    If[reducer === "LLM",
      (* Task 3: retry \:5305\:307f\:8fbc\:307f *)
      retryWrapper = Function[a, iLLMReducer[a, queryFn]];
      invokeResult = iRetryableInvoke[retryWrapper, artifacts,
        "MaxAttempts" -> retryMax,
        "Classifier" -> Function[r,
          If[AssociationQ[r], "Success", "Retryable"]]];
      result = Lookup[invokeResult, "Result", None];
      If[!AssociationQ[result],
        Return[<|"ArtifactType" -> "ReducedFailed",
                 "Payload"      -> <||>,
                 "Sources"      -> Keys[artifacts],
                 "Error"        -> "LLMReducerFailed",
                 "Attempts"     -> Lookup[invokeResult, "Attempts", 1]|>]];
      Return[<|"ArtifactType" -> "Reduced",
               "Sources"      -> Keys[artifacts],
               "Payload"      -> result,
               "Attempts"     -> Lookup[invokeResult, "Attempts", 1]|>]];
    
    If[reducer === Automatic,
      reducer = iDefaultReducer];
    
    If[!MatchQ[reducer, _Function | _Symbol],
      Return[<|"ArtifactType" -> "ReducedFailed",
               "Payload"      -> <||>,
               "Sources"      -> {},
               "Error"        -> "InvalidReducer"|>]];
    
    (* Task 3: \:30ab\:30b9\:30bf\:30e0 reducer \:3082 retry wrapper \:306b\:901a\:3059 *)
    invokeResult = iRetryableInvoke[reducer, artifacts,
      "MaxAttempts" -> retryMax,
      "Classifier" -> Function[r,
        If[AssociationQ[r], "Success", "Retryable"]]];
    result = Lookup[invokeResult, "Result", None];
    
    If[!AssociationQ[result],
      Return[<|"ArtifactType" -> "ReducedFailed",
               "Payload"      -> <||>,
               "Sources"      -> Keys[artifacts],
               "Error"        -> "ReducerReturnedNonAssociation",
               "Attempts"     -> Lookup[invokeResult, "Attempts", 1]|>]];
    
    finalResult = <|"ArtifactType" -> "Reduced",
                    "Sources"      -> Keys[artifacts],
                    "Payload"      -> result,
                    "Attempts"     -> Lookup[invokeResult, "Attempts", 1]|>;
    finalResult
  ];

ClaudeReduceArtifacts[_, ___] :=
  <|"ArtifactType" -> "ReducedFailed",
    "Payload"      -> <||>,
    "Sources"      -> {},
    "Error"        -> "InvalidArtifacts"|>;

(* \:2500\:2500 \:65e2\:5b9a reducer: \:6c7a\:5b9a\:7684\:306a payload \:7d50\:5408\:3002
   \:5404 artifact \:306e Payload \:3092\:30ad\:30fc\:540d\:91cd\:8907\:306a\:3057\:3067 merge\:3002
   \:540c\:540d\:30ad\:30fc\:304c\:3042\:308c\:3070\:914d\:5217\:306b\:96c6\:7d04\:3002 *)
iDefaultReducer[artifacts_Association] :=
  Module[{merged = <||>, items, key, val, prev},
    items = SortBy[
      Values[artifacts],
      Lookup[#, "TaskId", ""] &];  (* \:6c7a\:5b9a\:7684\:9806\:5e8f *)
    Do[
      If[AssociationQ[a] && AssociationQ[Lookup[a, "Payload", None]],
        KeyValueMap[
          Function[{k, v},
            If[KeyExistsQ[merged, k],
              prev = merged[k];
              merged[k] = If[ListQ[prev], Append[prev, v], {prev, v}],
              merged[k] = v]],
          a["Payload"]]],
      {a, items}];
    merged
  ];

(* ════════════════════════════════════════════════════════
   8b. LLM-backed Reducer (Stage 2.5)
   
   artifact \:7fa4\:3092 LLM \:306b\:6e21\:3057\:3001\:7d71\:5408\:7d50\:679c\:3092 JSON \:3067\:5f97\:308b\:3002
   iDefaultReducer \:3092 fallback \:3068\:3057\:3066\:4fdd\:6301\:3002
   
   \:4f7f\:3044\:65b9:
     ClaudeReduceArtifacts[artifacts, "Reducer" -> "LLM"]
     ClaudeReduceArtifacts[artifacts, "Reducer" -> "LLM",
       "QueryFunction" -> myQueryFn]
   ════════════════════════════════════════════════════════ *)

$iReducerSystemPrompt =
"You are a reducer agent. You receive multiple task artifacts (JSON objects)
and must synthesize them into a single unified result.

RULES:
1. Merge all artifacts into one coherent JSON object.
2. Preserve all important information from each artifact.
3. Resolve conflicts by preferring more specific/detailed information.
4. The output must be a single JSON object (inside ```json ... ``` fences).
5. Do NOT include any text outside the JSON block.
6. All keys from all artifacts should be represented in the output.";

iLLMReducer[artifacts_Association, queryFn_] :=
  Module[{prompt, artifactSummary, response, jsonStr, parsed,
          actualQueryFn, deterministicFallback},
    
    (* artifact \:304c 0 \:500b\:306a\:3089\:7a7a *)
    If[Length[artifacts] === 0, Return[<||>]];
    
    (* artifact \:304c 1 \:500b\:306a\:3089\:305d\:306e\:307e\:307e\:8fd4\:3059 (\:7d71\:5408\:4e0d\:8981) *)
    If[Length[artifacts] === 1,
      Module[{single = First[Values[artifacts]]},
        Return[If[AssociationQ[single],
          Lookup[single, "Payload", <||>],
          <||>]]]];
    
    (* artifact \:7fa4\:306e\:30c6\:30ad\:30b9\:30c8\:5316 *)
    artifactSummary = StringJoin[
      KeyValueMap[
        Function[{tid, art},
          "--- Artifact: " <> tid <> " ---\n" <>
          ToString[Lookup[art, "Payload", <||>], InputForm] <> "\n\n"],
        artifacts]];
    
    prompt = $iReducerSystemPrompt <> "\n\n" <>
      "ARTIFACTS TO MERGE (" <> ToString[Length[artifacts]] <> " total):\n\n" <>
      artifactSummary <>
      "\nMerge these artifacts into a single JSON object.";
    
    actualQueryFn = If[queryFn === Automatic,
      (* T27: \:540c\:671f\:7248 ClaudeQueryBg \:3092\:4f7f\:7528 *)
      Function[{p}, Quiet @ Check[ClaudeCode`ClaudeQueryBg[p], $Failed]],
      queryFn];
    
    response = actualQueryFn[prompt];
    
    If[!StringQ[response] || response === $Failed,
      (* LLM \:5931\:6557\:6642\:306f\:6c7a\:5b9a\:7684 reducer \:306b fallback *)
      Return[iDefaultReducer[artifacts]]];
    
    jsonStr = iExtractJSONFromResponse[response];
    parsed  = iParseJSON[jsonStr];
    
    If[AssociationQ[parsed],
      parsed,
      (* JSON \:30d1\:30fc\:30b9\:5931\:6557\:6642\:3082\:6c7a\:5b9a\:7684 reducer \:306b fallback *)
      iDefaultReducer[artifacts]]
  ];

(* ════════════════════════════════════════════════════════
   9. ClaudeCommitArtifacts (spec §10.3, §17.5)
   
   Stage 3 の核心: committer は唯一 notebook へ書ける runtime。
   ただし HeldExpr は target notebook を With で束縛して書き換え、
   CreateNotebook / EvaluationNotebook[] を潰す。
   ════════════════════════════════════════════════════════ *)

Options[ClaudeCommitArtifacts] = {
  "CommitterAdapterBuilder" -> Automatic,
  "Confirm"                 -> False,
  "Verbose"                 -> False,
  "CommitMode"              -> "Direct",     (* Stage 4: "Direct" | "Transactional" *)
  "Verifier"                -> Automatic,    (* Stage 4: fn[buffer, cells] -> True/False *)
  "CommitRetryMax"          -> 1,            (* Task 3: commit \:5168\:4f53\:306e\:518d\:8a66\:884c\:56de\:6570 *)
  "DeterministicFallback"   -> True,         (* T05: LLM \:304c\:30bb\:30eb\:3092\:66f8\:304b\:306a\:304b\:3063\:305f\:3068\:304d
                                                 iDeterministicSlideCommit \:3067\:6a5f\:68b0\:7684\:306b\:88dc\:5b8c *)
  "Model"                   -> Automatic     (* v2026-04-20 T08: Committer adapter \:306b\:4f1d\:9054 *)
};

(* Task 3: Public ClaudeCommitArtifacts \:306f iCommitArtifactsOnce \:3092 iRetryableInvoke \:3067\:5305\:3080\:3002
   iCommitArtifactsOnce \:304c\:5b9f\:969b\:306e commit \:51e6\:7406\:672c\:4f53\:3002 *)
iCommitArtifactsOnce[targetNotebook_, reducedArtifact_Association,
    opts:OptionsPattern[ClaudeCommitArtifacts]] :=
  Module[{builder, adapter, runtimeId, input, confirm, verbose,
          result, status, commitMode, verifier, effectiveTarget,
          buffer, verifyOk, flushResult, bufferCells,
          cellsBefore, cellsAfter, cellsDelta, model},
    builder    = OptionValue["CommitterAdapterBuilder"];
    confirm    = TrueQ[OptionValue["Confirm"]];
    verbose    = TrueQ[OptionValue["Verbose"]];
    commitMode = OptionValue["CommitMode"];
    verifier   = OptionValue["Verifier"];
    model      = OptionValue["Model"];   (* v2026-04-20 T08 *)
    
    (* T04: \:30bf\:30fc\:30b2\:30c3\:30c8 nb \:306e\:30bb\:30eb\:6570\:3092\:8a18\:9332 (\:5b9f\:66f8\:8fbc\:691c\:77e5\:7528) *)
    cellsBefore = If[MatchQ[targetNotebook, _NotebookObject],
      Quiet @ Check[Length[Cells[targetNotebook]], 0],
      0];
    
    (* Automatic \:306a\:3089\:65e2\:5b9a\:306e iDefaultCommitterAdapterBuilder \:3092\:4f7f\:7528
       (Stage 3 \:5b8c\:5168\:7248: ClaudeCode`ClaudeBuildRuntimeAdapter \:3092\:30e9\:30c3\:30d7) *)
    If[builder === Automatic,
      builder = iDefaultCommitterAdapterBuilder];
    
    (* Stage 4: Transactional \:306f shadow buffer \:3092 effective target \:3068\:3057\:3066\:6e21\:3059\:3002
       committer \:306f buffer \:3092 notebook \:3068\:898b\:306a\:3057\:3066 NotebookWrite \:3059\:308b\:304c\:3001
       UpValue intercept \:3067\:30b9\:30c6\:30fc\:30b8\:3055\:308c\:308b\:3002 *)
    If[commitMode === "Transactional",
      buffer = iCreateShadowBuffer[targetNotebook];
      effectiveTarget = buffer,
      effectiveTarget = targetNotebook
    ];
    
    (* v2026-04-20 T08: builder \:304c Options \:3092\:53d7\:3051\:53d6\:308c\:308b\:306a\:3089 Model \:3092\:6e21\:3059\:3002
       iDefaultCommitterAdapterBuilder \:306f Options \:5bfe\:5fdc\:2014
       \:30ab\:30b9\:30bf\:30e0 builder \:306f\:3053\:306e Model \:3092\:7121\:8996\:3059\:308b\:53ef\:80fd\:6027\:304c\:3042\:308b\:305f\:3081
       Quiet @ Check \:3067\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002 *)
    adapter = Quiet @ Check[
      builder[effectiveTarget, reducedArtifact, "Model" -> model],
      Quiet @ Check[
        builder[effectiveTarget, reducedArtifact],
        $Failed]];
    
    If[adapter === $Failed || !AssociationQ[adapter],
      If[commitMode === "Transactional", iShadowBufferDiscard[buffer]];
      Return[<|"Status"  -> "Failed",
               "Details" -> "CommitterAdapterBuilderFailed"|>]];
    
    (* BaseAdapter \:4e0d\:53ef (ClaudeCode`ClaudeBuildRuntimeAdapter \:975e\:7a3c\:50cd\:74b0\:5883) *)
    If[Lookup[adapter, "Error", None] === "BaseAdapterUnavailable",
      If[commitMode === "Transactional", iShadowBufferDiscard[buffer]];
      Return[<|
        "Status"  -> "NotImplemented",
        "Details" -> iL[
          "ClaudeCode`ClaudeBuildRuntimeAdapter \:304c\:5229\:7528\:4e0d\:53ef\:3067\:3059\:3002",
          "ClaudeCode`ClaudeBuildRuntimeAdapter is unavailable."],
        "Hint"    -> iL[
          "CommitterAdapterBuilder \:306b mock \:3092\:6e21\:3059\:304b\:3001\:5b9f\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:4e0a\:3067\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
          "Pass mock via CommitterAdapterBuilder, or run in a real notebook."],
        "ReducedArtifact" -> reducedArtifact|>]];
    
    runtimeId = Quiet @ Check[
      ClaudeRuntime`CreateClaudeRuntime[adapter],
      $Failed];
    If[runtimeId === $Failed,
      If[commitMode === "Transactional", iShadowBufferDiscard[buffer]];
      Return[<|"Status"  -> "Failed",
               "Details" -> "CreateCommitterRuntimeFailed"|>]];
    
    input = <|
      "Goal"             -> iL["\:30ec\:30c7\:30e5\:30fc\:30b9\:3055\:308c\:305f artifact \:3092 notebook \:306b\:53cd\:6620",
                               "Commit reduced artifact to notebook"],
      "Role"             -> "Commit",
      "TargetNotebook"   -> effectiveTarget,
      "ReducedArtifact"  -> reducedArtifact,
      "CommitPolicy"     -> <|
        "DenyCreateNotebook"      -> True,
        "RewriteEvaluationNotebook" -> True|>
    |>;
    
    result = Quiet @ Check[
      ClaudeRuntime`ClaudeRunTurn[runtimeId, input],
      $Failed];
    
    (* v2026-04-20 T06: ClaudeRunTurn \:306f jobId \:3092\:8fd4\:3059\:3060\:3051\:3067 async\:3002
       \:3053\:308c\:307e\:3067\:306f\:5f85\:305f\:305a\:306b\:300cCommitted\:300d\:3068\:8aa4\:5224\:5b9a\:3057\:3066\:3044\:305f\:3002
       iWaitForRuntimeDAG \:3067\:5b8c\:4e86\:307e\:305f\:306f Fatal (rate limit \:7b49) \:3092\:5f85\:3064\:3002
       Fatal \:6642\:306f state \:3092\:4fdd\:6301\:3057\:305f\:307e\:307e Failed \:3092\:8fd4\:3057\:3001\:30e6\:30fc\:30b6\:306f
       ClaudeRuntime`ClaudeRuntimeRetry \:3067\:518d\:5b9f\:884c\:3001\:307e\:305f\:306f
       ClaudeRuntime`ClaudeRuntimeCancel \:3067\:4e2d\:6b62\:3067\:304d\:308b\:3002 *)
    Module[{waitResult, outcome, failureDetail, reason},
      If[!StringQ[result],
        If[verbose,
          Print[Style["  [commit] ClaudeRunTurn failed: " <>
            ToString[result], Red]]];
        If[commitMode === "Transactional", iShadowBufferDiscard[buffer]];
        Return[<|"Status"    -> "Failed",
                 "Reason"    -> "RunTurnFailed",
                 "Details"   -> ToString[result],
                 "RuntimeId" -> runtimeId|>]];
      
      waitResult = iWaitForRuntimeDAG[runtimeId, result, 300];
      outcome = Lookup[waitResult, "Outcome", "Unknown"];
      failureDetail = Lookup[waitResult, "FailureDetail", <||>];
      If[!AssociationQ[failureDetail], failureDetail = <||>];
      
      If[verbose,
        Print["  [commit] runtimeId=", runtimeId,
          " jobId=", result, " outcome=", outcome,
          " mode=", commitMode];
        If[(outcome === "Failed" || outcome === "Timeout") &&
           AssociationQ[failureDetail] && Length[failureDetail] > 0,
          Print[Style["    reason: " <>
            ToString[Lookup[failureDetail, "ReasonClass", "?"]] <>
            " - " <> ToString[
              StringTake[ToString[Lookup[failureDetail, "Error", "?"]], UpTo[120]]],
            Red]]]];
      
      If[outcome === "Failed" || outcome === "Timeout",
        If[commitMode === "Transactional", iShadowBufferDiscard[buffer]];
        reason = Which[
          outcome === "Timeout", "Timeout",
          AssociationQ[failureDetail] && StringQ[Lookup[failureDetail, "ReasonClass", None]],
            failureDetail["ReasonClass"],
          True, "UnknownFailure"];
        Return[<|
          "Status"        -> If[outcome === "Timeout", "Timeout", "Failed"],
          "Reason"        -> reason,
          "FailureDetail" -> failureDetail,
          "RuntimeId"     -> runtimeId,
          "JobId"         -> result,
          "DAGStatus"     -> Lookup[waitResult, "DAGStatus", <||>],
          "Hint"          -> iL[
            "ClaudeRuntime`ClaudeRuntimeRetry[\"" <> runtimeId <>
              "\"] \:3067\:5931\:6557\:30ce\:30fc\:30c9\:304b\:3089\:518d\:5b9f\:884c\:3001\:307e\:305f\:306f ClaudeRuntime`ClaudeRuntimeCancel[\"" <>
              runtimeId <> "\"] \:3067\:4e2d\:6b62\:3002",
            "ClaudeRuntime`ClaudeRuntimeRetry[\"" <> runtimeId <>
              "\"] to retry failed nodes, or ClaudeRuntime`ClaudeRuntimeCancel[\"" <>
              runtimeId <> "\"] to abort."]|>]];
    ];
    
    (* ClaudeRunTurn \:306f jobId (String) \:307e\:305f\:306f Missing[...] \:3092\:8fd4\:3059\:3002
       Missing[...] (RuntimeNotFound / RuntimeBusy) \:306f Failed \:6271\:3044\:3002
       T06: \:4e0a\:3067 iWaitForRuntimeDAG \:304c Failed/Timeout \:3092 early return \:3057\:3066\:3044\:308b\:306e\:3067\:3001
       \:3053\:3053\:306b\:6765\:308b\:306e\:306f Done (\:6b63\:5e38\:5b8c\:4e86) \:306e\:5834\:5408\:306e\:307f\:3002 *)
    status = Which[
      result === $Failed, "Failed",
      MissingQ[result],   "Failed",
      True,               "Committed"
    ];
    
    (* Stage 4: Transactional \:306e verify + flush/discard *)
    If[commitMode === "Transactional",
      bufferCells = iShadowBufferCells[buffer];
      verifyOk = Which[
        status === "Failed", False,
        verifier === Automatic, iShadowBufferVerify[buffer],
        True, TrueQ @ Quiet @ Check[verifier[buffer, bufferCells], False]
      ];
      If[verifyOk,
        flushResult = iShadowBufferFlush[buffer];
        Return[<|
          "Status"       -> "Committed",
          "Mode"         -> "Transactional",
          "RuntimeId"    -> runtimeId,
          "Adapter"      -> adapter,
          "Details"      -> result,
          "CellsWritten" -> Lookup[flushResult, "Count", 0],
          "FlushStatus"  -> Lookup[flushResult, "Status", "Unknown"],
          "FlushResults" -> Lookup[flushResult, "Results", {}]|>],
        iShadowBufferDiscard[buffer];
        Return[<|
          "Status"        -> "RolledBack",
          "Mode"          -> "Transactional",
          "Reason"        -> If[status === "Failed",
                               "CommitterFailed", "VerificationFailed"],
          "RuntimeId"     -> runtimeId,
          "Details"       -> result,
          "StagedCells"   -> Length[bufferCells]|>]
      ]
    ];
    
    (* Direct mode (Stage 3 compatibility) *)
    (* T04: \:30b3\:30df\:30c3\:30c8\:5f8c\:306e\:30bb\:30eb\:6570\:3092\:6e2c\:5b9a\:3001delta \:3092\:8a18\:9332\:3002
       "Committed" \:3060\:304c CellsDelta == 0 \:306a\:3089\:5b9f\:66f8\:8fbc\:306a\:3057 (Direct mode \:306e\:507d\:967d\:6027\:691c\:77e5)\:3002 *)
    cellsAfter = If[MatchQ[targetNotebook, _NotebookObject],
      Quiet @ Check[Length[Cells[targetNotebook]], 0],
      0];
    cellsDelta = cellsAfter - cellsBefore;
    
    (* T05: LLM \:304c Cell \:3092\:66f8\:304b\:306a\:304b\:3063\:305f\:5834\:5408\:3001\:6c7a\:5b9a\:8ad6 fallback \:3067\:6a5f\:68b0\:7684\:306b\:88dc\:5b8c\:3002
       trigger \:6761\:4ef6: Direct mode + real notebook + cellsDelta==0 +
                  DeterministicFallback==True + \:5c11\:306a\:304f\:3068\:3082 committer runtime \:306f\:5b8c\:4e86\:3002 *)
    Module[{useFallback, fbResult, fbCellsWritten = 0,
            fbCellsAfter, fbCellsDelta,
            fbStatus = "NotRun"},
      useFallback = TrueQ[OptionValue["DeterministicFallback"]] &&
        cellsDelta === 0 &&
        MatchQ[targetNotebook, _NotebookObject] &&
        (status === "Committed");
      
      If[useFallback,
        If[verbose,
          Print[Style["[commit] T05 fallback: LLM \:304c Cell \:3092\:66f8\:304b\:306a\:304b\:3063\:305f\:305f\:3081\:3001" <>
            "iDeterministicSlideCommit \:3092\:5b9f\:884c\:3057\:307e\:3059\:3002",
            Italic, GrayLevel[0.4]]]];
        fbResult = Quiet @ Check[
          iDeterministicSlideCommit[targetNotebook, reducedArtifact],
          <|"Status" -> "Failed", "CellsWritten" -> 0,
            "Error" -> "iDeterministicSlideCommitThrew"|>];
        If[!AssociationQ[fbResult],
          fbResult = <|"Status" -> "Failed", "CellsWritten" -> 0|>];
        fbCellsWritten = Lookup[fbResult, "CellsWritten", 0];
        fbStatus = Lookup[fbResult, "Status", "Unknown"];
        (* fallback \:5f8c\:306e\:5b9f\:6e2c\:5024\:3067\:4e0a\:66f8\:304d *)
        fbCellsAfter = Quiet @ Check[
          Length[Cells[targetNotebook]], cellsAfter];
        fbCellsDelta = fbCellsAfter - cellsBefore;
        cellsAfter = fbCellsAfter;
        cellsDelta = fbCellsDelta;
        If[verbose,
          Print[Style["[commit] T05 fallback: status=" <> ToString[fbStatus] <>
            " CellsWritten=" <> ToString[fbCellsWritten] <>
            " CellsDelta=" <> ToString[cellsDelta],
            Italic, GrayLevel[0.4]]]],
        (* useFallback == False: \:65e7\:8b66\:544a\:306e\:307f *)
        If[verbose && status === "Committed" && cellsDelta === 0,
          Print[Style["[commit] \:8b66\:544a: Status=Committed \:3060\:304c CellsDelta=0 (\:5b9f\:30bb\:30eb\:304c 1 \:3064\:3082\:66f8\:304b\:308c\:3066\:3044\:306a\:3044)\:3002",
            RGBColor[0.8, 0.5, 0]]]]
      ];
      
      <|
        "Status"               -> status,
        "Mode"                 -> "Direct",
        "RuntimeId"            -> runtimeId,
        "Adapter"              -> adapter,
        "Details"              -> result,
        "CellsBefore"          -> cellsBefore,
        "CellsAfter"           -> cellsAfter,
        "CellsDelta"           -> cellsDelta,
        "FallbackUsed"         -> TrueQ[useFallback],
        "FallbackStatus"       -> fbStatus,
        "FallbackCellsWritten" -> fbCellsWritten
      |>
    ]
  ];

(* Task 3: Public ClaudeCommitArtifacts \:306f iRetryableInvoke \:3067\:5305\:3080\:3002
   Status = "Committed" \:306f Success\:3001 "NotImplemented" \:306f Permanent (retry \:7121\:52b9)\:3001
   "Failed" / "RolledBack" \:306f Retryable\:3002 *)
ClaudeCommitArtifacts[targetNotebook_, reducedArtifact_Association,
    opts:OptionsPattern[]] :=
  Module[{retryMax, invokeResult, finalResult},
    retryMax = Max[1, OptionValue["CommitRetryMax"]];
    
    invokeResult = iRetryableInvoke[
      Function[t, iCommitArtifactsOnce[t, reducedArtifact, opts]],
      targetNotebook,
      "MaxAttempts" -> retryMax,
      "Classifier" -> Function[r,
        Which[
          !AssociationQ[r], "Retryable",
          Lookup[r, "Status", ""] === "Committed", "Success",
          Lookup[r, "Status", ""] === "NotImplemented", "Permanent",
          True, "Retryable"]]];
    
    finalResult = Lookup[invokeResult, "Result", <|"Status" -> "Failed"|>];
    If[AssociationQ[finalResult] && retryMax > 1,
      finalResult = Append[finalResult,
        "CommitAttempts" -> Lookup[invokeResult, "Attempts", 1]]];
    finalResult
  ];

(* ────────────────────────────────────────────────────────
   iRewriteCommitterHeldExpr (Stage 3 bug-fix + CreateNotebook 保険):
   
     committer の HeldExpr を安全に書き換える。
     
     1. HoldPattern[EvaluationNotebook[___]] -> targetNb  (spec \:00a710.3)
     2. HoldPattern[CreateNotebook[___]]    -> targetNb  (rewrite \:4fdd\:967a)
     3. HoldComplete[body] -> HoldComplete[With[{nb = targetNb}, body]]
     
     \:6ce8: \:65e7\:5b9f\:88c5\:306f `Evaluate[ReleaseHold[...]]` \:306b\:3088\:308a
         rewrite \:6642\:70b9\:3067\:5f0f\:3092\:5b9f\:884c\:3057\:3066\:3057\:307e\:3046\:91cd\:5927\:30d0\:30b0\:3092\:542b\:3093\:3067\:3044\:305f\:305f\:3081\:3001
         HoldComplete \:3092\:4fdd\:6301\:3057\:305f\:307e\:307e ReplaceAll \:3067\:66f8\:304d\:63db\:3048\:308b\:65b9\:5f0f\:306b\:5909\:66f4\:3002
     
     CreateNotebook \:306f iValidateWorkerProposal[role="Commit"] \:3067
     validation \:5c64\:3067 Deny \:3055\:308c\:308b\:306e\:304c\:5148\:306b\:8d70\:308b\:304c\:3001
     \:4e07\:4e00 validation \:3092\:901a\:904e\:3057\:305f\:5834\:5408\:3082 targetNb \:306b\:66f8\:304d\:66ff\:3048\:308b\:3053\:3068\:3067
     \:65b0\:898f notebook \:4f5c\:6210\:3092\:9632\:304f (defense-in-depth)\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iRewriteCommitterHeldExpr];

iRewriteCommitterHeldExpr[heldExpr:HoldComplete[_], targetNb_] :=
  With[{tn = targetNb},
    (* Stage 3.7 fix (2026-04-17 T13 patch): \:30b7\:30f3\:30dc\:30eb\:885d\:7a81 + Q1/Q3 \:5931\:6557\:5bfe\:5fdc
       
       \:65e7\:5b9f\:88c5 (Stage 3): With[{Global`nb = tn}, body] \:5305\:307f\:8fbc\:307f
         \:2192 Global`nb \:30ea\:30c6\:30e9\:30eb\:53c2\:7167\:304c parse \:6642\:306b\:30b7\:30f3\:30dc\:30eb\:751f\:6210\:3057
            ClaudeCode`nb \:3068\:885d\:7a81\:3001 shdw \:8b66\:544a
       
       Stage 3.6 (T12): With \:3092\:5ec3\:6b62\:3057 ReplaceAll \:3068 Symbol["Global`" <> "nb"] \:3092
                      \:7d44\:307f\:5408\:308f\:305b\:305f\:304c\:3001 nbSym \:4ee3\:5165\:6642\:306b Symbol \:306e\:8fd4\:308a\:5024
                      \:304c\:518d\:8a55\:4fa1\:3055\:308c\:3001 Global`nb \:306b\:5024\:304c\:3042\:308b\:5834\:5408 nbSym \:304c
                      \:305d\:306e\:5024\:306b\:306a\:308b\:3002 Q1/Q3 \:304c\:5931\:6557\:3002
       
       Stage 3.7 (T13): \:4e09\:756a\:76ee\:306e\:30eb\:30fc\:30eb (Global`nb \:7f6e\:63db) \:3092\:5b8c\:5168\:306b\:5ec3\:6b62\:3002
                      \:7406\:7531:
                      (a) shdw \:306e\:6839\:3068\:306a\:308b Global`nb \:53c2\:7167\:304c\:30bd\:30fc\:30b9\:304b\:3089\:5b8c\:5168\:6d88\:6ec5
                      (b) Symbol \:8a55\:4fa1\:30c1\:30a7\:30fc\:30f3\:306e\:5371\:967a\:6027\:3082\:6d88\:6ec5
                      (c) spec \:00a710.3 \:306e With \:675f\:7e1b\:306f\:300c\:5fc5\:8981\:306a\:3089\:300d\:306e\:4efb\:610f\:9805
                      (d) LLM \:30d7\:30ed\:30f3\:30d7\:30c8\:3067 EvaluationNotebook[] \:4f7f\:7528\:3092\:6307\:793a\:3057\:3066
                          \:3044\:308b\:305f\:3081\:3001\:7121\:4fee\:98fe nb \:3092 LLM \:304c\:5229\:7528\:3059\:308b\:30b1\:30fc\:30b9\:306f\:7a00
                      (e) \:4e07\:4e00 LLM \:304c NotebookWrite[nb, ...] \:3092\:751f\:6210\:3057\:3066\:3082\:3001 nb \:304c
                          \:672a\:675f\:7e1b\:306e\:305f\:3081 NotebookWrite \:306f $Failed \:3092\:8fd4\:3057 graceful \:306b\:5931\:6557
       
       \:7d50\:679c\:3001\:3053\:306e\:95a2\:6570\:306f EvaluationNotebook[___] \:3068 CreateNotebook[___] \:306e
       2 \:30d1\:30bf\:30fc\:30f3\:3092 targetNb \:306b\:5165\:308c\:66ff\:3048\:308b\:3060\:3051\:306e\:3082\:306e\:3068\:306a\:308b\:3002
       Q4 \:6c7a\:5b9a\:6027 (rewrite \:6642\:306b\:5b9f\:884c\:3055\:308c\:306a\:3044) \:306f\:7dad\:6301 (HoldComplete /. \:306e\:6027\:8cea)\:3002 *)
    heldExpr /. {
      HoldPattern[EvaluationNotebook[___]] :> tn,
      HoldPattern[CreateNotebook[___]]     :> tn
    }
  ];

(* non-HoldComplete \:306f\:7d20\:901a\:3057 *)
iRewriteCommitterHeldExpr[other_, _] := other;

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   Stage 4: Shadow Buffer + Transactional Commit (spec \:00a712.3 / \:00a716 Stage 4)
   
   Commit \:5931\:6557\:6642\:306e\:90e8\:5206\:53cd\:6620\:3092\:56de\:907f\:3059\:308b\:305f\:3081\:3001 committer \:306f shadow buffer
   \:306b\:5199\:3044\:305f\:5f8c\:3001 verify \:3057\:3001\:6210\:529f\:6642\:306e\:307f target notebook \:3078 flush \:3059\:308b\:3002
   \:5931\:6557\:6642\:306f buffer \:3092\:7834\:68c4\:3057\:3001 target notebook \:306f\:7121\:5909\:66f4\:3002
   
   \:6a5f\:69cb:
     iShadowBuffer[id_String] \:304c committer \:304b\:3089\:898b\:3048\:308b "target notebook" \:306e\:5f79\:3002
     UpValue \:3067 NotebookWrite[iShadowBuffer[id], ...] \:3092 intercept \:3057\:3001
     $iShadowBuffers \:306b\:7a4d\:307f\:4e0a\:3052\:308b\:3002 flush \:6642\:306b\:5b9f\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:3078\:9806\:756a\:306b\:9069\:7528\:3002
   
   API:
     iCreateShadowBuffer[targetNb]      \:2192 iShadowBuffer[id] \:30cf\:30f3\:30c9\:30eb
     iShadowBufferCells[buffer]         \:2192 stage \:6e08\:307f write \:4e00\:89a7 (Association list)
     iShadowBufferTarget[buffer]        \:2192 \:5b9f\:30bf\:30fc\:30b2\:30c3\:30c8
     iShadowBufferFlush[buffer]         \:2192 \:5b9f\:30bf\:30fc\:30b2\:30c3\:30c8\:306b\:9069\:7528 + \:30af\:30ea\:30a2\:30f3\:30a2\:30c3\:30d7
     iShadowBufferDiscard[buffer]       \:2192 \:7834\:68c4\:306e\:307f
     iShadowBufferVerify[buffer]        \:2192 \:30c7\:30d5\:30a9\:30eb\:30c8 verifier: True/False
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

(* Shadow buffer \:306e\:30b0\:30ed\:30fc\:30d0\:30eb state: id -> <|Writes, Target, Created|>
   \:4e26\:5217 commit \:306f\:60f3\:5b9a\:3057\:306a\:3044 (single committer \:306e\:305f\:3081 1 \:306e buffer/runtime)\:3002 *)
If[!AssociationQ[$iShadowBuffers], $iShadowBuffers = <||>];

iCreateShadowBuffer[targetNb_] :=
  Module[{id},
    id = "shadow-" <> ToString[Round[1000 AbsoluteTime[]]] <>
         "-" <> ToString[RandomInteger[{1000, 9999}]];
    $iShadowBuffers[id] = <|
      "Writes"  -> {},
      "Target"  -> targetNb,
      "Created" -> AbsoluteTime[]|>;
    iShadowBuffer[id]
  ];

(* UpValue: NotebookWrite[iShadowBuffer[id], ...] \:3092 intercept\:3002
   \:30b9\:30c6\:30fc\:30b8\:3057\:3066 Null \:3092\:8fd4\:3059 (\:5b9f NotebookWrite \:3068\:540c\:3058 \:2014 \:5b9f\:969b\:306e
   NotebookWrite \:306f Null \:3092\:8fd4\:3059)\:3002 *)
iShadowBuffer /: NotebookWrite[iShadowBuffer[id_String], args___] :=
  (If[KeyExistsQ[$iShadowBuffers, id],
    AppendTo[$iShadowBuffers[id, "Writes"],
      <|"Call"      -> "NotebookWrite",
        "Args"      -> {args},
        "Timestamp" -> AbsoluteTime[]|>]];
   Null);

(* \:4fdd\:967a: NotebookApply / NotebookPut \:3082 intercept (Stage 4.1 \:7b49\:4fa1) *)
iShadowBuffer /: NotebookApply[iShadowBuffer[id_String], args___] :=
  (If[KeyExistsQ[$iShadowBuffers, id],
    AppendTo[$iShadowBuffers[id, "Writes"],
      <|"Call"      -> "NotebookApply",
        "Args"      -> {args},
        "Timestamp" -> AbsoluteTime[]|>]];
   Null);

iShadowBuffer /: NotebookPut[expr_, iShadowBuffer[id_String], args___] :=
  (If[KeyExistsQ[$iShadowBuffers, id],
    AppendTo[$iShadowBuffers[id, "Writes"],
      <|"Call"      -> "NotebookPut",
        "Args"      -> {expr, args},
        "Timestamp" -> AbsoluteTime[]|>]];
   Null);

iShadowBufferCells[iShadowBuffer[id_String]] :=
  Lookup[Lookup[$iShadowBuffers, id, <||>], "Writes", {}];
iShadowBufferCells[_] := {};

iShadowBufferTarget[iShadowBuffer[id_String]] :=
  Lookup[Lookup[$iShadowBuffers, id, <||>], "Target", None];
iShadowBufferTarget[_] := None;

iShadowBufferDiscard[iShadowBuffer[id_String]] :=
  (KeyDropFrom[$iShadowBuffers, id]; True);
iShadowBufferDiscard[_] := False;

(* \:30c7\:30d5\:30a9\:30eb\:30c8 verifier: \:6700\:4f4e 1 \:4ef6\:306e write \:304c\:3042\:308a\:3001\:5404 write \:304c
   \:69cb\:9020\:7684\:306b\:6b63\:3057\:3044 (Call/Args \:30ad\:30fc\:3042\:308a) \:3053\:3068\:3092\:78ba\:8a8d\:3002 *)
iShadowBufferVerify[iShadowBuffer[id_String]] :=
  Module[{state, writes},
    state = Lookup[$iShadowBuffers, id, None];
    If[state === None, Return[False]];
    writes = Lookup[state, "Writes", {}];
    Length[writes] > 0 &&
    AllTrue[writes,
      AssociationQ[#] && KeyExistsQ[#, "Call"] &&
      KeyExistsQ[#, "Args"] &]
  ];
iShadowBufferVerify[_] := False;

(* flush: stage \:6e08\:307f write \:3092\:9806\:756a\:306b target \:3078\:9069\:7528\:3002
   \:5404 write \:306f Quiet@Check \:3067\:5305\:3080 (\:4e2d\:9014\:30a8\:30e9\:30fc\:304c\:4ed6 write \:3092
   \:30d6\:30ed\:30c3\:30af\:3057\:306a\:3044\:3088\:3046\:306b)\:3002\:7d50\:679c\:30ea\:30b9\:30c8\:3068\:6210\:529f\:4ef6\:6570\:3092\:8fd4\:3059\:3002 *)
iShadowBufferFlush[iShadowBuffer[id_String]] :=
  Module[{state, writes, target, results, successes},
    state = Lookup[$iShadowBuffers, id, None];
    If[state === None,
      Return[<|"Status" -> "Failed", "Reason" -> "BufferNotFound",
               "Count" -> 0, "Results" -> {}|>]];
    writes = Lookup[state, "Writes", {}];
    target = Lookup[state, "Target", None];
    If[target === None,
      KeyDropFrom[$iShadowBuffers, id];
      Return[<|"Status" -> "Failed", "Reason" -> "TargetMissing",
               "Count" -> 0, "Results" -> {}|>]];
    results = Map[
      Function[w,
        Module[{call, cargs, res},
          call  = Lookup[w, "Call", ""];
          cargs = Lookup[w, "Args", {}];
          res = Quiet @ Check[
            Switch[call,
              "NotebookWrite", NotebookWrite[target, Sequence @@ cargs],
              "NotebookApply", NotebookApply[target, Sequence @@ cargs],
              "NotebookPut",   NotebookPut[First[cargs], target,
                                 Sequence @@ Rest[cargs]],
              _, $Failed],
            $Failed];
          <|"Call" -> call, "Result" -> If[res === $Failed, "Failed", "OK"]|>
        ]],
      writes];
    successes = Count[results, r_Association /; Lookup[r, "Result"] === "OK"];
    KeyDropFrom[$iShadowBuffers, id];
    <|"Status"    -> If[successes === Length[writes], "Flushed", "PartialFlush"],
      "Count"     -> Length[writes],
      "Successes" -> successes,
      "Results"   -> results|>
  ];
iShadowBufferFlush[_] :=
  <|"Status" -> "Failed", "Reason" -> "NotAShadowBuffer",
    "Count" -> 0, "Results" -> {}|>;

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   T05 (2026-04-18): \:30b3\:30df\:30c3\:30bf\:30fc LLM \:5411\:3051\:30d2\:30f3\:30c8\:69cb\:7bc9\:3068\:6c7a\:5b9a\:8ad6 fallback
   
   \:80cc\:666f: T04 \:3067 CellsDelta=0 \:306e\:507d\:967d\:6027\:3092\:691c\:77e5\:3067\:304d\:308b\:3088\:3046\:306b\:306a\:3063\:305f\:304c\:3001\:6839\:672c\:539f\:56e0
   \:2014 committer LLM \:304c NotebookWrite \:3092\:542b\:3080 HeldExpr \:3092\:63d0\:6848\:3057\:306a\:3044 \:2014 \:306f
   T04 \:306e\:7bc4\:56f2\:5916\:3060\:3063\:305f\:3002\:539f\:56e0\:306f iDefaultCommitterAdapterBuilder \:306e
   BuildContext override \:3060\:3051\:3067\:306f iAdapterBuildPrompt (claudecode.wl) \:306b
   \:300cRole=Commit / ReducedArtifact / nb \:3078\:306e\:66f8\:8fbc\:7fa9\:52d9\:300d\:304c\:4f1d\:308f\:3089\:306a\:3044\:305f\:3081\:3002
   
   T05 \:306f\:4e8c\:6bb5\:69cb\:3048\:3067\:89e3\:6c7a\:3059\:308b:
     (1) iBuildCommitterHint \:2014 commit \:5c02\:7528\:306e instruction \:3092\:751f\:6210\:3002
         BuildContext override \:3067 input["Hint"] / input["OriginalTask"] \:306b\:4ed5\:8fbc\:307f\:3001
         iAdapterBuildPrompt \:306e TASK OVERVIEW \:3068 task detail \:4e21\:65b9\:306b\:5c4a\:304b\:305b\:308b\:3002
     (2) iDeterministicSlideCommit \:2014 LLM \:304c\:5931\:6557\:3057\:3066\:3082 reducedArtifact.Payload
         \:304b\:3089\:6a5f\:68b0\:7684\:306b Cell \:3092\:751f\:6210\:3001NotebookWrite \:3067\:76f4\:63a5\:66f8\:304d\:8fbc\:3080\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

(* ---- iBuildCommitterHint: \:30b3\:30df\:30c3\:30bf\:30fc\:7528\:30d7\:30ed\:30f3\:30d7\:30c8\:7247 ---------------
   reducedArtifact.Payload \:3092 InputForm \:3067\:30c0\:30f3\:30d7\:3057\:3001\:660e\:793a\:7684\:306a\:6307\:793a\:6587\:3068\:4e00\:7dd2\:306b
   \:8fd4\:3059\:3002iAdapterBuildPrompt \:306f input \:306e "Hint" \:3092 task detail \:306b\:3001
   "OriginalTask" \:3092 overview \:306b\:5165\:308c\:308b\:306e\:3067\:3001\:3053\:306e hint \:306f\:5168\:4f53\:304c LLM \:306b
   \:5c4a\:304f (TASK OVERVIEW \:306f\:5148\:982d 300 \:6587\:5b57\:306b\:5207\:3089\:308c\:308b\:306e\:3067 task detail \:3092\:672c\:547d)\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iBuildCommitterHint];

iBuildCommitterHint[reducedArtifact_Association, targetNb_] :=
  Module[{payload, payloadStr, payloadLen, guideStr},
    payload = Lookup[reducedArtifact, "Payload", <||>];
    payloadStr = ToString[payload, InputForm];
    payloadLen = StringLength[payloadStr];
    (* payload \:304c\:5927\:304d\:3059\:304e\:308b\:5834\:5408\:306f\:5207\:308a\:8a70\:3081\:3002LLM \:306b\:306f\:3059\:3079\:3066\:898b\:305b\:306a\:304f\:3066\:3082
       \:305d\:308c\:305e\:308c\:306e\:8981\:7d20\:3092\:628a\:63e1\:3059\:308b\:306b\:306f\:6700\:5927 5-6K \:3082\:3042\:308c\:3070\:5341\:5206\:3002 *)
    If[payloadLen > 6000,
      payloadStr = StringTake[payloadStr, 6000] <>
        "\n... (truncated; " <> ToString[payloadLen - 6000] <>
        " more chars)"];
    guideStr = StringJoin[
      "=== COMMITTER ROLE (read carefully) ===\n",
      "You are the SINGLE COMMITTER for this orchestration turn.\n",
      "Your ONLY job is to write the ReducedArtifact below into the ",
      "user's current notebook.\n\n",
      "STRICT RULES:\n",
      "1. You MUST produce ```mathematica``` code blocks containing ",
      "`NotebookWrite[EvaluationNotebook[], Cell[...]]` calls \:2014 ",
      "one call per slide / section / item.\n",
      "2. Use EvaluationNotebook[] to refer to the target notebook. ",
      "The orchestrator will rewrite EvaluationNotebook[] to the ",
      "correct notebook handle. Do NOT use SelectedNotebook[] or a file path.\n",
      "3. Do NOT call CreateNotebook, DocumentNotebook, NotebookPut, ",
      "NotebookSave, NotebookClose, Export, or any file I/O.\n",
      "4. Do NOT produce [DONE] until you have written one Cell for ",
      "every item in the payload below.\n",
      "5. Prefer cell styles \"Title\" / \"Section\" / \"Subsection\" / ",
      "\"Text\" / \"Code\" / \"Input\" as appropriate.\n",
      "6. If an item has {Title, Body, Code, ...} sub-fields, emit ",
      "MULTIPLE NotebookWrite calls for that item (title + body + code etc.).\n",
      "7. If you are unsure about a value, emit a Cell with \"Text\" ",
      "style containing a short placeholder \:2014 do NOT skip the item.\n\n",
      "EXAMPLE output shape:\n",
      "```mathematica\n",
      "NotebookWrite[EvaluationNotebook[], Cell[\"My Presentation\", \"Title\"]];\n",
      "NotebookWrite[EvaluationNotebook[], Cell[\"Introduction\", \"Section\"]];\n",
      "NotebookWrite[EvaluationNotebook[], Cell[\"This slide covers the background.\", \"Text\"]];\n",
      "NotebookWrite[EvaluationNotebook[], Cell[\"Plot[Sin[x], {x, 0, 2 Pi}]\", \"Input\"]];\n",
      "(* ... one or more NotebookWrite per slide ... *)\n",
      "```\n",
      "After ALL items are written, respond with a brief text ",
      "confirmation and [DONE].\n\n",
      "=== ReducedArtifact.Payload (InputForm) ===\n",
      payloadStr, "\n",
      "=== END ReducedArtifact.Payload ===\n"];
    guideStr
  ];

(* ---- iExtractSlidesFromPayload: payload \:304b\:3089 slide \:76f8\:5f53\:30c7\:30fc\:30bf\:3092\:62bd\:51fa ----
   T06 (2026-04-18): \:30ad\:30fc\:540d\:3060\:3051\:3067\:306f\:306a\:304f\:3001\:4e2d\:8eab\:304c slide-like \:306a List[Assoc] \:304b\:3082
   \:898b\:308b\:3088\:3046\:306b\:62e1\:5f35\:3002T05 \:3067\:306f Slides/Sections/Pages/Outline/Items/SlideList/Cells
   \:306e 7 \:30ad\:30fc\:540d\:306b\:9650\:3063\:3066\:3044\:305f\:305f\:3081\:3001reducer \:304c\:300cSlideOutline\:300d\:300cSlideDraft\:300d
   \:306e\:3088\:3046\:306a\:300cSlide\:4ed8\:304d\:30ad\:30fc\:300d\:3092\:751f\:3093\:3060\:5834\:5408\:306b\:62ff\:3048\:306a\:304b\:3063\:305f\:3002
   T06: (a) \:6b63\:898f\:8868\:73fe\:3067 Slide/Outline/Draft/Pages/Sections \:306a\:3069\:3092\:542b\:3080\:30ad\:30fc\:3092
             \:5e83\:304f\:62fe\:3046\:3001(b) \:305d\:308c\:3067\:3082\:51fa\:3066\:3053\:306a\:3051\:308c\:3070\:3001top-level \:306e\:5404\:5024\:3092\:898b\:3066
             slide-like List[Association] \:306a\:3089\:305d\:306e\:307e\:307e\:4f7f\:3046\:3002
   \:623b\:308a\:5024: {<|"Title" -> ..., "Body" -> ..., "Cells" -> ...|>, ...}
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iExtractSlidesFromPayload, iIsSlideLikeAssoc,
  iLooksLikeSlideList];

(* slide-like: Page / Title+Subtitle / Cells (inner) / BodyOutline /
   SlideKind \:306e\:3044\:305a\:308c\:304b\:3092\:542b\:3080 Association *)
iIsSlideLikeAssoc[a_Association] :=
  AnyTrue[{"Page", "SlideKind", "Cells", "BodyOutline", "Subtitle"},
    KeyExistsQ[a, #] &] ||
  (KeyExistsQ[a, "Title"] && (KeyExistsQ[a, "Body"] ||
    KeyExistsQ[a, "Content"] || KeyExistsQ[a, "Subtitle"]));
iIsSlideLikeAssoc[_] := False;

(* list \:304c slide list \:306b\:898b\:3048\:308b\:304b: \:5168\:4ef6 Association \:304b\:3064 \:534a\:6570\:4ee5\:4e0a\:304c slide-like *)
iLooksLikeSlideList[lst_List] :=
  Length[lst] > 0 &&
  AllTrue[lst, AssociationQ] &&
  (Count[lst, a_Association /; iIsSlideLikeAssoc[a]] * 2 >=
    Length[lst]);
iLooksLikeSlideList[_] := False;

(* ---- iParseAsCellList ----
   T11 (2026-04-19): LLM \:304c\:6587\:5b57\:5217\:3067\:30b7\:30ea\:30a2\:30e9\:30a4\:30ba\:3055\:308c\:305f Cell[...] \:5f0f\:306e\n
   \:30ea\:30b9\:30c8 (\:4f8b: CellExpressions \:30ad\:30fc\:306e\:5024) \:3092\:691c\:51fa\:3057\:305f\:3089\:3001
   \:305d\:308c\:3092\:30d1\:30fc\:30b9\:3057\:3066\:5b9f Cell[...] \:30aa\:30d6\:30b8\:30a7\:30af\:30c8\:306b\:623b\:3059\:3002
   
   \:5b89\:5168\:8005: ToExpression \:3092 HoldComplete \:3067\:5305\:307f\:3001\:5916\:5074\:304c Cell[___] \:3067\:3042\:308b
   \:3053\:3068\:3092\:78ba\:8a8d\:3057\:3066\:304b\:3089 ReleaseHold \:3059\:308b\:3002\:5916\:5074\:30d1\:30bf\:30fc\:30f3\:4e0d\:4e00\:81f4\:306e
   \:5f0f\:306f\:4e00\:5207\:8a55\:4fa1\:3057\:306a\:3044 (\:30b3\:30de\:30f3\:30c9\:30a4\:30f3\:30b8\:30a7\:30af\:30b7\:30e7\:30f3\:9632\:6b62)\:3002
   \:5168\:4ef6\:6210\:529f\:6642\:306e\:307f List[Cell[...]] \:3092\:8fd4\:3057\:3001\:5931\:6557\:6df7\:5728\:6642\:306f None \:3092\:8fd4\:3059\:3002 *)

ClearAll[iParseAsCellList];

iParseAsCellList[strs_List] :=
  Module[{parsed},
    parsed = Map[
      Function[s,
        Module[{held},
          held = Quiet @ Check[
            ToExpression[s, StandardForm, HoldComplete],
            $Failed];
          If[MatchQ[held, HoldComplete[Cell[___]]],
            (* \:5916\:5074\:304c Cell[...] \:3068\:78ba\:8a8d\:3067\:304d\:305f\:306e\:3067\:5b89\:5168\:306b\:5c55\:958b *)
            ReleaseHold[held],
            $Failed]]],
      strs];
    If[FreeQ[parsed, $Failed], parsed, None]
  ];
iParseAsCellList[_] := None;

iExtractSlidesFromPayload[payload_] :=
  Module[{slides = {}, candidate, knownKeys, flattenOne,
          keyMatches, flatten1, scored},
    flattenOne[x_] :=
      Which[
        AssociationQ[x], x,
        StringQ[x],      <|"Title" -> "", "Body" -> x|>,
        True,            <|"Title" -> "", "Body" -> ToString[x]|>];
    
    flatten1[cand_] :=
      Module[{flat = cand, safety = 0},
        If[!ListQ[flat], flat = {flat}];
        While[safety < 5 && AnyTrue[flat, ListQ],
          flat = Flatten[flat, 1]; safety++];
        Map[flattenOne, flat]];
    
    (* Case 0: \:975e Association \:306a payload \:2014 \:305d\:306e\:307e\:307e 1 \:30a2\:30a4\:30c6\:30e0\:306b *)
    If[!AssociationQ[payload],
      Return[{flattenOne[payload]}]];
    
    (* Case 1: \:65e2\:77e5\:306e\:30ad\:30fc\:3002\:540c\:540d\:30ad\:30fc\:306f\:65e2\:5b9a reducer \:3067\:300c\:30d8\:30ed\:30ea\:30b9\:30c8\:300d\:5316\:3055\:308c\:308b
       ({{s1,s2,...}, {s3,...}}) \:3092\:591a\:6bb5 Flatten \:3067\:5e73\:5766\:5316\:3002 *)
    knownKeys = {"Slides", "Sections", "Pages", "Outline", "Items",
                 "SlideList", "Cells"};
    Do[
      candidate = Lookup[payload, k, None];
      If[ListQ[candidate] && Length[candidate] > 0,
        slides = flatten1[candidate];
        Return[slides, Module]],
      {k, knownKeys}];
    
    (* T06 Case 1b: \:30ad\:30fc\:540d\:306b Slide|Outline|Draft|Pages|Sections \:3092\:542b\:3080
       \:30ad\:30fc (\:5927\:6587\:5b57\:5c0f\:6587\:5b57\:7121\:8996) \:3092\:5e83\:304f\:63a2\:3059\:3002
       \:4f8b: SlideOutline / SlideDraft / MySlidesV2 / outline_of_sections \:306a\:3069\:3002 *)
    keyMatches = Select[Keys[payload],
      StringQ[#] && StringMatchQ[#,
        RegularExpression["(?i).*(slide|outline|draft|pages?|sections?|items?).*"]] &];
    If[Length[keyMatches] > 0,
      Module[{candidates},
        candidates = Map[Function[k,
          Module[{v = Lookup[payload, k]},
            If[ListQ[v] && Length[v] > 0,
              {k, v, If[iLooksLikeSlideList[v], 2, 1] * Length[v]},
              {k, v, 0}]]],
          keyMatches];
        candidates = SortBy[candidates, -#[[3]] &];
        If[Length[candidates] > 0 && candidates[[1, 3]] > 0,
          slides = flatten1[candidates[[1, 2]]];
          Return[slides, Module]]]];
    
    (* T06 Case 1c: top-level \:306e\:5404\:5024\:3092\:898b\:3066\:3001list \:304b\:3064 slide-like \:306a\:3082\:306e\:306e
       \:4e2d\:3067\:6700\:3082\:9577\:3044 list \:3092\:4f7f\:3046\:3002(\:30ad\:30fc\:540d\:304c\:5168\:304f\:7570\:306a\:3063\:3066\:3044\:3066\:3082\:6551\:3046) *)
    scored = KeyValueMap[
      Function[{k, v},
        {k, v, If[ListQ[v] && iLooksLikeSlideList[v], Length[v], 0]}],
      payload];
    scored = SortBy[scored, -#[[3]] &];
    If[Length[scored] > 0 && scored[[1, 3]] > 0,
      slides = flatten1[scored[[1, 2]]];
      Return[slides, Module]];
    
    (* Case 2: payload \:5168\:4f53\:304c 1 \:500b\:306e slide \:3060\:3068\:307f\:306a\:305b\:308b\:5834\:5408 *)
    If[iIsSlideLikeAssoc[payload],
      Return[{flattenOne[payload]}]];
    
    (* Case 3: fallback \:2014 \:5404\:30ad\:30fc\:3092 section \:6271\:3044
       T09 (\:539f\:5247 32): \:5024\:304c\:69cb\:9020\:5316\:30c7\:30fc\:30bf\:306e\:5834\:5408\:306f Text \:306b\:653e\:308a\:8fbc\:307e\:305a\n
       "Code" \:30ad\:30fc\:3092\:4f7f\:3046\:3002
       T10 (\:539f\:5247 33): \:3055\:3089\:306b\:69cb\:9020\:5316\:30c7\:30fc\:30bf\:306f\:751f\:306e\:5024\:3092 "DatasetValue" \:3067\:6e21\:3057\:3001
       commit \:6642\:306b Dataset[] \:3067\:81ea\:52d5\:8a55\:4fa1 Output \:30bb\:30eb\:3092\:751f\:6210\:3059\:308b\:3002
       (ClaudeEval \:306e\:300c\:5b89\:5168\:306a\:5f0f\:306f\:81ea\:52d5\:5b9f\:884c\:300d\:898f\:5247\:3092\:53cd\:6620) *)
    If[Length[payload] > 0,
      slides = KeyValueMap[
        Function[{k, v},
          Module[{isStructured, parsedCells},
            isStructured = Which[
              ListQ[v] && Length[v] > 0 && AllTrue[v, AssociationQ], True,
              AssociationQ[v] && Length[v] > 0,                       True,
              ListQ[v] && Length[v] > 0 && AllTrue[v, ListQ],         True,
              True, False];
            (* T11: List[String] \:3067\:5168\:4ef6\:304c Cell[...] \:5f0f\:3068\:3057\:3066\:30d1\:30fc\:30b9\:3067\:304d\:308c\:3070 *)
            parsedCells = If[!isStructured && ListQ[v] && Length[v] > 0 &&
                             AllTrue[v, StringQ],
              iParseAsCellList[v],
              None];
            
            Which[
              ListQ[parsedCells],
                (* T11: \:30b7\:30ea\:30a2\:30e9\:30a4\:30ba\:3055\:308c\:305f Cell \:5f0f \:2192 \:5b9f Cell \:30aa\:30d6\:30b8\:30a7\:30af\:30c8\:3078 *)
                <|"Title"         -> ToString[k],
                  "PreBuiltCells" -> parsedCells|>,
              isStructured,
                (* T10: \:69cb\:9020\:5316\:30c7\:30fc\:30bf\:306f\:751f\:306e\:5024\:3068 Code \:4e21\:65b9\:3092\:6e21\:3059 *)
                <|"Title"        -> ToString[k],
                  "Code"         -> ToString[v, InputForm],
                  "DatasetValue" -> v|>,
              True,
                <|"Title" -> ToString[k],
                  "Body"  -> If[StringQ[v], v, ToString[v, InputForm]]|>]]],
        payload];
      Return[slides, Module]];
    
    {}
  ];

(* ---- iCellFromSlideItem: 1 \:500b\:306e slide-like Association \:304b\:3089 1 \:4ee5\:4e0a\:306e Cell \:3092\:751f\:6210 ----
   T06 (2026-04-18): \:5185\:90e8\:306b "Cells" \:30ea\:30b9\:30c8 (SlideDraft \:5f62\:5f0f) \:3092\:6301\:3064 item \:306f
   \:305d\:306e\:307e\:307e Cell[Content, Style] \:306b\:5c55\:958b\:3059\:308b\:3002Subtitle/BodyOutline/Page \:3082\:6271\:3046\:3002
   
   \:623b\:308a\:5024: {Cell[...], Cell[...], ...}
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iCellFromSlideItem, iInnerCellFromSpec];

(* \:5185\:90e8\:306e <|"Style"->..., "Content"->...|> \:3092 Cell[content, style] \:306b
   (Options \:30ad\:30fc\:306f\:73fe\:6642\:70b9\:3067\:306f\:7121\:8996\:2014 slide \:5143\:306e\:6574\:5f62\:306f\:5f8c\:56de)
   T07: Style \:6587\:5b57\:5217\:306f iSanitizeCellStyle \:3067\:5fc5\:305a\:6b63\:898f\:5316\:3059\:308b\:3002
        "Subsection (title slide)" / "Subsection + Item/Subitem \:7fa4" \:306e\:3088\:3046\:306a
        \:30d7\:30ed\:30fc\:30ba Style \:3082\:57fa\:5e95 style \:306b\:843d\:3068\:3059\:3002
   T08: \:65b0\:305f\:306b "Kind" \:30d5\:30a3\:30fc\:30eb\:30c9\:3092\:30b5\:30dd\:30fc\:30c8:
        - "Input" / "Code" : Mathematica \:30b3\:30fc\:30c9\:30bb\:30eb (\:56f3\:751f\:6210\:5f0f\:306a\:3069)
        - "Graphics"        : HeldExpression \:3092 commit \:6642\:306b\:8a55\:4fa1\:3057\:3066 Output \:30bb\:30eb\:306b
        - "ImagePath"       : Path \:3092 Import \:3057\:3066 Output \:30bb\:30eb\:306b
        - "Grid2Col"        : Left / Right \:3092 Grid \:306b\:5305\:3093\:3067 Output \:30bb\:30eb\:306b
        Kind \:304c\:7121\:3044\:5834\:5408\:306f\:5f93\:6765\:306e Style+Content \:52d5\:4f5c\:3002 *)
iInnerCellFromSpec[spec_Association] :=
  Module[{cnt, sty, rawSty, kind, heldExpr, path, leftSpec, rightSpec,
          leftCell, rightCell, boxed, leftBox, rightBox},
    kind = Lookup[spec, "Kind", None];
    
    (* ---- T08 Kind-based branches ---- *)
    Which[
      (* (a) Input/Code: Mathematica \:30b3\:30fc\:30c9\:30bb\:30eb *)
      kind === "Input" || kind === "Code",
        cnt = Lookup[spec, "Content",
               Lookup[spec, "HeldExpression", ""]];
        If[!StringQ[cnt], cnt = ToString[cnt]];
        Return[Cell[cnt, "Input"], Module],
      
      (* (b) Graphics: HeldExpression \:3092 commit \:6642\:306b\:8a55\:4fa1 \:2014 \:5931\:6557\:3057\:305f\:3089 Text \:306b fallback *)
      kind === "Graphics" || kind === "HeldExpression",
        heldExpr = Lookup[spec, "HeldExpression",
                    Lookup[spec, "Content", ""]];
        If[!StringQ[heldExpr], heldExpr = ToString[heldExpr]];
        boxed = Quiet @ Check[
          ToBoxes[ToExpression[heldExpr]],
          Null];
        If[boxed === Null || boxed === $Failed,
          Return[Cell["(Graphics eval failed: " <>
            StringTake[heldExpr, UpTo[80]] <> ")", "Text"], Module]];
        Return[Cell[BoxData[boxed], "Output"], Module],
      
      (* (c) ImagePath: \:30d5\:30a1\:30a4\:30eb\:304b\:3089\:753b\:50cf\:3092 Import *)
      kind === "ImagePath" || kind === "Image",
        path = Lookup[spec, "Path", Lookup[spec, "Content", ""]];
        If[!StringQ[path] || !FileExistsQ[path],
          Return[Cell["(Image path not found: " <> ToString[path] <> ")",
            "Text"], Module]];
        boxed = Quiet @ Check[ToBoxes[Import[path]], Null];
        If[boxed === Null,
          Return[Cell["(Image import failed: " <> path <> ")", "Text"],
            Module]];
        Return[Cell[BoxData[boxed], "Output"], Module],
      
      (* (d) Grid2Col: Left / Right \:3092 2\:5217 Grid \:306b\:5305\:3080 *)
      kind === "Grid2Col" || kind === "Grid",
        leftSpec  = Lookup[spec, "Left",  Lookup[spec, "Column1", ""]];
        rightSpec = Lookup[spec, "Right", Lookup[spec, "Column2", ""]];
        (* \:5404\:5074\:306f\:307e\:305f\:30b9\:30da\:30c3\:30af\:306b\:306a\:308a\:3046\:308b\:2014\:518d\:5e30\:7684\:306b\:5c55\:958b *)
        leftCell  = Which[
          AssociationQ[leftSpec],
            iInnerCellFromSpec[leftSpec],
          StringQ[leftSpec] && FileExistsQ[leftSpec],
            iInnerCellFromSpec[<|"Kind" -> "ImagePath",
              "Path" -> leftSpec|>],
          True,
            Cell[ToString[leftSpec], "Text"]];
        rightCell = Which[
          AssociationQ[rightSpec],
            iInnerCellFromSpec[rightSpec],
          StringQ[rightSpec] && FileExistsQ[rightSpec],
            iInnerCellFromSpec[<|"Kind" -> "ImagePath",
              "Path" -> rightSpec|>],
          True,
            Cell[ToString[rightSpec], "Text"]];
        (* \:4e21\:5074\:306e BoxData \:3092\:53d6\:308a\:51fa\:3057\:3066 GridBox \:306b *)
        leftBox  = If[MatchQ[leftCell,
                        Cell[_BoxData, ___]],
                      leftCell[[1, 1]],
                      ToBoxes[leftCell[[1]]]];
        rightBox = If[MatchQ[rightCell,
                        Cell[_BoxData, ___]],
                      rightCell[[1, 1]],
                      ToBoxes[rightCell[[1]]]];
        Return[
          Cell[BoxData[
            GridBox[{{leftBox, rightBox}},
              GridBoxAlignment -> {"Columns" -> {Center, Center},
                "Rows" -> {Center}},
              GridBoxSpacings -> {"Columns" -> {{1}}}]],
            "Output"],
          Module],
      
      (* Kind \:304c\:4e0d\:660e/\:672a\:6307\:5b9a\:306a\:3089\:5f93\:6765\:306e\:6311\:52d5\:3078 *)
      True, Null];
    
    (* ---- \:5f93\:6765\:306e Style + Content \:30d1\:30b9 ---- *)
    cnt = Lookup[spec, "Content",
           Lookup[spec, "Text",
            Lookup[spec, "Body", ""]]];
    rawSty = Lookup[spec, "Style", "Text"];
    If[!StringQ[cnt], cnt = ToString[cnt]];
    (* T07: Style \:306e sanitize \:3092\:5f37\:5236 *)
    sty = iSanitizeCellStyle[If[StringQ[rawSty], rawSty, ToString[rawSty]]];
    If[cnt === "",
      Cell[" ", sty],        (* \:7a7a\:30bb\:30eb\:3082\:8868\:73fe\:7528\:306b\:306f\:6255\:3046\:2014\:7a7a\:6587\:5b57\:5217\:3060\:3068 NotebookWrite \:304c\:8dfe\:3053 *)
      Cell[cnt, sty]]
  ];
iInnerCellFromSpec[s_] := Cell[ToString[s], "Text"];

iCellFromSlideItem[item_Association, isFirst_:False] :=
  Module[{cells = {}, title, subtitle, body, code, style, subs, sec,
          innerCells, page, bodyOutline, datasetValue, dsBoxes,
          datasetCode, preBuiltCells},
    title       = Lookup[item, "Title",
                   Lookup[item, "Heading", None]];
    subtitle    = Lookup[item, "Subtitle", None];
    body        = Lookup[item, "Body",
                   Lookup[item, "Content",
                    Lookup[item, "Text", None]]];
    code        = Lookup[item, "Code",
                   Lookup[item, "Input", None]];
    style       = Lookup[item, "Style", Automatic];
    subs        = Lookup[item, "Subsection", None];
    sec         = Lookup[item, "Section", None];
    innerCells  = Lookup[item, "Cells", None];
    page        = Lookup[item, "Page", None];
    bodyOutline = Lookup[item, "BodyOutline", None];
    (* T10: \:69cb\:9020\:5316\:30c7\:30fc\:30bf\:306e\:751f\:5024 (Case 3 fallback \:304b\:3089\:6765\:308b) *)
    datasetValue = Lookup[item, "DatasetValue", None];
    (* T11: \:30b7\:30ea\:30a2\:30e9\:30a4\:30ba\:3055\:308c\:305f Cell \:5f0f\:3092\:30d1\:30fc\:30b9\:3057\:305f\:5b9f Cell \:30ea\:30b9\:30c8 *)
    preBuiltCells = Lookup[item, "PreBuiltCells", None];
    
    (* ==== T11: PreBuiltCells \:2014 \:65e2\:306b Cell[...] \:30aa\:30d6\:30b8\:30a7\:30af\:30c8\:306b\:30d1\:30fc\:30b9\:6e08\:307f ==== *)
    If[ListQ[preBuiltCells] && Length[preBuiltCells] > 0 &&
       AllTrue[preBuiltCells, MatchQ[#, Cell[___]] &],
      If[StringQ[title] && title =!= "",
        AppendTo[cells, Cell[title, "Section"]]];
      cells = Join[cells, preBuiltCells];
      Return[cells, Module]];
    
    (* ==== T06: SlideDraft \:5f62\:5f0f\:2014 item \:304c\:5185\:90e8\:306b "Cells" \:30ea\:30b9\:30c8\:3092\:6301\:3064\:5834\:5408 ====
       \:3053\:306e\:30d1\:30bf\:30fc\:30f3\:304c\:6700\:3082\:8c4a\:304b\:3002 LLM \:306f\:5404\:30b9\:30e9\:30a4\:30c9\:306b\:3064\:3044\:3066
       <|"Cells" -> {<|"Style"->..., "Content"->...|>, ...}|> \:3092\:751f\:6210\:3057\:3066
       \:304a\:308a\:3001\:305d\:306e\:307e\:307e Cell[...] \:306b\:5c55\:958b\:3067\:304d\:308b\:3002 *)
    If[ListQ[innerCells] && Length[innerCells] > 0 &&
       AllTrue[innerCells, AssociationQ],
      (* Page-header \:3092\:5148\:982d\:306b\:5165\:308c\:3066 slide \:5883\:754c\:3092\:660e\:78ba\:5316 *)
      If[IntegerQ[page] || (StringQ[page] && page =!= ""),
        AppendTo[cells,
          Cell["\:2014 Page " <> ToString[page] <> " \:2014",
               "SubsubsectionInPresentation"]]];
      cells = Join[cells, iInnerCellFromSpec /@ innerCells];
      (* Page-level \:306e Title \:3082\:65e2\:306b inner Cells \:5185\:306b\:542b\:307e\:308c\:308b\:306e\:304c
         \:901a\:4f8b\:2014\:4e0d\:8981\:306a\:91cd\:8907\:3092\:5165\:308c\:306a\:3044\:3002 cells \:304c\:7a7a\:306a\:3089\:6700\:4f4e\:9650 title
         \:3060\:3051\:3067\:3082\:5165\:308c\:308b\:3002 *)
      If[Length[cells] === 0 && StringQ[title] && title =!= "",
        AppendTo[cells, Cell[title, "Section"]]];
      Return[cells, Module]];
    
    (* ==== T06: SlideOutline \:5f62\:5f0f\:2014 Title + Subtitle + BodyOutline ==== *)
    If[(StringQ[title] || StringQ[subtitle] || ListQ[bodyOutline]),
      If[StringQ[title] && title =!= "",
        AppendTo[cells,
          Cell[title,
            If[style === Automatic,
              If[TrueQ[isFirst], "Title", "Section"],
              (* T07: \:30a2\:30a6\:30c8\:30e9\:30a4\:30f3\:5f62\:5f0f\:3067\:3082 Style \:304c\:30d7\:30ed\:30fc\:30ba\:306a\:3089 sanitize *)
              iSanitizeCellStyle[ToString[style]]]]]];
      If[StringQ[subtitle] && subtitle =!= "",
        AppendTo[cells, Cell[subtitle, "Subtitle"]]];
      (* BodyOutline \:306f\:9805\:76ee\:304c\:6587\:5b57\:5217\:306e\:30ea\:30b9\:30c8\:2014\:5404\:9805\:3092 ItemParagraph \:3067 *)
      If[ListQ[bodyOutline],
        Do[
          If[StringQ[b] && b =!= "",
            AppendTo[cells, Cell[b, "ItemParagraph"]]],
          {b, bodyOutline}]];
      (* Body/Section/Subsection \:304c\:88dc\:52a9\:7684\:306b\:3042\:308c\:3070 *)
      If[StringQ[sec] && sec =!= "" && !StringQ[title],
        AppendTo[cells, Cell[sec, "Section"]]];
      If[StringQ[subs] && subs =!= "",
        AppendTo[cells, Cell[subs, "Subsection"]]];
      If[StringQ[body] && body =!= "",
        AppendTo[cells, Cell[body, "Text"]]];
      If[ListQ[body],
        Do[
          If[StringQ[b], AppendTo[cells, Cell[b, "Text"]]],
          {b, body}]];
      If[StringQ[code] && code =!= "",
        AppendTo[cells, Cell[code, "Input"]]];
      (* T10: \:3053\:306e\:30d6\:30e9\:30f3\:30c1\:3067\:3082 DatasetValue \:3092\:5c0a\:91cd\:3059\:308b (Case 3 fallback \:304b\:3089\:6765\:308b) *)
      If[datasetValue =!= None,
        Module[{boxed},
          boxed = Quiet @ Check[ToBoxes[Dataset[datasetValue]], Null];
          If[boxed =!= Null && boxed =!= $Failed,
            AppendTo[cells, Cell[BoxData[boxed], "Output"]]]]];
      If[Length[cells] > 0,
        Return[cells, Module]]];
    
    (* ==== \:5f93\:6765\:306e simple \:5f62\:5f0f (T05 \:4e92\:63db) ==== *)
    If[StringQ[title] && title =!= "",
      AppendTo[cells,
        Cell[title,
          If[style === Automatic,
            If[TrueQ[isFirst], "Title", "Section"],
            (* T07: \:5f93\:6765\:5f62\:5f0f\:3067\:3082 Style \:304c\:30d7\:30ed\:30fc\:30ba\:306a\:3089 sanitize *)
            iSanitizeCellStyle[ToString[style]]]]]];
    If[StringQ[sec] && sec =!= "" && !StringQ[title],
      AppendTo[cells, Cell[sec, "Section"]]];
    If[StringQ[subs] && subs =!= "",
      AppendTo[cells, Cell[subs, "Subsection"]]];
    If[StringQ[body] && body =!= "",
      AppendTo[cells, Cell[body, "Text"]]];
    If[ListQ[body] && !StringQ[title],
      Do[
        If[StringQ[b], AppendTo[cells, Cell[b, "Text"]]],
        {b, body}]];
    If[StringQ[code] && code =!= "",
      AppendTo[cells, Cell[code, "Input"]]];
    
    (* T10: DatasetValue \:304c\:3042\:308c\:3070 Dataset[] \:3067\:8a55\:4fa1\:6e08\:307f\:306e Output \:30bb\:30eb\:3092\:8ffd\:52a0\:3002
       ClaudeEval \:898f\:5247\:300c\:5b89\:5168\:306a\:5f0f\:306f\:81ea\:52d5\:5b9f\:884c\:300d\:3092\:53cd\:6620\:3057\:3001
       Dataset (\:7d14\:9006\:5bfe\:64cd\:4f5c\:306e\:306a\:3044\:5373\:6642\:5024) \:3092\:4e8b\:524d\:8a55\:4fa1\:3057\:3066\:6a19\:6e96\:306e
       In[]/Out[] \:5bfe\:3092\:751f\:6210\:3059\:308b\:3002\:8a55\:4fa1\:5931\:6557\:6642\:306f\:30b5\:30a4\:30ec\:30f3\:30c8\:306b\:898b\:9003\:3059 (cells \:306f\:65e2\:306b
       Title + Input \:3092\:542b\:3080\:305f\:3081\:3001Output \:304c\:51fa\:306a\:3044\:3060\:3051)\:3002 *)
    If[datasetValue =!= None,
      Module[{boxed},
        boxed = Quiet @ Check[ToBoxes[Dataset[datasetValue]], Null];
        If[boxed =!= Null && boxed =!= $Failed,
          AppendTo[cells, Cell[BoxData[boxed], "Output"]]]]];
    If[Length[cells] === 0,
      AppendTo[cells,
        Cell[ToString[item, InputForm], "Text"]]];
    cells
  ];

iCellFromSlideItem[other_, isFirst_:False] :=
  {Cell[ToString[other], "Text"]};

(* ---- iDeterministicSlideCommit: LLM \:3092\:4ecb\:3055\:305a\:6a5f\:68b0\:7684\:306b Cell \:3092\:66f8\:304f ----
   reducedArtifact \:304b\:3089 slide \:76f8\:5f53\:3092\:62bd\:51fa\:3001\:5404\:3005 NotebookWrite \:3092\:76f4\:63a5\:547c\:3076\:3002
   \:623b\:308a\:5024: <|"CellsWritten" -> N, "Status" -> "OK"|"NoSlides"|"NotANotebook"|
                        "Failed", "Error" -> ...|>
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iDeterministicSlideCommit];

iDeterministicSlideCommit[targetNb_, reducedArtifact_Association] :=
  Module[{payload, slides, cells, written = 0, writeResult},
    If[!MatchQ[targetNb, _NotebookObject],
      Return[<|"Status" -> "NotANotebook",
               "CellsWritten" -> 0,
               "Error" -> "targetNb is not a NotebookObject"|>]];
    
    payload = Lookup[reducedArtifact, "Payload", <||>];
    slides  = iExtractSlidesFromPayload[payload];
    
    If[!ListQ[slides] || Length[slides] === 0,
      Return[<|"Status" -> "NoSlides",
               "CellsWritten" -> 0|>]];
    
    cells = Flatten[MapIndexed[
      Function[{slide, idx},
        iCellFromSlideItem[slide, First[idx] === 1]],
      slides], 1];
    
    (* \:5404 Cell \:3092\:9806\:6b21 NotebookWrite \:2014 1 \:56de\:306b\:307e\:3068\:3081\:3066 list \:3067\:6e21\:3059\:3068\:9806\:5e8f\:5d29\:308c\:306e\:6f5c\:5728\:7684\:5371\:967a
       \:304c\:3042\:308b\:305f\:3081 1 \:500b\:305a\:3064\:3002 NotebookWrite \:81ea\:4f53\:306f $Failed \:3082\:3042\:308a\:5f97\:308b\:306e\:3067 Check \:3067\:5305\:3080\:3002 
       
       v2026-04-20 T18: \:66f8\:304d\:8fbc\:307f\:524d\:306b SelectionMove \:3067 notebook \:672b\:5c3e\:306b
       insertion point \:3092\:79fb\:3057\:3001\:65e2\:5b58\:30bb\:30eb\:30b0\:30eb\:30fc\:30d7\:306b\:5272\:308a\:8fbc\:307e\:306a\:3044\:3088\:3046\:306b\:3059\:308b\:3002*)
    Quiet @ Check[
      SelectionMove[targetNb, After, Notebook],
      Null];
    
    Do[
      writeResult = Quiet @ Check[
        NotebookWrite[targetNb, c], $Failed];
      If[writeResult =!= $Failed, written++],
      {c, cells}];
    
    <|"Status" -> If[written > 0, "OK", "Failed"],
      "CellsWritten" -> written,
      "TotalSlides"  -> Length[slides],
      "TotalCells"   -> Length[cells]|>
  ];

iDeterministicSlideCommit[___] :=
  <|"Status" -> "Failed", "CellsWritten" -> 0,
    "Error" -> "InvalidArguments"|>;

(* ---- iGenericPayloadCommit (v2026-04-20 T10): 汎用 payload \:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af ----
   reducedArtifact.Payload \:304c slide \:69cb\:9020\:3092\:6301\:305f\:306a\:3044\:5834\:5408 (\:4f8b: \:5358\:7d14\:8a08\:7b97\:7d50\:679c
   <|"Result" -> 20100|> \:306a\:3069) \:306b\:3001payload \:3092\:6c4e\:7528\:7684\:306b Cell \:5217\:306b
   \:5909\:63db\:3057\:3066 NotebookWrite \:3059\:308b\:3002
   
   \:5909\:63db\:898f\:5247:
   1. Source \:30bf\:30b9\:30af\:540d\:3092 Subsection \:30bb\:30eb\:3068\:3057\:3066 1 \:679a (\:3042\:308c\:3070)
   2. Payload \:304c Association \:306a\:3089\:3001\:5404 key \:3054\:3068\:306b:
      - "Result"/"Answer"/"Value"/"Output" -> Code \:30bb\:30eb (key + " = " + value)
      - "Summary"/"Explanation"/"Description"/"Note" -> Text \:30bb\:30eb
      - "Code"/"Source" -> Input \:30bb\:30eb
      - \:305d\:306e\:4ed6 -> Text \:30bb\:30eb (key: value InputForm)
   3. Payload \:304c String \:306a\:3089 Text \:30bb\:30eb 1 \:679a
   4. \:305d\:306e\:4ed6 (List \:7b49) \:306f InputForm \:5168\:4f53\:3092 Text \:30bb\:30eb 1 \:679a
   
   \:623b\:308a\:5024: <|"Status" -> "OK"|"NoPayload"|"NotANotebook"|"Failed",
                  "CellsWritten" -> N|>
   
   T10 \:6ce8\:8a18: \:540c\:671f\:7248 iCommitArtifactsOnce \:306f iDeterministicSlideCommit \:306e\:307f
     fallback \:3068\:3057\:3066\:6301\:3064\:304c\:3001non-slide payload \:3067\:306f cells=0 \:306e\:307e\:307e\:7d42\:308f\:308b\:3002
     T10 \:3067\:306f\:518d\:5e30\:7684\:306b iDeterministicSlideCommit (slide \:9069\:5408)
     \:2192 iGenericPayloadCommit (\:6c4e\:7528) \:306e 2 \:6bb5\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:306b\:3059\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iGenericPayloadCommit, iCellFromPayloadEntry,
  iCellsFromGenericPayload];

(* \:5358\:4e00 (key, value) \:30a8\:30f3\:30c8\:30ea\:3092 Cell list \:306b\:3059\:308b\:30d8\:30eb\:30d1\:30fc *)
iCellFromPayloadEntry[key_String, value_] :=
  Module[{kLow, valStr},
    kLow = ToLowerCase[key];
    Which[
      MemberQ[{"result", "answer", "value", "output", "ans"}, kLow],
        valStr = ToString[value, InputForm];
        {Cell[key <> " = " <> valStr, "Code"]},
      
      MemberQ[{"summary", "explanation", "description",
               "note", "notes", "comment", "comments"}, kLow],
        {Cell[ToString[value], "Text"]},
      
      MemberQ[{"code", "source", "snippet", "expression"}, kLow],
        {Cell[ToString[value], "Input"]},
      
      MemberQ[{"title", "heading"}, kLow],
        {Cell[ToString[value], "Subsection"]},
      
      True,
        valStr = ToString[value, InputForm];
        (* \:9577\:3059\:304e\:308b\:5024\:306f\:5207\:308a\:8a70\:3081 *)
        If[StringLength[valStr] > 2000,
          valStr = StringTake[valStr, 2000] <> " ... (truncated)"];
        {Cell[key <> ": " <> valStr, "Text"]}
    ]
  ];

iCellFromPayloadEntry[___] := {};

(* Payload \:5168\:4f53\:3092 Cell list \:306b *)
iCellsFromGenericPayload[payload_Association] :=
  Module[{cells = {}, payloadKeys},
    payloadKeys = Keys[payload];
    Do[
      cells = Join[cells,
        iCellFromPayloadEntry[ToString[k], payload[k]]],
      {k, payloadKeys}];
    cells
  ];

iCellsFromGenericPayload[s_String] :=
  {Cell[s, "Text"]};

iCellsFromGenericPayload[lst_List] :=
  {Cell[ToString[lst, InputForm], "Text"]};

iCellsFromGenericPayload[other_] :=
  {Cell[ToString[other, InputForm], "Text"]};

iGenericPayloadCommit[targetNb_, reducedArtifact_Association] :=
  Module[{payload, sources, cells, written = 0, writeResult,
          headerCells = {}},
    If[!MatchQ[targetNb, _NotebookObject],
      Return[<|"Status"       -> "NotANotebook",
               "CellsWritten" -> 0,
               "Error"        -> "targetNb is not a NotebookObject"|>]];
    
    payload = Lookup[reducedArtifact, "Payload", <||>];
    sources = Lookup[reducedArtifact, "Sources", {}];
    
    (* Source \:30bf\:30b9\:30af\:540d\:304c\:3042\:308c\:3070 Subsection \:30d8\:30c3\:30c0 *)
    If[ListQ[sources] && Length[sources] > 0,
      headerCells = {Cell["Result (sources: " <>
        StringRiffle[ToString /@ sources, ", "] <> ")",
        "Subsection"]}];
    
    (* Payload \:3092 Cell list \:306b\:5909\:63db *)
    cells = Quiet @ Check[
      iCellsFromGenericPayload[payload], {}];
    If[!ListQ[cells], cells = {}];
    
    cells = Join[headerCells, cells];
    
    If[Length[cells] === 0,
      Return[<|"Status"       -> "NoPayload",
               "CellsWritten" -> 0|>]];
    
    (* \:9806\:6b21 NotebookWrite \:2014 1 \:500b\:305a\:3064 (iDeterministicSlideCommit \:3068\:540c\:69d8)
       v2026-04-20 T18: \:66f8\:304d\:8fbc\:307f\:524d\:306b SelectionMove \:3067 notebook \:672b\:5c3e\:306b\:79fb\:52d5\:3002 *)
    Quiet @ Check[
      SelectionMove[targetNb, After, Notebook],
      Null];
    
    Do[
      writeResult = Quiet @ Check[
        NotebookWrite[targetNb, c], $Failed];
      If[writeResult =!= $Failed, written++],
      {c, cells}];
    
    <|"Status"        -> If[written > 0, "OK", "Failed"],
      "CellsWritten"  -> written,
      "TotalCells"    -> Length[cells],
      "Mode"          -> "Generic"|>
  ];

iGenericPayloadCommit[___] :=
  <|"Status" -> "Failed", "CellsWritten" -> 0,
    "Error" -> "InvalidArguments"|>;

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iAttemptCommitFallback (v2026-04-20 T10):
   \:30c7\:30d5\:30a9\:30eb\:30c8 fallback \:30c1\:30a7\:30fc\:30f3\:3002 iDeterministicSlideCommit \:2192
   iGenericPayloadCommit \:306e\:9806\:3067\:8a66\:3057\:3001\:6700\:521d\:306b cellsWritten > 0 \:3092
   \:8fbe\:6210\:3057\:305f\:6642\:70b9\:3067 return \:3059\:308b\:3002
   
   \:8fd4\:308a\:5024: <|
     "Used"          -> "Slide"|"Generic"|"None",
     "CellsWritten"  -> N,
     "Status"        -> "OK"|"NoFallback"|"Failed",
     "SlideResult"   -> ... (\:8a66\:884c\:6e08\:307f\:306e\:307f),
     "GenericResult" -> ... (\:8a66\:884c\:6e08\:307f\:306e\:307f)
   |>
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

ClearAll[iAttemptCommitFallback];

iAttemptCommitFallback[targetNb_, reducedArtifact_Association] :=
  Module[{slideRes, genericRes, slideWritten = 0, genericWritten = 0},
    If[!MatchQ[targetNb, _NotebookObject],
      Return[<|"Used"         -> "None",
               "CellsWritten" -> 0,
               "Status"       -> "NoFallback",
               "Reason"       -> "NotANotebook"|>]];
    
    (* (i) iDeterministicSlideCommit (slide \:69cb\:9020\:3042\:308a\:7528) *)
    slideRes = Quiet @ Check[
      iDeterministicSlideCommit[targetNb, reducedArtifact],
      <|"Status" -> "Failed", "CellsWritten" -> 0,
        "Error" -> "iDeterministicSlideCommitThrew"|>];
    If[!AssociationQ[slideRes],
      slideRes = <|"Status" -> "Failed", "CellsWritten" -> 0|>];
    slideWritten = Lookup[slideRes, "CellsWritten", 0];
    If[!IntegerQ[slideWritten], slideWritten = 0];
    
    If[slideWritten > 0,
      Return[<|"Used"         -> "Slide",
               "CellsWritten" -> slideWritten,
               "Status"       -> "OK",
               "SlideResult"  -> slideRes|>]];
    
    (* (ii) iGenericPayloadCommit (\:6c4e\:7528) *)
    genericRes = Quiet @ Check[
      iGenericPayloadCommit[targetNb, reducedArtifact],
      <|"Status" -> "Failed", "CellsWritten" -> 0,
        "Error" -> "iGenericPayloadCommitThrew"|>];
    If[!AssociationQ[genericRes],
      genericRes = <|"Status" -> "Failed", "CellsWritten" -> 0|>];
    genericWritten = Lookup[genericRes, "CellsWritten", 0];
    If[!IntegerQ[genericWritten], genericWritten = 0];
    
    If[genericWritten > 0,
      Return[<|"Used"         -> "Generic",
               "CellsWritten" -> genericWritten,
               "Status"       -> "OK",
               "SlideResult"   -> slideRes,
               "GenericResult" -> genericRes|>]];
    
    (* \:3069\:3061\:3089\:3082\:30bb\:30eb\:3092\:66f8\:304b\:306a\:304b\:3063\:305f *)
    <|"Used"          -> "None",
      "CellsWritten"  -> 0,
      "Status"        -> "NoFallback",
      "SlideResult"   -> slideRes,
      "GenericResult" -> genericRes|>
  ];

iAttemptCommitFallback[___] :=
  <|"Used" -> "None", "CellsWritten" -> 0,
    "Status" -> "Failed", "Error" -> "InvalidArguments"|>;

(* ────────────────────────────────────────────────────────────
   iAttemptDirectLLMCodeRescue (T14, 2026-04-20):
   
   parseFn 経路 (T12) や fallback (T10/T11) とは独立した第3の救済層。
   commit phase の最後で LastProviderResponse を直接見て、
   multi-line code block ([\s\S]*? regex) を抽出し、ToExpression で
   HoldComplete 化、iRewriteCommitterHeldExpr で EvaluationNotebook[]
   を targetNb に書き換えた上で、ReleaseHold で実行する。
   
   parseFn が adapter に組み込まれていないとか runtime が呼んでくれない
   とかいう経路上のトラブルを完全にバイパスして、commit phase 内で
   LLM が書いた NotebookWrite 命令を直接走らせる。
   
   引数:
     targetNb           - 書き込み先 notebook (NotebookObject)
     lastProviderResp   - runtime 内の LastProviderResponse
                          (String | Association | None)
   
   戻り値: <|
     "Used"           -> "DirectLLM" | "None",
     "Status"         -> "OK" | "NoCodeBlock" | "ParseFailed" | "ExecFailed",
     "CellsWritten"   -> N (NotebookWrite 出現数を self-report),
     "RawCode"        -> 抽出 code (debug),
     "ParseMode"      -> "DirectLLMRescue" | None
   |>
   ──────────────────────────────────────────────────────────── *)

ClearAll[iAttemptDirectLLMCodeRescue];

iAttemptDirectLLMCodeRescue[targetNb_, lastProviderResp_] :=
  Module[{rawStr, codeBlocks, codeBlocks2, code, heldExpr, rewritten,
          execResult, nbwCount, nbwCountInHeld, diagExtra},
    
    diagExtra = <||>;
    
    If[!MatchQ[targetNb, _NotebookObject],
      Return[<|"Used" -> "None", "Status" -> "NoNotebook",
               "CellsWritten" -> 0|>]];
    
    (* 1. raw を文字列化 *)
    rawStr = Which[
      StringQ[lastProviderResp], lastProviderResp,
      AssociationQ[lastProviderResp],
        Module[{r = Lookup[lastProviderResp, "response",
                  ToString[lastProviderResp]]},
          If[StringQ[r], r, ToString[lastProviderResp]]],
      lastProviderResp === None || lastProviderResp === Null,
        Return[<|"Used" -> "None", "Status" -> "NoResponse",
                 "CellsWritten" -> 0|>],
      True, ToString[lastProviderResp]];
    
    diagExtra["RawStrLength"] = StringLength[rawStr];
    diagExtra["RawStrHead"]   = StringTake[rawStr, UpTo[120]];
    diagExtra["RawStrTail"]   = StringTake[rawStr, {-Min[120, StringLength[rawStr]], -1}];
    diagExtra["TripleTickCount"] = StringCount[rawStr, "```"];
    
    (* 2. multi-line regex で抽出 ([\s\S]*? は (?s) フラグ非依存) *)
    codeBlocks = Quiet @ Check[
      StringCases[rawStr,
        RegularExpression[
          "```(?:mathematica|Mathematica|wl|wolfram|mma)\\s*\\n([\\s\\S]*?)\\n\\s*```"
        ] :> "$1"],
      {}];
    diagExtra["CodeBlocksFoundTagged"] = Length[codeBlocks];
    
    (* Fallback: 言語タグなし *)
    If[Length[codeBlocks] === 0,
      codeBlocks2 = Quiet @ Check[
        StringCases[rawStr,
          RegularExpression["```\\s*\\n([\\s\\S]*?)\\n\\s*```"] :> "$1"],
        {}];
      diagExtra["CodeBlocksFoundBare"] = Length[codeBlocks2];
      codeBlocks = codeBlocks2];
    
    If[Length[codeBlocks] === 0,
      Return[<|"Used" -> "None", "Status" -> "NoCodeBlock",
               "CellsWritten" -> 0,
               "Diag" -> diagExtra|>]];
    
    code = StringTrim[First[codeBlocks]];
    diagExtra["CodeLength"] = StringLength[code];
    diagExtra["CodeHead"]   = StringTake[code, UpTo[200]];
    
    (* 3. ToExpression で HoldComplete 化
       
       v2026-04-20 T16: code が ";" 区切りの複数 statement の場合、
       ToExpression[code, InputForm, HoldComplete] は
       HoldComplete[e1, e2, ...] (複数引数形) を返す。
       これは MatchQ[_, HoldComplete[_]] に False(Blank は 1 引数のみ)。
       CompoundExpression にラップして 1 引数形に正規化する。 *)
    heldExpr = Quiet @ Check[
      ToExpression[code, InputForm, HoldComplete],
      None];
    
    (* T16: 複数引数 HoldComplete を CompoundExpression で括る。
       HoldComplete は HoldAllComplete なので、Replace RHS で
       args__ を直接 CompoundExpression に渡すと Sequence として展開され
       CompoundExpression が評価を始めて副作用が出る恐れがある。
       HoldPattern[HoldComplete[args__]] で受け、RHS でも
       HoldComplete[CompoundExpression[args]] を With でリフト直すことで
       副作用を避ける。実際には HoldComplete が HoldAll 属性なので
       args は Sequence として展開されるが、HoldComplete の中に
       入っているので内部式としてそのまま保持される。 *)
    heldExpr = Which[
      MatchQ[heldExpr, HoldComplete[_]],         heldExpr,
      MatchQ[heldExpr, HoldComplete[__]],
        Replace[heldExpr,
          HoldPattern[HoldComplete[args__]] :>
            HoldComplete[CompoundExpression[args]]],
      True, heldExpr];
    
    diagExtra["HeldExprHead"] = Head[heldExpr];
    diagExtra["HeldExprMatchesHoldComplete"] =
      MatchQ[heldExpr, HoldComplete[_]];
    diagExtra["HeldExprBodyHead"] =
      If[MatchQ[heldExpr, HoldComplete[_]],
        Head[heldExpr[[1]]], None];
    nbwCountInHeld = Quiet @ Check[
      Length[Cases[heldExpr,
        HoldPattern[NotebookWrite][___], Infinity,
        Heads -> False]], 0];
    diagExtra["NbwCountInHeldExpr"] = nbwCountInHeld;
    
    If[!MatchQ[heldExpr, HoldComplete[_]] ||
       heldExpr === HoldComplete[Null] ||
       heldExpr === HoldComplete[],
      Return[<|"Used" -> "DirectLLM", "Status" -> "ParseFailed",
               "CellsWritten" -> 0,
               "RawCode" -> StringTake[code, UpTo[200]],
               "Diag" -> diagExtra|>]];
    
    (* 4. EvaluationNotebook[] -> targetNb 書き換え (Stage 3 同等) *)
    rewritten = Quiet @ Check[
      iRewriteCommitterHeldExpr[heldExpr, targetNb],
      heldExpr];
    If[!MatchQ[rewritten, HoldComplete[_]],
      rewritten = heldExpr];
    
    diagExtra["RewrittenHead"] = Head[rewritten];
    diagExtra["RewrittenMatchesHoldComplete"] =
      MatchQ[rewritten, HoldComplete[_]];
    
    (* 5. NotebookWrite[__] の出現数を数えて self-report *)
    nbwCount = Quiet @ Check[
      Length[Cases[rewritten,
        HoldPattern[NotebookWrite][___], Infinity,
        Heads -> False]], 0];
    diagExtra["NbwCountInRewritten"] = nbwCount;
    
    (* 6. ReleaseHold で実行
       
       v2026-04-20 T18: ReleaseHold 直前に SelectionMove で Notebook 末尾に
       insertion point を移す。
       
       背景 (test20 で観察された症状):
         ClaudeEval を評価した Input セルの Output 位置に NotebookWrite が
         作用し、既存 Output セルと視覚的に融合する形で描画されていた
         (Section / Text / Output の 3 セルが Input セルのグループに
         押し込まれ、「1から200の和公式 : ...20100」のように連結して
         見える)。
       
       SelectionMove[nb, After, Notebook] は Notebook の一番末尾に
       insertion point を移し、以降の NotebookWrite はそこへ追加される。
       既存のセルグループに割り込まないので、LLM 出力は独立した新規
       セルとして末尾に並ぶ。
       
       NotebookWrite[nb, Cell[...]] は nb の current insertion point を
       使うので、SelectionMove で移せば追記先が制御できる。*)
    If[MatchQ[targetNb, _NotebookObject],
      Quiet @ Check[
        SelectionMove[targetNb, After, Notebook],
        Null]];
    
    execResult = Quiet @ Check[
      ReleaseHold[rewritten],
      $Failed];
    
    diagExtra["ExecSucceeded"] = (execResult =!= $Failed);
    diagExtra["SelectionMoveApplied"] = True;   (* T18 *)
    
    If[execResult === $Failed,
      Return[<|"Used" -> "DirectLLM", "Status" -> "ExecFailed",
               "CellsWritten" -> 0,
               "RawCode" -> StringTake[code, UpTo[200]],
               "Diag" -> diagExtra|>]];
    
    <|"Used"          -> "DirectLLM",
      "Status"        -> If[nbwCount > 0, "OK", "ExecutedButNoNbw"],
      "CellsWritten"  -> nbwCount,
      "RawCode"       -> StringTake[code, UpTo[200]],
      "ParseMode"     -> "DirectLLMRescue",
      "Diag"          -> diagExtra|>
  ];

iAttemptDirectLLMCodeRescue[___] :=
  <|"Used" -> "None", "Status" -> "Failed",
    "CellsWritten" -> 0, "Error" -> "InvalidArguments"|>;

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iDefaultCommitterAdapterBuilder (Stage 3 \:5b8c\:5168\:7248):
   
   \:65e2\:5b58 ClaudeCode`ClaudeBuildRuntimeAdapter \:3092\:30e9\:30c3\:30d7\:3057\:3001
   \:4ee5\:4e0b\:3092 commit \:7528\:306b\:5dee\:3057\:66ff\:3048\:305f adapter \:3092\:8fd4\:3059:
     - BuildContext: Role=Commit / TargetNotebook / ReducedArtifact /
                     CommitPolicy / AllowedCapabilities \:3092\:6ce8\:5165
     - ValidateProposal: iValidateWorkerProposal[..., "Commit"]
                         (CreateNotebook \:306f Deny\:3001spec \:00a710.3 \:5fe0\:5b9f)
     - ExecuteProposal: HeldExpr \:3092 iRewriteCommitterHeldExpr \:3067\:66f8\:63db\:5f8c\:306b
                        base \:306e ExecuteProposal \:306b\:59d4\:8b72 (\:4fdd\:967a\:5c64)
   
   \:4ed6\:306e\:30ad\:30fc (QueryProvider / ParseProposal / RedactResult /
   ShouldContinue / AvailableTools / ExecuteTools / SyncProvider) \:306f base \:7d99\:627f\:3002
   
   \:30aa\:30d7\:30b7\:30e7\:30f3:
     "AccessLevel"      -> 0.3 (default)
     "BaseAdapter"      -> Automatic (\:30c6\:30b9\:30c8\:6642\:306f mock adapter \:3092\:6ce8\:5165\:53ef\:80fd)
     "MaxContinuations" -> 2
   
   \:30c6\:30b9\:30c6\:30fc\:30bf\:30d3\:30ea\:30c6\:30a3: "BaseAdapter" \:306b mock Association \:3092\:6e21\:3059\:3053\:3068\:3067
     ClaudeCode`ClaudeBuildRuntimeAdapter \:547c\:3073\:51fa\:3057\:3092\:3057\:306a\:3044 pure \:306a unit test
     \:304c\:53ef\:80fd\:306b\:306a\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

(* v2026-04-20 T13: ClearAll \:3092\:8ffd\:52a0\:3057\:3001\:540c\:4e00 kernel \:3067 ClaudeOrchestrator
   \:3092\:518d\:30ed\:30fc\:30c9\:3057\:305f\:969b\:306b\:53e4\:3044 DownValues / Options \:304c\:6b8b\:3089\:306a\:3044\:3088\:3046\:306b\:3059\:308b\:3002
   T12 \:306e parseFn \:304c\:5165\:3063\:305f adapter \:3092\:78ba\:5b9f\:306b\:5165\:308c\:66ff\:3048\:308b\:305f\:3081\:3002 *)
ClearAll[iDefaultCommitterAdapterBuilder];

Options[iDefaultCommitterAdapterBuilder] = {
  "AccessLevel"      -> 0.3,
  "BaseAdapter"      -> Automatic,
  "MaxContinuations" -> 2,
  "Model"            -> Automatic   (* v2026-04-20 T08: ClaudeBuildRuntimeAdapter \:306b\:4f1d\:64ad *)
};

iDefaultCommitterAdapterBuilder[targetNb_, reducedArtifact_Association,
    opts:OptionsPattern[]] :=
  Module[{baseAdapter, accessLevel, maxCont, buildCtx, validateFn,
          executeFn, parseFn, baseParseFn, model},   (* T12 *)
    accessLevel = OptionValue["AccessLevel"];
    maxCont     = OptionValue["MaxContinuations"];
    baseAdapter = OptionValue["BaseAdapter"];
    model       = OptionValue["Model"];   (* v2026-04-20 T08 *)
    
    (* base adapter: Automatic \:306a\:3089 ClaudeCode`ClaudeBuildRuntimeAdapter \:547c\:51fa
       (\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:30bb\:30c3\:30b7\:30e7\:30f3\:3067\:3057\:304b\:9014\:5168\:3057\:306a\:3044 \[LongDash] \:30c6\:30b9\:30c8\:3067\:306f mock \:3092\:6e21\:3059)
       v2026-04-20 T08: Model \:6307\:5b9a\:304c\:3042\:308c\:3070 ClaudeBuildRuntimeAdapter \:306b\:6e21\:3057\:3066
         Claude CLI \:4ee5\:5916\:306e LLM (LM Studio \:7b49) \:3092\:4f7f\:7528\:53ef\:80fd\:306b\:3059\:308b\:3002 *)
    If[baseAdapter === Automatic,
      baseAdapter = Quiet @ Check[
        ClaudeCode`ClaudeBuildRuntimeAdapter[targetNb,
          "AccessLevel"      -> accessLevel,
          "MaxContinuations" -> maxCont,
          "Model"            -> model],
        $Failed]];
    
    If[!AssociationQ[baseAdapter],
      Return[<|
        "Error"        -> "BaseAdapterUnavailable",
        "SyncProvider" -> True|>]];
    
    (* \:2500\:2500 BuildContext: committer \:7528 context \:3092\:6ce8\:5165 \:2500\:2500
       T05: input \:306b Hint / OriginalTask \:3092\:3055\:3057\:8fbc\:307f\:3001
            iAdapterBuildPrompt \:306e TASK OVERVIEW \:3068 task detail \:4e21\:65b9\:306b
            commit \:6307\:793a\:3092\:5c4a\:304b\:305b\:308b\:3002 *)
    buildCtx = Function[{input, convState},
      Module[{basePacket, commitHint, effectiveInput,
              overviewStr},
        basePacket = Quiet @ Check[
          baseAdapter["BuildContext"][input, convState], <||>];
        If[!AssociationQ[basePacket], basePacket = <||>];
        
        (* T05: commit \:5c02\:7528\:30d7\:30ed\:30f3\:30d7\:30c8\:3092\:7d44\:307f\:7acb\:3066\:3001input \:306b\:307e\:3076\:3059 *)
        commitHint = Quiet @ Check[
          iBuildCommitterHint[reducedArtifact, targetNb],
          ""];
        If[!StringQ[commitHint], commitHint = ""];
        overviewStr = "COMMIT ROLE: write ReducedArtifact via " <>
          "NotebookWrite[EvaluationNotebook[], Cell[...]]. " <>
          "Sources: " <>
          ToString[Lookup[reducedArtifact, "Sources", {}]];
        effectiveInput = Which[
          AssociationQ[input],
            Join[input, <|
              "OriginalTask" -> overviewStr,
              "Hint"         -> commitHint|>],
          True,
            <|"OriginalTask" -> overviewStr,
              "Hint"         -> commitHint,
              "_OriginalInput" -> input|>];
        basePacket["Input"] = effectiveInput;
        
        basePacket["Role"]                = "Commit";
        basePacket["TargetNotebook"]      = targetNb;
        basePacket["ReducedArtifact"]     = reducedArtifact;
        basePacket["AllowedCapabilities"] = {"ReadArtifacts",
          "StructuredOutput", "NotebookWrite"};
        basePacket["CommitPolicy"]        = <|
          "DenyCreateNotebook"        -> True,
          "RewriteEvaluationNotebook" -> True,
          "BindNb"                    -> True|>;
        basePacket
      ]
    ];
    
    (* \:2500\:2500 ValidateProposal: worker validator \:306e Commit role \:5206\:5c90\:3092\:5229\:7528 \:2500\:2500
       (CreateNotebook \:306f $ClaudeOrchestratorDenyHeads \:306b\:542b\:307e\:308c\:3001
        $iCommitterAllowedHeads \:306b\:306f\:306a\:3044\:306e\:3067 Commit role \:3067\:3082 Deny) *)
    validateFn = Function[{proposal, contextPacket},
      iValidateWorkerProposal[proposal, contextPacket, "Commit"]
    ];
    
    (* \:2500\:2500 ExecuteProposal: HeldExpr \:3092 rewrite \:3057\:3066\:304b\:3089 base \:306b\:59d4\:8b72 \:2500\:2500 *)
    executeFn = Function[{proposal, validationResult},
      Module[{held, rewritten, newProposal},
        held = Lookup[proposal, "HeldExpr", None];
        If[MatchQ[held, HoldComplete[_]],
          rewritten = iRewriteCommitterHeldExpr[held, targetNb];
          newProposal = proposal;
          newProposal["HeldExpr"]         = rewritten;
          newProposal["Rewritten"]        = True;
          newProposal["OriginalHeldExpr"] = held;
          baseAdapter["ExecuteProposal"][newProposal, validationResult],
          (* non-HoldComplete: \:305d\:306e\:307e\:307e base \:3078 (text-only \:5fdc\:7b54\:5bfe\:5fdc) *)
          baseAdapter["ExecuteProposal"][proposal, validationResult]
        ]
      ]
    ];
    
    (* \:2500\:2500 ParseProposal: base \:306e ParseProposal \:3092\:30e9\:30c3\:30d7\:3057\:3001
       dotall \:76f8\:5f53 ([\\s\\S]*?) \:306e regex \:3067 multi-line code block \:3092\:518d\:62bd\:51fa\:2500\:2500
       
       v2026-04-20 T12 (fallback-race-fix \:306e\:6b21):
       
       \:540c\:671f\:7248\:306e ClaudeBuildRuntimeAdapter (claudecode.wl) \:306e ParseProposal \:306f
       regex "(?:mathematica|...)\\s*\\n(.*?)\\n\\s*```" \:3092\:4f7f\:3046\:304c\:3001 PCRE \:3067
       \:3059\:3067\:306b dotall flag \:306a\:3057\:306e `.*?` \:306f `\\n` \:3092\:8de8\:3052\:306a\:3044\:305f\:3081\:3001
       multi-line \:306a NotebookWrite \:306e\:7f85\:5217 (2 \:884c\:4ee5\:4e0a) \:3092\:629c\:304d\:6f0f\:3059\:3002
       test14b \:3067\:3001Claude Opus \:306e\:8fd4\:3057\:305f\:5b8c\:74a7\:306a code block \:304c
       HeldExpr\:301cFound=False \:306b\:306a\:3063\:305f\:771f\:56e0\:3002
       
       Rule 11 \:3092\:5b88\:308b\:305f\:3081\:3001claudecode.wl \:306f\:7121\:5909\:66f4\:3002
       \:4ee3\:308f\:308a\:3001 Committer adapter \:304c base \:306e ParseProposal \:3092\:30e9\:30c3\:30d7\:3057\:3001
       base \:304c HasProposal=False \:3092\:8fd4\:3057\:3001 \:304b\:3064 rawResponse \:306b ``` \:30d6\:30ed\:30c3\:30af\:304c
       \:898b\:3064\:304b\:308b\:5834\:5408\:3001 [\\s\\S]*? \:3067 multi-line \:5bfe\:5fdc\:306b\:518d\:62bd\:51fa\:3059\:308b\:3002
       
       [\\s\\S]*? \:306f (?s) \:30d5\:30e9\:30b0\:306b\:4f9d\:5b58\:3057\:306a\:3044\:305f\:3081\:3001 Wolfram \:306e
       RegularExpression \:5b9f\:88c5\:306b\:4f9d\:3089\:305a \:78ba\:5b9f\:306b\:6a5f\:80fd\:3059\:308b\:3002 *)
    baseParseFn = Lookup[baseAdapter, "ParseProposal",
                         Function[{raw},
                           <|"HeldExpr"     -> None,
                             "TextResponse" -> "",
                             "HasProposal"  -> False|>]];
    parseFn = Function[{raw},
      Module[{baseResult, rawStr, codeBlocks, code, heldExpr,
              enhanced = False, retval},
        baseResult = Quiet @ Check[baseParseFn[raw],
          <|"HeldExpr"     -> None,
            "TextResponse" -> "",
            "HasProposal"  -> False|>];
        If[!AssociationQ[baseResult],
          baseResult = <|"HeldExpr"     -> None,
                          "TextResponse" -> "",
                          "HasProposal"  -> False|>];
        
        (* base \:304c\:6b63\:5e38\:306b HeldExpr \:3092\:5f97\:305f\:306a\:3089\:3053\:308c\:3092\:305d\:306e\:307e\:307e\:4f7f\:3046 *)
        If[TrueQ[Lookup[baseResult, "HasProposal", False]] &&
           MatchQ[Lookup[baseResult, "HeldExpr", None], HoldComplete[_]],
          retval = baseResult,
          
          (* \:305d\:3046\:3067\:306a\:3051\:308c\:3070 raw \:3092\:6587\:5b57\:5217\:5316\:3057\:3066 multi-line regex \:3067\:518d\:62bd\:51fa *)
          rawStr = Which[
            StringQ[raw],     raw,
            AssociationQ[raw], Module[{r = Lookup[raw, "response",
                                         ToString[raw]]},
              If[StringQ[r], r, ToString[raw]]],
            True,             ToString[raw]];
          
          codeBlocks = Quiet @ Check[
            StringCases[rawStr,
              RegularExpression[
                "```(?:mathematica|Mathematica|wl|wolfram|mma)\\s*\\n([\\s\\S]*?)\\n\\s*```"
              ] :> "$1"],
            {}];
          
          (* \:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af: \:8a00\:8a9e\:30bf\:30b0\:306a\:3057 ``` \:30d6\:30ed\:30c3\:30af\:3082\:8a66\:3059
             (LLM \:304c ```\\n \:3067\:59cb\:3081\:308b\:30b1\:30fc\:30b9\:3042\:308a) *)
          If[Length[codeBlocks] === 0,
            codeBlocks = Quiet @ Check[
              StringCases[rawStr,
                RegularExpression[
                  "```\\s*\\n([\\s\\S]*?)\\n\\s*```"
                ] :> "$1"],
              {}]];
          
          If[Length[codeBlocks] > 0,
            code = StringTrim[First[codeBlocks]];
            heldExpr = Quiet @ Check[
              ToExpression[code, InputForm, HoldComplete],
              None];
            If[MatchQ[heldExpr, HoldComplete[_]] &&
               heldExpr =!= HoldComplete[Null] &&
               heldExpr =!= HoldComplete[],
              (* \:6210\:529f: base \:306e\:7d50\:679c\:306b\:8ffd\:8a18/\:4e0a\:66f8\:304d *)
              retval = baseResult;
              retval["HeldExpr"]     = heldExpr;
              retval["HasProposal"]  = True;
              retval["TextResponse"] = rawStr;
              retval["RawCode"]      = code;
              retval["ParseMode"]    = "CommitterMultilineFallback";
              enhanced = True,
              retval = baseResult],
            retval = baseResult]];
        
        (* \:8a3a\:65ad\:7528\:30d5\:30e9\:30b0\:3092\:4ed8\:52a0 (T12 \:3067 enhance \:3057\:305f\:304b\:3069\:3046\:304b) *)
        If[AssociationQ[retval] && enhanced,
          retval["ParseEnhanced"] = True];
        retval
      ]
    ];
    
    (* \:2500\:2500 \:4ed6\:30ad\:30fc\:306f base \:304b\:3089\:7d99\:627f (iValidateAdapter \:5fc5\:9808\:30ad\:30fc 7 \:3064) \:2500\:2500 *)
    <|
      "SyncProvider"     -> Lookup[baseAdapter, "SyncProvider", True],
      "BuildContext"     -> buildCtx,
      "QueryProvider"    -> Lookup[baseAdapter, "QueryProvider",
                                   Function[{ctx, cs}, <|"response" -> ""|>]],
      "ParseProposal"    -> parseFn,   (* v2026-04-20 T12: multiline fallback *)
      "ValidateProposal" -> validateFn,
      "ExecuteProposal"  -> executeFn,
      "RedactResult"     -> Lookup[baseAdapter, "RedactResult",
                                   Function[{res, ctx},
                                     <|"RedactedResult" ->
                                         Lookup[res, "RawResult", None]|>]],
      "ShouldContinue"   -> Lookup[baseAdapter, "ShouldContinue",
                                   Function[{_, _, _}, False]],
      "AvailableTools"   -> Lookup[baseAdapter, "AvailableTools",
                                   Function[{}, {}]],
      "ExecuteTools"     -> Lookup[baseAdapter, "ExecuteTools",
                                   Function[{calls, ctx}, {}]],
      "Role"             -> "Commit",
      "TargetNotebook"   -> targetNb,
      "ReducedArtifact"  -> reducedArtifact
    |>
  ];

(* ════════════════════════════════════════════════════════
   10. ClaudeRunOrchestration (spec §17.6)
   ════════════════════════════════════════════════════════ *)

Options[ClaudeRunOrchestration] = {
  "TargetNotebook"           -> Automatic,   (* v2026-04-20 T04: None -> Automatic *)
  "Planner"                  -> Automatic,
  "WorkerAdapterBuilder"     -> Automatic,
  "Reducer"                  -> Automatic,
  "CommitterAdapterBuilder"  -> Automatic,
  "QueryFunction"            -> Automatic,
  "MaxTasks"                 -> 10,
  "MaxParallelism"           -> 1,
  "JSONRetryMax"             -> 1,
  "UseDAG"                   -> Automatic,
  "Confirm"                  -> False,
  "Verbose"                  -> False,
  "SkipCommit"               -> False,
  "ReferenceText"            -> None,   (* T08: slide \:4f5c\:6210\:3067\:306e\:8a9e\:8abf/\:8a00\:3044\:56de\:3057\:3092\:771f\:4f3c\:308b\:305f\:3081\:306e\:30b5\:30f3\:30d7\:30eb\:672c\:6587 *)
  "Model"                    -> Automatic,  (* v2026-04-20 T08: Planner/Worker/Reducer/Committer \:5168\:90e8\:306b\:4f1d\:64ad *)
  "DeterministicFallback"    -> True   (* v2026-04-20 T10: deferred commit \:3067 LLM \:304c\:30bb\:30eb\:3092\:66f8\:304b\:306a\:304b\:3063\:305f\:3068\:304d\:3001
                                          iDeterministicSlideCommit / iGenericPayloadCommit \:3067\:6a5f\:68b0\:7684\:306b\:88dc\:5b8c\:3002
                                          \:540c\:671f\:7248 ClaudeCommitArtifacts \:306e\:540c\:540d option \:3068\:5bfe\:79f0\:3002 *)
};

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iResolveQueryFnForModel: Model \:6307\:5b9a\:304c\:3042\:308a queryFn \:304c Automatic \:306a\:3089\:3001
     ClaudeQuerySync \:3092 Model \:4ed8\:304d\:3067\:547c\:3076 wrapper \:3092\:751f\:6210\:3059\:308b\:3002
   
   v2026-04-20 T08: ClaudeRunOrchestration \:3067 Model \:30aa\:30d7\:30b7\:30e7\:30f3\:3092\:30b5\:30dd\:30fc\:30c8\:3002
     Planner/Worker/Reducer \:306f queryFn \:3092\:4f7f\:3046\:306e\:3067\:3001\:3053\:3053\:3067\:5909\:6570\:63db\:308f\:308a\:3001
     \:4e0b\:6d41\:3067\:306f\:901a\:5e38\:306e queryFn \:3068\:3057\:3066\:6271\:308f\:308c\:308b\:3002
     Committer \:306f\:5225\:9014 ClaudeBuildRuntimeAdapter \:306b Model \:3092\:76f4\:63a5\:6e21\:3059\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iResolveQueryFnForModel[queryFn_, model_] :=
  If[queryFn === Automatic && model =!= Automatic,
    With[{m = model},
      Function[prompt, ClaudeCode`ClaudeQuerySync[prompt, Model -> m]]],
    queryFn];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iResolveTargetNotebookAuto: "TargetNotebook" \:304c Automatic \:306e\:5834\:5408\:3001
     EvaluationNotebook[] \:306b\:81ea\:52d5\:89e3\:6c7a\:3059\:308b\:3002
   
   v2026-04-20 T04: Options \:306e\:30c7\:30d5\:30a9\:30eb\:30c8\:3092 None \:304b\:3089 Automatic \:306b\:5909\:3048\:305f\:3053\:3068\:306b
     \:4f34\:3046\:3002\:4ee5\:524d\:306f TargetNotebook \:672a\:6307\:5b9a = None = commit \:81ea\:52d5\:30b9\:30ad\:30c3\:30d7\:306e\:305f\:3081\:3001
     ClaudeRunOrchestration \:3092\:76f4\:63a5\:547c\:3076\:3068\:300c\:4f55\:3082\:8d77\:304d\:306a\:3044\:300d\:3068\:3044\:3046UX\:306b\:306a\:308a\:5f97\:305f\:3002
     Automatic \:306b\:3059\:308b\:3053\:3068\:3067 ClaudeEval \:7d4c\:7531\:3068\:540c\:3058\:632f\:308b\:821e\:3044 (\:73fe\:5728 nb \:306b\:66f8\:304d\:8fbc\:307f)
     \:3092\:5f97\:308b\:3002\:660e\:793a\:7684\:306b\:30b9\:30ad\:30c3\:30d7\:3057\:305f\:3044\:5834\:5408\:306f TargetNotebook -> None \:307e\:305f\:306f
     SkipCommit -> True \:3092\:6307\:5b9a\:3059\:308b\:3002
   
   None\:3001 _NotebookObject \:306f\:305d\:306e\:307e\:307e\:8fd4\:3059\:3002
   Quiet \:3067 FrontEnd \:4e0d\:5728\:6642 (\:30d0\:30c3\:30c1\:5b9f\:884c\:306a\:3069) \:306e\:5931\:6557\:306b\:5907\:3048\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iResolveTargetNotebookAuto[targetNb_] :=
  If[targetNb === Automatic,
    Quiet @ Check[EvaluationNotebook[], None],
    targetNb];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iWaitForRuntimeDAG: ClaudeRuntime \:306e DAG \:30b8\:30e7\:30d6\:3092\:540c\:671f\:5f85\:6a5f\:3059\:308b\:3002
   
   v2026-04-20 T06: ClaudeRunTurn \:306f jobId \:3092\:5373\:5ea7\:306b\:8fd4\:3059\:305f\:3081\:3001
   \:4e0a\:4f4d (commit \:7b49) \:306f DAG \:306e\:5b9f\:969b\:306e\:5b8c\:4e86\:3092\:5f85\:305f\:305a\:306b\:300cCommitted\:300d\:3068\:8aa4\:5224\:5b9a\:3057\:3066\:3044\:305f\:3002
   \:3053\:306e\:30d8\:30eb\:30d1\:30fc\:306f\:3001Runtime Status \:3068 DAG Status \:3092\:30dd\:30fc\:30ea\:30f3\:30b0\:3057\:3001
   Fatal (rate limit \:7b49) \:3092\:5373\:6642\:306b\:691c\:77e5\:3057\:3066\:9069\:5207\:306a Outcome \:3092\:8fd4\:3059\:3002
   
   \:8fd4\:308a\:5024: <|
     \"Outcome\"       -> \"Done\"|\"Failed\"|\"Timeout\"|\"JobMissing\",
     \"RuntimeId\"     -> rid,
     \"JobId\"         -> jid,
     \"FailureDetail\" -> <|\"ReasonClass\"->...,\"ResetsAt\"->...\:7b49|> (Failed \:6642\:306e\:307f),
     \"RuntimeStatus\" -> \"Done\"|\"Failed\"|... ,
     \"DAGStatus\"     -> <|\"Pending\"->..,\"Running\"->..,\"Done\"->..,\"Failed\"->..|>
   |>
   
   Done \:6642: runtime \:3082 DAG \:3082\:6b63\:5e38\:306b\:5b8c\:4e86
   Failed \:6642: ClaudeRuntime`ClaudeRuntimeRetry \:3067 retry \:53ef\:80fd\:3001
                 ClaudeRuntime`ClaudeRuntimeCancel \:3067\:4e2d\:6b62\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iWaitForRuntimeDAG[runtimeId_String, jobId_String,
    timeoutSecs_:300] :=
  Module[{startTime = AbsoluteTime[], status, rt, rtStatus,
          failureDetail, pollInterval = 0.3},
    While[True,
      (* 1. Runtime status check (Fatal \:6642\:306f\:5373\:691c\:77e5) *)
      rt = ClaudeRuntime`ClaudeRuntimeStateFull[runtimeId];
      rtStatus = If[AssociationQ[rt],
        Lookup[rt, "Status", "?"], "?"];
      failureDetail = If[AssociationQ[rt],
        Lookup[rt, "LastFailure", <||>], <||>];
      If[!AssociationQ[failureDetail], failureDetail = <||>];
      
      If[rtStatus === "Failed",
        Return[<|
          "Outcome"       -> "Failed",
          "RuntimeId"     -> runtimeId,
          "JobId"         -> jobId,
          "FailureDetail" -> failureDetail,
          "RuntimeStatus" -> rtStatus|>]];
      
      (* 2. DAG status *)
      status = ClaudeCode`LLMGraphDAGStatus[jobId];
      If[!AssociationQ[status],
        (* \:30b8\:30e7\:30d6\:304c\:898b\:3064\:304b\:3089\:306a\:3044: iAbortRuntimeDAGs \:3067\:524a\:9664\:3055\:308c\:305f\:304b\:3001\:6b63\:5e38\:5b8c\:4e86\:3067\:524a\:9664\:3055\:308c\:305f *)
        Return[<|
          "Outcome"       -> If[rtStatus === "Done", "Done", "JobMissing"],
          "RuntimeId"     -> runtimeId,
          "JobId"         -> jobId,
          "RuntimeStatus" -> rtStatus|>]];
      
      (* 3. \:5b8c\:4e86\:5224\:5b9a: Pending + Running == 0 *)
      If[Lookup[status, "Pending", 0] + Lookup[status, "Running", 0] === 0,
        If[Lookup[status, "Failed", 0] > 0,
          Return[<|
            "Outcome"       -> "Failed",
            "RuntimeId"     -> runtimeId,
            "JobId"         -> jobId,
            "FailureDetail" -> failureDetail,
            "RuntimeStatus" -> rtStatus,
            "DAGStatus"     -> status|>]];
        Return[<|
          "Outcome"       -> "Done",
          "RuntimeId"     -> runtimeId,
          "JobId"         -> jobId,
          "RuntimeStatus" -> rtStatus,
          "DAGStatus"     -> status|>]];
      
      (* 4. Timeout *)
      If[AbsoluteTime[] - startTime > timeoutSecs,
        Return[<|
          "Outcome"   -> "Timeout",
          "RuntimeId" -> runtimeId,
          "JobId"     -> jobId,
          "DAGStatus" -> status|>]];
      
      Pause[pollInterval]
    ]
  ];

ClaudeRunOrchestration[input_, opts:OptionsPattern[]] :=
  Module[{planResult, spawnResult, reduceResult, commitResult,
          verbose, skipCommit, targetNb, confirm, queryFn, model},
    verbose    = TrueQ[OptionValue["Verbose"]];
    skipCommit = TrueQ[OptionValue["SkipCommit"]];
    targetNb   = iResolveTargetNotebookAuto[OptionValue["TargetNotebook"]];
    confirm    = TrueQ[OptionValue["Confirm"]];
    model      = OptionValue["Model"];
    (* v2026-04-20 T08: Model \:6307\:5b9a\:6642\:306f queryFn \:3092 ClaudeQuerySync wrapper \:306b\:5909\:63db *)
    queryFn    = iResolveQueryFnForModel[OptionValue["QueryFunction"], model];
    
    If[verbose, Print["[orchestration] Phase A: Planning"]];
    planResult = ClaudePlanTasks[input,
      "Planner"       -> OptionValue["Planner"],
      "MaxTasks"      -> OptionValue["MaxTasks"],
      "QueryFunction" -> queryFn];
    
    If[Lookup[planResult, "Status", ""] =!= "Planned",
      Return[<|"Status"      -> "PlanningFailed",
               "PlanResult"  -> planResult|>]];
    
    If[verbose,
      Print["  Plan: ", Length[Lookup[planResult, "Tasks", {}]], " tasks"]];
    
    If[confirm,
      Return[<|"Status"      -> "AwaitingApproval",
               "PlanResult"  -> planResult,
               "Note"        -> iL["Confirm -> False \:3067\:518d\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
                                    "Re-run with Confirm -> False to proceed."]|>]];
    
    If[verbose, Print["[orchestration] Phase B: Worker Execution"]];
    spawnResult = ClaudeSpawnWorkers[planResult,
      "WorkerAdapterBuilder" -> OptionValue["WorkerAdapterBuilder"],
      "MaxParallelism"       -> OptionValue["MaxParallelism"],
      "JSONRetryMax"         -> OptionValue["JSONRetryMax"],
      "UseDAG"               -> OptionValue["UseDAG"],
      "QueryFunction"        -> queryFn,
      "Verbose"              -> verbose,
      "ReferenceText"        -> OptionValue["ReferenceText"]];  (* T08 *)
    
    If[verbose,
      Print["  Spawn status: ", Lookup[spawnResult, "Status", "?"]]];
    
    If[verbose, Print["[orchestration] Phase C: Reduction"]];
    reduceResult = ClaudeReduceArtifacts[
      Lookup[spawnResult, "Artifacts", <||>],
      "Reducer"       -> OptionValue["Reducer"],
      "QueryFunction" -> queryFn];
    
    commitResult = If[skipCommit || targetNb === None,
      <|"Status" -> "Skipped"|>,
      If[verbose, Print["[orchestration] Phase D: Commit"]];
      ClaudeCommitArtifacts[targetNb, reduceResult,
        "CommitterAdapterBuilder" -> OptionValue["CommitterAdapterBuilder"],
        "Confirm"                 -> False,
        "Verbose"                 -> verbose,
        "Model"                   -> model]];  (* T08: Committer \:306b Model \:4f1d\:9054 *)
    
    (* v2026-04-18T01: Status \:3092\:5b9f\:614b\:53cd\:6620\:3059\:308b (\:4ee5\:524d\:306f\:5e38\:306b "Done" \:3060\:3063\:305f)\:3002
       \:3053\:308c\:306b\:3088\:308a hook \:306f Status \\!= "Done" \:3092\:898b\:3066 Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3067\:304d\:308b\:3002
       Priority: Commit failure > Spawn failure > Spawn partial > Done\:3002
       \:4e92\:63db\:6027: Commit skip (targetNb==None) \:306f\:3053\:308c\:307e\:3067\:901a\:308a "Done" \:306e\:307e\:307e\:3002 *)
    Module[{spawnStatus, commitStatus, orchestrationStatus},
      spawnStatus  = Lookup[spawnResult,  "Status", ""];
      commitStatus = Lookup[commitResult, "Status", ""];
      orchestrationStatus = Which[
        commitStatus === "Failed" || commitStatus === "RolledBack" ||
          commitStatus === "Timeout",
          "CommitFailed",
        spawnStatus === "Failed",
          "SpawnFailed",
        spawnStatus === "Partial",
          "SpawnPartial",
        True,
          "Done"];
      <|
        "Status"       -> orchestrationStatus,
        "PlanResult"   -> planResult,
        "SpawnResult"  -> spawnResult,
        "ReduceResult" -> reduceResult,
        "CommitResult" -> commitResult
      |>
    ]
  ];

(* ════════════════════════════════════════════════════════
   11. ClaudeContinueBatch (spec §17.1 折衷案)
   
   単一 runtime セッションを維持したまま batchInstructions を
   ClaudeContinueTurn で順次投入する。Phase 31 の notebook 共有問題を
   回避する現実解。caller は既存の runtime (例: ClaudeStartRuntime の
   結果) を渡す。
   ════════════════════════════════════════════════════════ *)

Options[ClaudeContinueBatch] = {
  "WaitBetween" -> Quantity[0, "Seconds"],
  "Verbose"     -> False
};

ClaudeContinueBatch[runtimeId_String, batchInstructions_List,
    opts:OptionsPattern[]] :=
  Module[{results = {}, verbose, wait, waitSec, idx = 0, res},
    verbose = TrueQ[OptionValue["Verbose"]];
    wait    = OptionValue["WaitBetween"];
    waitSec = Quiet @ Check[
      If[Head[wait] === Quantity,
        QuantityMagnitude[UnitConvert[wait, "Seconds"]], 0], 0];
    
    Do[
      idx++;
      If[verbose,
        Print["  [batch ", idx, "/", Length[batchInstructions], "] ",
          StringTake[ToString[instr], UpTo[60]]]];
      
      (* 前バッチの返事を待つ必要があれば sleep *)
      If[idx > 1 && waitSec > 0, Pause[waitSec]];
      
      res = Quiet @ Check[
        If[idx === 1,
          ClaudeRuntime`ClaudeRunTurn[runtimeId, instr],
          (* 第 2 バッチ以降はユーザ入力として追加 *)
          Module[{rt = ClaudeRuntime`Private`$iClaudeRuntimes[runtimeId]},
            If[AssociationQ[rt],
              rt["ContinuationInput"] = instr;
              ClaudeRuntime`Private`$iClaudeRuntimes[runtimeId] = rt];
            ClaudeRuntime`ClaudeContinueTurn[runtimeId]]],
        $Failed];
      
      AppendTo[results, <|
        "Index"     -> idx,
        "Prompt"    -> instr,
        "RuntimeId" -> runtimeId,
        "Result"    -> res
      |>],
      {instr, batchInstructions}];
    
    results
  ];

ClaudeContinueBatch[_, _, ___] :=
  {<|"Error" -> "InvalidArguments"|>};

(* ════════════════════════════════════════════════════════
   12. Async Orchestration (v2026-04-20)
   
   4 フェーズ (Plan / Spawn / Reduce / Commit) を DAG コールバック
   チェーンで繋ぎ、フロントエンドをブロックせずに orchJobId を
   即時返す。
   
   設計:
     - ClaudeRunOrchestrationAsync[input, opts]:
         orchJobId を生成し $iClaudeOrchestrationJobs に登録。
         Plan フェーズを単一 sync ノードの DAG として起動し、
         その onComplete で Spawn フェーズを DAG 起動、
         Spawn の onComplete で Reduce+Commit を sync ノード DAG として起動、
         完了で最終状態を確定。
     - 各フェーズの sync ハンドラ内部は URLRead/ClaudeQueryBg で
       directive 95 に適合。共有ポーリングタスク ($iSharedPollingTask)
       上で回るため、Pause ベースのビジーウェイトは一切行わない。
   ════════════════════════════════════════════════════════ *)

(* レジストリ: orchJobId -> state Association *)
If[!AssociationQ[$iClaudeOrchestrationJobs],
  $iClaudeOrchestrationJobs = <||>];

(* 状態フィールドヘルパー: レジストリ内の特定フィールドを更新 *)
iOrchSet[orchId_String, fields_Association] :=
  Module[{s},
    s = Lookup[$iClaudeOrchestrationJobs, orchId, <||>];
    If[!AssociationQ[s], s = <||>];
    s = Join[s, fields];
    $iClaudeOrchestrationJobs[orchId] = s;
    s];

iOrchGet[orchId_String] :=
  Lookup[$iClaudeOrchestrationJobs, orchId, Missing["NotFound", orchId]];

(* ──────────────────────────────────────────────
   iRunPlanPhaseSync: Plan フェーズ (sync ノードハンドラ)
   ────────────────────────────────────────────── *)

iRunPlanPhaseSync[orchId_String] :=
  Module[{state, input, optsList, planResult, planner, maxTasks, queryFn},
    state    = iOrchGet[orchId];
    If[!AssociationQ[state], Return[<|"Status" -> "Failed"|>]];
    input    = Lookup[state, "Input", ""];
    optsList = Lookup[state, "OptionsList", {}];
    planner  = OptionValue[ClaudeRunOrchestration, optsList, "Planner"];
    maxTasks = OptionValue[ClaudeRunOrchestration, optsList, "MaxTasks"];
    queryFn  = OptionValue[ClaudeRunOrchestration, optsList, "QueryFunction"];
    
    planResult = Quiet @ Check[
      ClaudePlanTasks[input,
        "Planner"       -> planner,
        "MaxTasks"      -> maxTasks,
        "QueryFunction" -> queryFn],
      $Failed];
    
    If[planResult === $Failed || !AssociationQ[planResult],
      planResult = <|"Status" -> "Failed",
                     "Error"  -> "PlanExceptionOrFailed"|>];
    iOrchSet[orchId, <|"PlanResult" -> planResult|>];
    planResult
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iLaunchPlanPhase: Plan \:30d5\:30a7\:30fc\:30ba\:306e deferred sync \:8d77\:52d5\:95a2\:6570 (v2026-04-20 T02)
   
   \:8fd4\:308a\:5024: AssociationQ[<|"proc"->..., "outFile"->..., "parseFn"->...|>]
     \[RightArrow] iLLMGraphDAGTick \:304c\:30ce\:30fc\:30c9\:3092 "running" \:306b\:9077\:79fb\:3055\:305b\:3001
        iICollectChunkResult \:3067\:30dd\:30fc\:30ea\:30f3\:30b0\:3059\:308b\:3002
     Claude CLI \:547c\:3073\:51fa\:3057 (\:5e73\:5747 30\:79d2) \:304c tick \:5916\:3067\:884c\:308f\:308c\:308b\:305f\:3081\:3001
     FrontEnd \:30d6\:30ed\:30c3\:30af\:304c\:89e3\:6d88\:3055\:308c\:308b\:3002
   
   planner =!= "LLM" / queryFn =!= Automatic \:306e\:5834\:5408\:306f\:5f93\:6765\:540c\:671f\:306e
   iRunPlanPhaseSync \:306b fallback\:3002\:3053\:308c\:306b\:3088\:308a\:30c6\:30b9\:30c8\:74b0\:5883\:3084\:30b9\:30bf\:30d6
   planner \:306f\:4e92\:63db\:6027\:3092\:7dad\:6301\:3059\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iLaunchPlanPhase[orchId_String] :=
  Module[{state, input, optsList, planner, maxTasks, queryFn,
          prompt, plannerOpts, promptFile, outFile, batFile, proc,
          workDir, uniqueTag},
    state    = iOrchGet[orchId];
    If[!AssociationQ[state], Return[iRunPlanPhaseSync[orchId]]];
    input    = Lookup[state, "Input", ""];
    optsList = Lookup[state, "OptionsList", {}];
    planner  = OptionValue[ClaudeRunOrchestration, optsList, "Planner"];
    maxTasks = OptionValue[ClaudeRunOrchestration, optsList, "MaxTasks"];
    queryFn  = OptionValue[ClaudeRunOrchestration, optsList, "QueryFunction"];
    
    (* LLM planner \:304b\:3064 queryFn=Automatic \:4ee5\:5916\:306f\:5f93\:6765\:540c\:671f\:3067\:5373\:8fd4\:5374 *)
    If[planner =!= "LLM" || queryFn =!= Automatic,
      Return[iRunPlanPhaseSync[orchId]]];
    
    (* LLM planner \:306e\:975e\:540c\:671f\:8d77\:52d5 *)
    plannerOpts = <|"MaxTasks" -> maxTasks, "QueryFunction" -> queryFn|>;
    prompt = Quiet @ Check[
      iPlannerBuildPrompt[input, plannerOpts], $Failed];
    If[!StringQ[prompt],
      Return[iRunPlanPhaseSync[orchId]]];
    
    workDir = Quiet @ Check[
      ClaudeCode`$ClaudeWorkingDirectory, $TemporaryDirectory];
    If[!StringQ[workDir] || !DirectoryQ[workDir],
      workDir = $TemporaryDirectory];
    
    uniqueTag = orchId <> "_" <> ToString[RandomInteger[999999]];
    promptFile = FileNameJoin[{workDir,
      "orch_plan_prompt_" <> uniqueTag <> ".txt"}];
    outFile = FileNameJoin[{workDir,
      "orch_plan_out_" <> uniqueTag <> ".txt"}];
    
    Quiet @ Check[
      Export[promptFile, prompt, "Text",
        CharacterEncoding -> "UTF-8"], $Failed];
    If[!FileExistsQ[promptFile],
      Return[iRunPlanPhaseSync[orchId]]];
    
    batFile = Quiet @ Check[
      ClaudeCode`iMakeBat[promptFile, outFile, {}, False, {}],
      $Failed];
    If[!StringQ[batFile] || !FileExistsQ[batFile],
      Quiet @ DeleteFile[promptFile];
      Return[iRunPlanPhaseSync[orchId]]];
    
    proc = Quiet @ Check[
      RunProcess[{"cmd", "/c", batFile},
        ProcessDirectory -> workDir,
        "Process"],
      $Failed];
    If[proc === $Failed || !MatchQ[proc, _ProcessObject],
      Quiet @ DeleteFile[promptFile];
      Quiet @ DeleteFile[batFile];
      Return[iRunPlanPhaseSync[orchId]]];
    
    (* deferred sync runState \:3092\:8fd4\:3059\:3002
       iLLMGraphDAGTick \:304c\:3053\:308c\:3092 running \:72b6\:614b\:306b\:9077\:79fb\:3055\:305b\:3001
       iICollectChunkResult \:3067\:30dd\:30fc\:30ea\:30f3\:30b0\:3059\:308b\:3002
       \:5b8c\:4e86\:6642 parseFn (iParsePlanResult) \:304c raw response \:3092 planResult \:306b\:5909\:63db\:3059\:308b\:3002 *)
    With[{oid = orchId, mxt = maxTasks},
      <|"proc"       -> proc,
        "outFile"    -> outFile,
        "batFile"    -> batFile,
        "promptFile" -> promptFile,
        "startTime"  -> AbsoluteTime[],
        "timeout"    -> 1200,
        "parseFn"    -> Function[{raw},
          iParsePlanResult[oid, raw, mxt]]|>]
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iParsePlanResult: iLaunchPlanPhase \:306e parseFn \:672c\:4f53\:3002
   
   raw \:306f Claude CLI \:306e\:751f\:5fdc\:7b54 (cleanOutput + stripANSI \:6e08\:307f)\:3002
   JSON \:62bd\:51fa\:30fb\:30d1\:30fc\:30b9\:30fb TaskSpec \:6b63\:898f\:5316\:30fb validation \:307e\:3067\:3092
   \:4e00\:62ec\:3067\:884c\:3046\:3002iLLMPlannerFn \:306e\:5f8c\:534a\:90e8\:3092\:305d\:306e\:307e\:307e\:79fb\:690d\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iParsePlanResult[orchId_String, raw_String, maxTasks_Integer] :=
  Module[{jsonStr, parsed, tasksList, planResult, validation},
    jsonStr = iExtractJSONFromResponse[raw];
    parsed  = iParseJSON[jsonStr];
    
    If[parsed === $Failed || !AssociationQ[parsed],
      (* JSON \:30d1\:30fc\:30b9\:5931\:6557: Failed \:3068\:3057\:3066\:8fd4\:3059 *)
      planResult = <|"Tasks" -> {},
        "Status" -> "Failed",
        "Error"  -> iL["LLM \:5fdc\:7b54\:306e JSON \:30d1\:30fc\:30b9\:306b\:5931\:6557",
                       "Failed to parse JSON from LLM response"],
        "RawResponse" -> StringTake[raw, UpTo[500]]|>;
      iOrchSet[orchId, <|"PlanResult" -> planResult|>];
      Return[planResult]];
    
    (* Tasks \:30ad\:30fc\:53d6\:5f97 *)
    tasksList = Lookup[parsed, "Tasks", None];
    If[tasksList === None,
      If[ListQ[parsed],
        tasksList = parsed,
        planResult = <|"Tasks" -> {},
          "Status" -> "Failed",
          "Error"  -> iL["Tasks \:30ad\:30fc\:304c\:898b\:3064\:304b\:3089\:306a\:3044",
                         "No Tasks key found in LLM response"]|>;
        iOrchSet[orchId, <|"PlanResult" -> planResult|>];
        Return[planResult]]];
    
    If[!ListQ[tasksList],
      planResult = <|"Tasks" -> {},
        "Status" -> "Failed",
        "Error"  -> iL["Tasks \:304c\:30ea\:30b9\:30c8\:3067\:306f\:306a\:3044",
                       "Tasks is not a list"]|>;
      iOrchSet[orchId, <|"PlanResult" -> planResult|>];
      Return[planResult]];
    
    (* MaxTasks \:5236\:9650 *)
    If[Length[tasksList] > maxTasks,
      tasksList = Take[tasksList, maxTasks]];
    
    (* Association \:5316\:3068 TaskSpec \:88dc\:5b8c *)
    tasksList = Map[
      If[AssociationQ[#], #, Association[#]] &,
      tasksList];
    tasksList = Map[iNormalizeTaskSpec, tasksList];
    
    planResult = <|"Tasks" -> tasksList|>;
    validation = ClaudeValidateTaskSpec[planResult];
    
    planResult = If[TrueQ[Lookup[validation, "Valid", False]],
      Append[planResult, "Status" -> "Planned"],
      Join[planResult,
        <|"Status" -> "InvalidPlan",
          "ValidationErrors" -> Lookup[validation, "Errors", {}]|>]];
    
    iOrchSet[orchId, <|"PlanResult" -> planResult|>];
    planResult
  ];

(* ──────────────────────────────────────────────
   iRunReducePhaseSync: Reduce フェーズ (sync ノードハンドラ)
   ────────────────────────────────────────────── *)

iRunReducePhaseSync[orchId_String] :=
  Module[{state, spawnResult, artifacts, reducer, queryFn, reduceResult,
          optsList},
    state       = iOrchGet[orchId];
    If[!AssociationQ[state], Return[<|"Status" -> "Failed"|>]];
    optsList    = Lookup[state, "OptionsList", {}];
    spawnResult = Lookup[state, "SpawnResult", <||>];
    artifacts   = Lookup[spawnResult, "Artifacts", <||>];
    reducer     = OptionValue[ClaudeRunOrchestration, optsList, "Reducer"];
    queryFn     = OptionValue[ClaudeRunOrchestration, optsList, "QueryFunction"];
    
    reduceResult = Quiet @ Check[
      ClaudeReduceArtifacts[artifacts,
        "Reducer"       -> reducer,
        "QueryFunction" -> queryFn],
      <|"Status" -> "Failed"|>];
    If[!AssociationQ[reduceResult],
      reduceResult = <|"Status" -> "Failed"|>];
    iOrchSet[orchId, <|"ReduceResult" -> reduceResult|>];
    reduceResult
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iLaunchReducePhase: Reduce \:30d5\:30a7\:30fc\:30ba\:306e deferred sync \:8d77\:52d5\:95a2\:6570
   
   \:8a72\:5f53\:3059\:308b\:5834\:5408: reducer === "LLM" \:304b\:3064 queryFn === Automatic \:304b\:3064
     artifact \:304c 2 \:500b\:4ee5\:4e0a (1 \:500b\:306a\:3089\:30de\:30fc\:30b8\:4e0d\:8981\:3067\:5373\:8fd4\:5374)
   
   \:8a72\:5f53\:3057\:306a\:3044\:5834\:5408\:306f iRunReducePhaseSync \:306b fallback (\:5373\:6642\:5b8c\:4e86)\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iLaunchReducePhase[orchId_String] :=
  Module[{state, optsList, reducer, queryFn, spawnResult, artifacts,
          artifactSummary, prompt, promptFile, outFile, batFile, proc,
          workDir, uniqueTag},
    state    = iOrchGet[orchId];
    If[!AssociationQ[state], Return[iRunReducePhaseSync[orchId]]];
    optsList = Lookup[state, "OptionsList", {}];
    reducer  = OptionValue[ClaudeRunOrchestration, optsList, "Reducer"];
    queryFn  = OptionValue[ClaudeRunOrchestration, optsList, "QueryFunction"];
    
    (* LLM reducer \:304b\:3064 queryFn = Automatic \:4ee5\:5916\:306f\:540c\:671f fallback *)
    If[reducer =!= "LLM" || queryFn =!= Automatic,
      Return[iRunReducePhaseSync[orchId]]];
    
    spawnResult = Lookup[state, "SpawnResult", <||>];
    artifacts   = Lookup[spawnResult, "Artifacts", <||>];
    
    (* artifact 0/1 \:500b\:306f\:30de\:30fc\:30b8\:4e0d\:8981: \:540c\:671f\:5373\:8fd4\:5374\:3067\:5341\:5206 *)
    If[Length[artifacts] <= 1,
      Return[iRunReducePhaseSync[orchId]]];
    
    (* iLLMReducer \:3068\:540c\:3058\:30d7\:30ed\:30f3\:30d7\:30c8\:69cb\:7bc9 *)
    artifactSummary = StringJoin[
      KeyValueMap[
        Function[{tid, art},
          "--- Artifact: " <> tid <> " ---\n" <>
          ToString[Lookup[art, "Payload", <||>], InputForm] <> "\n\n"],
        artifacts]];
    prompt = $iReducerSystemPrompt <> "\n\n" <>
      "ARTIFACTS TO MERGE (" <> ToString[Length[artifacts]] <> " total):\n\n" <>
      artifactSummary <>
      "\nMerge these artifacts into a single JSON object.";
    
    workDir = Quiet @ Check[
      ClaudeCode`$ClaudeWorkingDirectory, $TemporaryDirectory];
    If[!StringQ[workDir] || !DirectoryQ[workDir],
      workDir = $TemporaryDirectory];
    
    uniqueTag = orchId <> "_" <> ToString[RandomInteger[999999]];
    promptFile = FileNameJoin[{workDir,
      "orch_reduce_prompt_" <> uniqueTag <> ".txt"}];
    outFile = FileNameJoin[{workDir,
      "orch_reduce_out_" <> uniqueTag <> ".txt"}];
    
    Quiet @ Check[
      Export[promptFile, prompt, "Text",
        CharacterEncoding -> "UTF-8"], $Failed];
    If[!FileExistsQ[promptFile],
      Return[iRunReducePhaseSync[orchId]]];
    
    batFile = Quiet @ Check[
      ClaudeCode`iMakeBat[promptFile, outFile, {}, False, {}],
      $Failed];
    If[!StringQ[batFile] || !FileExistsQ[batFile],
      Quiet @ DeleteFile[promptFile];
      Return[iRunReducePhaseSync[orchId]]];
    
    proc = Quiet @ Check[
      RunProcess[{"cmd", "/c", batFile},
        ProcessDirectory -> workDir,
        "Process"],
      $Failed];
    If[proc === $Failed || !MatchQ[proc, _ProcessObject],
      Quiet @ DeleteFile[promptFile];
      Quiet @ DeleteFile[batFile];
      Return[iRunReducePhaseSync[orchId]]];
    
    With[{oid = orchId, arts = artifacts},
      <|"proc"       -> proc,
        "outFile"    -> outFile,
        "batFile"    -> batFile,
        "promptFile" -> promptFile,
        "startTime"  -> AbsoluteTime[],
        "timeout"    -> 1200,
        "parseFn"    -> Function[{raw},
          iParseReduceResult[oid, raw, arts]]|>]
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iParseReduceResult: iLaunchReducePhase \:306e parseFn \:672c\:4f53
   
   iLLMReducer \:306e\:5f8c\:534a (JSON \:62bd\:51fa\:30fb\:30d1\:30fc\:30b9\:30fbdefault \:3078\:306e fallback) \:3092\:79fb\:690d\:3002
   \:6700\:7d42\:7684\:306b ClaudeReduceArtifacts \:304c\:8fd4\:3059\:5f62\:3068\:540c\:3058\:5f62\:5f0f (ArtifactType->"Reduced", ...)
   \:306b\:307e\:3067\:6574\:5f62\:3057\:3066 iOrchSet \:3059\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iParseReduceResult[orchId_String, raw_String,
    artifacts_Association] :=
  Module[{jsonStr, parsed, reducePayload, reduceResult},
    jsonStr = iExtractJSONFromResponse[raw];
    parsed  = iParseJSON[jsonStr];
    
    reducePayload = If[AssociationQ[parsed],
      parsed,
      (* JSON \:30d1\:30fc\:30b9\:5931\:6557\:6642\:306f\:6c7a\:5b9a\:7684 reducer \:306b fallback *)
      Quiet @ Check[iDefaultReducer[artifacts], <||>]];
    
    If[!AssociationQ[reducePayload], reducePayload = <||>];
    
    reduceResult = <|
      "ArtifactType" -> "Reduced",
      "Sources"      -> Keys[artifacts],
      "Payload"      -> reducePayload,
      "Attempts"     -> 1|>;
    
    iOrchSet[orchId, <|"ReduceResult" -> reduceResult|>];
    reduceResult
  ];

(* ──────────────────────────────────────────────
   iRunCommitPhaseSync: Commit フェーズ (sync ノードハンドラ)
   ────────────────────────────────────────────── *)

iRunCommitPhaseSync[orchId_String] :=
  Module[{state, optsList, skipCommit, targetNb, reduceResult,
          commitResult, builder, verbose, model},
    state       = iOrchGet[orchId];
    If[!AssociationQ[state], Return[<|"Status" -> "Failed"|>]];
    optsList    = Lookup[state, "OptionsList", {}];
    skipCommit  = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "SkipCommit"]];
    targetNb    = iResolveTargetNotebookAuto[
      OptionValue[ClaudeRunOrchestration, optsList, "TargetNotebook"]];
    builder     = OptionValue[ClaudeRunOrchestration, optsList, "CommitterAdapterBuilder"];
    verbose     = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "Verbose"]];
    model       = OptionValue[ClaudeRunOrchestration, optsList, "Model"];   (* T08 *)
    reduceResult = Lookup[state, "ReduceResult", <||>];
    
    commitResult = If[skipCommit || targetNb === None,
      <|"Status" -> "Skipped"|>,
      Quiet @ Check[
        ClaudeCommitArtifacts[targetNb, reduceResult,
          "CommitterAdapterBuilder" -> builder,
          "Confirm"                 -> False,
          "Verbose"                 -> verbose,
          "Model"                   -> model],   (* T08 *)
        <|"Status" -> "Failed"|>]];
    If[!AssociationQ[commitResult],
      commitResult = <|"Status" -> "Failed"|>];
    iOrchSet[orchId, <|"CommitResult" -> commitResult|>];
    commitResult
  ];

(* \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500
   iLaunchCommitPhase / iOnCommitSubJobComplete
   
   v2026-04-20 T07 (Stage 3): \:975e\:540c\:671f\:30e2\:30fc\:30c9\:7528\:306b commit \:30d5\:30a7\:30fc\:30ba\:3092 deferred \:5316\:3002
   
   \:3053\:308c\:307e\:3067\:306f iOnReduceCompleteDirect \:304c iRunCommitPhaseSync \:3092 commit
   \:30ce\:30fc\:30c9\:306e sync \:30cf\:30f3\:30c9\:30e9\:3068\:3057\:3066\:547c\:3093\:3067\:3044\:305f\:305f\:3081\:3001\:305d\:306e\:5185\:90e8\:3067
   ClaudeCommitArtifacts \:2192 iWaitForRuntimeDAG \:306e Pause \:30dd\:30fc\:30ea\:30f3\:30b0\:304c tick \:3092
   \:5360\:6709\:3057\:3001\:300c\:52d5\:7684\:8a55\:4fa1\:306e\:653e\:68c4\:300d\:30c0\:30a4\:30a2\:30ed\:30b0\:306e\:539f\:56e0\:306b\:306a\:3063\:3066\:3044\:305f\:3002
   
   iLaunchCommitPhase \:306f commit \:7528 runtime \:3092\:8d77\:52d5\:3057\:3066 sub-DAG jobId \:3092\:8fd4\:3059\:3002
   claudecode.wl \:306e iLLMGraphDAGTick (T19+) \:304c subJobId \:30d9\:30fc\:30b9\:3067\:5f85\:6a5f\:3057\:3001
   tick \:3092\:30d6\:30ed\:30c3\:30af\:3057\:306a\:3044\:3002\:5b8c\:4e86\:6642\:306b subCompleteFn \:304c\:547c\:3070\:308c\:3001
   runtime \:306e FailureInfo \:3092\:898b\:3066 commitResult \:3092\:69cb\:7bc9\:3059\:308b\:3002
   
   \:540c\:671f\:30e2\:30fc\:30c9 (ClaudeRunOrchestration \:76f4\:63a5\:547c\:3073\:51fa\:3057) \:3067\:306f
   iRunCommitPhaseSync \:3092\:7d9a\:3051\:3066\:4f7f\:7528 (\:30d6\:30ed\:30c3\:30af\:3057\:3066\:3088\:3044\:306e\:3067)\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

iLaunchCommitPhase[orchId_String] :=
  Module[{state, optsList, skipCommit, targetNb, verbose,
          reduceResult, builder, reducedArtifact, adapter,
          runtimeId, input, subJobId, model, cellsBeforeCommit,
          detFallback},
    state = iOrchGet[orchId];
    If[!AssociationQ[state],
      Return[<|"Status" -> "Failed", "Reason" -> "OrchestrationNotFound"|>]];
    
    optsList   = Lookup[state, "OptionsList", {}];
    skipCommit = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "SkipCommit"]];
    targetNb   = iResolveTargetNotebookAuto[
      OptionValue[ClaudeRunOrchestration, optsList, "TargetNotebook"]];
    verbose    = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "Verbose"]];
    builder    = OptionValue[ClaudeRunOrchestration, optsList, "CommitterAdapterBuilder"];
    model      = OptionValue[ClaudeRunOrchestration, optsList, "Model"];  (* T08 *)
    detFallback = TrueQ[OptionValue[ClaudeRunOrchestration, optsList,
                          "DeterministicFallback"]];   (* v2026-04-20 T10 *)
    reduceResult = Lookup[state, "ReduceResult", <||>];
    
    If[skipCommit || targetNb === None,
      iOrchSet[orchId, <|"CommitResult" -> <|"Status" -> "Skipped"|>|>];
      Return[<|"Status" -> "Skipped"|>]];
    
    reducedArtifact = If[AssociationQ[reduceResult],
      <|"Status"       -> Lookup[reduceResult, "Status", "Reduced"],
        "ArtifactType" -> Lookup[reduceResult, "ArtifactType", "Reduced"],
        "Sources"      -> Lookup[reduceResult, "Sources", {}],
        "Payload"      -> Lookup[reduceResult, "Payload", <||>]|>,
      <|"Status" -> "Reduced", "ArtifactType" -> "Reduced",
        "Sources" -> {}, "Payload" -> <||>|>];
    
    (* adapter \:69cb\:7bc9 \:2014 T08: Model \:3092 Committer adapter \:306b\:4f1d\:9054\:3002
       \:30ab\:30b9\:30bf\:30e0 builder \:304c Options \:3092\:53d7\:3051\:53d6\:308c\:306a\:3044\:5834\:5408\:3092
       \:4e8c\:6bb5\:968e Fallback \:3067\:51e6\:7406\:3002 *)
    adapter = Which[
      builder === Automatic,
        Quiet @ Check[
          iDefaultCommitterAdapterBuilder[targetNb, reducedArtifact,
            "Model" -> model],
          $Failed],
      True,
        Quiet @ Check[
          builder[targetNb, reducedArtifact, "Model" -> model],
          Quiet @ Check[
            builder[targetNb, reducedArtifact],
            $Failed]]];
    
    If[!AssociationQ[adapter] || KeyExistsQ[adapter, "Error"],
      Module[{errMsg},
        errMsg = If[AssociationQ[adapter],
          Lookup[adapter, "Error", "UnknownBuilderError"],
          "AdapterBuilderFailed"];
        If[verbose,
          Print[Style["  [commit] adapter builder failed: " <> errMsg, Red]]];
        iOrchSet[orchId, <|"CommitResult" -> <|
          "Status" -> "Failed",
          "Reason" -> "CommitterAdapterFailed",
          "Error"  -> errMsg|>|>];
        Return[<|"Status" -> "Failed", "Reason" -> "CommitterAdapterFailed"|>]]];
    
    (* runtime \:4f5c\:6210 *)
    runtimeId = Quiet @ Check[
      ClaudeRuntime`CreateClaudeRuntime[adapter], $Failed];
    If[!StringQ[runtimeId],
      If[verbose,
        Print[Style["  [commit] CreateClaudeRuntime failed", Red]]];
      iOrchSet[orchId, <|"CommitResult" -> <|
        "Status" -> "Failed",
        "Reason" -> "CreateCommitterRuntimeFailed"|>|>];
      Return[<|"Status" -> "Failed", "Reason" -> "CreateRuntimeFailed"|>]];
    
    input = <|
      "Goal" -> iL["\:30ec\:30c7\:30e5\:30fc\:30b9\:3055\:308c\:305f artifact \:3092 notebook \:306b\:53cd\:6620",
                   "Commit reduced artifact to notebook"],
      "Role"             -> "Commit",
      "TargetNotebook"   -> targetNb,
      "ReducedArtifact"  -> reducedArtifact,
      "CommitPolicy"     -> <|
        "DenyCreateNotebook"        -> True,
        "RewriteEvaluationNotebook" -> True|>|>;
    
    (* sub-DAG \:8d77\:52d5 *)
    subJobId = Quiet @ Check[
      ClaudeRuntime`ClaudeRunTurn[runtimeId, input], $Failed];
    
    If[!StringQ[subJobId],
      If[verbose,
        Print[Style["  [commit] ClaudeRunTurn failed: " <>
          ToString[subJobId], Red]]];
      iOrchSet[orchId, <|"CommitResult" -> <|
        "Status"    -> "Failed",
        "Reason"    -> "RunTurnFailed",
        "Details"   -> ToString[subJobId],
        "RuntimeId" -> runtimeId|>|>];
      Return[<|"Status" -> "Failed", "Reason" -> "RunTurnFailed"|>]];
    
    If[verbose,
      Print["  [commit] deferred launched: runtimeId=", runtimeId,
        " subJobId=", subJobId,
        " detFallback=", detFallback]];
    
    (* v2026-04-20 T09: commit \:8d77\:52d5\:6642\:306e\:30bb\:30eb\:6570\:3092\:8a18\:9332\:3057\:3001
       \:5b8c\:4e86\:6642\:306e cellsDelta \:3067\:66f8\:304d\:8fbc\:307f\:304c\:884c\:308f\:308c\:305f\:304b\:5224\:5b9a\:3059\:308b\:3002
       \:540c\:671f\:7248 iCommitArtifactsOnce \:306f\:5143\:304b\:3089\:3053\:306e\:30c1\:30a7\:30c3\:30af\:3092\:6301\:3064\:304c\:3001
       T07 \:3067\:65b0\:8a2d\:3057\:305f deferred \:7248 iOnCommitSubJobComplete \:3067\:6f0f\:308c\:3066\:3044\:305f\:3002
       \:ff08LLM \:304c runtime \:3092 Done \:306b\:3057\:3066\:3082 NotebookWrite \:3092\:547c\:3070\:306a\:3044\:5834\:5408\:3001
        \:300cCommitted\:300d\:3068\:8aa4\:5224\:5b9a\:3057\:3066\:3044\:305f\:ff09\:3002 *)
    cellsBeforeCommit = If[MatchQ[targetNb, _NotebookObject],
      Quiet @ Check[Length[Cells[targetNb]], 0], 0];
    
    iOrchSet[orchId, <|
      "CommitRuntimeId"    -> runtimeId,
      "CommitSubJobId"     -> subJobId,
      "CommitStartTime"    -> AbsoluteTime[],
      "CommitCellsBefore"  -> cellsBeforeCommit|>];
    
    (* Deferred sync: iLLMGraphDAGTick \:304c subJobId \:30d9\:30fc\:30b9\:3067\:5f85\:6a5f\:3059\:308b runState
       v2026-04-20 T10: detFallback \:30d5\:30e9\:30b0\:3092 closure \:306b\:6e21\:3057\:3001
         iOnCommitSubJobComplete \:5185\:3067 LLM \:7d4c\:7531\:5931\:6557\:6642\:306b deterministic fallback
         (iAttemptCommitFallback) \:3092\:8d77\:52d5\:3059\:308b\:3002 *)
    With[{oid = orchId, rid = runtimeId, sjid = subJobId,
          tn = targetNb, ra = reducedArtifact, ad = adapter,
          verb = verbose, cb = cellsBeforeCommit, df = detFallback},
      <|
        "subJobId"      -> sjid,
        "subRuntimeId"  -> rid,
        "subCompleteFn" -> Function[{outcome, subStatus, runState},
          iOnCommitSubJobComplete[oid, rid, sjid, tn, ra, ad,
            outcome, subStatus, verb, cb, df]]
      |>
    ]
  ];

iOnCommitSubJobComplete[orchId_String, rid_String, sjid_String,
    targetNb_, reducedArtifact_Association, adapter_Association,
    outcome_String, subStatus_, verbose_, cellsBefore_Integer:0,
    deterministicFallback_:True] :=
  Module[{rt, failureDetail, cellsAfter, cellsDelta, commitResult,
          lastProposal, lastProviderRespRaw, providerRespHead,
          heldExprFound, fallbackResult, fallbackUsed, fallbackCells,
          cellsAfterFb, cellsDeltaFb, diagInfo,
          effectiveCellsAfter, effectiveCellsDelta,   (* T11 *)
          directRescueResult},   (* T15 *)
    rt = Quiet @ ClaudeRuntime`ClaudeRuntimeStateFull[rid];
    failureDetail = If[AssociationQ[rt],
      Lookup[rt, "LastFailure", <||>], <||>];
    If[!AssociationQ[failureDetail], failureDetail = <||>];
    
    cellsAfter = If[MatchQ[targetNb, _NotebookObject],
      Quiet @ Check[Length[Cells[targetNb]], 0], 0];
    cellsDelta = cellsAfter - cellsBefore;   (* v2026-04-20 T09 *)
    
    (* v2026-04-20 T10: \:8a3a\:65ad\:60c5\:5831\:3092 runtime state \:304b\:3089\:62bd\:51fa
       \:2014 LastProposal \:306e HeldExpr \:6709\:7121\:3068 ParseProposal \:7d50\:679c
       \:2014 LastProviderResponse \:306e\:5148\:982d\:6587\:5b57\:5217 (LLM \:751f\:5fdc\:7b54\:306e\:8a3a\:65ad\:7528) *)
    lastProposal = If[AssociationQ[rt],
      Lookup[rt, "LastProposal", <||>], <||>];
    If[!AssociationQ[lastProposal], lastProposal = <||>];
    heldExprFound = MatchQ[Lookup[lastProposal, "HeldExpr", None],
      HoldComplete[_]];
    lastProviderRespRaw = If[AssociationQ[rt],
      Lookup[rt, "LastProviderResponse", None], None];
    providerRespHead = Which[
      StringQ[lastProviderRespRaw],
        StringTake[lastProviderRespRaw, UpTo[500]],
      AssociationQ[lastProviderRespRaw],
        Module[{r = Lookup[lastProviderRespRaw, "response",
                  ToString[lastProviderRespRaw]]},
          If[!StringQ[r], r = ToString[lastProviderRespRaw]];
          StringTake[r, UpTo[500]]],
      True,
        ToString[Short[lastProviderRespRaw, 5]]];
    diagInfo = <|
      "HeldExprFound"            -> heldExprFound,
      "LastProviderResponseHead" -> providerRespHead,
      "HasProposal"              -> TrueQ[Lookup[lastProposal, "HasProposal", False]],
      "HasToolUse"               -> TrueQ[Lookup[lastProposal, "HasToolUse", False]],
      "ParseMode"                -> Lookup[lastProposal, "ParseMode", "Default"],
      "ParseEnhanced"            -> TrueQ[Lookup[lastProposal,
                                            "ParseEnhanced", False]]|>;   (* T12 *)
    
    If[verbose,
      (
        Print["  [commit] sub-DAG complete: outcome=", outcome,
          " cellsBefore=", cellsBefore,
          " cellsAfter=", cellsAfter,
          " cellsDelta=", cellsDelta,
          " heldExprFound=", heldExprFound];
        If[outcome =!= "Done" && AssociationQ[failureDetail] &&
           Length[failureDetail] > 0,
          Print[Style["    reason: " <>
            ToString[Lookup[failureDetail, "ReasonClass", "?"]] <>
            " - " <> ToString[
              StringTake[ToString[Lookup[failureDetail, "Error", "?"]], UpTo[120]]],
            Red]]]
      )];
    
    (* v2026-04-20 T10: outcome === "Done" \:3067 cellsDelta <= 0 \:306e\:3068\:304d\:3001
       deterministicFallback \:304c True \:306a\:3089\:3001\:540c\:671f\:7248 iCommitArtifactsOnce
       \:3068\:540c\:69d8\:306e fallback (iAttemptCommitFallback) \:3092\:8a66\:3059\:3002
       2 \:6bb5\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af: iDeterministicSlideCommit \:2192 iGenericPayloadCommit
       \:3053\:308c\:307e\:3067 deferred \:7d4c\:8def\:306b\:306f\:3053\:306e fallback \:304c\:5b58\:5728\:305b\:305a\:3001
       LLM \:7d4c\:7531\:5931\:6557\:6642\:306b\:30c8\:30fc\:30bf\:30eb\:306a\:7121\:64cd\:4f5c\:306b\:306a\:3063\:3066\:3044\:305f\:3002 
       
       v2026-04-20 T14: T10/T11 fallback \:306e\:524d\:306b\:3001\:307e\:305a
       iAttemptDirectLLMCodeRescue \:3092\:8a66\:3059\:3002 LastProviderResponse \:306b
       multi-line code block \:304c\:3042\:308c\:3070\:3001 [\\s\\S]*? regex \:3067\:62bd\:51fa\:3057\:3001
       ToExpression \:2192 iRewriteCommitterHeldExpr \:2192 ReleaseHold \:3067\:76f4\:63a5\:5b9f\:884c\:3059\:308b\:3002
       \:3053\:308c\:3067 parseFn \:304c adapter \:306b\:5165\:3063\:3066\:3044\:306a\:3044\:30b1\:30fc\:30b9 (T13 \:4ee5\:524d\:306e
       \:8a2d\:8a08\:4e0a\:306e\:9650\:754c) \:3082\:6557\:308f\:3055\:308c\:308b\:3002\:6210\:529f\:6642\:306f Mode = "DeferredDirectLLM"\:3002 *)
    fallbackUsed = "None";
    fallbackResult = <||>;
    fallbackCells = 0;
    cellsAfterFb = cellsAfter;
    cellsDeltaFb = cellsDelta;
    directRescueResult = <||>;   (* T15: T14 の生の戻り値を退避 *)
    
    If[outcome === "Done" && cellsDelta <= 0 &&
       TrueQ[deterministicFallback] &&
       MatchQ[targetNb, _NotebookObject],
      (
        (* T14: \:307e\:305a LLM \:5fdc\:7b54\:306e multi-line code block \:3092\:76f4\:63a5\:5b9f\:884c\:3057\:3066\:307f\:308b *)
        If[verbose,
          Print[Style[
            "  [commit] T14 direct rescue: trying iAttemptDirectLLMCodeRescue " <>
            "from LastProviderResponse.",
            Italic, GrayLevel[0.4]]]];
        directRescueResult = Quiet @ Check[
          iAttemptDirectLLMCodeRescue[targetNb, lastProviderRespRaw],
          <|"Used" -> "None", "CellsWritten" -> 0,
            "Status" -> "Failed",
            "Error" -> "iAttemptDirectLLMCodeRescueThrew"|>];
        If[!AssociationQ[directRescueResult],
          directRescueResult = <|"Used" -> "None", "CellsWritten" -> 0,
            "Status" -> "Failed"|>];
        fallbackResult = directRescueResult;   (* T14 \:6210\:529f\:6642\:306f\:3053\:308c\:304c\:4f7f\:308f\:308c\:308b *)
        fallbackUsed  = Lookup[fallbackResult, "Used", "None"];
        fallbackCells = Lookup[fallbackResult, "CellsWritten", 0];
        If[!IntegerQ[fallbackCells], fallbackCells = 0];
        cellsAfterFb  = Quiet @ Check[
          Length[Cells[targetNb]], cellsAfter];
        cellsDeltaFb  = cellsAfterFb - cellsBefore;
        If[verbose,
          Print[Style[
            "  [commit] T14 direct rescue: used=" <> ToString[fallbackUsed] <>
            " status=" <> ToString[Lookup[fallbackResult, "Status", "?"]] <>
            " cellsWritten=" <> ToString[fallbackCells] <>
            " cellsDeltaAfter=" <> ToString[cellsDeltaFb],
            Italic, GrayLevel[0.4]]]];
        
        (* T14 \:304c\:5931\:6557\:307e\:305f\:306f code block \:7121\:3057\:3060\:3063\:305f\:5834\:5408\:3001
           T10 \:306e iAttemptCommitFallback (slide -> generic) \:306b\:5012\:308c\:3066\:307f\:308b\:3002
           T14 \:304c\:6210\:529f (CellsWritten > 0) \:3057\:305f\:5834\:5408\:306f\:3001 fallback \:306f\:30b9\:30ad\:30c3\:30d7\:3002 *)
        If[fallbackCells === 0,
          (
            If[verbose,
              Print[Style[
                "  [commit] T10 fallback: T14 returned 0 cells; " <>
                "trying iAttemptCommitFallback (slide -> generic).",
                Italic, GrayLevel[0.4]]]];
            fallbackResult = Quiet @ Check[
              iAttemptCommitFallback[targetNb, reducedArtifact],
              <|"Used" -> "None", "CellsWritten" -> 0,
                "Status" -> "Failed",
                "Error" -> "iAttemptCommitFallbackThrew"|>];
            If[!AssociationQ[fallbackResult],
              fallbackResult = <|"Used" -> "None", "CellsWritten" -> 0,
                "Status" -> "Failed"|>];
            fallbackUsed  = Lookup[fallbackResult, "Used", "None"];
            fallbackCells = Lookup[fallbackResult, "CellsWritten", 0];
            If[!IntegerQ[fallbackCells], fallbackCells = 0];
            cellsAfterFb  = Quiet @ Check[
              Length[Cells[targetNb]], cellsAfter];
            cellsDeltaFb  = cellsAfterFb - cellsBefore;
            If[verbose,
              Print[Style[
                "  [commit] T10 fallback: used=" <> ToString[fallbackUsed] <>
                " cellsWritten=" <> ToString[fallbackCells] <>
                " cellsDeltaAfter=" <> ToString[cellsDeltaFb],
                Italic, GrayLevel[0.4]]]]
          )]
      )];
    
    (* v2026-04-20 T09 + T10 + T11: Done \:3067 cellsDelta > 0 \:306f\:6210\:529f\:3002
       cellsDelta <= 0 \:3067\:3082 fallback \:5f8c\:306b\:30bb\:30eb\:304c\:589e\:3048\:305f\:306a\:3089
         "Committed" + Mode "DeferredFallback" \:3068\:3057\:3066\:6271\:3046\:3002
       
       T11 (2026-04-20 evening): \:5224\:5b9a\:6761\:4ef6\:3092 cellsDeltaFb > 0 \:304b\:3089
         (cellsDeltaFb > 0 || fallbackCells > 0) \:306b\:5909\:66f4\:3002
       
       \:7406\:7531: ScheduledTask \:5185\:3067 NotebookWrite \:3092\:547c\:3093\:3060\:76f4\:5f8c\:306b
         Length[Cells[targetNb]] \:3092\:30dd\:30fc\:30ea\:30f3\:30b0\:3057\:3066\:3082\:3001FrontEnd \:901a\:4fe1\:304c
         async \:306a\:305f\:3081 cells \:6570\:304c\:307e\:3060\:66f4\:65b0\:3055\:308c\:3066\:3044\:306a\:3044\:30b1\:30fc\:30b9\:304c\:3042\:308b\:3002
         (test14b \:3067\:5b9f\:969b\:306b\:78ba\:8a8d: fallback \:304c 12 \:30bb\:30eb\:66f8\:304d\:8fbc\:307e\:308c\:3066\:3044\:308b\:306e\:306b
          Length[Cells[]] \:306f\:5909\:308f\:3089\:305a cellsAfter == cellsBefore\:3002)
         iAttemptCommitFallback \:306e\:81ea\:5df1\:7533\:544a\:5024 (fallbackCells) \:3092\:4fe1\:7528\:3057\:3001
         \:30bb\:30eb\:6570\:304c\:5897\:3048\:305f\:3053\:3068\:306b\:3059\:308b\:3002
       
       \:5831\:544a\:5024\:306e\:88dc\:6b63: CellsAfter \:3068 CellsDelta \:306f max(cellsAfterFb,
         cellsBefore + fallbackCells) \:3068 fallbackCells \:3092\:4f7f\:3046\:3002
       \:6700\:7d42\:7684\:306b fallbackCells == 0 \:304b\:3064 cellsDeltaFb == 0 \:306a\:3089 NoWrite \:3092\:8fd4\:3059\:3002 *)
    effectiveCellsAfter = Max[cellsAfterFb,
      cellsBefore + fallbackCells];
    effectiveCellsDelta = Max[cellsDeltaFb, fallbackCells];
    
    commitResult = Which[
      outcome === "Done" && cellsDelta > 0,
        <|"Status"      -> "Committed",
          "Mode"        -> "DeferredDirect",
          "RuntimeId"   -> rid,
          "SubJobId"    -> sjid,
          "CellsBefore" -> cellsBefore,
          "CellsAfter"  -> cellsAfter,
          "CellsDelta"  -> cellsDelta,
          "Diagnostics" -> diagInfo,
          "Details"     -> sjid|>,
      
      (* v2026-04-20 T11: cellsDeltaFb \:307e\:305f\:306f fallbackCells \:306e
         \:3044\:305a\:308c\:304b\:304c\:6b63\:306a\:3089 fallback \:6210\:529f\:3002
         v2026-04-20 T14: fallbackUsed == "DirectLLM" \:306a\:3089
         Mode \:3092 "DeferredDirectLLM" \:306b\:5909\:3048\:3066\:5831\:544a\:3002
         v2026-04-20 T15: DirectRescueResult \:3092\:5225\:30ad\:30fc\:3067\:4fdd\:6301\:3057\:3001
         T14 \:306e\:8a3a\:65ad\:60c5\:5831\:3092\:5931\:308f\:306a\:3044\:3002 *)
      outcome === "Done" && cellsDelta <= 0 &&
        (cellsDeltaFb > 0 || fallbackCells > 0),
        <|"Status"               -> "Committed",
          "Mode"                 -> If[fallbackUsed === "DirectLLM",
                                       "DeferredDirectLLM",
                                       "DeferredFallback"],
          "RuntimeId"            -> rid,
          "SubJobId"             -> sjid,
          "CellsBefore"          -> cellsBefore,
          "CellsAfter"           -> effectiveCellsAfter,
          "CellsDelta"           -> effectiveCellsDelta,
          "CellsAfterObserved"   -> cellsAfterFb,
          "CellsDeltaObserved"   -> cellsDeltaFb,
          "FallbackUsed"         -> fallbackUsed,
          "FallbackCellsWritten" -> fallbackCells,
          "FallbackResult"       -> fallbackResult,
          "DirectRescueResult"   -> directRescueResult,   (* T15 *)
          "Diagnostics"          -> diagInfo,
          "Details"              -> sjid|>,
      
      outcome === "Done" && cellsDelta <= 0,
        <|"Status"               -> "NoWrite",
          "Mode"                 -> "DeferredDirect",
          "RuntimeId"            -> rid,
          "SubJobId"             -> sjid,
          "CellsBefore"          -> cellsBefore,
          "CellsAfter"           -> cellsAfter,
          "CellsDelta"           -> 0,
          "Reason"               -> "NoCellsWritten",
          "FallbackUsed"         -> fallbackUsed,
          "FallbackCellsWritten" -> fallbackCells,
          "FallbackResult"       -> fallbackResult,
          "DirectRescueResult"   -> directRescueResult,   (* T15 *)
          "Diagnostics"          -> diagInfo,
          "Hint"                 -> iL[
            "Runtime \:306f\:6b63\:5e38\:7d42\:4e86\:3057\:305f\:304c notebook \:306b\:66f8\:304d\:8fbc\:307f\:304c\:884c\:308f\:308c\:307e\:305b\:3093\:3067\:3057\:305f\:3002 " <>
              "T10 fallback (slide -> generic) \:3082\:30bb\:30eb\:3092\:751f\:6210\:3057\:307e\:305b\:3093\:3067\:3057\:305f " <>
              "(payload \:7a7a\:307e\:305f\:306f\:8a8d\:8b58\:4e0d\:80fd\:5f62\:5f0f)\:3002 " <>
              "Diagnostics \[Rule] HeldExprFound / LastProviderResponseHead \:3092\:78ba\:8a8d\:3057\:3066\:304f\:3060\:3055\:3044\:3002 " <>
              "Claude CLI (Model -> Automatic) \:3067\:8a66\:3059\:304b\:3001" <>
              "ClaudeRuntime`ClaudeRuntimeRetry[\"" <> rid <> "\"] \:3067\:518d\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
            "Runtime completed successfully but no cells were written. " <>
              "T10 fallback (slide -> generic) also produced no cells " <>
              "(empty payload or unrecognized shape). " <>
              "Inspect Diagnostics->HeldExprFound / LastProviderResponseHead. " <>
              "Try Model -> Automatic (Claude CLI), or retry with " <>
              "ClaudeRuntime`ClaudeRuntimeRetry[\"" <> rid <> "\"]."]|>,
      
      True,
        <|"Status"        -> If[outcome === "Failed", "Failed", outcome],
          "Reason"        -> Lookup[failureDetail, "ReasonClass",
                               If[outcome === "Timeout", "Timeout", outcome]],
          "FailureDetail" -> failureDetail,
          "RuntimeId"     -> rid,
          "SubJobId"      -> sjid,
          "DAGStatus"     -> subStatus,
          "CellsBefore"   -> cellsBefore,
          "CellsAfter"    -> cellsAfter,
          "CellsDelta"    -> cellsDelta,
          "Diagnostics"   -> diagInfo,
          "Hint"          -> iL[
            "ClaudeRuntime`ClaudeRuntimeRetry[\"" <> rid <>
              "\"] \:3067\:5931\:6557\:30ce\:30fc\:30c9\:304b\:3089\:518d\:5b9f\:884c\:3001\:307e\:305f\:306f ClaudeRuntime`ClaudeRuntimeCancel[\"" <>
              rid <> "\"] \:3067\:4e2d\:6b62\:3002",
            "ClaudeRuntime`ClaudeRuntimeRetry[\"" <> rid <>
              "\"] to retry failed nodes, or ClaudeRuntime`ClaudeRuntimeCancel[\"" <>
              rid <> "\"] to abort."]|>];
    
    iOrchSet[orchId, <|"CommitResult" -> commitResult|>];
    commitResult
  ];

(* ──────────────────────────────────────────────
   iSpawnWorkersDAGAsync: iSpawnWorkersDAG の非ブロッキング版
   
   完了時は onCompleteOuter[spawnResult_Association] を呼ぶ。
   戻り値は spawnJobId。Pause ベースの待機なし。
   ────────────────────────────────────────────── *)

iSpawnWorkersDAGAsync[sortedTasks_List, builder_, queryFn_,
    cfg_Association, onCompleteOuter_] :=
  Module[{nodes = <||>, jobId, maxParallel, jsonRetryMax, verbose,
          prevArtifacts, t, tid, deps, sessionTag, refText, dagAvail},
    maxParallel   = Lookup[cfg, "MaxParallelism", 1];
    jsonRetryMax  = Lookup[cfg, "JSONRetryMax", 1];
    verbose       = TrueQ[Lookup[cfg, "Verbose", False]];
    prevArtifacts = Lookup[cfg, "ArtifactAccumulator", <||>];
    refText       = Lookup[cfg, "ReferenceText", None];
    sessionTag    = Lookup[cfg, "SessionTag",
      "orch-" <> ToString[Floor[AbsoluteTime[]]] <>
        "-" <> ToString[RandomInteger[99999]]];
    
    dagAvail = Quiet @ Check[
      ValueQ[ClaudeCode`LLMGraphDAGCreate] ||
        Length[DownValues[ClaudeCode`LLMGraphDAGCreate]] > 0,
      False];
    If[!dagAvail,
      (* DAG 基盤が無い環境はフォールバック (純同期)。 *)
      Module[{fbRes},
        fbRes = iSpawnWorkersFallback[sortedTasks, builder, queryFn,
          cfg, prevArtifacts];
        onCompleteOuter[fbRes];
        Return["sync-fallback-" <> sessionTag]]];
    
    (* ノード構築: iSpawnWorkersDAG と同じパターン。
       Phase 34 T02: worker ノードの起動ハンドラを iLaunchSingleWorker に
       差し替える。条件不一致時は iRunSingleWorkerSync に fallback。 *)
    Do[
      tid  = Lookup[t, "TaskId", ""];
      deps = Lookup[t, "DependsOn", {}];
      With[{ttask = t, ttid = tid, tdeps = deps,
            tbuilder = builder, tqueryFn = queryFn,
            tjsonRetry = jsonRetryMax,
            tprevArtifacts = prevArtifacts,
            trefText = refText},
        nodes[ttid] = ClaudeCode`iLLMGraphNode[
          ttid, "sync", "worker", tdeps,
          Function[{job},
            iLaunchSingleWorker[ttask, tbuilder, tqueryFn,
              iCollectDepArtifactsFromJob[job, tdeps, tprevArtifacts],
              tjsonRetry, trefText]]]],
      {t, sortedTasks}];
    
    If[verbose,
      Print["  [dag-spawn-async] ", Length[nodes],
        " nodes, MaxParallelism=", maxParallel]];
    
    (* DAG 起動。onComplete で artifact を組み立てて outer callback を呼ぶ。 *)
    With[{pa = prevArtifacts, st = sortedTasks, ocb = onCompleteOuter},
      jobId = Quiet @ Check[
        ClaudeCode`LLMGraphDAGCreate[<|
          "nodes"          -> nodes,
          "taskDescriptor" -> <|
            "name"           -> "ClaudeSpawnWorkers (DAG Async)",
            "categoryMap"    -> <|"worker" -> "sync"|>,
            "maxConcurrency" -> <|"sync" -> maxParallel|>
          |>,
          "context"    -> <|"orchestratorJob" -> "spawn-dag-async",
                            "SessionTag"     -> sessionTag|>,
          "onComplete" -> Function[{job},
            Module[{artifacts = pa, failures = {}, tt, tid2, n, art,
                    status, spawnResult},
              Do[
                tid2 = Lookup[tt, "TaskId", ""];
                n    = Lookup[Lookup[job, "nodes", <||>], tid2, <||>];
                art  = Lookup[n, "result", None];
                If[AssociationQ[art],
                  artifacts[tid2] = art;
                  If[Lookup[art, "Status", ""] =!= "Success",
                    AppendTo[failures,
                      <|"TaskId" -> tid2,
                        "Error"  -> "ArtifactExtractionFailed",
                        "Details"-> Lookup[art, "Diagnostics", <||>]|>]],
                  artifacts[tid2] = <|"TaskId" -> tid2,
                    "Status" -> "Failed",
                    "ArtifactType" -> Lookup[tt, "ExpectedArtifactType", "Error"],
                    "Payload" -> <||>,
                    "Diagnostics" -> <|"NodeStatus" -> Lookup[n, "status", "?"],
                                        "NodeError"  -> Lookup[n, "error", "?"]|>|>;
                  AppendTo[failures,
                    <|"TaskId" -> tid2, "Error" -> "DAGNodeFailed"|>]],
                {tt, st}];
              status = Which[
                Length[failures] === 0, "Complete",
                Length[artifacts] > Length[pa], "Partial",
                True, "Failed"];
              spawnResult = <|
                "Artifacts" -> artifacts,
                "Failures"  -> failures,
                "Status"    -> status,
                "DAGJobId"  -> Lookup[job, "jobId", ""]|>;
              (* outer callback へ結果を渡す。内部で例外が起きても
                 orchestration 状態が「宙ぶらりん」にならないよう Quiet+Check。 *)
              Quiet @ Check[ocb[spawnResult], Null]]]
        |>],
        $Failed]];
    
    If[jobId === $Failed,
      (* DAG 起動に失敗したら即フォールバックで回す。 *)
      Module[{fbRes},
        fbRes = iSpawnWorkersFallback[sortedTasks, builder, queryFn,
          cfg, prevArtifacts];
        onCompleteOuter[fbRes];
        Return["sync-fallback-" <> sessionTag]]];
    
    jobId
  ];

(* ──────────────────────────────────────────────
   コールバックチェーン
   ────────────────────────────────────────────── *)

(* Plan 完了時 *)
iOnPlanComplete[orchId_String, planJob_Association] :=
  Module[{state, planNode, planResult, tasks, optsList, builderSpec,
          queryFn, verbose, cfg, sortedTasks, spawnJobId},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Null]];
    
    planNode   = Lookup[Lookup[planJob, "nodes", <||>], "plan", <||>];
    planResult = Lookup[planNode, "result", Lookup[state, "PlanResult", <||>]];
    If[!AssociationQ[planResult], planResult = <||>];
    
    optsList = Lookup[state, "OptionsList", {}];
    verbose  = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "Verbose"]];
    
    If[Lookup[planResult, "Status", ""] =!= "Planned",
      iOrchSet[orchId, <|"Status"      -> "Failed",
                         "Phase"       -> "Plan",
                         "FinalStatus" -> "PlanningFailed",
                         "EndTime"     -> AbsoluteTime[]|>];
      iOnOrchestrationComplete[orchId];
      Return[Null]];
    
    tasks = Lookup[planResult, "Tasks", {}];
    If[verbose,
      Print["[orchestration] Phase A done: ", Length[tasks], " tasks"]];
    
    (* v2026-04-20: builder spec は解決せずそのまま渡す。
       "LLM" / Automatic / 関数 のいずれも iRunSingleWorkerSync が
       内部で識別して処理する (既存の iSpawnWorkersDAG と同じ流儀)。 *)
    builderSpec = OptionValue[ClaudeRunOrchestration, optsList, "WorkerAdapterBuilder"];
    queryFn     = OptionValue[ClaudeRunOrchestration, optsList, "QueryFunction"];
    
    sortedTasks = Quiet @ Check[iTopologicalSortTasks[tasks], tasks];
    If[!ListQ[sortedTasks] || sortedTasks === $Failed,
      sortedTasks = tasks];
    
    cfg = <|
      "MaxParallelism" -> OptionValue[ClaudeRunOrchestration, optsList, "MaxParallelism"],
      "JSONRetryMax"   -> OptionValue[ClaudeRunOrchestration, optsList, "JSONRetryMax"],
      "Verbose"        -> verbose,
      "ReferenceText"  -> OptionValue[ClaudeRunOrchestration, optsList, "ReferenceText"],
      "SessionTag"     -> "orch-" <> orchId
    |>;
    
    iOrchSet[orchId, <|"Status" -> "Spawning", "Phase" -> "Spawn"|>];
    If[verbose, Print["[orchestration] Phase B: Worker Execution (async)"]];
    
    With[{oid = orchId},
      spawnJobId = iSpawnWorkersDAGAsync[sortedTasks,
        builderSpec, queryFn, cfg,
        Function[{sr}, iOnSpawnComplete[oid, sr]]]];
    
    iOrchSet[orchId, <|"SpawnJobId" -> spawnJobId|>];
    Null
  ];

(* Spawn 完了時 *)
iOnSpawnComplete[orchId_String, spawnResult_Association] :=
  Module[{state, optsList, verbose, reduceJobId},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Null]];
    
    iOrchSet[orchId, <|"SpawnResult" -> spawnResult,
                       "Phase"       -> "Reduce",
                       "Status"      -> "Reducing"|>];
    
    optsList = Lookup[state, "OptionsList", {}];
    verbose  = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "Verbose"]];
    If[verbose,
      Print["[orchestration] Phase B done: status=",
        Lookup[spawnResult, "Status", "?"]]];
    
    (* Reduce を単一 sync ノードの DAG として起動。 *)
    With[{oid = orchId},
      reduceJobId = Quiet @ Check[
        ClaudeCode`LLMGraphDAGCreate[<|
          "nodes" -> <|
            "reduce" -> ClaudeCode`iLLMGraphNode[
              "reduce", "sync", "orch-reduce", {},
              Function[{job}, iLaunchReducePhase[oid]]]
          |>,
          "taskDescriptor" -> <|"name" -> "Orchestration Reduce",
            "categoryMap" -> <|"orch-reduce" -> "sync"|>|>,
          "onComplete" -> Function[{job},
            iOnReduceComplete[oid, job]]
        |>],
        $Failed]];
    
    If[reduceJobId === $Failed,
      (* DAG が無ければ直接呼ぶ *)
      iRunReducePhaseSync[orchId];
      iOnReduceCompleteDirect[orchId],
      iOrchSet[orchId, <|"ReduceJobId" -> reduceJobId|>]];
    Null
  ];

(* Reduce 完了時 *)
iOnReduceComplete[orchId_String, reduceJob_Association] :=
  iOnReduceCompleteDirect[orchId];

iOnReduceCompleteDirect[orchId_String] :=
  Module[{state, optsList, skipCommit, targetNb, verbose, commitJobId},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Null]];
    
    optsList   = Lookup[state, "OptionsList", {}];
    skipCommit = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "SkipCommit"]];
    targetNb   = iResolveTargetNotebookAuto[
      OptionValue[ClaudeRunOrchestration, optsList, "TargetNotebook"]];
    verbose    = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "Verbose"]];
    
    iOrchSet[orchId, <|"Phase" -> "Commit", "Status" -> "Committing"|>];
    If[verbose, Print["[orchestration] Phase C done"]];
    
    If[skipCommit || targetNb === None,
      (* Commit スキップ: 直接完了 *)
      iOrchSet[orchId,
        <|"CommitResult" -> <|"Status" -> "Skipped"|>|>];
      iOnCommitCompleteDirect[orchId];
      Return[Null]];
    
    With[{oid = orchId},
      commitJobId = Quiet @ Check[
        ClaudeCode`LLMGraphDAGCreate[<|
          "nodes" -> <|
            "commit" -> ClaudeCode`iLLMGraphNode[
              "commit", "sync", "orch-commit", {},
              (* v2026-04-20 T07 (Stage 3): iRunCommitPhaseSync \:2192 iLaunchCommitPhase\:3002
                 iLaunchCommitPhase \:306f subJobId \:3092 runState \:3067\:8fd4\:3057\:3001
                 iLLMGraphDAGTick \:304c sub-DAG \:5b8c\:4e86\:3092\:30dd\:30fc\:30ea\:30f3\:30b0\:3059\:308b
                 (tick \:306f\:30d6\:30ed\:30c3\:30af\:3057\:306a\:3044)\:3002 *)
              Function[{job}, iLaunchCommitPhase[oid]]]
          |>,
          "taskDescriptor" -> <|"name" -> "Orchestration Commit",
            "categoryMap" -> <|"orch-commit" -> "sync"|>|>,
          "onComplete" -> Function[{job},
            iOnCommitComplete[oid, job]]
        |>],
        $Failed]];
    
    If[commitJobId === $Failed,
      iRunCommitPhaseSync[orchId];
      iOnCommitCompleteDirect[orchId],
      iOrchSet[orchId, <|"CommitJobId" -> commitJobId|>]];
    Null
  ];

(* Commit 完了時 *)
iOnCommitComplete[orchId_String, commitJob_Association] :=
  iOnCommitCompleteDirect[orchId];

iOnCommitCompleteDirect[orchId_String] :=
  iOnOrchestrationComplete[orchId];

(* 最終完了処理: Status を確定させ、notebook に軽い完了通知を出す *)
iOnOrchestrationComplete[orchId_String] :=
  Module[{state, spawnResult, commitResult, finalStatus, verbose,
          optsList, targetNb},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Null]];
    
    spawnResult  = Lookup[state, "SpawnResult", <||>];
    commitResult = Lookup[state, "CommitResult", <||>];
    optsList     = Lookup[state, "OptionsList", {}];
    verbose      = TrueQ[OptionValue[ClaudeRunOrchestration, optsList, "Verbose"]];
    targetNb     = iResolveTargetNotebookAuto[
      OptionValue[ClaudeRunOrchestration, optsList, "TargetNotebook"]];
    
    finalStatus = Which[
      Lookup[state, "FinalStatus", None] === "PlanningFailed",
        "PlanningFailed",
      Lookup[commitResult, "Status", ""] === "Failed" ||
        Lookup[commitResult, "Status", ""] === "RolledBack" ||
        Lookup[commitResult, "Status", ""] === "Timeout",
        "CommitFailed",
      Lookup[spawnResult, "Status", ""] === "Failed",
        "SpawnFailed",
      Lookup[spawnResult, "Status", ""] === "Partial",
        "SpawnPartial",
      True,
        "Done"];
    
    iOrchSet[orchId, <|
      "Status"      -> If[finalStatus === "Done", "Done", "Failed"],
      "FinalStatus" -> finalStatus,
      "Phase"       -> "Complete",
      "EndTime"     -> AbsoluteTime[]|>];
    
    If[verbose,
      Print["[orchestration] Complete: ", finalStatus,
        " (", Round[AbsoluteTime[] - Lookup[state, "StartTime", AbsoluteTime[]], 0.1], "s)"]];
    
    (* 任意: 対象 notebook のステータスバーを軽く更新 *)
    If[targetNb =!= None && MatchQ[targetNb, _NotebookObject],
      Quiet[CurrentValue[targetNb, WindowStatusArea] =
        "ClaudeOrchestration: " <> finalStatus]];
    Null
  ];

(* ──────────────────────────────────────────────
   ClaudeRunOrchestrationAsync (公開エントリ)
   ────────────────────────────────────────────── *)

Options[ClaudeRunOrchestrationAsync] = Options[ClaudeRunOrchestration];

ClaudeRunOrchestrationAsync[input_, opts:OptionsPattern[]] :=
  Module[{orchId, planJobId, optsList, verbose, model, queryFn, wrappedQueryFn},
    optsList = {opts};
    verbose  = TrueQ[OptionValue["Verbose"]];
    
    (* v2026-04-20 T08: Model \:30aa\:30d7\:30b7\:30e7\:30f3\:306e\:4f1d\:64ad\:2014
       optsList \:5185\:306e QueryFunction \:3092 wrapper \:3067\:7f6e\:304d\:63db\:3048\:3001\:5404 launcher \:306f
       \:5f93\:6765\:901a\:308a OptionValue[..., optsList, "QueryFunction"] \:3067\:53d6\:5f97\:3059\:308b\:3002
       Plan/Worker/Reduce \:306e async launcher \:306f\:300cqueryFn \:304c Automatic \:3067\:306a\:3044\:300d
       \:5834\:5408\:306b sync \:7248\:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3059\:308b\:306e\:3067\:3001Model \:6307\:5b9a\:6642\:306f
       \:81ea\:52d5\:7684\:306b\:540c\:671f sync \:7248\:3067\:5b9f\:884c\:3055\:308c\:308b\:3002 *)
    model   = OptionValue["Model"];
    queryFn = OptionValue["QueryFunction"];
    If[queryFn === Automatic && model =!= Automatic,
      With[{m = model},
        wrappedQueryFn = Function[prompt,
          ClaudeCode`ClaudeQuerySync[prompt, Model -> m]]];
      optsList = Append[
        FilterRules[optsList, Except["QueryFunction"]],
        "QueryFunction" -> wrappedQueryFn];
      If[verbose,
        Print[Style["[orchestration:async] Model -> " <>
          ToString[Short[model, 2]] <> " \:3067 QueryFunction wrapper \:3092\:9069\:7528\:3002",
          Italic, GrayLevel[0.4]]]]];
    
    orchId   = "orch-" <> ToString[Floor[AbsoluteTime[]]] <>
      "-" <> ToString[RandomInteger[999999]];
    
    iOrchSet[orchId, <|
      "OrchJobId"   -> orchId,
      "Status"      -> "Planning",
      "Phase"       -> "Plan",
      "Input"       -> input,
      "OptionsList" -> optsList,
      "StartTime"   -> AbsoluteTime[],
      "PlanResult"  -> None,
      "SpawnResult" -> None,
      "ReduceResult"-> None,
      "CommitResult"-> None,
      "FinalStatus" -> None
    |>];
    
    If[verbose, Print["[orchestration:async] start orchId=", orchId]];
    
    (* Plan を DAG で起動。fallback: DAG 不在時は同期で即走らせてチェーンを駆動。 *)
    With[{oid = orchId},
      planJobId = Quiet @ Check[
        ClaudeCode`LLMGraphDAGCreate[<|
          "nodes" -> <|
            "plan" -> ClaudeCode`iLLMGraphNode[
              "plan", "sync", "orch-plan", {},
              Function[{job}, iLaunchPlanPhase[oid]]]
          |>,
          "taskDescriptor" -> <|"name" -> "Orchestration Plan",
            "categoryMap" -> <|"orch-plan" -> "sync"|>|>,
          "onComplete" -> Function[{job},
            iOnPlanComplete[oid, job]]
        |>],
        $Failed]];
    
    If[planJobId === $Failed,
      (* DAG 無し: 従来同期実装を呼んでおく(このパスはテスト環境のみ)。 *)
      iRunPlanPhaseSync[orchId];
      iOnPlanComplete[orchId,
        <|"nodes" -> <|"plan" -> <|"result" -> iOrchGet[orchId]["PlanResult"]|>|>|>],
      iOrchSet[orchId, <|"PlanJobId" -> planJobId|>]];
    
    orchId
  ];

(* ──────────────────────────────────────────────
   状態参照 API
   ────────────────────────────────────────────── *)

ClaudeOrchestrationStatus[orchId_String] :=
  Module[{state},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Missing["NotFound", orchId]]];
    <|
      "OrchJobId"    -> orchId,
      "Status"       -> Lookup[state, "Status", "?"],
      "Phase"        -> Lookup[state, "Phase", "?"],
      "FinalStatus"  -> Lookup[state, "FinalStatus", None],
      "PlanJobId"    -> Lookup[state, "PlanJobId", None],
      "SpawnJobId"   -> Lookup[state, "SpawnJobId", None],
      "ReduceJobId"  -> Lookup[state, "ReduceJobId", None],
      "CommitJobId"  -> Lookup[state, "CommitJobId", None],
      "ElapsedSecs"  -> Round[
        AbsoluteTime[] - Lookup[state, "StartTime", AbsoluteTime[]], 0.1],
      "Done"         -> (Lookup[state, "Phase", ""] === "Complete")
    |>
  ];
ClaudeOrchestrationStatus[_] := Missing["InvalidArgument"];

ClaudeOrchestrationResult[orchId_String] :=
  Module[{state},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Missing["NotFound", orchId]]];
    If[Lookup[state, "Phase", ""] =!= "Complete",
      Return[Missing["NotComplete",
        Lookup[state, "Status", "?"] <> "/" <> Lookup[state, "Phase", "?"]]]];
    <|
      "Status"       -> Lookup[state, "FinalStatus", "?"],
      "OrchJobId"    -> orchId,
      "PlanResult"   -> Lookup[state, "PlanResult", <||>],
      "SpawnResult"  -> Lookup[state, "SpawnResult", <||>],
      "ReduceResult" -> Lookup[state, "ReduceResult", <||>],
      "CommitResult" -> Lookup[state, "CommitResult", <||>],
      "ElapsedSecs"  -> Round[
        Lookup[state, "EndTime", AbsoluteTime[]] -
          Lookup[state, "StartTime", AbsoluteTime[]], 0.1]
    |>
  ];
ClaudeOrchestrationResult[_] := Missing["InvalidArgument"];

(* テスト/スクリプト専用。対話セルでの使用は非推奨。 *)
ClaudeOrchestrationWait[orchId_String, timeoutSec_:300] :=
  Module[{waited = 0, step = 0.1, state, maxWait},
    maxWait = If[NumericQ[timeoutSec], timeoutSec, 300];
    While[waited < maxWait,
      state = iOrchGet[orchId];
      If[AssociationQ[state] && Lookup[state, "Phase", ""] === "Complete",
        Return[ClaudeOrchestrationResult[orchId]]];
      Pause[step]; waited += step];
    Missing["Timeout", orchId]
  ];

ClaudeOrchestrationCancel[orchId_String] :=
  Module[{state, planJid, spawnJid, reduceJid, commitJid},
    state = iOrchGet[orchId];
    If[!AssociationQ[state], Return[Missing["NotFound", orchId]]];
    planJid   = Lookup[state, "PlanJobId", None];
    spawnJid  = Lookup[state, "SpawnJobId", None];
    reduceJid = Lookup[state, "ReduceJobId", None];
    commitJid = Lookup[state, "CommitJobId", None];
    Scan[
      If[StringQ[#],
        Quiet @ Check[ClaudeCode`LLMGraphDAGCancel[#], Null]] &,
      {planJid, spawnJid, reduceJid, commitJid}];
    iOrchSet[orchId, <|"Status" -> "Cancelled",
                       "Phase"  -> "Complete",
                       "EndTime"-> AbsoluteTime[]|>];
    orchId
  ];

ClaudeOrchestrationJobs[] :=
  Module[{keys, rows},
    keys = Keys[$iClaudeOrchestrationJobs];
    If[Length[keys] === 0, Return[Dataset[{}]]];
    rows = Map[
      Function[k,
        Module[{s = $iClaudeOrchestrationJobs[k]},
          <|"OrchJobId"   -> k,
            "Status"      -> Lookup[s, "Status", "?"],
            "Phase"       -> Lookup[s, "Phase", "?"],
            "FinalStatus" -> Lookup[s, "FinalStatus", "-"],
            "ElapsedSecs" -> Round[
              Lookup[s, "EndTime", AbsoluteTime[]] -
                Lookup[s, "StartTime", AbsoluteTime[]], 0.1]|>]],
      keys];
    Dataset[rows]
  ];

(* ──────────────────────────────────────────────
   iOrchHookDispatch: $ClaudeEvalHook から呼ばれる共通ディスパッチ。
   
   $ClaudeOrchestratorAsyncMode の True/False に応じて
   ClaudeRunOrchestrationAsync (非同期) か ClaudeRunOrchestration (同期)
   に切り替える。async のときは "Status" -> "Pending" の Association を
   即時返し、ClaudeEval のフロントエンドブロックを回避する。
   ────────────────────────────────────────────── *)

iOrchHookDispatch[task_, targetNb_, refText_, verbose_, model_:Automatic] :=
  If[TrueQ[$ClaudeOrchestratorAsyncMode],
    Module[{orchId},
      orchId = Quiet @ Check[
        ClaudeRunOrchestrationAsync[task,
          "Planner"              -> "LLM",
          "WorkerAdapterBuilder" -> "LLM",
          "TargetNotebook"       -> targetNb,
          "ReferenceText"        -> refText,
          "Verbose"              -> verbose,
          "Model"                -> model],   (* v2026-04-20 T08 *)
        $Failed];
      If[!StringQ[orchId],
        $Failed,
        (
          If[verbose,
            Print[Style["[ClaudeEval\[Rule]Orchestrator] \:975e\:540c\:671f\:5b9f\:884c\:958b\:59cb orchJobId=" <> orchId,
              Italic, GrayLevel[0.4]]]];
          <|"Status"    -> "Pending",
            "Async"     -> True,
            "OrchJobId" -> orchId,
            "Hint"      -> "ClaudeOrchestrationStatus[\"" <> orchId <>
              "\"] \:3067\:72b6\:614b\:78ba\:8a8d\:3001ClaudeOrchestrationResult[...] \:3067\:7d50\:679c\:53d6\:5f97\:3002"|>
        )]],
    (* Sync mode: \:65e7\:632f\:308b\:821e\:3044 *)
    Quiet @ ClaudeRunOrchestration[task,
      "Planner"              -> "LLM",
      "WorkerAdapterBuilder" -> "LLM",
      "TargetNotebook"       -> targetNb,
      "ReferenceText"        -> refText,
      "Model"                -> model]];   (* v2026-04-20 T08 *)

(* iOrchHookResultOK: hook が受け取った result が「成功」扱いか。
   Async は "Pending" を成功とする (裏で実行継続中のため)。
   Sync は "Done" のみ成功とする。 *)
iOrchHookResultOK[result_] :=
  AssociationQ[result] &&
    MemberQ[{"Done", "Pending"}, Lookup[result, "Status", ""]];

(* ════════════════════════════════════════════════════════
   Startup
   ════════════════════════════════════════════════════════ *)

(* Phase 33 Task 5: ClaudeEval dispatch \:30d5\:30c3\:30af\:306e\:767b\:9332
   ClaudeCode \:306e $ClaudeEvalMode \:30b9\:30a4\:30c3\:30c1\:304c "Auto" / "Orchestrated" \:6642\:306b\:547c\:3070\:308c\:308b\:3002
   $Failed \:3092\:8fd4\:3057\:305f\:5834\:5408 ClaudeEval \:304c\:5f93\:6765\:306e Single \:30d1\:30b9\:306b\:81ea\:52d5\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3059\:308b\:3002 *)
If[Length[Names["ClaudeCode`$ClaudeEvalHook"]] > 0,
  ClaudeCode`$ClaudeEvalHook = Function[{task, mode, optsList},
    Module[{plan, tasks, threshold, targetNb, result, verbose, retval,
            refText, model},
      verbose = TrueQ[Quiet @ Check[ClaudeCode`$ClaudeEvalVerbose, False]];
      (* T08: caller \:304c optsList \:3067 "ReferenceText" \:3092\:6e21\:3059\:3068
         ClaudeRunOrchestration \:306b\:6e21\:3059\:3002 Slide \:4f5c\:6210\:6642\:306e\:30b5\:30f3\:30d7\:30eb\:672c\:6587\:6ce8\:5165\:306b\:4f7f\:3046\:3002 *)
      refText = Quiet @ Check[
        Module[{v}, v = OptionValue[optsList, {"ReferenceText"}, "ReferenceText"];
          If[v === "ReferenceText", None, v]],
        None];
      (* v2026-04-20 T08: ClaudeEval \:306e Model \:30aa\:30d7\:30b7\:30e7\:30f3\:3092 orchestration \:306b\:4f1d\:9054\:3002
         ClaudeEval \:306f\:300cModel\:300d\:3092 Options \:306b\:6301\:3064\:306e\:3067 OptionValue[ClaudeEval, ...] \:3067\:53d6\:308a\:51fa\:3059\:3002 *)
      model = Quiet @ Check[
        OptionValue[ClaudeCode`ClaudeEval, optsList, Model],
        Automatic];
      retval = $Failed;  (* \:30c7\:30d5\:30a9\:30eb\:30c8: \:5931\:6557 \:2192 Single \:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af *)
      Which[
        (* Orchestrated \:30e2\:30fc\:30c9: \:5e38\:306b Orchestration \:3092\:8d70\:3089\:305b\:308b *)
        mode === "Orchestrated",
          (* T07b: slide-intent \:6642\:306f\:65b0\:898f notebook \:3092\:4f5c\:308a\:3001\:4f5c\:696d nb \:3092\:6e29\:5b58 *)
          targetNb = Lookup[
            iResolveTargetNotebook[task, verbose],
            "TargetNotebook", None];
          If[verbose,
            Print[Style["[ClaudeEval\:2192Orchestrator] Orchestrated \:30e2\:30fc\:30c9\:3067 " <>
              If[TrueQ[$ClaudeOrchestratorAsyncMode],
                "ClaudeRunOrchestrationAsync", "ClaudeRunOrchestration"] <> " \:3092\:8d77\:52d5\:3002",
              Italic, GrayLevel[0.4]]]];
          (* v2026-04-20: AsyncMode \:5207\:308a\:66ff\:3048\:306b\:3088\:308a\:30d5\:30ed\:30f3\:30c8\:30a8\:30f3\:30c9\:30d6\:30ed\:30c3\:30af\:3092\:56de\:907f\:3002 *)
          result = iOrchHookDispatch[task, targetNb, refText, verbose, model];
          Which[
            result === $Failed || !AssociationQ[result] ||
              (AssociationQ[result] && Lookup[result, "Status", ""] === "PlanningFailed"),
              (
                If[verbose,
                  Print[Style["[ClaudeEval\:2192Orchestrator] Planning \:5931\:6557 \:2192 Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002",
                    Italic, GrayLevel[0.4]]]];
                retval = $Failed
              ),
            iOrchHookResultOK[result],
              retval = result,
            True,
              (
                Print[Style["[ClaudeEval\:2192Orchestrator] Orchestration \:306f Status=" <>
                  ToString[Lookup[result, "Status", "?"]] <> " \:3001Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3057\:307e\:3059\:3002",
                  RGBColor[0.8, 0.5, 0]]];
                retval = $Failed
              )],

        (* Auto \:30e2\:30fc\:30c9: \:30d2\:30e5\:30fc\:30ea\:30b9\:30c6\:30a3\:30c3\:30af\:30b2\:30fc\:30c8 \:2192 LLM planner \:2192 \:9589\:5024\:5224\:5b9a *)
        mode === "Auto",
          threshold = Quiet @ Check[ClaudeCode`$ClaudeEvalAutoThreshold, 3];
          If[!IntegerQ[threshold] || threshold < 2, threshold = 3];
          Module[{minLen, minNL, taskLen, nlCount, gatePass, taskStr},
            minLen = Quiet @ Check[ClaudeCode`$ClaudeEvalAutoLLMMinLength, 500];
            If[!IntegerQ[minLen] || minLen < 0, minLen = 500];
            minNL = Quiet @ Check[ClaudeCode`$ClaudeEvalAutoLLMMinNewlines, 3];
            If[!IntegerQ[minNL] || minNL < 0, minNL = 3];
            taskStr = If[StringQ[task], task, ToString[task]];
            taskLen = StringLength[taskStr];
            nlCount = StringCount[taskStr, "\n"];
            gatePass = (taskLen >= minLen) || (nlCount >= minNL);
            If[!gatePass,
              (* \:8efd\:91cf\:30bf\:30b9\:30af: planner \:3092\:547c\:3070\:305a\:306b\:5373 Single *)
              If[verbose,
                Print[Style["[ClaudeEval\:2192Orchestrator] Auto: len=" <>
                  ToString[taskLen] <> "<" <> ToString[minLen] <>
                  " && nl=" <> ToString[nlCount] <> "<" <> ToString[minNL] <>
                  " \:2192 LLM planner \:30b9\:30ad\:30c3\:30d7\:3001Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002",
                  Italic, GrayLevel[0.4]]]];
              retval = $Failed
              ,
              (* \:91cd\:91cf\:30bf\:30b9\:30af: LLM planner \:3092\:547c\:3076 *)
              If[verbose,
                Print[Style["[ClaudeEval\:2192Orchestrator] Auto: len=" <>
                  ToString[taskLen] <> "/" <> ToString[minLen] <>
                  " nl=" <> ToString[nlCount] <> "/" <> ToString[minNL] <>
                  " \:2192 LLM planner \:3092\:547c\:3073\:51fa\:3057\:3002",
                  Italic, GrayLevel[0.4]]]];
              (* T03: Check \:3092\:524a\:9664 (harmless Message \:3067\:8aa4 $Failed \:3092\:9632\:3050) *)
              plan = Quiet @ ClaudePlanTasks[task, "Planner" -> "LLM"];
              Which[
                plan === $Failed || !AssociationQ[plan] ||
                  Lookup[plan, "Status", ""] =!= "Planned",
                  (
                    If[verbose,
                      Print[Style["[ClaudeEval\:2192Orchestrator] Auto: ClaudePlanTasks(LLM) \:5931\:6557 \:2192 Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002",
                        Italic, GrayLevel[0.4]]]];
                    retval = $Failed
                  ),
                True,
                  tasks = Lookup[plan, "Tasks", {}];
                  Which[
                    !ListQ[tasks] || Length[tasks] < threshold,
                      (
                        If[verbose,
                          Print[Style["[ClaudeEval\:2192Orchestrator] Auto: Tasks=" <>
                            ToString[If[ListQ[tasks], Length[tasks], 0]] <>
                            " < threshold=" <> ToString[threshold] <>
                            " \:2192 Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002",
                            Italic, GrayLevel[0.4]]]];
                        retval = $Failed
                      ),
                    True,
                      (* T07b: slide-intent \:6642\:306f\:65b0\:898f notebook \:3092\:4f5c\:308a\:4f5c\:696d nb \:3092\:6e29\:5b58 *)
                      targetNb = Lookup[
                        iResolveTargetNotebook[task, verbose],
                        "TargetNotebook", None];
                      If[verbose,
                        Print[Style["[ClaudeEval\:2192Orchestrator] Auto: Tasks=" <>
                          ToString[Length[tasks]] <> " \:3001" <>
                          If[TrueQ[$ClaudeOrchestratorAsyncMode],
                            "ClaudeRunOrchestrationAsync", "ClaudeRunOrchestration"] <>
                          "(LLM planner) \:3092\:8d77\:52d5\:3002",
                          Italic, GrayLevel[0.4]]]];
                      (* v2026-04-20: AsyncMode \:5207\:308a\:66ff\:3048\:306b\:3088\:308a\:30d5\:30ed\:30f3\:30c8\:30a8\:30f3\:30c9\:30d6\:30ed\:30c3\:30af\:3092\:56de\:907f\:3002 *)
                      result = iOrchHookDispatch[task, targetNb, refText, verbose, model];
                      Which[
                        result === $Failed || !AssociationQ[result] ||
                          (AssociationQ[result] && Lookup[result, "Status", ""] === "PlanningFailed"),
                          (
                            If[verbose,
                              Print[Style["[ClaudeEval\:2192Orchestrator] Auto: Orchestration Planning \:5931\:6557 \:2192 Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3002",
                                Italic, GrayLevel[0.4]]]];
                            retval = $Failed
                          ),
                        iOrchHookResultOK[result],
                          retval = result,
                        True,
                          (
                            Print[Style["[ClaudeEval\:2192Orchestrator] Orchestration \:306f Status=" <>
                              ToString[Lookup[result, "Status", "?"]] <> " \:3001Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3057\:307e\:3059\:3002",
                              RGBColor[0.8, 0.5, 0]]];
                            retval = $Failed
                          )]]]]],

        True,
          retval = $Failed];

      retval]];

  (* Phase 33 Task 5: Orchestrator \:304c\:30ed\:30fc\:30c9\:3055\:308c\:305f\:3089\:81ea\:52d5\:7684\:306b Auto \:30e2\:30fc\:30c9\:306b\:5207\:308a\:66ff\:3048\:308b\:3002
     v2026-04-21 T19: \:30e6\:30fc\:30b6\:30fc\:660e\:793a\:4f9d\:983c\:306b\:3088\:308a "Auto" \:3092\:65e2\:5b9a\:5024\:3068\:3057\:3066
     \:5f37\:5236\:30bb\:30c3\:30c8\:3002 \:5f8c\:304b\:3089 "Single" / "Orchestrated" \:306b\:624b\:52d5\:5909\:66f4\:53ef\:80fd\:3002 *)
  ClaudeCode`$ClaudeEvalMode = "Auto";

  Print[Style[If[$Language === "Japanese",
    "ClaudeOrchestrator: $ClaudeEvalHook \:3092\:767b\:9332\:3057\:307e\:3057\:305f\:3002\
$ClaudeEvalMode = \"" <> ToString[ClaudeCode`$ClaudeEvalMode] <>
    "\"\:3001$ClaudeOrchestratorAsyncMode = " <>
    ToString[$ClaudeOrchestratorAsyncMode] <>
    "\:3002Single \:306b\:623b\:3059\:306b\:306f ClaudeCode`$ClaudeEvalMode = \"Single\"\:3001\
\:540c\:671f\:306b\:623b\:3059\:306b\:306f $ClaudeOrchestratorAsyncMode = False \:3068\:3059\:308b\:3002",
    "ClaudeOrchestrator: $ClaudeEvalHook registered. $ClaudeEvalMode = \"" <>
    ToString[ClaudeCode`$ClaudeEvalMode] <>
    "\", $ClaudeOrchestratorAsyncMode = " <>
    ToString[$ClaudeOrchestratorAsyncMode] <>
    ". Set $ClaudeEvalMode = \"Single\" to revert, or $ClaudeOrchestratorAsyncMode = False for sync."],
    Italic, GrayLevel[0.4]]]];

End[];
EndPackage[];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   ClaudeRuntime \:3092\:672a\:30ed\:30fc\:30c9\:306a\:3089\:3053\:3053\:3067\:30ed\:30fc\:30c9\:3059\:308b (v2026-04-18T01 fix)
   Orchestrator \:306f worker \:914d\:8eca\:6642\:306b ClaudeRuntime`CreateClaudeRuntime \:3092
   \:547c\:3076\:304c\:3001\:30ed\:30fc\:30c9\:3055\:308c\:3066\:3044\:306a\:3044\:3068\:30b7\:30f3\:30dc\:30eb\:304c\:672a\:8a55\:4fa1\:306e\:307e\:307e\:8fd4\:308a\:3001
   \:3059\:3079\:3066\:306e worker \:304c "CreateRuntimeFailed" \:3067\:843d\:3061\:308b\:3002
   Rule 11 \:4f9d\:5b58\:65b9\:5411\:5236\:7d04 (claudecode/NBAccess \:306f\:4ed6\:306b\:4f9d\:5b58\:3057\:306a\:3044) \:3068\:306f\:7121\:7dd1\:3067\:3001
   Orchestrator \:2192 Runtime \:306f\:8ad6\:7406\:7684\:306b\:8a31\:3055\:308c\:308b\:4f9d\:5b58\:3002
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)
(* v2026-04-18T02: Names \:30ac\:30fc\:30c9\:306f\:30dd\:30a4\:30b8\:30cd\:30eb \:2014 \:30bd\:30fc\:30b9\:5185\:306b
   ClaudeRuntime`CreateClaudeRuntime \:3068\:3044\:3046\:6587\:5b57\:5217\:304c\:51fa\:73fe\:3059\:308b\:3060\:3051\:3067
   \:30b7\:30f3\:30dc\:30eb\:306f parse \:6642\:306b\:81ea\:52d5\:751f\:6210\:3055\:308c\:3001 Names \:304c\:5e38\:306b\:975e\:7a7a\:306b\:306a\:308b\:3002
   \:305d\:306e\:305f\:3081 DownValues \:306e\:6709\:7121\:3067 \"\:5b9f\:88c5\:304c\:3042\:308b\" \:3092\:5224\:5b9a\:3059\:308b\:3002
   ClaudeRunTurn \:306f DownValues \:30d9\:30fc\:30b9\:3001 \$ClaudeRuntimeVersion \:306f OwnValues \:30d9\:30fc\:30b9\:3067\:78ba\:8a8d\:3002 *)
ClaudeOrchestrator`Private`iRuntimeLoadedQ[] :=
  (Length[DownValues[ClaudeRuntime`CreateClaudeRuntime]] > 0);

If[!ClaudeOrchestrator`Private`iRuntimeLoadedQ[],
  Module[{loaded = False},
    (* \:7b2c 1 \:624b: Needs \:3067 $Path \:4e0a\:306e ClaudeRuntime\` \:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:3092\:63a2\:3059 *)
    Quiet @ Check[
      Needs["ClaudeRuntime`"];
      loaded = ClaudeOrchestrator`Private`iRuntimeLoadedQ[],
      loaded = False];
    (* \:7b2c 2 \:624b: Needs \:3067 DownValues \:304c\:3064\:304b\:306a\:3051\:308c\:3070 Get \:3067\:76f4\:63a5\:30ed\:30fc\:30c9 *)
    If[!loaded,
      Quiet @ Check[
        Block[{$CharacterEncoding = "UTF-8"},
          Get["ClaudeRuntime.wl"]];
        loaded = ClaudeOrchestrator`Private`iRuntimeLoadedQ[],
        loaded = False]];
    If[!loaded,
      Print[Style[If[$Language === "Japanese",
        "ClaudeOrchestrator: ClaudeRuntime \:306e\:81ea\:52d5\:30ed\:30fc\:30c9\:306b\:5931\:6557\:3002Orchestration \:306f\:4f7f\:3048\:307e\:305b\:3093 (Single \:306f\:5f71\:97ff\:306a\:3057)\:3002",
        "ClaudeOrchestrator: Failed to auto-load ClaudeRuntime. Orchestration unavailable (Single unaffected)."],
        RGBColor[0.8, 0.5, 0]]],
      If[$Language === "Japanese",
        Print[Style["ClaudeOrchestrator: ClaudeRuntime \:3092\:81ea\:52d5\:30ed\:30fc\:30c9\:3057\:307e\:3057\:305f\:3002",
          Italic, GrayLevel[0.4]]],
        Print[Style["ClaudeOrchestrator: ClaudeRuntime auto-loaded.",
          Italic, GrayLevel[0.4]]]]]]];

Print[Style[If[$Language === "Japanese",
  "ClaudeOrchestrator パッケージがロードされました。(v" <>
    ClaudeOrchestrator`$ClaudeOrchestratorVersion <> ")",
  "ClaudeOrchestrator package loaded. (v" <>
    ClaudeOrchestrator`$ClaudeOrchestratorVersion <> ")"], Bold]];

Print[If[$Language === "Japanese", "
  ClaudePlanTasks[input]                      \[Rule] TaskSpec DAG \:751f\:6210
  ClaudePlanTasks[input, \"Planner\"->\"LLM\"]   \[Rule] LLM \:3067\:30bf\:30b9\:30af\:5206\:89e3 (Stage 2 / 3.5c \:65e5\:8a9e\:6700\:9069\:5316)
  ClaudeValidateTaskSpec[taskSpec]            \[Rule] TaskSpec \:691c\:8a3c
  ClaudeSpawnWorkers[tasksSpec]               \[Rule] artifact \:53ce\:96c6 (worker \:306f NotebookWrite \:7981\:6b62)
  ClaudeSpawnWorkers[ts, \"WorkerAdapterBuilder\"->\"LLM\",\n                      \"JSONRetryMax\"->2]
                                              \[Rule] LLM worker + JSON \:518d\:8a66\:884c (Stage 3.5a)
  ClaudeSpawnWorkers[ts, \"MaxParallelism\"->4] \[Rule] LLMGraphDAGCreate \:3067\:4e26\:5217\:914d\:8eca (Stage 3.5b)
  ClaudeCollectArtifacts[spawnResult]         \[Rule] artifact \:3092 Dataset \:306b\:6574\:5f62
  ClaudeValidateArtifact[artifact, schema]    \[Rule] OutputSchema \:6e96\:62e0\:30c1\:30a7\:30c3\:30af
  ClaudeReduceArtifacts[artifacts]            \[Rule] artifact \:7fa4\:3092\:7d71\:5408 (reducer)
  ClaudeCommitArtifacts[targetNb, reduced]    \[Rule] committer \:304c notebook \:306b\:53cd\:6620 (Stage 3 \:5b8c\:5168\:7248)
  ClaudeRunOrchestration[input]               \[Rule] Plan -> Spawn -> Reduce -> Commit
  ClaudeContinueBatch[rid, batches]           \[Rule] \:5358\:4e00 runtime \:3067\:6bb5\:968e\:5b9f\:884c (\:73fe\:5b9f\:89e3)
  
  Role: Explore / Plan / Draft / Verify / Reduce / Commit
  Worker \:306f $ClaudeOrchestratorDenyHeads \:306e head \:3092\:63d0\:6848\:3067\:304d\:306a\:3044\:3002
  \"QueryFunction\" -> fn \:3067 LLM \:547c\:3073\:51fa\:3057\:3092\:30ab\:30b9\:30bf\:30de\:30a4\:30ba\:53ef\:80fd\:3002
  Stage 3: committer \:306f EvaluationNotebook[] / CreateNotebook[...] \:3092 targetNb \:306b\:66f8\:63db\:3057\:3001
           \:305d\:306e\:4ed6\:306e nb \:8868\:8a18 (\:4f8b: \:7121\:4fee\:98fe nb) \:306f preserve \:3059\:308b (Stage 3.7)\:3002
  Stage 3.5a: LLM worker \:306f JSON \:30d1\:30fc\:30b9\:5931\:6557\:6642 \"JSONRetryMax\" \:307e\:3067\:5fdc\:7b54\:518d\:8981\:6c42\:3002
  Stage 3.5b: \"MaxParallelism\" > 1 \:307e\:305f\:306f \"UseDAG\" -> True \:3067 LLMGraphDAGCreate \:914d\:8eca\:3002
  Stage 3.5c: $Language === \"Japanese\" \:6642\:3001 LLM planner \:30d7\:30ed\:30f3\:30d7\:30c8\:3092\:65e5\:672c\:8a9e\:5316\:3002
  Stage 4: ClaudeCommitArtifacts[..., \"CommitMode\" -> \"Transactional\"] \:3067
           shadow buffer \:7d4c\:7531 commit (\:5931\:6557\:6642 rollback, spec \:00a712.3)\:3002
  Task 3: ClaudeReduceArtifacts[..., \"RetryMax\" -> N] \:3068
           ClaudeCommitArtifacts[..., \"CommitRetryMax\" -> N] \:3067\:518d\:8a66\:884c\:3092\:6709\:52b9\:5316\:3002
  Task 4: ClaudeSpawnWorkers[..., \"ParallelismMode\" -> \"CLIFork\"] \:3067
           \:5225\:30d7\:30ed\:30bb\:30b9 Claude CLI \:306b\:3088\:308b\:771f\:306e\:4e26\:5217\:5316 (\"CLICommand\" \:3067\:62bd\:8c61\:5316)\:3002
  Task 2: $ClaudeOrchestratorRealLLMEndpoint = \"ClaudeCode\"|\"CLI\"|fn \:307e\:305f\:306f
           \:74b0\:5883\:5909\:6570 CLAUDE_ORCH_REAL_LLM \:3067 real LLM \:7d71\:5408\:30c6\:30b9\:30c8\:3092\:6709\:52b9\:5316\:3002
  T10 (2026-04-20): deferred commit \:306b deterministic fallback \:3092\:5f90\:5fa9\:30fb\:62e1\:5f35\:3002
           LLM \:304c HeldExpr \:3092\:8fd4\:3055\:305a\:30bb\:30eb\:304c\:66f8\:304b\:308c\:306a\:3044\:5834\:5408\:3001
           iDeterministicSlideCommit \:2192 iGenericPayloadCommit \:306e\:9806\:3067\:81ea\:52d5\:88dc\:5b8c\:3002
           \"DeterministicFallback\" -> False \:3067\:7121\:52b9\:5316\:3001
           CommitResult[\"Diagnostics\"] \:306b HeldExprFound / LastProviderResponseHead \:304c\:4ed8\:5c5e\:3002
", "
  ClaudePlanTasks[input]                      \[Rule] Generate TaskSpec DAG
  ClaudePlanTasks[input, \"Planner\"->\"LLM\"]   \[Rule] LLM-backed task decomposition (Stage 2 / 3.5c JP-aware)
  ClaudeValidateTaskSpec[taskSpec]            \[Rule] Validate TaskSpec
  ClaudeSpawnWorkers[tasksSpec]               \[Rule] Collect artifacts (workers can't NotebookWrite)
  ClaudeSpawnWorkers[ts, \"WorkerAdapterBuilder\"->\"LLM\",\n                      \"JSONRetryMax\"->2]
                                              \[Rule] LLM workers + JSON retry (Stage 3.5a)
  ClaudeSpawnWorkers[ts, \"MaxParallelism\"->4] \[Rule] Parallel dispatch via LLMGraphDAGCreate (Stage 3.5b)
  ClaudeCollectArtifacts[spawnResult]         \[Rule] Format artifacts as Dataset
  ClaudeValidateArtifact[artifact, schema]    \[Rule] Check OutputSchema
  ClaudeReduceArtifacts[artifacts]            \[Rule] Merge artifacts (reducer)
  ClaudeCommitArtifacts[targetNb, reduced]    \[Rule] Committer writes to notebook (Stage 3 full)
  ClaudeRunOrchestration[input]               \[Rule] Plan -> Spawn -> Reduce -> Commit
  ClaudeContinueBatch[rid, batches]           \[Rule] Serial batch on single runtime (pragmatic)
  
  Roles: Explore / Plan / Draft / Verify / Reduce / Commit
  Workers cannot propose heads in $ClaudeOrchestratorDenyHeads.
  Use \"QueryFunction\" -> fn to customize LLM calls.
  Stage 3: committer rewrites EvaluationNotebook[] / CreateNotebook[...] to targetNb;
           other nb-like references (e.g., unqualified nb) are preserved (Stage 3.7).
  Stage 3.5a: LLM worker requests JSON repair up to \"JSONRetryMax\" attempts on parse failure.
  Stage 3.5b: \"MaxParallelism\" > 1 or \"UseDAG\" -> True dispatches via LLMGraphDAGCreate.
  Stage 3.5c: When $Language === \"Japanese\", LLM planner prompt is localized.
  Stage 4: ClaudeCommitArtifacts[..., \"CommitMode\" -> \"Transactional\"] stages
           writes to a shadow buffer, then verifies and flushes (spec \:00a712.3).
  Task 3: ClaudeReduceArtifacts[..., \"RetryMax\" -> N] and
          ClaudeCommitArtifacts[..., \"CommitRetryMax\" -> N] enable retry loops.
  Task 4: ClaudeSpawnWorkers[..., \"ParallelismMode\" -> \"CLIFork\"] spawns
          separate Claude CLI processes (\"CLICommand\" hook for testability).
  Task 2: Set $ClaudeOrchestratorRealLLMEndpoint = \"ClaudeCode\"|\"CLI\"|fn or
          env CLAUDE_ORCH_REAL_LLM to opt into real-LLM integration tests.
  T10 (2026-04-20): Deferred commit path now applies deterministic fallback.
          When the LLM returns no HeldExpr and no cells are written, we try
          iDeterministicSlideCommit -> iGenericPayloadCommit automatically.
          Disable with \"DeterministicFallback\" -> False.
          CommitResult[\"Diagnostics\"] carries HeldExprFound / LastProviderResponseHead.
"]];
