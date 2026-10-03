(* ::Package:: *)

(* ::Title:: *)
(* ClaudeOrchestrator_turnwiki.wl *)


(* ::Subsection:: *)
(* \:6982\:8981 *)


(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   ClaudeOrchestrator_turnwiki.wl

   ClaudeOrchestrator`TurnWiki` \:540d\:524d\:7a7a\:9593\:3002
   WikiSkill \:578b (arXiv:2608.27454) \:306e LLM turn \:81ea\:5df1\:6539\:5584\:30eb\:30fc\:30d7\:3002
   \:4ed5\:69d8: \:30c9\:30ad\:30e5\:30e1\:30f3\:30c8/claude_turnwiki_wikiskill_spec_v0_1.md

   3 \:5c64 (root = $ClaudeTurnWikiRoot, \:65e2\:5b9a <MyPackages>/Claude TurnWiki/):
     raw/      \:4e0d\:5909\:5b9f\:884c\:30c8\:30ec\:30fc\:30b9 (write-once)
     wiki/     \:30d1\:30bf\:30fc\:30f3\:96c6 + \:9032\:5316\:30ed\:30b0 + skill-impact \:53f0\:5e33 (append/compound\:3001
               \:6c7a\:3057\:3066\:30ed\:30fc\:30eb\:30d0\:30c3\:30af\:3057\:306a\:3044)
     skills/   \:6607\:683c\:6e08\:307f\:624b\:9806\:66f8 (\:691c\:8a3c\:30b2\:30fc\:30c8\:901a\:904e\:6642\:306e\:307f\:66f4\:65b0\:3001archive/ \:3067\:7248\:7ba1\:7406)

   4 \:30b3\:30f3\:30dd\:30fc\:30cd\:30f3\:30c8:
     Inference Agent  = \:65e2\:5b58 ClaudeEval/ClaudeRunTurn (\:7121\:6539\:5909\:3002\:624b\:9806\:66f8\:306e\:307f\:6ce8\:5165)
     Wiki Maintainer  = ClaudeTurnWikiMaintain   (LLM 1 \:547c\:3073\:51fa\:3057 + \:7d14\:95a2\:6570\:9069\:7528)
     Skill Proposer   = ClaudeTurnWikiPropose    (ReAct \:578b\:30af\:30e9\:30a4\:30a2\:30f3\:30c8\:5074\:30c4\:30fc\:30eb\:30eb\:30fc\:30d7)
     Gating&Rollback  = ClaudeTurnWikiValidate/GateDecision/Promote/Reject/
                        RollbackSkill (probe \:30b9\:30b3\:30a2 > RBest \:306e\:307f\:6607\:683c\:3001fail-closed)

   \:8a2d\:8a08\:4e0d\:5909\:6761\:4ef6 (I1-I4):
     I1 wiki \:306f append/compound \:306e\:307f (\:30ea\:30bb\:30c3\:30c8\:30fb\:30ed\:30fc\:30eb\:30d0\:30c3\:30af\:7981\:6b62)
     I2 \:5168\:63d0\:6848 (\:5374\:4e0b\:542b\:3080) \:3092 skill-impact \:306b diff+\:30b9\:30b3\:30a2+\:5224\:5b9a\:3064\:304d\:3067\:53f0\:5e33\:8ffd\:8a18
     I3 \:624b\:9806\:66f8\:306f\:691c\:8a3c\:30b2\:30fc\:30c8\:901a\:904e\:6642\:306e\:307f\:66f4\:65b0\:3002\:60aa\:5316\:6642\:306f\:624b\:9806\:66f8\:306e\:307f\:623b\:3059\:3002
        probe 0 \:4ef6\:3067\:306f\:6607\:683c\:3057\:306a\:3044
     I4 \:5b9f\:884c\:5f79\:306b\:306f\:624b\:9806\:66f8\:3060\:3051\:3002wiki \:306f directive root \:306e\:5916 (\:8d77\:52d5\:6642\:691c\:67fb)\:3002
        \:5177\:73fe\:5316\:3055\:308c\:308b\:306e\:306f skills/<name>/SKILL.md \:672c\:6587\:306e\:307f

   \:5883\:754c (runtime-orchestrator-boundary): \:9032\:5316\:30eb\:30fc\:30d7\:306f turn \:3092\:8de8\:3050\:6c38\:7d9a state \:3092
   \:6301\:3064\:305f\:3081 Orchestrator \:5074\:3002turn \:5185\:306e\:6ce8\:5165\:306f\:65e2\:5b58 ClaudeDirectives \:6a5f\:69cb
   (always-on rule \:3068\:3057\:3066\:5177\:73fe\:5316) \:3092\:4f7f\:3044\:3001ClaudeRuntime/claudecode \:306f\:7121\:6539\:5909\:3002

   \:5f31\:7d50\:5408\:4f9d\:5b58 (\:30ed\:30fc\:30c9\:6e08\:307f\:306e\:3068\:304d\:306e\:307f\:4f7f\:7528\:3001\:7121\:3051\:308c\:3070\:7e2e\:9000):
     ClaudeOrchestrator`Workflow` : \:53cd\:5fa9\:306e Petri net \:5b9f\:884c (UseOrchestrator)
     ClaudeDirectives`            : \:624b\:9806\:66f8\:306e\:6ce8\:5165\:5177\:73fe\:5316 (WireInjection)
     SourceVault`                 : \:65e2\:5b9a LLM (SourceVaultQueryLocalLLM) \:3068
                                    llmlog \:30c8\:30ec\:30fc\:30b9\:539f\:8cc7
     ClaudeRuntime`               : \:751f\:304d\:3066\:3044\:308b runtime \:306e EventTrace \:539f\:8cc7

   \:30d0\:30fc\:30b8\:30e7\:30f3: v0.1 (2026-09-01) \:521d\:7248
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

BeginPackage["ClaudeOrchestrator`TurnWiki`"];



(* ::Subsection:: *)
(* \:516c\:958b API usage *)


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

(* \:30ed\:30fc\:30c9\:6642\:306e\:30d5\:30a1\:30a4\:30eb\:4f4d\:7f6e\:3092\:6355\:6349 (root \:65e2\:5b9a\:5024\:306e\:57fa\:6e96)\:3002 *)
$iTWPackageDir = Quiet @ Check[DirectoryName[$InputFileName], ""];
If[!StringQ[$iTWPackageDir] || $iTWPackageDir === "", $iTWPackageDir = Directory[]];

If[!ValueQ[$ClaudeTurnWikiRoot], $ClaudeTurnWikiRoot = Automatic];
If[!ValueQ[$ClaudeTurnWikiLLMFn], $ClaudeTurnWikiLLMFn = Automatic];
(* \:5b9f\:6e2c (2026-09-02, strixhalo128 / qwen3.8-27b): Maintainer \:306e JSON \:51fa\:529b\:306f\:751f\:6210 ~12 tok/s \:3067
   1500 \:30c8\:30fc\:30af\:30f3\:8d85 \[RightArrow] 180s \:3067\:306f client \:5207\:65ad (LLMFailed) \:306b\:306a\:3063\:305f\:3002480s = 5000 \:30c8\:30fc\:30af\:30f3\:76f8\:5f53\:3002 *)
If[!ValueQ[$ClaudeTurnWikiLLMTimeout], $ClaudeTurnWikiLLMTimeout = 480];
If[!ValueQ[$ClaudeTurnWikiMaxActiveSkills], $ClaudeTurnWikiMaxActiveSkills = 3];
If[!ValueQ[$ClaudeTurnWikiAutoWire], $ClaudeTurnWikiAutoWire = True];
If[!ValueQ[$ClaudeTurnWikiInjectionEnabled], $ClaudeTurnWikiInjectionEnabled = True];
If[!ValueQ[$ClaudeTurnWikiDirectiveRootOverride], $ClaudeTurnWikiDirectiveRootOverride = Automatic];
If[!IntegerQ[$ClaudeTurnWikiMaxFailStreak], $ClaudeTurnWikiMaxFailStreak = 3];
(* \:81ea\:52d5\:539f\:8cc7 (runtime/llmlog) \:306e\:30c8\:30ec\:30fc\:30b9\:6700\:5c0f\:6587\:5b57\:6570\:3002\:3053\:308c\:672a\:6e80\:306f\:6750\:6599\:306b\:306a\:3089\:306a\:3044 (\:5b9f\:6e2c:
   "(no user message)" \:306e 40 \:5b57\:30bb\:30c3\:30b7\:30e7\:30f3\:304c Maintainer \:306b\:6e21\:3063\:3066\:3044\:305f)\:3002TracesFn \:6ce8\:5165\:306b\:306f\:9069\:7528\:3057\:306a\:3044\:3002 *)
If[!ValueQ[$ClaudeTurnWikiMinTraceChars], $ClaudeTurnWikiMinTraceChars = 200];
If[!ValueQ[$ClaudeTurnWikiFailureMarkers],
  $ClaudeTurnWikiFailureMarkers = {
    "SyntaxError", "RepairRequest", "ValidationRepair", "\\$Failed",
    "FatalFailure", "ExecutionFailed", "TransportRetryExhausted",
    "CallContractViolation", "ToolLoopBudgetExhausted"}];



(* ::Subsection:: *)
(* \:57fa\:672c\:30e6\:30fc\:30c6\:30a3\:30ea\:30c6\:30a3: \:30d1\:30b9 / IO / JSON *)


iTWRoot[] := Module[{r = $ClaudeTurnWikiRoot},
  If[!StringQ[r], r = FileNameJoin[{$iTWPackageDir, "Claude TurnWiki"}]];
  r];

iTWPath[parts___] := FileNameJoin[{iTWRoot[], parts}];

iTWEnsureDir[dir_String] :=
  If[!DirectoryQ[dir],
    Quiet @ Check[CreateDirectory[dir, CreateIntermediateDirectories -> True], $Failed],
    dir];

(* UTF-8 \:56fa\:5b9a\:306e read/write\:3002wolframscript / FE \:3069\:3061\:3089\:3067\:3082\:540c\:4e00\:6319\:52d5\:306b\:3059\:308b\:3002 *)
iTWReadFile[path_String] := Module[{ba},
  If[!FileExistsQ[path], Return[Missing["NotFound", path]]];
  ba = Quiet @ Check[ReadByteArray[path], $Failed];
  Which[
    ba === EndOfFile, "",
    ByteArrayQ[ba], Quiet @ Check[ByteArrayToString[ba], Missing["DecodeFailed", path]],
    True, Missing["ReadFailed", path]]];

(* tmp+rename \:306e\:539f\:5b50\:7684\:66f8\:304d\:8fbc\:307f (Windows \:306f Rename \:5148\:5728\:3067\:5931\:6557\:3059\:308b\:305f\:3081\:9000\:907f\:524a\:9664)\:3002 *)
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

(* JSON: Missing \:3092\:843d\:3068\:3057\:3066\:304b\:3089 Export (RawJSON \:306f Missing \:3092\:6271\:3048\:306a\:3044)\:3002
   2026-09-08 \:5b9f\:6e2c: ImportString[s, "RawJSON"] \:306f\:975e ASCII (\:65e5\:672c\:8a9e) \:3092\:542b\:3080\:6587\:5b57\:5217\:3067
   \:5931\:6557\:3057\:3001LM Studio \:306e\:6b63\:3057\:3044 JSON \:5fdc\:7b54 (append_log \:306b\:300c\:3067\:3042\:308b\:8abf\:300d) \:304c ParseFailed \:306b
   \:306a\:3063\:3066\:3044\:305f\:3002mining \:3068\:540c\:3058 Developer`ReadRawJSONString \:3092\:7b2c\:4e00\:5019\:88dc\:306b\:3057\:3001
   UTF-8 \:30d0\:30a4\:30c8\:7d4c\:7531 \[RightArrow] ImportString \:306e\:9806\:3067\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3059\:308b\:3002 *)
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

