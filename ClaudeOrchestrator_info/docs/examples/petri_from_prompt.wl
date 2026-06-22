(* ::Package:: *)

(* ::Title:: *)
(* petri_from_prompt.wl *)

(* ::Subsection:: *)
(* \:6982\:8981 *)

(* ============================================================
   \:81ea\:7136\:8a00\:8a9e\:30d7\:30ed\:30f3\:30d7\:30c8\:304b\:3089\:30da\:30c8\:30ea\:30cd\:30c3\:30c8 (WorkflowNet) \:3092\:69cb\:6210\:3057\:5b9f\:884c\:3059\:308b\:3002

   v2 (2026-05-08): \:751f\:6210\:30b3\:30fc\:30c9\:304c\:4ed8\:968f\:3057\:3066\:5b9f\:884c API \:307e\:3067\:542b\:3093\:3067\:3057\:307e\:3046\:554f\:984c\:306b\:5bfe\:51e6\:3002
     - \:6587\:5b57\:5217\:62bd\:51fa\:3092\:5f37\:5316 (First[{}] \:5bfe\:7b56)
     - LLM \:306b\:6e21\:3059\:30ac\:30a4\:30c9\:3092\:3088\:308a\:53b3\:5bc6\:306b: \"buildXxxNet[]\" \:95a2\:6570\:5b9a\:7fa9\:306e\:307f
     - \:751f\:6210\:30b3\:30fc\:30c9\:5185\:306e\:7981\:6b62 API \:3092\:691c\:51fa (ClaudeCreateWorkflowNet \:7b49)
     - \:30b3\:30fc\:30c9\:8a55\:4fa1\:3092 2 \:6bb5\:968e: \:95a2\:6570\:5b9a\:7fa9\:306e\:307f Get \:2192 builder() \:547c\:3073\:51fa\:3057

   v0.10.0 (2026-05-11): petri_from_prompt_chatgpt.wl \:3092\:30de\:30fc\:30b8\:7d71\:5408\:3002
     - proposePetriNetWithProvider \:2192 proposePetriNet \:306b\:7d71\:5408
       (\"Providers\" \:30aa\:30d7\:30b7\:30e7\:30f3\:3092\:8ffd\:52a0\:3001\:30c7\:30d5\:30a9\:30eb\:30c8\:306f {} = \:65e7 proposePetriNet \:3068\:540c\:3058)
     - parsePetriCode \:3092 Trap #16 \:4fee\:6b63\:7248\:306b\:7f6e\:63db\:3001fallback \:7d4c\:8def\:8ffd\:52a0
       (builder \:4e0d\:5728\:6642\:306b\:30b3\:30fc\:30c9\:672b\:5c3e\:306e WorkflowNet[...] \:5f0f\:3092\:76f4\:63a5\:8a55\:4fa1)
     - iCheckWorkerHandlerIssues \:7b49\:306e\:8ffd\:52a0\:9759\:7684\:691c\:67fb\:3092\:53d6\:308a\:8fbc\:307f
     - AddProviderSupportToPetriPrompt / AddANDMergeGuideToPetriPrompt /
       AddRetryGuideToPetriPrompt \:3092\:53d6\:308a\:8fbc\:307f (skill \:8aad\:307f\:8fbc\:307f\:578b)
     - iResolveModelPlaceholders / iFindModelByProviderClass /
       iFindModelByProvider \:3092\:53d6\:308a\:8fbc\:307f (rules/02 \:9075\:62e0)
     - checkLLMResponse / iIsLLMErrorResponse \:3092\:53d6\:308a\:8fbc\:307f
     - validateWorkflowOutput / extractReviewsFromWorkflow \:3092\:53d6\:308a\:8fbc\:307f
     - showHandlerTrace / diagnoseHandlerOutputs \:3092\:53d6\:308a\:8fbc\:307f
     petri_from_prompt_chatgpt.wl \:306f\:672c\:30d5\:30a1\:30a4\:30eb\:306b\:7d71\:5408\:3055\:308c\:3001\:524a\:9664\:3055\:308c\:305f\:3002
     \:4f5c\:52d5\:306f\:5168\:3066\:4e0a\:4f4d\:4e92\:63db: \:65e7 proposePetriNet[goal] \:306f\:305d\:306e\:307e\:307e\:52d5\:304d\:3001
     \:65e7 proposePetriNetWithProvider[goal, opts] \:306f proposePetriNet[goal, opts] \:3068\:540c\:3058\:52d5\:4f5c\:3002

   v0.10.1 (2026-05-12, Phase 27): iProposeOnce \:306e LLM \:547c\:3073\:51fa\:3057\:3092 CLI \:7d4c\:8def\:306b\:5909\:66f4\:3002
     - \:8a02\:6b63\:524d\:306f ClaudeQueryBg[prompt, Fallback -> True] \:3067\:8ab2\:91d1 API \:7d4c\:7531\:3060\:3063\:305f\:304c\:3001
       Imai \:5148\:751f\:306e\:8a2d\:8a08 (NBAccess \:304c absolute truth\:3001\:65b0\:898f\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:306f\:30c7\:30d5\:30a9\:30eb\:30c8\:7981\:6b62) \:3067\:306f
       proposePetriNet \:304c\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:3092\:958b\:3044\:305f\:76f4\:5f8c\:306b\:4f7f\:3048\:306a\:304f\:306a\:3063\:3066\:3057\:307e\:3046\:3002
     - \:30b3\:30fc\:30c9\:751f\:6210\:30bf\:30b9\:30af\:306f Claude Code CLI (\:8ab2\:91d1\:306a\:3057) \:3067\:5341\:5206\:306a\:306e\:3067\:3001
       \:30c7\:30d5\:30a9\:30eb\:30c8\:3067 CLI \:7d4c\:8def\:306b\:3057\:3066\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:8a2d\:5b9a\:3068\:72ec\:7acb\:306b\:52d5\:304f\:3088\:3046\:306b\:3057\:305f\:3002
     - LLM \:304c API \:30a8\:30e9\:30fc\:5fdc\:7b54\:3092\:8fd4\:3057\:305f\:5834\:5408\:306f\:30e6\:30fc\:30b6\:306b\:660e\:793a\:8868\:793a\:3059\:308b Print \:3092\:8ffd\:52a0\:3002
       \:3053\:308c\:304c\:306a\:3044\:3068\:3001response = "Error: ..." \:304c\:30b3\:30fc\:30c9\:62bd\:51fa\:306b\:6d41\:308c\:3066
       code = "" \:306e\:307e\:307e\:9762\:500d\:304f parsePetriCode[""] \:3068\:306a\:308a\:3001
       \:4f55\:304c\:8d77\:304d\:305f\:304b\:30e6\:30fc\:30b6\:306b\:898b\:3048\:306a\:304f\:306a\:308b\:3002
     - "IsErrorResponse" \:30ad\:30fc\:3092 result Association \:306b\:8ffd\:52a0\:3002
   ============================================================ *)

Needs["ClaudeOrchestrator`Workflow`"];

If[!ValueQ[ClaudeCode`ClaudeQueryBg] &&
   Length[DownValues[ClaudeCode`ClaudeQueryBg]] === 0,
  Print[Style["WARNING: ClaudeQueryBg \:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093\:3002 " <>
    "claudecode.wl \:3092\:5148\:306b Get \:3057\:3066\:304f\:3060\:3055\:3044\:3002", Bold, Red]]];

(* ::Subsection:: *)
(* 1. LLM \:30ac\:30a4\:30c9\:30c6\:30ad\:30b9\:30c8 *)

$petriNetGuide = "
You design Wolfram Language Petri Nets using ClaudeOrchestrator`Workflow` API.

# API

