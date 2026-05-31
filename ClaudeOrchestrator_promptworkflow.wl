(* ::Package:: *)

(* ============================================================
   ClaudeOrchestrator_promptworkflow.wl

   PromptWorkflow extension for ClaudeOrchestrator: the safe
   parser and validation layer for LLM-proposed WorkflowNet code
   (unified spec section 23.5).

   This file is the redesigned replacement for the parse portion
   of petri_from_prompt.wl. Per spec 23.17 it is a separate file
   from SourceVault_promptrouter.wl: the router never owns a
   workflow parser.

   ----------------------------------------------------------------
   Order 7a -- merged forbidden-pattern registry + static check.

   Spec 23.5.3 requires that the workflow forbidden list and the
   rule 00 AutoEvaluate-prohibited patterns are NOT maintained as
   two separate sources of truth. ClaudeWorkflowForbiddenPatternRegistry
   is that single merged registry; ClaudeWorkflowCheckForbidden is
   the static, evaluation-free pre-parse check (spec 23.5.2 step 3).

   The check is purely textual: it inspects a code STRING with
   word-boundary matching and never evaluates it, so it cannot
   trigger any file / network / process / notebook side effect.

   This file is all-ASCII (rule 30 / trap #11) and does not load
   ClaudeTestKit (spec 23.17).
   ============================================================ *)

BeginPackage["ClaudeOrchestrator`"];

Quiet[ClearAll[
  "ClaudeOrchestrator`$ClaudePromptWorkflowVersion",
  "ClaudeOrchestrator`ClaudePromptWorkflowStatus",
  "ClaudeOrchestrator`ClaudeWorkflowForbiddenPatternRegistry",
  "ClaudeOrchestrator`ClaudeWorkflowCheckForbidden",
  "ClaudeOrchestrator`ClaudeParseWorkflowNetCode",
  "ClaudeOrchestrator`ClaudeWorkflowNetWellFormedQ",
  "ClaudeOrchestrator`ClaudeProposeWorkflowNetFromPrompt",
  "ClaudeOrchestrator`ClaudeCreateWorkflowRouteDraft",
  "ClaudeOrchestrator`ClaudeWorkflowComplexPromptQ",
  "ClaudeOrchestrator`ClaudeWorkflowRouteFromPrompt"
]];

$ClaudePromptWorkflowVersion::usage =
  "$ClaudePromptWorkflowVersion is the version string of the ClaudeOrchestrator PromptWorkflow extension.";

ClaudePromptWorkflowStatus::usage =
  "ClaudePromptWorkflowStatus[] returns an Association describing the PromptWorkflow extension: version, implementation phase, and the size of the forbidden-pattern registry.";

ClaudeWorkflowForbiddenPatternRegistry::usage =
  "ClaudeWorkflowForbiddenPatternRegistry[] returns the single merged registry of patterns forbidden in LLM-proposed workflow code (spec 23.5.3): the rule 00 AutoEvaluate-prohibited heads plus workflow-specific file / network / process / credential / notebook-mutation patterns. Each entry is an Association with Name, Token, and Category.";

ClaudeWorkflowCheckForbidden::usage =
  "ClaudeWorkflowCheckForbidden[code_String] statically scans a workflow code string for forbidden patterns WITHOUT evaluating it. It returns <|Status -> \"Clean\" | \"ForbiddenDetected\", Findings -> {...}|>. Matching is word-boundary based so substrings of longer identifiers do not false-positive.";

ClaudeParseWorkflowNetCode::usage =
  "ClaudeParseWorkflowNetCode[input_String, opts] is the safe parser for LLM-proposed WorkflowNet code (spec 23.5.4). It extracts a fenced code block, runs the static forbidden-pattern check, parses the code with a HoldComplete-wrapped (non-evaluating) parse, and extracts WorkflowNet[spec] from the AST -- without ever calling a builder. It returns a WorkflowParseResult Association with Status Parsed / Rejected / ParseFailed / NoWorkflowNet and, on success, the held WorkflowNet wrapped in HoldComplete.";

ClaudeWorkflowNetWellFormedQ::usage =
  "ClaudeWorkflowNetWellFormedQ[spec_Association] checks a WorkflowNet declarative spec for well-formedness (spec 17.9): Places and Transitions must be lists and each entry an Association with a String Name. Returns <|Status -> \"WellFormed\" | \"Malformed\", Issues -> {...}|>.";

ClaudeProposeWorkflowNetFromPrompt::usage =
  "ClaudeProposeWorkflowNetFromPrompt[prompt_String, opts] turns a natural-language goal into a WorkflowNet proposal (spec 23.4.1): it asks the code provider for WorkflowNet code, runs it through the safe parser, and on failure feeds the static diagnostics back and retries up to MaxProposalAttempts. It only proposes -- it never executes or registers a workflow. The CodeProvider option is Automatic (weak-call ClaudeCode`ClaudeQuery) or a Function supplying code directly. Returns a WorkflowProposal Association with Status Proposed / NeedsRepair / Rejected and an AttemptTrace.";

ClaudeCreateWorkflowRouteDraft::usage =
  "ClaudeCreateWorkflowRouteDraft[prompt_String, proposal_Association, opts] turns a successful Order 8 proposal into a WorkflowRouteDraft (spec 23.8). The workflow code body is saved as a private artifact under the SourceVault PrivateVault; the draft metadata carries only a CodeHash and a CodeStorage reference. The draft is created with Status NeedsApproval and is never auto-promoted or executed (spec 23.9 rule 6). DryRun -> True (default, rule 103) reports the plan without writing.";

ClaudeWorkflowComplexPromptQ::usage =
  "ClaudeWorkflowComplexPromptQ[prompt_String] is the deterministic, evaluation-free complex-prompt detector (spec 23.6, step 5 of the ClaudeEval flow). It runs locally BEFORE any router LLM so a secret prompt is not sent out merely to test workflow-candidacy. It returns <|Decision -> \"WorkflowCandidate\" | \"NotComplex\", Reason -> ..., Signals -> ...|> based on explicit workflow requests, multiple sub-task verbs, or a sub-task verb combined with sequencing control words.";

ClaudeWorkflowRouteFromPrompt::usage =
  "ClaudeWorkflowRouteFromPrompt[prompt_String, opts] orchestrates the ClaudeEval workflow-integration flow (spec 23.7) under the conflict-avoidance rules of spec 23.9: an existing unique route is used as-is; otherwise the local complex-prompt detector runs, and only a WorkflowCandidate proceeds to proposal (Order 8) and WorkflowRouteDraft creation (Order 9). A freshly generated workflow always stops at NeedsApproval -- it is never auto-registered or executed. Returns a WorkflowRouteDecision Association.";

Begin["`Private`"];

$ClaudePromptWorkflowVersion = "0.7.0-order10b (2026-05-24)";

iCPWImplementationPhase[] := "Order10b-ClaudeEvalIntegration";

(* ------------------------------------------------------------
   Merged forbidden-pattern registry (spec 23.5.2 / 23.5.3).

   Categories:
   - AutoEvaluate : rule 00 -- whole-code evaluation / hold escape
   - FileIO       : file read/write/delete
   - Network      : URL / remote fetch
   - Process      : OS process / external language evaluation
   - Credential   : credential and attach surfaces
   - Notebook     : notebook mutation and cell-eval bypass
   - CloudBypass  : LLM calls that skip the cloud-send boundary

   MakeExpression is intentionally NOT forbidden: it is the safe
   parser's own held-parse tool (spec 23.5.4). ToExpression IS
   forbidden because it evaluates.
   ------------------------------------------------------------ *)
ClaudeWorkflowForbiddenPatternRegistry[] := {
  (* rule 00 -- AutoEvaluate *)
  <|"Name" -> "ToExpression",   "Token" -> "ToExpression",
    "Category" -> "AutoEvaluate"|>,
  <|"Name" -> "ReleaseHold",    "Token" -> "ReleaseHold",
    "Category" -> "AutoEvaluate"|>,
  <|"Name" -> "Interpreter",    "Token" -> "Interpreter",
    "Category" -> "AutoEvaluate"|>,
  (* file I/O *)
  <|"Name" -> "Get",            "Token" -> "Get",
    "Category" -> "FileIO"|>,
  <|"Name" -> "Import",         "Token" -> "Import",
    "Category" -> "FileIO"|>,
  <|"Name" -> "Put",            "Token" -> "Put",
    "Category" -> "FileIO"|>,
  <|"Name" -> "Export",         "Token" -> "Export",
    "Category" -> "FileIO"|>,
  <|"Name" -> "DeleteFile",     "Token" -> "DeleteFile",
    "Category" -> "FileIO"|>,
  <|"Name" -> "RenameFile",     "Token" -> "RenameFile",
    "Category" -> "FileIO"|>,
  <|"Name" -> "CopyFile",       "Token" -> "CopyFile",
    "Category" -> "FileIO"|>,
  <|"Name" -> "OpenWrite",      "Token" -> "OpenWrite",
    "Category" -> "FileIO"|>,
  <|"Name" -> "OpenAppend",     "Token" -> "OpenAppend",
    "Category" -> "FileIO"|>,
  <|"Name" -> "BinaryWrite",    "Token" -> "BinaryWrite",
    "Category" -> "FileIO"|>,
  (* network *)
  <|"Name" -> "URLRead",        "Token" -> "URLRead",
    "Category" -> "Network"|>,
  <|"Name" -> "URLExecute",     "Token" -> "URLExecute",
    "Category" -> "Network"|>,
  <|"Name" -> "URLFetch",       "Token" -> "URLFetch",
    "Category" -> "Network"|>,
  <|"Name" -> "URLSubmit",      "Token" -> "URLSubmit",
    "Category" -> "Network"|>,
  <|"Name" -> "HTTPRequest",    "Token" -> "HTTPRequest",
    "Category" -> "Network"|>,
  (* process / external evaluation *)
  <|"Name" -> "RunProcess",     "Token" -> "RunProcess",
    "Category" -> "Process"|>,
  <|"Name" -> "StartProcess",   "Token" -> "StartProcess",
    "Category" -> "Process"|>,
  <|"Name" -> "ExternalEvaluate","Token" -> "ExternalEvaluate",
    "Category" -> "Process"|>,
  <|"Name" -> "Run",            "Token" -> "Run",
    "Category" -> "Process"|>,
  (* credential / attach *)
  <|"Name" -> "SystemCredential","Token" -> "SystemCredential",
    "Category" -> "Credential"|>,
  <|"Name" -> "ClaudeAttach",   "Token" -> "ClaudeAttach",
    "Category" -> "Credential"|>,
  <|"Name" -> "Authentication", "Token" -> "$Authentication",
    "Category" -> "Credential"|>,
  (* notebook mutation / cell-eval bypass *)
  <|"Name" -> "NotebookWrite",  "Token" -> "NotebookWrite",
    "Category" -> "Notebook"|>,
  <|"Name" -> "NotebookPut",    "Token" -> "NotebookPut",
    "Category" -> "Notebook"|>,
  <|"Name" -> "NotebookDelete", "Token" -> "NotebookDelete",
    "Category" -> "Notebook"|>,
  <|"Name" -> "NBEvaluatePreviousCell",
    "Token" -> "NBEvaluatePreviousCell",
    "Category" -> "Notebook"|>,
  <|"Name" -> "FrontEndExecute","Token" -> "FrontEndExecute",
    "Category" -> "Notebook"|>,
  (* cloud-send boundary bypass *)
  <|"Name" -> "LLMSynthesize",  "Token" -> "LLMSynthesize",
    "Category" -> "CloudBypass"|>,
  <|"Name" -> "ServiceExecute", "Token" -> "ServiceExecute",
    "Category" -> "CloudBypass"|>
};

(* ------------------------------------------------------------
   Static forbidden-pattern check (spec 23.5.2 step 3).

   Purely textual: word-boundary regex match against the code
   string. No evaluation, no parsing -- this runs BEFORE any
   held parse, so even a malicious string cannot cause a side
   effect here.
   ------------------------------------------------------------ *)
ClaudeWorkflowCheckForbidden[code_String] :=
  Module[{registry, findings},
    registry = ClaudeWorkflowForbiddenPatternRegistry[];
    findings = Select[registry,
      Function[entry,
        StringContainsQ[code,
          RegularExpression[
            "\\b" <> entry["Token"] <> "\\b"]]]];
    <|
      "Type"     -> "WorkflowForbiddenCheck",
      "Status"   -> If[Length[findings] === 0,
        "Clean", "ForbiddenDetected"],
      "Findings" -> findings,
      "FindingCount" -> Length[findings]
    |>
  ];

ClaudeWorkflowCheckForbidden[___] :=
  <|"Type" -> "WorkflowForbiddenCheck",
    "Status" -> "Failed",
    "Reason" -> "InvalidArguments",
    "Hint" -> "Expected ClaudeWorkflowCheckForbidden[code_String]."|>;

(* ------------------------------------------------------------
   Status
   ------------------------------------------------------------ *)
ClaudePromptWorkflowStatus[] :=
  <|
    "Type"             -> "PromptWorkflowStatus",
    "Version"          -> $ClaudePromptWorkflowVersion,
    "Phase"            -> iCPWImplementationPhase[],
    "ForbiddenPatterns"->
      Length[ClaudeWorkflowForbiddenPatternRegistry[]]
  |>;


(* ============================================================
   Order 7b: safe parser body -- ClaudeParseWorkflowNetCode.

   Implements stages 1, 2, 3 and 4 of the spec 23.5.2 pipeline:

     1. code-block extraction
     2. held syntax parse  (NO evaluation)
     3. static forbidden-pattern check (Order 7a)
     4. WorkflowNet declarative-form extraction from the AST

   The whitelist evaluator (stage 5) and well-formedness
   validation (stage 6) follow in Order 7c.

   Held parse: ToExpression[code, InputForm, HoldComplete] is
   used deliberately. Plain-text Wolfram code is InputForm syntax;
   StandardForm is for 2D box structure and cannot parse <|...|>
   literals from a plain string. This three-argument HoldComplete
   form is NOT the forbidden two-argument ToExpression[code,
   InputForm] (spec 23.5.2): the third argument wraps the parsed
   result in HoldComplete immediately, so nothing in the parsed
   code is ever evaluated. The forbidden static check also runs BEFORE the
   parse, so malicious code is rejected first.

   Builder extraction follows spec 23.5.4: from
   SetDelayed[buildName[], WorkflowNet[spec]] the parser takes the
   right-hand side WorkflowNet[spec] from the AST; it never calls
   buildName[]. The builder name is kept only as provenance.

   All held WorkflowNet values are returned wrapped in
   HoldComplete so the caller cannot accidentally evaluate them.
   This section is all-ASCII.
   ============================================================ *)

(* stage 1: pull the first fenced code block; if none, treat the
   whole input as code *)
iCPWExtractCodeBlock[response_String] :=
  Module[{blocks},
    blocks = StringCases[response,
      "```" ~~ (LetterCharacter ...) ~~ "\n" ~~
      Shortest[body___] ~~ "```" :> body];
    If[Length[blocks] >= 1, First[blocks], response]
  ];
iCPWExtractCodeBlock[_] := "";

(* stage 2: held parse. The HoldComplete wrapper guarantees the
   parsed expression is not evaluated. *)
iCPWHeldParse[code_String] :=
  Quiet @ Check[
    ToExpression[code, InputForm, HoldComplete],
    $Failed];
iCPWHeldParse[_] := $Failed;

(* stage 4a: extract WorkflowNet[spec], held, from the AST.
   Accepts SetDelayed[builder[], WorkflowNet[spec]],
   CompoundExpression ending in such a SetDelayed, or a direct
   WorkflowNet[spec]. The result stays inside HoldComplete. *)
iCPWExtractWorkflowNet[held_HoldComplete] :=
  Module[{step1, headName, argCount},
    step1 = Replace[held, {
      HoldComplete[SetDelayed[_, rhs_]] :> HoldComplete[rhs],
      HoldComplete[CompoundExpression[___,
        SetDelayed[_, rhs_], ___]] :> HoldComplete[rhs],
      other_ :> other
    }];
    (* identify the head by SYMBOL NAME, not by symbol identity:
       the parsed WorkflowNet symbol lives in the caller's
       evaluation context, which differs from this package's
       private context, so a literal WorkflowNet[_] pattern would
       not match. *)
    headName = Replace[step1, {
      HoldComplete[(h_Symbol)[___]] :>
        SymbolName[Unevaluated[h]],
      _ :> ""
    }];
    argCount = Replace[step1, {
      HoldComplete[_[args___]] :> Length[HoldComplete[args]],
      _ :> -1
    }];
    If[headName === "WorkflowNet" && argCount === 1,
      <|"Status" -> "OK", "WorkflowNetHeld" -> step1|>,
      <|"Status" -> "NoWorkflowNet"|>]
  ];
iCPWExtractWorkflowNet[_] := <|"Status" -> "NoWorkflowNet"|>;

(* stage 4b: builder name as provenance only (spec 23.5.4).
   buildName[] is never evaluated; only its symbol name is read. *)
iCPWBuilderName[held_HoldComplete] :=
  Replace[held, {
    HoldComplete[SetDelayed[(b_Symbol)[___], _]] :>
      SymbolName[Unevaluated[b]],
    HoldComplete[CompoundExpression[___,
      SetDelayed[(b_Symbol)[___], _], ___]] :>
      SymbolName[Unevaluated[b]],
    _ :> Missing["DirectForm"]
  }];
iCPWBuilderName[_] := Missing["DirectForm"];

Options[ClaudeParseWorkflowNetCode] = {};

ClaudeParseWorkflowNetCode[input_String,
                           opts:OptionsPattern[]] :=
  Module[{code, fcheck, held, extracted, builder,
          specResult, wf},
    (* stage 1 *)
    code = iCPWExtractCodeBlock[input];
    If[!StringQ[code] || StringTrim[code] === "",
      Return[<|"Type" -> "WorkflowParseResult",
        "Status" -> "Rejected",
        "Reason" -> "NoCodeFound"|>]];

    (* stage 3: static forbidden check BEFORE any parse *)
    fcheck = ClaudeWorkflowCheckForbidden[code];
    If[Lookup[fcheck, "Status", ""] === "ForbiddenDetected",
      Return[<|"Type" -> "WorkflowParseResult",
        "Status"   -> "Rejected",
        "Reason"   -> "ForbiddenPatterns",
        "Findings" -> Lookup[fcheck, "Findings", {}]|>]];

    (* stage 2: held parse (evaluation-free) *)
    held = iCPWHeldParse[code];
    If[held === $Failed || !MatchQ[held, _HoldComplete],
      Return[<|"Type" -> "WorkflowParseResult",
        "Status" -> "ParseFailed",
        "Reason" -> "HeldParseFailed"|>]];

    (* stage 4: extract WorkflowNet[spec] from the AST *)
    extracted = iCPWExtractWorkflowNet[held];
    If[Lookup[extracted, "Status", ""] =!= "OK",
      Return[<|"Type" -> "WorkflowParseResult",
        "Status" -> "NoWorkflowNet",
        "Reason" -> "NoWorkflowNetFormInAST"|>]];

    builder = iCPWBuilderName[held];

    (* stage 5: whitelist evaluator -- build the declarative spec *)
    specResult = iCPWBuildSpec[extracted["WorkflowNetHeld"]];
    If[Lookup[specResult, "Status", ""] =!= "OK",
      Return[<|"Type" -> "WorkflowParseResult",
        "Status"          -> "Rejected",
        "Reason"          -> "NonWhitelistedSymbols",
        "ForbiddenSymbols"->
          Lookup[specResult, "ForbiddenSymbols", {}],
        "Builder"         -> builder|>]];

    (* stage 6: WorkflowNet well-formedness validation *)
    wf = ClaudeWorkflowNetWellFormedQ[specResult["Spec"]];
    If[Lookup[wf, "Status", ""] =!= "WellFormed",
      Return[<|"Type" -> "WorkflowParseResult",
        "Status"  -> "NeedsRepair",
        "Reason"  -> "NotWellFormed",
        "Issues"  -> Lookup[wf, "Issues", {}],
        "Builder" -> builder|>]];

    <|
      "Type"            -> "WorkflowParseResult",
      "Status"          -> "Parsed",
      "WorkflowNetHeld" -> extracted["WorkflowNetHeld"],
      "Spec"            -> specResult["Spec"],
      "Builder"         -> builder,
      "ForbiddenCheck"  -> "Clean",
      "WellFormed"      -> True,
      "ParserStage"     -> "FullPipeline"
    |>
  ];

ClaudeParseWorkflowNetCode[___] :=
  <|"Type" -> "WorkflowParseResult",
    "Status" -> "Failed",
    "Reason" -> "InvalidArguments",
    "Hint" ->
      "Expected ClaudeParseWorkflowNetCode[input_String, opts]."|>;


(* ============================================================
   Order 7c: whitelist evaluator + WorkflowNet well-formedness.

   Stages 5 and 6 of the spec 23.5.2 pipeline.

   Stage 5 -- whitelist evaluator (spec 23.5.4). The held
   WorkflowNet[spec] AST is scanned for every Symbol it contains
   (heads included). Only a fixed whitelist is allowed:
   Association / List / Rule / RuleDelayed structure, the
   WorkflowNet / HoldComplete wrappers, and the value symbols
   Missing / Infinity / Automatic / True / False / Null. Any
   other symbol -- Plus from "1 + 1", StringJoin from
   "x" <> "y", Join, ToString, or an arbitrary function head --
   causes rejection. Integer / Real / String literals are not
   symbols and are therefore allowed.

   Once the whitelist check passes, the held spec provably
   contains only structural and literal nodes, so removing the
   HoldComplete wrapper cannot trigger a side effect. The hold
   is removed with a Replace rule -- NOT ReleaseHold on raw code
   (spec 23.5.2) -- and only AFTER the whitelist has passed.

   Stage 6 -- ClaudeWorkflowNetWellFormedQ checks the resulting
   declarative spec: Places / Transitions are lists, and each
   Place / Transition is an Association carrying a String Name.

   This section is all-ASCII.
   ============================================================ *)

(* symbols permitted anywhere inside a WorkflowNet spec *)
iCPWSpecWhitelistSymbols[] := {
  "Association", "List", "Rule", "RuleDelayed",
  "WorkflowNet", "HoldComplete",
  "Missing", "Infinity", "Automatic",
  "True", "False", "Null"
};

(* stage 5a: collect every symbol name in the held spec and
   reject if any is outside the whitelist. Cases with Heads->True
   walks the held expression without evaluating it. *)
iCPWValidateSpecWhitelist[held_HoldComplete] :=
  Module[{symbols, forbidden},
    symbols = DeleteDuplicates[
      Cases[held,
        s_Symbol :> SymbolName[Unevaluated[s]],
        {0, Infinity}, Heads -> True]];
    forbidden = Complement[symbols, iCPWSpecWhitelistSymbols[]];
    If[forbidden === {},
      <|"Status" -> "OK", "Symbols" -> symbols|>,
      <|"Status" -> "Rejected",
        "ForbiddenSymbols" -> forbidden|>]
  ];
iCPWValidateSpecWhitelist[_] :=
  <|"Status" -> "Rejected",
    "ForbiddenSymbols" -> {"NotHeld"}|>;

(* stage 5b: extract WorkflowNet's single argument as the held
   spec, run the whitelist, then -- only on success -- drop the
   hold to obtain the literal declarative Association. *)
iCPWBuildSpec[heldWF_HoldComplete] :=
  Module[{heldSpec, wl, specValue},
    heldSpec = Replace[heldWF,
      HoldComplete[_[s_]] :> HoldComplete[s]];
    If[!MatchQ[heldSpec, _HoldComplete],
      Return[<|"Status" -> "Failed", "Reason" -> "NoSpec"|>]];
    wl = iCPWValidateSpecWhitelist[heldSpec];
    If[Lookup[wl, "Status", ""] =!= "OK", Return[wl]];
    (* whitelist passed -> the held spec is structural + literal
       only; releasing the hold here is side-effect free. *)
    specValue = Replace[heldSpec, HoldComplete[s_] :> s];
    <|"Status" -> "OK", "Spec" -> specValue|>
  ];
iCPWBuildSpec[_] :=
  <|"Status" -> "Failed", "Reason" -> "NotHeld"|>;

(* stage 6: WorkflowNet well-formedness check
   (AssertWorkflowNetWellFormed counterpart, spec 17.9) *)
ClaudeWorkflowNetWellFormedQ[spec_Association] :=
  Module[{places, transitions, issues},
    issues = {};
    places      = Lookup[spec, "Places", {}];
    transitions = Lookup[spec, "Transitions", {}];

    If[!ListQ[places],
      AppendTo[issues, "PlacesNotList"]];
    If[!ListQ[transitions],
      AppendTo[issues, "TransitionsNotList"]];

    If[ListQ[places] && Length[places] > 0 &&
       !AllTrue[places,
         Function[p,
           AssociationQ[p] &&
           StringQ[Lookup[p, "Name", Null]]]],
      AppendTo[issues, "PlaceMissingName"]];

    If[ListQ[transitions] && Length[transitions] > 0 &&
       !AllTrue[transitions,
         Function[t,
           AssociationQ[t] &&
           StringQ[Lookup[t, "Name", Null]]]],
      AppendTo[issues, "TransitionMissingName"]];

    <|
      "Type"   -> "WorkflowNetValidation",
      "Status" -> If[issues === {}, "WellFormed", "Malformed"],
      "Issues" -> issues
    |>
  ];

ClaudeWorkflowNetWellFormedQ[_] :=
  <|"Type" -> "WorkflowNetValidation",
    "Status" -> "Malformed",
    "Issues" -> {"SpecNotAssociation"}|>;


(* ============================================================
   Order 8: workflow proposal API.

   ClaudeProposeWorkflowNetFromPrompt turns a natural-language
   goal into a WorkflowNet proposal (spec 23.4.1). It absorbs the
   iProposeOnce / iProposeMulti / iBuildFeedback / iIsProposalBad
   roles of the old petri_from_prompt.wl into one feedback-retry
   loop:

     1. build a proposal prompt (with the previous feedback)
     2. obtain candidate code from the code provider
     3. run it through the Order 7 safe parser
     4. if not Parsed, turn the static diagnostics into feedback
        text and retry, up to MaxProposalAttempts

   This is the PROPOSAL-stage retry only. It never executes a
   workflow and never registers anything (spec 23.4.1); workflow
   execution retry / snapshot / restore is a different layer.

   The CodeProvider option is the seam for the model: Automatic
   weak-calls ClaudeCode`ClaudeQuery, and a Function value lets a
   test or a custom proposer supply code deterministically
   without an LLM.

   This section is all-ASCII.
   ============================================================ *)

(* build the instruction prompt sent to the code provider *)
iCPWBuildProposalPrompt[goal_String, feedback_String] :=
  StringJoin[
    "Generate a WorkflowNet declarative specification for the ",
    "following goal.\n\n",
    "Goal: ", goal, "\n\n",
    "Requirements:\n",
    "- Output a single WorkflowNet[<|...|>] expression, or a ",
    "builder of the form buildName[] := WorkflowNet[<|...|>].\n",
    "- Use only HandlerRef strings for transition handlers; do ",
    "not write arbitrary handler code.\n",
    "- Spec values must be literals, strings, lists, or ",
    "associations only -- no arithmetic and no function calls.\n",
    If[StringTrim[feedback] === "", "",
      "\nThe previous attempt had problems:\n" <> feedback <>
      "\nFix these problems and produce a corrected spec.\n"]
  ];
iCPWBuildProposalPrompt[_, _] := "";

(* obtain candidate code: Automatic -> weak LLM call;
   a Function (or other callable) -> call it directly *)
iCPWProposeOnce[proposalPrompt_String, provider_] :=
  If[provider === Automatic,
    If[Names["ClaudeCode`ClaudeQuery"] =!= {},
      Quiet @ Check[
        Symbol["ClaudeCode`ClaudeQuery"][proposalPrompt],
        $Failed],
      $Failed],
    Quiet @ Check[provider[proposalPrompt], $Failed]
  ];