(* LLM \:5fdc\:7b54\:304b\:3089\:306e\:7de9\:3044 JSON \:62bd\:51fa: <think> \:30d6\:30ed\:30c3\:30af\:3068 code fence \:3092\:5265\:304c\:3057\:3001
   \:6700\:521d\:306e balanced {...} \:3092\:53d6\:308a\:51fa\:3059\:3002 *)
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

(* \:5f31\:7d50\:5408: \:30d5\:30eb\:30cd\:30fc\:30e0\:306e\:95a2\:6570/\:5909\:6570\:304c\:5b9f\:5728\:3059\:308b\:304b\:3092 DownValues/OwnValues \:3067\:5224\:5b9a
   (\:534a\:767b\:9332\:30b7\:30f3\:30dc\:30eb\:5bfe\:7b56 = ClaudeOrchestrator iHookCallableQ \:3068\:540c\:767a\:60f3)\:3002 *)
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
(* \:30b9\:30c8\:30a2\:521d\:671f\:5316 / \:72b6\:614b / \:9694\:96e2\:691c\:67fb *)


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

(* RBest \:306f JSON \:3067 Null \:5316\:3055\:308c\:308b\:306e\:3067\:6570\:5024\:4ee5\:5916\:306f Missing \:6271\:3044\:3078\:6b63\:898f\:5316\:3002 *)
iTWRBest[] := Module[{r = Lookup[iTWLoadState[], "RBest", Null]},
  If[NumberQ[r], r, Missing["NoBaseline"]]];



