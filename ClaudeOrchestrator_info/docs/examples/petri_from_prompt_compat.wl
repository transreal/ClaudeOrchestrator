(* ::Package:: *)

(* ::Title:: *)
(* petri_from_prompt_compat.wl *)

(* ============================================================
   petri_from_prompt_compat.wl

   DEPRECATED COMPATIBILITY SHIM (unified spec section 23.16).

   The natural-language-to-WorkflowNet capability that used to
   live in docs/examples/petri_from_prompt.wl has been redesigned
   into the supported API in ClaudeOrchestrator_promptworkflow.wl
   (Order 7 - Order 10):

     proposePetriNet      ->  ClaudeProposeWorkflowNetFromPrompt
     parsePetriCode       ->  ClaudeParseWorkflowNetCode
     runPetriFromPrompt   ->  ClaudeWorkflowRouteFromPrompt
                              (proposes a draft, stops at
                               NeedsApproval -- it does NOT run)

   Per spec 23.16 the old entry points are kept for ONE
   compatibility cycle as thin wrappers that:
     1. print a one-time deprecation notice;
     2. delegate to the new API;
     3. adapt the new Association result back to a shape close
        to the old return value.

   This shim does NOT reproduce the old parser. It requires
   ClaudeOrchestrator_promptworkflow.wl to be loaded first; if
   the new API is absent every wrapper returns a Failed
   Association explaining what to load.

   IMPORTANT: the old runPetriFromPrompt used to generate AND run
   a workflow. The new flow never auto-runs a freshly generated
   workflow (spec 23.7): this wrapper stops at the draft /
   NeedsApproval stage. Code that relied on auto-execution must
   move to the explicit approve-then-run path.

   This file is all-ASCII.
   ============================================================ *)

BeginPackage["PetriFromPromptCompat`"];

Quiet[ClearAll[
  "PetriFromPromptCompat`proposePetriNet",
  "PetriFromPromptCompat`parsePetriCode",
  "PetriFromPromptCompat`runPetriFromPrompt"
]];

proposePetriNet::usage =
  "proposePetriNet[goal_String, opts] is a DEPRECATED compatibility wrapper for ClaudeProposeWorkflowNetFromPrompt. Use the new API directly in new code.";

parsePetriCode::usage =
  "parsePetriCode[code_String] is a DEPRECATED compatibility wrapper for ClaudeParseWorkflowNetCode. Use the new API directly in new code.";

runPetriFromPrompt::usage =
  "runPetriFromPrompt[goal_String, opts] is a DEPRECATED compatibility wrapper. The new flow (ClaudeWorkflowRouteFromPrompt) proposes a WorkflowRouteDraft and stops at NeedsApproval; it does NOT auto-run a freshly generated workflow. Approve and run explicitly instead.";

proposePetriNet::deprecated =
  "proposePetriNet is deprecated; use ClaudeProposeWorkflowNetFromPrompt (ClaudeOrchestrator_promptworkflow.wl).";
parsePetriCode::deprecated =
  "parsePetriCode is deprecated; use ClaudeParseWorkflowNetCode (ClaudeOrchestrator_promptworkflow.wl).";
runPetriFromPrompt::deprecated =
  "runPetriFromPrompt is deprecated; the new flow stops at NeedsApproval and does not auto-run. Use ClaudeWorkflowRouteFromPrompt then approve explicitly.";

Begin["`Private`"];

$petriCompatVersion = "0.1.0-order12 (2026-05-24)";

(* one-time deprecation notice per symbol per session *)
$petriCompatWarned = <||>;
iWarnOnce[sym_Symbol, tag_String] :=
  If[!TrueQ[$petriCompatWarned[tag]],
    $petriCompatWarned[tag] = True;
    Message[MessageName[sym, "deprecated"]]];

(* is a new-API symbol available? *)
iNewApi[name_String] :=
  If[Names["ClaudeOrchestrator`" <> name] =!= {},
    Symbol["ClaudeOrchestrator`" <> name],
    $Failed];