iCPWProposeOnce[_, _] := $Failed;

(* turn an Order 7 parse result into feedback text *)
iCPWBuildFeedback[parseResult_Association] :=
  Module[{status, reason},
    status = Lookup[parseResult, "Status", ""];
    reason = Lookup[parseResult, "Reason", ""];
    Which[
      status === "Rejected" && reason === "ForbiddenPatterns",
        "Forbidden API calls were used: " <>
        StringRiffle[
          Map[Lookup[#, "Name", "?"] &,
            Lookup[parseResult, "Findings", {}]], ", "],
      status === "Rejected" && reason === "NonWhitelistedSymbols",
        "Non-whitelisted symbols appeared in the spec: " <>
        StringRiffle[
          Lookup[parseResult, "ForbiddenSymbols", {}], ", "] <>
        ". Use only literals, strings, lists and associations.",
      status === "NeedsRepair",
        "The WorkflowNet is not well-formed: " <>
        StringRiffle[Lookup[parseResult, "Issues", {}], ", "],
      status === "ParseFailed",
        "The code could not be parsed; check the syntax.",
      status === "NoWorkflowNet",
        "No WorkflowNet[...] expression was found in the code.",
      True,
        "The proposal was not accepted."
    ]
  ];
iCPWBuildFeedback[_] := "The proposal was not accepted.";

(* is an Order 7 parse result a failed proposal? *)
iCPWIsProposalBad[parseResult_] :=
  !(AssociationQ[parseResult] &&
    Lookup[parseResult, "Status", ""] === "Parsed");

Options[ClaudeProposeWorkflowNetFromPrompt] = {
  "MaxProposalAttempts" -> 3,
  "ProviderPolicy"      -> Automatic,
  "FeedbackMode"        -> "StaticDiagnostics",
  "CodeProvider"        -> Automatic
};

ClaudeProposeWorkflowNetFromPrompt[prompt_String,
                                   opts:OptionsPattern[]] :=
  Module[{maxAttempts, provider, attempts, feedback, code,
          parseResult, trace, proposalPrompt, finalStatus},
    maxAttempts = OptionValue[
      ClaudeProposeWorkflowNetFromPrompt, {opts},
      "MaxProposalAttempts"];
    If[!IntegerQ[maxAttempts] || maxAttempts < 1,
      maxAttempts = 3];
    provider = OptionValue[
      ClaudeProposeWorkflowNetFromPrompt, {opts},
      "CodeProvider"];

    trace       = {};
    feedback    = "";
    attempts    = 0;
    code        = "";
    parseResult = <|"Status" -> "NotAttempted"|>;

    (* proposal-stage feedback retry loop *)
    While[
      attempts < maxAttempts &&
      Lookup[parseResult, "Status", ""] =!= "Parsed",

      attempts = attempts + 1;
      proposalPrompt = iCPWBuildProposalPrompt[prompt, feedback];
      code = iCPWProposeOnce[proposalPrompt, provider];

      If[!StringQ[code],
        AppendTo[trace, <|
          "Attempt" -> attempts,
          "Status"  -> "ProviderFailed"|>];
        feedback = "The code generator returned nothing; retry.";
        Continue[]];

      parseResult = ClaudeParseWorkflowNetCode[code];
      AppendTo[trace, <|
        "Attempt" -> attempts,
        "Status"  -> Lookup[parseResult, "Status", "?"]|>];

      If[Lookup[parseResult, "Status", ""] =!= "Parsed",
        feedback = iCPWBuildFeedback[parseResult]];
    ];

    finalStatus = Which[
      Lookup[parseResult, "Status", ""] === "Parsed",
        "Proposed",
      Lookup[parseResult, "Status", ""] === "NeedsRepair",
        "NeedsRepair",
      True,
        "Rejected"
    ];

    <|
      "Type"            -> "WorkflowProposal",
      "Status"          -> finalStatus,
      "Prompt"          ->
        "sha256:" <> Hash[prompt, "SHA256", "HexString"],
      "Attempts"        -> attempts,
      "AttemptTrace"    -> trace,
      "Code"            -> code,
      "BuilderName"     ->
        Lookup[parseResult, "Builder", Missing["None"]],
      "WorkflowNetSpec" ->
        Lookup[parseResult, "Spec", Missing["None"]],
      "Diagnostics"     -> <|
        "FinalParseStatus" ->
          Lookup[parseResult, "Status", "?"],
        "LastFeedback"     -> feedback
      |>,
      "ProposerVersion" -> $ClaudePromptWorkflowVersion
    |>
  ];

ClaudeProposeWorkflowNetFromPrompt[___] :=
  <|"Type" -> "WorkflowProposal",
    "Status" -> "Failed",
    "Reason" -> "InvalidArguments",
    "Hint" ->
      "Expected ClaudeProposeWorkflowNetFromPrompt[prompt_String, opts]."|>;


(* ============================================================
   Order 9: WorkflowRouteDraft storage.

   ClaudeCreateWorkflowRouteDraft turns an Order 8 proposal into
   a WorkflowRouteDraft (spec 23.8). The workflow code body is
   stored as a private artifact; the draft metadata carries only
   a CodeHash and a CodeStorage reference -- never the code
   itself (spec 23.8 / Test W8).

   The draft is created with Status NeedsApproval. It is never
   auto-promoted to the WorkflowRoute registry and never executed
   (spec 23.9 rule 6, spec 23.17). Approval and registration are
   separate, later steps.

   Code artifacts live under the SourceVault PrivateVault:
     <PrivateVault>/promptrouter/artifacts/wf-code/sha256-<h>.wl
     <PrivateVault>/promptrouter/artifacts/wf-code/sha256-<h>.metadata.json
   so this layer weak-reads SourceVault`$SourceVaultRoots. Writes
   follow rule 103: DryRun -> True is the default, and the real
   write is a tmp-then-rename atomic write in UTF-8.

   This section is all-ASCII.
   ============================================================ *)

(* private artifact directory, via the SourceVault PrivateVault *)
iCPWArtifactDir[] :=
  Module[{roots, pv},
    If[Names["SourceVault`$SourceVaultRoots"] === {},
      Return[$Failed]];
    roots = Symbol["SourceVault`$SourceVaultRoots"];
    If[!AssociationQ[roots], Return[$Failed]];
    pv = Lookup[roots, "PrivateVault", $Failed];
    If[!StringQ[pv], Return[$Failed]];
    FileNameJoin[{pv, "promptrouter", "artifacts", "wf-code"}]
  ];