(* ::Subsection:: *)
(**)


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

(* I4: wiki \:304c directive root \:914d\:4e0b\:306b\:7f6e\:304b\:308c\:308b\:3068\:6ce8\:5165\:7d4c\:8def\:306b\:4e57\:3063\:3066\:3057\:307e\:3046\:305f\:3081\:7981\:6b62\:3002 *)
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
(* LLM \:89e3\:6c7a *)


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
(* Raw Layer: \:30c8\:30ec\:30fc\:30b9\:5206\:985e / \:63cf\:753b / \:63a1\:53d6 *)


$iTWFailEventTypes = {
  "FatalFailure", "ExecutionFailed", "TransportRetryExhausted",
  "ToolLoopBudgetExhausted", "CallContractViolation", "TextOnlyRepair",
  "FormatRetry", "ValidationRepairAttempt", "ProviderFatalError",
  "BudgetExhausted", "ProviderFailed"};

(* \:300c\:4fee\:5fa9\:30eb\:30fc\:30d7\:304c\:8981\:3089\:306a\:3044 turn\:300d\:3092 pass \:3068\:307f\:306a\:3059: \:4fee\:5fa9\:7cfb\:30a4\:30d9\:30f3\:30c8\:304c 1 \:3064\:3067\:3082
   \:3042\:308c\:3070\:5b66\:7fd2\:5bfe\:8c61 (fail)\:3002 *)
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