iNewApiMissing[which_String] :=
  <|"Status" -> "Failed",
    "Reason" -> "NewApiNotLoaded",
    "Hint" ->
      "Load ClaudeOrchestrator_promptworkflow.wl, which provides " <>
      which <> "."|>;

(* ---- proposePetriNet -> ClaudeProposeWorkflowNetFromPrompt ---- *)
proposePetriNet[goal_String, opts:OptionsPattern[]] :=
  Module[{api, result},
    iWarnOnce[proposePetriNet, "propose"];
    api = iNewApi["ClaudeProposeWorkflowNetFromPrompt"];
    If[api === $Failed,
      Return[iNewApiMissing[
        "ClaudeProposeWorkflowNetFromPrompt"]]];
    result = api[goal];
    (* adapt: expose the old-style keys alongside the new ones *)
    If[AssociationQ[result],
      Append[result, <|
        "CompatShim"    -> "proposePetriNet",
        "CompatGoal"    -> goal,
        "CompatCode"    -> Lookup[result, "Code", ""]|>],
      <|"Status" -> "Failed", "Reason" -> "UnexpectedResult"|>]
  ];
proposePetriNet[___] :=
  <|"Status" -> "Failed", "Reason" -> "InvalidArguments",
    "Hint" -> "Expected proposePetriNet[goal_String, opts]."|>;

(* ---- parsePetriCode -> ClaudeParseWorkflowNetCode ---- *)
parsePetriCode[code_String] :=
  Module[{api, result},
    iWarnOnce[parsePetriCode, "parse"];
    api = iNewApi["ClaudeParseWorkflowNetCode"];
    If[api === $Failed,
      Return[iNewApiMissing["ClaudeParseWorkflowNetCode"]]];
    result = api[code];
    If[AssociationQ[result],
      Append[result, "CompatShim" -> "parsePetriCode"],
      <|"Status" -> "Failed", "Reason" -> "UnexpectedResult"|>]
  ];
parsePetriCode[___] :=
  <|"Status" -> "Failed", "Reason" -> "InvalidArguments",
    "Hint" -> "Expected parsePetriCode[code_String]."|>;

(* ---- runPetriFromPrompt -> ClaudeWorkflowRouteFromPrompt ---- *)
runPetriFromPrompt[goal_String, opts:OptionsPattern[]] :=
  Module[{api, result},
    iWarnOnce[runPetriFromPrompt, "run"];
    api = iNewApi["ClaudeWorkflowRouteFromPrompt"];
    If[api === $Failed,
      Return[iNewApiMissing["ClaudeWorkflowRouteFromPrompt"]]];
    result = api[goal];
    (* the new flow stops at NeedsApproval -- it does not run *)
    If[AssociationQ[result],
      Append[result, <|
        "CompatShim"  -> "runPetriFromPrompt",
        "CompatNote"  ->
          "The new flow stops at NeedsApproval and does not " <>
          "auto-run. Approve and run the WorkflowRouteDraft " <>
          "explicitly."|>],
      <|"Status" -> "Failed", "Reason" -> "UnexpectedResult"|>]
  ];
runPetriFromPrompt[___] :=
  <|"Status" -> "Failed", "Reason" -> "InvalidArguments",
    "Hint" -> "Expected runPetriFromPrompt[goal_String, opts]."|>;

End[];

EndPackage[];

If[TrueQ[PetriFromPromptCompat`Private`$petriCompatVerbose] =!= False,
  Print[Style[
    "petri_from_prompt compatibility shim loaded (Order 12).",
    "Section"]];
  Print["  Version : " <>
    PetriFromPromptCompat`Private`$petriCompatVersion];
  Print["  DEPRECATED: proposePetriNet / parsePetriCode / " <>
    "runPetriFromPrompt"];
  Print["  New API (ClaudeOrchestrator_promptworkflow.wl):"];
  Print["    ClaudeProposeWorkflowNetFromPrompt"];
  Print["    ClaudeParseWorkflowNetCode"];
  Print["    ClaudeWorkflowRouteFromPrompt"];
];