(* atomic-ish write of one string to a path.
   Stage 9 P1.5: encoding \:5f15\:6570\:8ffd\:52a0\:3002\:901a\:5e38\:306e Wolfram \:6587\:5b57\:5217\:306f
   "UTF-8" (\:65e2\:5b9a)\:3001ExportString["RawJSON"] / WriteRawJSONString \:306e\:623b\:308a
   (codepoint = UTF-8 byte \:306e Latin-1 \:8868\:73fe) \:306f "ISO8859-1" \:3092\:6307\:5b9a\:3059\:308b
   (\:305d\:3046\:3057\:306a\:3044\:3068\:4e8c\:91cd encode \:3067\:6587\:5b57\:5316\:3051)\:3002 *)
iCPWAtomicWriteString[path_String, content_String, encoding_String:"UTF-8"] :=
  Module[{strm, renamed},
    strm = Quiet[OpenWrite[path <> ".tmp", BinaryFormat -> True]];
    If[Head[strm] =!= OutputStream,
      Return[<|"Status" -> "Failed", "Reason" -> "OpenFailed"|>]];
    BinaryWrite[strm, StringToByteArray[content, encoding]];
    Close[strm];
    If[FileExistsQ[path], Quiet[DeleteFile[path]]];
    renamed = Quiet @ Check[
      RenameFile[path <> ".tmp", path], $Failed];
    If[renamed === $Failed,
      Quiet[DeleteFile[path <> ".tmp"]];
      Return[<|"Status" -> "Failed", "Reason" -> "RenameFailed"|>]];
    <|"Status" -> "OK", "Path" -> path|>
  ];