(* \:751f\:304d\:3066\:3044\:308b runtime \:304b\:3089\:306e\:63a1\:53d6 (\:5f31\:7d50\:5408\:3002\:516c\:958b enumeration \:304c\:7121\:3044\:305f\:3081
   Private \:30ec\:30b8\:30b9\:30c8\:30ea\:3092 defensive \:306b\:8aad\:3080)\:3002 *)
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

(* \:30cf\:30fc\:30cd\:30b9\:751f\:6210\:30d7\:30ed\:30f3\:30d7\:30c8 (ClaudeEval \:5358\:767a) \:306e user \:767a\:8a71\:306f CLAUDE.md \:6295\:5f71\:3084\:6ce8\:5165 docs \:306e
   \:5b9a\:578b\:6587\:304c\:6570\:5343\:5b57\:7d9a\:304f\:3002llmlog \:3068\:540c\:3058\:898f\:5247\:3067\:5b9f\:30bf\:30b9\:30af\:672c\:6587\:3060\:3051\:3092\:6b8b\:3059 (llmlog \:306e\:62bd\:51fa\:95a2\:6570\:304c
   \:3042\:308c\:3070\:305d\:308c\:3092\:4f7f\:3044\:3001\:7121\:3051\:308c\:3070\:540c\:7b49\:306e\:6700\:5c0f\:5b9f\:88c5)\:3002\:5bfe\:8a71\:30bb\:30c3\:30b7\:30e7\:30f3\:306e\:767a\:8a71\:306f\:7d20\:901a\:3057\:3002 *)
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

(* llmlog \:306e\:5168\:6587 transcript ({<|Role,At,Text,Tools|>..}) \:3092 LLM \:5411\:3051\:30c6\:30ad\:30b9\:30c8\:306b\:63cf\:753b\:3002
   \:5931\:6557\:306e\:8a3c\:62e0\:306f\:672b\:5c3e\:306b\:51fa\:308b\:306e\:3067 tail-keep (\:5148\:982d\:306e user \:4f9d\:983c\:3060\:3051\:306f Task \:3068\:3057\:3066\:5225\:9014\:4fdd\:6301)\:3002 *)
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

(* SourceVault llmlog \:304b\:3089\:306e\:63a1\:53d6 (\:5f31\:7d50\:5408)\:3002SessionKind=harness \:304c ClaudeEval \:5358\:767a turn \:306b
   \:76f8\:5f53\:3002\:5168\:6587 transcript \:304c\:53d6\:308c\:308c\:3070\:305d\:308c\:3092 (2026-09-02: digest \:7531\:6765\:306e\:8981\:7d04\:306f \:6570\:5341\:301c\:6570\:767e\:5b57\:3067
   Maintainer \:306e\:6750\:6599\:306b\:306a\:3089\:306a\:304b\:3063\:305f)\:3001\:7121\:3051\:308c\:3070 digest \:30d5\:30a3\:30fc\:30eb\:30c9\:3092\:4f7f\:3046\:3002
   \:5206\:985e\:306f failure marker \:6b63\:898f\:8868\:73fe (cap \:524d\:306e\:5168\:6587\:306b\:5bfe\:3057\:3066)\:3002 *)
