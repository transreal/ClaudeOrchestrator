(* ::Package:: *)

(* ::Title:: *)
(* ClaudeOrchestrator_turnwiki.wl *)

(* ::Subsection:: *)
(* 概要 *)

(* ════════════════════════════════════════════════════════════════════
   ClaudeOrchestrator_turnwiki.wl

   ClaudeOrchestrator`TurnWiki` 名前空間。
   WikiSkill 型 (arXiv:2608.27454) の LLM turn 自己改善ループ。
   仕様: ドキュメント/claude_turnwiki_wikiskill_spec_v0_1.md

   3 層 (root = $ClaudeTurnWikiRoot, 既定 <MyPackages>/Claude TurnWiki/):
     raw/      不変実行トレース (write-once)
     wiki/     パターン集 + 進化ログ + skill-impact 台帳 (append/compound、
               決してロールバックしない)
     skills/   昇格済み手順書 (検証ゲート通過時のみ更新、archive/ で版管理)

   4 コンポーネント:
     Inference Agent  = 既存 ClaudeEval/ClaudeRunTurn (無改変。手順書のみ注入)
     Wiki Maintainer  = ClaudeTurnWikiMaintain   (LLM 1 呼び出し + 純関数適用)
     Skill Proposer   = ClaudeTurnWikiPropose    (ReAct 型クライアント側ツールループ)
     Gating&Rollback  = ClaudeTurnWikiValidate/GateDecision/Promote/Reject/
                        RollbackSkill (probe スコア > RBest のみ昇格、fail-closed)

   設計不変条件 (I1-I4):
     I1 wiki は append/compound のみ (リセット・ロールバック禁止)
     I2 全提案 (却下含む) を skill-impact に diff+スコア+判定つきで台帳追記
     I3 手順書は検証ゲート通過時のみ更新。悪化時は手順書のみ戻す。
        probe 0 件では昇格しない
     I4 実行役には手順書だけ。wiki は directive root の外 (起動時検査)。
        具現化されるのは skills/<name>/SKILL.md 本文のみ

   境界 (runtime-orchestrator-boundary): 進化ループは turn を跨ぐ永続 state を
   持つため Orchestrator 側。turn 内の注入は既存 ClaudeDirectives 機構
   (always-on rule として具現化) を使い、ClaudeRuntime/claudecode は無改変。

   弱結合依存 (ロード済みのときのみ使用、無ければ縮退):
     ClaudeOrchestrator`Workflow` : 反復の Petri net 実行 (UseOrchestrator)
     ClaudeDirectives`            : 手順書の注入具現化 (WireInjection)
     SourceVault`                 : 既定 LLM (SourceVaultQueryLocalLLM) と
                                    llmlog トレース原資
     ClaudeRuntime`               : 生きている runtime の EventTrace 原資

   バージョン: v0.1 (2026-09-01) 初版
   ════════════════════════════════════════════════════════════════════ *)

BeginPackage["ClaudeOrchestrator`TurnWiki`"];

(* ::Subsection:: *)
(* 公開 API usage *)

$TurnWikiVersion::usage =
  "$TurnWikiVersion is the real-load marker / version string of ClaudeOrchestrator_turnwiki.wl.";

$ClaudeTurnWikiRoot::usage =
  "$ClaudeTurnWikiRoot overrides the TurnWiki workspace root directory. Default: <package dir>/Claude TurnWiki.";

$ClaudeTurnWikiLLMFn::usage =
  "$ClaudeTurnWikiLLMFn, when set to a function fn[prompt, sysPrompt] -> String|Missing, overrides the default LLM backend (SourceVaultQueryLocalLLM).";

$ClaudeTurnWikiLLMTimeout::usage =
  "$ClaudeTurnWikiLLMTimeout is the per-call timeout in seconds for the default local LLM backend (default 480; local 27B models generate the Maintainer JSON at ~12 tok/s).";

$ClaudeTurnWikiMaxActiveSkills::usage =
  "$ClaudeTurnWikiMaxActiveSkills caps how many evolved skills are materialized into the directive store at once (default 3).";

$ClaudeTurnWikiFailureMarkers::usage =
  "$ClaudeTurnWikiFailureMarkers is a list of regex strings used to classify llmlog session texts as failing traces.";

$ClaudeTurnWikiMinTraceChars::usage =
  "$ClaudeTurnWikiMinTraceChars (default 200) drops automatically collected traces (runtime/llmlog) whose text is shorter than this; injected \"TracesFn\" traces are not filtered.";

$ClaudeTurnWikiAutoWire::usage =
  "$ClaudeTurnWikiAutoWire (default True) re-registers already-accepted evolved skills into the directive layer at package load.";

$ClaudeTurnWikiInjectionEnabled::usage =
  "$ClaudeTurnWikiInjectionEnabled (default True) gates whether Promote/Wire materialize evolved skills into the Claude Directives store.";

$ClaudeTurnWikiMaxFailStreak::usage =
  "$ClaudeTurnWikiMaxFailStreak (default 3): when the maintain tick fails this many consecutive times on the same set of traces, those traces are marked consumed (Status \"GaveUp\") so a poison trace cannot stall the loop forever.";

$ClaudeTurnWikiDirectiveRootOverride::usage =
  "$ClaudeTurnWikiDirectiveRootOverride (default Automatic) overrides the directive root used for skill materialization. Intended for tests; production resolves via ClaudeDirectives`ClaudeResolveDirectiveRoot.";

ClaudeTurnWikiInitialize::usage =
  "ClaudeTurnWikiInitialize[] creates the TurnWiki workspace (raw/wiki/skills/staging/archive/probes + seed files). Idempotent. Returns a status Association.";

ClaudeTurnWikiStatus::usage =
  "ClaudeTurnWikiStatus[] returns a summary Association: Root, Iteration, RBest, ActiveSkills, Patterns, Probes, Isolation.";

ClaudeTurnWikiCheckIsolation::usage =
  "ClaudeTurnWikiCheckIsolation[] verifies invariant I4: the TurnWiki root and the Claude Directives root do not contain each other. Returns <|\"OK\"->True|False, \"Detail\"->...|>.";

ClaudeTurnWikiState::usage =
  "ClaudeTurnWikiState[] returns the persistent loop state (RBest, Iteration, ActiveSkills, UpdatedAt).";

ClaudeTurnWikiCollectTraces::usage =
  "ClaudeTurnWikiCollectTraces[opts] collects a stratified sample of turn execution traces (Raw Layer). Options: \"TracesFn\" (Automatic = live ClaudeRuntime EventTraces + SourceVault llmlog digests), \"MaxFail\" (5), \"MaxPass\" (3), \"MaxChars\" (15000), \"Persist\" (True). Returns a list of <|TraceId, Kind, Task, Text, Source|>.";

ClaudeTurnWikiClassifyRuntimeTrace::usage =
  "ClaudeTurnWikiClassifyRuntimeTrace[trace] classifies a ClaudeTurnTrace event list as <|\"Kind\"->\"pass\"|\"fail\"|\"unknown\", \"Signals\"->{...}|>. Pure function.";

ClaudeTurnWikiRenderTrace::usage =
  "ClaudeTurnWikiRenderTrace[trace, maxChars] renders a ClaudeTurnTrace event list as compact text for LLM consumption. Pure function.";

ClaudeTurnWikiApplyPatchOps::usage =
  "ClaudeTurnWikiApplyPatchOps[content, edits] applies patch operations (op: append | replace | insert_after, with target/content) to a string. Pure. Returns <|\"Content\", \"Applied\", \"Failed\"|>.";

ClaudeTurnWikiApplyMaintainerOutput::usage =
  "ClaudeTurnWikiApplyMaintainerOutput[out] applies a Wiki Maintainer JSON output (create_patterns / update_patterns / update_index / append_log) to the wiki store. Returns a summary Association.";

ClaudeTurnWikiMaintain::usage =
  "ClaudeTurnWikiMaintain[traces, opts] runs the Wiki Maintainer: one LLM call consolidating traces into the persistent wiki. Options: \"LLMFn\" (Automatic). Returns <|Status, Created, Updated, ...|>.";

ClaudeTurnWikiParseProposal::usage =
  "ClaudeTurnWikiParseProposal[assoc] validates/normalizes a Skill Proposer proposal. Pure. Returns <|Action, Name, SkillMD, PurposeMD, Edits, Rationale, Status|>.";

ClaudeTurnWikiPropose::usage =
  "ClaudeTurnWikiPropose[opts] runs the Skill Proposer as a ReAct-style client-side tool loop (read_file over wiki/traces/skills + finish). Options: \"LLMFn\", \"MaxTurns\" (12). Returns a proposal Association.";

ClaudeTurnWikiActiveSkills::usage =
  "ClaudeTurnWikiActiveSkills[] returns <|name -> SKILL.md content, ...|> for the accepted skill set.";

ClaudeTurnWikiApplyProposal::usage =
  "ClaudeTurnWikiApplyProposal[proposal] applies a create/patch proposal into staging/ and returns <|Status, Name, CandidateSkills|>. Production skills/ is untouched.";

ClaudeTurnWikiAddProbe::usage =
  "ClaudeTurnWikiAddProbe[probe] stores a validation probe <|\"ProbeId\", \"Task\", \"Expected\", ...|> under probes/. ClaudeTurnWikiAddProbe[task, expected] is a shorthand.";

ClaudeTurnWikiProbes::usage =
  "ClaudeTurnWikiProbes[] returns the list of stored validation probes.";

ClaudeTurnWikiProbeFromTrace::usage =
  "ClaudeTurnWikiProbeFromTrace[trace] drafts a probe from a collected trace (Expected left Missing for the user to fill in). Pure.";

ClaudeTurnWikiValidate::usage =
  "ClaudeTurnWikiValidate[opts] scores a skill set against the stored probes. Options: \"Skills\" (Automatic = active), \"Probes\" (Automatic), \"EvalFn\" (Automatic = LLM answer + Expected containment), \"LLMFn\". Returns <|Score, Runs, Passed, Failed, Status|>.";

ClaudeTurnWikiGateDecision::usage =
  "ClaudeTurnWikiGateDecision[candidateScore, rBest] returns \"Accepted\" iff candidateScore is a number strictly greater than rBest (fail-closed otherwise). Pure.";

ClaudeTurnWikiPromote::usage =
  "ClaudeTurnWikiPromote[name, skillMD, purposeMD, score, meta] archives the previous version, installs the skill into skills/, updates state (ActiveSkills/RBest) and materializes it into the directive layer when wired.";

ClaudeTurnWikiReject::usage =
  "ClaudeTurnWikiReject[name] discards the staged candidate for name. The wiki is untouched.";

ClaudeTurnWikiRollbackSkill::usage =
  "ClaudeTurnWikiRollbackSkill[name] restores the previous archived version of an accepted skill (or deactivates it when no archive exists). The wiki is never rolled back. RBest is reset to Missing so the next iteration re-baselines.";

ClaudeTurnWikiAppendSkillImpact::usage =
  "ClaudeTurnWikiAppendSkillImpact[entry] appends a proposal outcome entry (markdown + jsonl) to the skill-impact ledger. Called programmatically by the iteration harness.";

ClaudeTurnWikiSkillImpact::usage =
  "ClaudeTurnWikiSkillImpact[] returns the skill-impact ledger markdown text (\"\" when absent).";

ClaudeTurnWikiRunIteration::usage =
  "ClaudeTurnWikiRunIteration[opts] runs one full WikiSkill iteration: collect -> maintain -> propose -> stage -> validate -> gate (promote/reject) -> ledger. Options: \"LLMFn\", \"TracesFn\", \"EvalFn\", \"UseOrchestrator\" (Automatic), \"MaxProposerTurns\". Returns a summary Association.";

ClaudeTurnWikiRun::usage =
  "ClaudeTurnWikiRun[k, opts] runs up to k iterations, stopping early when RBest >= 1.0. Returns the list of iteration summaries.";

ClaudeTurnWikiWireInjection::usage =
  "ClaudeTurnWikiWireInjection[] materializes the active evolved skills as always-on rules (rules/evolved-turn-<name>.md) in the Claude Directives store and registers them in $ClaudeAlwaysOnRules. Idempotent, defensive. Returns a status Association.";

ClaudeTurnWikiUnwireInjection::usage =
  "ClaudeTurnWikiUnwireInjection[] removes all evolved-turn-* rule files and their always-on registrations, and invalidates the directive cache.";

ClaudeTurnWikiInjectionStatus::usage =
  "ClaudeTurnWikiInjectionStatus[] reports which evolved skills are currently materialized and registered.";

ClaudeTurnWikiSettings::usage =
  "ClaudeTurnWikiSettings[] returns the persisted TurnWiki settings (<|\"AutoMaintain\", \"MaintainIntervalSeconds\"|>) stored in <root>/settings.json, readable from any kernel (interactive or service).";

ClaudeTurnWikiSetAutoMaintain::usage =
  "ClaudeTurnWikiSetAutoMaintain[True|False] persists the auto-maintain flag (periodic Collect+Maintain tick). ClaudeTurnWikiSetAutoMaintain[flag, intervalSeconds] also sets the minimum tick interval.";

ClaudeTurnWikiAutoMaintainQ::usage =
  "ClaudeTurnWikiAutoMaintainQ[] returns True when the persisted auto-maintain flag is on.";

ClaudeTurnWikiMaintainTick::usage =
  "ClaudeTurnWikiMaintainTick[opts] is the periodic maintenance step for service/heartbeat use: Collect (only traces not yet consumed, per watermark) + Maintain (Wiki Maintainer). No proposal, no gating, no skill change. Guards: persisted AutoMaintain flag (unless \"Force\"->True), minimum interval, cross-kernel lock file, LLM availability. Returns <|\"Status\"->\"OK\"|\"Disabled\"|\"IntervalNotElapsed\"|\"Locked\"|\"LLMUnavailable\"|\"NoNewTraces\"|..., ...|>.";

ClaudeTurnWikiMaintainTickStatus::usage =
  "ClaudeTurnWikiMaintainTickStatus[] reports the watermark (last tick time, consumed trace count) and lock state.";

(* ---- model profiles / adaptive DirectiveLevel / views (2026-09-08) ---- *)

ClaudeTurnWikiProfileKey::usage =
  "ClaudeTurnWikiProfileKey[provider, model] (or [trace]) is the canonical model profile key \"provider:model\" (lower case; \"unknown\" when neither is known). Traces, per-profile state, the ledger and the adaptive directive levels are keyed by it.";

$ClaudeTurnWikiProfileLLMFns::usage =
  "$ClaudeTurnWikiProfileLLMFns is an Association profileKey -> fn[prompt, sys] used to VALIDATE skills for that model profile (the probes are answered by the model the skill is meant for). Profiles without an entry use the default local LLM.";

$ClaudeTurnWikiLevelPolicy::usage =
  "$ClaudeTurnWikiLevelPolicy holds the adaptive DirectiveLevel thresholds: MinTraces (6), EscalateFailRatio (0.4), DeescalateFailRatio (0.1), DeescalateMinTraces (12).";

$ClaudeTurnWikiViewMaxRows::usage =
  "$ClaudeTurnWikiViewMaxRows (25) caps the rows drawn by the ...View functions (core functions are not capped).";

ClaudeTurnWikiProfiles::usage =
  "ClaudeTurnWikiProfiles[] (core) returns one Association per model profile: Profile, Provider, Model, RBest, ActiveSkills, Traces, Fails, FailRatio, DirectiveLevel, LevelSource, LastLedgerAt, Iteration. ClaudeTurnWikiProfilesView[] is the Dataset view.";
ClaudeTurnWikiProfilesView::usage =
  "ClaudeTurnWikiProfilesView[] renders ClaudeTurnWikiProfiles[] as a Dataset (rows capped by $ClaudeTurnWikiViewMaxRows).";

ClaudeTurnWikiLedger::usage =
  "ClaudeTurnWikiLedger[opts] (core) reads the skill-impact ledger (wiki/skill-impact.jsonl) as a list of Associations, newest first: At, Iteration, Profile, Outcome, Action, Name, Score, RBest, Rationale, Content, Edits. Options: \"Profile\" -> All | key, \"Outcome\" -> All | \"Accepted\" | \"Rejected\" | \"NoAction\" | \"RolledBack\" | \"LevelChanged\", \"Limit\" -> All | n.";
ClaudeTurnWikiLedgerView::usage =
  "ClaudeTurnWikiLedgerView[opts] is the Dataset view of ClaudeTurnWikiLedger (same options; rows capped by $ClaudeTurnWikiViewMaxRows). Each row with a skill has an open button for skills/<name>/SKILL.md.";

ClaudeTurnWikiLog::usage =
  "ClaudeTurnWikiLog[opts] (core) parses wiki/logs.md (the Wiki Maintainer's evolution log) into {<|At, Iteration, Text|>..}, newest first. Option \"Limit\".";
ClaudeTurnWikiLogView::usage =
  "ClaudeTurnWikiLogView[opts] is the Dataset view of ClaudeTurnWikiLog.";

ClaudeTurnWikiTraces::usage =
  "ClaudeTurnWikiTraces[opts] (core) lists the raw trace metadata (no full text): TraceId, Iteration, Kind, Provider, Model, Profile, Source, Task, Chars, File. Options: \"Iteration\" -> All | k, \"Profile\" -> All | key, \"Kind\" -> All | \"pass\" | \"fail\".";
ClaudeTurnWikiTracesView::usage =
  "ClaudeTurnWikiTracesView[opts] is the Dataset view of ClaudeTurnWikiTraces (task snippets may contain notebook content: local display only).";

ClaudeTurnWikiTimelineView::usage =
  "ClaudeTurnWikiTimelineView[] plots validation Score and RBest over time per profile from the ledger (DateListPlot), or a notice when no scored entry exists yet.";

ClaudeTurnWikiDashboard::usage =
  "ClaudeTurnWikiDashboard[] is the one-panel view: status, profiles, ledger, log, timeline, directive levels.";

ClaudeTurnWikiDirectiveLevelAdvice::usage =
  "ClaudeTurnWikiDirectiveLevelAdvice[opts] (pure, no LLM) computes per model profile whether the DirectiveLevel should be escalated (fail ratio high), de-escalated (sustained low fail ratio, never below the capability baseline) or kept. Option \"Traces\" -> Automatic (raw store) | list. Returns {<|Profile, Provider, Model, Traces, Fails, FailRatio, Current, CurrentSource, Base, Advised, Change, Reason|>..}.";
ClaudeTurnWikiApplyDirectiveLevels::usage =
  "ClaudeTurnWikiApplyDirectiveLevels[advice|Automatic, opts] persists the advised levels to <root>/directive-levels.json, installs them as ClaudeDirectives`$ClaudeDirectiveLevelOverrides (when loaded) and appends LevelChanged entries to the ledger. Option \"DryRun\" -> False.";
ClaudeTurnWikiDirectiveLevels::usage =
  "ClaudeTurnWikiDirectiveLevels[] returns the persisted adaptive levels (profile -> <|Level, At, Reason|>).";
ClaudeTurnWikiSetAutoLevel::usage =
  "ClaudeTurnWikiSetAutoLevel[True|False] persists the AutoLevel flag (settings.json): when True the maintenance tick also applies ClaudeTurnWikiDirectiveLevelAdvice.";
ClaudeTurnWikiAutoLevelQ::usage =
  "ClaudeTurnWikiAutoLevelQ[] is the persisted AutoLevel flag.";

ClaudeTurnWikiTransferSkill::usage =
  "ClaudeTurnWikiTransferSkill[name, toProfile, opts] validates an existing skill for another model profile (WikiSkill cross-model transfer) and promotes it there only if it beats that profile's RBest. Options: \"LLMFn\", \"EvalFn\".";

ClaudeTurnWikiRepairRawEncoding::usage =
  "ClaudeTurnWikiRepairRawEncoding[opts] repairs raw traces whose Task / Text were double-encoded (UTF-8 bytes stored as Latin-1 characters, the ExportString[\"RawJSON\"] trap). Option \"DryRun\" -> False. Returns <|Scanned, Repaired, Files|>.";

Begin["`Private`"];

$TurnWikiVersion = "0.2 (2026-09-08)";

(* ロード時のファイル位置を捕捉 (root 既定値の基準)。 *)
$iTWPackageDir = Quiet @ Check[DirectoryName[$InputFileName], ""];
If[!StringQ[$iTWPackageDir] || $iTWPackageDir === "", $iTWPackageDir = Directory[]];

If[!ValueQ[$ClaudeTurnWikiRoot], $ClaudeTurnWikiRoot = Automatic];
If[!ValueQ[$ClaudeTurnWikiLLMFn], $ClaudeTurnWikiLLMFn = Automatic];
(* 実測 (2026-09-02, strixhalo128 / qwen3.8-27b): Maintainer の JSON 出力は生成 ~12 tok/s で
   1500 トークン超 → 180s では client 切断 (LLMFailed) になった。480s = 5000 トークン相当。 *)
If[!ValueQ[$ClaudeTurnWikiLLMTimeout], $ClaudeTurnWikiLLMTimeout = 480];
If[!ValueQ[$ClaudeTurnWikiMaxActiveSkills], $ClaudeTurnWikiMaxActiveSkills = 3];
If[!ValueQ[$ClaudeTurnWikiAutoWire], $ClaudeTurnWikiAutoWire = True];
If[!ValueQ[$ClaudeTurnWikiInjectionEnabled], $ClaudeTurnWikiInjectionEnabled = True];
If[!ValueQ[$ClaudeTurnWikiDirectiveRootOverride], $ClaudeTurnWikiDirectiveRootOverride = Automatic];
If[!IntegerQ[$ClaudeTurnWikiMaxFailStreak], $ClaudeTurnWikiMaxFailStreak = 3];
(* 自動原資 (runtime/llmlog) のトレース最小文字数。これ未満は材料にならない (実測:
   "(no user message)" の 40 字セッションが Maintainer に渡っていた)。TracesFn 注入には適用しない。 *)
If[!ValueQ[$ClaudeTurnWikiMinTraceChars], $ClaudeTurnWikiMinTraceChars = 200];
If[!ValueQ[$ClaudeTurnWikiFailureMarkers],
  $ClaudeTurnWikiFailureMarkers = {
    "SyntaxError", "RepairRequest", "ValidationRepair", "\\$Failed",
    "FatalFailure", "ExecutionFailed", "TransportRetryExhausted",
    "CallContractViolation", "ToolLoopBudgetExhausted"}];

(* ::Subsection:: *)
(* 基本ユーティリティ: パス / IO / JSON *)

iTWRoot[] := Module[{r = $ClaudeTurnWikiRoot},
  If[!StringQ[r], r = FileNameJoin[{$iTWPackageDir, "Claude TurnWiki"}]];
  r];

iTWPath[parts___] := FileNameJoin[{iTWRoot[], parts}];

iTWEnsureDir[dir_String] :=
  If[!DirectoryQ[dir],
    Quiet @ Check[CreateDirectory[dir, CreateIntermediateDirectories -> True], $Failed],
    dir];

(* UTF-8 固定の read/write。wolframscript / FE どちらでも同一挙動にする。 *)
iTWReadFile[path_String] := Module[{ba},
  If[!FileExistsQ[path], Return[Missing["NotFound", path]]];
  ba = Quiet @ Check[ReadByteArray[path], $Failed];
  Which[
    ba === EndOfFile, "",
    ByteArrayQ[ba], Quiet @ Check[ByteArrayToString[ba], Missing["DecodeFailed", path]],
    True, Missing["ReadFailed", path]]];

(* tmp+rename の原子的書き込み (Windows は Rename 先在で失敗するため退避削除)。 *)
iTWWriteFile[path_String, content_String] := Module[{dir, tmp, strm, ok = True},
  dir = DirectoryName[path];
  If[dir =!= "", iTWEnsureDir[dir]];
  tmp = path <> ".tmp-" <> ToString[$ProcessID] <> "-" <> ToString[RandomInteger[10^6]];
  Quiet @ Check[
    strm = OpenWrite[tmp, CharacterEncoding -> "UTF-8"];
    WriteString[strm, content];
    Close[strm],
    ok = False];
  If[!ok, Return[$Failed]];
  Quiet @ Check[
    If[FileExistsQ[path], DeleteFile[path]];
    RenameFile[tmp, path];
    path,
    Quiet @ Check[DeleteFile[tmp], Null]; $Failed]];

iTWAppendFile[path_String, content_String] := Module[{cur},
  cur = iTWReadFile[path];
  If[!StringQ[cur], cur = ""];
  iTWWriteFile[path, cur <> content]];

iTWNowISO[] := DateString[TimeZoneConvert[Now, 0], "ISODateTime"] <> "Z";
iTWStamp[] := DateString[{"Year", "Month", "Day", "Hour", "Minute", "Second"}];

(* JSON: Missing を落としてから Export (RawJSON は Missing を扱えない)。
   2026-09-08 実測: ImportString[s, "RawJSON"] は非 ASCII (日本語) を含む文字列で
   失敗し、LM Studio の正しい JSON 応答 (append_log に「である調」) が ParseFailed に
   なっていた。mining と同じ Developer`ReadRawJSONString を第一候補にし、
   UTF-8 バイト経由 → ImportString の順でフォールバックする。 *)
iTWToJSON[expr_] := Module[{e = expr /. _Missing -> Null, r},
  r = Quiet @ Check[Developer`WriteRawJSONString[e, "Compact" -> True], $Failed];
  If[StringQ[r], r,
    (* 2026-09-08: the old fallback ExportString[.., "RawJSON"] returns the
       UTF-8 BYTES as Latin-1 characters; written through a UTF-8 stream that
       double-encodes every non-ASCII character (18 of 23 raw traces written
       before 09-08 came out as mojibake). ExportByteArray + UTF-8 decode is
       the byte-correct spelling. *)
    Quiet @ Check[
      ByteArrayToString[ExportByteArray[e, "RawJSON", "Compact" -> True], "UTF-8"],
      $Failed]]];