(* save the workflow code body + a metadata sidecar *)
iCPWSaveCodeArtifact[code_String] :=
  Module[{dir, hash, wlPath, metaPath, rel, wlWrite, metaJson,
          metaWrite},
    dir = iCPWArtifactDir[];
    If[dir === $Failed,
      Return[<|"Status" -> "Failed",
        "Reason" -> "NoPrivateVault"|>]];
    hash     = Hash[code, "SHA256", "HexString"];
    wlPath   = FileNameJoin[{dir, "sha256-" <> hash <> ".wl"}];
    metaPath = FileNameJoin[{dir,
      "sha256-" <> hash <> ".metadata.json"}];
    rel = "promptrouter/artifacts/wf-code/sha256-" <>
      hash <> ".wl";
    Quiet[CreateDirectory[dir,
      CreateIntermediateDirectories -> True]];

    wlWrite = iCPWAtomicWriteString[wlPath, code];
    If[Lookup[wlWrite, "Status", ""] =!= "OK",
      Return[<|"Status" -> "Failed",
        "Reason" -> Lookup[wlWrite, "Reason", "WriteFailed"]|>]];

    metaJson = Quiet @ Check[
      ExportString[<|
        "CodeHash"  -> "sha256:" <> hash,
        "ByteCount" -> StringLength[code],
        "Kind"      -> "WorkflowCodeArtifact"|>,
        "RawJSON"], "{}"];
    metaWrite = iCPWAtomicWriteString[metaPath, metaJson, "ISO8859-1"];

    <|
      "Status"       -> "OK",
      "CodeHash"     -> "sha256:" <> hash,
      "ArtifactPath" -> wlPath,
      "RelativePath" -> rel,
      "MetadataPath" -> metaPath,
      "MetadataOK"   ->
        (Lookup[metaWrite, "Status", ""] === "OK")
    |>
  ];