(* SessionTranscript \:306e\:623b\:308a\:306f <|SessionId, Source, Path, Turns|> (\:5b9f\:6e2c) \:307e\:305f\:306f turn \:306e List\:3002 *)
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
  (* ClaudeEval \:5358\:767a (SessionKind=harness) \:3092\:512a\:5148\:3057\:3001\:8db3\:308a\:306a\:3051\:308c\:3070 interactive \:3067\:88dc\:3046\:3002 *)
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
          (* transcript \:306f 1 \:4ef6 1-5s \:304b\:304b\:308b\:306e\:3067\:76f4\:8fd1 transcriptLimit \:4ef6\:3060\:3051\:5168\:6587\:3092\:5f15\:304f *)
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
          (* \:6570\:5341\:5b57\:306e\:7a7a\:30bb\:30c3\:30b7\:30e7\:30f3 ("(no user message)" \:7b49) \:306f\:6750\:6599\:306b\:306a\:3089\:306a\:3044\:306e\:3067\:6368\:3066\:308b *)
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
  (* \:5b9a\:671f tick \:306e watermark: \:6d88\:8cbb\:6e08\:307f TraceId \:306f\:518d\:30b5\:30f3\:30d7\:30eb\:3057\:306a\:3044\:3002 *)
  If[ListQ[exclude] && exclude =!= {},
    all = Select[all, !MemberQ[exclude, ToString[Lookup[#, "TraceId", ""]]] &]];
  (* \:5c64\:5316: \:8ad6\:6587 App.C = fail<=5 + pass<=3\:3002\:539f\:8cc7\:306f\:65b0\:3057\:3044\:9806 (llmlog \:306f
     LastAtUTC \:964d\:9806) \:306a\:306e\:3067\:5148\:982d\:304b\:3089\:63a1\:308b\:3002 *)
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
          (* Raw Layer \:306f\:4e0d\:5909: \:65e2\:5b58\:30d5\:30a1\:30a4\:30eb\:306f\:4e0a\:66f8\:304d\:3057\:306a\:3044 (write-once)\:3002 *)
          If[!FileExistsQ[p], iTWWriteFile[p, iTWToJSON[t]]]]],
      sample]];
  sample];



(* ::Subsection:: *)
(* patch ops \:30a8\:30f3\:30b8\:30f3 (\:7d14\:95a2\:6570) *)


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
  (* create_patterns: \:65e2\:5b58\:304c\:3042\:308c\:3070\:4e0a\:66f8\:304d\:305b\:305a\:8ffd\:8a18 (I1 append/compound)\:3002 *)
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
  (* update_patterns: patch ops\:3002 *)
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
(* Skill Layer: \:8aad\:307f\:51fa\:3057 / staging / \:6607\:683c / \:5374\:4e0b / \:30ed\:30fc\:30eb\:30d0\:30c3\:30af *)


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
  (* \:540c\:4e00\:79d2\:5185\:306e\:9023\:7d9a\:6607\:683c\:3067 archive \:304c\:6f70\:308c\:306a\:3044\:3088\:3046\:30b5\:30d5\:30a3\:30c3\:30af\:30b9\:3067\:56de\:907f\:3002 *)
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
    (* \:524d\:7248\:304c\:7121\:3044: \:975e\:6d3b\:6027\:5316 (\:624b\:9806\:66f8\:3092\:5916\:3059)\:3002wiki \:306f\:4e0d\:5909\:3002 *)
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
    iTWSaveProfileState[profile, <|"RBest" -> Null|>];  (* \:6b21\:53cd\:5fa9\:3067\:518d\:30d9\:30fc\:30b9\:30e9\:30a4\:30f3 (I3) *)
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
(* Skill Proposer (ReAct \:578b\:30af\:30e9\:30a4\:30a2\:30f3\:30c8\:5074\:30c4\:30fc\:30eb\:30eb\:30fc\:30d7) *)


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

(* \:30b5\:30f3\:30c9\:30dc\:30c3\:30af\:30b9: wiki/ traces/ skills/ \:306e\:307f\:3002traces/<id> \:306f raw/iter-<k>/ \:3078\:89e3\:6c7a\:3002 *)
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
    (* raw \:30c8\:30ec\:30fc\:30b9 JSON \:306f Text \:30d5\:30a3\:30fc\:30eb\:30c9\:3092\:672c\:6587\:3068\:3057\:3066\:8fd4\:3059\:3002 *)
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
        (* \:540c\:4e00 read \:306e\:5802\:3005\:5de1\:308a\:30ac\:30fc\:30c9 (claudecode-eval-loop-guard \:3068\:540c\:767a\:60f3)\:3002 *)
        If[path === lastSig, sameSigCount++, sameSigCount = 0; lastSig = path];
        If[sameSigCount >= 2,
          result = <|"Action" -> "no_action", "Status" -> "LoopGuard", "Path" -> path|>;
          Break[]];
        convo = convo <> "\n\n=== read_file: " <> path <> " ===\n" <>
          iTWSandboxRead[path, maxChars] <>
          "\n\nRespond with your next JSON action.",
      (* finish \:76f8\:5f53\:3092\:76f4\:63a5\:8fd4\:3057\:3066\:304f\:308b\:30e2\:30c7\:30eb\:3078\:306e\:5bdb\:5bb9: proposal \:5f62\:3092\:3057\:3066\:3044\:308c\:3070\:53d7\:3051\:308b\:3002 *)
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

(* \:65e2\:5b9a\:306e probe \:8a55\:4fa1: \:624b\:9806\:66f8\:3092\:6ce8\:5165\:3057\:305f 1 \:767a LLM \:56de\:7b54\:306b Expected \:304c\:542b\:307e\:308c\:308b\:304b\:3002
   Expected \:7121\:3057 probe \:306f pass (WiCER iSVMDefaultProbeEval \:3068\:540c\:898f\:7d04)\:3002 *)
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