(* double-encoded text (UTF-8 bytes seen as Latin-1 chars): every code point
   < 256, some >= 128, and the code points re-read as UTF-8 decode cleanly *)
iTWMojibakeRepair[s_String] := Module[{codes, r},
  codes = ToCharacterCode[s];
  If[codes === {} || Max[codes] > 255 || Max[codes] < 128, Return[s]];
  r = Quiet @ Check[ByteArrayToString[ByteArray[codes], "UTF-8"], $Failed];
  If[StringQ[r] && r =!= s && !StringContainsQ[r, "\[UnknownGlyph]"], r, s]];
iTWMojibakeRepair[x_] := x;

iTWFromJSON[s_String] := Module[{r},
  r = Quiet @ Check[Developer`ReadRawJSONString[s], $Failed];
  If[r === $Failed,
    r = Quiet @ Check[ImportByteArray[StringToByteArray[s, "UTF-8"], "RawJSON"], $Failed]];
  If[r === $Failed,
    r = Quiet @ Check[ImportString[s, "RawJSON"], $Failed]];
  r];

(* LLM 応答からの緩い JSON 抽出: <think> ブロックと code fence を剥がし、
   最初の balanced {...} を取り出す。 *)
iTWParseJSONLenient[s_String] := Module[{t = s, start, depth = 0, i, chars, inStr = False, esc = False, endPos = 0, res},
  t = StringReplace[t, RegularExpression["(?s)<think>.*?</think>"] -> ""];
  t = StringReplace[t, RegularExpression["```[a-zA-Z]*"] -> ""];
  t = StringReplace[t, "```" -> ""];
  start = StringPosition[t, "{", 1];
  If[start === {}, Return[Missing["NoJSON"]]];
  start = start[[1, 1]];
  chars = Characters[StringDrop[t, start - 1]];
  Do[
    Module[{c = chars[[i]]},
      Which[
        esc, esc = False,
        inStr && c === "\\", esc = True,
        c === "\"", inStr = !inStr,
        !inStr && c === "{", depth++,
        !inStr && c === "}", depth--; If[depth === 0, endPos = i; Break[]]]],
    {i, Length[chars]}];
  If[endPos === 0, Return[Missing["Unbalanced"]]];
  res = iTWFromJSON[StringJoin[Take[chars, endPos]]];
  If[AssociationQ[res], res, Missing["ParseFailed"]]];
iTWParseJSONLenient[___] := Missing["NoJSON"];

(* 弱結合: フルネームの関数/変数が実在するかを DownValues/OwnValues で判定
   (半登録シンボル対策 = ClaudeOrchestrator iHookCallableQ と同発想)。 *)
iTWCallableQ[fullName_String] := Quiet @ Check[
  Names[fullName] =!= {} &&
    With[{h = ToExpression[fullName, InputForm, Hold]},
      MatchQ[h, Hold[_Symbol]] && (DownValues @@ h) =!= {}],
  False];

iTWValueQ[fullName_String] := Quiet @ Check[
  Names[fullName] =!= {} &&
    With[{h = ToExpression[fullName, InputForm, Hold]},
      MatchQ[h, Hold[_Symbol]] && (OwnValues @@ h) =!= {}],
  False];

iTWSafeName[name_String] := Module[{n},
  n = ToLowerCase[name];
  n = StringReplace[n, RegularExpression["[^a-z0-9_-]+"] -> "-"];
  n = StringReplace[n, RegularExpression["-+"] -> "-"];
  n = StringTrim[n, "-"];
  If[n === "", Missing["EmptyName"], n]];
iTWSafeName[___] := Missing["EmptyName"];

iTWTruncate[s_String, max_Integer] :=
  If[StringLength[s] <= max, s,
    StringTake[s, max] <> "\n...[truncated " <> ToString[StringLength[s] - max] <> " chars]"];

(* ::Subsection:: *)
(* ストア初期化 / 状態 / 隔離検査 *)

$iTWIndexSeed = "# TurnWiki pattern index\n\nNo patterns yet.\n";
$iTWLogsSeed = "# TurnWiki evolution log\n";
$iTWImpactSeed = "# TurnWiki skill-impact ledger\n\nEvery proposal (accepted or rejected) is recorded here by the harness.\n";

ClaudeTurnWikiInitialize[] := Module[{root = iTWRoot[], made = {}},
  Scan[
    Function[d, If[iTWEnsureDir[iTWPath[d]] =!= $Failed, AppendTo[made, d]]],
    {"raw", "wiki", FileNameJoin[{"wiki", "patterns"}], "skills", "staging", "archive", "probes"}];
  If[!FileExistsQ[iTWPath["wiki", "index.md"]], iTWWriteFile[iTWPath["wiki", "index.md"], $iTWIndexSeed]];
  If[!FileExistsQ[iTWPath["wiki", "logs.md"]], iTWWriteFile[iTWPath["wiki", "logs.md"], $iTWLogsSeed]];
  If[!FileExistsQ[iTWPath["wiki", "skill-impact.md"]], iTWWriteFile[iTWPath["wiki", "skill-impact.md"], $iTWImpactSeed]];
  If[!FileExistsQ[iTWPath["state.json"]],
    iTWSaveState[<|"RBest" -> Null, "Iteration" -> 0, "ActiveSkills" -> {}, "UpdatedAt" -> iTWNowISO[]|>]];
  <|"Status" -> "OK", "Root" -> root, "Ensured" -> made|>];

iTWLoadState[] := Module[{s = iTWReadFile[iTWPath["state.json"]], a},
  If[!StringQ[s], Return[<|"RBest" -> Null, "Iteration" -> 0, "ActiveSkills" -> {}|>]];
  a = iTWFromJSON[s];
  If[!AssociationQ[a], <|"RBest" -> Null, "Iteration" -> 0, "ActiveSkills" -> {}|>, a]];

iTWSaveState[a_Association] :=
  iTWWriteFile[iTWPath["state.json"], iTWToJSON[Append[a, "UpdatedAt" -> iTWNowISO[]]]];

ClaudeTurnWikiState[] := iTWLoadState[];

(* RBest は JSON で Null 化されるので数値以外は Missing 扱いへ正規化。 *)
iTWRBest[] := Module[{r = Lookup[iTWLoadState[], "RBest", Null]},
  If[NumberQ[r], r, Missing["NoBaseline"]]];

(* ::Subsection:: *)
(* Model profiles (2026-09-08)

   WikiSkill's finding: evolved skills transfer across models, but WHICH skills
   help and how much depends on the model (a small model with skills can beat a
   large one without; a Claude 5 needs far fewer explicit rules). So the loop
   keeps its state per model profile "provider:model":
     state.json  Profiles -> <|key -> <|RBest, ActiveSkills, Iteration|>|>
   The legacy top-level RBest / ActiveSkills / Iteration ARE the "default"
   profile (all traces, no model filter) -- fully backward compatible. *)

$iTWDefaultProfile = "default";

ClaudeTurnWikiProfileKey[prov_, model_] := Module[{p, m},
  p = If[StringQ[prov] && StringTrim[prov] =!= "", ToLowerCase[StringTrim[prov]], "unknown"];
  m = If[StringQ[model] && StringTrim[model] =!= "", ToLowerCase[StringTrim[model]], "unknown"];
  If[p === "unknown" && m === "unknown", "unknown", p <> ":" <> m]];
ClaudeTurnWikiProfileKey[t_Association] :=
  ClaudeTurnWikiProfileKey[Lookup[t, "Provider", Missing[]], Lookup[t, "Model", Missing[]]];
ClaudeTurnWikiProfileKey[___] := "unknown";

iTWProfileSpec[key_String] := With[{p = StringSplit[key, ":", 2]},
  If[Length[p] === 2, p, {None, key}]];

iTWNormProfile[x_] := Which[
  x === Automatic || x === None || x === Null || x === "" || x === All, $iTWDefaultProfile,
  StringQ[x], ToLowerCase[StringTrim[x]],
  ListQ[x] && Length[x] >= 2, ClaudeTurnWikiProfileKey[x[[1]], x[[2]]],
  AssociationQ[x], ClaudeTurnWikiProfileKey[x],
  True, $iTWDefaultProfile];

iTWProfileState[key_String] := Module[{st = iTWLoadState[], profs, p},
  If[key === $iTWDefaultProfile,
    Return[<|"RBest" -> Lookup[st, "RBest", Null],
      "ActiveSkills" -> Lookup[st, "ActiveSkills", {}],
      "Iteration" -> Lookup[st, "Iteration", 0]|>]];
  profs = Lookup[st, "Profiles", <||>]; If[!AssociationQ[profs], profs = <||>];
  p = Lookup[profs, key, <||>]; If[!AssociationQ[p], p = <||>];
  <|"RBest" -> Lookup[p, "RBest", Null],
    "ActiveSkills" -> With[{a = Lookup[p, "ActiveSkills", {}]}, If[ListQ[a], a, {}]],
    "Iteration" -> Lookup[p, "Iteration", 0]|>];

iTWSaveProfileState[key_String, upd_Association] := Module[{st = iTWLoadState[], profs, p},
  If[key === $iTWDefaultProfile,
    st = Join[st, upd]; iTWSaveState[st]; Return[st]];
  profs = Lookup[st, "Profiles", <||>]; If[!AssociationQ[profs], profs = <||>];
  p = Lookup[profs, key, <||>]; If[!AssociationQ[p], p = <||>];
  p = Join[p, upd, <|"UpdatedAt" -> iTWNowISO[]|>];
  profs[key] = p; st["Profiles"] = profs;
  iTWSaveState[st]; p];

iTWProfileRBest[key_String] := With[{r = Lookup[iTWProfileState[key], "RBest", Null]},
  If[NumberQ[r], r, Missing["NoBaseline"]]];
iTWProfileActiveSkills[key_String] := Lookup[iTWProfileState[key], "ActiveSkills", {}];

iTWKnownProfiles[] := Module[{st = iTWLoadState[], profs},
  profs = Lookup[st, "Profiles", <||>];
  If[AssociationQ[profs], Keys[profs], {}]];

(* every skill active in ANY profile (default first, then per profile) *)
iTWAllActiveSkillNames[] := Module[{st = iTWLoadState[], profs},
  profs = Lookup[st, "Profiles", <||>];
  If[!AssociationQ[profs], profs = <||>];
  DeleteDuplicates @ Join[
    With[{a = Lookup[st, "ActiveSkills", {}]}, If[ListQ[a], a, {}]],
    Flatten[With[{a = Lookup[#, "ActiveSkills", {}]}, If[ListQ[a], a, {}]] & /@ Values[profs]]]];

(* profiles a skill is active in ({} = not active anywhere; contains "default"
   when active globally) *)
iTWSkillProfiles[name_String] := Module[{st = iTWLoadState[], profs, out = {}},
  If[MemberQ[Lookup[st, "ActiveSkills", {}], name], AppendTo[out, $iTWDefaultProfile]];
  profs = Lookup[st, "Profiles", <||>];
  If[AssociationQ[profs],
    KeyValueMap[Function[{k, v}, If[MemberQ[Lookup[v, "ActiveSkills", {}], name], AppendTo[out, k]]], profs]];
  out];

iTWEnsureTraceProfile[t_Association] :=
  If[KeyExistsQ[t, "Profile"] && StringQ[t["Profile"]], t,
    Append[t, "Profile" -> ClaudeTurnWikiProfileKey[t]]];
iTWEnsureTraceProfile[x_] := x;

iTWDirectiveRoot[] := Module[{r},
  If[StringQ[$ClaudeTurnWikiDirectiveRootOverride],
    Return[If[DirectoryQ[$ClaudeTurnWikiDirectiveRootOverride],
      $ClaudeTurnWikiDirectiveRootOverride, Missing["NoDirectiveRoot"]]]];
  If[!iTWCallableQ["ClaudeDirectives`ClaudeResolveDirectiveRoot"], Return[Missing["DirectivesNotLoaded"]]];
  r = Quiet @ Check[ToExpression["ClaudeDirectives`ClaudeResolveDirectiveRoot"][Automatic], $Failed];
  If[StringQ[r] && DirectoryQ[r], r, Missing["NoDirectiveRoot"]]];

(* I4: wiki が directive root 配下に置かれると注入経路に乗ってしまうため禁止。 *)
ClaudeTurnWikiCheckIsolation[] := Module[{root, droot, inside, contains, canon},
  root = iTWRoot[];
  droot = iTWDirectiveRoot[];
  If[MissingQ[droot],
    Return[<|"OK" -> True, "Detail" -> "Directive root unavailable (ClaudeDirectives not loaded); nothing to violate."|>]];
  canon = Function[p, ToLowerCase[StringReplace[ExpandFileName[p], "\\" -> "/"]]];
  inside = StringStartsQ[canon[root], canon[droot] <> "/"] || canon[root] === canon[droot];
  contains = StringStartsQ[canon[droot], canon[root] <> "/"];
  If[inside || contains,
    <|"OK" -> False, "Detail" -> "TurnWiki root and directive root overlap: " <> root <> " vs " <> droot|>,
    <|"OK" -> True, "Detail" -> "Disjoint roots."|>]];

ClaudeTurnWikiStatus[] := Module[{st = iTWLoadState[], pats, probes},
  pats = Quiet @ Check[FileNames["*.md", iTWPath["wiki", "patterns"]], {}];
  probes = Quiet @ Check[FileNames["*.json", iTWPath["probes"]], {}];
  <|"Root" -> iTWRoot[],
    "Iteration" -> Lookup[st, "Iteration", 0],
    "RBest" -> iTWRBest[],
    "ActiveSkills" -> Lookup[st, "ActiveSkills", {}],
    "Profiles" -> With[{p = Lookup[st, "Profiles", <||>]},
      If[AssociationQ[p], KeyValueMap[#1 -> KeyTake[#2, {"RBest", "ActiveSkills"}] &, p], {}]],
    "Patterns" -> Length[pats],
    "Probes" -> Length[probes],
    "Isolation" -> ClaudeTurnWikiCheckIsolation[],
    "Injection" -> ClaudeTurnWikiInjectionStatus[],
    "AutoMaintain" -> ClaudeTurnWikiAutoMaintainQ[],
    "AutoLevel" -> ClaudeTurnWikiAutoLevelQ[],
    "DirectiveLevels" -> ClaudeTurnWikiDirectiveLevels[]|>];

(* ::Subsection:: *)
(* LLM 解決 *)

iTWResolveLLMFn[opt_] := Which[
  opt =!= Automatic && opt =!= None, opt,
  $ClaudeTurnWikiLLMFn =!= Automatic && $ClaudeTurnWikiLLMFn =!= None, $ClaudeTurnWikiLLMFn,
  iTWCallableQ["SourceVault`SourceVaultQueryLocalLLM"],
    With[{f = ToExpression["SourceVault`SourceVaultQueryLocalLLM"], to = $ClaudeTurnWikiLLMTimeout},
      Function[{p, sys}, f[p, to, 0, sys]]],
  True, Missing["LLMUnavailable"]];

iTWCallLLM[llmFn_, prompt_String, sys_] := Module[{r},
  If[MissingQ[llmFn] || llmFn === Automatic, Return[Missing["LLMUnavailable"]]];
  r = Quiet @ Check[llmFn[prompt, sys], $Failed];
  If[StringQ[r], r, Missing["LLMFailed", r]]];

(* ::Subsection:: *)
(* Raw Layer: トレース分類 / 描画 / 採取 *)

$iTWFailEventTypes = {
  "FatalFailure", "ExecutionFailed", "TransportRetryExhausted",
  "ToolLoopBudgetExhausted", "CallContractViolation", "TextOnlyRepair",
  "FormatRetry", "ValidationRepairAttempt", "ProviderFatalError",
  "BudgetExhausted", "ProviderFailed"};

(* 「修復ループが要らない turn」を pass とみなす: 修復系イベントが 1 つでも
   あれば学習対象 (fail)。 *)
ClaudeTurnWikiClassifyRuntimeTrace[trace_List] := Module[{evs, types, signals, denyQ},
  evs = Select[trace, AssociationQ];
  types = Lookup[#, "Type", ""] & /@ evs;
  signals = DeleteDuplicates[Select[types, MemberQ[$iTWFailEventTypes, #] &]];
  denyQ = AnyTrue[evs,
    Lookup[#, "Type", ""] === "ValidationComplete" && Lookup[#, "Decision", ""] === "Deny" &];
  If[denyQ, AppendTo[signals, "ValidationDeny"]];
  <|"Kind" -> Which[
      signals =!= {}, "fail",
      MemberQ[types, "TurnComplete"] || MemberQ[types, "TextOnlyResponse"], "pass",
      True, "unknown"],
    "Signals" -> signals|>];
ClaudeTurnWikiClassifyRuntimeTrace[___] := <|"Kind" -> "unknown", "Signals" -> {}|>;

$iTWTraceEventKeys = {"Type", "Decision", "Detail", "Reason", "ReasonClass",
  "Outcome", "TurnCount", "Hint", "Status", "FailedPhase"};

ClaudeTurnWikiRenderTrace[trace_List, maxChars_Integer : 15000] := Module[{lines},
  lines = Map[
    Function[ev,
      If[!AssociationQ[ev], "",
        StringRiffle[
          KeyValueMap[
            Function[{k, v}, k <> "=" <> iTWTruncate[ToString[v], 300]],
            KeyTake[ev, $iTWTraceEventKeys]],
          " "]]],
    trace];
  iTWTruncate[StringRiffle[Select[lines, # =!= "" &], "\n"], maxChars]];
ClaudeTurnWikiRenderTrace[___] := "";

(* 生きている runtime からの採取 (弱結合。公開 enumeration が無いため
   Private レジストリを defensive に読む)。 *)
iTWCollectRuntimeTraces[maxChars_Integer] := Module[{reg, out = {}},
  If[!iTWCallableQ["ClaudeRuntime`ClaudeTurnTrace"], Return[{}]];
  reg = Quiet @ Check[ToExpression["ClaudeRuntime`Private`$iClaudeRuntimes"], <||>];
  If[!AssociationQ[reg], Return[{}]];
  KeyValueMap[
    Function[{rid, rt},
      Module[{tr, cls},
        tr = Quiet @ Check[ToExpression["ClaudeRuntime`ClaudeTurnTrace"][rid], {}];
        If[ListQ[tr] && tr =!= {} &&
           StringLength[ClaudeTurnWikiRenderTrace[tr, maxChars]] >= $ClaudeTurnWikiMinTraceChars,
          cls = ClaudeTurnWikiClassifyRuntimeTrace[tr];
          AppendTo[out, iTWEnsureTraceProfile @ Join[<|
            "TraceId" -> "rt-" <> rid,
            "Kind" -> cls["Kind"],
            "Signals" -> cls["Signals"],
            "Task" -> iTWTruncate[ToString[Lookup[If[AssociationQ[rt], rt, <||>], "Metadata", ""]], 200],
            "Text" -> ClaudeTurnWikiRenderTrace[tr, maxChars],
            "Source" -> "ClaudeRuntime"|>,
            iTWRuntimeProviderModel[tr]]]]]],
    reg];
  out];

(* provider / model of a runtime trace: the ProviderQueried event carries them
   since 2026-09-08 (claudecode adapter -> ClaudeRuntime) *)
iTWRuntimeProviderModel[tr_List] := Module[{ev},
  ev = SelectFirst[tr,
    AssociationQ[#] && Lookup[#, "Type", ""] === "ProviderQueried" &&
      StringQ[Lookup[#, "Provider", None]] &, <||>];
  <|"Provider" -> Lookup[ev, "Provider", Missing["NotReported"]],
    "Model" -> With[{m = Lookup[ev, "Model", Missing["NotReported"]]},
      If[StringQ[m], m, Missing["NotReported"]]]|>];
iTWRuntimeProviderModel[___] := <|"Provider" -> Missing["NotReported"], "Model" -> Missing["NotReported"]|>;

(* ハーネス生成プロンプト (ClaudeEval 単発) の user 発話は CLAUDE.md 投影や注入 docs の
   定型文が数千字続く。llmlog と同じ規則で実タスク本文だけを残す (llmlog の抽出関数が
   あればそれを使い、無ければ同等の最小実装)。対話セッションの発話は素通し。 *)
iTWStripHarnessBoilerplate[s_String] := Module[{f, m, t},
  If[iTWCallableQ["SourceVault`PrivateLLMLog`iSVLLExtractTaskText"],
    f = ToExpression["SourceVault`PrivateLLMLog`iSVLLExtractTaskText"];
    t = Quiet @ Check[f[s], $Failed];
    If[StringQ[t], Return[t]]];
  m = StringCases[s,
    Shortest["=== TASK OVERVIEW" ~~ __ ~~ "===" ~~ body__ ~~ "=== END TASK OVERVIEW"] :> body, 1];
  If[m =!= {},
    t = StringTrim[StringReplace[First[m], Shortest["(Full task details" ~~ ___ ~~ ")"] -> ""]];
    If[t =!= "", Return[t]]];
  If[StringStartsQ[s, "You are an expert"] || StringStartsQ[s, "## Project guidelines"],
    m = StringPosition[s, "\nTask: "];
    If[m =!= {},
      t = StringTrim @ StringDrop[s, m[[-1, 2]]];
      If[t =!= "", Return[t]]]];
  s];
iTWStripHarnessBoilerplate[x_] := ToString[x];

iTWTurnText[t_Association] := With[{txt = StringTrim[ToString[Lookup[t, "Text", ""]]]},
  If[ToLowerCase[ToString[Lookup[t, "Role", ""]]] === "user",
    iTWStripHarnessBoilerplate[txt], txt]];

(* llmlog の全文 transcript ({<|Role,At,Text,Tools|>..}) を LLM 向けテキストに描画。
   失敗の証拠は末尾に出るので tail-keep (先頭の user 依頼だけは Task として別途保持)。 *)
iTWRenderTranscript[turns_List, maxChars_Integer] := Module[{lines, acc = {}, total = 0},
  lines = Map[
    Function[t,
      If[AssociationQ[t],
        "[" <> ToString[Lookup[t, "Role", "?"]] <> "] " <>
          iTWTruncate[iTWTurnText[t], 2000] <>
          With[{tools = Lookup[t, "Tools", {}]},
            If[ListQ[tools] && tools =!= {}, "\n  tools: " <> iTWTruncate[ToString[tools], 300], ""]],
        ""]],
    turns];
  lines = Select[lines, # =!= "" &];
  Do[
    With[{l = lines[[i]]},
      If[total + StringLength[l] + 1 > maxChars, Break[]];
      PrependTo[acc, l]; total += StringLength[l] + 1],
    {i, Length[lines], 1, -1}];
  If[Length[acc] < Length[lines], "...[earlier turns omitted]\n", ""] <> StringRiffle[acc, "\n"]];

(* SourceVault llmlog からの採取 (弱結合)。SessionKind=harness が ClaudeEval 単発 turn に
   相当。全文 transcript が取れればそれを (2026-09-02: digest 由来の要約は 数十〜数百字で
   Maintainer の材料にならなかった)、無ければ digest フィールドを使う。
   分類は failure marker 正規表現 (cap 前の全文に対して)。 *)
(* SessionTranscript の戻りは <|SessionId, Source, Path, Turns|> (実測) または turn の List。 *)
iTWTranscriptTurns[r_] := Which[
  ListQ[r], Select[r, AssociationQ],
  AssociationQ[r], With[{t = Lookup[r, "Turns", {}]}, If[ListQ[t], Select[t, AssociationQ], {}]],
  True, {}];

iTWCollectLLMLogTraces[maxChars_Integer, scanLimit_Integer, transcriptLimit_Integer : 10] := Module[
  {f, tf, sessions, extra, out = {}, hasTranscript, fetched = 0},
  If[!iTWCallableQ["SourceVault`SourceVaultClaudeCodeSessions"], Return[{}]];
  f = ToExpression["SourceVault`SourceVaultClaudeCodeSessions"];
  hasTranscript = iTWCallableQ["SourceVault`SourceVaultClaudeCodeSessionTranscript"];
  tf = If[hasTranscript, ToExpression["SourceVault`SourceVaultClaudeCodeSessionTranscript"], None];
  (* ClaudeEval 単発 (SessionKind=harness) を優先し、足りなければ interactive で補う。 *)
  sessions = Quiet @ Check[f["Limit" -> scanLimit, "Kind" -> "harness"], {}];
  If[!ListQ[sessions], sessions = {}];
  sessions = Select[sessions, AssociationQ];
  If[Length[sessions] < scanLimit,
    extra = Quiet @ Check[f["Limit" -> scanLimit], {}];
    If[ListQ[extra],
      sessions = DeleteDuplicatesBy[Join[sessions, Select[extra, AssociationQ]],
        ToString[Lookup[#, "SessionId", ""]] &]]];
  sessions = Take[sessions, UpTo[scanLimit]];
  Scan[
    Function[d,
      Module[{text, full, kind, sid, turns, task},
        If[AssociationQ[d],
          sid = ToString[Lookup[d, "SessionId", CreateUUID[]]];
          (* transcript は 1 件 1-5s かかるので直近 transcriptLimit 件だけ全文を引く *)
          turns = If[hasTranscript && fetched < transcriptLimit,
            fetched++; iTWTranscriptTurns[Quiet @ Check[tf[sid], $Failed]],
            {}];
          If[ListQ[turns] && turns =!= {},
            full = StringRiffle[
              Map[If[AssociationQ[#], ToString[Lookup[#, "Text", ""]], ""] &, turns], "\n"];
            task = With[{u = SelectFirst[turns,
                AssociationQ[#] && ToLowerCase[ToString[Lookup[#, "Role", ""]]] === "user" &, <||>]},
              iTWTruncate[If[u === <||>, ToString[Lookup[d, "Title", ""]], iTWTurnText[u]], 200]];
            text = iTWRenderTranscript[turns, maxChars],
            full = StringRiffle[
              Flatten[{
                "Title: " <> ToString[Lookup[d, "Title", ""]],
                ToString /@ Flatten[{Lookup[d, "UserPreviews", {}]}],
                ToString /@ Flatten[{Lookup[d, "Summaries", {}]}],
                "AssistantTail: " <> ToString[Lookup[d, "AssistantTail", ""]]}],
              "\n"];
            task = iTWTruncate[ToString[Lookup[d, "Title", ""]], 200];
            text = iTWTruncate[full, maxChars]];
          kind = If[
            AnyTrue[$ClaudeTurnWikiFailureMarkers,
              StringContainsQ[full, RegularExpression[#]] &],
            "fail", "pass"];
          (* 数十字の空セッション ("(no user message)" 等) は材料にならないので捨てる *)
          If[StringLength[full] >= $ClaudeTurnWikiMinTraceChars,
            AppendTo[out, iTWEnsureTraceProfile @ <|
              "TraceId" -> "cc-" <> sid,
              "Kind" -> kind,
              "Signals" -> {},
              "Task" -> task,
              "Text" -> text,
              "Source" -> If[ListQ[turns] && turns =!= {}, "llmlog-transcript", "llmlog"],
              (* 2026-09-08: per-turn model from the transcript (assistant
                 "Model", lifted by SourceVault_llmlog), else the digest's
                 per-session union. Claude Code sessions are always the
                 claudecode provider. *)
              "Provider" -> "claudecode",
              "Model" -> iTWLLMLogModel[turns, d]|>]]]]],
    sessions];
  out];

iTWLLMLogModel[turns_, d_] := Module[{ms},
  ms = If[ListQ[turns],
    Cases[turns, a_Association /; StringQ[Lookup[a, "Model", None]] :> a["Model"]], {}];
  If[ms =!= {}, Return[Last[ms]]];
  ms = Select[Flatten[{Lookup[If[AssociationQ[d], d, <||>], "Models", {}]}], StringQ];
  If[ms =!= {}, Last[ms], Missing["NotReported"]]];

Options[ClaudeTurnWikiCollectTraces] = {
  "TracesFn" -> Automatic, "MaxFail" -> 5, "MaxPass" -> 3,
  "MaxChars" -> 15000, "Persist" -> True, "LLMLogScanLimit" -> 30,
  "LLMLogTranscriptLimit" -> 10, "ExcludeTraceIds" -> {},
  (* 2026-09-08: All | "default" = every model; "provider:model" = that profile only *)
  "ModelProfile" -> All};

ClaudeTurnWikiCollectTraces[opts : OptionsPattern[]] := Module[
  {tracesFn = OptionValue["TracesFn"], maxFail = OptionValue["MaxFail"],
   maxPass = OptionValue["MaxPass"], maxChars = OptionValue["MaxChars"],
   exclude = OptionValue["ExcludeTraceIds"], all, fails, passes, sample, iter,
   profile = iTWNormProfile[OptionValue["ModelProfile"]]},
  ClaudeTurnWikiInitialize[];
  all = If[tracesFn =!= Automatic,
    Quiet @ Check[tracesFn[], {}],
    Join[
      iTWCollectRuntimeTraces[maxChars],
      iTWCollectLLMLogTraces[maxChars, OptionValue["LLMLogScanLimit"],
        OptionValue["LLMLogTranscriptLimit"]]]];
  all = iTWEnsureTraceProfile /@ Select[all, AssociationQ];
  If[profile =!= $iTWDefaultProfile,
    all = Select[all, Lookup[#, "Profile", "unknown"] === profile &]];
  (* 定期 tick の watermark: 消費済み TraceId は再サンプルしない。 *)
  If[ListQ[exclude] && exclude =!= {},
    all = Select[all, !MemberQ[exclude, ToString[Lookup[#, "TraceId", ""]]] &]];
  (* 層化: 論文 App.C = fail<=5 + pass<=3。原資は新しい順 (llmlog は
     LastAtUTC 降順) なので先頭から採る。 *)
  fails = Take[Select[all, Lookup[#, "Kind", ""] === "fail" &], UpTo[maxFail]];
  passes = Take[Select[all, Lookup[#, "Kind", ""] === "pass" &], UpTo[maxPass]];
  sample = Join[fails, passes];
  sample = Map[Append[#, "Text" -> iTWTruncate[Lookup[#, "Text", ""], maxChars]] &, sample];
  If[TrueQ[OptionValue["Persist"]] && sample =!= {},
    iter = Lookup[iTWLoadState[], "Iteration", 0];
    iTWEnsureDir[iTWPath["raw", "iter-" <> ToString[iter]]];
    Scan[
      Function[t,
        Module[{p = iTWPath["raw", "iter-" <> ToString[iter],
            ToString[Lookup[t, "TraceId", CreateUUID[]]] <> ".json"]},
          (* Raw Layer は不変: 既存ファイルは上書きしない (write-once)。 *)
          If[!FileExistsQ[p], iTWWriteFile[p, iTWToJSON[t]]]]],
      sample]];
  sample];

(* ::Subsection:: *)
(* patch ops エンジン (純関数) *)

ClaudeTurnWikiApplyPatchOps[content_String, edits_List] := Module[{cur = content, applied = 0, failed = {}},
  Scan[
    Function[ed,
      Module[{op, tgt, c},
        If[!AssociationQ[ed], AppendTo[failed, ed],
          op = Lookup[ed, "op", ""];
          tgt = Lookup[ed, "target", ""];
          c = Lookup[ed, "content", ""];
          Which[
            op === "append" && StringQ[c],
              cur = If[cur === "", c, cur <> "\n" <> c]; applied++,
            op === "replace" && StringQ[tgt] && tgt =!= "" && StringQ[c],
              If[StringContainsQ[cur, tgt],
                cur = StringReplace[cur, tgt -> c, 1]; applied++,
                AppendTo[failed, ed]],
            op === "insert_after" && StringQ[tgt] && tgt =!= "" && StringQ[c],
              If[StringContainsQ[cur, tgt],
                cur = StringReplace[cur, tgt -> tgt <> "\n" <> c, 1]; applied++,
                AppendTo[failed, ed]],
            True, AppendTo[failed, ed]]]]],
    edits];
  <|"Content" -> cur, "Applied" -> applied, "Failed" -> failed|>];
ClaudeTurnWikiApplyPatchOps[content_String, _] := <|"Content" -> content, "Applied" -> 0, "Failed" -> {}|>;

(* ::Subsection:: *)
(* Wiki Maintainer *)

$iTWMaintainerSysPrompt = "You are a Wiki Maintainer Agent for an LLM turn-improvement system.
Your job is to maintain a structured knowledge base (wiki) documenting patterns observed
in LLM turn executions -- both successes and failures. Perform DEEP root-cause analysis
of the execution traces, not surface-level symptom listing.

## Wiki structure
- wiki/index.md -- concise catalog of known patterns (one line per pattern)
- wiki/logs.md -- chronological evolution log
- wiki/patterns/ -- one markdown page per pattern with evidence and analysis

## Output (STRICT)
Return a SINGLE JSON object with keys:
- \"create_patterns\": list of {\"name\": \"pattern-name.md\", \"content\": \"...\"}
- \"update_patterns\": list of {\"name\": \"existing.md\", \"edits\": [{\"op\": \"append\"|\"replace\"|\"insert_after\", \"target\": \"exact text\", \"content\": \"...\"}]}
- \"update_index\": full updated content of index.md (REQUIRED, complete catalog)
- \"append_log\": brief summary of this iteration's findings (REQUIRED)

Patch rules: \"target\" must be an EXACT substring of the existing page. Keep edits minimal.

## Analysis guidelines
1. Compare failing vs passing traces: what did passing turns do differently?
2. Document ROOT CAUSE (why), exact failing behavior, and a concrete workaround.
3. Do NOT create duplicate patterns -- update existing ones with new evidence.
4. Pattern pages are 10-30 lines. Only meaningful, generalizable observations.
5. Index entries: '- [name](wiki/patterns/name.md): PROBLEM + ROOT CAUSE + FIX in one or two sentences.'
6. Be brief: the whole JSON should stay under ~800 tokens. If the traces do not
   support any generalizable pattern, return empty create_patterns/update_patterns,
   repeat the current index unchanged, and write a one-line append_log saying so.
   Never invent patterns that the traces do not evidence.
Respond with ONLY the JSON object.";

iTWWikiContextText[maxPatternChars_Integer : 12000] := Module[{idx, logs, pats, patTexts},
  idx = iTWReadFile[iTWPath["wiki", "index.md"]];
  logs = iTWReadFile[iTWPath["wiki", "logs.md"]];
  pats = Quiet @ Check[FileNames["*.md", iTWPath["wiki", "patterns"]], {}];
  patTexts = StringRiffle[
    Map[
      Function[p, "=== wiki/patterns/" <> FileNameTake[p] <> " ===\n" <>
        With[{c = iTWReadFile[p]}, If[StringQ[c], c, ""]]],
      pats],
    "\n\n"];
  "=== wiki/index.md ===\n" <> If[StringQ[idx], idx, ""] <>
  "\n\n=== wiki/logs.md (tail) ===\n" <>
    If[StringQ[logs],
      If[StringLength[logs] > 2000, StringTake[logs, -2000], logs], ""] <>
  "\n\n" <> iTWTruncate[patTexts, maxPatternChars]];

Options[ClaudeTurnWikiApplyMaintainerOutput] = {"Iteration" -> Automatic};

ClaudeTurnWikiApplyMaintainerOutput[out_Association, opts : OptionsPattern[]] := Module[
  {created = {}, updated = {}, failedOps = {}, iter, idx, logEntry},
  ClaudeTurnWikiInitialize[];
  iter = OptionValue["Iteration"];
  If[iter === Automatic, iter = Lookup[iTWLoadState[], "Iteration", 0]];
  (* create_patterns: 既存があれば上書きせず追記 (I1 append/compound)。 *)
  Scan[
    Function[cp,
      Module[{nm, safe, path, content},
        If[AssociationQ[cp],
          nm = ToString[Lookup[cp, "name", ""]];
          content = Lookup[cp, "content", ""];
          safe = iTWSafeName[StringReplace[nm, ".md" ~~ EndOfString -> ""]];
          If[!MissingQ[safe] && StringQ[content] && content =!= "",
            path = iTWPath["wiki", "patterns", safe <> ".md"];
            If[FileExistsQ[path],
              iTWAppendFile[path, "\n\n<!-- merged " <> iTWNowISO[] <> " -->\n" <> content],
              iTWWriteFile[path, content]];
            AppendTo[created, safe <> ".md"],
            AppendTo[failedOps, cp]]]]],
    Lookup[out, "create_patterns", {}]];
  (* update_patterns: patch ops。 *)
  Scan[
    Function[up,
      Module[{nm, safe, path, cur, res},
        If[AssociationQ[up],
          nm = ToString[Lookup[up, "name", ""]];
          safe = iTWSafeName[StringReplace[nm, ".md" ~~ EndOfString -> ""]];
          If[!MissingQ[safe],
            path = iTWPath["wiki", "patterns", safe <> ".md"];
            cur = iTWReadFile[path];
            If[StringQ[cur],
              res = ClaudeTurnWikiApplyPatchOps[cur, Lookup[up, "edits", {}]];
              iTWWriteFile[path, res["Content"]];
              If[res["Failed"] =!= {}, failedOps = Join[failedOps, res["Failed"]]];
              AppendTo[updated, safe <> ".md"],
              AppendTo[failedOps, up]]]]]],
    Lookup[out, "update_patterns", {}]];
  idx = Lookup[out, "update_index", Missing["NotGiven"]];
  If[StringQ[idx] && idx =!= "", iTWWriteFile[iTWPath["wiki", "index.md"], idx]];
  logEntry = Lookup[out, "append_log", Missing["NotGiven"]];
  If[StringQ[logEntry] && logEntry =!= "",
    iTWAppendFile[iTWPath["wiki", "logs.md"],
      "\n## " <> iTWNowISO[] <> " iteration " <> ToString[iter] <> "\n" <> logEntry <> "\n"]];
  <|"Status" -> "OK", "Created" -> created, "Updated" -> updated,
    "IndexUpdated" -> StringQ[idx], "LogAppended" -> StringQ[logEntry],
    "FailedOps" -> failedOps|>];

Options[ClaudeTurnWikiMaintain] = {"LLMFn" -> Automatic, "Iteration" -> Automatic};

ClaudeTurnWikiMaintain[traces_List, opts : OptionsPattern[]] := Module[
  {llmFn, prompt, resp, parsed},
  llmFn = iTWResolveLLMFn[OptionValue["LLMFn"]];
  If[MissingQ[llmFn], Return[<|"Status" -> "LLMUnavailable"|>]];
  If[traces === {}, Return[<|"Status" -> "NoTraces"|>]];
  prompt = "## Current wiki\n" <> iTWWikiContextText[] <>
    "\n\n## Execution traces from the latest iteration\n" <>
    StringRiffle[
      Map[
        Function[t, "=== TRACE " <> ToString[Lookup[t, "TraceId", "?"]] <>
          " (" <> ToString[Lookup[t, "Kind", "?"]] <> ") ===\nTask: " <>
          ToString[Lookup[t, "Task", ""]] <> "\n" <> ToString[Lookup[t, "Text", ""]]],
        traces],
      "\n\n"];
  resp = iTWCallLLM[llmFn, prompt, $iTWMaintainerSysPrompt];
  If[!StringQ[resp], Return[<|"Status" -> "LLMFailed", "Detail" -> resp|>]];
  parsed = iTWParseJSONLenient[resp];
  If[!AssociationQ[parsed],
    Return[<|"Status" -> "ParseFailed", "RawResponse" -> iTWTruncate[resp, 2000]|>]];
  Append[
    ClaudeTurnWikiApplyMaintainerOutput[parsed, "Iteration" -> OptionValue["Iteration"]],
    "RawKeys" -> Keys[parsed]]];

(* ::Subsection:: *)
(* Skill Layer: 読み出し / staging / 昇格 / 却下 / ロールバック *)

(* active skills of a profile (default = the global set). Skill files are
   shared under skills/<name>/; profiles only differ in which are active. *)
ClaudeTurnWikiActiveSkills[profile_ : Automatic] := Module[{names},
  names = iTWProfileActiveSkills[iTWNormProfile[profile]];
  Association @ Map[
    Function[n,
      n -> With[{c = iTWReadFile[iTWPath["skills", n, "SKILL.md"]]}, If[StringQ[c], c, ""]]],
    names]];

iTWSkillsText[skills_Association] :=
  If[skills === <||>, "",
    StringRiffle[
      KeyValueMap[
        Function[{n, c}, "=== SKILL: " <> n <> " ===\n" <> c],
        skills],
      "\n\n"]];

ClaudeTurnWikiParseProposal[p_Association] := Module[{action, name, safe},
  action = ToLowerCase[ToString[Lookup[p, "action", Lookup[p, "Action", ""]]]];
  name = ToString[Lookup[p, "name", Lookup[p, "Name", ""]]];
  safe = iTWSafeName[name];
  Which[
    action === "no_action",
      <|"Action" -> "no_action", "Status" -> "OK",
        "Rationale" -> ToString[Lookup[p, "rationale", ""]]|>,
    action === "create" && !MissingQ[safe] &&
      StringQ[Lookup[p, "skill_md", Lookup[p, "SkillMD", Missing[]]]],
      <|"Action" -> "create", "Name" -> safe, "Status" -> "OK",
        "SkillMD" -> Lookup[p, "skill_md", Lookup[p, "SkillMD", ""]],
        "PurposeMD" -> ToString[Lookup[p, "purpose_md", Lookup[p, "PurposeMD", ""]]],
        "Rationale" -> ToString[Lookup[p, "rationale", ""]]|>,
    action === "patch" && !MissingQ[safe] &&
      ListQ[Lookup[p, "edits", Lookup[p, "Edits", Missing[]]]],
      <|"Action" -> "patch", "Name" -> safe, "Status" -> "OK",
        "Edits" -> Lookup[p, "edits", Lookup[p, "Edits", {}]],
        "PurposeMD" -> ToString[Lookup[p, "purpose_md", Lookup[p, "PurposeMD", ""]]],
        "Rationale" -> ToString[Lookup[p, "rationale", ""]]|>,
    True,
      <|"Action" -> "no_action", "Status" -> "Invalid",
        "Detail" -> "Unrecognized or incomplete proposal", "Raw" -> p|>]];
ClaudeTurnWikiParseProposal[___] :=
  <|"Action" -> "no_action", "Status" -> "Invalid", "Detail" -> "Not an association"|>;

(* profile: the candidate set = that profile's active skills + the candidate
   ("transfer" = an existing skill staged for another profile, 2026-09-08) *)
ClaudeTurnWikiApplyProposal[proposal_Association, profileIn_ : Automatic] := Module[
  {action = Lookup[proposal, "Action", ""], name, staged, base, res, cand,
   profile = iTWNormProfile[If[profileIn === Automatic, Lookup[proposal, "Profile", Automatic], profileIn]]},
  ClaudeTurnWikiInitialize[];
  name = Lookup[proposal, "Name", Missing["NoName"]];
  Which[
    action === "create" || action === "transfer",
      staged = Lookup[proposal, "SkillMD", ""];
      iTWWriteFile[iTWPath["staging", name, "SKILL.md"], staged];
      If[StringQ[Lookup[proposal, "PurposeMD", ""]] && Lookup[proposal, "PurposeMD", ""] =!= "",
        iTWWriteFile[iTWPath["staging", name, "PURPOSE.md"], Lookup[proposal, "PurposeMD", ""]]];
      cand = Append[ClaudeTurnWikiActiveSkills[profile], name -> staged];
      <|"Status" -> "Staged", "Name" -> name, "CandidateSkills" -> cand, "Profile" -> profile|>,
    action === "patch",
      base = iTWReadFile[iTWPath["skills", name, "SKILL.md"]];
      If[!StringQ[base],
        Return[<|"Status" -> "NoSuchSkill", "Name" -> name|>]];
      res = ClaudeTurnWikiApplyPatchOps[base, Lookup[proposal, "Edits", {}]];
      If[res["Failed"] =!= {},
        Return[<|"Status" -> "PatchFailed", "Name" -> name, "Failed" -> res["Failed"]|>]];
      iTWWriteFile[iTWPath["staging", name, "SKILL.md"], res["Content"]];
      cand = Append[ClaudeTurnWikiActiveSkills[profile], name -> res["Content"]];
      <|"Status" -> "Staged", "Name" -> name, "CandidateSkills" -> cand, "Profile" -> profile|>,
    True,
      <|"Status" -> "NoAction"|>]];

iTWClearStaging[name_String] := Module[{d = iTWPath["staging", name]},
  If[DirectoryQ[d], Quiet @ Check[DeleteDirectory[d, DeleteContents -> True], Null]]];

(* meta "Profile" (default = global): the skill becomes active for that
   profile and RBest of that profile moves. The skill FILE is shared. *)
ClaudeTurnWikiPromote[name_String, skillMD_String, purposeMD_String, score_, meta_Association : <||>] := Module[
  {ps, cur, ts = iTWStamp[], profile = iTWNormProfile[Lookup[meta, "Profile", Automatic]]},
  ClaudeTurnWikiInitialize[];
  cur = iTWReadFile[iTWPath["skills", name, "SKILL.md"]];
  (* 同一秒内の連続昇格で archive が潰れないようサフィックスで回避。 *)
  While[DirectoryQ[iTWPath["archive", name, ts]], ts = ts <> "x"];
  If[StringQ[cur],
    iTWWriteFile[iTWPath["archive", name, ts, "SKILL.md"], cur]];
  iTWWriteFile[iTWPath["skills", name, "SKILL.md"], skillMD];
  If[purposeMD =!= "",
    iTWWriteFile[iTWPath["skills", name, "PURPOSE.md"], purposeMD]];
  iTWClearStaging[name];
  ps = iTWProfileState[profile];
  iTWSaveProfileState[profile, <|
    "ActiveSkills" -> DeleteDuplicates[Append[Lookup[ps, "ActiveSkills", {}], name]],
    "RBest" -> If[NumberQ[score], score, Lookup[ps, "RBest", Null]]|>];
  If[TrueQ[$ClaudeTurnWikiInjectionEnabled],
    Quiet @ Check[iTWMaterializeSkill[name, skillMD], Null]];
  <|"Status" -> "Promoted", "Name" -> name, "Profile" -> profile,
    "ArchivedPrevious" -> StringQ[cur],
    "RBest" -> If[NumberQ[score], score, iTWProfileRBest[profile]]|>];

ClaudeTurnWikiReject[name_String] := (
  iTWClearStaging[name];
  <|"Status" -> "Rejected", "Name" -> name|>);

(* profile: which profile's activation / RBest is rolled back (default =
   global). A skill still active in another profile keeps its file and its
   materialization (narrowed to the remaining profiles). *)
ClaudeTurnWikiRollbackSkill[name_String, profileIn_ : Automatic] := Module[
  {arDir, versions, latest, content, ps, profile = iTWNormProfile[profileIn], stillActive},
  arDir = iTWPath["archive", name];
  versions = If[DirectoryQ[arDir], Sort[Select[FileNames["*", arDir], DirectoryQ]], {}];
  ps = iTWProfileState[profile];
  (* a named (non-default) profile rolls back its ACTIVATION: the skill file
     is shared, so restoring an archived version would change every other
     profile too. Content restore is the default-profile operation. *)
  If[versions === {} || profile =!= $iTWDefaultProfile,
    (* 前版が無い: 非活性化 (手順書を外す)。wiki は不変。 *)
    iTWSaveProfileState[profile, <|
      "ActiveSkills" -> DeleteCases[Lookup[ps, "ActiveSkills", {}], name],
      "RBest" -> Null|>];
    stillActive = iTWSkillProfiles[name];
    If[stillActive === {},
      Quiet @ Check[
        If[DirectoryQ[iTWPath["skills", name]],
          DeleteDirectory[iTWPath["skills", name], DeleteContents -> True]], Null];
      Quiet @ Check[iTWUnmaterializeSkill[name], Null],
      (* narrow the rule's model scope to the remaining profiles *)
      With[{c = iTWReadFile[iTWPath["skills", name, "SKILL.md"]]},
        If[StringQ[c] && TrueQ[$ClaudeTurnWikiInjectionEnabled],
          Quiet @ Check[iTWMaterializeSkill[name, c], Null]]]];
    ClaudeTurnWikiAppendSkillImpact[<|
      "Outcome" -> "RolledBack", "Action" -> "deactivate", "Name" -> name,
      "Profile" -> profile,
      "Score" -> Missing[], "RBest" -> Missing[], "Rationale" -> "Rollback with no archive: deactivated."|>];
    <|"Status" -> "Deactivated", "Name" -> name, "Profile" -> profile|>,
    latest = Last[versions];
    content = iTWReadFile[FileNameJoin[{latest, "SKILL.md"}]];
    If[!StringQ[content], Return[<|"Status" -> "ArchiveUnreadable", "Name" -> name|>]];
    iTWWriteFile[iTWPath["skills", name, "SKILL.md"], content];
    iTWSaveProfileState[profile, <|"RBest" -> Null|>];  (* 次反復で再ベースライン (I3) *)
    If[TrueQ[$ClaudeTurnWikiInjectionEnabled],
      Quiet @ Check[iTWMaterializeSkill[name, content], Null]];
    ClaudeTurnWikiAppendSkillImpact[<|
      "Outcome" -> "RolledBack", "Action" -> "restore", "Name" -> name,
      "Profile" -> profile,
      "Score" -> Missing[], "RBest" -> Missing[],
      "Rationale" -> "Skill rolled back to " <> FileNameTake[latest] <> ". Wiki untouched."|>];
    <|"Status" -> "RolledBack", "Name" -> name, "Profile" -> profile,
      "RestoredVersion" -> FileNameTake[latest]|>]];

(* WikiSkill cross-model transfer: an existing skill is validated for another
   profile and promoted there only if it beats that profile's RBest (I3). *)
Options[ClaudeTurnWikiTransferSkill] = {"LLMFn" -> Automatic, "EvalFn" -> Automatic};
ClaudeTurnWikiTransferSkill[name_String, toProfile_, opts : OptionsPattern[]] := Module[
  {profile = iTWNormProfile[toProfile], content, llmFn, evalFn, baseline, gate, from},
  ClaudeTurnWikiInitialize[];
  content = iTWReadFile[iTWPath["skills", name, "SKILL.md"]];
  If[!StringQ[content], Return[<|"Status" -> "NoSuchSkill", "Name" -> name|>]];
  If[MemberQ[iTWProfileActiveSkills[profile], name],
    Return[<|"Status" -> "AlreadyActive", "Name" -> name, "Profile" -> profile|>]];
  llmFn = iTWResolveProfileLLMFn[profile, OptionValue["LLMFn"]];
  evalFn = OptionValue["EvalFn"];
  from = iTWSkillProfiles[name];
  baseline = iTWStepEnsureBaseline[llmFn, evalFn, profile];
  gate = iTWStepGate[<|"Action" -> "transfer", "Name" -> name, "SkillMD" -> content,
      "PurposeMD" -> "",
      "Rationale" -> "Transfer of skill evolved for " <> ToString[from] <> " to " <> profile|>,
    llmFn, evalFn, profile];
  <|"Status" -> "OK", "Name" -> name, "Profile" -> profile, "From" -> from,
    "Baseline" -> baseline, "Decision" -> gate["Decision"],
    "Validation" -> Lookup[gate, "Validation", Missing[]],
    "RBest" -> iTWProfileRBest[profile]|>];

(* ::Subsection:: *)
(* Skill Proposer (ReAct 型クライアント側ツールループ) *)

$iTWProposerSysPrompt = "You are a Skill Proposer Agent for an LLM turn-improvement system.
Your job is to explore the wiki knowledge base and execution traces, diagnose root causes,
and propose ONE atomic skill change (create or patch) to the procedural skill set that is
injected into the inference agent's system prompt.

## Protocol (STRICT)
Respond with EXACTLY ONE JSON object per turn, nothing else:
- {\"tool\": \"read_file\", \"path\": \"wiki/index.md\"} -- read a workspace file
- {\"tool\": \"finish\", \"proposal\": {...}} -- submit the final proposal

Readable paths: wiki/index.md, wiki/logs.md, wiki/skill-impact.md,
wiki/patterns/<name>.md, traces/<trace-id>, skills/<name>/SKILL.md

## Proposal format (inside \"proposal\")
Create: {\"action\": \"create\", \"name\": \"kebab-case-name\", \"skill_md\": \"...\", \"purpose_md\": \"...\", \"rationale\": \"...\"}
Patch: {\"action\": \"patch\", \"name\": \"existing-name\", \"edits\": [{\"op\": \"append\"|\"replace\"|\"insert_after\", \"target\": \"exact text\", \"content\": \"...\"}], \"purpose_md\": \"...\", \"rationale\": \"...\"}
No change needed: {\"action\": \"no_action\", \"rationale\": \"...\"}

## Rules
1. Read wiki/skill-impact.md FIRST -- it contains full content of rejected proposals.
   DO NOT repeat a rejected approach.
2. Read relevant pattern pages and at least the failing traces before proposing.
3. Skills are injected into a system prompt and may be truncated to their first
   400 characters: put the essential instruction in the FIRST 400 characters.
4. Keep skills concise (<= 60 lines), concrete action rules, no essays.
5. Prefer patching an existing skill over creating a new one when it is partially correct.
6. One atomic proposal targeting a single skill.";

(* サンドボックス: wiki/ traces/ skills/ のみ。traces/<id> は raw/iter-<k>/ へ解決。 *)
iTWSandboxRead[path_String, maxChars_Integer] := Module[{p = path, iter, full, c},
  If[StringContainsQ[p, ".."] || StringStartsQ[p, "/"] || StringContainsQ[p, ":"],
    Return["ERROR: path not allowed"]];
  p = StringReplace[p, "\\" -> "/"];
  Which[
    StringStartsQ[p, "traces/"],
      iter = Lookup[iTWLoadState[], "Iteration", 0],
    True, iter = Null];
  full = Which[
    StringStartsQ[p, "wiki/"],
      iTWPath @@ StringSplit[p, "/"],
    StringStartsQ[p, "skills/"],
      iTWPath @@ StringSplit[p, "/"],
    StringStartsQ[p, "traces/"],
      iTWPath["raw", "iter-" <> ToString[iter],
        StringReplace[StringDrop[p, StringLength["traces/"]], "/" -> ""] <>
        If[StringEndsQ[p, ".json"], "", ".json"]],
    True, Missing["Denied"]];
  If[MissingQ[full], Return["ERROR: path not allowed"]];
  c = iTWReadFile[full];
  If[!StringQ[c], Return["ERROR: not found: " <> p]];
  If[StringStartsQ[p, "traces/"],
    (* raw トレース JSON は Text フィールドを本文として返す。 *)
    Module[{a = iTWFromJSON[c]},
      If[AssociationQ[a],
        iTWTruncate["Task: " <> ToString[Lookup[a, "Task", ""]] <> "\n" <>
          ToString[Lookup[a, "Text", ""]], maxChars],
        iTWTruncate[c, maxChars]]],
    iTWTruncate[c, maxChars]]];

iTWListCurrentTraces[] := Module[{iter, files},
  iter = Lookup[iTWLoadState[], "Iteration", 0];
  files = Quiet @ Check[FileNames["*.json", iTWPath["raw", "iter-" <> ToString[iter]]], {}];
  StringReplace[FileNameTake[#], ".json" ~~ EndOfString -> ""] & /@ files];

Options[ClaudeTurnWikiPropose] = {
  "LLMFn" -> Automatic, "MaxTurns" -> 12, "MaxFileChars" -> 16000,
  "TaskSummary" -> Automatic, "ModelProfile" -> Automatic};

ClaudeTurnWikiPropose[opts : OptionsPattern[]] := Module[
  {llmFn, maxTurns = OptionValue["MaxTurns"], maxChars = OptionValue["MaxFileChars"],
   convo, resp, parsed, tool, path, result = Missing["NoProposal"], nudges = 0,
   lastSig = "", sameSigCount = 0, summary, traceIds, st, turnsUsed = 0},
  llmFn = iTWResolveLLMFn[OptionValue["LLMFn"]];
  If[MissingQ[llmFn], Return[<|"Action" -> "no_action", "Status" -> "LLMUnavailable"|>]];
  ClaudeTurnWikiInitialize[];
  st = iTWLoadState[];
  traceIds = iTWListCurrentTraces[];
  summary = If[OptionValue["TaskSummary"] =!= Automatic,
    ToString[OptionValue["TaskSummary"]],
    With[{profile = iTWNormProfile[OptionValue["ModelProfile"]]},
      "Iteration: " <> ToString[Lookup[st, "Iteration", 0]] <>
      "\nModel profile: " <> profile <>
      "\nActive skills: " <> ToString[iTWProfileActiveSkills[profile]] <>
      "\nAvailable traces: " <> StringRiffle[("traces/" <> # &) /@ traceIds, ", "]]];
  convo = "## Workspace summary\n" <> summary <>
    "\n\n=== wiki/index.md ===\n" <>
      With[{c = iTWReadFile[iTWPath["wiki", "index.md"]]}, If[StringQ[c], c, ""]] <>
    "\n\n=== wiki/skill-impact.md ===\n" <>
      iTWTruncate[ClaudeTurnWikiSkillImpact[], 8000] <>
    "\n\nRespond with your next JSON action.";
  Do[
    turnsUsed = i;
    resp = iTWCallLLM[llmFn, convo, $iTWProposerSysPrompt];
    If[!StringQ[resp],
      result = <|"Action" -> "no_action", "Status" -> "LLMFailed"|>; Break[]];
    parsed = iTWParseJSONLenient[resp];
    Which[
      !AssociationQ[parsed],
        nudges++;
        If[nudges > 1,
          result = <|"Action" -> "no_action", "Status" -> "ParseFailed",
            "Raw" -> iTWTruncate[resp, 1000]|>; Break[]];
        convo = convo <> "\n\n[system] Your last response was not a single valid JSON action object. Respond with ONLY one JSON object.",
      ToString[Lookup[parsed, "tool", ""]] === "finish",
        result = ClaudeTurnWikiParseProposal[Lookup[parsed, "proposal", <||>]];
        Break[],
      ToString[Lookup[parsed, "tool", ""]] === "read_file",
        path = ToString[Lookup[parsed, "path", ""]];
        (* 同一 read の堂々巡りガード (claudecode-eval-loop-guard と同発想)。 *)
        If[path === lastSig, sameSigCount++, sameSigCount = 0; lastSig = path];
        If[sameSigCount >= 2,
          result = <|"Action" -> "no_action", "Status" -> "LoopGuard", "Path" -> path|>;
          Break[]];
        convo = convo <> "\n\n=== read_file: " <> path <> " ===\n" <>
          iTWSandboxRead[path, maxChars] <>
          "\n\nRespond with your next JSON action.",
      (* finish 相当を直接返してくるモデルへの寛容: proposal 形をしていれば受ける。 *)
      KeyExistsQ[parsed, "action"],
        result = ClaudeTurnWikiParseProposal[parsed]; Break[],
      True,
        nudges++;
        If[nudges > 1,
          result = <|"Action" -> "no_action", "Status" -> "UnknownTool"|>; Break[]];
        convo = convo <> "\n\n[system] Unknown tool. Use read_file or finish."],
    {i, maxTurns}];
  If[MissingQ[result],
    result = <|"Action" -> "no_action", "Status" -> "Exhausted"|>];
  Append[result, "TurnsUsed" -> turnsUsed]];

(* ::Subsection:: *)
(* Probes / Validation / Gate *)

ClaudeTurnWikiAddProbe[probe_Association] := Module[{pid, p = probe},
  ClaudeTurnWikiInitialize[];
  pid = ToString[Lookup[p, "ProbeId", "probe-" <> StringTake[Hash[p, "SHA256", "HexString"], 12]]];
  p["ProbeId"] = pid;
  iTWWriteFile[iTWPath["probes", pid <> ".json"], iTWToJSON[p]];
  <|"Status" -> "OK", "ProbeId" -> pid|>];

ClaudeTurnWikiAddProbe[task_String, expected_] :=
  ClaudeTurnWikiAddProbe[<|"Task" -> task, "Expected" -> expected, "Kind" -> "contains"|>];

ClaudeTurnWikiProbes[] := Module[{files},
  files = Quiet @ Check[FileNames["*.json", iTWPath["probes"]], {}];
  Select[
    Map[Function[f, With[{c = iTWReadFile[f]}, If[StringQ[c], iTWFromJSON[c], $Failed]]], Sort[files]],
    AssociationQ]];

ClaudeTurnWikiProbeFromTrace[trace_Association] :=
  <|"ProbeId" -> "probe-" <> ToString[Lookup[trace, "TraceId", "x"]],
    "Task" -> ToString[Lookup[trace, "Task", ""]],
    "Expected" -> Missing["FillMe"],
    "Kind" -> "contains",
    "OriginTraceId" -> Lookup[trace, "TraceId", Missing[]]|>;

(* 既定の probe 評価: 手順書を注入した 1 発 LLM 回答に Expected が含まれるか。
   Expected 無し probe は pass (WiCER iSVMDefaultProbeEval と同規約)。 *)
iTWDefaultProbeEval[probe_Association, skillsText_String, llmFn_] := Module[{exp, task, sys, resp},
  exp = Lookup[probe, "Expected", Missing["NoExpected"]];
  If[MissingQ[exp] || exp === Null, Return[True]];
  task = ToString[Lookup[probe, "Task", ""]];
  If[MissingQ[llmFn], Return[Missing["LLMUnavailable"]]];
  sys = "You are an inference agent executing a task." <>
    If[skillsText =!= "",
      "\n\n## Procedural skills (follow them)\n" <> skillsText, ""];
  resp = iTWCallLLM[llmFn, task <> "\n\nAnswer concisely.", sys];
  If[!StringQ[resp], Return[Missing["LLMFailed"]]];
  Module[{exps = Flatten[{exp}]},
    AllTrue[exps, StringContainsQ[resp, ToString[#], IgnoreCase -> True] &]]];

(* per-profile validation LLM: explicit option > $ClaudeTurnWikiProfileLLMFns
   > default local LLM. Probes are PL 0 tasks with expected substrings, so a
   cloud fn may be registered for a cloud profile by the user. *)
If[!AssociationQ[$ClaudeTurnWikiProfileLLMFns], $ClaudeTurnWikiProfileLLMFns = <||>];
iTWResolveProfileLLMFn[profile_String, opt_] := Which[
  opt =!= Automatic && opt =!= None, opt,
  KeyExistsQ[$ClaudeTurnWikiProfileLLMFns, profile] &&
    $ClaudeTurnWikiProfileLLMFns[profile] =!= None, $ClaudeTurnWikiProfileLLMFns[profile],
  True, iTWResolveLLMFn[Automatic]];

Options[ClaudeTurnWikiValidate] = {
  "Skills" -> Automatic, "Probes" -> Automatic,
  "EvalFn" -> Automatic, "LLMFn" -> Automatic,
  "ModelProfile" -> Automatic};

ClaudeTurnWikiValidate[opts : OptionsPattern[]] := Module[
  {skills, probes, evalFn, llmFn, skillsText, runs, passed, failed, score,
   profile = iTWNormProfile[OptionValue["ModelProfile"]]},
  skills = OptionValue["Skills"];
  If[skills === Automatic, skills = ClaudeTurnWikiActiveSkills[profile]];
  probes = OptionValue["Probes"];
  If[probes === Automatic, probes = ClaudeTurnWikiProbes[]];
  If[!ListQ[probes] || probes === {},
    Return[<|"Status" -> "NoProbes", "Score" -> Missing["NoProbes"], "Runs" -> {}|>]];
  llmFn = iTWResolveProfileLLMFn[profile, OptionValue["LLMFn"]];
  evalFn = OptionValue["EvalFn"];
  If[evalFn === Automatic,
    evalFn = Function[{pr, sk}, iTWDefaultProbeEval[pr, sk, llmFn]]];
  skillsText = iTWSkillsText[If[AssociationQ[skills], skills, <||>]];
  runs = Map[
    Function[pr,
      Module[{r = Quiet @ Check[evalFn[pr, skillsText], $Failed]},
        <|"ProbeId" -> Lookup[pr, "ProbeId", "?"],
          "Result" -> Which[TrueQ[r], "pass", r === False, "fail", True, "error"],
          "Detail" -> If[TrueQ[r] || r === False, Missing[], r]|>]],
    probes];
  passed = Count[runs, a_Association /; a["Result"] === "pass"];
  failed = Count[runs, a_Association /; a["Result"] =!= "pass"];
  score = N[passed / Max[1, Length[runs]]];
  <|"Status" -> If[AnyTrue[runs, #["Result"] === "error" &], "PartialError", "OK"],
    "Score" -> score, "Passed" -> passed, "Failed" -> failed, "Runs" -> runs,
    "Profile" -> profile|>];

(* fail-closed: 数値スコア同士の厳密な > のみ Accepted (論文 Eq.4)。 *)
ClaudeTurnWikiGateDecision[cand_, rBest_] := Which[
  !NumberQ[cand], "Rejected",
  !NumberQ[rBest], "Rejected",
  cand > rBest, "Accepted",
  True, "Rejected"];

(* ::Subsection:: *)
(* skill-impact 台帳 (I2: 没案も残す。ハーネスが機械的に追記) *)

ClaudeTurnWikiAppendSkillImpact[entry_Association] := Module[{md, jl, iter},
  ClaudeTurnWikiInitialize[];
  iter = Lookup[entry, "Iteration", Lookup[iTWLoadState[], "Iteration", 0]];
  md = "\n## " <> iTWNowISO[] <> " iteration " <> ToString[iter] <> " -- " <>
    ToString[Lookup[entry, "Outcome", "?"]] <> "\n" <>
    "- Proposal: " <> ToString[Lookup[entry, "Action", "?"]] <>
      " `" <> ToString[Lookup[entry, "Name", "-"]] <> "`\n" <>
    "- ValidationScore: " <> ToString[Lookup[entry, "Score", "-"]] <>
      " (RBest was " <> ToString[Lookup[entry, "RBest", "-"]] <> ")\n" <>
    "- Rationale: " <> iTWTruncate[ToString[Lookup[entry, "Rationale", ""]], 600] <> "\n" <>
    If[KeyExistsQ[entry, "Content"] && StringQ[entry["Content"]],
      "- Proposed content:\n```\n" <> iTWTruncate[entry["Content"], 4000] <> "\n```\n", ""] <>
    If[KeyExistsQ[entry, "Edits"] && entry["Edits"] =!= {},
      "- Edits:\n```json\n" <> iTWTruncate[ToString[iTWToJSON[entry["Edits"]]], 4000] <> "\n```\n", ""];
  iTWAppendFile[iTWPath["wiki", "skill-impact.md"], md];
  jl = iTWToJSON[Append[KeyDrop[entry, {}], <|"At" -> iTWNowISO[], "Iteration" -> iter|>]];
  If[StringQ[jl], iTWAppendFile[iTWPath["wiki", "skill-impact.jsonl"], jl <> "\n"]];
  <|"Status" -> "OK"|>];

ClaudeTurnWikiSkillImpact[] :=
  With[{c = iTWReadFile[iTWPath["wiki", "skill-impact.md"]]}, If[StringQ[c], c, ""]];

(* ::Subsection:: *)
(* 反復 step 関数 (direct / Orchestrator 共有) *)

(* 評価が健全 (Status OK) なときだけベースライン確定。エラー混じりの
   0 点を RBest に固定しない (fail-closed だが junk baseline も作らない)。 *)
iTWStepEnsureBaseline[llmFn_, evalFn_, profileIn_ : Automatic] := Module[
  {profile = iTWNormProfile[profileIn], ps, v},
  ps = iTWProfileState[profile];
  If[NumberQ[Lookup[ps, "RBest", Null]], Return[iTWProfileRBest[profile]]];
  v = ClaudeTurnWikiValidate["Skills" -> Automatic, "EvalFn" -> evalFn, "LLMFn" -> llmFn,
    "ModelProfile" -> profile];
  If[NumberQ[v["Score"]] && v["Status"] === "OK",
    iTWSaveProfileState[profile, <|"RBest" -> v["Score"]|>]; v["Score"],
    Missing["NoBaseline"]]];

iTWStepGate[proposal_Association, llmFn_, evalFn_, profileIn_ : Automatic] := Module[
  {name, applied, validation, score, rBest, decision, entry, iterNow,
   profile = iTWNormProfile[profileIn]},
  iterNow = Lookup[iTWLoadState[], "Iteration", 0];
  name = Lookup[proposal, "Name", Missing[]];
  applied = ClaudeTurnWikiApplyProposal[proposal, profile];
  If[applied["Status"] =!= "Staged",
    ClaudeTurnWikiAppendSkillImpact[<|
      "Outcome" -> "Rejected", "Action" -> Lookup[proposal, "Action", "?"],
      "Name" -> name, "Profile" -> profile,
      "Score" -> Missing[], "RBest" -> iTWProfileRBest[profile],
      "Rationale" -> "Apply failed: " <> ToString[applied["Status"]],
      "Iteration" -> iterNow|>];
    Return[<|"Decision" -> "Rejected", "Reason" -> applied["Status"], "Validation" -> Missing[]|>]];
  validation = ClaudeTurnWikiValidate[
    "Skills" -> applied["CandidateSkills"], "EvalFn" -> evalFn, "LLMFn" -> llmFn,
    "ModelProfile" -> profile];
  score = validation["Score"];
  rBest = iTWProfileRBest[profile];
  decision = ClaudeTurnWikiGateDecision[score, rBest];
  entry = <|
    "Outcome" -> decision, "Action" -> Lookup[proposal, "Action", "?"],
    "Name" -> name, "Profile" -> profile, "Score" -> score, "RBest" -> rBest,
    "Rationale" -> Lookup[proposal, "Rationale", ""],
    "Iteration" -> iterNow|>;
  If[MemberQ[{"create", "transfer"}, Lookup[proposal, "Action", ""]],
    entry["Content"] = Lookup[proposal, "SkillMD", ""]];
  If[Lookup[proposal, "Action", ""] === "patch",
    entry["Edits"] = Lookup[proposal, "Edits", {}]];
  ClaudeTurnWikiAppendSkillImpact[entry];
  If[decision === "Accepted",
    ClaudeTurnWikiPromote[name,
      Lookup[applied["CandidateSkills"], name, ""],
      Lookup[proposal, "PurposeMD", ""], score, <|"Profile" -> profile|>],
    ClaudeTurnWikiReject[name]];
  <|"Decision" -> decision, "Validation" -> validation, "Profile" -> profile,
    "RBest" -> If[decision === "Accepted", score, rBest]|>];

iTWBumpIteration[] := Module[{st = iTWLoadState[]},
  st["Iteration"] = Lookup[st, "Iteration", 0] + 1;
  iTWSaveState[st];
  st["Iteration"]];

(* ::Subsection:: *)
(* 反復ドライバ (direct + Orchestrator) *)

iTWOrchestratorAvailableQ[] :=
  iTWValueQ["ClaudeOrchestrator`Workflow`$WorkflowVersion"] &&
  iTWCallableQ["ClaudeOrchestrator`Workflow`ClaudeCreateWorkflowNet"];

Options[ClaudeTurnWikiRunIteration] = {
  "LLMFn" -> Automatic, "TracesFn" -> Automatic, "EvalFn" -> Automatic,
  "UseOrchestrator" -> Automatic, "MaxProposerTurns" -> 12,
  "MaxFail" -> 5, "MaxPass" -> 3,
  (* 2026-09-08: Automatic = "default" (all models, global state);
     "provider:model" = traces / RBest / ActiveSkills / validation of that
     model profile only (the evolved rule is scoped with models: frontmatter) *)
  "ModelProfile" -> Automatic};

ClaudeTurnWikiRunIteration[opts : OptionsPattern[]] := Module[
  {useOrch = OptionValue["UseOrchestrator"], iso},
  ClaudeTurnWikiInitialize[];
  iso = ClaudeTurnWikiCheckIsolation[];
  If[!TrueQ[iso["OK"]],
    Return[<|"Status" -> "IsolationViolation", "Detail" -> iso["Detail"]|>]];
  If[useOrch === Automatic, useOrch = iTWOrchestratorAvailableQ[]];
  If[TrueQ[useOrch] && iTWOrchestratorAvailableQ[],
    iTWRunIterationViaOrchestrator[opts],
    iTWRunIterationDirect[opts]]];

iTWRunIterationDirect[opts : OptionsPattern[ClaudeTurnWikiRunIteration]] := Module[
  {llmFn, evalFn, traces, maintain, proposal, gate, baseline, iterBefore, profile, valFn},
  profile = iTWNormProfile[OptionValue[ClaudeTurnWikiRunIteration, {opts}, "ModelProfile"]];
  llmFn = iTWResolveLLMFn[OptionValue[ClaudeTurnWikiRunIteration, {opts}, "LLMFn"]];
  (* validation answers come from the profile's own model when registered *)
  valFn = iTWResolveProfileLLMFn[profile, OptionValue[ClaudeTurnWikiRunIteration, {opts}, "LLMFn"]];
  evalFn = OptionValue[ClaudeTurnWikiRunIteration, {opts}, "EvalFn"];
  iterBefore = Lookup[iTWLoadState[], "Iteration", 0];
  baseline = iTWStepEnsureBaseline[valFn, evalFn, profile];
  traces = ClaudeTurnWikiCollectTraces[
    "TracesFn" -> OptionValue[ClaudeTurnWikiRunIteration, {opts}, "TracesFn"],
    "MaxFail" -> OptionValue[ClaudeTurnWikiRunIteration, {opts}, "MaxFail"],
    "MaxPass" -> OptionValue[ClaudeTurnWikiRunIteration, {opts}, "MaxPass"],
    "ModelProfile" -> profile];
  If[traces === {},
    Return[<|"Status" -> "NoTraces", "Iteration" -> iterBefore, "Baseline" -> baseline,
      "Profile" -> profile|>]];
  maintain = ClaudeTurnWikiMaintain[traces, "LLMFn" -> llmFn, "Iteration" -> iterBefore];
  If[maintain["Status"] === "LLMUnavailable",
    Return[<|"Status" -> "LLMUnavailable", "Iteration" -> iterBefore,
      "Traces" -> Length[traces], "Profile" -> profile|>]];
  proposal = ClaudeTurnWikiPropose["LLMFn" -> llmFn,
    "MaxTurns" -> OptionValue[ClaudeTurnWikiRunIteration, {opts}, "MaxProposerTurns"],
    "ModelProfile" -> profile];
  If[Lookup[proposal, "Action", ""] === "no_action",
    ClaudeTurnWikiAppendSkillImpact[<|
      "Outcome" -> "NoAction", "Action" -> "no_action", "Name" -> "-",
      "Profile" -> profile,
      "Score" -> Missing[], "RBest" -> iTWProfileRBest[profile],
      "Rationale" -> ToString[Lookup[proposal, "Rationale",
        ToString[Lookup[proposal, "Status", ""]]]],
      "Iteration" -> iterBefore|>];
    iTWBumpIteration[];
    Return[<|"Status" -> "NoAction", "Iteration" -> iterBefore, "Profile" -> profile,
      "Traces" -> Length[traces], "Maintain" -> maintain, "Proposal" -> proposal|>]];
  gate = iTWStepGate[proposal, valFn, evalFn, profile];
  iTWBumpIteration[];
  <|"Status" -> "OK", "Iteration" -> iterBefore, "Mode" -> "Direct", "Profile" -> profile,
    "Traces" -> Length[traces], "Maintain" -> KeyDrop[maintain, {"RawResponse"}],
    "Proposal" -> KeyTake[proposal, {"Action", "Name", "Status", "TurnsUsed"}],
    "Decision" -> gate["Decision"], "Validation" -> Lookup[gate, "Validation", Missing[]],
    "RBest" -> iTWProfileRBest[profile]|>];

(* Orchestrator 経路: 分岐は Guard 純関数、LLM は transition handler のみ
   (WiCER iSVMWikiCompileNetWith と同型)。step 関数は direct と共有。 *)
iTWPay[b_] := Lookup[First[Values[b], <||>], "Payload", <||>];

iTWRunIterationViaOrchestrator[opts : OptionsPattern[ClaudeTurnWikiRunIteration]] := Module[
  {WN, WP, WT, WTok, llmFn, evalFn, tracesFn, maxFail, maxPass, maxProposer,
   net, wid, runRes, state, marking, tokens, finTok, payload, iterBefore, baseline,
   profile, valFn},
  WN = ToExpression["ClaudeOrchestrator`Workflow`WorkflowNet"];
  WP = ToExpression["ClaudeOrchestrator`Workflow`WorkflowPlace"];
  WT = ToExpression["ClaudeOrchestrator`Workflow`WorkflowTransition"];
  WTok = ToExpression["ClaudeOrchestrator`Workflow`WorkflowToken"];
  profile = iTWNormProfile[OptionValue[ClaudeTurnWikiRunIteration, {opts}, "ModelProfile"]];
  llmFn = iTWResolveLLMFn[OptionValue[ClaudeTurnWikiRunIteration, {opts}, "LLMFn"]];
  valFn = iTWResolveProfileLLMFn[profile, OptionValue[ClaudeTurnWikiRunIteration, {opts}, "LLMFn"]];
  evalFn = OptionValue[ClaudeTurnWikiRunIteration, {opts}, "EvalFn"];
  tracesFn = OptionValue[ClaudeTurnWikiRunIteration, {opts}, "TracesFn"];
  maxFail = OptionValue[ClaudeTurnWikiRunIteration, {opts}, "MaxFail"];
  maxPass = OptionValue[ClaudeTurnWikiRunIteration, {opts}, "MaxPass"];
  maxProposer = OptionValue[ClaudeTurnWikiRunIteration, {opts}, "MaxProposerTurns"];
  iterBefore = Lookup[iTWLoadState[], "Iteration", 0];
  baseline = iTWStepEnsureBaseline[valFn, evalFn, profile];
  net = WN[
    "SourcePlace" -> "Start",
    "FinalPlaces" -> {"DoneAccepted", "DoneRejected", "DoneNoAction", "DoneError"},
    "Places" -> <|
      "Start" -> WP["Start"], "Collected" -> WP["Collected"],
      "Maintained" -> WP["Maintained"], "Proposed" -> WP["Proposed"],
      "Decided" -> WP["Decided"],
      "DoneAccepted" -> WP["DoneAccepted"], "DoneRejected" -> WP["DoneRejected"],
      "DoneNoAction" -> WP["DoneNoAction"], "DoneError" -> WP["DoneError"]|>,
    "Transitions" -> <|
      "Collect" -> WT["Collect", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Start"|>}, "OutputArcs" -> {<|"Place" -> "Collected"|>},
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          Module[{traces = ClaudeTurnWikiCollectTraces[
              "TracesFn" -> tracesFn, "MaxFail" -> maxFail, "MaxPass" -> maxPass,
              "ModelProfile" -> profile]},
            WTok["Kind" -> "Control", "Payload" ->
              Append[iTWPay[b], <|"Traces" -> traces, "Profile" -> profile|>]]]]|>],
      "Maintain" -> WT["Maintain", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Collected"|>}, "OutputArcs" -> {<|"Place" -> "Maintained"|>},
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          Module[{p = iTWPay[b], m},
            m = If[Lookup[p, "Traces", {}] === {},
              <|"Status" -> "NoTraces"|>,
              ClaudeTurnWikiMaintain[p["Traces"], "LLMFn" -> llmFn, "Iteration" -> iterBefore]];
            WTok["Kind" -> "Control", "Payload" ->
              Append[p, <|"Maintain" -> KeyDrop[m, {"RawResponse"}]|>]]]]|>],
      "Propose" -> WT["Propose", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Maintained"|>}, "OutputArcs" -> {<|"Place" -> "Proposed"|>},
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          Module[{p = iTWPay[b], prop},
            prop = ClaudeTurnWikiPropose["LLMFn" -> llmFn, "MaxTurns" -> maxProposer,
              "ModelProfile" -> profile];
            WTok["Kind" -> "Control", "Payload" -> Append[p, <|"Proposal" -> prop|>]]]]|>],
      "GateApply" -> WT["GateApply", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Proposed"|>}, "OutputArcs" -> {<|"Place" -> "Decided"|>},
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          Module[{p = iTWPay[b], prop = Lookup[iTWPay[b], "Proposal", <||>], g},
            If[Lookup[prop, "Action", ""] === "no_action",
              ClaudeTurnWikiAppendSkillImpact[<|
                "Outcome" -> "NoAction", "Action" -> "no_action", "Name" -> "-",
                "Profile" -> profile,
                "Score" -> Missing[], "RBest" -> iTWProfileRBest[profile],
                "Rationale" -> ToString[Lookup[prop, "Rationale", ""]],
                "Iteration" -> iterBefore|>];
              WTok["Kind" -> "Control", "Payload" -> Append[p, <|"Decision" -> "NoAction"|>]],
              g = iTWStepGate[prop, valFn, evalFn, profile];
              WTok["Kind" -> "Control", "Payload" ->
                Append[p, <|"Decision" -> g["Decision"], "Validation" -> Lookup[g, "Validation", Missing[]]|>]]]]]|>],
      "FinishAccepted" -> WT["FinishAccepted", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Decided"|>}, "OutputArcs" -> {<|"Place" -> "DoneAccepted"|>},
        "Guard" -> Function[b, Lookup[iTWPay[b], "Decision", ""] === "Accepted"],
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          WTok["Kind" -> "Artifact", "Payload" -> iTWPay[b]]]|>],
      "FinishRejected" -> WT["FinishRejected", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Decided"|>}, "OutputArcs" -> {<|"Place" -> "DoneRejected"|>},
        "Guard" -> Function[b, Lookup[iTWPay[b], "Decision", ""] === "Rejected"],
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          WTok["Kind" -> "Artifact", "Payload" -> iTWPay[b]]]|>],
      "FinishNoAction" -> WT["FinishNoAction", "Executor" -> "PureFunction",
        "InputArcs" -> {<|"Place" -> "Decided"|>}, "OutputArcs" -> {<|"Place" -> "DoneNoAction"|>},
        "Guard" -> Function[b, !MemberQ[{"Accepted", "Rejected"}, Lookup[iTWPay[b], "Decision", ""]]],
        "RuntimeSpec" -> <|"Handler" -> Function[b,
          WTok["Kind" -> "Artifact", "Payload" -> iTWPay[b]]]|>]|>];
  wid = ToExpression["ClaudeOrchestrator`Workflow`ClaudeCreateWorkflowNet"][net];
  If[!StringQ[wid],
    Return[<|"Status" -> "CreateFailed", "Detail" -> wid|>]];
  ToExpression["ClaudeOrchestrator`Workflow`ClaudeSubmitInputs"][wid, <|"Iteration" -> iterBefore|>];
  runRes = ToExpression["ClaudeOrchestrator`Workflow`ClaudeRunWorkflow"][
    wid, "Async" -> False, "MaxWait" -> Quantity[3600, "Seconds"]];
  (* 結果抽出は marking 由来のみ (closure 非依存 = restore 後も抽出可)。 *)
  state = Quiet @ Check[ToExpression["ClaudeOrchestrator`Workflow`ClaudeWorkflowState"][wid], <||>];
  marking = Lookup[state, "Marking", <||>];
  tokens = Lookup[state, "Tokens", <||>];
  finTok = First[
    Join @@ (Lookup[marking, #, {}] & /@ {"DoneAccepted", "DoneRejected", "DoneNoAction", "DoneError"}),
    Missing["NoToken"]];
  payload = If[MissingQ[finTok], <||>, Lookup[Lookup[tokens, finTok, <||>], "Payload", <||>]];
  iTWBumpIteration[];
  <|"Status" -> "OK", "Iteration" -> iterBefore, "Mode" -> "Orchestrator", "Profile" -> profile,
    "WorkflowId" -> wid, "RunStatus" -> Lookup[If[AssociationQ[runRes], runRes, <||>], "Status", "?"],
    "Traces" -> Length[Lookup[payload, "Traces", {}]],
    "Maintain" -> Lookup[payload, "Maintain", Missing[]],
    "Proposal" -> KeyTake[Lookup[payload, "Proposal", <||>], {"Action", "Name", "Status", "TurnsUsed"}],
    "Decision" -> Lookup[payload, "Decision", Missing[]],
    "Validation" -> Lookup[payload, "Validation", Missing[]],
    "RBest" -> iTWProfileRBest[profile]|>];

Options[ClaudeTurnWikiRun] = Options[ClaudeTurnWikiRunIteration];

ClaudeTurnWikiRun[k_Integer?Positive, opts : OptionsPattern[]] := Module[{results = {}, r, rb},
  Do[
    rb = iTWRBest[];
    If[NumberQ[rb] && rb >= 1.0, Break[]];  (* 早期終了 (Algorithm 1 line 4) *)
    r = ClaudeTurnWikiRunIteration[opts];
    AppendTo[results, r];
    If[MemberQ[{"IsolationViolation", "LLMUnavailable"}, Lookup[r, "Status", ""]], Break[]],
    {k}];
  results];

(* ::Subsection:: *)
(* 定期維持 tick (service/heartbeat 用): 設定 / watermark / 排他ロック *)

(* 設定は root 直下の settings.json に永続化 = 対話カーネルの設定欄で ON にした
   値を headless の service カーネルが Dropbox 経由でそのまま読める。 *)
$iTWDefaultSettings = <|"AutoMaintain" -> False, "MaintainIntervalSeconds" -> 21600|>;

iTWSettingsPath[] := iTWPath["settings.json"];

ClaudeTurnWikiSettings[] := Module[{s = iTWReadFile[iTWSettingsPath[]], a},
  a = If[StringQ[s], iTWFromJSON[s], $Failed];
  If[AssociationQ[a], Join[$iTWDefaultSettings, a], $iTWDefaultSettings]];

iTWSaveSettings[a_Association] := (
  ClaudeTurnWikiInitialize[];
  iTWWriteFile[iTWSettingsPath[], iTWToJSON[Append[a, "UpdatedAt" -> iTWNowISO[]]]]);

ClaudeTurnWikiSetAutoMaintain[flag : (True | False)] :=
  ClaudeTurnWikiSetAutoMaintain[flag, Automatic];
ClaudeTurnWikiSetAutoMaintain[flag : (True | False), interval_] := Module[
  {s = ClaudeTurnWikiSettings[]},
  s["AutoMaintain"] = flag;
  If[NumberQ[interval] && interval > 0, s["MaintainIntervalSeconds"] = interval];
  iTWSaveSettings[s];
  KeyTake[ClaudeTurnWikiSettings[], {"AutoMaintain", "MaintainIntervalSeconds"}]];

ClaudeTurnWikiAutoMaintainQ[] :=
  TrueQ[Lookup[ClaudeTurnWikiSettings[], "AutoMaintain", False]];

ClaudeTurnWikiSetAutoLevel[flag : (True | False)] := Module[{s = ClaudeTurnWikiSettings[]},
  s["AutoLevel"] = flag;
  iTWSaveSettings[s];
  KeyTake[ClaudeTurnWikiSettings[], {"AutoLevel"}]];
ClaudeTurnWikiAutoLevelQ[] := TrueQ[Lookup[ClaudeTurnWikiSettings[], "AutoLevel", False]];

(* ::Subsection:: *)
(* Adaptive DirectiveLevel per model profile (2026-09-08)

   The "how many rules does this model need" knob (ClaudeDirectives
   DirectiveLevel) is tuned from the failure record: a profile whose traces
   keep failing gets one step more explicit guidance (Minimal -> Standard ->
   Full); a profile with a sustained clean record steps back down, never below
   its capability baseline (the table entry / class). Pure arithmetic, no LLM.
   Persisted in <root>/directive-levels.json (Dropbox-shared) and installed as
   ClaudeDirectives`$ClaudeDirectiveLevelOverrides when that package is loaded;
   a resolver hook re-reads the file in kernels that load later. *)

If[!AssociationQ[$ClaudeTurnWikiLevelPolicy],
  $ClaudeTurnWikiLevelPolicy = <|"MinTraces" -> 6, "EscalateFailRatio" -> 0.4,
    "DeescalateFailRatio" -> 0.1, "DeescalateMinTraces" -> 12|>];
$iTWLevels = {"Minimal", "Standard", "Full"};
iTWLevelIndex[l_] := With[{p = Position[$iTWLevels, l]}, If[p === {}, 2, p[[1, 1]]]];
iTWLevelStep[l_, d_Integer] := $iTWLevels[[Clip[iTWLevelIndex[l] + d, {1, Length[$iTWLevels]}]]];
iTWLevelsPath[] := iTWPath["directive-levels.json"];

ClaudeTurnWikiDirectiveLevels[] := Module[{s = iTWReadFile[iTWLevelsPath[]], a},
  a = If[StringQ[s], iTWFromJSON[s], $Failed];
  If[AssociationQ[a], a, <||>]];

iTWDirectivesLevelAPIQ[] := iTWCallableQ["ClaudeDirectives`ClaudeResolveDirectiveLevel"];

(* current level as ClaudeDirectives would resolve it (override > resolver >
   capability > class), else the persisted file, else Standard *)
iTWCurrentLevel[profile_String] := Module[{spec = iTWProfileSpec[profile], r, persisted},
  If[iTWDirectivesLevelAPIQ[],
    r = Quiet @ Check[ToExpression["ClaudeDirectives`ClaudeResolveDirectiveLevel"][spec], $Failed];
    If[AssociationQ[r] && StringQ[Lookup[r, "Level", None]],
      Return[<|"Level" -> r["Level"], "Source" -> Lookup[r, "Source", "?"]|>]]];
  persisted = Lookup[ClaudeTurnWikiDirectiveLevels[], profile, <||>];
  If[AssociationQ[persisted] && StringQ[Lookup[persisted, "Level", None]],
    <|"Level" -> persisted["Level"], "Source" -> "persisted"|>,
    <|"Level" -> "Standard", "Source" -> "default"|>]];

(* capability baseline: ignore overrides and the resolver hook *)
iTWBaseLevel[profile_String] := Module[{spec = iTWProfileSpec[profile], r},
  If[!iTWDirectivesLevelAPIQ[], Return["Standard"]];
  r = Quiet @ Check[
    ToExpression["Block[{ClaudeDirectives`$ClaudeDirectiveLevelOverrides = <||>, " <>
      "ClaudeDirectives`$ClaudeDirectiveLevelResolver = None}, " <>
      "ClaudeDirectives`ClaudeResolveDirectiveLevel[" <> ToString[spec, InputForm] <> "]]"],
    $Failed];
  If[AssociationQ[r] && StringQ[Lookup[r, "Level", None]], r["Level"], "Standard"]];

Options[ClaudeTurnWikiDirectiveLevelAdvice] = {"Traces" -> Automatic};
ClaudeTurnWikiDirectiveLevelAdvice[opts : OptionsPattern[]] := Module[
  {traces, pol = $ClaudeTurnWikiLevelPolicy, groups, minN, esc, de, deMin},
  traces = OptionValue["Traces"];
  If[traces === Automatic, traces = ClaudeTurnWikiTraces[]];
  traces = iTWEnsureTraceProfile /@ Select[traces, AssociationQ];
  traces = Select[traces, !MemberQ[{"unknown", $iTWDefaultProfile}, Lookup[#, "Profile", "unknown"]] &];
  minN = Lookup[pol, "MinTraces", 6]; esc = Lookup[pol, "EscalateFailRatio", 0.4];
  de = Lookup[pol, "DeescalateFailRatio", 0.1]; deMin = Lookup[pol, "DeescalateMinTraces", 12];
  groups = GroupBy[traces, Lookup[#, "Profile", "unknown"] &];
  KeyValueMap[
    Function[{profile, ts},
      Module[{n = Length[ts], fails, ratio, cur, base, advised, change, reason, spec},
        fails = Count[ts, a_Association /; Lookup[a, "Kind", ""] === "fail"];
        ratio = If[n > 0, N[fails / n], 0.];
        cur = iTWCurrentLevel[profile];
        base = iTWBaseLevel[profile];
        spec = iTWProfileSpec[profile];
        {advised, change, reason} = Which[
          n >= minN && ratio >= esc && cur["Level"] =!= "Full",
            {iTWLevelStep[cur["Level"], 1], "Escalate",
             "fail ratio " <> ToString[Round[ratio, 0.01]] <> " over " <> ToString[n] <> " traces"},
          n >= deMin && ratio <= de && iTWLevelIndex[cur["Level"]] > iTWLevelIndex[base],
            {iTWLevelStep[cur["Level"], -1], "Deescalate",
             "fail ratio " <> ToString[Round[ratio, 0.01]] <> " over " <> ToString[n] <> " traces; above baseline " <> base},
          True,
            {cur["Level"], "Keep",
             If[n < minN, "only " <> ToString[n] <> " traces (< " <> ToString[minN] <> ")",
               "fail ratio " <> ToString[Round[ratio, 0.01]] <> " within band"]}];
        <|"Profile" -> profile, "Provider" -> spec[[1]], "Model" -> spec[[2]],
          "Traces" -> n, "Fails" -> fails, "FailRatio" -> ratio,
          "Current" -> cur["Level"], "CurrentSource" -> cur["Source"], "Base" -> base,
          "Advised" -> advised, "Change" -> change, "Reason" -> reason|>]],
    groups]];

Options[ClaudeTurnWikiApplyDirectiveLevels] = {"DryRun" -> False};
ClaudeTurnWikiApplyDirectiveLevels[adviceIn_ : Automatic, opts : OptionsPattern[]] := Module[
  {advice, changes, levels, dry = TrueQ[OptionValue["DryRun"]]},
  advice = If[adviceIn === Automatic, ClaudeTurnWikiDirectiveLevelAdvice[], adviceIn];
  changes = Select[Select[advice, AssociationQ], Lookup[#, "Change", "Keep"] =!= "Keep" &];
  If[changes === {}, Return[<|"Status" -> "NoChange", "Applied" -> {}|>]];
  If[dry, Return[<|"Status" -> "DryRun", "Applied" -> changes|>]];
  ClaudeTurnWikiInitialize[];
  levels = ClaudeTurnWikiDirectiveLevels[];
  Scan[
    Function[c,
      levels[c["Profile"]] = <|"Level" -> c["Advised"], "Previous" -> c["Current"],
        "At" -> iTWNowISO[], "Reason" -> c["Reason"], "Change" -> c["Change"]|>;
      If[iTWCallableQ["ClaudeDirectives`ClaudeSetDirectiveLevelOverride"],
        Quiet @ Check[ToExpression["ClaudeDirectives`ClaudeSetDirectiveLevelOverride"][
          iTWProfileSpec[c["Profile"]], c["Advised"]], Null]];
      ClaudeTurnWikiAppendSkillImpact[<|
        "Outcome" -> "LevelChanged", "Action" -> ToLowerCase[c["Change"]],
        "Name" -> c["Profile"], "Profile" -> c["Profile"],
        "Score" -> Lookup[c, "FailRatio", Missing[]], "RBest" -> iTWProfileRBest[c["Profile"]],
        "Rationale" -> "DirectiveLevel " <> c["Current"] <> " -> " <> c["Advised"] <> ": " <> c["Reason"]|>]],
    changes];
  iTWWriteFile[iTWLevelsPath[], iTWToJSON[levels]];
  iTWInstallLevelResolver[];
  <|"Status" -> "OK", "Applied" -> changes, "Levels" -> levels|>];

(* resolver hook for kernels that load ClaudeDirectives without going through
   ApplyDirectiveLevels (service / fresh notebook): reads the shared file *)
iTWInstallLevelResolver[] := Module[{f},
  If[!iTWDirectivesLevelAPIQ[], Return[<|"Status" -> "DirectivesNotLoaded"|>]];
  f = Function[spec,
    Module[{key = ClaudeTurnWikiProfileKey[
        If[ListQ[spec] && Length[spec] >= 1, spec[[1]], None],
        If[ListQ[spec] && Length[spec] >= 2, spec[[2]], None]], e},
      e = Lookup[ClaudeTurnWikiDirectiveLevels[], key, None];
      If[AssociationQ[e], Lookup[e, "Level", None], None]]];
  $iTWLevelResolverFn = f;
  (* string assignment: the target symbol may already hold a Function, so a
     With-burned Symbol[...] would evaluate to that value instead *)
  Quiet @ Check[
    ToExpression["ClaudeDirectives`$ClaudeDirectiveLevelResolver = " <>
      "ClaudeOrchestrator`TurnWiki`Private`$iTWLevelResolverFn"],
    Null];
  <|"Status" -> "OK"|>];

(* watermark: 消費済み TraceId (上限つき) と最終 tick 時刻。時刻は AbsoluteTime の
   数値で持つ (文字列時刻の大小比較は禁物)。 *)
$iTWMaxSeenTraceIds = 2000;
iTWWatermarkPath[] := iTWPath["maintain-watermark.json"];

iTWLoadWatermark[] := Module[{s = iTWReadFile[iTWWatermarkPath[]], a},
  a = If[StringQ[s], iTWFromJSON[s], $Failed];
  If[AssociationQ[a], a,
    <|"LastTickAbs" -> Null, "LastTickAtUTC" -> Null, "SeenTraceIds" -> {}, "TickCount" -> 0|>]];

iTWSaveWatermark[a_Association] := iTWWriteFile[iTWWatermarkPath[], iTWToJSON[a]];

(* 排他ロック: 対話カーネルと service カーネルの同時 tick を防ぐ。stale なら奪う。
   書いた後に読み戻して所有者を確認する (同時書き込みの取りこぼし対策)。 *)
iTWLockPath[] := iTWPath["locks", "maintain-tick.lock"];
iTWLockOwner[] := $MachineName <> ":" <> ToString[$ProcessID];

iTWAcquireLock[staleSeconds_] := Module[
  {p = iTWLockPath[], cur, a, now = AbsoluteTime[], owner = iTWLockOwner[], verify},
  cur = iTWReadFile[p];
  If[StringQ[cur],
    a = iTWFromJSON[cur];
    If[AssociationQ[a] && NumberQ[Lookup[a, "AcquiredAbs", Null]] &&
       now - a["AcquiredAbs"] < staleSeconds && Lookup[a, "Owner", ""] =!= owner,
      Return[<|"Acquired" -> False, "Holder" -> Lookup[a, "Owner", "?"],
        "AgeSeconds" -> Round[now - a["AcquiredAbs"]]|>]]];
  iTWWriteFile[p, iTWToJSON[<|"Owner" -> owner, "AcquiredAbs" -> now,
    "AcquiredAtUTC" -> iTWNowISO[]|>]];
  verify = With[{c = iTWReadFile[p]}, If[StringQ[c], iTWFromJSON[c], $Failed]];
  If[AssociationQ[verify] && Lookup[verify, "Owner", ""] === owner,
    <|"Acquired" -> True, "Owner" -> owner|>,
    <|"Acquired" -> False,
      "Holder" -> Lookup[If[AssociationQ[verify], verify, <||>], "Owner", "?"]|>]];

iTWReleaseLock[] := Module[{p = iTWLockPath[], a, c},
  c = iTWReadFile[p];
  a = If[StringQ[c], iTWFromJSON[c], $Failed];
  If[AssociationQ[a] && Lookup[a, "Owner", ""] === iTWLockOwner[],
    Quiet @ Check[DeleteFile[p], Null]]];

(* LLM 可用性の軽量 ping (Automatic かつ ClaudeBackendAvailableQ 不在のとき)。 *)
iTWLLMPingQ[llmFn_] := Module[{r},
  If[MissingQ[llmFn], Return[False]];
  r = Quiet @ Check[
    llmFn["Reply with the single word OK.", "You are a health check. Reply with OK."], $Failed];
  StringQ[r]];

Options[ClaudeTurnWikiMaintainTick] = {
  "Force" -> False, "LLMFn" -> Automatic, "TracesFn" -> Automatic,
  "AvailabilityFn" -> Automatic, "MinIntervalSeconds" -> Automatic,
  "MaxFail" -> 5, "MaxPass" -> 3, "LockStaleSeconds" -> 1800};

(* Collect + Maintain のみ (提案・ゲート・手順書変更は行わない = 観測モードの自動化)。
   Iteration カウンタは進めない。raw は TraceId 単位 write-once なので重複しない。 *)
ClaudeTurnWikiMaintainTick[opts : OptionsPattern[]] := Module[
  {settings, wm, now = AbsoluteTime[], interval, lock, llmFn, avail, traces, m,
   seen, newSeen, iter, res, force = TrueQ[OptionValue["Force"]],
   ids, setKey, status, streak},
  ClaudeTurnWikiInitialize[];
  settings = ClaudeTurnWikiSettings[];
  If[!force && !TrueQ[settings["AutoMaintain"]],
    Return[<|"Status" -> "Disabled"|>]];
  interval = OptionValue["MinIntervalSeconds"];
  If[interval === Automatic, interval = Lookup[settings, "MaintainIntervalSeconds", 21600]];
  wm = iTWLoadWatermark[];
  If[!force && NumberQ[Lookup[wm, "LastTickAbs", Null]] && now - wm["LastTickAbs"] < interval,
    Return[<|"Status" -> "IntervalNotElapsed",
      "NextInSeconds" -> Round[interval - (now - wm["LastTickAbs"])]|>]];
  lock = iTWAcquireLock[OptionValue["LockStaleSeconds"]];
  If[!TrueQ[lock["Acquired"]], Return[Append[lock, "Status" -> "Locked"]]];
  res = Catch[
    (* LLM 不可用で終わる場合も最終 tick 時刻を記録する (service の判定周期ごとに
       再試行せず、設定の MaintainIntervalSeconds に従わせる。実測: 旧版は 10 分おきに
       LLMUnavailable を繰り返した)。 *)
    Module[{markUnavailable},
      markUnavailable := (
        wm["LastTickAbs"] = now; wm["LastTickAtUTC"] = iTWNowISO[];
        wm["TickCount"] = Lookup[wm, "TickCount", 0] + 1;
        wm["LastResult"] = "LLMUnavailable"; iTWSaveWatermark[wm]);
      llmFn = iTWResolveLLMFn[OptionValue["LLMFn"]];
      If[MissingQ[llmFn], markUnavailable; Throw[<|"Status" -> "LLMUnavailable"|>]];
    avail = OptionValue["AvailabilityFn"];
    avail = Which[
      avail =!= Automatic, TrueQ[Quiet @ Check[avail[], False]],
      OptionValue["LLMFn"] =!= Automatic, True,
      (* ClaudeBackendAvailableQ は <|"Available"->True|False, "Reason"->..|> を返す
         (真偽値ではない。実測: service で llmlog が claudecode を遅延ロードした後、
         TrueQ[assoc]=False で常に LLMUnavailable になった 2026-09-02)。 *)
      iTWCallableQ["ClaudeCode`ClaudeBackendAvailableQ"],
        With[{r = Quiet @ Check[
            ToExpression["ClaudeCode`ClaudeBackendAvailableQ"][{"lmstudio", Automatic}], False]},
          TrueQ[r] || (AssociationQ[r] && TrueQ[Lookup[r, "Available", False]])],
      (* service カーネル (claudecode 不在) では mining の安価な /v1/models 照会で判定。
         戻りは <|"URL","Model"|> (実測) または model 文字列。不達は Missing/$Failed。 *)
      iTWCallableQ["SourceVault`Private`iSVMResolveLocalLLM"],
        With[{r = Quiet @ Check[ToExpression["SourceVault`Private`iSVMResolveLocalLLM"][], $Failed]},
          StringQ[r] || (AssociationQ[r] && StringQ[Lookup[r, "Model", Missing[]]])],
      True, iTWLLMPingQ[llmFn]];
    If[!avail, markUnavailable; Throw[<|"Status" -> "LLMUnavailable"|>]]];
    seen = Lookup[wm, "SeenTraceIds", {}];
    If[!ListQ[seen], seen = {}];
    traces = ClaudeTurnWikiCollectTraces["TracesFn" -> OptionValue["TracesFn"],
      "MaxFail" -> OptionValue["MaxFail"], "MaxPass" -> OptionValue["MaxPass"],
      "ExcludeTraceIds" -> seen];
    wm["LastTickAbs"] = now; wm["LastTickAtUTC"] = iTWNowISO[];
    wm["TickCount"] = Lookup[wm, "TickCount", 0] + 1;
    If[traces === {},
      wm["LastResult"] = "NoNewTraces"; iTWSaveWatermark[wm];
      Throw[<|"Status" -> "NoNewTraces"|>]];
    iter = Lookup[iTWLoadState[], "Iteration", 0];
    m = ClaudeTurnWikiMaintain[traces, "LLMFn" -> llmFn, "Iteration" -> iter];
    (* 消費済みマークは Maintainer が成功したときだけ (失敗分は次回再挑戦)。
       ただし最終 tick 時刻は毎回更新して LLM を連打しない。
       2026-09-08: 同一トレース集合で連続 $ClaudeTurnWikiMaxFailStreak 回失敗したら
       毒トレースとみなして消費済みにし (Status "GaveUp")、ループの永久停滞を防ぐ
       (実測: 日本語 JSON の parse 失敗で同じ 2 件を 6h ごとに 3 回以上再試行していた)。 *)
    newSeen = seen;
    ids = ToString[Lookup[#, "TraceId", ""]] & /@ traces;
    setKey = Hash[Sort[ids], "SHA256", "HexString"];
    status = m["Status"];
    If[status === "OK",
      newSeen = DeleteDuplicates[Join[seen, ids]];
      wm["FailStreak"] = 0; wm["FailSetKey"] = "",
      streak = If[Lookup[wm, "FailSetKey", ""] === setKey, Lookup[wm, "FailStreak", 0] + 1, 1];
      wm["FailStreak"] = streak; wm["FailSetKey"] = setKey;
      If[streak >= $ClaudeTurnWikiMaxFailStreak,
        newSeen = DeleteDuplicates[Join[seen, ids]];
        wm["FailStreak"] = 0; wm["FailSetKey"] = "";
        status = "GaveUp"]];
    If[Length[newSeen] > $iTWMaxSeenTraceIds, newSeen = Take[newSeen, -$iTWMaxSeenTraceIds]];
    wm["SeenTraceIds"] = newSeen;
    wm["LastResult"] = status;
    iTWSaveWatermark[wm];
    <|"Status" -> status, "Traces" -> Length[traces],
      "Maintain" -> KeyDrop[m, {"RawResponse"}], "Consumed" -> Length[newSeen],
      "FailStreak" -> Lookup[wm, "FailStreak", 0],
      (* 2026-09-08: adaptive DirectiveLevel (pure arithmetic over the raw
         store, no LLM) when the persisted AutoLevel flag is on *)
      "Levels" -> If[TrueQ[Lookup[settings, "AutoLevel", False]],
        Quiet @ Check[ClaudeTurnWikiApplyDirectiveLevels[], <|"Status" -> "Error"|>],
        <|"Status" -> "Disabled"|>]|>];
  iTWReleaseLock[];
  res];

ClaudeTurnWikiMaintainTickStatus[] := Module[{wm = iTWLoadWatermark[], c, lock},
  c = iTWReadFile[iTWLockPath[]];
  lock = If[StringQ[c], iTWFromJSON[c], None];
  <|"AutoMaintain" -> ClaudeTurnWikiAutoMaintainQ[],
    "IntervalSeconds" -> Lookup[ClaudeTurnWikiSettings[], "MaintainIntervalSeconds", 21600],
    "LastTickAtUTC" -> Lookup[wm, "LastTickAtUTC", None],
    "TickCount" -> Lookup[wm, "TickCount", 0],
    "ConsumedTraces" -> Length[Lookup[wm, "SeenTraceIds", {}]],
    "LastResult" -> Lookup[wm, "LastResult", None],
    "Lock" -> If[AssociationQ[lock], KeyTake[lock, {"Owner", "AcquiredAtUTC"}], None]|>];

(* ::Subsection:: *)
(* 注入 (I4: 手順書のみ。always-on rule として具現化) *)

(* ::Subsection:: *)
(* Raw store repair (2026-09-08) *)

Options[ClaudeTurnWikiRepairRawEncoding] = {"DryRun" -> False};
ClaudeTurnWikiRepairRawEncoding[opts : OptionsPattern[]] := Module[
  {files, scanned = 0, repaired = {}, dry = TrueQ[OptionValue["DryRun"]]},
  files = Quiet @ Check[FileNames["*.json", iTWPath["raw"], Infinity], {}];
  Scan[
    Function[f,
      Module[{c = iTWReadFile[f], a, fixed, changed = False},
        scanned++;
        a = If[StringQ[c], iTWFromJSON[c], $Failed];
        If[AssociationQ[a],
          fixed = a;
          Scan[
            Function[k,
              If[StringQ[Lookup[a, k, None]],
                With[{r = iTWMojibakeRepair[a[k]]},
                  If[r =!= a[k], fixed[k] = r; changed = True]]]],
            {"Task", "Text"}];
          If[changed,
            AppendTo[repaired, f];
            If[!dry, iTWWriteFile[f, iTWToJSON[fixed]]]]]]],
    files];
  <|"Scanned" -> scanned, "Repaired" -> Length[repaired], "DryRun" -> dry, "Files" -> repaired|>];

(* ::Subsection:: *)
(* Ledger / log / trace readers (core) and their Views (2026-09-08)

   core  -> List[Association] (chainable, uncapped)
   View  -> Pane[Dataset[..]] capped by $ClaudeTurnWikiViewMaxRows, frameless
            row buttons (SourceVault core/View convention, rule 108) *)

If[!IntegerQ[$ClaudeTurnWikiViewMaxRows] || $ClaudeTurnWikiViewMaxRows < 1,
  $ClaudeTurnWikiViewMaxRows = 25];

iTWReadJSONL[path_String] := Module[{c = iTWReadFile[path]},
  If[!StringQ[c], Return[{}]];
  Select[
    Map[Function[l, With[{s = StringTrim[l]}, If[s === "", Null, iTWFromJSON[s]]]],
      StringSplit[c, "\n"]],
    AssociationQ]];

iTWNormLedgerEntry[e_Association] := <|
  "At" -> ToString[Lookup[e, "At", ""]],
  "Iteration" -> Lookup[e, "Iteration", Missing[]],
  "Profile" -> With[{p = Lookup[e, "Profile", Null]}, If[StringQ[p] && p =!= "", p, $iTWDefaultProfile]],
  "Outcome" -> ToString[Lookup[e, "Outcome", "?"]],
  "Action" -> ToString[Lookup[e, "Action", "?"]],
  "Name" -> ToString[Lookup[e, "Name", "-"]],
  "Score" -> With[{s = Lookup[e, "Score", Null]}, If[NumberQ[s], s, Missing[]]],
  "RBest" -> With[{s = Lookup[e, "RBest", Null]}, If[NumberQ[s], s, Missing[]]],
  "Rationale" -> ToString[Lookup[e, "Rationale", ""]],
  "Content" -> Lookup[e, "Content", Missing[]],
  "Edits" -> Lookup[e, "Edits", Missing[]]|>;

Options[ClaudeTurnWikiLedger] = {"Profile" -> All, "Outcome" -> All, "Limit" -> All};
ClaudeTurnWikiLedger[opts : OptionsPattern[]] := Module[
  {rows, prof = OptionValue["Profile"], out = OptionValue["Outcome"], lim = OptionValue["Limit"]},
  rows = iTWNormLedgerEntry /@ iTWReadJSONL[iTWPath["wiki", "skill-impact.jsonl"]];
  rows = Reverse[rows];
  If[prof =!= All, rows = Select[rows, #["Profile"] === iTWNormProfile[prof] &]];
  If[out =!= All, rows = Select[rows, #["Outcome"] === ToString[out] &]];
  If[IntegerQ[lim] && lim >= 0, rows = Take[rows, UpTo[lim]]];
  rows];

Options[ClaudeTurnWikiLog] = {"Limit" -> All};
ClaudeTurnWikiLog[opts : OptionsPattern[]] := Module[{c, blocks, rows, lim = OptionValue["Limit"]},
  c = iTWReadFile[iTWPath["wiki", "logs.md"]];
  If[!StringQ[c], Return[{}]];
  (* entries are "## <iso> iteration <k>\n<body>" blocks (writer:
     ClaudeTurnWikiApplyMaintainerOutput); the first split piece is the seed *)
  blocks = Rest[StringSplit["\n" <> StringReplace[c, "\r\n" -> "\n"], "\n## "]];
  rows = DeleteMissing @ Map[
    Function[b,
      Module[{lines = StringSplit[b, "\n", 2], hdr, body, m},
        hdr = First[lines, ""]; body = If[Length[lines] > 1, lines[[2]], ""];
        m = StringCases[hdr,
          StartOfString ~~ at : (Except[" "] ..) ~~ " iteration " ~~ it : (DigitCharacter ..) :> {at, it}, 1];
        If[m === {}, Missing[],
          <|"At" -> m[[1, 1]], "Iteration" -> ToExpression[m[[1, 2]]], "Text" -> StringTrim[body]|>]]],
    blocks];
  rows = Reverse[rows];
  If[IntegerQ[lim] && lim >= 0, rows = Take[rows, UpTo[lim]]];
  rows];

Options[ClaudeTurnWikiTraces] = {"Iteration" -> All, "Profile" -> All, "Kind" -> All};
ClaudeTurnWikiTraces[opts : OptionsPattern[]] := Module[
  {files, rows, it = OptionValue["Iteration"], prof = OptionValue["Profile"], kind = OptionValue["Kind"]},
  files = Quiet @ Check[FileNames["*.json", iTWPath["raw"], Infinity], {}];
  rows = DeleteMissing @ Map[
    Function[f,
      Module[{c = iTWReadFile[f], a, iterDir},
        a = If[StringQ[c], iTWFromJSON[c], $Failed];
        If[!AssociationQ[a], Missing[],
          iterDir = FileNameTake[DirectoryName[f]];
          a = iTWEnsureTraceProfile[a];
          <|"TraceId" -> ToString[Lookup[a, "TraceId", FileBaseName[f]]],
            "Iteration" -> With[{m = StringCases[iterDir, "iter-" ~~ d : (DigitCharacter ..) :> ToExpression[d]]},
              If[m === {}, Missing[], First[m]]],
            "Kind" -> ToString[Lookup[a, "Kind", "?"]],
            "Provider" -> With[{p = Lookup[a, "Provider", Missing[]]}, If[StringQ[p], p, Missing[]]],
            "Model" -> With[{p = Lookup[a, "Model", Missing[]]}, If[StringQ[p], p, Missing[]]],
            "Profile" -> Lookup[a, "Profile", "unknown"],
            "Source" -> ToString[Lookup[a, "Source", "?"]],
            "Task" -> iTWTruncate[ToString[Lookup[a, "Task", ""]], 120],
            "Chars" -> StringLength[ToString[Lookup[a, "Text", ""]]],
            "File" -> f|>]]],
    files];
  If[it =!= All, rows = Select[rows, #["Iteration"] === it &]];
  If[prof =!= All, rows = Select[rows, #["Profile"] === iTWNormProfile[prof] &]];
  If[kind =!= All, rows = Select[rows, #["Kind"] === ToString[kind] &]];
  rows];

ClaudeTurnWikiProfiles[] := Module[{traces, ledger, keys, byTrace, byLedger},
  traces = ClaudeTurnWikiTraces[];
  ledger = ClaudeTurnWikiLedger[];
  keys = DeleteDuplicates @ Join[{$iTWDefaultProfile}, iTWKnownProfiles[],
    DeleteCases[Lookup[#, "Profile", "unknown"] & /@ traces, "unknown"],
    Lookup[#, "Profile", $iTWDefaultProfile] & /@ ledger];
  byTrace = GroupBy[traces, Lookup[#, "Profile", "unknown"] &];
  byLedger = GroupBy[ledger, #["Profile"] &];
  Map[
    Function[k,
      Module[{ps = iTWProfileState[k], ts, n, fails, lvl, spec = iTWProfileSpec[k], led},
        ts = If[k === $iTWDefaultProfile, traces, Lookup[byTrace, k, {}]];
        n = Length[ts]; fails = Count[ts, a_ /; Lookup[a, "Kind", ""] === "fail"];
        lvl = If[k === $iTWDefaultProfile, <|"Level" -> Missing["AllModels"], "Source" -> "-"|>, iTWCurrentLevel[k]];
        led = Lookup[byLedger, k, {}];
        <|"Profile" -> k, "Provider" -> spec[[1]], "Model" -> spec[[2]],
          "RBest" -> With[{r = Lookup[ps, "RBest", Null]}, If[NumberQ[r], r, Missing["NoBaseline"]]],
          "ActiveSkills" -> Lookup[ps, "ActiveSkills", {}],
          "Traces" -> n, "Fails" -> fails,
          "FailRatio" -> If[n > 0, N[fails / n], Missing[]],
          "DirectiveLevel" -> lvl["Level"], "LevelSource" -> lvl["Source"],
          "LastLedgerAt" -> If[led === {}, Missing[], First[led]["At"]],
          "LedgerEntries" -> Length[led],
          "Iteration" -> Lookup[ps, "Iteration", 0]|>]],
    keys]];

(* ---- views ---- *)
iTWViewCap[] := $ClaudeTurnWikiViewMaxRows;
iTWOpenButton[label_String, path_String] :=
  With[{p = path},
    Button[label, If[FileExistsQ[p], SystemOpen[p]],
      Appearance -> "Frameless", Method -> "Queued",
      BaseStyle -> {RGBColor[0.1, 0.3, 0.7]}]];
iTWFmt[x_?NumberQ] := Round[x, 0.001];
iTWFmt[x_] := x;
iTWDataset[rows_List, total_Integer] :=
  If[rows === {},
    Style["(no entries)", GrayLevel[0.5], Italic],
    Pane[
      Column[{
        Dataset[rows, MaxItems -> {iTWViewCap[], All}, Alignment -> {Left, Center}],
        If[total > Length[rows],
          Style[Row[{"... ", total - Length[rows], " more (core function returns all)"}], GrayLevel[0.5], 10],
          Nothing]}],
      ImageSize -> Full]];

Options[ClaudeTurnWikiLedgerView] = Options[ClaudeTurnWikiLedger];
ClaudeTurnWikiLedgerView[opts : OptionsPattern[]] := Module[{rows, shown},
  rows = ClaudeTurnWikiLedger[opts];
  shown = Take[rows, UpTo[iTWViewCap[]]];
  iTWDataset[
    Map[Function[r, <|
      "At" -> r["At"], "Iter" -> r["Iteration"], "Profile" -> r["Profile"],
      "Outcome" -> r["Outcome"], "Action" -> r["Action"], "Name" -> r["Name"],
      "Score" -> iTWFmt[r["Score"]], "RBest" -> iTWFmt[r["RBest"]],
      "Rationale" -> iTWTruncate[r["Rationale"], 160],
      "Open" -> If[r["Name"] =!= "-" && FileExistsQ[iTWPath["skills", r["Name"], "SKILL.md"]],
        iTWOpenButton["SKILL", iTWPath["skills", r["Name"], "SKILL.md"]], ""]|>],
      shown],
    Length[rows]]];

Options[ClaudeTurnWikiLogView] = Options[ClaudeTurnWikiLog];
ClaudeTurnWikiLogView[opts : OptionsPattern[]] := Module[{rows, shown},
  rows = ClaudeTurnWikiLog[opts];
  shown = Take[rows, UpTo[iTWViewCap[]]];
  iTWDataset[
    Map[Function[r, <|"At" -> r["At"], "Iter" -> r["Iteration"],
      "Finding" -> iTWTruncate[r["Text"], 400]|>], shown],
    Length[rows]]];

Options[ClaudeTurnWikiTracesView] = Options[ClaudeTurnWikiTraces];
ClaudeTurnWikiTracesView[opts : OptionsPattern[]] := Module[{rows, shown, ds},
  rows = ClaudeTurnWikiTraces[opts];
  shown = Take[rows, UpTo[iTWViewCap[]]];
  ds = iTWDataset[
    Map[Function[r, <|"TraceId" -> r["TraceId"], "Iter" -> r["Iteration"], "Kind" -> r["Kind"],
      "Profile" -> r["Profile"], "Source" -> r["Source"], "Task" -> r["Task"], "Chars" -> r["Chars"],
      "Open" -> iTWOpenButton["json", r["File"]]|>], shown],
    Length[rows]];
  (* task snippets may quote notebook content: wrap as a private view when
     SourceVault's confidential-view helper is present *)
  If[iTWCallableQ["SourceVault`SourceVaultPrivateView"],
    Quiet @ Check[ToExpression["SourceVault`SourceVaultPrivateView"][ds, 0.75], ds], ds]];

ClaudeTurnWikiProfilesView[] := Module[{rows},
  rows = ClaudeTurnWikiProfiles[];
  iTWDataset[
    Map[Function[r, <|"Profile" -> r["Profile"], "Level" -> r["DirectiveLevel"],
      "LevelSrc" -> r["LevelSource"], "RBest" -> iTWFmt[r["RBest"]],
      "Skills" -> StringRiffle[r["ActiveSkills"], ", "],
      "Traces" -> r["Traces"], "Fails" -> r["Fails"], "FailRatio" -> iTWFmt[r["FailRatio"]],
      "Ledger" -> r["LedgerEntries"], "Last" -> r["LastLedgerAt"]|>],
      Take[rows, UpTo[iTWViewCap[]]]],
    Length[rows]]];

iTWISODate[s_String] := Quiet @ Check[
  DateObject[StringReplace[s, "Z" ~~ EndOfString -> ""], TimeZone -> 0], $Failed];

ClaudeTurnWikiTimelineView[] := Module[{rows, scored, byProf, series, rbest},
  rows = Reverse[ClaudeTurnWikiLedger[]];  (* oldest first *)
  scored = Select[rows, NumberQ[#["Score"]] && #["Outcome"] =!= "LevelChanged" &];
  If[scored === {},
    Return[Style["(no validated proposal yet: add probes with ClaudeTurnWikiAddProbe and run ClaudeTurnWikiRunIteration)",
      GrayLevel[0.5], Italic]]];
  byProf = GroupBy[scored, #["Profile"] &];
  series = KeyValueMap[
    Function[{p, es},
      Select[Map[{iTWISODate[#["At"]], #["Score"]} &, es], DateObjectQ[First[#]] &]],
    byProf];
  rbest = KeyValueMap[
    Function[{p, es},
      Select[Map[{iTWISODate[#["At"]], If[NumberQ[#["RBest"]], #["RBest"], 0.]} &, es], DateObjectQ[First[#]] &]],
    byProf];
  DateListPlot[Join[series, rbest],
    PlotLegends -> Join[("score " <> # &) /@ Keys[byProf], ("RBest " <> # &) /@ Keys[byProf]],
    PlotStyle -> Join[Table[Automatic, Length[byProf]], Table[Dashed, Length[byProf]]],
    PlotMarkers -> Automatic, Joined -> True, PlotRange -> {Automatic, {0, 1.05}},
    FrameLabel -> {None, "validation score"}, ImageSize -> 560]];

ClaudeTurnWikiDashboard[] := Module[{st = ClaudeTurnWikiStatus[], lv = ClaudeTurnWikiDirectiveLevels[]},
  Column[{
    Style["TurnWiki (WikiSkill turn-improvement loop)", Bold, 14],
    Grid[{
      {"Root", st["Root"]},
      {"Iteration", st["Iteration"]},
      {"Patterns / Probes", Row[{st["Patterns"], " / ", st["Probes"]}]},
      {"AutoMaintain / AutoLevel", Row[{st["AutoMaintain"], " / ", ClaudeTurnWikiAutoLevelQ[]}]},
      {"Injection", Lookup[st["Injection"], "Registered", {}]},
      {"Adaptive levels", If[lv === <||>, "(none)",
        Grid[KeyValueMap[{#1, Lookup[#2, "Level", "?"], Lookup[#2, "At", ""]} &, lv], Alignment -> Left]]}},
      Alignment -> Left, Spacings -> {2, 0.5}],
    Style["Model profiles", Bold], ClaudeTurnWikiProfilesView[],
    Style["Skill-impact ledger (all proposals, incl. rejected)", Bold], ClaudeTurnWikiLedgerView[],
    Style["Wiki evolution log", Bold], ClaudeTurnWikiLogView[],
    Style["Validation timeline", Bold], ClaudeTurnWikiTimelineView[]},
    Spacings -> 1.2]];

$iTWRulePrefix = "evolved-turn-";

iTWDirectivesReadyQ[] :=
  StringQ[$ClaudeTurnWikiDirectiveRootOverride] ||
  (MemberQ[$Packages, "ClaudeDirectives`"] &&
   iTWCallableQ["ClaudeDirectives`ClaudeResolveDirectiveRoot"]);

iTWRulePath[droot_String, name_String] :=
  FileNameJoin[{droot, "rules", $iTWRulePrefix <> name <> ".md"}];

(* frontmatter の YAML サブセットパーサに優しいよう ":" は "-" に潰す。 *)
iTWSkillDescription[skillMD_String] := Module[{lines, d},
  lines = Select[StringSplit[skillMD, "\n"],
    StringTrim[#] =!= "" && !StringStartsQ[StringTrim[#], "#"] &&
    !StringStartsQ[StringTrim[#], "---"] &];
  d = If[lines === {}, "evolved turn skill", StringTrim[First[lines]]];
  iTWTruncate[StringReplace[d, ":" -> "-"], 160]];

(* frontmatter scope of the evolved rule: the profiles the skill is active in.
   Active in "default" (or nowhere yet = about to be promoted globally) ->
   no models: line (every model); otherwise models: <provider:model> lines so
   ClaudeDirectives injects it only for those models (validated there, I3). *)
iTWMaterializeModelsBlock[name_String] := Module[{profs = iTWSkillProfiles[name]},
  profs = DeleteCases[profs, $iTWDefaultProfile | "unknown"];
  If[MemberQ[iTWSkillProfiles[name], $iTWDefaultProfile] || profs === {}, "",
    "models:\n" <> StringRiffle[("  - " <> # &) /@ profs, "\n"] <> "\n"]];

iTWMaterializeSkill[name_String, skillMD_String] := Module[{droot, ruleName, body, iso},
  If[!iTWDirectivesReadyQ[], Return[<|"Status" -> "DirectivesNotLoaded"|>]];
  iso = ClaudeTurnWikiCheckIsolation[];
  If[!TrueQ[iso["OK"]], Return[<|"Status" -> "IsolationViolation", "Detail" -> iso["Detail"]|>]];
  droot = iTWDirectiveRoot[];
  If[MissingQ[droot], Return[<|"Status" -> "NoDirectiveRoot"|>]];
  ruleName = $iTWRulePrefix <> name;
  (* 具現化は SKILL.md 本文のみ (I4)。frontmatter は最小限。
     2026-09-08: tier: evolved (always delivered in full at every
     DirectiveLevel) + models: scope of the validated profiles. *)
  body = "---\nname: " <> ruleName <>
    "\ndescription: TurnWiki evolved skill - " <> iTWSkillDescription[skillMD] <>
    "\ntier: evolved\n" <> iTWMaterializeModelsBlock[name] <>
    "---\n\n" <> skillMD <> "\n";
  If[iTWWriteFile[iTWRulePath[droot, name], body] === $Failed,
    Return[<|"Status" -> "WriteFailed"|>]];
  iTWRegisterAlwaysOn[ruleName];
  Quiet @ Check[ToExpression["ClaudeDirectives`ClaudeInvalidateDirectiveCache"][], Null];
  <|"Status" -> "OK", "Rule" -> ruleName|>];

iTWRegisterAlwaysOn[ruleName_String] :=
  Quiet @ Check[
    Module[{cur = ToExpression["ClaudeDirectives`$ClaudeAlwaysOnRules"]},
      If[ListQ[cur] && !MemberQ[cur, ruleName],
        ToExpression["ClaudeDirectives`$ClaudeAlwaysOnRules = " <>
          ToString[Append[cur, ruleName], InputForm]]]],
    Null];

iTWUnregisterAlwaysOn[ruleName_String] :=
  Quiet @ Check[
    Module[{cur = ToExpression["ClaudeDirectives`$ClaudeAlwaysOnRules"]},
      If[ListQ[cur] && MemberQ[cur, ruleName],
        ToExpression["ClaudeDirectives`$ClaudeAlwaysOnRules = " <>
          ToString[DeleteCases[cur, ruleName], InputForm]]]],
    Null];

iTWUnmaterializeSkill[name_String] := Module[{droot, p},
  If[!iTWDirectivesReadyQ[], Return[<|"Status" -> "DirectivesNotLoaded"|>]];
  droot = iTWDirectiveRoot[];
  If[MissingQ[droot], Return[<|"Status" -> "NoDirectiveRoot"|>]];
  p = iTWRulePath[droot, name];
  If[FileExistsQ[p], Quiet @ Check[DeleteFile[p], Null]];
  iTWUnregisterAlwaysOn[$iTWRulePrefix <> name];
  Quiet @ Check[ToExpression["ClaudeDirectives`ClaudeInvalidateDirectiveCache"][], Null];
  <|"Status" -> "OK"|>];

ClaudeTurnWikiWireInjection[] := Module[{st, names, done = {}, skipped = {}},
  If[!TrueQ[$ClaudeTurnWikiInjectionEnabled],
    Return[<|"Status" -> "Disabled"|>]];
  If[!iTWDirectivesReadyQ[],
    Return[<|"Status" -> "DirectivesNotLoaded"|>]];
  st = iTWLoadState[];
  (* 直近採用分を優先して上限まで具現化 (肥大防止)。2026-09-08: every profile's
     active skills (the models: frontmatter keeps them scoped). *)
  names = Take[Reverse[iTWAllActiveSkillNames[]],
    UpTo[$ClaudeTurnWikiMaxActiveSkills]];
  Scan[
    Function[n,
      Module[{c = iTWReadFile[iTWPath["skills", n, "SKILL.md"]]},
        If[StringQ[c],
          If[Lookup[iTWMaterializeSkill[n, c], "Status", "?"] === "OK",
            AppendTo[done, n], AppendTo[skipped, n]],
          AppendTo[skipped, n]]]],
    names];
  <|"Status" -> "OK", "Wired" -> done, "Skipped" -> skipped|>];

ClaudeTurnWikiUnwireInjection[] := Module[{droot, files, names = {}},
  If[!iTWDirectivesReadyQ[], Return[<|"Status" -> "DirectivesNotLoaded"|>]];
  droot = iTWDirectiveRoot[];
  If[MissingQ[droot], Return[<|"Status" -> "NoDirectiveRoot"|>]];
  files = Quiet @ Check[
    FileNames[$iTWRulePrefix <> "*.md", FileNameJoin[{droot, "rules"}]], {}];
  Scan[
    Function[f,
      Module[{base = StringReplace[FileNameTake[f], ".md" ~~ EndOfString -> ""]},
        AppendTo[names, base];
        Quiet @ Check[DeleteFile[f], Null];
        iTWUnregisterAlwaysOn[base]]],
    files];
  Quiet @ Check[ToExpression["ClaudeDirectives`ClaudeInvalidateDirectiveCache"][], Null];
  <|"Status" -> "OK", "Removed" -> names|>];

ClaudeTurnWikiInjectionStatus[] := Module[{droot, files, reg},
  If[!iTWDirectivesReadyQ[],
    Return[<|"Status" -> "DirectivesNotLoaded", "Materialized" -> {}, "Registered" -> {}|>]];
  droot = iTWDirectiveRoot[];
  If[MissingQ[droot],
    Return[<|"Status" -> "NoDirectiveRoot", "Materialized" -> {}, "Registered" -> {}|>]];
  files = Quiet @ Check[
    FileNames[$iTWRulePrefix <> "*.md", FileNameJoin[{droot, "rules"}]], {}];
  reg = Quiet @ Check[
    Select[ToExpression["ClaudeDirectives`$ClaudeAlwaysOnRules"],
      StringStartsQ[#, $iTWRulePrefix] &], {}];
  <|"Status" -> "OK",
    "Materialized" -> (StringReplace[FileNameTake[#], ".md" ~~ EndOfString -> ""] & /@ files),
    "Registered" -> reg|>];

End[];  (* `Private` *)

EndPackage[];

(* ロード時: 既採用スキルの注入を復元 (新規作成はしない。冪等)。 *)
If[TrueQ[ClaudeOrchestrator`TurnWiki`$ClaudeTurnWikiAutoWire],
  Quiet @ Check[ClaudeOrchestrator`TurnWiki`ClaudeTurnWikiWireInjection[], Null]];
(* 2026-09-08: adaptive DirectiveLevel resolver (reads directive-levels.json)
   for ClaudeDirectives when it is loaded; idempotent, no-op otherwise. *)
Quiet @ Check[ClaudeOrchestrator`TurnWiki`Private`iTWInstallLevelResolver[], Null];

Print[Style["ClaudeOrchestrator`TurnWiki` (WikiSkill turn-improvement loop) \:30ed\:30fc\:30c9\:5b8c\:4e86 v" <>
  ClaudeOrchestrator`TurnWiki`$TurnWikiVersion, Bold]];
Print["
  ClaudeTurnWikiRunIteration[]  \:2192 1\:53cd\:5fa9 (collect\:2192maintain\:2192propose\:2192gate)
  ClaudeTurnWikiRun[k]          \:2192 k\:53cd\:5fa9 (RBest\:22651.0 \:3067\:65e9\:671f\:7d42\:4e86)
  ClaudeTurnWikiStatus[]        \:2192 \:73fe\:5728\:306e wiki/skill/probe/\:6ce8\:5165\:72b6\:614b
  ClaudeTurnWikiAddProbe[task, expected] \:2192 \:691c\:8a3c\:30d7\:30ed\:30fc\:30d6\:767b\:9332
  ClaudeTurnWikiWireInjection[] / Unwire \:2192 \:624b\:9806\:66f8\:306e\:6ce8\:5165 (always-on rule)
  ClaudeTurnWikiRollbackSkill[name]      \:2192 \:624b\:9806\:66f8\:306e\:307f\:30ed\:30fc\:30eb\:30d0\:30c3\:30af
  ClaudeTurnWikiSetAutoMaintain[True|False] \:2192 \:5b9a\:671f\:7dad\:6301 tick (Collect+Maintain) \:306e ON/OFF (settings.json)
  ClaudeTurnWikiMaintainTick[]           \:2192 \:7dad\:6301 tick \:3092 1 \:56de (service heartbeat \:304c\:547c\:3076)
"];