(* summary of the parsed net (no code body) *)
iCPWParsedNetSummary[spec_Association] :=
  <|
    "PlaceCount"      -> Length[Lookup[spec, "Places", {}]],
    "TransitionCount" -> Length[Lookup[spec, "Transitions", {}]],
    "HandlerMode"     -> "DeclarativeOnly"
  |>;
iCPWParsedNetSummary[_] :=
  <|"PlaceCount" -> 0, "TransitionCount" -> 0,
    "HandlerMode" -> "Unknown"|>;

Options[ClaudeCreateWorkflowRouteDraft] = {
  "DryRun"             -> True,
  "PrivacyLevel"       -> 0.75,
  "WorkflowTemplateId" -> Automatic
};

ClaudeCreateWorkflowRouteDraft[prompt_String,
                               proposal_Association,
                               opts:OptionsPattern[]] :=
  Module[{dryRun, privLevel, tmplId, code, codeHash, draftId,
          spec, netSummary, artifactResult},
    dryRun = TrueQ[OptionValue[
      ClaudeCreateWorkflowRouteDraft, {opts}, "DryRun"]];
    privLevel = OptionValue[
      ClaudeCreateWorkflowRouteDraft, {opts}, "PrivacyLevel"];
    If[!NumericQ[privLevel], privLevel = 0.75];
    tmplId = OptionValue[
      ClaudeCreateWorkflowRouteDraft, {opts}, "WorkflowTemplateId"];

    (* the proposal must be a successful Order 8 proposal *)
    If[Lookup[proposal, "Status", ""] =!= "Proposed",
      Return[<|"Type" -> "WorkflowRouteDraft",
        "Status" -> "Rejected",
        "Reason" -> "ProposalNotProposed"|>]];

    code = Lookup[proposal, "Code", ""];
    If[!StringQ[code] || StringTrim[code] === "",
      Return[<|"Type" -> "WorkflowRouteDraft",
        "Status" -> "Rejected",
        "Reason" -> "ProposalHasNoCode"|>]];

    codeHash = "sha256:" <> Hash[code, "SHA256", "HexString"];
    draftId  = "wfdraft-" <>
      StringTake[Hash[code, "SHA256", "HexString"], 12];
    spec     = Lookup[proposal, "WorkflowNetSpec", <||>];
    netSummary = iCPWParsedNetSummary[spec];

    (* DryRun (default, rule 103): report the plan, write nothing *)
    If[dryRun,
      Return[<|
        "Type"                -> "WorkflowRouteDraft",
        "Status"              -> "DryRun",
        "DraftId"             -> draftId,
        "CodeHash"            -> codeHash,
        "PlannedStatus"       -> "NeedsApproval",
        "PlannedArtifactKind" -> "PrivateArtifactRef",
        "ParsedNetSummary"    -> netSummary,
        "PrivacyLevel"        -> privLevel|>]];

    (* real: save the code artifact under the PrivateVault *)
    artifactResult = iCPWSaveCodeArtifact[code];
    If[Lookup[artifactResult, "Status", ""] =!= "OK",
      Return[<|"Type" -> "WorkflowRouteDraft",
        "Status" -> "Failed",
        "Reason" ->
          Lookup[artifactResult, "Reason", "ArtifactSaveFailed"]|>]];

    (* draft is NeedsApproval: no auto-promotion (spec 23.9-6) *)
    <|
      "Type"               -> "WorkflowRouteDraft",
      "DraftId"            -> draftId,
      "Status"             -> "NeedsApproval",
      "PromptFingerprint"  ->
        "sha256:" <> Hash[prompt, "SHA256", "HexString"],
      "WorkflowTemplateId" -> tmplId,
      "WorkflowVersion"    -> 1,
      "CodeHash"           -> artifactResult["CodeHash"],
      "CodeStorage"        -> <|
        "Kind"         -> "PrivateArtifactRef",
        "ArtifactPath" -> artifactResult["RelativePath"]
      |>,
      "ParsedNetSummary"   -> netSummary,
      "ProposalTrace"      ->
        Lookup[proposal, "AttemptTrace", {}],
      "PrivacyLevel"       -> privLevel,
      "AllowedModelClasses"-> If[privLevel >= 0.5,
        {"Local", "Private"}, {"Cloud", "Private", "Local"}],
      "RequiresApproval"   -> True
    |>
  ];