(* fail-closed: \:6570\:5024\:30b9\:30b3\:30a2\:540c\:58eb\:306e\:53b3\:5bc6\:306a > \:306e\:307f Accepted (\:8ad6\:6587 Eq.4)\:3002 *)
ClaudeTurnWikiGateDecision[cand_, rBest_] := Which[
  !NumberQ[cand], "Rejected",
  !NumberQ[rBest], "Rejected",
  cand > rBest, "Accepted",
  True, "Rejected"];



(* ::Subsection:: *)
(* skill-impact \:53f0\:5e33 (I2: \:6ca1\:6848\:3082\:6b8b\:3059\:3002\:30cf\:30fc\:30cd\:30b9\:304c\:6a5f\:68b0\:7684\:306b\:8ffd\:8a18) *)


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
(* \:53cd\:5fa9 step \:95a2\:6570 (direct / Orchestrator \:5171\:6709) *)


(* \:8a55\:4fa1\:304c\:5065\:5168 (Status OK) \:306a\:3068\:304d\:3060\:3051\:30d9\:30fc\:30b9\:30e9\:30a4\:30f3\:78ba\:5b9a\:3002\:30a8\:30e9\:30fc\:6df7\:3058\:308a\:306e
   0 \:70b9\:3092 RBest \:306b\:56fa\:5b9a\:3057\:306a\:3044 (fail-closed \:3060\:304c junk baseline \:3082\:4f5c\:3089\:306a\:3044)\:3002 *)
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
(* \:53cd\:5fa9\:30c9\:30e9\:30a4\:30d0 (direct + Orchestrator) *)


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

(* Orchestrator \:7d4c\:8def: \:5206\:5c90\:306f Guard \:7d14\:95a2\:6570\:3001LLM \:306f transition handler \:306e\:307f
   (WiCER iSVMWikiCompileNetWith \:3068\:540c\:578b)\:3002step \:95a2\:6570\:306f direct \:3068\:5171\:6709\:3002 *)
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
  (* \:7d50\:679c\:62bd\:51fa\:306f marking \:7531\:6765\:306e\:307f (closure \:975e\:4f9d\:5b58 = restore \:5f8c\:3082\:62bd\:51fa\:53ef)\:3002 *)
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
    If[NumberQ[rb] && rb >= 1.0, Break[]];  (* \:65e9\:671f\:7d42\:4e86 (Algorithm 1 line 4) *)
    r = ClaudeTurnWikiRunIteration[opts];
    AppendTo[results, r];
    If[MemberQ[{"IsolationViolation", "LLMUnavailable"}, Lookup[r, "Status", ""]], Break[]],
    {k}];
  results];



(* ::Subsection:: *)
(* \:5b9a\:671f\:7dad\:6301 tick (service/heartbeat \:7528): \:8a2d\:5b9a / watermark / \:6392\:4ed6\:30ed\:30c3\:30af *)


(* \:8a2d\:5b9a\:306f root \:76f4\:4e0b\:306e settings.json \:306b\:6c38\:7d9a\:5316 = \:5bfe\:8a71\:30ab\:30fc\:30cd\:30eb\:306e\:8a2d\:5b9a\:6b04\:3067 ON \:306b\:3057\:305f
   \:5024\:3092 headless \:306e service \:30ab\:30fc\:30cd\:30eb\:304c Dropbox \:7d4c\:7531\:3067\:305d\:306e\:307e\:307e\:8aad\:3081\:308b\:3002 *)
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
(**)


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

(* watermark: \:6d88\:8cbb\:6e08\:307f TraceId (\:4e0a\:9650\:3064\:304d) \:3068\:6700\:7d42 tick \:6642\:523b\:3002\:6642\:523b\:306f AbsoluteTime \:306e
   \:6570\:5024\:3067\:6301\:3064 (\:6587\:5b57\:5217\:6642\:523b\:306e\:5927\:5c0f\:6bd4\:8f03\:306f\:7981\:7269)\:3002 *)
$iTWMaxSeenTraceIds = 2000;
iTWWatermarkPath[] := iTWPath["maintain-watermark.json"];

iTWLoadWatermark[] := Module[{s = iTWReadFile[iTWWatermarkPath[]], a},
  a = If[StringQ[s], iTWFromJSON[s], $Failed];
  If[AssociationQ[a], a,
    <|"LastTickAbs" -> Null, "LastTickAtUTC" -> Null, "SeenTraceIds" -> {}, "TickCount" -> 0|>]];

iTWSaveWatermark[a_Association] := iTWWriteFile[iTWWatermarkPath[], iTWToJSON[a]];