WorkflowToken[\"Kind\" -> \"Task\", \"Payload\" -> <|...|>]
WorkflowPlace[\"Name\", \"Capacity\" -> 1, \"AcceptedKinds\" -> {\"Task\"}]
WorkflowTransition[\"Name\",
  \"InputArcs\"  -> {<|\"Place\" -> \"P1\", \"Multiplicity\" -> 1|>},
  \"OutputArcs\" -> {<|\"Place\" -> \"P2\", \"Multiplicity\" -> 1, \"TokenKind\" -> \"Result\"|>},
  \"Guard\"      -> Function[binding, ...],
  \"Executor\"   -> \"PureFunction\",
  \"RuntimeSpec\" -> <|\"Handler\" -> myHandler|>]
WorkflowNet[
  \"SourcePlace\" -> \"Start\",
  \"FinalPlaces\" -> {\"Done\"},
  \"Places\" -> <|...|>,
  \"Transitions\" -> <|...|>]

# Source token Payload key convention (CRITICAL)

The user creates the Source token via the helper

  ClaudeBindAndSubmit[wid, var1, var2, ...]

which uses SymbolName[varK] VERBATIM as the Payload key (no case
transformation, no translation). Therefore, when the user goal
mentions Mathematica variable names, you MUST use those EXACT names
as Payload keys in the FIRST worker / Distribute handler.

Examples (the right column is the Source token's Payload):
  goal: \"textに代入されたテキストを...\"
    Source Payload: <|\"text\" -> ...|>
    handler reads: Lookup[binding[[\"Source\", \"Payload\"]], \"text\", \"\"]

  goal: \"titleとtextを連結し...\"
    Source Payload: <|\"title\" -> ..., \"text\" -> ...|>
    handler reads: Lookup[binding[[\"Source\", \"Payload\"]], \"title\", \"\"]
                   Lookup[binding[[\"Source\", \"Payload\"]], \"text\", \"\"]

  goal: \"本文をレビューし...\"  (CJK identifiers are valid Mathematica symbols)
    Source Payload: <|\"本文\" -> ...|>
    handler reads: Lookup[binding[[\"Source\", \"Payload\"]], \"本文\", \"\"]

  goal: \"inputData を処理し...\"  (camelCase preserved)
    Source Payload: <|\"inputData\" -> ...|>

Rules:
- DO NOT translate Japanese / CJK variable names like \"本文\" to English
  keys like \"Text\" or \"Body\". Mathematica symbols may contain CJK
  characters and the helper preserves them verbatim.
- DO NOT capitalize, lowercase, or otherwise transform the symbol name.
- DO NOT invent unrelated key names like \"Plan\", \"Trial\", \"Input\",
  \"Data\" when the goal does not mention them.
- If the goal uses a noun-phrase rather than a Mathematica identifier
  (e.g. \"the input text\", \"the article body\"), default to the
  single key \"text\" and note the fallback in a code comment.
- If the goal explicitly states different keys (e.g. \"the token has
  keys X, Y, Z\"), use those.

# Handler — DETAILED template

A handler receives a `binding` Association whose KEYS are the Place NAMES
listed in the transition's InputArcs. To get the Payload of an input token:
  binding[[\"PlaceName\"]][[\"Payload\"]]

For Multiplicity 1 input arcs, binding[[place]] is a single token Association.
For Multiplicity N input arcs (Join), binding[[place]] is a List of N tokens.

handler = Function[binding, Module[{inputTok, inputPayload, payload},
  inputTok = binding[[\"InputPlaceName\"]];                  (* token *)
  inputPayload = inputTok[[\"Payload\"]];                    (* the Payload *)
  payload = <|
    \"key1\" -> Lookup[inputPayload, \"key1\", \"default\"], (* preserve fields *)
    \"key2\" -> computedValue
  |>;
  <|\"Payload\" -> payload|>
]];

CRITICAL handler rules (lessons from real failures):

(a) Always go through [[\"Payload\"]] when reading token data.
    WRONG: tok = binding[[\"PoolA\"]]; x = tok[[\"Text\"]]
    RIGHT: tok = binding[[\"PoolA\"]]; x = tok[[\"Payload\", \"Text\"]]

(b) Use Lookup[..., key, default] instead of [[]] when reading Payload keys
    that might be absent. Bare [[]] returns Missing[KeyAbsent, key] which
    then propagates as Missing into && / || / numeric ops, causing silent
    failures.
    WRONG: trial = tok[[\"Payload\", \"Trial\"]]
    RIGHT: trial = Lookup[tok[[\"Payload\"]], \"Trial\", 1]

(c) For Aggregate handlers (Multiplicity > 1 input), iterate the list and
    pull each token's Payload separately:
    aggregateHandler = Function[binding, Module[{toks, payloads, decision},
      toks = binding[[\"ResultPool\"]];           (* a List of N tokens *)
      payloads = toks[[All, \"Payload\"]];         (* List of N Payloads *)
      decision = If[some-condition, \"OK\", \"Repair\"];
      <|\"Payload\" -> <|\"Results\" -> payloads,
                      \"Decision\" -> decision,
                      \"Trial\" -> Lookup[First[payloads], \"Trial\", 1]|>|>
    ]];

(d) The Verdict token's Payload MUST contain the keys that downstream Guards
    check. If your Guards check \"Decision\" and \"Trial\", the Aggregate (or
    whichever transition writes to Verdict) MUST set both keys explicitly.
    A missing key => Missing[KeyAbsent,...] => Guard returns Missing not
    False => no transition fires => workflow Stuck at Verdict.

(e) Each Worker handler MUST add its review/processing result to the output
    Payload, NOT just pass through the input Text. The output Payload should
    contain at least one NEW key like \"Review\", \"Verdict\", \"Comment\",
    \"Score\", or \"Result\" that holds the LLM's response or computed value.
    DO NOT do this:
      workerA = Function[b, Module[{p}, p = b[[\"PoolA\", \"Payload\"]];
        <|\"Payload\" -> p|>]]   (* WRONG: passes Text through unchanged *)
    DO this (ASYNCHRONOUS SessionSubmit PATTERN — see section below):
      workerA = Function[b, Module[{p, text,
                                    wid = $ClaudeCurrentWid,
                                    aid = $ClaudeCurrentAwaitId},
        p = b[[\"PoolA\", \"Payload\"]];
        text = Lookup[p, \"Text\", \"\"];
        With[{wid1 = wid, aid1 = aid, p1 = p, t = text},
          SessionSubmit[ScheduledTask[
            Module[{review = Quiet @ Check[
                ClaudeCode`ClaudeQueryBg[\"Review (one paragraph): \" <> t],
                \"[Error] ClaudeQueryBg failed.\"]},
              ClaudeOrchestrator`Workflow`ClaudeCompleteHandlerOutput[
                wid1, aid1,
                <|\"Payload\" -> Append[p1, \"ReviewA\" -> review]|>]],
            {0.01, 1}]]];
        <|\"Status\" -> \"AwaitingLLM\",
          \"Payload\" -> p|>]]   (* partial payload, retained until callback *)
    The Aggregate handler then collects \"ReviewA\"/\"ReviewB\"/\"ReviewC\"
    from each input token's Payload and produces a Decision.

(f) The Permit/Finalize handler should produce a Payload whose value-bearing
    key has a CLEAR NAME like \"FinalReview\", \"Verdict\", \"Decision\".
    Avoid emitting only \"Text\" because the user cannot tell whether \"Text\"
    is the original input or the processed result.

(g) STRICT PAYLOAD KEY CONVENTION (mandatory).
    The final Payload (the one Permit/Finalize emits to the Done place) MUST
    contain a key named EXACTLY \"FinalResult\". This is a fixed convention so
    the user's downstream code can always retrieve the result without guessing
    the key name. Use \"FinalResult\" even if the value is also stored under
    other keys.
    
    Example final transition:
      finalize = Function[b, Module[{p, finalResult},
        p = b[[\"Verdict\", \"Payload\"]];
        finalResult = <|
          \"Reviews\"  -> Lookup[p, \"Reviews\", {}],
          \"Decision\" -> Lookup[p, \"Decision\", \"?\"],
          \"Trial\"    -> Lookup[p, \"Trial\", 1]|>;
        <|\"Payload\" -> Append[p, \"FinalResult\" -> finalResult]|>]]
    
    Worker handlers should use clear semantic key names like \"ReviewA\",
    \"ScoreA\", \"OutputA\" (not just \"Text\").
    
    Aggregate handlers should produce \"Reviews\" (List), \"Scores\" (List),
    or similar plural keys that are clearly aggregated results.

# Critical rules

1. OutputArc Multiplicity is IGNORED. To produce N tokens, use N OutputArc entries.
2. ALL OutputArcs receive the same Payload.
3. binding keys are Place names, not token Kinds.
4. NEVER use Return[<|...|>] inside Function[binding, Module[...]].
5. For LLM calls inside handlers, use the ASYNCHRONOUS SessionSubmit PATTERN
   below (handler returns <|\"Status\" -> \"AwaitingLLM\"|> immediately and
   spawns a SessionSubmit task that calls ClaudeQueryBg + ClaudeCompleteHandlerOutput).
   DO NOT call ClaudeCode`ClaudeQueryBg synchronously DIRECTLY inside a handler
   — it blocks the main kernel for the duration of the LLM response and freezes
   front-end dynamic evaluation (\"動的評価の放棄\" dialog).
   DO NOT use ClaudeCode`ClaudeQueryAsyncSilent — its callback is not delivered
   reliably in current environments (the shared polling task may auto-abort
   during workflow ticks; this is reserved for future repair).
6. Each parallel worker MUST pull from its OWN DEDICATED Place. NEVER share an
   input Place between two or more workers. Sharing causes one worker to grab
   ALL tokens (Wolfram's SortBy gives lexicographic priority to alphabetically-
   earlier transition names like \"WorkerA\" over \"WorkerB\"), and the other
   workers never fire.

# Asynchronous LLM call pattern (REQUIRED for LLM handlers)

When a transition handler needs to call an LLM, you MUST use the
SessionSubmit pattern below.  The handler returns IMMEDIATELY with the
sentinel Association <|\"Status\" -> \"AwaitingLLM\", ...|> and SPAWNS a
SessionSubmit task that:
  (a) calls ClaudeQueryBg synchronously (safe inside SessionSubmit body
      because the handler itself has already returned, so the main
      evaluator is free during the LLM round-trip),
  (b) when ClaudeQueryBg returns, calls ClaudeCompleteHandlerOutput
      with the response, producing the output tokens.

Why this pattern is required:
- Workflow ticks run inside SessionSubmit/ScheduledTask on the main kernel.
- A synchronous LLM call DIRECTLY in the handler blocks the main kernel for
  30-60 s.  During that time, all Dynamic evaluations are frozen and the
  front end shows \"動的評価の放棄\" dialog.
- The SessionSubmit pattern keeps each tick short (a few ms), so the front
  end keeps updating smoothly even during LLM calls.
- This pattern was verified end-to-end on 2026-05-17 (8 s round-trip,
  Done place populated with Claude's response, no kernel freeze).

## Template — single LLM call handler (C-2 pattern)

  reviewHandler = Function[binding,
    Module[{p, text,
            wid = $ClaudeCurrentWid,                   (* (1) capture context *)
            aid = $ClaudeCurrentAwaitId},
      p    = binding[[\"InputPlace\", \"Payload\"]];   (* (2) read input *)
      text = Lookup[p, \"Text\", \"\"];

      (* (3) Fire-and-forget SessionSubmit.  Note the With[{wid1=..., aid1=...,
             p1=..., t=...}] captures the values lexically so the body sees
             stable bindings even after handler returns. *)
      With[{wid1 = wid, aid1 = aid, p1 = p, t = text},
        SessionSubmit[ScheduledTask[
          Module[{review},
            review = Quiet @ Check[
              ClaudeCode`ClaudeQueryBg[\"Review for clarity: \" <> t],
              \"[Error] ClaudeQueryBg threw an exception.\"];
            If[!StringQ[review] || StringLength[review] === 0,
              review = \"[Error] ClaudeQueryBg returned empty/non-string.\"];
            ClaudeOrchestrator`Workflow`ClaudeCompleteHandlerOutput[
              wid1, aid1,
              <|\"Payload\" -> Append[p1, \"Review\" -> review]|>]
          ],
          {0.01, 1}]]];

      (* (4) Return AwaitingLLM sentinel.  The workflow engine will:
               - consume input tokens NOW (so other transitions don't refire)
               - hold the output Place empty
               - register this transition in AwaitingLLMTransitions
             When ClaudeCompleteHandlerOutput is called from the SessionSubmit
             body, output tokens are produced and downstream transitions fire. *)
      <|\"Status\"  -> \"AwaitingLLM\",
        \"Payload\" -> p|>     (* optional partial payload for diagnostics *)
    ]];

## Optional safety net (recommended for long-running LLM calls)

Add a second SessionSubmit with a 90 s timeout so the workflow does not
deadlock if ClaudeQueryBg hangs indefinitely.  The safety net checks
ClaudeAwaitingTransitions[wid1] and, if the awaitId is still pending,
manually completes with an error payload.

  With[{wid1 = wid, aid1 = aid, p1 = p},
    SessionSubmit[ScheduledTask[
      Quiet @ Check[
        Module[{rows = Normal @
                        ClaudeOrchestrator`Workflow`ClaudeAwaitingTransitions[wid1]},
          If[ListQ[rows] &&
             AnyTrue[rows, Lookup[#, \"AwaitId\", \"\"] === aid1 &],
            ClaudeOrchestrator`Workflow`ClaudeCompleteHandlerOutput[
              wid1, aid1,
              <|\"Payload\" -> Append[p1, \"Review\" ->
                \"[SAFETY-NET] LLM did not return within 90 s.\"]|>]]],
        Null],
      {90, 1}]]];

## Dynamic context symbols (only valid INSIDE a handler)

  $ClaudeCurrentWid          — current WorkflowId
  $ClaudeCurrentTransition   — current transition Name
  $ClaudeCurrentAwaitId      — newly issued await ID (use in callback)
  $ClaudeCurrentBinding      — the binding Association

These are Block-bound by iExecutePureFunction during handler evaluation.
Outside a handler they evaluate to Missing[\"NotInHandler\"].

ALWAYS capture wid / aid as local Module variables BEFORE issuing the
SessionSubmit.  The With[{wid1=wid, aid1=aid, ...}] in the template
preserves them as lexical bindings even if the SessionSubmit body runs
much later on a different scheduled task.

  RIGHT (local capture + With closes over them):
    Module[{wid = $ClaudeCurrentWid, aid = $ClaudeCurrentAwaitId},
      With[{wid1 = wid, aid1 = aid, ...},
        SessionSubmit[ScheduledTask[
          ... ClaudeCompleteHandlerOutput[wid1, aid1, ...] ...,
          {0.01, 1}]]]]

  WRONG (referencing the dynamic symbols inside the SessionSubmit body —
  they will be Missing[\"NotInHandler\"] when the body fires):
    SessionSubmit[ScheduledTask[
      ... ClaudeCompleteHandlerOutput[
        $ClaudeCurrentWid, $ClaudeCurrentAwaitId, ...] ...,
      {0.01, 1}]]

## Rules — async SessionSubmit pattern

(i)   ALWAYS capture $ClaudeCurrentWid and $ClaudeCurrentAwaitId in a
      local Module variable, and use With[{wid1=wid, aid1=aid, ...}]
      around the SessionSubmit to bind them lexically.
(ii)  The SessionSubmit body must call ClaudeCompleteHandlerOutput
      EXACTLY ONCE.  Calling it twice for the same aid will silently
      no-op the second call.
(iii) Output payload passed to ClaudeCompleteHandlerOutput goes through
      the SAME OutputArcs as a normal Fired result.  Wrap the final
      payload as <|\"Payload\" -> <|...|>|> just like a normal handler.
(iv)  Handlers that DON'T need LLM (pure compute / aggregate / route)
      can keep using the synchronous <|\"Payload\" -> ...|> return form.
      Only LLM-calling handlers need the AwaitingLLM pattern.
(v)   If the workflow is Cancelled while a SessionSubmit body is still
      pending, ClaudeCompleteHandlerOutput becomes a silent no-op
      (TransitionCallbackDiscarded event is logged in Trace).
(vi)  Use ClaudeQueryBg (synchronous API) inside the SessionSubmit body,
      NOT ClaudeQueryAsyncSilent.  ClaudeQueryAsyncSilent's callback is
      not reliably delivered in current environments (shared polling
      task may auto-abort during workflow ticks; reserved for future
      repair).
(vii) ClaudeQueryBg is rule 95-A safe: it does no FrontEnd / ScheduledTask
      creation and can be called from any non-blocking context including
      SessionSubmit bodies.

## WRONG patterns

WRONG 1 — direct synchronous call inside handler (blocks kernel 30-60 s,
triggers \"動的評価の放棄\" dialog):
  reviewHandler = Function[b, Module[{p, text, review},
    p = b[[\"InputPlace\", \"Payload\"]];
    text = Lookup[p, \"Text\", \"\"];
    review = ClaudeCode`ClaudeQueryBg[\"Review: \" <> text];   (* BLOCKS *)
    <|\"Payload\" -> Append[p, \"Review\" -> review]|>]];

WRONG 2 — ClaudeQueryAsyncSilent (callback not delivered in current
environments; reserved for future repair):
  reviewHandler = Function[b, Module[{...},
    ClaudeCode`ClaudeQueryAsyncSilent[prompt,
      Function[r, ClaudeCompleteHandlerOutput[wid, aid, ...]]];
    <|\"Status\" -> \"AwaitingLLM\"|>]];

# WRONG vs RIGHT example for parallel fan-out

The following example shows the most common mistake: 3 workers sharing a Pool.

WRONG (sharing Pool causes WorkerA to monopolize tokens):
  \"Pool\"   -> WorkflowPlace[\"Pool\"],
  \"WorkerA\" -> WorkflowTransition[\"WorkerA\",
    \"InputArcs\" -> {<|\"Place\" -> \"Pool\", \"Multiplicity\" -> 1|>}, ...],
  \"WorkerB\" -> WorkflowTransition[\"WorkerB\",
    \"InputArcs\" -> {<|\"Place\" -> \"Pool\", \"Multiplicity\" -> 1|>}, ...],
  \"WorkerC\" -> WorkflowTransition[\"WorkerC\",
    \"InputArcs\" -> {<|\"Place\" -> \"Pool\", \"Multiplicity\" -> 1|>}, ...]
  -> WorkerA fires 3 times, WorkerB and WorkerC never fire, Join stuck.

RIGHT (each worker has its own dedicated input Place):
  \"PoolA\" -> WorkflowPlace[\"PoolA\"],
  \"PoolB\" -> WorkflowPlace[\"PoolB\"],
  \"PoolC\" -> WorkflowPlace[\"PoolC\"],
  \"Distribute\" -> WorkflowTransition[\"Distribute\",
    \"InputArcs\"  -> {<|\"Place\" -> \"Source\", \"Multiplicity\" -> 1|>},
    \"OutputArcs\" -> {
      <|\"Place\" -> \"PoolA\", \"Multiplicity\" -> 1, \"TokenKind\" -> \"Task\"|>,
      <|\"Place\" -> \"PoolB\", \"Multiplicity\" -> 1, \"TokenKind\" -> \"Task\"|>,
      <|\"Place\" -> \"PoolC\", \"Multiplicity\" -> 1, \"TokenKind\" -> \"Task\"|>}, ...],
  \"WorkerA\" -> WorkflowTransition[\"WorkerA\",
    \"InputArcs\" -> {<|\"Place\" -> \"PoolA\", \"Multiplicity\" -> 1|>}, ...],
  \"WorkerB\" -> WorkflowTransition[\"WorkerB\",
    \"InputArcs\" -> {<|\"Place\" -> \"PoolB\", \"Multiplicity\" -> 1|>}, ...],
  \"WorkerC\" -> WorkflowTransition[\"WorkerC\",
    \"InputArcs\" -> {<|\"Place\" -> \"PoolC\", \"Multiplicity\" -> 1|>}, ...]
  -> Each worker fires exactly once on its dedicated token. Join can collect 3.

# CRITICAL: Use feedback loops, NOT duplicated retry transitions

When the goal involves \"retry on failure\" or \"loop back if not satisfied\",
USE A FEEDBACK LOOP back to the original transitions. Do NOT duplicate the
review/work transitions into a separate Retry chain. Petri nets natively
express loops via OutputArcs that point back to upstream Places.

WRONG (duplicating workers for retry doubles the node count):
  \"Distribute\" -> ...  ->  \"ReviewA\", \"ReviewB\", \"ReviewC\"
  -> \"Join\" -> \"FailCheck\" -> \"RetryDist\"
  -> \"RetryA\", \"RetryB\", \"RetryC\"            <- duplicated!
  -> \"RetryJoin\" -> \"Done\"
  Total: ~12 transitions, ~16 places. Hard to extend to N retries.

RIGHT (single set of workers reused via feedback loop):
  \"Plan\" (Capacity 1) -> \"Distribute\" -> \"PoolA/B/C\"
  -> \"WorkerA/B/C\" -> \"ResultPool\"
  -> \"Aggregate\" -> \"Verdict\"
  -> \"Permit\" (Guard: pass)     -> \"Done\"
  -> \"Retry\"  (Guard: fail && trial<MaxTrials) -> \"Plan\"   <- FEEDBACK!
  -> \"GiveUp\" (Guard: trial>=MaxTrials)        -> \"GivenUp\"
  Total: ~8 transitions, ~9 places. Trivially extends to N retries
  by changing only the trial counter.

Concrete loop construction:
  \"Plan\" -> WorkflowPlace[\"Plan\", \"Capacity\" -> 1, \"AcceptedKinds\" -> {\"Plan\"}],
  \"Retry\" -> WorkflowTransition[\"Retry\",
    \"InputArcs\"  -> {<|\"Place\" -> \"Verdict\", \"Multiplicity\" -> 1|>},
    \"OutputArcs\" -> {<|\"Place\" -> \"Plan\", \"Multiplicity\" -> 1, \"TokenKind\" -> \"Plan\"|>},
    \"Guard\" -> Function[b,
      And[b[[\"Verdict\", \"Payload\", \"Decision\"]] === \"Repair\",
          b[[\"Verdict\", \"Payload\", \"Trial\"]] < 3]],
    \"Executor\" -> \"PureFunction\",
    \"RuntimeSpec\" -> <|\"Handler\" -> Function[binding,
      Module[{verdict, oldTrial},
        verdict = binding[[\"Verdict\"]];
        oldTrial = verdict[[\"Payload\", \"Trial\"]];
        <|\"Payload\" -> Append[verdict[[\"Payload\"]], \"Trial\" -> oldTrial + 1]|>
      ]]|>]

KEY POINTS for feedback loops:
1. The Plan place MUST have Capacity 1 (prevents two retries running in parallel).
2. The Retry transition MUST have a Guard checking trial < MaxTrials (otherwise
   infinite loop).
3. Track the trial counter in the token's Payload (NOT in a global variable).
4. Provide a separate GiveUp transition with Guard checking trial >= MaxTrials,
   pointing to a GivenUp final place.

# Token payload conventions for loops

When using feedback loops, token Payload must carry:
  - the trial counter, e.g. \"Trial\" -> 1, 2, 3, ...
  - the original input data needed for retry (e.g. \"Text\" -> \"...\")
  - the previous Verdict's Decision so the Retry handler can advance the trial

# Node count rule of thumb

For an N-worker, M-retry workflow:
  - Use feedback loops: places ~= N+5, transitions ~= N+5  (independent of M!)
  - DO NOT duplicate transitions per retry attempt.

# OUTPUT FORMAT (STRICT)

Reply with EXACTLY ONE ```mathematica code block. The block must contain:
  (a) zero or more handler definitions using `:=`
  (b) EXACTLY ONE function definition of the form:
      buildMyNet[] := WorkflowNet[ ... ]
  Replace `MyNet` with a descriptive name.

ABSOLUTELY FORBIDDEN in your code (will be rejected):
  - ClaudeCreateWorkflowNet[...]
  - ClaudeRunWorkflow[...]
  - ClaudeSubmitToken[...]
  - ClaudeWaitWorkflow[...]
  - Any top-level code that EXECUTES (only DEFINITIONS allowed)
  - Print[...]
  - Module evaluation outside of := definitions

# COMPACTNESS (CRITICAL)

Output capacity is LIMITED. Your reply MUST fit in approximately 600 lines.
To stay compact:
  - Do NOT inline large prompt strings inside ClaudeQueryBg. Use short prompts
    or hard-coded values for the demo.
  - Reuse handlers via factory functions: `makeWorker[label] := Function[binding, ...]`
    instead of writing each worker out separately.
  - Use SHORT Place/Transition names (e.g. \"P1\", \"WkA\") if you have many.
  - Do NOT add comments inside the code block.
  - Keep Guard functions one-line when possible.

The caller will: (1) evaluate your code to load definitions, (2) call buildXxxNet[]
to obtain the WorkflowNet, (3) submit tokens and run the workflow.

DO NOT include explanatory prose outside the code block. Output ONLY the code block.
END your reply with the closing ``` on its own line. Do not omit it.
";

(* ::Subsection:: *)
(* 2. \:6587\:5b57\:5217\:30e6\:30fc\:30c6\:30a3\:30ea\:30c6\:30a3 *)

ClearAll[iSafeFirst, iExtractCodeBlock, iFindBuilderName, iCheckForbiddenAPIs];

(* First[{}] \:5bfe\:7b56\:3002 \:7a7a\:3084 $Failed \:306a\:3089\:30c7\:30d5\:30a9\:30eb\:30c8\:3092\:8fd4\:3059 *)
iSafeFirst[lst_List, default_:""] :=
  If[lst === {} || lst === $Failed, default, First[lst]];
iSafeFirst[other_, default_:""] := default;

(* response \:304b\:3089 ```mathematica ... ``` \:30d6\:30ed\:30c3\:30af\:3092\:62bd\:51fa\:3002
   \:8907\:6570\:3042\:308c\:3070\:6700\:9577\:306e\:3082\:306e\:3092\:8fd4\:3059\:3002
   \:5fdc\:7b54\:304c truncate \:3055\:308c\:3066\:9589\:3058 ``` \:304c\:7121\:3044\:5834\:5408\:306f\:3001
   ```mathematica \:4ee5\:964d\:5168\:3066\:3092 fallback \:3068\:3057\:3066\:62bd\:51fa\:3059\:308b\:3002 *)
iExtractCodeBlock[response_String] :=
  Module[{matches, openIdx, withClose, withoutClose},
    (* Pass 1: ```mathematica ... ``` (closed) *)
    matches = StringCases[response,
      "```mathematica" ~~ Whitespace... ~~
      code__ ~~
      Whitespace... ~~ "```" :> code,
      Overlaps -> False];
    
    (* Pass 2: ``` ... ``` (any language, closed) *)
    If[Length[matches] === 0,
      matches = StringCases[response,
        "```" ~~ Whitespace... ~~
        code__ ~~
        Whitespace... ~~ "```" :> code,
        Overlaps -> False]];
    
    (* Pass 3 (fallback): ``` \:304c\:9589\:3058\:3066\:3044\:306a\:3044 \[Rule] \:6700\:521d\:306e ```mathematica
       \:307e\:305f\:306f ``` \:4ee5\:964d\:3092\:5168\:3066\:53d6\:308b *)
    If[Length[matches] === 0,
      openIdx = StringPosition[response, "```mathematica", 1];
      If[Length[openIdx] === 0,
        openIdx = StringPosition[response, "```", 1]];
      If[Length[openIdx] > 0,
        matches = {StringTrim @ StringDrop[response, openIdx[[1, 2]]]}]];
    
    If[Length[matches] === 0, "",
      First @ SortBy[matches, -StringLength[#] &]]
  ];
iExtractCodeBlock[_] := "";

(* code \:5185\:306e \"buildXxx[\" \:30d1\:30bf\:30fc\:30f3\:3092\:63a2\:3059 *)
iFindBuilderName[code_String] :=
  Module[{matches, names},
    matches = StringCases[code,
      "build" ~~ x:LetterCharacter.. ~~ "[" :> "build" <> x];
    names = DeleteDuplicates[matches];
    iSafeFirst[names, ""]
  ];
iFindBuilderName[_] := "";

(* \:7981\:6b62 API \:304c\:30b3\:30fc\:30c9\:306b\:542b\:307e\:308c\:3066\:3044\:308b\:304b\:30c1\:30a7\:30c3\:30af *)
iCheckForbiddenAPIs[code_String] :=
  Module[{forbidden, found},
    forbidden = {"ClaudeCreateWorkflowNet",
                 "ClaudeRunWorkflow",
                 "ClaudeSubmitToken",
                 "ClaudeWaitWorkflow",
                 "ClaudeStepWorkflow",
                 "ClaudeFireTransition"};
    found = Select[forbidden, StringContainsQ[code, #] &];
    found
  ];
iCheckForbiddenAPIs[_] := {};

(* \:7f60 #3 (\:5171\:6709\:5165\:529b Place) \:306e\:691c\:51fa\:3002
   Transition \:30d6\:30ed\:30c3\:30af\:3054\:3068\:306b\:30d1\:30fc\:30b9\:3057\:3001Guard \:3092\:6301\:3064 transition \:306f
   \:5206\:5c90\:30eb\:30fc\:30c8 (\:5171\:6709\:304c\:5fc5\:8981) \:3068\:307f\:306a\:3057\:3066\:9664\:5916\:3002
   Guard \:4e0d\:5728\:306e\:8907\:6570 transition \:304c\:540c\:3058 InputArc Place \:3092\:5171\:6709\:3057\:3066\:3044\:308b\:5834\:5408\:306e\:307f
   \:7f60 #3 \:3068\:3057\:3066\:691c\:51fa\:3059\:308b\:3002 *)
ClearAll[iCheckSharedInputPlaces];
iCheckSharedInputPlaces[code_String] :=
  Module[{transBlocks, parsed, places, counts, suspicious},
    (* Pass 1: WorkflowTransition[...] \:30d6\:30ed\:30c3\:30af\:3054\:3068\:306b\:5206\:5272 *)
    transBlocks = StringCases[code,
      "WorkflowTransition[" ~~ blk:Shortest[___] ~~ "]," :> blk];
    (* Pass 2: \:5404\:30d6\:30ed\:30c3\:30af\:304b\:3089 InputArc \:5185\:306e Place \:3068 Guard \:6709\:7121\:3092\:62bd\:51fa *)
    parsed = Map[
      Function[blk,
        Module[{inputArcs, placesInBlock, hasGuard},
          inputArcs = StringCases[blk,
            "\"InputArcs\"" ~~ Whitespace... ~~ "->" ~~ Whitespace... ~~
            "{" ~~ ia:Shortest[___] ~~ "}" :> ia];
          placesInBlock = If[Length[inputArcs] === 0, {},
            StringCases[First[inputArcs],
              "\"Place\"" ~~ Whitespace... ~~ "->" ~~ Whitespace... ~~
              "\"" ~~ name:Except["\""].. ~~ "\"" :> name]];
          hasGuard = StringContainsQ[blk, "\"Guard\""];
          <|"Places" -> placesInBlock, "HasGuard" -> hasGuard|>
        ]],
      transBlocks];
    (* Pass 3: Guard \:7121\:3057 transition \:306e Place \:3060\:3051\:3067 count *)
    places = Flatten @ Map[
      If[#[["HasGuard"]], {}, #[["Places"]]] &,
      parsed];
    counts = Counts[places];
    suspicious = Select[Keys[counts], counts[#] >= 2 &];
    suspicious
  ];
iCheckSharedInputPlaces[_] := {};

(* DAG \:91cd\:8907\:30d1\:30bf\:30fc\:30f3\:306e\:691c\:51fa: \:540c\:3058\:5f79\:5272\:3092 2 \:3064\:4ee5\:4e0a\:306e transition \:540d\:3067
   \:8868\:3057\:3066\:3044\:308b\:30b1\:30fc\:30b9 (Review/Retry, Worker/Worker2 \:7b49) \:3092\:691c\:51fa *)
ClearAll[iCheckDuplicatedTransitions];
iCheckDuplicatedTransitions[code_String] :=
  Module[{transNames, baseSets, dups},
    transNames = StringCases[code,
      "\"" ~~ name:LetterCharacter.. ~~ "\"" ~~ Whitespace... ~~ "->" ~~
      Whitespace... ~~ "WorkflowTransition[" :> name];
    transNames = DeleteDuplicates[transNames];
    (* "Retry" prefix \:307e\:305f\:306f \"_2\" suffix \:30d1\:30bf\:30fc\:30f3 *)
    dups = Select[transNames,
      Function[name,
        Or[
          (* Retry-prefix: Retry \:3092\:524a\:308b\:3068\:5143\:540d\:304c\:5b58\:5728 *)
          And[StringStartsQ[name, "Retry"],
              MemberQ[transNames, StringDrop[name, 5]]],
          (* numeric suffix: 2 \:3092\:5916\:3059\:3068\:5143\:540d\:304c\:5b58\:5728 *)
          And[StringEndsQ[name, "2"],
              MemberQ[transNames, StringDrop[name, -1]]]]]];
    dups
  ];
iCheckDuplicatedTransitions[_] := {};

(* \:7121\:9650\:30eb\:30fc\:30d7\:9632\:6b62\:306e\:691c\:67fb: Retry / Loop \:3092\:884c\:3046 transition \:306b
   \"Trial\" \:3068 \"<\" \:3084 \"GiveUp\" \:3068\:3044\:3046\:30ad\:30fc\:30ef\:30fc\:30c9\:304c\:542b\:307e\:308c\:3066\:3044\:308b\:304b\:691c\:67fb\:3002
   \:542b\:307e\:308c\:3066\:3044\:306a\:3044\:3068\:3001\:30c8\:30fc\:30af\:30f3\:904e\:5270\:6d88\:8cbb\:306e\:30ea\:30b9\:30af\:304c\:9ad8\:3044\:3002 *)
ClearAll[iCheckRetryGuards];
iCheckRetryGuards[code_String] :=
  Module[{transBlocks, retryBlocks, issues = {}, hasGiveUp},
    transBlocks = StringCases[code,
      "WorkflowTransition[\"" ~~ name:LetterCharacter.. ~~ "\"" ~~
      blk:Shortest[___] ~~ "]," :>
        <|"Name" -> name, "Block" -> blk|>];
    
    (* "Retry" / "Loop" \:30d1\:30bf\:30fc\:30f3\:540d\:3092\:6301\:3064 transition \:3092\:62bd\:51fa *)
    retryBlocks = Select[transBlocks,
      StringContainsQ[#[["Name"]], "Retry"|"Loop"|"Repeat"|"Iterate"] &];
    
    Map[
      Function[t,
        Module[{blk, hasTrial, hasGuard, hasComparison},
          blk = t[["Block"]];
          hasGuard = StringContainsQ[blk, "\"Guard\""];
          hasTrial = StringContainsQ[blk, "Trial"|"trial"|"Count"|"Attempt"|"Iteration"];
          hasComparison = StringContainsQ[blk, "<"|">"|"=="];
          If[!hasGuard,
            AppendTo[issues, t[["Name"]] <> ": no Guard (infinite loop risk)"]];
          If[hasGuard && (!hasTrial || !hasComparison),
            AppendTo[issues, t[["Name"]] <>
              ": Guard does not check Trial counter (infinite loop risk)"]]
        ]],
      retryBlocks];
    
    (* \"GiveUp\" / \"Abort\" \:7b49\:306e\:7d42\:4e86 transition \:304c\:5b58\:5728\:3059\:308b\:304b *)
    hasGiveUp = AnyTrue[transBlocks,
      StringContainsQ[#[["Name"]], "GiveUp"|"Abort"|"Stop"|"Bail"] &];
    If[Length[retryBlocks] > 0 && !hasGiveUp,
      AppendTo[issues, "no GiveUp transition (no escape from retry loop)"]];
    
    issues
  ];
iCheckRetryGuards[_] := {};

(* handler \:5185\:306e binding[[place, key]] \:3067 key !== \"Payload\" \:306a access \:3092\:691c\:51fa\:3002
   binding[[place, "X"]] \:306f token \:30ec\:30d9\:30eb\:3067\:306f\:306a\:304f\:3001
   binding[[place, "Payload", "X"]] \:3067\:306a\:3051\:308c\:3070 Missing \:3092\:8fd4\:3059\:3002 *)
ClearAll[iCheckPayloadAccess];
iCheckPayloadAccess[code_String] :=
  Module[{badAccesses},
    (* \:30d1\:30bf\:30fc\:30f3 binding[[\"X\", \"Y\"]] \:3067 Y \:304c \"Payload\" \:3067\:306a\:3044\:30b1\:30fc\:30b9 *)
    badAccesses = StringCases[code,
      "binding[[\"" ~~ place:LetterCharacter.. ~~ "\"," ~~ Whitespace... ~~
      "\"" ~~ key:LetterCharacter.. ~~ "\"" :>
        If[!MemberQ[{"Payload", "Kind", "TokenId", "ParentIds",
                     "CreatedBy", "CreatedAt"}, key],
          place <> "->\"" <> key <> "\"",
          ""]];
    DeleteCases[badAccesses, ""]
  ];
iCheckPayloadAccess[_] := {};

(* ::Subsection:: *)
(* 3. \:30b3\:30fc\:30c9\:751f\:6210 *)

ClearAll[proposePetriNet, reviewPetriProposal];

(* \:5185\:90e8\:30d8\:30eb\:30d1\:30fc: \:4e00\:56de\:751f\:6210\:3057\:3066 proposal Association \:3092\:8fd4\:3059\:3002
   feedback \:6587\:5b57\:5217\:3092\:8ffd\:52a0 prompt \:3068\:3057\:3066\:6e21\:305b\:308b\:3088\:3046\:306b\:3057\:3066\:3001
   \:518d\:8a66\:884c\:6642\:306b\:300c\:3053\:3053\:304c\:60aa\:304b\:3063\:305f\:300d\:3068 LLM \:306b\:6307\:6458\:3067\:304d\:308b\:3002 *)
ClearAll[iProposeOnce];
iProposeOnce[goal_String, feedback_String] :=
  Module[{prompt, response, code, builder, forbidden, truncated, hasOpen, hasClose,
          sharedInputs, duplicated, retryIssues, payloadIssues, isErrorResp},
    prompt = $petriNetGuide <>
             "\n\n# User goal\n\n" <> goal <>
             If[feedback === "",
                "\n\nGenerate the code block now.",
                "\n\n# Previous attempt feedback (FIX THESE ISSUES)\n\n" <>
                feedback <>
                "\n\nRegenerate the code, fixing the above issues."];
    (* v0.10.1 (Phase 27): Fallback -> True \:3092\:524a\:9664\:3002
       \:8a02\:6b63\:524d\:306f\:8ab2\:91d1 API \:7d4c\:8def (Anthropic API \:76f4) \:3092\:4f7f\:3063\:3066\:3044\:305f\:304c\:3001
       Imai \:5148\:751f\:306e\:8a2d\:8a08 (NBAccess \:304c absolute truth) \:3067\:306f\:8ab2\:91d1 API \:30c7\:30d5\:30a9\:30eb\:30c8\:7981\:6b62\:3068\:306a\:308a\:3001
       proposePetriNet \:304c\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:3092\:958b\:3044\:305f\:76f4\:5f8c\:306b\:4f7f\:3048\:306a\:304f\:306a\:3063\:3066\:3057\:307e\:3046\:3002
       \:30b3\:30fc\:30c9\:751f\:6210\:30bf\:30b9\:30af\:306f Claude Code CLI (\:8ab2\:91d1\:306a\:3057) \:3067\:5341\:5206\:306a\:306e\:3067\:3001
       \:30c7\:30d5\:30a9\:30eb\:30c8\:3067 CLI \:7d4c\:8def\:306b\:3057\:3066\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:8a2d\:5b9a\:3068\:72ec\:7acb\:306b\:52d5\:304f\:3088\:3046\:306b\:3059\:308b\:3002 *)
    response = Quiet @ Check[
      ClaudeCode`ClaudeQueryBg[prompt],
      ""];
    
    (* v0.10.1: LLM \:304c API \:30a8\:30e9\:30fc\:5fdc\:7b54\:3092\:8fd4\:3057\:305f\:5834\:5408\:306f\:30e6\:30fc\:30b6\:306b\:660e\:793a\:8868\:793a\:3002
       \:3053\:308c\:304c\:306a\:3044\:3068\:3001response = "Error: ..." \:304c\:30b3\:30fc\:30c9\:62bd\:51fa\:306b\:6d41\:308c\:3066
       code = "" \:306e\:307e\:307e\:9762\:500d\:304f parsePetriCode[""] \:3068\:306a\:308a\:3001
       \:4f55\:304c\:8d77\:304d\:305f\:304b\:30e6\:30fc\:30b6\:306b\:898b\:3048\:306a\:304f\:306a\:308b\:3002 *)
    isErrorResp = StringQ[response] && StringLength[response] > 0 &&
      (StringStartsQ[response, "Error:"] || StringStartsQ[response, "Error "] ||
       StringStartsQ[response, "[Error"] || StringStartsQ[response, "[ClaudeQuery"] ||
       StringStartsQ[response, "[ClaudeQueryBg"]);
    If[isErrorResp,
      Print[Style["[iProposeOnce] LLM \:547c\:3073\:51fa\:3057\:304c\:30a8\:30e9\:30fc\:5fdc\:7b54\:3092\:8fd4\:3057\:307e\:3057\:305f:", Red, Bold]];
      Print[Style["  " <> StringTake[response, UpTo[400]], Orange]];
      Print[Style["  \:4ee5\:4e0b\:3001\:30b3\:30fc\:30c9\:62bd\:51fa\:3092\:8a66\:307f\:308b\:304c \"Code\" -> \"\" \:3067\:8fd4\:308b\:53ef\:80fd\:6027\:304c\:9ad8\:3044\:3067\:3059\:3002", Gray]]];
    
    code = iExtractCodeBlock[response];
    builder = iFindBuilderName[code];
    forbidden = iCheckForbiddenAPIs[code];
    sharedInputs = iCheckSharedInputPlaces[code];
    duplicated = iCheckDuplicatedTransitions[code];
    retryIssues = iCheckRetryGuards[code];
    payloadIssues = iCheckPayloadAccess[code];
    
    hasOpen  = StringContainsQ[response, "```"];
    hasClose = If[hasOpen,
      Length[StringPosition[response, "```"]] >= 2, False];
    truncated = hasOpen && !hasClose;
    
    <|"Goal"                   -> goal,
      "Code"                   -> code,
      "BuilderName"            -> builder,
      "ForbiddenFound"         -> forbidden,
      "SharedInputPlaces"      -> sharedInputs,
      "DuplicatedTransitions"  -> duplicated,
      "RetryGuardIssues"       -> retryIssues,
      "PayloadAccessIssues"    -> payloadIssues,
      "Truncated"              -> truncated,
      "IsErrorResponse"        -> isErrorResp,
      "ResponseLength"         -> StringLength[response],
      "CodeLength"             -> StringLength[code],
      "RawResponse"            -> response|>
  ];

(* proposal \:306b\:5bfe\:3057\:3066 LLM \:306b\:6307\:6458\:3059\:3079\:304d\:554f\:984c\:3092 feedback \:6587\:5b57\:5217\:306b\:307e\:3068\:3081\:308b *)
ClearAll[iBuildFeedback];
iBuildFeedback[proposal_Association] :=
  Module[{issues = {}},
    If[proposal[["Code"]] === "",
      AppendTo[issues, "- No code block extracted from your reply."]];
    If[proposal[["Truncated"]],
      AppendTo[issues,
        "- Your previous reply was truncated (no closing ```). Be more compact."]];
    If[proposal[["BuilderName"]] === "" && proposal[["Code"]] =!= "",
      AppendTo[issues,
        "- No buildXxx[] := WorkflowNet[...] definition found."]];
    If[Length[proposal[["ForbiddenFound"]]] > 0,
      AppendTo[issues,
        "- Forbidden APIs detected: " <>
        StringRiffle[proposal[["ForbiddenFound"]], ", "] <>
        ". Remove all execution code (only definitions allowed)."]];
    If[Length[proposal[["SharedInputPlaces"]]] > 0,
      AppendTo[issues,
        "- TRAP #3: Multiple transitions share the SAME InputArc Place: " <>
        StringRiffle[proposal[["SharedInputPlaces"]], ", "] <>
        ". This is the most critical bug. Fix: give EACH parallel worker its " <>
        "OWN dedicated input Place. For 3 workers, you need 3 distinct " <>
        "Places (e.g. PoolA, PoolB, PoolC), and Distribute should output to " <>
        "all 3, while WorkerA reads from PoolA only, WorkerB from PoolB only, " <>
        "etc. Do NOT have WorkerA, WorkerB, WorkerC all reading from the same Place."]];
    If[Length[proposal[["DuplicatedTransitions"]]] > 0,
      AppendTo[issues,
        "- DUPLICATED TRANSITIONS: " <>
        StringRiffle[proposal[["DuplicatedTransitions"]], ", "] <>
        ". You duplicated transitions for retry/repair (e.g. RetryA when " <>
        "WorkerA already exists). Use a FEEDBACK LOOP instead: have the " <>
        "Retry transition route the token back to the SAME upstream Place " <>
        "that feeds the original WorkerA. The Plan place must have Capacity 1, " <>
        "and the Retry transition's Guard must check trial < MaxTrials. " <>
        "This reduces node count and makes the structure scalable."]];
    If[Length[proposal[["RetryGuardIssues"]]] > 0,
      AppendTo[issues,
        "- INFINITE LOOP RISK in retry transitions: " <>
        StringRiffle[proposal[["RetryGuardIssues"]], "; "] <>
        ". CRITICAL: Each Retry/Loop transition MUST have a Guard like " <>
        "Function[b, b[[\"Verdict\", \"Payload\", \"Trial\"]] < 3]. " <>
        "Also include a separate GiveUp transition with Guard checking " <>
        "Trial >= MaxTrials, going to a GivenUp final place. " <>
        "Without these, an infinite loop will burn through token budget."]];
    If[Length[proposal[["PayloadAccessIssues"]]] > 0,
      AppendTo[issues,
        "- WRONG Payload access pattern: " <>
        StringRiffle[Take[proposal[["PayloadAccessIssues"]],
                          Min[5, Length[proposal[["PayloadAccessIssues"]]]]], "; "] <>
        ". You accessed binding[[place, key]] where key is not \"Payload\". " <>
        "This returns Missing[KeyAbsent, key] because token is " <>
        "<|TokenId, Kind, Payload, ...|>. To read token data, ALWAYS use " <>
        "binding[[place, \"Payload\", key]] or " <>
        "Lookup[binding[[place, \"Payload\"]], key, default]. " <>
        "Wrong access causes handler to return $Failed (Status: Failed) " <>
        "and downstream Stuck."]];
    StringRiffle[issues, "\n"]
  ];

(* \:7570\:5e38\:5224\:5b9a: \:6539\:5584\:304c\:5fc5\:8981\:304b *)
ClearAll[iIsProposalBad];
iIsProposalBad[proposal_Association] :=
  Or[
    proposal[["Code"]] === "",
    proposal[["Truncated"]],
    proposal[["BuilderName"]] === "" && proposal[["Code"]] =!= "",
    Length[proposal[["ForbiddenFound"]]] > 0,
    Length[proposal[["SharedInputPlaces"]]] > 0,
    Length[proposal[["DuplicatedTransitions"]]] > 0,
    Length[proposal[["RetryGuardIssues"]]] > 0,
    Length[proposal[["PayloadAccessIssues"]]] > 0
  ];

(* v0.10.0 \:7d71\:5408\:7248 proposePetriNet:
   \:65e7 proposePetriNet (single-provider) + \:65e7 proposePetriNetWithProvider \:3092 1 \:3064\:306e\:95a2\:6570\:306b\:7d71\:5408\:3002

   Options:
     "Providers"        -> {} | {"anthropic", "openai", ...}
                           \:7a7a\:30ea\:30b9\:30c8 (default) \:306a\:3089 single-provider mode
                           (\:65e7 proposePetriNet \:3068\:540c\:3058\:52d5\:4f5c)\:3002
                           \:975e\:7a7a\:306a\:3089 multi-provider mode (\:65e7 proposePetriNetWithProvider)\:3002
     "InputPayloadKeys" -> {"Text"}
                           Source token Payload \:306e\:671f\:5f85\:30ad\:30fc (multi-provider \:6642\:306b prompt \:3078\:8ffd\:52a0)
     "MaxRetries"       -> 2 | 3
                           feedback \:30ea\:30c8\:30e9\:30a4\:56de\:6570
     "Verbose"          -> True
*)

Options[proposePetriNet] = {
  "Providers" -> {},
  "InputPayloadKeys" -> {"Text"},
  "MaxRetries" -> 2,
  "Verbose" -> True
};

ClearAll[iProposeMulti];

(* multi-provider mode \:306e\:30ed\:30b8\:30c3\:30af:
   $petriNetGuide \:306b $petriNetGuideExtras \:3092\:4e00\:6642\:8ffd\:52a0\:3057\:3001
   goal \:306b provider \:5ba3\:8a00 / input key \:5ba3\:8a00\:3092\:3064\:3051\:3066\:304b\:3089
   single-provider proposePetriNet \:3092\:547c\:3076\:3002\:9759\:7684\:691c\:67fb retry \:3082\:542b\:3080\:3002 *)
iProposeMulti[goal_String, providers_List, inputKeys_List,
              maxRetries_Integer, verbose_] :=
  Module[{augmentedGoal, savedGuide, result,
          providerSection, inputKeySection, whIssues,
          attempt, extraFeedback},
    (* Provider \:6307\:5b9a\:6cd5\:3092 $petriNetGuide \:306b\:4e00\:6642\:7684\:306b\:8ffd\:8a18 *)
    savedGuide = If[ValueQ[$petriNetGuide], $petriNetGuide, ""];
    If[StringQ[savedGuide] && ValueQ[$petriNetGuideExtras] &&
       StringQ[$petriNetGuideExtras] &&
       !StringContainsQ[savedGuide, "# Provider selection for LLM calls"],
      $petriNetGuide = savedGuide <> "\n\n" <> $petriNetGuideExtras];

    (* goal \:306b\:30d7\:30ed\:30d0\:30a4\:30c0\:5ba3\:8a00\:3068 input key \:5ba3\:8a00\:3092\:52a0\:3048\:308b *)
    providerSection = If[Length[providers] > 0,
      "\n\n# Required providers\n" <>
      "Use these LLM providers (each must be invoked via " <>
      "ClaudeCode`ClaudeQueryBg with Model option):\n  " <>
      StringRiffle[Map["- " <> # &, providers], "\n  "] <>
      "\n\nEach parallel worker MUST specify a different provider via Model option.",
      ""];

    inputKeySection = If[Length[inputKeys] > 0,
      "\n\n# Source token Payload keys\n" <>
      "The user-submitted Source token's Payload contains EXACTLY these keys:\n  " <>
      StringRiffle[Map["- \"" <> # <> "\"" &, inputKeys], "\n  "] <>
      "\nThe FIRST worker(s) MUST read input via Lookup with one of these keys, " <>
      "NOT \"Plan\" or any other key.",
      ""];

    augmentedGoal = goal <> providerSection <> inputKeySection;

    (* === Outer retry loop: \:9759\:7684\:691c\:67fb\:304c\:5931\:6557\:3057\:305f\:3089\:8ffd\:52a0 feedback \:3092\:4ed8\:3051\:3066\:518d\:751f\:6210 === *)
    extraFeedback = "";
    result = Null;
    whIssues = {};

    Do[
      If[verbose && attempt > 1,
        Print[Style["[proposePetriNet] " <>
          "\:9759\:7684\:691c\:67fb\:30ea\:30c8\:30e9\:30a4 " <> ToString[attempt] <> "/" <> ToString[maxRetries + 1] <>
          " (\:524d\:56de\:554f\:984c\:6570: " <> ToString[Length[whIssues]] <> ")",
          Orange]]];

      (* iProposeOnce \:3092\:4f7f\:3046 single-shot \:751f\:6210 (\:672c\:4f53 retry \:3092\:305b\:305a 1 \:56de\:3060\:3051) *)
      result = iProposeOnce[augmentedGoal <> extraFeedback, ""];

      If[!AssociationQ[result],
        Break[]];

      whIssues = If[ValueQ[iCheckWorkerHandlerIssues],
        iCheckWorkerHandlerIssues[Lookup[result, "Code", ""]],
        {}];

      If[Length[whIssues] === 0, Break[]];

      (* \:6b21\:56de\:30d7\:30ed\:30f3\:30d7\:30c8\:7528 feedback \:3092\:69cb\:7bc9 *)
      extraFeedback = "\n\n# Static check feedback from previous attempt (FIX THESE)\n" <>
        StringRiffle[Map["- " <> # &, whIssues], "\n"] <>
        "\n\nThese are static checks on your generated code. " <>
        "Re-read the Worker handler I/O convention, especially the Self-check trace, " <>
        "and emit corrected code."
      ,
      {attempt, 1, maxRetries + 1}
    ];

    (* $petriNetGuide \:3092\:5143\:306b\:623b\:3059 (\:526f\:4f5c\:7528\:6700\:5c0f\:5316) *)
    $petriNetGuide = savedGuide;

    (* result \:304c Association \:3067\:8fd4\:3063\:305f\:304b\:78ba\:8a8d *)
    If[!AssociationQ[result],
      Print[Style["[proposePetriNet] iProposeOnce \:304c " <>
        "Association \:3092\:8fd4\:3057\:307e\:305b\:3093\:3067\:3057\:305f (Head: " <> ToString[Head[result]] <> ")\:3002",
        Red, Bold]];
      Return[<|"Error" -> "ProposeOnceReturnedNonAssoc",
               "ResultHead" -> Head[result]|>]];

    If[Length[whIssues] > 0 && verbose,
      Print[Style["[proposePetriNet] \:9759\:7684\:691c\:67fb\:30ea\:30c8\:30e9\:30a4\:5f8c\:3082\:6b8b\:3063\:305f\:8b66\:544a:",
        Bold, Orange]];
      Scan[Print["  ", #] &, whIssues]];

    Append[Append[Append[result,
      "ProvidersRequested" -> providers],
      "InputPayloadKeys" -> inputKeys],
      "WorkerHandlerIssues" -> whIssues]
  ];

(* LLM \:306b\:30b3\:30fc\:30c9\:3092\:751f\:6210\:3055\:305b\:308b\:3002
   \:7f60\:691c\:51fa\:6642\:306f\:30d5\:30a3\:30fc\:30c9\:30d0\:30c3\:30af\:4ed8\:304d\:3067\:6700\:5927 MaxRetries \:56de\:518d\:8a66\:884c\:3002
   \:6700\:7d42\:7684\:306a proposal \:3092\:8fd4\:3059 (\:5168\:8a66\:884c\:5c65\:6b74\:3092 "Attempts" \:30ad\:30fc\:306b\:683c\:7d0d) *)
proposePetriNet[goal_String, opts:OptionsPattern[]] :=
  Module[{providers, inputKeys, maxRetries, verbose,
          attempts, proposal, feedback, attempt},
    providers  = OptionValue["Providers"];
    inputKeys  = OptionValue["InputPayloadKeys"];
    maxRetries = OptionValue["MaxRetries"];
    verbose    = OptionValue["Verbose"];

    (* multi-provider mode (Providers \:304c\:975e\:7a7a) \:306f iProposeMulti \:306b\:59d4\:8b72 *)
    If[Length[providers] > 0,
      Return[iProposeMulti[goal, providers, inputKeys, maxRetries, verbose]]];

    (* single-provider mode (\:65e7 proposePetriNet \:3068\:540c\:3058\:52d5\:4f5c) *)
    attempts = {};
    feedback = "";

    (* \:521d\:56de + \:6700\:5927 maxRetries \:56de\:306e\:30ea\:30c8\:30e9\:30a4 *)
    Do[
      If[verbose && attempt > 1,
        Print[Style["[proposePetriNet] \:518d\:751f\:6210\:8a66\:884c " <>
          ToString[attempt] <> "/" <> ToString[maxRetries + 1] <>
          " (\:524d\:56de\:554f\:984c: " <> StringTake[feedback, Min[80, StringLength[feedback]]] <> "...)",
          Orange]]];
      proposal = iProposeOnce[goal, feedback];
      AppendTo[attempts, proposal];

      If[!iIsProposalBad[proposal], Break[]];

      feedback = iBuildFeedback[proposal];
      ,
      {attempt, 1, maxRetries + 1}
    ];

    Append[proposal, "Attempts" -> Length[attempts]]
  ];

(* \:65e7 proposePetriNetWithProvider \:306f proposePetriNet \:306b\:7d71\:5408\:3055\:308c\:305f\:3002
   \:4e92\:63db\:6027\:306e\:305f\:3081\:306e\:30b5\:30dd\:30fc\:30c8 stub \:3092\:8a2d\:3051\:308b: *)
ClearAll[proposePetriNetWithProvider];
proposePetriNetWithProvider::deprecated =
  "proposePetriNetWithProvider \:306f\:5ec3\:6b62\:3055\:308c\:307e\:3057\:305f\:3002proposePetriNet[goal, \"Providers\" -> {...}] \:3092\:4f7f\:7528\:3057\:3066\:304f\:3060\:3055\:3044\:3002";
proposePetriNetWithProvider[goal_String, opts:OptionsPattern[proposePetriNet]] :=
  (Message[proposePetriNetWithProvider::deprecated];
   proposePetriNet[goal, opts]);

(* \:30ec\:30d3\:30e5\:30fc\:8868\:793a *)
reviewPetriProposal[goal_String] :=
  Module[{proposal, code, builder, forbidden, sharedInputs, status},
    proposal = proposePetriNet[goal];
    code     = proposal[["Code"]];
    builder  = proposal[["BuilderName"]];
    forbidden = proposal[["ForbiddenFound"]];
    sharedInputs = proposal[["SharedInputPlaces"]];
    status = Which[
      code === "",       Style["[\:30a8\:30e9\:30fc] \:30b3\:30fc\:30c9\:30d6\:30ed\:30c3\:30af\:304c\:62bd\:51fa\:3067\:304d\:307e\:305b\:3093\:3067\:3057\:305f", Red, Bold],
      proposal[["Truncated"]],
        Style["[\:8b66\:544a] LLM \:5fdc\:7b54\:304c\:9014\:4e2d\:3067\:5207\:308c\:3066\:3044\:307e\:3059 (\:9589\:3058 ``` \:7121\:3057)", Orange, Bold],
      builder === "",    Style["[\:30a8\:30e9\:30fc] buildXxx[] \:5b9a\:7fa9\:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093", Red, Bold],
      Length[forbidden] > 0,
        Style["[\:8b66\:544a] \:7981\:6b62 API \:304c\:542b\:307e\:308c\:3066\:3044\:307e\:3059: " <>
              StringRiffle[forbidden, ", "], Orange, Bold],
      Length[sharedInputs] > 0,
        Style["[\:8b66\:544a] \:7f60 #3: \:5171\:6709\:5165\:529b Place \:691c\:51fa: " <>
              StringRiffle[sharedInputs, ", "] <>
              " (1 worker \:304c\:5168 token \:3092\:5360\:6709\:3057 Stuck \:3059\:308b\:5371\:967a\:6027)", Orange, Bold],
      True, Style["[OK] \:30b3\:30fc\:30c9\:3082\:95a2\:6570\:5b9a\:7fa9\:3082\:691c\:51fa\:3055\:308c\:307e\:3057\:305f", Darker[Green], Bold]];
    Column[{
      Style["Goal:", Bold], goal, "",
      Style["Status:", Bold], status, "",
      Row[{Style["BuilderName: ", Bold], builder}],
      Row[{Style["SharedInputPlaces: ", Bold],
           If[Length[sharedInputs] === 0, "(none)",
             StringRiffle[sharedInputs, ", "]]}],
      Row[{Style["ResponseLen: ", Bold], proposal[["ResponseLength"]],
           "  ", Style["CodeLen: ", Bold], proposal[["CodeLength"]]}],
      "",
      Style["Generated code:", Bold],
      Style[code, FontFamily -> "Courier", FontSize -> 11]
    }, Frame -> All]
  ];

(* ::Subsection:: *)
(* 4. \:30b3\:30fc\:30c9\:8a55\:4fa1 *)

ClearAll[parsePetriCode];

(* v0.10.0 \:7d71\:5408\:7248: \:7f60 #16 \:4fee\:6b63 + fallback \:7d4c\:8def\:8ffd\:52a0
   - Quiet@Check[expr, $Failed] \:3092\:4f7f\:308f\:305a Quiet[expr] \:306e\:307f (\:7f60 #16 \:56de\:907f)
   - ToExpression \:306e\:30a8\:30e9\:30fc\:8a73\:7d30\:3092\:8868\:793a
   - builder[] \:4e0d\:5728\:3001\:307e\:305f\:306f builder[] \:304c Association \:3092\:8fd4\:3055\:306a\:3044\:5834\:5408\:3001
     \:30b3\:30fc\:30c9\:672b\:5c3e\:306e WorkflowNet[...] \:5f0f\:3092\:76f4\:63a5\:8a55\:4fa1\:3059\:308b fallback (ChatGPT 5.5 \:7b49\:304c\:76f4\:66f8\:304d\:3059\:308b\:5834\:5408\:306b\:5bfe\:5fdc) *)
parsePetriCode[code_String] :=
  Module[{forbidden, builder, evalResult, net, evalMessages,
          fallbackNet},

    If[code === "" || code === $Failed,
      Print[Style["[parsePetriCode] \:30b3\:30fc\:30c9\:304c\:7a7a\:3067\:3059", Red]];
      Return[$Failed]];

    (* \:7981\:6b62 API \:30c1\:30a7\:30c3\:30af (\:672c\:4f53\:3068\:540c\:4e00) *)
    forbidden = iCheckForbiddenAPIs[code];
    If[Length[forbidden] > 0,
      Print[Style["[parsePetriCode] \:7981\:6b62 API \:304c\:542b\:307e\:308c\:3066\:3044\:307e\:3059: " <>
                  StringRiffle[forbidden, ", "], Red]];
      Print[Style["LLM \:304c\:6307\:793a\:306b\:53cd\:3057\:3066\:5b9f\:884c\:30b3\:30fc\:30c9\:3092\:751f\:6210\:3057\:305f\:53ef\:80fd\:6027\:3002 reviewPetriProposal \:3067\:78ba\:8a8d\:3057\:3066\:4e0b\:3055\:3044\:3002",
        Orange]];
      Return[$Failed]];

    (* builder \:540d\:62bd\:51fa *)
    builder = iFindBuilderName[code];

    (* \:7f60 #16 \:4fee\:6b63: Quiet@Check[expr, $Failed] \:306f\:4f7f\:308f\:306a\:3044\:3002
       Quiet[expr] \:306e\:307f\:4f7f\:7528\:3057\:3001ToExpression \:306e\:30e1\:30c3\:30bb\:30fc\:30b8\:3067 $Failed \:304c\:51fa\:305f\:304b\:306f
       \:623b\:308a\:5024\:3067\:5224\:5b9a\:3059\:308b\:3002 *)
    evalMessages = {};
    evalResult = Block[{$MessageList = {}},
      Quiet[
        Module[{r},
          r = ToExpression[code, InputForm];
          evalMessages = $MessageList;
          r
        ]
      ]
    ];

    If[evalResult === $Failed,
      Print[Style["[parsePetriCode] \:30b3\:30fc\:30c9\:8a55\:4fa1\:306b\:5931\:6557 (ToExpression returned $Failed)", Red]];
      Print[Style["\:30b3\:30fc\:30c9\:9577: " <> ToString[StringLength[code]] <> " chars", Orange]];
      If[Length[evalMessages] > 0,
        Print[Style["\:8a55\:4fa1\:4e2d\:306e\:30e1\:30c3\:30bb\:30fc\:30b8:", Orange]];
        Scan[Print["  ", #] &, Take[evalMessages, UpTo[5]]]
      ];
      Print[Style["\:6700\:521d\:306e 200 chars:", Orange]];
      Print[StringTake[code, Min[200, StringLength[code]]]];
      Print[Style["\:6700\:5f8c\:306e 200 chars:", Orange]];
      Print[StringTake[code, -Min[200, StringLength[code]]]];
      Print[Style["\:30c7\:30d0\:30c3\:30b0\:7528: ToExpression \:30a8\:30e9\:30fc\:8a73\:7d30\:3092\:78ba\:8a8d\:3059\:308b\:306b\:306f " <>
                  "ToExpression[code] \:3092\:76f4\:63a5\:5b9f\:884c", Italic, Gray]];
      Return[$Failed]];

    (* builder \:304c\:898b\:3064\:304b\:3063\:305f\:3089\:547c\:3076\:3002fallback \:3068\:3057\:3066:
       - builder == "" \:306e\:3068\:304d \:2192 \:30b3\:30fc\:30c9\:5185\:306e WorkflowNet[...] \:5f0f\:3092\:63a2\:3059
       - builder[] \:547c\:3073\:51fa\:3057\:304c Association \:3092\:8fd4\:3055\:306a\:304b\:3063\:305f\:3068\:304d \:2192 \:540c\:3058 fallback *)

    If[builder =!= "",
      (* Quiet[expr] \:306e\:307f\:3067\:7f60 #16 \:3092\:56de\:907f *)
      net = Quiet[
        ToExpression[builder <> "[]"]
      ];

      If[net === $Failed || !AssociationQ[net] ||
         !KeyExistsQ[net, "FormatVersion"] ||
         !KeyExistsQ[net, "Places"] ||
         !KeyExistsQ[net, "Transitions"] ||
         !KeyExistsQ[net, "SourcePlace"],
        (* Builder \:7d4c\:8def\:304c\:6a5f\:80fd\:3057\:306a\:304b\:3063\:305f\:306e\:3067 fallback \:3092\:8a66\:3059 *)
        net = $Failed
      ];

      If[AssociationQ[net], Return[net]]
    ];

    (* Fallback: \:30b3\:30fc\:30c9\:6587\:5b57\:5217\:5185\:306e WorkflowNet[...] \:5f0f\:3092\:76f4\:63a5\:8a55\:4fa1 *)
    fallbackNet = iEvalLastWorkflowNetExpr[code];

    If[AssociationQ[fallbackNet] &&
       KeyExistsQ[fallbackNet, "FormatVersion"] &&
       KeyExistsQ[fallbackNet, "Places"] &&
       KeyExistsQ[fallbackNet, "Transitions"] &&
       KeyExistsQ[fallbackNet, "SourcePlace"],
      Print[Style["[parsePetriCode] builder \:7d4c\:7531\:5931\:6557\:3002\:30b3\:30fc\:30c9\:672b\:5c3e\:306e WorkflowNet[...] \:5f0f\:3092\:76f4\:63a5\:8a55\:4fa1\:3057\:3066\:6210\:529f (fallback)\:3002",
        Darker[Yellow]]];
      Return[fallbackNet]
    ];

    (* \:3069\:3061\:3089\:3082\:5931\:6557 *)
    If[builder === "",
      Print[Style["[parsePetriCode] buildXxx[] \:5b9a\:7fa9\:3082\:72ec\:7acb WorkflowNet[...] \:5f0f\:3082\:898b\:3064\:304b\:308a\:307e\:305b\:3093",
        Red]],
      Print[Style["[parsePetriCode] " <> builder <>
                  "[] \:306f WorkflowNet Association \:3092\:8fd4\:3055\:306a\:304b\:3063\:305f (fallback \:3082\:5931\:6557)", Red]];
      Print[Style["\:8fd4\:3063\:305f Head: " <> ToString[Head[net]], Orange]]];
    $Failed
  ];
parsePetriCode[_] := $Failed;

(* ============================================================
   helper: \:30b3\:30fc\:30c9\:6587\:5b57\:5217\:304b\:3089\:6700\:5f8c\:306e WorkflowNet[...] \:5f0f\:3092\:8a55\:4fa1\:3059\:308b
     - \:95a2\:6570\:5b9a\:7fa9 (`:=`) \:304c\:4e26\:3076\:30b3\:30fc\:30c9\:3092 Get \:98a8\:306b\:8a55\:4fa1\:3057\:5b9a\:7fa9\:3092\:30ed\:30fc\:30c9\:3057\:305f\:4e0a\:3067\:3001
       \:30b3\:30fc\:30c9\:672b\:5c3e\:306e WorkflowNet[...] \:5f0f\:3092\:6700\:7d42\:7d50\:679c\:3068\:3057\:3066\:53d6\:308a\:51fa\:3059\:3002
   ============================================================ *)

ClearAll[iEvalLastWorkflowNetExpr];
iEvalLastWorkflowNetExpr[code_String] :=
  Module[{result},
    (* ToExpression \:306f\:8907\:6570\:5f0f\:5217\:3092 CompoundExpression \:3068\:3057\:3066\:8a55\:4fa1\:3057\:3001
       \:6700\:5f8c\:306e\:5f0f\:306e\:5024\:3092\:8fd4\:3059\:3002definitions (Set/SetDelayed) \:306f Null \:3092\:8fd4\:3059\:304c\:3001
       \:30b3\:30fc\:30c9\:672b\:5c3e\:304c WorkflowNet[...] \:3068\:3044\:3046 Association \:306a\:3089\:305d\:306e\:5024\:304c\:8fd4\:308b\:3002 *)
    result = Quiet[
      ToExpression[code, InputForm]
    ];
    Which[
      AssociationQ[result], result,
      Head[result] === ClaudeOrchestrator`Workflow`WorkflowNet,
      (* WorkflowNet[opts...] \:5f62\:306e\:30d8\:30c3\:30c9\:4ed8\:304d\:3067\:8fd4\:3063\:3066\:304d\:305f\:5834\:5408\:3001
         \:672c\:4f53\:5074\:306e WorkflowNet[opts] -> Association \:8a55\:4fa1\:3092\:5f37\:5236\:3059\:308b *)
      Quiet[ReleaseHold[Hold[Evaluate][result]]],
      True, $Failed
    ]
  ];
iEvalLastWorkflowNetExpr[_] := $Failed;

(* ::Subsection:: *)
(* 5. \:5b9f\:884c\:7d71\:5408 *)

ClearAll[runPetriFromPrompt, summarizePromptPetri];

Options[runPetriFromPrompt] = {
  "InitialToken" -> Automatic,
  "MaxSteps"     -> 30,
  "MaxStepsHardLimit" -> 60,
  "Async"        -> True
};

runPetriFromPrompt[goal_String, opts:OptionsPattern[]] :=
  Module[{proposal, net, wid, initToken, runResult, maxSteps, hardLimit,
          effectiveMaxSteps},
    proposal = proposePetriNet[goal];
    
    (* \:8fd4\:308a\:5024\:306b\:30c7\:30d0\:30c3\:30b0\:60c5\:5831\:3092\:542b\:3081\:308b *)
    If[proposal[["Code"]] === "",
      Return[<|"Status"      -> "ProposalEmpty",
               "Goal"        -> goal,
               "RawResponse" -> proposal[["RawResponse"]]|>]];
    
    net = parsePetriCode[proposal[["Code"]]];
    
    If[net === $Failed,
      Return[<|"Status"         -> "ParseFailed",
               "Goal"           -> goal,
               "Code"           -> proposal[["Code"]],
               "BuilderName"    -> proposal[["BuilderName"]],
               "ForbiddenFound" -> proposal[["ForbiddenFound"]],
               "RawResponse"    -> proposal[["RawResponse"]]|>]];
    
    wid = ClaudeCreateWorkflowNet[net,
      "Description" -> "from prompt: " <> StringTake[goal, Min[80, StringLength[goal]]]];
    
    initToken = OptionValue["InitialToken"];
    If[initToken === Automatic,
      initToken = WorkflowToken["Kind" -> "Task",
        "Payload" -> <|"Goal" -> goal, "Trial" -> 1|>]];
    
    ClaudeSubmitToken[wid, initToken];
    
    (* MaxSteps \:306f hard limit \:3092\:8d85\:3048\:306a\:3044\:3088\:3046\:30af\:30ea\:30c3\:30d7 *)
    maxSteps = OptionValue["MaxSteps"];
    hardLimit = OptionValue["MaxStepsHardLimit"];
    effectiveMaxSteps = Min[maxSteps, hardLimit];
    If[maxSteps > hardLimit,
      Print[Style["[runPetriFromPrompt] MaxSteps=" <> ToString[maxSteps] <>
                  " \:306f hard limit " <> ToString[hardLimit] <>
                  " \:3092\:8d85\:3048\:308b\:305f\:3081\:30af\:30ea\:30c3\:30d7\:3057\:305f\:3002 " <>
                  "token \:904e\:5270\:6d88\:8cbb\:9632\:6b62\:306e\:305f\:3081\:3002", Orange]]];
    
    runResult = ClaudeRunWorkflow[wid,
      "MaxSteps" -> effectiveMaxSteps,
      "Async"    -> OptionValue["Async"]];
    
    <|"Status"      -> Lookup[runResult, "Status",
                              Lookup[runResult, "TerminationReason", "?"]],
      "WorkflowId"  -> wid,
      "Goal"        -> goal,
      "Code"        -> proposal[["Code"]],
      "Net"         -> net,
      "RunResult"   -> runResult|>
  ];

summarizePromptPetri[goal_String, opts:OptionsPattern[ClaudeWaitWorkflow]] :=
  Module[{startInfo, wid, waitResult, finalState, trace},
    startInfo = runPetriFromPrompt[goal, "Async" -> True];
    If[MatchQ[Lookup[startInfo, "Status", ""], "ProposalEmpty" | "ParseFailed"],
      Return[startInfo]];
    
    wid = startInfo[["WorkflowId"]];
    waitResult = ClaudeWaitWorkflow[wid, opts];
    finalState = ClaudeWorkflowState[wid];
    trace      = ClaudeWorkflowTrace[wid];
    
    <|"Goal"             -> goal,
      "WorkflowId"       -> wid,
      "Status"           -> Lookup[waitResult, "Status", "?"],
      "WorkflowStatus"   -> Lookup[waitResult, "WorkflowStatus", "?"],
      "Steps"            -> Length[Cases[trace,
        ev_ /; ev[["Event"]] === "TransitionFired"]],
      "FiredTransitions" -> Counts[Cases[trace,
        ev_ /; ev[["Event"]] === "TransitionFired" :> ev[["TransitionName"]]]],
      "Code"             -> startInfo[["Code"]],
      "FinalState"       -> finalState,
      "Trace"            -> trace|>
  ];

(* === \:30c8\:30fc\:30af\:30f3\:904e\:5270\:6d88\:8cbb\:9632\:6b62\:306e\:305f\:3081\:306e\:5b89\:5168\:8d77\:52d5\:95a2\:6570 ===
   \:751f\:6210\:3055\:308c\:305f net \:3092\:5b9f\:884c\:524d\:306b\:9759\:7684\:30c1\:30a7\:30c3\:30af\:3057\:3001
   \:7121\:9650\:30eb\:30fc\:30d7\:3084 token \:904e\:5270\:6d88\:8cbb\:306e\:5371\:967a\:304c\:3042\:308b\:5834\:5408\:306f\:5b9f\:884c\:3092\:62d2\:5426\:3059\:308b\:3002 *)
ClearAll[safeRunPetriFromPrompt, iAnalyzeNetSafety];

(* WorkflowNet \:3092\:30c1\:30a7\:30c3\:30af\:3057\:3001\:5371\:967a\:8981\:56e0\:3092 List \:3067\:8fd4\:3059 *)
iAnalyzeNetSafety[net_Association] :=
  Module[{transitions, retryTransitions, hasGiveUp, issues = {}},
    transitions = Lookup[net, "Transitions", <||>];
    
    (* Retry / Loop \:30d1\:30bf\:30fc\:30f3\:306e transition \:3092\:62bd\:51fa *)
    retryTransitions = Select[Keys[transitions],
      StringContainsQ[#, "Retry"|"Loop"|"Repeat"|"Iterate"] &];
    
    (* GiveUp / Abort \:304c\:3042\:308b\:304b *)
    hasGiveUp = AnyTrue[Keys[transitions],
      StringContainsQ[#, "GiveUp"|"Abort"|"Bail"|"Stop"] &];
    
    Map[
      Function[tname,
        Module[{tdef, hasGuard, guardStr},
          tdef = transitions[[tname]];
          hasGuard = KeyExistsQ[tdef, "Guard"];
          If[!hasGuard,
            AppendTo[issues,
              "Retry transition \"" <> tname <>
              "\" \:306b Guard \:304c\:3042\:308a\:307e\:305b\:3093 (\:7121\:9650\:30eb\:30fc\:30d7\:30ea\:30b9\:30af)"]];
          (* Guard \:304c Function[...] \:306e\:5834\:5408\:3001\:4e2d\:8eab\:306b Trial \:3084 < \:304c\:542b\:307e\:308c\:308b\:304b *)
          If[hasGuard,
            guardStr = ToString[InputForm[tdef[["Guard"]]]];
            If[!StringContainsQ[guardStr, "Trial"|"trial"|"Count"|"Attempt"|"Iteration"|"<"|">"],
              AppendTo[issues,
                "Retry transition \"" <> tname <>
                "\" \:306e Guard \:304c\:30ab\:30a6\:30f3\:30bf\:3092\:30c1\:30a7\:30c3\:30af\:3057\:3066\:3044\:306a\:3044 (\:7121\:9650\:30eb\:30fc\:30d7\:30ea\:30b9\:30af)"]]]
        ]],
      retryTransitions];
    
    If[Length[retryTransitions] > 0 && !hasGiveUp,
      AppendTo[issues,
        "Retry transition \:304c\:3042\:308b\:306e\:306b GiveUp/Abort transition \:304c\:306a\:3044 (\:30eb\:30fc\:30d7\:304b\:3089\:8131\:51fa\:4e0d\:53ef)"]];
    
    issues
  ];

Options[safeRunPetriFromPrompt] = {
  "InitialToken" -> Automatic,
  "MaxSteps"     -> 30,
  "MaxStepsHardLimit" -> 60,
  "Async"        -> True,
  "ForceRun"     -> False
};

safeRunPetriFromPrompt[goal_String, opts:OptionsPattern[]] :=
  Module[{proposal, net, safetyIssues, force, maxSteps, hardLimit, effectiveMaxSteps,
          wid, initToken, runResult},
    force = OptionValue["ForceRun"];
    maxSteps = OptionValue["MaxSteps"];
    hardLimit = OptionValue["MaxStepsHardLimit"];
    effectiveMaxSteps = Min[maxSteps, hardLimit];
    
    proposal = proposePetriNet[goal];
    
    If[proposal[["Code"]] === "",
      Return[<|"Status" -> "ProposalEmpty", "Goal" -> goal,
               "RawResponse" -> proposal[["RawResponse"]]|>]];
    
    (* \:9759\:7684\:30c1\:30a7\:30c3\:30af\:306e\:5168\:4f53\:3092\:691c\:8a3c *)
    If[!force,
      If[Length[proposal[["RetryGuardIssues"]]] > 0,
        Print[Style["[safeRunPetriFromPrompt] \:5b9f\:884c\:3092\:62d2\:5426\:3057\:307e\:3057\:305f\:3002 " <>
                    "Retry Guard \:306e\:4e0d\:5099 (\:7121\:9650\:30eb\:30fc\:30d7\:30ea\:30b9\:30af):", Red, Bold]];
        Print[Style["  " <> StringRiffle[proposal[["RetryGuardIssues"]], "\n  "], Red]];
        Return[<|"Status" -> "RetryGuardMissing",
                 "RetryGuardIssues" -> proposal[["RetryGuardIssues"]],
                 "Hint" -> "ForceRun -> True \:3067\:5f37\:5236\:5b9f\:884c\:53ef\:80fd\:3060\:304c\:63a8\:5968\:3057\:306a\:3044",
                 "Code" -> proposal[["Code"]]|>]];
      If[Length[proposal[["PayloadAccessIssues"]]] > 0,
        Print[Style["[safeRunPetriFromPrompt] \:8b66\:544a: handler \:306e Payload \:30a2\:30af\:30bb\:30b9\:306b\:554f\:984c\:304c\:3042\:308a\:307e\:3059", Orange, Bold]];
        Print[Style["  " <> StringRiffle[proposal[["PayloadAccessIssues"]], ", "], Orange]]]];
    
    net = parsePetriCode[proposal[["Code"]]];
    
    If[net === $Failed,
      Return[<|"Status" -> "ParseFailed",
               "Code" -> proposal[["Code"]],
               "BuilderName" -> proposal[["BuilderName"]],
               "RawResponse" -> proposal[["RawResponse"]]|>]];
    
    (* \:52d5\:7684\:691c\:8a3c: net \:3092\:898b\:3066\:691c\:67fb *)
    safetyIssues = iAnalyzeNetSafety[net];
    If[!force && Length[safetyIssues] > 0,
      Print[Style["[safeRunPetriFromPrompt] \:5b9f\:884c\:3092\:62d2\:5426\:3057\:307e\:3057\:305f\:3002 " <>
                  "WorkflowNet \:306b\:5b89\:5168\:4e0a\:306e\:554f\:984c\:3042\:308a:", Red, Bold]];
      Map[Print[Style["  - " <> #, Red]] &, safetyIssues];
      Return[<|"Status" -> "UnsafeNet",
               "SafetyIssues" -> safetyIssues,
               "Hint" -> "ForceRun -> True \:3067\:5f37\:5236\:5b9f\:884c\:53ef\:80fd\:3060\:304c\:63a8\:5968\:3057\:306a\:3044",
               "Net" -> net|>]];
    
    wid = ClaudeCreateWorkflowNet[net,
      "Description" -> "safe-run: " <> StringTake[goal, Min[80, StringLength[goal]]]];
    
    initToken = OptionValue["InitialToken"];
    If[initToken === Automatic,
      initToken = WorkflowToken["Kind" -> "Task",
        "Payload" -> <|"Goal" -> goal, "Trial" -> 1|>]];
    
    ClaudeSubmitToken[wid, initToken];
    
    Print[Style["[safeRunPetriFromPrompt] \:5b9f\:884c\:958b\:59cb (MaxSteps=" <>
                ToString[effectiveMaxSteps] <> ")", Darker[Green], Bold]];
    
    runResult = ClaudeRunWorkflow[wid,
      "MaxSteps" -> effectiveMaxSteps,
      "Async"    -> OptionValue["Async"]];
    
    <|"Status"      -> "Started",
      "Goal"        -> goal,
      "WorkflowId"  -> wid,
      "MaxSteps"    -> effectiveMaxSteps,
      "Code"        -> proposal[["Code"]],
      "Net"         -> net,
      "SafetyIssues" -> safetyIssues,
      "RunResult"   -> runResult|>
  ];

(* ::Subsection:: *)
(* 6. \:6c4e\:7528\:7d50\:679c\:30a2\:30af\:30bb\:30b5 (\:65e2\:5b58\:306e wid \:304b\:3089\:7d50\:679c\:3092\:53d6\:308a\:51fa\:3059)
   
   \:8a2d\:8a08\:65b9\:91dd:
     - workflow \:304c\:5b8c\:8d70 (FinalPlaces \:306b token \:3042\:308a) \:306a\:3089 value \:3092\:8fd4\:3059
     - \:5b8c\:8d70\:3057\:306a\:304b\:3063\:305f\:306a\:3089\:30a8\:30e9\:30fc\:60c5\:5831 (\:30c7\:30ed\:30c3\:30af\:5834\:6240\:7b49) \:3092\:8fd4\:3059
     - getWorkflowValue: \:5b8c\:8d70\:6642\:306e\:307f value\:3001\:5931\:6557\:6642\:306f $Failed
     - getWorkflowError: \:5931\:6557\:6642\:306e\:8a73\:7d30\:3001\:5b8c\:8d70\:6642\:306f None *)

ClearAll[getWorkflowResults, getFinalTokens, getWorkflowReport,
         getTokensInPlace, getWorkflowValue, getWorkflowError,
         iIsCompleted, iExtractValue, iGetFinalPlaces];

(* FinalPlaces \:3092\:8907\:6570\:306e\:5834\:6240\:304b\:3089\:63a2\:3059\:3002
   ClaudeWorkflowState / ClaudeAsyncJobInfo / state.Net \:7b49\:306b\:683c\:7d0d\:3055\:308c\:3066\:3044\:308b\:3002 *)
iGetFinalPlaces[wid_String] :=
  Module[{state, info, places},
    state = ClaudeWorkflowState[wid];
    (* Try 1: state \:76f4\:4e0b *)
    places = Lookup[state, "FinalPlaces", None];
    If[places =!= None && places =!= {}, Return[places]];
    (* Try 2: state \:5185\:306e Net *)
    places = Lookup[Lookup[state, "Net", <||>], "FinalPlaces", None];
    If[places =!= None && places =!= {}, Return[places]];
    (* Try 3: AsyncJobInfo *)
    info = Quiet @ Check[ClaudeAsyncJobInfo[wid], <||>];
    places = Lookup[info, "FinalPlaces", None];
    If[places =!= None && places =!= {}, Return[places]];
    (* Try 4: state \:5185\:306e Spec / Definition \:7b49\:5225\:540d *)
    places = Lookup[Lookup[state, "Spec", <||>], "FinalPlaces", None];
    If[places =!= None && places =!= {}, Return[places]];
    {}
  ];

(* workflow \:304c\:5b8c\:8d70\:3057\:305f\:304b\:5224\:5b9a\:3002
   \:8907\:6570\:306e\:6307\:6a19\:3092 OR \:7d50\:5408:
     1. TerminationReason \:304c "ReachedFinalPlace" \:307e\:305f\:306f\:540c\:7b49
     2. FinalPlaces \:306e\:3044\:305a\:308c\:304b\:306b token \:304c\:5165\:3063\:305f *)
iIsCompleted[wid_String] :=
  Module[{state, info, marking, finalPlaces, totalInFinal, reason},
    state = ClaudeWorkflowState[wid];
    info  = Quiet @ Check[ClaudeAsyncJobInfo[wid], <||>];
    
    (* \:6307\:6a19 1: TerminationReason \:3092\:898b\:308b *)
    reason = Lookup[info, "TerminationReason",
      Lookup[state, "TerminationReason", ""]];
    If[MemberQ[{"ReachedFinalPlace", "Reached final place",
                "Completed", "completed"}, reason],
      Return[True]];
    
    (* \:6307\:6a19 2: FinalPlaces \:306b token \:304c\:3042\:308b\:304b *)
    marking = Lookup[state, "CurrentMarking",
      Lookup[state, "Marking", <||>]];
    finalPlaces = iGetFinalPlaces[wid];
    totalInFinal = Total @ Map[Length[Lookup[marking, #, {}]] &, finalPlaces];
    totalInFinal > 0
  ];

(* Payload \:304b\:3089 value-like \:306a\:30ad\:30fc\:3092\:512a\:5148\:9806\:306b\:62bd\:51fa\:3002
   \:30ec\:30d3\:30e5\:30fc\:7d50\:679c (Review/Verdict/Decision \:7b49) \:3092\:6700\:512a\:5148\:3001
   "Text" \:306f\:6700\:5f8c\:306e fallback \:306b\:3059\:308b\:3002
   key \:304c\:3042\:3063\:3066\:3082\:5024\:304c Missing \:306e\:5834\:5408\:306f\:6b21\:5019\:88dc\:306b\:9032\:3080\:3002
   \:898b\:3064\:304b\:3089\:306a\:3051\:308c\:3070 Payload \:5168\:4f53\:3092\:8fd4\:3059\:3002 *)
iExtractValue[payload_Association] :=
  Module[{candidateKeys, candidate, value, found = None},
    candidateKeys = {
      (* \:6700\:512a\:5148: $petriNetGuide \:898f\:7d04\:30ad\:30fc *)
      "FinalResult",
      (* \:6b21\:512a\:5148: \:30ec\:30d3\:30e5\:30fc/\:8a55\:4fa1/\:51e6\:7406\:7d50\:679c\:3092\:793a\:3059\:30ad\:30fc *)
      "Verdict", "Decision", "Review", "Reviews", "Reasoning", "Comment", "Comments",
      "Results", "FinalResults",
      (* \:6c4e\:7528\:7684\:306a\:51fa\:529b\:30ad\:30fc *)
      "Value", "Result", "Answer", "Output", "FinalAnswer", "Final",
      (* fallback *)
      "Summary", "Response",
      (* \:6700\:7d42 fallback (\:5165\:529b\:7e26\:8d70\:308a\:306e\:53ef\:80fd\:6027\:3042\:308a) *)
      "Text"};
    Do[
      If[KeyExistsQ[payload, candidate],
        value = payload[[candidate]];
        If[!MatchQ[value, _Missing],
          found = value;
          Break[]]],
      {candidate, candidateKeys}
    ];
    If[found === None, payload, found]
  ];
iExtractValue[other_] := other;

(* \:6700\:7d42 Place (Done / Final \:7b49) \:306b\:6b8b\:3063\:3066\:3044\:308b token \:3092\:53d6\:5f97\:3002
   FinalPlaces \:304c\:53d6\:5f97\:3067\:304d\:306a\:3044\:5834\:5408\:306f\:3001
   trace \:304b\:3089\:6700\:5f8c\:306b fire \:3057\:305f transition \:304c\:751f\:6210\:3057\:305f token \:3092\:8fd4\:3059\:3002 *)
getFinalTokens[wid_String] :=
  Module[{state, marking, finalPlaces, finalTokenIds, allTokens,
          trace, fired, lastFired, lastProducedIds},
    state = ClaudeWorkflowState[wid];
    marking = Lookup[state, "CurrentMarking",
      Lookup[state, "Marking", <||>]];
    finalPlaces = iGetFinalPlaces[wid];
    allTokens = Lookup[state, "Tokens", <||>];
    
    If[finalPlaces =!= {},
      (* \:6b63\:898f\:30eb\:30fc\:30c8: FinalPlaces \:304c\:5224\:660e\:3057\:3066\:3044\:308b *)
      finalTokenIds = Flatten @ Map[Lookup[marking, #, {}] &, finalPlaces];
      Return[Map[Lookup[allTokens, #, <||>] &, finalTokenIds]]];
    
    (* Fallback 1: \:5b8c\:8d70\:3057\:3066\:3044\:308b\:306a\:3089\:3001trace \:306e\:6700\:7d42 transition \:304c
       \:751f\:6210\:3057\:305f token \:3092\:8fd4\:3059 *)
    If[iIsCompleted[wid],
      trace = ClaudeWorkflowTrace[wid];
      fired = Cases[trace, ev_ /; ev[["Event"]] === "TransitionFired"];
      If[Length[fired] > 0,
        lastFired = Last[fired];
        lastProducedIds = Lookup[lastFired, "ProducedIds",
          Lookup[lastFired, "ProducedTokenIds", {}]];
        If[Length[lastProducedIds] > 0,
          Return[Map[Lookup[allTokens, #, <||>] &, lastProducedIds]]]]];
    
    (* Fallback 2: token \:304c\:6b8b\:3063\:3066\:3044\:308b place \:3092\:5168\:90e8 final \:3068\:307f\:306a\:3059
       (\:5b8c\:8d70\:3057\:3066\:3044\:306a\:3044\:5834\:5408\:3084 trace \:304c\:7a7a\:306e\:5834\:5408) *)
    finalPlaces = Select[Keys[marking],
      Length[Lookup[marking, #, {}]] > 0 &];
    finalTokenIds = Flatten @ Map[Lookup[marking, #, {}] &, finalPlaces];
    Map[Lookup[allTokens, #, <||>] &, finalTokenIds]
  ];

(* \:7279\:5b9a Place \:306b\:3042\:308b token \:3092\:53d6\:5f97 *)
getTokensInPlace[wid_String, placeName_String] :=
  Module[{state, marking, tokenIds, allTokens},
    state = ClaudeWorkflowState[wid];
    marking = Lookup[state, "CurrentMarking",
      Lookup[state, "Marking", <||>]];
    allTokens = Lookup[state, "Tokens", <||>];
    tokenIds = Lookup[marking, placeName, {}];
    Map[Lookup[allTokens, #, <||>] &, tokenIds]
  ];

(* === \:30e1\:30a4\:30f3 API: \:5b8c\:8d70\:6642\:306f value\:3001\:5931\:6557\:6642\:306f $Failed === *)
getWorkflowValue[wid_String] :=
  Module[{finalToks, payloads, values},
    If[!iIsCompleted[wid], Return[$Failed]];
    finalToks = getFinalTokens[wid];
    If[Length[finalToks] === 0, Return[$Failed]];
    payloads = Map[Lookup[#, "Payload", <||>] &, finalToks];
    values = Map[iExtractValue, payloads];
    (* token \:304c 1 \:3064\:306a\:3089\:305d\:306e\:307e\:307e\:3001\:8907\:6570\:306a\:3089\:30ea\:30b9\:30c8 *)
    If[Length[values] === 1, First[values], values]
  ];

(* === \:5931\:6557\:6642\:306e\:8a73\:7d30\:60c5\:5831\:3002\:5b8c\:8d70\:6642\:306f None\:3002 === *)
getWorkflowError[wid_String] :=
  Module[{state, info, marking, finalPlaces, fired, lastFired,
          stuckPlaces, stuckTokenCount, failedFired, failedNames},
    If[iIsCompleted[wid], Return[None]];
    
    state = ClaudeWorkflowState[wid];
    info  = Quiet @ Check[ClaudeAsyncJobInfo[wid], <||>];
    marking = Lookup[state, "CurrentMarking",
      Lookup[state, "Marking", <||>]];
    finalPlaces = iGetFinalPlaces[wid];
    
    (* \:6700\:5f8c\:306b fire \:3057\:305f transition \:3092\:53d6\:5f97 *)
    fired = Cases[ClaudeWorkflowTrace[wid],
      ev_ /; ev[["Event"]] === "TransitionFired"];
    lastFired = If[Length[fired] === 0, None,
      Last[fired][["TransitionName"]]];
    
    (* ExecutorStatus \:304c "Failed" \:3060\:3063\:305f transition \:3092\:62bd\:51fa
       (handler \:5185\:3067\:30a8\:30e9\:30fc\:304c\:8d77\:304d\:305f\:3053\:3068\:3092\:610f\:5473) *)
    failedFired = Select[fired,
      Lookup[#, "ExecutorStatus", ""] === "Failed" &];
    failedNames = Counts[failedFired[[All, "TransitionName"]]];
    
    (* token \:304c\:6b8b\:3063\:3066\:3044\:308b\:975e final Place \:3092\:62bd\:51fa (\:8a70\:307e\:308a\:5834\:6240) *)
    stuckPlaces = Select[Keys[marking],
      And[Length[Lookup[marking, #, {}]] > 0,
          !MemberQ[finalPlaces, #]] &];
    stuckTokenCount = AssociationMap[
      Length[Lookup[marking, #, {}]] &, stuckPlaces];
    
    <|"WorkflowId"          -> wid,
      "Reason"               -> Lookup[info, "TerminationReason",
                                       Lookup[state, "Status", "Unknown"]],
      "Steps"                -> Lookup[info, "Steps", 0],
      "LastFiredTransition"  -> lastFired,
      "FailedTransitions"    -> failedNames,
      "StuckPlaces"          -> stuckTokenCount,
      "FinalPlaces"          -> finalPlaces,
      "TokensInFinal"        -> AssociationMap[
        Length[Lookup[marking, #, {}]] &, finalPlaces]|>
  ];

(* === \:30c7\:30d0\:30c3\:30b0\:7528\:306e\:8a73\:7d30 Association === *)
getWorkflowResults[wid_String] :=
  Module[{state, info, trace, fired, finalToks, marking, finalPlaces},
    state = ClaudeWorkflowState[wid];
    info  = Quiet @ Check[ClaudeAsyncJobInfo[wid], <||>];
    trace = ClaudeWorkflowTrace[wid];
    fired = Cases[trace, ev_ /; ev[["Event"]] === "TransitionFired"];
    finalToks = getFinalTokens[wid];
    marking = Lookup[state, "CurrentMarking",
      Lookup[state, "Marking", <||>]];
    finalPlaces = iGetFinalPlaces[wid];
    
    <|"WorkflowId"        -> wid,
      "Completed"         -> iIsCompleted[wid],
      "AsyncStatus"       -> Lookup[info, "Status",
                                    Lookup[state, "Status", "?"]],
      "TerminationReason" -> Lookup[info, "TerminationReason", "-"],
      "Steps"             -> Length[fired],
      "FiredTransitions"  -> Counts[fired[[All, "TransitionName"]]],
      "FinalPlaces"       -> finalPlaces,
      "TokensInFinal"     -> AssociationMap[
        Length[Lookup[marking, #, {}]] &, finalPlaces],
      "FinalTokens"       -> finalToks,
      "FinalPayloads"     -> Map[Lookup[#, "Payload", <||>] &, finalToks],
      "Value"             -> getWorkflowValue[wid],
      "Error"             -> getWorkflowError[wid],
      "CurrentMarking"    -> AssociationMap[
        Length[Lookup[marking, #, {}]] &, Keys[marking]]|>
  ];

(* === \:30e1\:30a4\:30f3 \:8868\:793a API: \:5b8c\:8d70\:306a\:3089 value\:3001\:5931\:6557\:306a\:3089\:30a8\:30e9\:30fc\:8a73\:7d30 === *)
getWorkflowReport[wid_String] :=
  Module[{r, completed, value, err, state, allTokens, initTokens, initPayloads,
          valueIsPassthrough, suspicionWarning},
    r = getWorkflowResults[wid];
    completed = r[["Completed"]];
    
    If[completed,
      (* \:5b8c\:8d70\:6642: value \:3092\:5f37\:8abf\:8868\:793a *)
      value = r[["Value"]];
      
      (* \:300c\:51e6\:7406\:304c\:7a7a\:758e\:300d\:691c\:51fa: value \:304c\:5165\:529b token \:306e Payload \:5024\:3068
         \:5b8c\:5168\:4e00\:81f4\:3057\:3066\:3044\:308b\:5834\:5408\:3001\:30ec\:30d3\:30e5\:30fc\:7b49\:306e\:5b9f\:8cea\:4ed8\:52a0\:51e6\:7406\:304c
         \:5168\:304f\:884c\:308f\:308c\:3066\:3044\:306a\:3044\:53ef\:80fd\:6027\:3002 *)
      state = ClaudeWorkflowState[wid];
      allTokens = Lookup[state, "Tokens", <||>];
      (* \:521d\:671f\:6295\:5165 token (ParentIds \:304c\:7a7a) \:3092\:63a2\:3059 *)
      initTokens = Select[Values[allTokens],
        And[AssociationQ[#],
            Length[Lookup[#, "ParentIds", {1}]] === 0] &];
      initPayloads = Map[Lookup[#, "Payload", <||>] &, initTokens];
      valueIsPassthrough = AnyTrue[initPayloads,
        Function[ip,
          Or[
            (* value \:304c\:521d\:671f Payload \:306e Text/Goal/Input \:30ad\:30fc\:3068\:540c\:3058 *)
            value === Lookup[ip, "Text", $missing1],
            value === Lookup[ip, "Goal", $missing2],
            value === Lookup[ip, "Input", $missing3],
            value === Lookup[ip, "Query", $missing4]]]];
      suspicionWarning = If[valueIsPassthrough,
        Style["\:26a0 Value \:304c\:5165\:529b token \:306e\:30c7\:30fc\:30bf\:3068\:4e00\:81f4 \:2014 " <>
              "\:30ec\:30d3\:30e5\:30fc/\:51e6\:7406\:7d50\:679c\:304c Payload \:306b\:52a0\:3048\:3089\:308c\:3066\:3044\:306a\:3044\:53ef\:80fd\:6027 " <>
              "(handler \:304c\:5b9f\:8cea\:4f55\:3082\:3057\:3066\:3044\:306a\:3044\:3001\:307e\:305f\:306f \"Text\" \:30ad\:30fc\:3060\:3051\:3092\:30d1\:30b9\:30b9\:30eb\:30fc\:3057\:3066\:3044\:308b)",
              Bold, Orange, 12],
        ""];
      
      Column[{
        Style["\:2705 Workflow Completed", Bold, Darker[Green], 14],
        suspicionWarning,
        Grid[{
          {Style["WorkflowId",       Bold], r[["WorkflowId"]]},
          {Style["Steps",            Bold], r[["Steps"]]},
          {Style["FiredTransitions", Bold], r[["FiredTransitions"]]},
          {Style["TokensInFinal",    Bold], r[["TokensInFinal"]]}
        }, Frame -> All, Alignment -> {Left, Center}],
        "",
        Style["\:6700\:7d42 token \:306e Payload \:30ad\:30fc\:4e00\:89a7:", Bold, 13],
        Quiet @ Check[listValueKeys[wid], "(\:30ad\:30fc\:4e00\:89a7\:53d6\:5f97\:5931\:6557)"],
        "",
        Style["\:63a8\:5b9a Value (iExtractValue \:306b\:3088\:308b\:81ea\:52d5\:62bd\:51fa):", Bold, 13],
        Style[ToString[value, InputForm], FontFamily -> "Courier", FontSize -> 12,
              Background -> If[valueIsPassthrough,
                Lighter[Orange, 0.8], Lighter[Yellow, 0.85]]],
        If[valueIsPassthrough,
          Style["\:8a3a\:65ad: \:4e0a\:306e Value \:304c\:5165\:529b token \:3068\:4e00\:81f4\:3057\:3066\:3044\:307e\:3059\:3002 " <>
                "\:4e0a\:306e\:30ad\:30fc\:4e00\:89a7\:3092\:898b\:3066\:3001\:672c\:5f53\:306e\:51e6\:7406\:7d50\:679c\:304c\:5225\:306e\:30ad\:30fc\:540d (Reviews \:7b49) \:306b\:3042\:308b\:304b\:78ba\:8a8d\:3057\:3001 " <>
                "getValueByKey[wid, \"<keyName>\"] \:3067\:53d6\:308a\:51fa\:3059\:3002",
                Italic, Gray, 11],
          ""]
      }, Frame -> True]
      ,
      (* \:5931\:6557\:6642: \:30a8\:30e9\:30fc\:60c5\:5831 *)
      err = r[["Error"]];
      Module[{maxFiredCount, loopWarning},
        maxFiredCount = If[Length[r[["FiredTransitions"]]] > 0,
          Max[Values[r[["FiredTransitions"]]]], 0];
        loopWarning = If[maxFiredCount >= 5,
          Style["\:26a0 \:540c\:3058 transition \:304c " <> ToString[maxFiredCount] <>
                " \:56de\:767a\:706b\:3057\:3066\:3044\:307e\:3059 \:2014 \:7121\:9650\:30eb\:30fc\:30d7\:306e\:53ef\:80fd\:6027\:9ad8\:3057",
                Bold, Red, 13],
          ""];
        Column[{
          Style["\:274c Workflow Failed (not completed)", Bold, Red, 14],
          loopWarning,
          Grid[{
            {Style["WorkflowId",          Bold], r[["WorkflowId"]]},
            {Style["Reason",              Bold], err[["Reason"]]},
            {Style["Steps",               Bold,
                   If[err[["Steps"]] >= 30, Red, Black]],
              err[["Steps"]]},
            {Style["LastFiredTransition", Bold], err[["LastFiredTransition"]]},
            {Style["FiredTransitions",    Bold,
                   If[maxFiredCount >= 5, Red, Black]],
              r[["FiredTransitions"]]},
            {Style["FailedTransitions",   Bold,
                   If[Length[err[["FailedTransitions"]]] > 0, Red, Black]],
              err[["FailedTransitions"]]},
            {Style["TokensInFinal",       Bold], err[["TokensInFinal"]]},
            {Style["StuckPlaces",         Bold,
                   If[Total[Values[err[["StuckPlaces"]]]] > 0,
                      Orange, Black]],
              err[["StuckPlaces"]]}
          }, Frame -> All, Alignment -> {Left, Center}],
          "",
          Style[Switch[True,
            maxFiredCount >= 5,
              "Tip: \:540c\:3058 transition \:304c\:591a\:6570\:56de\:767a\:706b\:2192\:7121\:9650\:30eb\:30fc\:30d7\:3002 " <>
              "Retry transition \:306e Guard \:304c Trial \:3092\:30c1\:30a7\:30c3\:30af\:3057\:3066\:3044\:306a\:3044\:3001 " <>
              "\:307e\:305f\:306f Trial \:30ab\:30a6\:30f3\:30bf\:3092\:6b63\:3057\:304f +1 \:3057\:3066\:3044\:306a\:3044\:3002 " <>
              "\:4eca\:5f8c\:306f safeRunPetriFromPrompt \:3092\:4f7f\:3046\:3068\:9759\:7684\:30c1\:30a7\:30c3\:30af\:3067\:3053\:306e\:578b\:306e\:30d0\:30b0\:3092\:4e8b\:524d\:68c4\:5374\:3067\:304d\:308b\:3002",
            Length[err[["FailedTransitions"]]] > 0,
              "Tip: handler \:5185\:3067\:30a8\:30e9\:30fc\:304c\:8d77\:304d\:307e\:3057\:305f\:3002 " <>
              "getTokensInPlace[wid, \"<placeName>\"] \:3067 token \:3092\:898b\:308b\:3001\:307e\:305f\:306f " <>
              "ClaudeWorkflowTrace[wid] \:3067\:8a73\:7d30\:30c8\:30ec\:30fc\:30b9\:3092\:898b\:308b\:3002 " <>
              "\:591a\:304f\:306e\:5834\:5408\:3001handler \:304c binding[[place, \"Payload\", key]] \:3067\:306f\:306a\:304f " <>
              "binding[[place, key]] \:306b\:30a2\:30af\:30bb\:30b9\:3057\:3066\:3044\:308b (\\\"Payload\\\" \:62b9\:3051\:843d\:3061)\:3002",
            Total[Values[err[["StuckPlaces"]]]] > 0,
              "Tip: \:8a70\:307e\:308a\:5834\:6240 (StuckPlaces) \:306e token \:3092\:898b\:308b\:306b\:306f " <>
              "getTokensInPlace[wid, \"<placeName>\"]\:3002 " <>
              "Verdict \:306e Stuck \:306e\:591a\:304f\:306f\:3001Aggregate \:306e Payload \:306b " <>
              "\:30c0\:30a6\:30f3\:30b9\:30c8\:30ea\:30fc\:30e0 Guard \:304c\:671f\:5f85\:3059\:308b\:30ad\:30fc " <>
              "(\\\"Decision\\\", \\\"Trial\\\" \:7b49) \:304c\:5165\:3063\:3066\:3044\:306a\:3044\:305f\:3081\:3002",
            True, ""], Italic, Gray, 11]
        }, Frame -> True]
      ]
    ]
  ];

(* ::Subsection:: *)
(* 6.5. \:8a73\:7d30\:89b3\:6e2c\:3068\:900f\:660e\:6027 (Observability) *)

ClearAll[inspectAllTokens, inspectTokenFlow, inspectFinalPayload,
         allPayloadKeys, getValueByKey, listValueKeys];

(* === \:5168 token \:3092\:898b\:308b: Place \:6bce\:306b\:3069\:306e token \:304c\:4f5c\:3089\:308c\:305f\:304b\:3092\:78ba\:8a8d === *)
inspectAllTokens[wid_String] :=
  Module[{state, allTokens, trace, fired, eventInfo},
    state = ClaudeWorkflowState[wid];
    allTokens = Lookup[state, "Tokens", <||>];
    trace = ClaudeWorkflowTrace[wid];
    fired = Cases[trace, ev_ /; ev[["Event"]] === "TransitionFired"];
    
    (* \:5404 fired event \:304b\:3089 ProducedIds -> Transition \:30de\:30c3\:30d4\:30f3\:30b0\:3092\:4f5c\:308b *)
    eventInfo = Association @@ Flatten @ Map[
      Function[ev,
        Map[(# -> <|"CreatedBy" -> ev[["TransitionName"]],
                    "Step" -> Lookup[ev, "Step", "?"],
                    "Status" -> Lookup[ev, "ExecutorStatus", "?"]|>) &,
          Lookup[ev, "ProducedIds", {}]]],
      fired];
    
    Dataset[
      KeyValueMap[
        Function[{tid, tok},
          Module[{ev, payload},
            ev = Lookup[eventInfo, tid, <|"CreatedBy" -> "Initial",
                                          "Step" -> 0, "Status" -> "-"|>];
            payload = Lookup[tok, "Payload", <||>];
            <|"TokenId"       -> tid,
              "Step"          -> ev[["Step"]],
              "CreatedBy"     -> ev[["CreatedBy"]],
              "Status"        -> ev[["Status"]],
              "Kind"          -> Lookup[tok, "Kind", "?"],
              "PayloadKeys"   -> If[AssociationQ[payload], Keys[payload], {}],
              "PayloadSizes"  -> If[AssociationQ[payload],
                AssociationMap[
                  Function[k,
                    Module[{v}, v = payload[[k]];
                      Which[StringQ[v], StringLength[v],
                            ListQ[v], Length[v],
                            True, "?"]]],
                  Keys[payload]],
                <||>]|>
          ]],
        allTokens]]
  ];

(* === \:7279\:5b9a transition \:306e\:5165\:51fa\:529b token \:3092\:898b\:308b === *)
inspectTokenFlow[wid_String, transitionName_String] :=
  Module[{state, allTokens, trace, fired, evs, getPayload},
    state = ClaudeWorkflowState[wid];
    allTokens = Lookup[state, "Tokens", <||>];
    trace = ClaudeWorkflowTrace[wid];
    fired = Cases[trace, ev_ /; ev[["Event"]] === "TransitionFired"];
    evs = Select[fired, #[["TransitionName"]] === transitionName &];
    
    If[Length[evs] === 0,
      Print[Style["[inspectTokenFlow] " <> transitionName <>
                  " \:306f\:307e\:3060 fire \:3057\:3066\:3044\:307e\:305b\:3093", Orange]];
      Return[Dataset[{}]]];
    
    getPayload[tid_] := Lookup[Lookup[allTokens, tid, <||>], "Payload", <||>];
    
    Dataset[
      MapIndexed[
        Function[{ev, idx},
          <|"FireCount"     -> First[idx],
            "Step"           -> Lookup[ev, "Step", "?"],
            "Status"         -> Lookup[ev, "ExecutorStatus", "?"],
            "ConsumedIds"    -> Lookup[ev, "ConsumedIds", {}],
            "ConsumedPayloads" -> Map[getPayload, Lookup[ev, "ConsumedIds", {}]],
            "ProducedIds"    -> Lookup[ev, "ProducedIds", {}],
            "ProducedPayloads" -> Map[getPayload, Lookup[ev, "ProducedIds", {}]]|>
        ],
        evs]]
  ];

(* === \:6700\:7d42 token \:306e Payload \:5168\:4f53\:3092\:30ec\:30f3\:30c0\:30ea\:30f3\:30b0 === *)
inspectFinalPayload[wid_String] :=
  Module[{tokens, payloads},
    tokens = getFinalTokens[wid];
    If[Length[tokens] === 0,
      Print[Style["[inspectFinalPayload] \:6700\:7d42 token \:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093", Orange]];
      Return[$Failed]];
    payloads = Map[Lookup[#, "Payload", <||>] &, tokens];
    Column[Map[
      Function[p,
        Column[{
          Style["Payload \:30ad\:30fc:", Bold],
          Grid[
            KeyValueMap[
              Function[{k, v},
                {Style[k, Bold],
                 Style[Which[
                   StringQ[v] && StringLength[v] > 100,
                     StringTake[v, 100] <> "...",
                   ListQ[v], "List of " <> ToString[Length[v]] <> " items",
                   AssociationQ[v], "Association",
                   True, ToString[v]],
                  FontFamily -> "Courier", FontSize -> 11]}],
              p],
            Frame -> All, Alignment -> {Left, Top}]
        }]],
      payloads], Spacings -> 1]
  ];

(* === \:4efb\:610f\:30ad\:30fc\:3067 value \:3092\:53d6\:308a\:51fa\:3059 === *)
getValueByKey[wid_String, key_String] :=
  Module[{tokens, payloads},
    tokens = getFinalTokens[wid];
    payloads = Map[Lookup[#, "Payload", <||>] &, tokens];
    DeleteCases[
      Map[Lookup[#, key, $Failed] &, payloads],
      $Failed]
  ];

(* === \:5168 token \:306e Payload \:30ad\:30fc\:540d\:3092\:30ea\:30b9\:30c8 === *)
allPayloadKeys[wid_String] :=
  Module[{state, allTokens, payloads, allKeys},
    state = ClaudeWorkflowState[wid];
    allTokens = Lookup[state, "Tokens", <||>];
    payloads = Map[Lookup[#, "Payload", <||>] &, Values[allTokens]];
    allKeys = Flatten @ Map[Keys, Select[payloads, AssociationQ]];
    Counts[allKeys]
  ];

(* === \:6700\:7d42 token \:306e\:51fa\:529b\:30ad\:30fc\:3092\:30ea\:30b9\:30c8 (\:3069\:306e\:30ad\:30fc\:3067\:4f55\:304c\:53d6\:308c\:308b\:304b) === *)
listValueKeys[wid_String] :=
  Module[{tokens, payloads, keys},
    tokens = getFinalTokens[wid];
    payloads = Map[Lookup[#, "Payload", <||>] &, tokens];
    keys = Flatten @ Map[Keys, Select[payloads, AssociationQ]];
    Grid[
      Prepend[
        Map[
          Function[k,
            Module[{v},
              v = First[DeleteCases[
                Map[Lookup[#, k, Missing[]] &, payloads],
                _Missing]];
              {Style[k, Bold],
               Style[Which[
                 StringQ[v] && StringLength[v] > 60,
                   StringTake[v, 60] <> "...",
                 ListQ[v], "List(" <> ToString[Length[v]] <> ")",
                 AssociationQ[v], "Assoc(" <> ToString[Length[v]] <> ")",
                 True, ToString[v]],
                FontFamily -> "Courier", FontSize -> 10]}]],
          DeleteDuplicates[keys]],
        {Style["Key", Bold, Background -> Lighter[Gray, 0.7]],
         Style["Value preview", Bold, Background -> Lighter[Gray, 0.7]]}],
      Frame -> All, Alignment -> {Left, Top}]
  ];

(* === \:81ea\:52d5\:5931\:6557\:8a3a\:65ad: \:5931\:6557\:30b1\:30fc\:30b9\:306e\:771f\:56e0\:3092\:7d76\:5bfe\:7684\:306b\:7279\:5b9a\:3059\:308b === *)
ClearAll[diagnoseFailure];

diagnoseFailure[wid_String] :=
  Module[{state, allTokens, trace, fired, failedFired, marking,
          stuckPlaces, finalPlaces, net, transitions,
          findings = {}, hypothesis = "Unknown",
          failedNames, failedTrans, lastFailed, beforeLastFailed},
    
    state = ClaudeWorkflowState[wid];
    allTokens = Lookup[state, "Tokens", <||>];
    trace = ClaudeWorkflowTrace[wid];
    fired = Cases[trace, ev_ /; ev[["Event"]] === "TransitionFired"];
    failedFired = Select[fired, Lookup[#, "ExecutorStatus", ""] === "Failed" &];
    failedNames = DeleteDuplicates[failedFired[[All, "TransitionName"]]];
    
    marking = Lookup[state, "CurrentMarking", Lookup[state, "Marking", <||>]];
    finalPlaces = iGetFinalPlaces[wid];
    stuckPlaces = Select[Keys[marking],
      And[Length[Lookup[marking, #, {}]] > 0, !MemberQ[finalPlaces, #]] &];
    
    net = Lookup[state, "Net", <||>];
    transitions = Lookup[net, "Transitions", <||>];
    
    (* === \:8a3a\:65ad\:30ed\:30b8\:30c3\:30af === *)
    
    (* Case 1: \:540c\:3058 transition \:304c\:591a\:6570\:56de\:5b9f\:884c \:2192 \:7121\:9650\:30eb\:30fc\:30d7 *)
    Module[{firedCounts, maxCount},
      firedCounts = Counts[fired[[All, "TransitionName"]]];
      maxCount = If[Length[firedCounts] > 0, Max[Values[firedCounts]], 0];
      If[maxCount >= 5,
        AppendTo[findings,
          "\:540c\:3058 transition \:304c " <> ToString[maxCount] <>
          " \:56de\:767a\:706b\:3057\:3066\:3044\:308b \:2192 \:7121\:9650\:30eb\:30fc\:30d7"];
        hypothesis = "InfiniteLoop"]];
    
    (* Case 2: ExecutorStatus = Failed \:306e transition \:304c\:3042\:308b *)
    If[Length[failedNames] > 0,
      AppendTo[findings,
        "Failed \:3057\:305f transition: " <> StringRiffle[failedNames, ", "]];
      hypothesis = "HandlerError"];
    
    (* Case 3: Stuck Place \:306e token \:306e Payload \:30ad\:30fc\:3092\:8abf\:3079\:308b *)
    If[Length[stuckPlaces] > 0,
      Module[{place, tokensThere, payloadKeysOnTok, expectedKeys, missingKeys,
              guards},
        place = First[stuckPlaces];
        tokensThere = Map[Lookup[allTokens, #, <||>] &,
                          Lookup[marking, place, {}]];
        payloadKeysOnTok = If[Length[tokensThere] > 0,
          Keys[Lookup[First[tokensThere], "Payload", <||>]], {}];
        AppendTo[findings,
          "Stuck Place \"" <> place <> "\" \:306e token \:306e Payload \:30ad\:30fc: " <>
          StringRiffle[payloadKeysOnTok, ", "]];
        
        (* \:305d\:306e Place \:3092\:5165\:529b\:3068\:3059\:308b transition \:306e Guard \:3092\:63a2\:3057\:3066\:3001
           Guard \:304c\:671f\:5f85\:3057\:3066\:3044\:308b\:30ad\:30fc\:3068\:30de\:30c3\:30c1\:3055\:305b\:308b *)
        guards = Select[
          KeyValueMap[
            Function[{tname, tdef},
              Module[{inputArcs, readsThisPlace, guardStr},
                inputArcs = Lookup[tdef, "InputArcs", {}];
                readsThisPlace = AnyTrue[inputArcs,
                  Lookup[#, "Place", ""] === place &];
                If[readsThisPlace && KeyExistsQ[tdef, "Guard"],
                  guardStr = ToString[InputForm[tdef[["Guard"]]]];
                  <|"Transition" -> tname, "GuardStr" -> guardStr|>,
                  Nothing]]],
            transitions],
          AssociationQ];
        
        Map[
          Function[g,
            Module[{gs, mentioned, missingInPayload},
              gs = g[["GuardStr"]];
              (* Guard \:4e2d\:306e \"X\" \:30ea\:30c6\:30e9\:30eb\:3092\:62bd\:51fa *)
              mentioned = StringCases[gs,
                "\"" ~~ k:Except["\""].. ~~ "\"" :> k];
              mentioned = DeleteDuplicates[mentioned];
              missingInPayload = Select[mentioned,
                And[!MemberQ[payloadKeysOnTok, #],
                    !MemberQ[{"Payload", "Kind", "TokenId"}, #]] &];
              If[Length[missingInPayload] > 0,
                AppendTo[findings,
                  "Guard \"" <> g[["Transition"]] <>
                  "\" \:304c\:671f\:5f85\:3059\:308b\:30ad\:30fc " <>
                  StringRiffle[missingInPayload, ", "] <>
                  " \:304c token \:306e Payload \:306b\:306a\:3044 \:2192 Stuck \:306e\:539f\:56e0"];
                hypothesis = "GuardKeyMismatch"]
            ]],
          guards]
      ]];
    
    (* Case 4: Aggregate Failed \:306e\:539f\:56e0\:63a8\:5b9a *)
    failedTrans = If[Length[failedFired] > 0, Last[failedFired], None];
    If[failedTrans =!= None,
      Module[{tname, consumedIds, consumedPayloads, allConsumedKeys},
        tname = failedTrans[["TransitionName"]];
        consumedIds = Lookup[failedTrans, "ConsumedIds", {}];
        consumedPayloads = Map[
          Lookup[Lookup[allTokens, #, <||>], "Payload", <||>] &,
          consumedIds];
        allConsumedKeys = Flatten @ Map[Keys, Select[consumedPayloads, AssociationQ]];
        AppendTo[findings,
          tname <> " \:306f\:4ee5\:4e0b\:306e\:30ad\:30fc\:3092\:6301\:3064 token \:3092\:6d88\:8cbb\:3057\:305f: " <>
          StringRiffle[DeleteDuplicates[allConsumedKeys], ", "]];
        AppendTo[findings,
          tname <> " \:306e handler \:304c\:4e0a\:8a18\:30ad\:30fc\:4ee5\:5916 (\:4f8b: \"Review\" \:3068 \"ReviewA\" \:306e\:4e0d\:4e00\:81f4 etc.) \:3092\:8aad\:3082\:3046\:3068\:3057\:3066\:4f8b\:5916\:30b3\:30fc\:30b9\:306b\:9665\:3063\:305f\:53ef\:80fd\:6027\:9ad8\:3057"]
      ]];
    
    (* === \:8868\:793a === *)
    Column[{
      Style["\:26a0 Failure Diagnosis: " <> hypothesis, Bold, Red, 14],
      "",
      Style["WorkflowId: " <> wid, Italic, Gray],
      "",
      Style["Findings:", Bold],
      Column[Map[("\:30fb " <> #) &, findings]],
      "",
      Style["\:63a8\:5968\:30a2\:30af\:30b7\:30e7\:30f3:", Bold],
      Switch[hypothesis,
        "InfiniteLoop",
          "Retry transition \:306e Guard \:304c Trial \:3092\:30c1\:30a7\:30c3\:30af\:3057\:3066\:3044\:306a\:3044\:3002 " <>
          "MaxSteps \:3092\:4e0a\:3052\:305a\:3001\:65b0\:3057\:3044 net \:3092\:751f\:6210\:3057\:308b\:3002",
        "GuardKeyMismatch",
          "Aggregate / \:4e2d\:9593 transition \:304c Verdict \:306b\:671f\:5f85\:30ad\:30fc\:3092\:5165\:308c\:3066\:3044\:306a\:3044\:3002 " <>
          "inspectTokenFlow[wid, \"Aggregate\"] \:3067\:51fa\:529b\:3092\:898b\:3066\:3001 " <>
          "Aggregate handler \:3092\:4fee\:6b63 (\:307e\:305f\:306f net \:3092\:518d\:751f\:6210)\:3002",
        "HandlerError",
          "Failed \:3057\:305f transition \:306e\:8a73\:7d30: inspectTokenFlow[wid, \"" <>
          If[Length[failedNames] > 0, First[failedNames], "?"] <>
          "\"]\:3002 \:591a\:304f\:306e\:5834\:5408 handler \:5185\:3067\:30ad\:30fc\:540d\:4e0d\:4e00\:81f4\:3001 " <>
          "\:307e\:305f\:306f Payload \:968e\:5c64\:62b9\:3051\:843d\:3061\:3002",
        _,
          "inspectAllTokens[wid] / listValueKeys[wid] / inspectTokenFlow[wid, \"<name>\"] \:3067\:8abf\:67fb\:3002"]
    }, Frame -> True]
  ];

(* ::Subsection:: *)
(* 7. \:53ef\:8996\:5316: \:30cd\:30c3\:30c8\:69cb\:9020\:3068\:5b9f\:884c\:30c8\:30ec\:30fc\:30b9\:306e\:30b0\:30e9\:30d5 *)

ClearAll[plotPetriNet, plotExecutionTrace, traceList,
         iExtractEdges];

(* WorkflowNet \:304b\:3089 Place \[RightArrow] Transition / Transition \[RightArrow] Place \:306e\:8fba\:3092\:62bd\:51fa *)
iExtractEdges[net_Association] :=
  Module[{transitions, edges},
    transitions = Lookup[net, "Transitions", <||>];
    edges = Flatten @ KeyValueMap[
      Function[{tname, tdef},
        Module[{inArcs, outArcs},
          inArcs = Lookup[tdef, "InputArcs", {}];
          outArcs = Lookup[tdef, "OutputArcs", {}];
          Join[
            Map[Lookup[#, "Place"] -> tname &, inArcs],
            Map[tname -> Lookup[#, "Place"] &, outArcs]]
        ]],
      transitions];
    edges
  ];

(* WorkflowNet \:3092\:30da\:30c8\:30ea\:30cd\:30c3\:30c8\:30b0\:30e9\:30d5\:3068\:3057\:3066\:63cf\:753b\:3002
   wid \:307e\:305f\:306f net Association \:306e\:3069\:3061\:3089\:3082\:53d7\:3051\:5165\:308c\:308b\:3002 *)
plotPetriNet[netOrWid_, opts:OptionsPattern[Graph]] :=
  Module[{net, places, transitions, vertices, finalPlaces, sourcePlace,
          edges, vertexLabels, vertexShapeFn, vertexStyle},
    net = If[StringQ[netOrWid],
      (* wid \:304c\:6e21\:3055\:308c\:305f\:5834\:5408 *)
      Module[{state},
        state = ClaudeWorkflowState[netOrWid];
        Lookup[state, "Net", state]],
      netOrWid];

    If[!AssociationQ[net] || !KeyExistsQ[net, "Places"],
      Print[Style["[plotPetriNet] WorkflowNet \:3068\:3057\:3066\:8a8d\:8b58\:3067\:304d\:307e\:305b\:3093\:3002", Red]];
      Return[$Failed]];

    places      = Keys @ Lookup[net, "Places",      <||>];
    transitions = Keys @ Lookup[net, "Transitions", <||>];
    (* \:91cd\:8981: \:5b64\:7acb\:9802\:70b9 (\:8fba\:3092\:6301\:305f\:306a\:3044 place / transition) \:3082\:660e\:793a\:7684\:306b\:6e21\:3059\:3002
       Graph[edges, ...] \:306e 1 \:5f15\:6570\:5f62\:5f0f\:3060\:3068\:8fba\:306b\:73fe\:308c\:308b\:9802\:70b9\:3057\:304b\:63a1\:7528\:3055\:308c\:305a\:3001
       FinalPlaces = {"Done", "Failed"} \:306e "Failed" \:306e\:3088\:3046\:306a\:5b64\:7acb place \:304c
       VertexShapeFunction / VertexLabels / VertexStyle \:3068\:4e0d\:6574\:5408\:3092\:8d77\:3053\:3057\:3001
       Graph \:5168\:4f53\:304c\:672a\:8a55\:4fa1\:306e\:307e\:307e\:6b8b\:308b (review6.nb \:3067\:5224\:660e)\:3002 *)
    vertices    = Join[places, transitions];
    sourcePlace = Lookup[net, "SourcePlace", ""];
    finalPlaces = Lookup[net, "FinalPlaces", {}];
    edges       = iExtractEdges[net];

    vertexLabels = Join[
      (# -> Placed[Style[#, 9], Center]) & /@ places,
      (# -> Placed[Style[#, Bold, White, 8], Center]) & /@ transitions];

    vertexStyle = Join[
      (# -> Directive[Lighter[Blue, 0.7], EdgeForm[Darker[Blue]]]) & /@ places,
      (# -> Directive[Darker[Red, 0.2], EdgeForm[Black]]) & /@ transitions,
      (* source / final \:306f\:8272\:3092\:5909\:3048\:308b *)
      If[sourcePlace =!= "" && MemberQ[places, sourcePlace],
        {sourcePlace -> Directive[Lighter[Yellow, 0.3], EdgeForm[Darker[Yellow]]]},
        {}],
      Map[# -> Directive[Lighter[Green, 0.5], EdgeForm[Darker[Green]]] &,
        Cases[finalPlaces, _String]]];

    vertexShapeFn = Join[
      (# -> "Circle") & /@ places,
      (* "Rectangle" \:306f Mathematica \:306e\:540d\:524d\:4ed8\:304d vertex shape \:306b\:5b58\:5728\:3057\:306a\:3044\:305f\:3081
         (\:516c\:5f0f\:30c9\:30ad\:30e5\:30e1\:30f3\:30c8: "Square", "Diamond", "ConcaveHexagon" \:306a\:3069\:306f
          \:6709\:308a\:3001"Rectangle" \:306f\:306a\:3057)\:3001"Square" \:3092\:4f7f\:7528\:3059\:308b\:3002 *)
      (# -> "Square") & /@ transitions];

    Graph[vertices, edges,
      VertexLabels        -> vertexLabels,
      VertexStyle         -> vertexStyle,
      VertexShapeFunction -> vertexShapeFn,
      VertexSize          -> {"Scaled", 0.05},
      EdgeStyle           -> Directive[Gray, Arrowheads[0.022]],
      ImageSize           -> 850,
      PlotLabel           -> Style[
        ToString[Length[places]] <> " places, " <>
        ToString[Length[transitions]] <> " transitions  " <>
        "(\:9ec4=Source / \:7dd1=Final / \:9752=Place / \:8d64=Transition)",
        13, Bold],
      opts]
  ];

(* \:5b9f\:884c\:30c8\:30ec\:30fc\:30b9\:3092\:6642\:7cfb\:5217\:30b0\:30e9\:30d5\:3067\:8868\:793a\:3002
   wid \:307e\:305f\:306f trace List \:307e\:305f\:306f summary Association \:3092\:53d7\:3051\:4ed8\:3051\:308b\:3002 *)
plotExecutionTrace[input_, opts:OptionsPattern[Graph]] :=
  Module[{trace, fired, edges, lbl, vstyles},
    trace = Which[
      StringQ[input],          ClaudeWorkflowTrace[input],
      ListQ[input],            input,
      AssociationQ[input],     Lookup[input, "Trace", {}],
      True,                    {}];
    
    fired = Select[trace, #[["Event"]] === "TransitionFired" &];
    If[Length[fired] === 0,
      Print[Style["[plotExecutionTrace] fired transition \:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093", Orange]];
      Return["(no trace)"]];
    
    edges = MapThread[
      DirectedEdge[
        ToString[#1] <> "-step" <> ToString[#2 - 1],
        ToString[fired[[#2, "TransitionName"]]] <> "-step" <> ToString[#2]] &,
      {Most[fired[[All, "TransitionName"]]], Range[2, Length[fired]]}];
    
    lbl = MapThread[
      (ToString[#1] <> "-step" <> ToString[#2]) -> Style[
        ToString[#2] <> ". " <> ToString[#1], 10, Bold] &,
      {fired[[All, "TransitionName"]], Range[Length[fired]]}];
    
    (* \:7279\:5fb4\:7684\:306a transition \:540d\:306b\:306f\:8272\:3092\:4ed8\:3051\:308b\:3002
       Pass / Permit / Final / Done \[RightArrow] \:7dd1\:3001
       Reject / Repair / Retry / GiveUp \[RightArrow] \:30aa\:30ec\:30f3\:30b8\:3001
       \:305d\:306e\:4ed6\:306f\:9ec4 *)
    vstyles = MapThread[
      (ToString[#1] <> "-step" <> ToString[#2]) -> Which[
        StringContainsQ[#1, "Pass"|"Permit"|"Final"|"Done"|"Accept"],
          Directive[Lighter[Green, 0.5], EdgeForm[Darker[Green]]],
        StringContainsQ[#1, "Reject"|"Repair"|"Retry"|"GiveUp"|"Fail"],
          Directive[Lighter[Orange, 0.5], EdgeForm[Darker[Orange]]],
        True,
          Directive[Lighter[Yellow, 0.6], EdgeForm[Black]]] &,
      {fired[[All, "TransitionName"]], Range[Length[fired]]}];
    
    Graph[edges,
      VertexLabels        -> lbl,
      VertexStyle         -> vstyles,
      (* "Rectangle" \:306f Mathematica \:306e\:540d\:524d\:4ed8\:304d vertex shape \:306b\:306a\:3044\:305f\:3081 "Square" \:3092\:4f7f\:7528 *)
      VertexShapeFunction -> "Square",
      VertexSize          -> {"Scaled", 0.04},
      EdgeStyle           -> Directive[Gray, Arrowheads[0.02]],
      ImageSize           -> 850,
      PlotLabel           -> Style[
        "Execution trace (" <> ToString[Length[fired]] <> " transitions fired)",
        14, Bold],
      opts]
  ];

(* \:5b9f\:884c\:30c8\:30ec\:30fc\:30b9\:3092 Dataset / Grid \:5f62\:5f0f\:3067\:8868\:8a18\:3002
   wid / trace List / summary Association \:306e\:3069\:308c\:3082\:53d7\:4ed8 *)
traceList[input_] :=
  Module[{trace, fired},
    trace = Which[
      StringQ[input],          ClaudeWorkflowTrace[input],
      ListQ[input],            input,
      AssociationQ[input],     Lookup[input, "Trace", {}],
      True,                    {}];
    
    fired = Select[trace, #[["Event"]] === "TransitionFired" &];
    If[Length[fired] === 0,
      Return[Dataset[{}]]];
    
    Dataset[
      MapIndexed[
        <|"Step"        -> First[#2],
          "Transition"  -> #1[["TransitionName"]],
          "Status"      -> Lookup[#1, "ExecutorStatus", "?"],
          "ConsumedIds" -> Lookup[#1, "ConsumedIds", {}],
          "ProducedIds" -> Lookup[#1, "ProducedIds", {}]|> &,
        fired]]
  ];


(* ============================================================
   v0.10.0 統合パート: 旧 petri_from_prompt_chatgpt.wl からの取り込み
   ============================================================ *)

ClearAll[
  $petriNetGuideExtras,
  $petriNetGuideOriginal,
  $petriANDMergeGuide,
  $petriRetryGuide,
  AddProviderSupportToPetriPrompt,
  RemoveProviderSupportFromPetriPrompt,
  AddANDMergeGuideToPetriPrompt,
  AddRetryGuideToPetriPrompt,
  iCheckWorkerHandlerIssues,
  validateWorkflowOutput,
  extractReviewsFromWorkflow,
  showHandlerTrace,
  diagnoseHandlerOutputs,
  checkLLMResponse,
  iIsLLMErrorResponse,
  iReadSkillBody,
  iResolveModelPlaceholders,
  iFindModelByProviderClass,
  iFindModelByProvider
];

(* ============================================================
   1.5  iCheckWorkerHandlerIssues
     生成コードに対する追加の静的検査:
       - Lookup[..., \"Plan\", ...] のような怪しいキー名 (Source の規約逸脱)
       - Worker handler の出力 Payload に \"Review\" / \"Score\" 系の新キーが
         追加されているか (素通し検出ヒューリスティクス)

     完全ではないが、生成コード品質を粗く measure できる。
   ============================================================ *)

ClearAll[iCheckWorkerHandlerIssues];

iCheckWorkerHandlerIssues[code_String] :=
  Module[{issues = {}, suspiciousKeys, placeNameKeys,
          hasReviewKey, hasScoreKey, hasFinalResult, hasNewKeyOutput,
          nestPattern, nestMatches},

    (* === 1. 不審な Source token キー (Plan / Input / Data) === *)
    suspiciousKeys = {"Plan", "Input", "Data"};
    Do[
      If[StringContainsQ[code,
           "Lookup[" ~~ Whitespace... ~~
           (LetterCharacter | DigitCharacter | "$").. ~~
           Whitespace... ~~ "," ~~
           Whitespace... ~~ "\"" <> key <> "\""],
        AppendTo[issues,
          "WARNING: Found Lookup[..., \"" <> key <>
          "\", ...] - the Source token's Payload key is \"Text\". " <>
          "This Lookup will return the default and the worker will produce " <>
          "an empty review."]],
      {key, suspiciousKeys}];

    (* === 2. ネスト疑い: handler が Place 名をキーにして input を埋め込んでいる ===
       result20/result21 で連発した素通しパターン。LLM は様々な経路で書く:
         <|"Payload" -> <|"PoolOpus" -> binding[["PoolOpus"]]|>|>
         <|"Payload" -> <|"PoolOpus" -> p|>|>          (* ローカル変数経由 *)
         <|"Payload" -> binding[["PoolOpus"]]|>        (* Payload 自体を token に *)
       それらをすべて捕まえるため、Place 名がキーとして「-> ...」の左に
       現れたら警告する。Place 名 = ユーザー domain key ではないので
       Payload の中に出現することは正当な理由がない。 *)
    placeNameKeys = {"PoolOpus", "PoolChatGPT", "PoolA", "PoolB", "PoolC",
                     "Source", "ResultPool", "Merged", "Verdict",
                     "Done", "GivenUp", "Plan", "Start"};
    Do[
      (* パターン a: 「"PlaceName" -> ...」が Payload 文脈に出現 *)
      If[StringContainsQ[code,
           "\"" <> key <> "\"" ~~ Whitespace... ~~ "->"],
        (* Payload 中のキーであることをさらに絞り込みたいが、
           StringExpression で文脈追跡は重いので、現れたら全部警告。
           誤検知も生じうるが、安全側に倒す。 *)
        AppendTo[issues,
          "WARNING: \"" <> key <> "\" appears as a key (\"" <> key <> "\" -> ...) " <>
          "somewhere in the code. Place names should NEVER be Payload keys. " <>
          "Use Append[oldPayload, \"DomainKey\" -> value] (e.g. \"ReviewOpus\", \"Text\") instead."]],
      {key, placeNameKeys}];

    (* パターン b: 「<|"Payload" -> binding[[...]]|>」または「<|"Payload" -> someVar|>」
       で Payload を直接 token / 局所変数に置き換えてしまう *)
    If[StringContainsQ[code,
         "\"Payload\"" ~~ Whitespace... ~~ "->" ~~ Whitespace... ~~ "binding[["],
      AppendTo[issues,
        "WARNING: Found <|\"Payload\" -> binding[[...]]|> - " <>
        "this assigns the entire input token to Payload. " <>
        "Use <|\"Payload\" -> Append[oldPayload, \"NewKey\" -> newValue]|> instead."]];

    (* === 3. 出力 Payload に Review/Score/Verdict/FinalResult 系の新キーがあるか === *)
    hasReviewKey = StringContainsQ[code, "\"Review" ~~ LetterCharacter..];
    hasScoreKey  = StringContainsQ[code, "\"Score"  ~~ LetterCharacter..];
    hasFinalResult = StringContainsQ[code, "\"FinalResult\""];
    hasNewKeyOutput = hasReviewKey || hasScoreKey || hasFinalResult ||
      StringContainsQ[code, "\"Verdict\""];

    If[!hasNewKeyOutput,
      AppendTo[issues,
        "WARNING: No new output key (Review*, Score*, Verdict, FinalResult) " <>
        "detected. Worker handlers may be passing input through unchanged."]];

    (* === 4. FinalResult が必須 (規約) === *)
    If[!hasFinalResult,
      AppendTo[issues,
        "WARNING: \"FinalResult\" key not found in code. " <>
        "The Finalize transition MUST produce a Payload with \"FinalResult\" key " <>
        "(convention rule g)."]];

    (* === 5. Append[oldPayload, ...] パターンが見えるか === *)
    If[!StringContainsQ[code, "Append["],
      AppendTo[issues,
        "WARNING: No Append[...] call detected in handlers. " <>
        "Worker / Finalize handlers should use Append[oldPayload, \"NewKey\" -> newValue] " <>
        "to add fields to the Payload without nesting."]];

    issues
  ];
iCheckWorkerHandlerIssues[_] := {};

(* ============================================================
   2. $petriNetGuideExtras: Provider 指定方法のガイド文字列

   このガイド文字列は Claude Directives の skill から動的に読み込む
   (rules/02-llm-instructions-not-in-source.md 準拠)。
   .wl にハードコードしないことで、生成プロンプトの保守性を高める。

   読み込み元:
     <directives>/skills/petri-multi-provider-generation/SKILL.md

   skill が見つからない / ロード失敗時は AddProviderSupportToPetriPrompt[]
   が警告メッセージ付きで dummy 文字列を $petriNetGuide に追加する。
   ============================================================ *)

(* iReadSkillBody: Claude Directives の skill 本体 (frontmatter 除く) を
   文字列で取得する helper。
   Directives ディレクトリの解決は ClaudeDirectives`ClaudeFindDirectiveRoots[]
   に完全委譲し、Global コンテキストのシンボルを直接参照しない
   (シンボル shadowing 警告 General::shdw 回避)。 *)
iReadSkillBody[skillName_String] :=
  Module[{roots, candidates, path, body},
    roots = If[
        StringQ[Quiet[Context[ClaudeDirectives`ClaudeFindDirectiveRoots]]] &&
        Context[ClaudeDirectives`ClaudeFindDirectiveRoots] === "ClaudeDirectives`",
      Quiet[ClaudeDirectives`ClaudeFindDirectiveRoots[]],
      {}
    ];
    If[!ListQ[roots], roots = {}];
    candidates =
      Map[FileNameJoin[{#, "skills", skillName, "SKILL.md"}] &, roots];
    path = SelectFirst[candidates, FileExistsQ, None];
    If[path === None,
      Return["[skill " <> skillName <> " not found in directive roots: " <>
        ToString[roots] <> "]"]];
    body = Quiet[Import[path, "String"]];
    If[!StringQ[body],
      Return["[skill " <> skillName <> " load failed at " <> path <> "]"]];
    (* frontmatter (--- ... ---) を除去 *)
    StringReplace[body,
      RegularExpression["(?s)\\A---.*?---\\s*"] -> "", 1]
  ];

iReadSkillBody[_] := "[iReadSkillBody: invalid argument]";

(* ============================================================
   2a-bis. iResolveModelPlaceholders[text]
     skill 本文に含まれる model placeholder を $ClaudeModelCapabilities
     の現状を見て実際のモデル名に置換する。

     対応 placeholder (skill 側と必ず整合させる):
       <anthropic-heavy>   -> Provider="anthropic", Class="Heavy-Cloud" の最初のキー
       <anthropic-mid>     -> Provider="anthropic", Class="Mid-Cloud" の最初のキー
       <anthropic-light>   -> Provider="anthropic", Class="Light-Cloud" の最初のキー
       <openai-heavy>      -> Provider="openai",    Class="Heavy-Cloud" の最初のキー
       <openai-mid>        -> Provider="openai",    Class="Mid-Cloud" の最初のキー
       <openai-light>      -> Provider="openai",    Class="Light-Cloud" の最初のキー
       <lmstudio-default>  -> Provider="lm-studio" の最初のキー (Class 不問)

     この層で動的解決することにより:
       (a) .wl にも skill にもモデル枝番をハードコードしない
           (rules/02-llm-instructions-not-in-source.md 準拠)
       (b) Imai 先生が claudecode_directives.wl の $ClaudeModelCapabilities
           を更新すれば、次の AddProviderSupportToPetriPrompt[] 呼び出しで
           最新モデル名が生成プロンプトに反映される
       (c) 解決失敗 (該当 Capability が無い) 時は placeholder を残して警告
           を出す。生成 LLM が placeholder を見れば「設定ミスでは?」と気付く
           手がかりになる。
   ============================================================ *)

(* 内部: provider と class で Capability テーブルを引いてモデル名を返す。
   $ClaudeModelCapabilities は ClaudeDirectives` パッケージで Public 宣言されている
   (Global` ではない)。Global` を参照すると未定義扱いになり、placeholder 解決が
   全て失敗する (v0.10.0 でこのバグを修正)。 *)
(* Phase 28 (2026-05-12): $ClaudeModelCapabilities が tuple キー {provider, model} 形式になった。
   iFindModelByProviderClass / iFindModelByProvider は **model 部分の文字列だけ** を返す。
   placeholder 解決はその文字列を使って Model -> {provider, "<resolved>"} の形に組み立てる。 *)
iFindModelByProviderClass[provider_String, class_String] :=
  Module[{caps, keys, matchedKey},
    caps = If[ValueQ[ClaudeDirectives`$ClaudeModelCapabilities] &&
              AssociationQ[ClaudeDirectives`$ClaudeModelCapabilities],
      ClaudeDirectives`$ClaudeModelCapabilities, <||>];
    keys = Keys[caps];
    (* {provider, model} 形式のキーで、provider が一致し、値の Class が一致するもの *)
    matchedKey = SelectFirst[keys,
      Function[k,
        MatchQ[k, {_String, _String}] &&
        k[[1]] === provider &&
        AssociationQ[caps[k]] &&
        Lookup[caps[k], "Class", ""] === class
      ],
      Missing[]];
    If[MissingQ[matchedKey], Missing[], matchedKey[[2]]]
  ];

(* 内部: provider のみで引く (Class 指定なし、LM Studio など) *)
iFindModelByProvider[provider_String] :=
  Module[{caps, keys, matchedKey},
    caps = If[ValueQ[ClaudeDirectives`$ClaudeModelCapabilities] &&
              AssociationQ[ClaudeDirectives`$ClaudeModelCapabilities],
      ClaudeDirectives`$ClaudeModelCapabilities, <||>];
    keys = Keys[caps];
    matchedKey = SelectFirst[keys,
      Function[k,
        MatchQ[k, {_String, _String}] &&
        k[[1]] === provider
      ],
      Missing[]];
    If[MissingQ[matchedKey], Missing[], matchedKey[[2]]]
  ];

iResolveModelPlaceholders[text_String] :=
  Module[{result = text, unresolved = {},
          tryReplace, placeholderMap},
    (* Phase 28 (2026-05-12): claudecode 系 placeholder を追加。
       課金なしを希望する場合は <claudecode-*>、課金 API 直接を希望する場合は
       <anthropic-*> を使う。<lmstudio-default> は LM Studio (ローカル、課金なし)。
       <openai-*> は OpenAI API (課金あり、NBAccess 許可必要)。 *)
    placeholderMap = {
      "<claudecode-heavy>"  -> iFindModelByProviderClass["claudecode", "Heavy-Cloud"],
      "<claudecode-mid>"    -> iFindModelByProviderClass["claudecode", "Mid-Cloud"],
      "<claudecode-light>"  -> iFindModelByProviderClass["claudecode", "Light-Cloud"],
      "<anthropic-heavy>"   -> iFindModelByProviderClass["anthropic", "Heavy-Cloud"],
      "<anthropic-mid>"     -> iFindModelByProviderClass["anthropic", "Mid-Cloud"],
      "<anthropic-light>"   -> iFindModelByProviderClass["anthropic", "Light-Cloud"],
      "<openai-heavy>"      -> iFindModelByProviderClass["openai",    "Heavy-Cloud"],
      "<openai-mid>"        -> iFindModelByProviderClass["openai",    "Mid-Cloud"],
      "<openai-light>"      -> iFindModelByProviderClass["openai",    "Light-Cloud"],
      "<lmstudio-default>"  -> iFindModelByProvider["lmstudio"]
    };
    Do[
      Module[{ph = pair[[1]], resolved = pair[[2]]},
        If[StringContainsQ[result, ph],
          If[StringQ[resolved],
            result = StringReplace[result, ph -> resolved],
            (* 解決失敗: placeholder を残してリストに記録 *)
            AppendTo[unresolved, ph]
          ]
        ]
      ],
      {pair, placeholderMap}];
    If[Length[unresolved] > 0,
      Print[Style[
        "[iResolveModelPlaceholders] \:6b21\:306e placeholder \:3092\:89e3\:6c7a\:3067\:304d\:307e\:305b\:3093\:3067\:3057\:305f: " <>
        StringRiffle[unresolved, ", "],
        Darker[Yellow]]];
      Print[Style[
        "  ClaudeDirectives`$ClaudeModelCapabilities \:306b " <>
        "\:8a72\:5f53\:3059\:308b Provider + Class \:306e\:30a8\:30f3\:30c8\:30ea\:304c\:5b58\:5728\:3057\:307e\:3059\:304b\:ff1f",
        Gray]];
      Print[Style[
        "  \:78ba\:8a8d\:65b9\:6cd5: " <>
        "Keys[ClaudeDirectives`$ClaudeModelCapabilities] / " <>
        "Length[ClaudeDirectives`$ClaudeModelCapabilities]",
        Gray]];
      If[!ValueQ[ClaudeDirectives`$ClaudeModelCapabilities],
        Print[Style[
          "  WARNING: ClaudeDirectives`$ClaudeModelCapabilities \:304c\:672a\:5b9a\:7fa9\:3067\:3059\:3002 " <>
          "claudecode_directives.wl \:3092\:5148\:306b\:30ed\:30fc\:30c9\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
          Red]]]
    ];
    result
  ];

iResolveModelPlaceholders[_] := "[iResolveModelPlaceholders: non-string]";

(* $petriNetGuideExtras: skill 読み込み + placeholder 解決 を組み合わせる。
   SetDelayed なので AddProviderSupportToPetriPrompt[] 呼び出し時に毎回
   最新の $ClaudeModelCapabilities が反映される。 *)
$petriNetGuideExtras :=
  iResolveModelPlaceholders @ iReadSkillBody["petri-multi-provider-generation"];

(* ============================================================
   2b. checkLLMResponse / iIsLLMErrorResponse helper

   handler 内で API エラー応答 ("Error: model: ..." 等) を通常の LLM
   応答と区別して $Failed に変換するための helper。
   生成プロンプト (skill petri-multi-provider-generation の P5) で必須。

   生成コードでの使い方 (モデル名は placeholder 解決で実モデル名に変わる):
     review = checkLLMResponse @ ClaudeCode`ClaudeQueryBg[
       prompt, "Model" -> {"openai", "<openai-heavy>"}];
     If[review === $Failed, Return[$Failed, Module]];

   エラー判定パターン:
     - "Error:" / "[Error]" / "[ClaudeQuery error" / "[ClaudeQueryBg error" /
       "$Failed" で始まる文字列
     - JSON エラー応答 ({"error": ...})
     - 空文字列
     - 短い応答 (< 120 文字) に "error" を含む
   ============================================================ *)

iIsLLMErrorResponse[response_] :=
  Module[{s},
    s = response;
    Which[
      !StringQ[s],                                     False,
      StringLength[s] === 0,                           True,
      StringStartsQ[s, "Error:"],                      True,
      StringStartsQ[s, "[Error]"],                     True,
      StringStartsQ[s, "[ClaudeQuery error"],          True,
      StringStartsQ[s, "[ClaudeQueryBg error"],        True,
      StringStartsQ[s, "$Failed"],                     True,
      StringMatchQ[s,
        RegularExpression["(?is)^\\s*\\{[^}]*\"error\"[^}]*\\}.*"]],
                                                       True,
      StringLength[s] < 120 &&
        StringContainsQ[s, "error", IgnoreCase -> True], True,
      True,                                            False
    ]
  ];

iIsLLMErrorResponse[_] := False;

checkLLMResponse::llmerr =
  "LLM response indicates failure: ``";

checkLLMResponse[response_] :=
  If[iIsLLMErrorResponse[response],
    (Message[checkLLMResponse::llmerr,
       If[StringQ[response],
         StringTake[response, UpTo[200]],
         ToString[Short[response, 200]]]];
     $Failed),
    response];


(* ============================================================
   3. AddProviderSupportToPetriPrompt[]
     $petriNetGuide に $petriNetGuideExtras を追記する。
     一度だけ追記するため、既に追記済みなら何もしない。
   ============================================================ *)

AddProviderSupportToPetriPrompt[] :=
  Module[{extras},
    If[!ValueQ[$petriNetGuide] || !StringQ[$petriNetGuide],
      Print[Style["[AddProviderSupportToPetriPrompt] $petriNetGuide が未定義。" <>
        " petri_from_prompt.wl を先に Get してください。", Red]];
      Return[$Failed]];

    If[!ValueQ[$petriNetGuideOriginal],
      $petriNetGuideOriginal = $petriNetGuide];

    If[StringContainsQ[$petriNetGuide, "# Provider selection for LLM calls"],
      Print[Style["[AddProviderSupportToPetriPrompt] 既に追記済みです。", Darker[Yellow]]];
      Return["AlreadyAdded"]];

    extras = $petriNetGuideExtras;
    If[!StringQ[extras] || StringStartsQ[extras, "[skill "],
      Print[Style["[AddProviderSupportToPetriPrompt] skill 'petri-multi-provider-generation' " <>
        "の読み込みに失敗しました: " <> ToString[extras], Red]];
      Print[Style["  ClaudeDirectives`ClaudeFindDirectiveRoots[] が返した " <>
        "ディレクトリの skills/ 配下にこの skill が配置されているか確認してください。",
        Darker[Yellow]]];
      Return[$Failed]];

    $petriNetGuide = $petriNetGuide <> "\n\n" <> extras;
    Print[Style["[AddProviderSupportToPetriPrompt] $petriNetGuide に skill " <>
      "'petri-multi-provider-generation' から Provider 指定方法を追記しました。",
      Darker[Green]]];
    Print["  追記後の長さ: " <> ToString[StringLength[$petriNetGuide]] <> " chars"];
    Print["  元に戻す場合: RemoveProviderSupportFromPetriPrompt[]"];
    "Added"
  ];

(* ============================================================
   3b. AddANDMergeGuideToPetriPrompt[]
     $petriNetGuide に skills/petri-and-xor-merge から AND-merge / XOR-merge
     の選択指針を追記する。

     一度だけ追記するため、既に追記済みなら何もしない。
     skill 'petri-and-xor-merge' が見つからない場合は警告を出す。

     使い分け:
       - peer review (複数査読者の総合判断) や ensemble は AND-merge
       - 冗長系 (どれか一つ届けば良い) は XOR-merge

     既存の Aggregate 推奨 (Multiplicity = N) と矛盾しないが、より
     明示的に AND-distribute / AND-merge / XOR-distribute / XOR-merge の
     4 パターンを示す追加ガイド。
   ============================================================ *)

(* SetDelayed で skill 読み込みに切替。Get 時点では skill が無くても OK。 *)
$petriANDMergeGuide := iReadSkillBody["petri-and-xor-merge"];

AddANDMergeGuideToPetriPrompt[] :=
  Module[{guide},
    If[!ValueQ[$petriNetGuide] || !StringQ[$petriNetGuide],
      Print[Style["[AddANDMergeGuideToPetriPrompt] $petriNetGuide が未定義。" <>
        " petri_from_prompt.wl を先に Get してください。", Red]];
      Return[$Failed]];

    If[!ValueQ[$petriNetGuideOriginal],
      $petriNetGuideOriginal = $petriNetGuide];

    If[StringContainsQ[$petriNetGuide, "# AND-merge vs XOR-merge in Petri nets"],
      Print[Style["[AddANDMergeGuideToPetriPrompt] 既に追記済みです。", Darker[Yellow]]];
      Return["AlreadyAdded"]];

    guide = $petriANDMergeGuide;
    If[!StringQ[guide] || StringStartsQ[guide, "[skill "],
      Print[Style["[AddANDMergeGuideToPetriPrompt] skill 'petri-and-xor-merge' " <>
        "の読み込みに失敗しました: " <> ToString[guide], Red]];
      Print[Style["  ClaudeDirectives`ClaudeFindDirectiveRoots[] が返した " <>
        "ディレクトリの skills/ 配下にこの skill が配置されているか確認してください。",
        Darker[Yellow]]];
      Return[$Failed]];

    $petriNetGuide = $petriNetGuide <> "\n\n" <> guide;
    Print[Style["[AddANDMergeGuideToPetriPrompt] $petriNetGuide に skill " <>
      "'petri-and-xor-merge' から AND/XOR merge 指針を追記しました。",
      Darker[Green]]];
    Print["  追記後の長さ: " <> ToString[StringLength[$petriNetGuide]] <> " chars"];
    Print["  元に戻す場合: RemoveProviderSupportFromPetriPrompt[] を呼ぶか、" <>
      "$petriNetGuide を再ロードしてください。"];
    "Added"
  ];

(* ============================================================
   3c. AddRetryGuideToPetriPrompt[]
     $petriNetGuide に skills/petri-retry-patterns から retry 配線指針を
     追記する。

     一度だけ追記するため、既に追記済みなら何もしない。
     skill 'petri-retry-patterns' が見つからない場合は警告を出す。

     背景: review.nb で観測された問題。LLM が retry transition を Merge の
     下流 (Verdict から分岐) に配置してしまい、AND-merge と組み合わさって
     「片方の Worker が失敗すると Merge が永遠に enabled せず Retry も
     起動しない」という構造的バグを再現性高く生成する。

     対策: retry のための per-worker パターンと、Verdict 下流 retry を
     使うべきかの判定指針を skill 化。
   ============================================================ *)

(* SetDelayed で skill 読み込みに切替 *)
$petriRetryGuide := iReadSkillBody["petri-retry-patterns"];

AddRetryGuideToPetriPrompt[] :=
  Module[{guide},
    If[!ValueQ[$petriNetGuide] || !StringQ[$petriNetGuide],
      Print[Style["[AddRetryGuideToPetriPrompt] $petriNetGuide が未定義。" <>
        " petri_from_prompt.wl を先に Get してください。", Red]];
      Return[$Failed]];

    If[!ValueQ[$petriNetGuideOriginal],
      $petriNetGuideOriginal = $petriNetGuide];

    If[StringContainsQ[$petriNetGuide,
        "# Retry pattern selection in fan-out parallel review nets"],
      Print[Style["[AddRetryGuideToPetriPrompt] 既に追記済みです。",
        Darker[Yellow]]];
      Return["AlreadyAdded"]];

    guide = $petriRetryGuide;
    If[!StringQ[guide] || StringStartsQ[guide, "[skill "],
      Print[Style["[AddRetryGuideToPetriPrompt] skill 'petri-retry-patterns' " <>
        "の読み込みに失敗しました: " <> ToString[guide], Red]];
      Print[Style["  ClaudeDirectives`ClaudeFindDirectiveRoots[] が返した " <>
        "ディレクトリの skills/ 配下にこの skill が配置されているか確認してください。",
        Darker[Yellow]]];
      Return[$Failed]];

    $petriNetGuide = $petriNetGuide <> "\n\n" <> guide;
    Print[Style["[AddRetryGuideToPetriPrompt] $petriNetGuide に skill " <>
      "'petri-retry-patterns' から retry 配線指針を追記しました。",
      Darker[Green]]];
    Print["  追記後の長さ: " <> ToString[StringLength[$petriNetGuide]] <> " chars"];
    Print["  元に戻す場合: RemoveProviderSupportFromPetriPrompt[] を呼ぶか、" <>
      "$petriNetGuide を再ロードしてください。"];
    "Added"
  ];

(* ============================================================
   RemoveProviderSupportFromPetriPrompt[]
     $petriNetGuide を元の状態に戻す。
   ============================================================ *)

RemoveProviderSupportFromPetriPrompt[] :=
  Module[{},
    If[!ValueQ[$petriNetGuideOriginal] || !StringQ[$petriNetGuideOriginal],
      Print[Style["[RemoveProviderSupportFromPetriPrompt] バックアップが存在しません。", Red]];
      Return[$Failed]];

    $petriNetGuide = $petriNetGuideOriginal;
    Print[Style["[RemoveProviderSupportFromPetriPrompt] $petriNetGuide を元に戻しました。",
      Darker[Green]]];
    "Removed"
  ];

(* ============================================================
   5. validateWorkflowOutput[wid]
     完走した workflow の最終 token を解析し、
     - FinalResult キーを持つ token があるか
     - Payload に Place 名キー (ネスト疑い) が混入していないか
     - 期待されるレビューキー (ReviewOpus, ReviewChatGPT 等) があるか
     を動的検査する。proposal 段階の静的検査ではすり抜けるパターンを
     実行後に確実に検出する。
   ============================================================ *)

Options[validateWorkflowOutput] = {
  "ExpectedReviewKeys" -> Automatic,
  "PlaceNameKeys" -> Automatic
};

validateWorkflowOutput[wid_String, opts:OptionsPattern[]] :=
  Module[{state, tokens, finalToks, issues = {},
          payloads, placeKeys, expectedKeys, placeKeyHits,
          finalResultToks},

    state = Quiet[ClaudeWorkflowState[wid]];
    If[!AssociationQ[state],
      Return[<|"Status" -> "NoState",
               "Issues" -> {"ClaudeWorkflowState returned non-Association"}|>]];

    tokens = Lookup[state, "Tokens", <||>];
    If[Length[tokens] === 0,
      Return[<|"Status" -> "NoTokens",
               "Issues" -> {"No tokens in workflow state"}|>]];

    placeKeys = OptionValue["PlaceNameKeys"];
    If[placeKeys === Automatic,
      placeKeys = {"PoolOpus", "PoolChatGPT", "PoolA", "PoolB", "PoolC",
                   "Source", "ResultPool", "Merged", "Verdict",
                   "Done", "GivenUp", "Plan", "Start"}];

    expectedKeys = OptionValue["ExpectedReviewKeys"];
    If[expectedKeys === Automatic, expectedKeys = {}];

    (* 全 token の Payload を順に検査 *)
    payloads = Map[Lookup[#, "Payload", <||>] &, Values[tokens]];
    payloads = Select[payloads, AssociationQ];

    (* 検査 1: Place 名キーが Payload に混入しているか (ネスト疑い) *)
    placeKeyHits = {};
    Do[
      If[KeyExistsQ[p, key],
        AppendTo[placeKeyHits, key]],
      {p, payloads}, {key, placeKeys}];
    placeKeyHits = DeleteDuplicates[placeKeyHits];

    If[Length[placeKeyHits] > 0,
      AppendTo[issues,
        "Place-name keys found in token Payloads: " <>
        StringRiffle[placeKeyHits, ", "] <>
        " (handler nesting bug — input tokens are nested under Place-name keys)"]];

    (* 検査 2: FinalResult を持つ token *)
    finalResultToks = Select[payloads, KeyExistsQ[#, "FinalResult"] &];
    If[Length[finalResultToks] === 0,
      AppendTo[issues,
        "No token has \"FinalResult\" key. Finalize transition did not produce the expected key."]];

    (* 検査 3: 期待されるレビューキー *)
    Do[
      If[!AnyTrue[payloads, KeyExistsQ[#, key] &] &&
         (Length[finalResultToks] === 0 ||
          !AnyTrue[finalResultToks,
            KeyExistsQ[Lookup[#, "FinalResult", <||>], key] &]),
        AppendTo[issues,
          "Expected review key \"" <> key <> "\" not found anywhere in Payload tree"]],
      {key, expectedKeys}];

    <|"Status" -> If[Length[issues] === 0, "OK", "Issues"],
      "Issues" -> issues,
      "PlaceKeyHits" -> placeKeyHits,
      "FinalResultTokenCount" -> Length[finalResultToks],
      "TotalTokenCount" -> Length[payloads]|>
  ];

(* ============================================================
   6. extractReviewsFromWorkflow[wid]
     handler がネストして埋めた token であっても、深さに関係なく
     特定のキー (ReviewOpus 等) を payload tree から再帰的に探して取り出す。
     これは「LLM が変なコードを生成しても、レビュー結果は捨てない」ための
     防御的取り出し。
   ============================================================ *)

Options[extractReviewsFromWorkflow] = {
  "Keys" -> Automatic
};

extractReviewsFromWorkflow[wid_String, opts:OptionsPattern[]] :=
  Module[{state, tokens, payloads, keys, found,
          searchInAssoc, allReviewKeys},

    keys = OptionValue["Keys"];
    If[keys === Automatic,
      keys = {"ReviewOpus", "ReviewChatGPT", "ReviewSonnet",
              "ReviewClaude", "ReviewGPT", "ReviewLlama",
              "ScoreOpus", "ScoreChatGPT",
              "FinalResult"}];

    state = Quiet[ClaudeWorkflowState[wid]];
    If[!AssociationQ[state], Return[<||>]];

    tokens = Lookup[state, "Tokens", <||>];
    payloads = Map[Lookup[#, "Payload", <||>] &, Values[tokens]];

    (* Payload tree を深さ優先で再帰探索し、指定キーを集める *)
    searchInAssoc[a_Association, depth_Integer] :=
      Module[{collected = <||>, v},
        If[depth > 8, Return[<||>]];   (* 深さ上限 *)
        Do[
          If[KeyExistsQ[a, k] && !MissingQ[a[[k]]] &&
             !AssociationQ[a[[k]]] && !ListQ[a[[k]]],
            collected[k] = a[[k]]],
          {k, keys}];
        Do[
          v = a[[k]];
          If[AssociationQ[v],
            collected = Join[collected, searchInAssoc[v, depth + 1]];
            ,
            If[ListQ[v],
              Do[
                If[AssociationQ[item],
                  collected = Join[collected, searchInAssoc[item, depth + 1]]],
                {item, v}]
            ]
          ],
          {k, Keys[a]}];
        collected
      ];
    searchInAssoc[other_, _] := <||>;

    found = <||>;
    Do[
      If[AssociationQ[p],
        found = Join[found, searchInAssoc[p, 0]]],
      {p, payloads}];

    found
  ];

(* ============================================================
   7. showHandlerTrace[] / showHandlerTrace[transName]
     ClaudeOrchestrator`Workflow`$iHandlerTraceLog (本体 patch で導入) を
     人間が読みやすい Dataset で表示する。
     LLM 呼び出しが何を返したか、handler が何を出力したかを直接観察できる。

     Imai 先生指摘:「LLMにプロンプトを送ったら、返り値はほぼ100%あるはずなので、
                    それを失っているのは明らかにおかしい」
     -> 本体 iExecutePureFunction を罠 #16 修正版に直し、handler の戻り値と
        評価中メッセージを $iHandlerTraceLog に記録するようにした。
        この API でその記録を見る。
   ============================================================ *)

ClearAll[showHandlerTrace];

showHandlerTrace[] :=
  Module[{traces},
    traces = If[ValueQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog] &&
                ListQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog],
              ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog,
              {}];
    If[Length[traces] === 0,
      Print[Style["[showHandlerTrace] handler trace ログは空です。", Orange]];
      Print["  ClaudeOrchestrator_workflow.wl が罠 #16 修正版 (2026-05-09 patch) " <>
            "になっているか確認してください。"];
      Return[$Failed]];

    Dataset[
      Map[
        Function[t,
          <|"Transition"   -> Lookup[t, "TransitionName", "?"],
            "OutputAssoc?" -> Lookup[t, "OutputAssocQ", False],
            "OutputHead"   -> ToString[Lookup[t, "OutputHead", Missing[]]],
            "PayloadKeys"  ->
              Module[{p = Lookup[t, "OutputPayload", $NotProvided]},
                If[AssociationQ[p], Keys[p], "<no Payload key>"]],
            "FailedHead"   -> Lookup[t, "FailedHead", False],
            "Messages"     -> ToString[Length[Lookup[t, "Messages", {}]]] <> " msg(s)"
          |>],
        traces]
    ]
  ];

showHandlerTrace[transName_String] :=
  Module[{traces, filtered},
    traces = If[ValueQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog] &&
                ListQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog],
              ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog,
              {}];
    filtered = Select[traces, Lookup[#, "TransitionName", ""] === transName &];
    If[Length[filtered] === 0,
      Print[Style["[showHandlerTrace] transition \"" <> transName <>
            "\" の trace なし", Orange]];
      Return[$Failed]];

    (* 詳細表示: 1 件ずつ Pretty Print *)
    Column[
      Map[
        Function[t,
          Column[{
            Style["=== " <> Lookup[t, "TransitionName", "?"] <>
                  " (" <> DateString[Lookup[t, "Time", AbsoluteTime[]]] <> ") ===",
                  Bold, Darker[Blue]],
            Style["Binding payloads:", Bold],
            Lookup[t, "BindingPayloads", <||>],
            "",
            Style["Output (raw):", Bold],
            Short[Lookup[t, "OutputRaw", $NotProvided], 5],
            "",
            Style["Output Payload:", Bold],
            Short[Lookup[t, "OutputPayload", $NotProvided], 5],
            "",
            If[Length[Lookup[t, "Messages", {}]] > 0,
              Column[{
                Style["Evaluation messages (suppressed by Quiet):", Bold, Red],
                Lookup[t, "Messages", {}]}],
              ""],
            ""
          }, Frame -> All]],
        filtered]
    ]
  ];

(* ============================================================
   8. diagnoseHandlerOutputs[]
     全 handler trace を見て、LLM 呼び出し結果が捨てられている疑いを
     自動診断する。
   ============================================================ *)

ClearAll[diagnoseHandlerOutputs];

diagnoseHandlerOutputs[] :=
  Module[{traces, issues = {}, byTransition, llmHandlerSuspects},

    traces = If[ValueQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog] &&
                ListQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog],
              ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog,
              {}];

    If[Length[traces] === 0,
      Return[<|"Status" -> "NoTraces",
               "Issues" -> {"handler trace ログが空です"}|>]];

    (* 検査 1: handler が $Failed Head の出力を出していないか *)
    Do[
      If[TrueQ[Lookup[t, "FailedHead", False]],
        AppendTo[issues,
          "transition \"" <> Lookup[t, "TransitionName", "?"] <>
          "\" の handler が $Failed や Hold[...] を返した。" <>
          " trap #16 (Quiet@Check) または handler 内部例外。"]],
      {t, traces}];

    (* 検査 2: 出力 Payload に新キーが無く binding と同じ *)
    Do[
      Module[{outPayload, bindingPayloads, allBindingKeys, outKeys},
        outPayload = Lookup[t, "OutputPayload", $NotProvided];
        bindingPayloads = Lookup[t, "BindingPayloads", <||>];
        If[AssociationQ[outPayload] && AssociationQ[bindingPayloads],
          allBindingKeys = Flatten[Map[
            If[AssociationQ[#], Keys[#], {}] &,
            Values[bindingPayloads]]];
          outKeys = Keys[outPayload];
          (* 出力 Payload が完全に input の subset ならレビュー結果なし疑い *)
          If[Length[Complement[outKeys, allBindingKeys]] === 0 &&
             Length[outKeys] > 0,
            AppendTo[issues,
              "transition \"" <> Lookup[t, "TransitionName", "?"] <>
              "\" の出力 Payload に新キーが無い (input keys = output keys: " <>
              StringRiffle[outKeys, ", "] <>
              ")。worker handler が LLM 呼び出し結果を捨てた疑い。"]]
        ]
      ],
      {t, traces}];

    (* 検査 3: Messages が記録されている (handler 内で例外が発生したかも) *)
    Do[
      Module[{msgs = Lookup[t, "Messages", {}]},
        If[Length[msgs] > 0,
          AppendTo[issues,
            "transition \"" <> Lookup[t, "TransitionName", "?"] <>
            "\" で評価中に " <> ToString[Length[msgs]] <>
            " 件のメッセージが発生 (Quiet で抑制された)。" <>
            " showHandlerTrace[\"" <> Lookup[t, "TransitionName", "?"] <>
            "\"] で詳細確認。"]
        ]
      ],
      {t, traces}];

    <|"Status"           -> If[Length[issues] === 0, "OK", "Issues"],
      "Issues"           -> issues,
      "TransitionsTraced" -> DeleteDuplicates[Map[Lookup[#, "TransitionName", "?"] &, traces]],
      "TraceCount"       -> Length[traces]|>
  ];

(* ::Subsection:: *)
(* 8. \:30a8\:30f3\:30c8\:30ea\:30dd\:30a4\:30f3\:30c8 *)

Print[Style["petri_from_prompt v0.10.0 \:304c\:30ed\:30fc\:30c9\:3055\:308c\:307e\:3057\:305f (\:7d71\:5408\:7248)\:3002", Bold]];
Print["  \:65e7 petri_from_prompt_chatgpt.wl \:306f\:672c\:30d5\:30a1\:30a4\:30eb\:306b\:30de\:30fc\:30b8\:3055\:308c\:307e\:3057\:305f\:3002"];
Print["  - proposePetriNet[goal, \"Providers\" -> {...}] (\:65e7 ...WithProvider \:3082\:4e92\:63db stub \:3042\:308a)"];
Print["  - parsePetriCode \:306f Trap #16 \:4fee\:6b63\:7248 + fallback \:7d4c\:8def"];
Print["  - AddProviderSupportToPetriPrompt[] / AddANDMergeGuideToPetriPrompt[] / AddRetryGuideToPetriPrompt[] (skill \:8aad\:307f\:8fbc\:307f)"];
Print["  - validateWorkflowOutput[wid] / extractReviewsFromWorkflow[wid] (\:52d5\:7684\:691c\:67fb)"];
Print["  - showHandlerTrace[] / diagnoseHandlerOutputs[] (handler \:73fe\:72b6\:53ef\:8996\:5316)"];
Print["  - checkLLMResponse / iIsLLMErrorResponse (LLM \:30a8\:30e9\:30fc\:5fdc\:7b54\:691c\:51fa)"];
Print[""];
Print["
\:81ea\:7136\:8a00\:8a9e\:30d7\:30ed\:30f3\:30d7\:30c8\:304b\:3089\:30da\:30c8\:30ea\:30cd\:30c3\:30c8\:3092\:69cb\:6210\:30fb\:5b9f\:884c\:3059\:308b API:

  proposePetriNet[\"goal\"]            \[RightArrow] \:30b3\:30fc\:30c9\:751f\:6210 (\:81ea\:52d5\:518d\:751f\:6210\:30eb\:30fc\:30d7\:6700\:5927 3 \:56de\:3001single-provider \:30e2\:30fc\:30c9)
  proposePetriNet[\"goal\", \"Providers\" -> {\"anthropic\", \"openai\"}, \"InputPayloadKeys\" -> {\"Text\"}]
                                      \[RightArrow] multi-provider \:30e2\:30fc\:30c9 (\:65e7 proposePetriNetWithProvider \:30b3\:30fc\:30b9)
  reviewPetriProposal[\"goal\"]        \[RightArrow] \:30b3\:30fc\:30c9\:30ec\:30d3\:30e5\:30fc
  parsePetriCode[code]                \[RightArrow] \:30b3\:30fc\:30c9 \[RightArrow] WorkflowNet
  runPetriFromPrompt[\"goal\"]         \[RightArrow] \:751f\:6210 + \:5b9f\:884c
  summarizePromptPetri[\"goal\"]       \[RightArrow] \:751f\:6210 + \:5b9f\:884c + wait + summary

\:7d50\:679c\:30a2\:30af\:30bb\:30b5 (\:65e2\:5b58\:306e wid \:7528):
  getWorkflowValue[wid]               \[RightArrow] \:5b8c\:8d70\:306a\:3089 value\:3001\:5931\:6557\:306a\:3089 $Failed
  getWorkflowError[wid]               \[RightArrow] \:5931\:6557\:6642\:306e\:8a73\:7d30 (Reason / StuckPlaces \:7b49)\:3001\:5b8c\:8d70\:6642\:306f None
  getWorkflowReport[wid]              \[RightArrow] \:5b8c\:8d70: value\:3001\:5931\:6557: \:30a8\:30e9\:30fc\:8a73\:7d30 (\:30b0\:30e9\:30d5\:30a3\:30ab\:30eb)
  getWorkflowResults[wid]             \[RightArrow] \:30c7\:30d0\:30c3\:30b0\:7528\:306e\:5168\:60c5\:5831 Association
  getFinalTokens[wid]                 \[RightArrow] FinalPlaces \:306b\:3042\:308b token \:30ea\:30b9\:30c8
  getTokensInPlace[wid, place]        \[RightArrow] \:7279\:5b9a Place \:306e token (\:5931\:6557\:6642\:306e\:30c7\:30d0\:30c3\:30b0\:7528)

\:53ef\:8996\:5316 (v10):
  plotPetriNet[net]                   \[RightArrow] WorkflowNet \:69cb\:9020\:3092\:30b0\:30e9\:30d5\:8868\:793a
  plotPetriNet[wid]                   \[RightArrow] wid \:7d4c\:7531\:3067\:3082\:53ef
  plotExecutionTrace[wid]             \[RightArrow] \:5b9f\:884c\:7d4c\:8def\:3092\:6642\:7cfb\:5217\:30b0\:30e9\:30d5\:3067
  traceList[wid]                      \[RightArrow] \:5b9f\:884c\:30c8\:30ec\:30fc\:30b9\:3092 Dataset \:8868\:793a

v6 \:65b0\:6a5f\:80fd: \:81ea\:52d5\:518d\:751f\:6210\:30eb\:30fc\:30d7
  proposePetriNet \:306f\:7f60 #3 (\:5171\:6709\:5165\:529b Place) \:7b49\:3092\:691c\:51fa\:3059\:308b\:3068\:3001
  LLM \:306b\:5177\:4f53\:7684\:30d5\:30a3\:30fc\:30c9\:30d0\:30c3\:30af\:3092\:6e21\:3057\:3066\:6700\:5927 3 \:56de\:81ea\:52d5\:518d\:8a66\:884c\:3059\:308b\:3002
  - \"MaxRetries\" -> N \:3067\:30ea\:30c8\:30e9\:30a4\:56de\:6570\:3092\:5909\:66f4
  - \"Verbose\" -> True \:3067\:30ea\:30c8\:30e9\:30a4\:6642\:306b\:30b3\:30f3\:30bd\:30fc\:30eb\:8868\:793a
  - prop[[\"Attempts\"]] \:3067\:5b9f\:969b\:306b\:8a66\:884c\:3057\:305f\:56de\:6570\:78ba\:8a8d
  - prop[[\"SharedInputPlaces\"]] \:304c {} \:306a\:3089\:7f60 #3 \:56de\:907f\:6210\:529f

\:4f8b 1: \:5b8c\:8d70\:30b1\:30fc\:30b9
  prop = proposePetriNet[\"3 \:8996\:70b9\:3067\:4e26\:5217\:30ec\:30d3\:30e5\:30fc\:3001\:4e0d\:5408\:683c\:306a\:3089 1 \:56de\:518d\:8a66\:884c\"];
  prop[[\"Attempts\"]]                  (* 1 \:306a\:3089\:521d\:56de\:6210\:529f\:30012-3 \:306a\:3089\:81ea\:52d5\:518d\:751f\:6210\:6210\:529f *)
  prop[[\"SharedInputPlaces\"]]         (* {} \:306a\:3089\:7f60 #3 \:56de\:907f *)
  net = parsePetriCode[prop[[\"Code\"]]];
  wid = ClaudeCreateWorkflowNet[net];
  ClaudeSubmitToken[wid, WorkflowToken[\"Kind\" -> \"Task\",
    \"Payload\" -> <|\"Text\" -> $exampleDraftAbstract|>]];
  ClaudeRunWorkflow[wid, \"Async\" -> True];
  getWorkflowReport[wid]
  
\:4f8b 2: \:5931\:6557\:30b1\:30fc\:30b9 (Stuck \:7b49)
  v = getWorkflowValue[wid]                  (* $Failed *)
  e = getWorkflowError[wid]                  (* <|Reason -> ..., StuckPlaces -> ...|> *)
  getTokensInPlace[wid, e[[\"StuckPlaces\"]] // Keys // First]  (* \:8a70\:307e\:3063\:305f token \:3092\:898b\:308b *)

\:30c8\:30e9\:30d6\:30eb\:30b7\:30e5\:30fc\:30c8:
  prop[[\"BuilderName\"]]        (* \:7a7a\:3060\:3068 LLM \:304c build*[] \:3092\:8fd4\:3055\:306a\:304b\:3063\:305f *)
  prop[[\"Truncated\"]]          (* True \:3060\:3068 LLM \:5fdc\:7b54\:304c\:9014\:4e2d\:3067\:5207\:308c\:305f *)
  prop[[\"ForbiddenFound\"]]     (* \:975e\:7a7a\:3060\:3068 LLM \:304c\:5b9f\:884c\:30b3\:30fc\:30c9\:3092\:542b\:3081\:305f *)
  prop[[\"SharedInputPlaces\"]]  (* \:975e\:7a7a\:3060\:3068 \:7f60 #3 \:3067 max \:307e\:3067\:8a66\:3057\:3066\:3082\:30c0\:30e1\:3060\:3063\:305f *)
  prop[[\"RawResponse\"]]        (* LLM \:751f\:5fdc\:7b54\:3092\:898b\:3066\:539f\:56e0\:8ffd\:8de1 *)
"];