ClaudeCreateWorkflowRouteDraft[___] :=
  <|"Type" -> "WorkflowRouteDraft",
    "Status" -> "Failed",
    "Reason" -> "InvalidArguments",
    "Hint" ->
      "Expected ClaudeCreateWorkflowRouteDraft[prompt_String, proposal_Association, opts]."|>;


(* ============================================================
   Order 10a: deterministic complex-prompt detector.

   ClaudeWorkflowComplexPromptQ is step 5 of the ClaudeEval flow
   (spec 23.7). After exact / FunctionRoute / lexical / existing
   WorkflowRoute matching all fail, this LOCAL, evaluation-free
   detector decides whether the prompt is complex enough to
   justify a workflow draft -- BEFORE any router LLM is called,
   so a secret prompt is never sent to an LLM just to test
   workflow-candidacy (spec 23.7).

   A prompt is treated as a workflow candidate (spec 23.6) when
   ANY of:
   - an explicit workflow request appears ("make this a
     workflow", "save as steps", "turn into a Petri net");
   - two or more distinct sub-task verbs appear together
     (extract + summarize + compare ...);
   - a sub-task verb appears together with a sequencing /
     conditionality control word ("first ... then ...",
     "if needed ...").

   A single verb with no control word is NOT complex: it should
   go to a FunctionRoute or a heavy-LLM fallback, not a workflow.

   The detector returns a Decision: WorkflowCandidate, or
   NotComplex. It never itself proposes or builds anything.

   Japanese cue words are \:XXXX literals (rule 30 / trap #11).
   ============================================================ *)

iCPWControlWords[]    := {"\:307e\:305a", "\:6b21\:306b", "\:305d\:308c\:304b\:3089", "\:6700\:5f8c\:306b", "\:5fc5\:8981\:306a\:3089", "first", "then", "next", "finally", "after that"};
iCPWTaskVerbs[]       := {"\:62bd\:51fa", "\:8981\:7d04", "\:6bd4\:8f03", "\:4e26\:3079\:66ff", "\:30bd\:30fc\:30c8", "\:627f\:8a8d", "\:9023\:643a", "extract", "summarize", "compare", "sort", "approve"};
iCPWExplicitRequests[]:= {"\:30ef\:30fc\:30af\:30d5\:30ed\:30fc\:5316", "\:624b\:9806\:3068\:3057\:3066\:4fdd\:5b58", "Petri net\:306b\:3057\:3066", "workflow"};

(* count how many distinct entries of a cue list occur in text *)
iCPWCountCues[text_String, cues_List] :=
  Count[cues,
    c_ /; StringContainsQ[text, c, IgnoreCase -> True]];

ClaudeWorkflowComplexPromptQ[prompt_String] :=
  Module[{explicitHits, verbHits, controlHits, decision, reason},
    explicitHits = iCPWCountCues[prompt, iCPWExplicitRequests[]];
    verbHits     = iCPWCountCues[prompt, iCPWTaskVerbs[]];
    controlHits  = iCPWCountCues[prompt, iCPWControlWords[]];

    Which[
      explicitHits >= 1,
        decision = "WorkflowCandidate";
        reason   = "ExplicitWorkflowRequest",
      verbHits >= 2,
        decision = "WorkflowCandidate";
        reason   = "MultipleSubTaskVerbs",
      verbHits >= 1 && controlHits >= 1,
        decision = "WorkflowCandidate";
        reason   = "SubTaskWithControlFlow",
      True,
        decision = "NotComplex";
        reason   = "SingleStepOrUnclear"
    ];

    <|
      "Type"        -> "ComplexPromptDecision",
      "Decision"    -> decision,
      "Reason"      -> reason,
      "Signals"     -> <|
        "ExplicitRequestHits" -> explicitHits,
        "SubTaskVerbHits"     -> verbHits,
        "ControlWordHits"     -> controlHits
      |>,
      "DetectorVersion" -> $ClaudePromptWorkflowVersion
    |>
  ];

ClaudeWorkflowComplexPromptQ[___] :=
  <|"Type" -> "ComplexPromptDecision",
    "Decision" -> "NotComplex",
    "Reason" -> "InvalidArguments"|>;



(* ============================================================
   Order 10b: ClaudeEval workflow integration.

   ClaudeWorkflowRouteFromPrompt orchestrates steps 1, 4, 5, 7,
   9, 10 and 11 of the ClaudeEval flow (spec 23.7) and enforces
   the conflict-avoidance rules of spec 23.9.

   Decision order:
     1. an existing FunctionRoute / WorkflowRoute that matches
        uniquely is used as-is -- no new workflow is generated
        (spec 23.9 rules 1, 2; spec 23.7);
     2. otherwise the deterministic complex-prompt detector
        (Order 10a) runs locally, BEFORE any LLM;
     3. NotComplex  -> Decision NeedsHeavyLLM (no workflow);
     4. WorkflowCandidate -> propose (Order 8), then create a
        WorkflowRouteDraft (Order 9).

   Per spec 23.7 a freshly generated workflow always stops at
   NeedsApproval, even if the prompt said "create and run it":
   this layer never auto-registers and never executes. The
   auto-run exception of spec 23.7 is intentionally not
   implemented in the initial version.

   Per spec 23.9 rule 5, if the workflow proposal / parser layer
   cannot be reached the result is NeedsOrchestrator rather than
   a guess. The existing-route probe weak-calls
   SourceVault`SourceVaultResolvePromptRoute so this layer also
   loads when the router is absent.

   This section is all-ASCII.
   ============================================================ *)

(* step 1: weak probe for an existing unique route via the
   PromptRouter. A unique deterministic / lexical match means a
   route already exists and no new workflow may be generated. *)
iCPWExistingRouteMatch[prompt_String] :=
  Module[{decision},
    If[Names["SourceVault`SourceVaultResolvePromptRoute"] === {},
      Return[<|"Status" -> "RouterUnavailable"|>]];
    decision = Quiet @ Check[
      Symbol["SourceVault`SourceVaultResolvePromptRoute"][prompt],
      $Failed];
    If[!AssociationQ[decision],
      Return[<|"Status" -> "RouterUnavailable"|>]];
    If[Lookup[decision, "Status", ""] === "Matched",
      <|"Status" -> "ExistingRoute", "Decision" -> decision|>,
      <|"Status" -> "NoExistingRoute", "Decision" -> decision|>]
  ];
iCPWExistingRouteMatch[_] := <|"Status" -> "RouterUnavailable"|>;

Options[ClaudeWorkflowRouteFromPrompt] = {
  "MaxProposalAttempts" -> 3,
  "CodeProvider"        -> Automatic,
  "DryRunDraft"         -> True
};

ClaudeWorkflowRouteFromPrompt[prompt_String,
                              opts:OptionsPattern[]] :=
  Module[{provider, maxAttempts, dryRunDraft, routeProbe,
          complexity, proposal, draft, base},
    provider = OptionValue[
      ClaudeWorkflowRouteFromPrompt, {opts}, "CodeProvider"];
    maxAttempts = OptionValue[
      ClaudeWorkflowRouteFromPrompt, {opts},
      "MaxProposalAttempts"];
    If[!IntegerQ[maxAttempts] || maxAttempts < 1,
      maxAttempts = 3];
    dryRunDraft = TrueQ[OptionValue[
      ClaudeWorkflowRouteFromPrompt, {opts}, "DryRunDraft"]];

    base = <|
      "Type"            -> "WorkflowRouteDecision",
      "PromptFingerprint" ->
        "sha256:" <> Hash[prompt, "SHA256", "HexString"],
      "RouterVersion"   -> $ClaudePromptWorkflowVersion
    |>;

    (* step 1: an existing unique route wins (spec 23.9-1/2) *)
    routeProbe = iCPWExistingRouteMatch[prompt];
    If[Lookup[routeProbe, "Status", ""] === "ExistingRoute",
      Return[Join[base, <|
        "Decision" -> "UseExistingRoute",
        "Reason"   -> "ExistingRouteMatchedUniquely",
        "ExistingDecision" -> routeProbe["Decision"]|>]]];

    (* step 5: deterministic complex detector, local + LLM-free *)
    complexity = ClaudeWorkflowComplexPromptQ[prompt];
    If[!AssociationQ[complexity] ||
       Lookup[complexity, "Decision", ""] =!= "WorkflowCandidate",
      Return[Join[base, <|
        "Decision"   -> "NeedsHeavyLLM",
        "Reason"     -> "NotAWorkflowCandidate",
        "Complexity" -> complexity|>]]];

    (* step 7: propose a WorkflowNet (Order 8) *)
    proposal = ClaudeProposeWorkflowNetFromPrompt[prompt,
      "CodeProvider" -> provider,
      "MaxProposalAttempts" -> maxAttempts];

    If[!AssociationQ[proposal] ||
       Lookup[proposal, "Status", ""] =!= "Proposed",
      Return[Join[base, <|
        "Decision"   -> "WorkflowProposalFailed",
        "Reason"     -> Lookup[proposal, "Status", "ProposeFailed"],
        "Complexity" -> complexity,
        "Proposal"   -> proposal|>]]];

    (* steps 9-10: create a WorkflowRouteDraft (Order 9) *)
    draft = ClaudeCreateWorkflowRouteDraft[prompt, proposal,
      "DryRun" -> dryRunDraft];

    If[!AssociationQ[draft] ||
       !MemberQ[{"NeedsApproval", "DryRun"},
         Lookup[draft, "Status", ""]],
      Return[Join[base, <|
        "Decision" -> "WorkflowDraftFailed",
        "Reason"   -> Lookup[draft, "Status", "DraftFailed"],
        "Draft"    -> draft|>]]];

    (* step 11: a freshly generated workflow stops at
       NeedsApproval -- never auto-registered, never executed,
       even if the prompt asked to "create and run it" *)
    Join[base, <|
      "Decision"   -> "WorkflowDraftCreated",
      "Reason"     -> "NewWorkflowNeedsApproval",
      "Complexity" -> complexity,
      "Draft"      -> draft,
      "NextStep"   -> "AwaitUserApproval"
    |>]
  ];

ClaudeWorkflowRouteFromPrompt[___] :=
  <|"Type" -> "WorkflowRouteDecision",
    "Decision" -> "Failed",
    "Reason" -> "InvalidArguments",
    "Hint" ->
      "Expected ClaudeWorkflowRouteFromPrompt[prompt_String, opts]."|>;

End[];

EndPackage[];

(* ------------------------------------------------------------
   Load banner.
   ------------------------------------------------------------ *)
If[TrueQ[ClaudeOrchestrator`Private`$ClaudePromptWorkflowVerbose] =!= False,
  Print[Style[
    "ClaudeOrchestrator PromptWorkflow extension loaded (Order 10b).",
    "Section"]];
  Print["  Version : " <>
    ClaudeOrchestrator`$ClaudePromptWorkflowVersion];
  Print["  Phase   : Order 10b (ClaudeEval workflow integration)"];
  Print["  API:"];
  Print["    ClaudeWorkflowForbiddenPatternRegistry[]"];
  Print["    ClaudeWorkflowCheckForbidden[code_String]"];
  Print["    ClaudeParseWorkflowNetCode[input_String]"];
  Print["    ClaudeWorkflowNetWellFormedQ[spec_Association]"];
  Print["    ClaudeProposeWorkflowNetFromPrompt[prompt_String]"];
  Print["    ClaudeCreateWorkflowRouteDraft[prompt, proposal]"];
  Print["    ClaudeWorkflowComplexPromptQ[prompt_String]"];
  Print["    ClaudeWorkflowRouteFromPrompt[prompt_String]"];
  Print["    ClaudePromptWorkflowStatus[]"];
];