(* \:6392\:4ed6\:30ed\:30c3\:30af: \:5bfe\:8a71\:30ab\:30fc\:30cd\:30eb\:3068 service \:30ab\:30fc\:30cd\:30eb\:306e\:540c\:6642 tick \:3092\:9632\:3050\:3002stale \:306a\:3089\:596a\:3046\:3002
   \:66f8\:3044\:305f\:5f8c\:306b\:8aad\:307f\:623b\:3057\:3066\:6240\:6709\:8005\:3092\:78ba\:8a8d\:3059\:308b (\:540c\:6642\:66f8\:304d\:8fbc\:307f\:306e\:53d6\:308a\:3053\:307c\:3057\:5bfe\:7b56)\:3002 *)
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

(* LLM \:53ef\:7528\:6027\:306e\:8efd\:91cf ping (Automatic \:304b\:3064 ClaudeBackendAvailableQ \:4e0d\:5728\:306e\:3068\:304d)\:3002 *)
iTWLLMPingQ[llmFn_] := Module[{r},
  If[MissingQ[llmFn], Return[False]];
  r = Quiet @ Check[
    llmFn["Reply with the single word OK.", "You are a health check. Reply with OK."], $Failed];
  StringQ[r]];

Options[ClaudeTurnWikiMaintainTick] = {
  "Force" -> False, "LLMFn" -> Automatic, "TracesFn" -> Automatic,
  "AvailabilityFn" -> Automatic, "MinIntervalSeconds" -> Automatic,
  "MaxFail" -> 5, "MaxPass" -> 3, "LockStaleSeconds" -> 1800};

(* Collect + Maintain \:306e\:307f (\:63d0\:6848\:30fb\:30b2\:30fc\:30c8\:30fb\:624b\:9806\:66f8\:5909\:66f4\:306f\:884c\:308f\:306a\:3044 = \:89b3\:6e2c\:30e2\:30fc\:30c9\:306e\:81ea\:52d5\:5316)\:3002
   Iteration \:30ab\:30a6\:30f3\:30bf\:306f\:9032\:3081\:306a\:3044\:3002raw \:306f TraceId \:5358\:4f4d write-once \:306a\:306e\:3067\:91cd\:8907\:3057\:306a\:3044\:3002 *)
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
    (* LLM \:4e0d\:53ef\:7528\:3067\:7d42\:308f\:308b\:5834\:5408\:3082\:6700\:7d42 tick \:6642\:523b\:3092\:8a18\:9332\:3059\:308b (service \:306e\:5224\:5b9a\:5468\:671f\:3054\:3068\:306b
       \:518d\:8a66\:884c\:305b\:305a\:3001\:8a2d\:5b9a\:306e MaintainIntervalSeconds \:306b\:5f93\:308f\:305b\:308b\:3002\:5b9f\:6e2c: \:65e7\:7248\:306f 10 \:5206\:304a\:304d\:306b
       LLMUnavailable \:3092\:7e70\:308a\:8fd4\:3057\:305f)\:3002 *)
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
      (* ClaudeBackendAvailableQ \:306f <|"Available"->True|False, "Reason"->..|> \:3092\:8fd4\:3059
         (\:771f\:507d\:5024\:3067\:306f\:306a\:3044\:3002\:5b9f\:6e2c: service \:3067 llmlog \:304c claudecode \:3092\:9045\:5ef6\:30ed\:30fc\:30c9\:3057\:305f\:5f8c\:3001
         TrueQ[assoc]=False \:3067\:5e38\:306b LLMUnavailable \:306b\:306a\:3063\:305f 2026-09-02)\:3002 *)
      iTWCallableQ["ClaudeCode`ClaudeBackendAvailableQ"],
        With[{r = Quiet @ Check[
            ToExpression["ClaudeCode`ClaudeBackendAvailableQ"][{"lmstudio", Automatic}], False]},
          TrueQ[r] || (AssociationQ[r] && TrueQ[Lookup[r, "Available", False]])],
      (* service \:30ab\:30fc\:30cd\:30eb (claudecode \:4e0d\:5728) \:3067\:306f mining \:306e\:5b89\:4fa1\:306a /v1/models \:7167\:4f1a\:3067\:5224\:5b9a\:3002
         \:623b\:308a\:306f <|"URL","Model"|> (\:5b9f\:6e2c) \:307e\:305f\:306f model \:6587\:5b57\:5217\:3002\:4e0d\:9054\:306f Missing/$Failed\:3002 *)
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
    (* \:6d88\:8cbb\:6e08\:307f\:30de\:30fc\:30af\:306f Maintainer \:304c\:6210\:529f\:3057\:305f\:3068\:304d\:3060\:3051 (\:5931\:6557\:5206\:306f\:6b21\:56de\:518d\:6311\:6226)\:3002
       \:305f\:3060\:3057\:6700\:7d42 tick \:6642\:523b\:306f\:6bce\:56de\:66f4\:65b0\:3057\:3066 LLM \:3092\:9023\:6253\:3057\:306a\:3044\:3002
       2026-09-08: \:540c\:4e00\:30c8\:30ec\:30fc\:30b9\:96c6\:5408\:3067\:9023\:7d9a $ClaudeTurnWikiMaxFailStreak \:56de\:5931\:6557\:3057\:305f\:3089
       \:6bd2\:30c8\:30ec\:30fc\:30b9\:3068\:307f\:306a\:3057\:3066\:6d88\:8cbb\:6e08\:307f\:306b\:3057 (Status "GaveUp")\:3001\:30eb\:30fc\:30d7\:306e\:6c38\:4e45\:505c\:6ede\:3092\:9632\:3050
       (\:5b9f\:6e2c: \:65e5\:672c\:8a9e JSON \:306e parse \:5931\:6557\:3067\:540c\:3058 2 \:4ef6\:3092 6h \:3054\:3068\:306b 3 \:56de\:4ee5\:4e0a\:518d\:8a66\:884c\:3057\:3066\:3044\:305f)\:3002 *)
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
(* \:6ce8\:5165 (I4: \:624b\:9806\:66f8\:306e\:307f\:3002always-on rule \:3068\:3057\:3066\:5177\:73fe\:5316) *)


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
(**)


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

(* frontmatter \:306e YAML \:30b5\:30d6\:30bb\:30c3\:30c8\:30d1\:30fc\:30b5\:306b\:512a\:3057\:3044\:3088\:3046 ":" \:306f "-" \:306b\:6f70\:3059\:3002 *)
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
  (* \:5177\:73fe\:5316\:306f SKILL.md \:672c\:6587\:306e\:307f (I4)\:3002frontmatter \:306f\:6700\:5c0f\:9650\:3002
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
  (* \:76f4\:8fd1\:63a1\:7528\:5206\:3092\:512a\:5148\:3057\:3066\:4e0a\:9650\:307e\:3067\:5177\:73fe\:5316 (\:80a5\:5927\:9632\:6b62)\:30022026-09-08: every profile's
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

(* \:30ed\:30fc\:30c9\:6642: \:65e2\:63a1\:7528\:30b9\:30ad\:30eb\:306e\:6ce8\:5165\:3092\:5fa9\:5143 (\:65b0\:898f\:4f5c\:6210\:306f\:3057\:306a\:3044\:3002\:51aa\:7b49)\:3002 *)
If[TrueQ[ClaudeOrchestrator`TurnWiki`$ClaudeTurnWikiAutoWire],
  Quiet @ Check[ClaudeOrchestrator`TurnWiki`ClaudeTurnWikiWireInjection[], Null]];
(* 2026-09-08: adaptive DirectiveLevel resolver (reads directive-levels.json)
   for ClaudeDirectives when it is loaded; idempotent, no-op otherwise. *)
Quiet @ Check[ClaudeOrchestrator`TurnWiki`Private`iTWInstallLevelResolver[], Null];

(*Print[Style["ClaudeOrchestrator`TurnWiki` (WikiSkill turn-improvement loop) \:30ed\:30fc\:30c9\:5b8c\:4e86 v" <>
  ClaudeOrchestrator`TurnWiki`$TurnWikiVersion, Bold]];
Print["
  ClaudeTurnWikiRunIteration[]  \[RightArrow] 1\:53cd\:5fa9 (collect\[RightArrow]maintain\[RightArrow]propose\[RightArrow]gate)
  ClaudeTurnWikiRun[k]          \[RightArrow] k\:53cd\:5fa9 (RBest\[GreaterEqual]1.0 \:3067\:65e9\:671f\:7d42\:4e86)
  ClaudeTurnWikiStatus[]        \[RightArrow] \:73fe\:5728\:306e wiki/skill/probe/\:6ce8\:5165\:72b6\:614b
  ClaudeTurnWikiAddProbe[task, expected] \[RightArrow] \:691c\:8a3c\:30d7\:30ed\:30fc\:30d6\:767b\:9332
  ClaudeTurnWikiWireInjection[] / Unwire \[RightArrow] \:624b\:9806\:66f8\:306e\:6ce8\:5165 (always-on rule)
  ClaudeTurnWikiRollbackSkill[name]      \[RightArrow] \:624b\:9806\:66f8\:306e\:307f\:30ed\:30fc\:30eb\:30d0\:30c3\:30af
  ClaudeTurnWikiSetAutoMaintain[True|False] \[RightArrow] \:5b9a\:671f\:7dad\:6301 tick (Collect+Maintain) \:306e ON/OFF (settings.json)
  ClaudeTurnWikiMaintainTick[]           \[RightArrow] \:7dad\:6301 tick \:3092 1 \:56de (service heartbeat \:304c\:547c\:3076)
"];*)
