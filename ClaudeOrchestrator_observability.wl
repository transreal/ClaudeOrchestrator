(* ::Package:: *)

(* ::Title:: *)
(* ClaudeOrchestrator_observability.wl *)


(* ::Text:: *)
(**)


(* \:65e7\:540d: petri_observability.wl (v0.1.9 \:307e\:3067)\:3002
   v0.2.0 (2026-05-11) \:3067 ClaudeOrchestrator_observability.wl \:306b\:6539\:540d\:3002
   petri_from_prompt.wl \:3068 petri_from_prompt_chatgpt.wl \:306e\:30de\:30fc\:30b8
   (proposePetriNetWithProvider \[RightArrow] proposePetriNet \:7d71\:4e00) \:306b\:5408\:308f\:305b\:3001
   \:540d\:79f0\:306e\:6574\:5408\:6027\:3092\:53d6\:3063\:305f\:3002
   \:5185\:90e8 API / \:516c\:958b\:30b7\:30f3\:30dc\:30eb / \:52d5\:4f5c\:306f\:5b8c\:5168\:4e92\:63db\:3002 *)



(* ::Subsection:: *)
(* \:6982\:8981 *)


(* ============================================================
   petri_from_prompt.wl (v0.10.0+ \:7d71\:5408\:7248\:3001\:65e7 petri_from_prompt_chatgpt.wl \:306e
   \:6a5f\:80fd\:3092\:5438\:53ce\:6e08\:307f) \:3078\:306e\:89b3\:6e2c (observability) \:88dc\:5b8c\:30e2\:30b8\:30e5\:30fc\:30eb\:3002

   \:76ee\:7684:
     \:300cno review \:304c\:51fa\:306a\:3044\:300d\:3088\:3046\:306a\:4e0d\:53ef\:89e3\:306a\:73fe\:8c61\:306b\:5bfe\:3057\:3066\:3001
       1. \:305d\:3082\:305d\:3082\:30e2\:30c7\:30eb\:9078\:629e\:304c\:3067\:304d\:3066\:3044\:306a\:3044
       2. LLM \:306b\:6e21\:308b\:30d7\:30ed\:30f3\:30d7\:30c8\:304c\:304a\:304b\:3057\:3044
       3. LLM \:306e\:51fa\:529b\:304c\:304a\:304b\:3057\:3044
       4. LLM \:306e\:51fa\:529b\:306f OK \:3060\:304c\:3001\:305d\:306e\:5f8c\:306e\:62bd\:51fa\:306b\:5931\:6557
     \:306e\:3069\:3053\:306b\:8d77\:56e0\:3059\:308b\:304b *\:77ac\:6642\:306b* \:5224\:5225\:3067\:304d\:308b\:89b3\:6e2c\:624b\:6bb5\:3092\:63d0\:4f9b\:3059\:308b\:3002

   \:8a2d\:8a08\:539f\:5247 (Session_Pitfalls_Summary.md \:306e\:6559\:8a13\:3092\:53cd\:6620):
     - ClaudeQueryBg \:672c\:4f53\:3092 wrap \:3057\:306a\:3044\:3002\:65b0\:95a2\:6570 ClaudeQueryBgLogged \:3092\:4f5c\:308b\:3002
       (Pitfall C: Options/Context/Protect \:6574\:5408\:306e\:5d29\:58ca\:56de\:907f)
     - parsePetriCode \:306b\:624b\:3092\:5165\:308c\:306a\:3044\:3002net Association \:53d6\:5f97 *\:5f8c* \:306b instrument\:3002
       (Pitfall D: Return \:7d4c\:8def\:306b\:526f\:4f5c\:7528\:3092\:631f\:3080\:5371\:967a\:3092\:56de\:907f)
     - \:9759\:7684\:691c\:67fb\:306f\:8ffd\:52a0\:3057\:306a\:3044\:3002false positive \:3067 LLM \:3092\:30df\:30b9\:30ea\:30fc\:30c9\:3057\:306a\:3044\:3002
       (Pitfall A \:306e\:56de\:907f)
     - \:6587\:5b57\:5217\:7f6e\:63db\:306f\:300c\:95a2\:6570\:540d -> \:95a2\:6570\:540d\:300d\:306e\:307f\:3002Function/Module \:30b9\:30b3\:30fc\:30d7\:306b\:89e6\:308c\:306a\:3044\:3002
       (Pitfall E: \:6587\:5b57\:5217\:30ec\:30d9\:30eb\:3067\:306e Function \:30e9\:30c3\:30d7\:306b\:3088\:308b scope \:7834\:58ca\:3068\:533a\:5225)
     - \:89b3\:6e2c API \:3092 1 \:4ef6\:5165\:308c\:305f\:77ac\:9593\:306b\:771f\:56e0\:304c\:898b\:3048\:308b\:8a2d\:8a08\:3092\:512a\:5148\:3002
       (Pitfall F: \:89b3\:6e2c\:306a\:3057\:3067\:4eee\:8aac\:3092\:81a8\:3089\:307e\:305b\:306a\:3044)

   \:63d0\:4f9b\:3059\:308b\:516c\:958b\:30b7\:30f3\:30dc\:30eb:

     --- LLM \:547c\:3073\:51fa\:3057\:30ed\:30b0 ---
     ClaudeQueryBgLogged[prompt, opts]
     $LLMCallLog
     showLLMCallLog[]                Dataset \:4e00\:89a7
     showLLMCallLog[idx]             1 \:4ef6 Pretty Print
     clearLLMCallLog[]

     --- Handler \:89b3\:6e2c (\:672c\:4f53\:30d1\:30c3\:30c1\:975e\:4f9d\:5b58) ---
     instrumentNetForObservation[net]
     $ObservedHandlerLog
     clearObservedHandlerLog[]

     --- \:751f\:6210\:30b3\:30fc\:30c9\:3078\:306e logger \:6ce8\:5165 ---
     withLLMLogging[code_String]

     --- \:53ef\:8996\:5316 (\:672c\:4f53 plotPetriNet \:3068\:306f\:72ec\:7acb\:306e\:5225\:95a2\:6570) ---
     plotPetriNetDetail[netOrWid, opts]
       Tooltip \:4ed8\:304d\:8a73\:7d30\:8868\:793a\:3002\:672c\:4f53 plotPetriNet \:306f\:4e0a\:66f8\:304d\:305b\:305a\:6e29\:5b58\:3059\:308b\:3002
       \:30aa\:30d7\:30b7\:30e7\:30f3 "TraceWid" -> wid \:3092\:6e21\:3059\:3068 Tooltip \:3067\:30ce\:30fc\:30c9/\:8fba\:306e\:60c5\:5831\:3092\:8868\:793a\:3002
       wid \:3092\:76f4\:63a5\:6e21\:3057\:305f\:5834\:5408\:306f\:81ea\:52d5\:7684\:306b Tooltip \:30e2\:30fc\:30c9\:306b\:306a\:308b\:3002
       Graph \:306e\:30aa\:30d7\:30b7\:30e7\:30f3 (VertexLayout \:7b49) \:3082\:305d\:306e\:307e\:307e\:6e21\:305b\:308b
       (Options[plotPetriNetDetail] = Join[..., Options[Graph]] \:306e\:305f\:3081)\:3002

     --- transition \:8ffd\:8de1 Dataset ---
     traceTransitions[wid, opts]
       Status \:306f\:89b3\:6e2c\:30ed\:30b0\:512a\:5148\:3067\:5224\:5b9a (\:672c\:4f53 ExecutorStatus \:3092\:76f2\:4fe1\:3057\:306a\:3044)\:3002
         OK / Failed ($Failed) / Errored (N msg) / BadOutput /
         AwaitingLLM / Skip / NoPayload / LLMError (M/N)
       "Detail" -> True \:3067 LLM \:547c\:3073\:51fa\:3057\:8a73\:7d30 + \:672c\:4f53 ExecStatus \:3092\:4f75\:8a18\:3002

   \:4f9d\:5b58\:95a2\:4fc2:
     - petri_from_prompt.wl  (plotPetriNet, getTokensInPlace, iExtractEdges)
     - ClaudeOrchestrator`Workflow`
       (ClaudeWorkflowTrace, ClaudeWorkflowState \:516c\:958b API \:306e\:307f\:4f7f\:7528)
     - ClaudeCode`ClaudeQueryBg

   \:30d0\:30fc\:30b8\:30e7\:30f3:
     v0.1.0 (2026-05-10): \:521d\:7248\:3002
     v0.1.1 (2026-05-10): Status \:5224\:5b9a\:3092\:89b3\:6e2c\:30ed\:30b0\:512a\:5148\:306b\:5909\:66f4\:3002
       \:672c\:4f53 iExecutePureFunction \:306e\:7f60 #16 \:3067\:63e1\:308a\:6f70\:3055\:308c\:305f $Failed \:3084
       \:6291\:5236\:30e1\:30c3\:30bb\:30fc\:30b8\:3092 Status \:30ab\:30e9\:30e0\:306b\:53cd\:6620\:3059\:308b\:3002Detail \:30e2\:30fc\:30c9\:306b
       \:672c\:4f53\:7531\:6765\:306e ExecStatus \:30ab\:30e9\:30e0\:3092\:8ffd\:52a0\:3057\:3066\:4e21\:8005\:306e\:98df\:3044\:9055\:3044\:3092\:53ef\:8996\:5316\:3002
     v0.1.2 (2026-05-10): LLM \:5fdc\:7b54\:30a8\:30e9\:30fc\:30d1\:30bf\:30fc\:30f3\:691c\:51fa\:3092\:8ffd\:52a0\:3002
       handler \:304c API \:30a8\:30e9\:30fc\:6587\:5b57\:5217 ("Error: model: gpt-4.5-preview" \:7b49)
       \:3092 Payload \:306b graceful \:683c\:7d0d\:3059\:308b\:30b1\:30fc\:30b9\:3092 Status \:306b\:53cd\:6620:
       LLMError (1/1) \:306e\:3088\:3046\:306b LLM \:30ec\:30a4\:30e4\:30fc\:5931\:6557\:3092\:8868\:793a\:3002
     v0.1.3 (2026-05-10): traceTransitions / plotPetriNet Tooltip \:304c
       TransitionFailed event (atomic firing rollback) \:3082\:53d6\:308a\:8fbc\:3080\:3088\:3046\:62e1\:5f35\:3002
     v0.1.4 (2026-05-10): traceTransitions Dataset \:306b Attempt \:30ab\:30e9\:30e0\:8ffd\:52a0
       (RetryPolicy \:3067\:8907\:6570\:56de\:8a66\:884c\:3055\:308c\:305f transition \:306e attempts \:6570\:3092\:53ef\:8996\:5316)\:3002
     v0.1.5 (2026-05-10): plotPetriNet \:672b\:5c3e\:306e FilterRules[...] \:3092
       Sequence @@ \:3067\:5c55\:958b\:3059\:308b\:4fee\:6b63 (review2.nb \:3067 Graph[] \:304c `{}` \:3092\:672b\:5c3e
       \:5f15\:6570\:3068\:3057\:3066\:53d7\:3051\:53d6\:308a\:672a\:8a55\:4fa1\:3067\:6b8b\:308b\:554f\:984c\:3078\:306e\:5bfe\:5fdc)\:3002
     v0.1.6 (2026-05-10, \:64a4\:56de\:6e08): Graph 2 \:5f15\:6570\:5f62\:5f0f (\:9802\:70b9\:30ea\:30b9\:30c8, edge \:30ea\:30b9\:30c8)
       \:3078\:306e\:5207\:66ff\:3092\:8a66\:307f\:305f\:304c review3/4.nb \:3067\:6539\:5584\:305b\:305a\:3001Imai \:5148\:751f\:304b\:3089\:672c\:4f53
       plotPetriNet \:4e0a\:66f8\:304d\:65b9\:91dd\:81ea\:4f53\:3078\:306e\:7570\:8b70\:3092\:53d7\:9818\:3002
     v0.1.7 (2026-05-10): \:8a2d\:8a08\:65b9\:91dd\:3092\:8ee2\:63db\:3002\:672c\:4f53 petri_from_prompt.wl \:306e
       plotPetriNet \:306f\:4e0a\:66f8\:304d\:305b\:305a\:6e29\:5b58\:3002Tooltip \:62e1\:5f35\:306f\:5225\:95a2\:6570
       plotPetriNetDetail \:3068\:3057\:3066\:63d0\:4f9b (Imai \:5148\:751f\:306e\:6307\:793a)\:3002
       - \:672c\:4f53 plotPetriNet \:306f\:6a19\:6e96\:306e\:30b0\:30e9\:30d5\:63cf\:753b\:3092\:62c5\:3046 (\:52d5\:4f5c\:5b9f\:7e3e\:3042\:308a)
       - plotPetriNetDetail[wid] / plotPetriNetDetail[net, "TraceWid"->wid]
         \:3092 Tooltip \:4ed8\:304d\:89b3\:6e2c\:7528\:306b\:4f7f\:3046
       - Options[plotPetriNetDetail] = Join[{"TraceWid"->None}, Options[Graph]]
         \:3068\:3057\:3066\:3001Graph \:30aa\:30d7\:30b7\:30e7\:30f3 (VertexLayout \:7b49) \:3082\:305d\:306e\:307e\:307e\:53d7\:3051\:53d6\:308c\:308b
     v0.1.8 (2026-05-11): "Rectangle" vertex shape \:30d0\:30b0\:4fee\:6b63\:3002
       VertexShapeFunction -> {..., transition -> "Rectangle", ...} \:306e
       "Rectangle" \:306f Mathematica \:306e\:540d\:524d\:4ed8\:304d vertex shape \:3068\:3057\:3066\:672a\:5b9a\:7fa9
       (\:516c\:5f0f\:30c9\:30ad\:30e5\:30e1\:30f3\:30c8: "Square", "Diamond", "ConcaveHexagon" \:7b49\:306f
       \:3042\:308b\:304c "Rectangle" \:306f\:7121\:3057)\:3002"Square" \:306b\:7f6e\:63db\:3057\:305f\:3002
     v0.1.9 (2026-05-11): plotPetriNet \:63cf\:753b\:5931\:6557\:306e\:771f\:56e0\:306b\:3088\:3046\:3084\:304f\:5230\:9054\:3002
       Imai \:5148\:751f\:306e review6.nb \:5206\:6790\:30ec\:30dd\:30fc\:30c8\:306b\:5f93\:3044\:3001Graph \:306b\:660e\:793a\:7684\:306a\:9802\:70b9
       \:30ea\:30b9\:30c8\:3092\:6e21\:3059 2 \:5f15\:6570\:5f62\:5f0f Graph[vertices, edges, ...] \:306b\:5909\:66f4
       (vertices = Join[places, transitions])\:3002
       \:3053\:308c\:306f v0.1.6 \:3067\:4e00\:5ea6\:5b9f\:65bd\:3057\:305f\:4fee\:6b63\:3068\:540c\:3058\:3060\:304c\:3001\:5f53\:6642 Imai \:5148\:751f\:306e
       \:300c\:4ee5\:524d\:306e plotPetriNet \:5b9a\:7fa9\:306b\:623b\:3063\:3066\:307b\:3057\:3044\:300d\:3092\:300c2 \:5f15\:6570\:5f62\:5f0f\:306e\:64a4\:56de\:307e\:3067
       \:542b\:3080\:300d\:3068\:904e\:5270\:89e3\:91c8\:3057\:3066 v0.1.7 \:3067\:8aa4\:3063\:3066\:64a4\:56de\:3057\:3066\:3044\:305f\:3002\:5b9f\:969b\:306e\:3054\:6307\:793a\:306e
       \:8da3\:65e8\:306f\:300c\:672c\:4f53\:4e0a\:66f8\:304d\:3092\:3084\:3081\:3066\:30c9\:30ad\:30e5\:30e1\:30f3\:30c8\:3092\:8aad\:307f\:76f4\:305b\:300d\:3067\:3042\:308a\:3001
       2 \:5f15\:6570\:5f62\:5f0f\:305d\:306e\:3082\:306e\:306f\:5426\:5b9a\:3055\:308c\:3066\:3044\:306a\:304b\:3063\:305f\:3002

       \:771f\:56e0\:306e\:6574\:7406 (review.nb \:301c review6.nb \:306e\:4e00\:9023):
         - "Failed" \:306e\:3088\:3046\:306a\:5b64\:7acb Place (FinalPlaces \:306b\:3042\:308b\:304c\:8fba\:3092\:6301\:305f\:306a\:3044)
           \:304c\:542b\:307e\:308c\:308b net \:3067\:3001Graph[edges, ...] \:306e 1 \:5f15\:6570\:5f62\:5f0f\:306f\:8fba\:7aef\:70b9\:3057\:304b
           \:9802\:70b9\:63a1\:7528\:3057\:306a\:3044 -> VertexShapeFunction / VertexStyle / VertexLabels
           \:306e\:6307\:5b9a\:3068\:4e0d\:6574\:5408 -> Graph[] \:304c\:672a\:8a55\:4fa1\:306e\:307e\:307e\:6b8b\:308b (review2-6.nb)
         - \:672c\:4f53 petri_from_prompt.wl \:306e plotPetriNet \:3082\:540c\:3058\:30d0\:30b0\:3092\:6301\:3064
           \:306e\:3067\:672c\:30d5\:30a1\:30a4\:30eb\:3068\:540c\:68b1\:3067\:672c\:4f53\:5074\:3082\:4fee\:6b63\:3059\:308b
         - v0.1.5 (Sequence @@ FilterRules), v0.1.8 ("Rectangle" -> "Square")
           \:306f\:5225\:306e\:5c0f\:30d0\:30b0\:4fee\:6b63\:3067\:3001\:672c\:8cea\:7684\:4fee\:6b63\:306f\:672c v0.1.9 \:306e\:307f

       \:540c\:6642\:306b Imai \:5148\:751f\:63d0\:793a\:306e\:691c\:67fb\:30e6\:30fc\:30c6\:30a3\:30ea\:30c6\:30a3 checkPetriNetVertices \:3092
       \:8ffd\:52a0\:3002net \:306e\:9802\:70b9\:6574\:5408\:6027 (IsolatedDeclaredVertices /
       UnknownVerticesInEdges) \:3092\:8a3a\:65ad\:3067\:304d\:308b\:3002

     v0.2.0 (2026-05-11): \:30d5\:30a1\:30a4\:30eb\:540d\:3092 ClaudeOrchestrator_observability.wl
       \:306b\:6539\:540d\:3002petri_from_prompt.wl \:3068 petri_from_prompt_chatgpt.wl \:306e
       \:30de\:30fc\:30b8 (proposePetriNet \:7d71\:4e00) \:3068\:4e26\:884c\:3057\:305f\:547d\:540d\:6574\:5408\:5316\:3002
       \:5185\:90e8 API / \:516c\:958b\:30b7\:30f3\:30dc\:30eb / \:52d5\:4f5c\:306f\:5b8c\:5168\:4e92\:63db\:3002
       \:30b3\:30e1\:30f3\:30c8\:4e2d\:306e Get["petri_from_prompt_chatgpt.wl"] \:8a00\:53ca\:3092\:524a\:9664\:3057\:3001
       proposePetriNetWithProvider \:3078\:306e\:53c2\:7167\:3092 proposePetriNet \:306b\:7d71\:4e00\:3002
     v0.2.1 (2026-05-17): Z \:6848 (handler \:5185\:975e\:540c\:671f LLM) \:3068\:306e\:9023\:643a\:5bfe\:5fdc\:3002
       handler \:304c <|Status -> "AwaitingLLM"|> \:3092\:540c\:671f return \:3059\:308b\:30d1\:30bf\:30fc\:30f3\:3092
       Status \:30ab\:30e9\:30e0\:3067\:6b63\:5f0f\:306b\:533a\:5225\:3067\:304d\:308b\:3088\:3046\:306b\:3057\:305f\:3002
       - iObsMakeHandlerWrapper \:306e log entry \:306b OutputStatus \:30d5\:30a3\:30fc\:30eb\:30c9\:8ffd\:52a0
         (output \:304c Association + Status \:30ad\:30fc\:3092\:6301\:3064\:3068\:304d\:306b\:5024\:3092\:8a18\:9332)
       - iObsDeriveStatus \:306e Which \:306b AwaitingLLM / Skip \:5206\:5c90\:3092\:8ffd\:52a0
         (PayloadKeyMissing \:5224\:5b9a\:3088\:308a\:524d\:3067\:512a\:5148\:8a55\:4fa1)
       - \:3053\:308c\:306b\:3088\:308a Z \:6848 handler \:306e\:6b63\:5e38\:306a AwaitingLLM \:623b\:308a\:5024\:304c "NoPayload"
         \:306b\:8aa4\:5206\:985e\:3055\:308c\:308b\:306e\:3092\:9632\:3050\:3002
       - completion \:5074 (ClaudeCompleteHandlerOutput \:7d4c\:7531\:306e finalize) \:306e
         \:89b3\:6e2c\:306f\:672c patch \:306e\:5bfe\:8c61\:5916\:3002Stage 2-B / C \:3067\:5225\:9014\:6271\:3046\:3002
*)

Needs["ClaudeOrchestrator`Workflow`"];



(* ::Subsection:: *)
(* \:516c\:958b\:30b7\:30f3\:30dc\:30eb\:5ba3\:8a00 *)


ClearAll[
  $petriObservabilityVersion,
  (* LLM call log *)
  $LLMCallLog,
  ClaudeQueryBgLogged,
  clearLLMCallLog,
  showLLMCallLog,
  (* Handler observation *)
  $ObservedHandlerLog,
  $CurrentObservedTransition,
  clearObservedHandlerLog,
  instrumentNetForObservation,
  (* Code logger injection *)
  withLLMLogging,
  (* Plot extension - \:672c\:4f53 plotPetriNet \:306f\:4e0a\:66f8\:304d\:305b\:305a\:3001\:5225\:95a2\:6570\:3068\:3057\:3066\:63d0\:4f9b *)
  plotPetriNetDetail,
  checkPetriNetVertices,
  (* Transition tracking *)
  traceTransitions,
  (* Internal *)
  iObsExtractEdges,
  iObsMakeHandlerWrapper,
  iObsHandlerTraceFor,
  iObsLLMCallsFor,
  iObsLLMCallsForFiring,
  iObsLLMErrorPatternQ,
  iObsMkPlaceTooltip,
  iObsMkTransitionTooltip,
  iObsMkEdgeTooltip,
  iObsResolveNet,
  iObsObservedFor,
  iObsDeriveStatus,
  (* Phase 5 (2026-05-26): provider provenance display *)
  iProviderDisplayName
];

$petriObservabilityVersion = "0.3.0 (2026-05-26)";

(* \:65e2\:5b58\:30ed\:30b0\:3092\:6e29\:5b58\:3059\:308b\:305f\:3081\:3001\:672a\:5b9a\:7fa9\:306e\:3068\:304d\:3060\:3051\:521d\:671f\:5316 *)
If[!ListQ[$LLMCallLog],         $LLMCallLog = {}];
If[!ListQ[$ObservedHandlerLog], $ObservedHandlerLog = {}];
If[!StringQ[$CurrentObservedTransition], $CurrentObservedTransition = "?"];



(* ::Subsection:: *)
(* 1. ClaudeQueryBgLogged *)


(* ============================================================
   ClaudeQueryBgLogged \:306f ClaudeQueryBg \:3092 *\:547c\:3073\:51fa\:3059\:5074* \:306e\:95a2\:6570\:3068\:3057\:3066
   \:5b9f\:88c5\:3057\:3001ClaudeQueryBg \:672c\:4f53 / Options / DownValues \:306f\:4e00\:5207\:5909\:66f4\:3057\:306a\:3044\:3002
   handler \:30e9\:30c3\:30d1\:304c Block[{$CurrentObservedTransition = tname}, ...] \:3067
   \:56f2\:3080\:306e\:3067\:3001\:3053\:3053\:3067 $CurrentObservedTransition \:3092\:8aad\:3081\:3070 transition \:540d\:304c
   \:53d6\:308c\:308b\:3002
   ============================================================ *)

ClaudeQueryBgLogged::usage =
  "ClaudeQueryBgLogged[prompt, opts] \:306f ClaudeCode`ClaudeQueryBg \:3068\:540c\:3058\:547c\:3073\:51fa\:3057\:3092\:884c\:3044\:3001" <>
  " \:958b\:59cb\:6642\:523b / \:6240\:8981\:6642\:9593 / Model / Fallback / \:30d7\:30ed\:30f3\:30d7\:30c8 / \:5fdc\:7b54\:3092 $LLMCallLog \:306b\:8ffd\:8a18\:3059\:308b\:3002" <>
  " \:547c\:3073\:51fa\:3057\:4e2d\:306b $CurrentObservedTransition \:304c\:675f\:7e1b\:3055\:308c\:3066\:3044\:308c\:3070\:3001\:305d\:306e transition \:540d\:3082\:8a18\:9332\:3059\:308b\:3002" <>
  " ClaudeQueryBg \:672c\:4f53\:306f\:5909\:66f4\:3057\:306a\:3044\:306e\:3067\:3001Options / Protect / Context \:306e\:6574\:5408\:306f\:58ca\:308c\:306a\:3044\:3002";

(* ------------------------------------------------------------------
   Phase 5 (2026-05-26, spec 13.2): provider identifier -> UI display
   name. Accepts the internal provider id ("chatgptcodex"), the
   ProviderKind from a ProviderResultMetadata association
   ("ChatGPTCodexCLI") or a human label, and normalizes to a stable
   display string. Unknown ids pass through unchanged.
   ------------------------------------------------------------------ *)
iProviderDisplayName[id_String] :=
  Module[{p},
    p = ToLowerCase @ StringTrim @ id;
    Which[
      MemberQ[{"chatgptcodex", "chatgptcodexcli", "chatgpt-codex",
        "codex", "chatgpt codex"}, p], "ChatGPT Codex",
      MemberQ[{"anthropic", "claude", "claude-cli", "claudecli"}, p],
        "Claude",
      MemberQ[{"lmstudio", "lm studio", "lm-studio"}, p], "LM Studio",
      MemberQ[{"openai", "open-ai"}, p], "OpenAI",
      MemberQ[{"generic", "unknown", ""}, p], "Unknown",
      True, id]];
iProviderDisplayName[___] := "Unknown";

ClaudeQueryBgLogged[prompt_, opts:OptionsPattern[]] :=
  Module[{t0, t1, response, transName, optAssoc, model, fallback,
          entry, prm, providerKind},
    t0 = AbsoluteTime[];
    transName = If[StringQ[$CurrentObservedTransition],
      $CurrentObservedTransition, "?"];

    optAssoc = Association[opts];
    model    = Lookup[optAssoc, ClaudeCode`Model,    Automatic];
    fallback = Lookup[optAssoc, ClaudeCode`Fallback, False];

    response = ClaudeCode`ClaudeQueryBg[prompt, opts];
    t1 = AbsoluteTime[];

    (* Phase 5 (spec 13.2): if the response carries a Codex /
       provider ProviderResultMetadata association, lift its
       provenance keys into the trace entry. ClaudeQueryBg may return
       a bare string (no metadata) or an association. *)
    prm = If[AssociationQ[response],
      Lookup[response, "ProviderResultMetadata", <||>], <||>];
    If[!AssociationQ[prm], prm = <||>];
    providerKind = Lookup[prm, "ProviderKind",
      Which[
        StringQ[model], iProviderDisplayName[model],
        ListQ[model] && Length[model] >= 1 && StringQ[model[[1]]],
          model[[1]],
        True, "Unknown"]];

    entry = <|
      "Index"          -> Length[$LLMCallLog] + 1,
      "Time"           -> t0,
      "TimeStr"        -> DateString[t0, {"Hour", ":", "Minute", ":", "Second"}],
      "Duration"       -> t1 - t0,
      "TransitionName" -> transName,
      "Model"          -> model,
      "Fallback"       -> fallback,
      "Prompt"         -> prompt,
      "PromptLen"      -> StringLength[ToString[prompt]],
      "Response"       -> response,
      "ResponseLen"    -> StringLength[ToString[response]],
      "OptionList"     -> {opts},
      (* Phase 5 (2026-05-26, spec 13.2): provider provenance *)
      "ProviderKind"           -> providerKind,
      "ProviderDisplayName"    -> iProviderDisplayName[
        ToString[providerKind]],
      "HarnessBundleId"        -> Lookup[prm, "HarnessBundleId",
        Missing["NotApplicable"]],
      "DirectiveSnapshotId"    -> Lookup[prm, "DirectiveSnapshotId",
        Missing["NotApplicable"]],
      "RuntimeEnvironmentHash" -> Lookup[prm, "RuntimeEnvironmentHash",
        Missing["NotApplicable"]],
      "ProviderResultMetadata" -> prm
    |>;
    AppendTo[$LLMCallLog, entry];
    response
  ];

clearLLMCallLog[] := ($LLMCallLog = {}; "$LLMCallLog cleared");

showLLMCallLog[] :=
  If[Length[$LLMCallLog] === 0,
    Print[Style["[showLLMCallLog] $LLMCallLog \:306f\:7a7a\:3067\:3059\:3002", Orange]];
    $Failed,
    Dataset[
      Map[
        Function[c,
          <|"#"           -> Lookup[c, "Index", "?"],
            "Time"        -> Lookup[c, "TimeStr", "?"],
            "Trans"       -> Lookup[c, "TransitionName", "?"],
            "Provider"    -> Lookup[c, "ProviderDisplayName", "?"],
            "Model"       -> ToString[Lookup[c, "Model", "?"]],
            "PromptLen"   -> Lookup[c, "PromptLen", 0],
            "ResponseLen" -> Lookup[c, "ResponseLen", 0],
            "Duration"    -> Round[Lookup[c, "Duration", 0.0], 0.01],
            "Preview"     -> StringTake[
              ToString[Lookup[c, "Response", ""]], UpTo[60]]|>],
        $LLMCallLog]]];

showLLMCallLog[idx_Integer] :=
  Module[{entry},
    If[idx < 1 || idx > Length[$LLMCallLog],
      Print[Style["[showLLMCallLog] index \:7bc4\:56f2\:5916: " <>
        ToString[idx] <> " (1.." <> ToString[Length[$LLMCallLog]] <> ")", Orange]];
      Return[$Failed]];
    entry = $LLMCallLog[[idx]];
    Column[{
      Style["=== LLM Call #" <> ToString[idx] <> " ===",
            Bold, Darker[Blue]],
      Row[{Style["Time:        ", Bold], Lookup[entry, "TimeStr", "?"]}],
      Row[{Style["Transition:  ", Bold], Lookup[entry, "TransitionName", "?"]}],
      Row[{Style["Provider:    ", Bold],
        ToString[Lookup[entry, "ProviderDisplayName", "?"]]}],
      Row[{Style["Model:       ", Bold], ToString[Lookup[entry, "Model", "?"]]}],
      Row[{Style["Fallback:    ", Bold], ToString[Lookup[entry, "Fallback", False]]}],
      Row[{Style["Duration:    ", Bold],
        ToString[Round[Lookup[entry, "Duration", 0.0], 0.001]] <> " s"}],
      Row[{Style["PromptLen:   ", Bold], ToString[Lookup[entry, "PromptLen", 0]]}],
      Row[{Style["ResponseLen: ", Bold], ToString[Lookup[entry, "ResponseLen", 0]]}],
      Sequence @@ If[
        MatchQ[Lookup[entry, "HarnessBundleId", Missing[]],
          _Missing | Missing] &&
        MatchQ[Lookup[entry, "DirectiveSnapshotId", Missing[]],
          _Missing | Missing],
        {},
        {Row[{Style["HarnessBundle:    ", Bold],
            ToString[Lookup[entry, "HarnessBundleId", "?"]]}],
         Row[{Style["DirectiveSnapshot:", Bold], " ",
            ToString[Lookup[entry, "DirectiveSnapshotId", "?"]]}],
         Row[{Style["RuntimeEnvHash:   ", Bold],
            ToString[Lookup[entry, "RuntimeEnvironmentHash", "?"]]}]}],
      "",
      Style["--- Prompt ---", Bold, Darker[Green]],
      Pane[Lookup[entry, "Prompt", ""], {640, 220},
           Scrollbars -> {False, Automatic}],
      "",
      Style["--- Response ---", Bold, Darker[Green]],
      Pane[Lookup[entry, "Response", ""], {640, 220},
           Scrollbars -> {False, Automatic}]
    }, Frame -> All, FrameMargins -> 6]
  ];



(* ::Subsection:: *)
(* 2. instrumentNetForObservation *)


(* ============================================================
   net \:5185\:306e\:5168 transition \:306e Handler \:3092\:89b3\:6e2c\:30e9\:30c3\:30d1\:3067\:5305\:3093\:3060\:65b0\:3057\:3044 net \:3092\:8fd4\:3059\:3002
   \:526f\:6b21\:52b9\:679c:
     - Symbol handler \:3067\:3082\:660e\:793a\:7684\:306b handler[binding] \:3092\:547c\:3076\:30e9\:30c3\:30d1\:3067\:5305\:3080\:306e\:3067\:3001
       \:672c\:4f53 iExecutePureFunction \:306e Symbol/Function \:5224\:5b9a\:5dee\:30d0\:30b0 (Bug 2) \:3092\:56de\:907f\:3002
     - Block \:3067 $CurrentObservedTransition \:3092\:5c40\:6240\:675f\:7e1b\:3059\:308b\:306e\:3067\:3001handler \:5185\:3067
       ClaudeQueryBgLogged \:304c transition \:540d\:3092\:77e5\:308b\:3053\:3068\:304c\:3067\:304d\:308b\:3002
   ============================================================ *)

clearObservedHandlerLog[] := ($ObservedHandlerLog = {}; "$ObservedHandlerLog cleared");

instrumentNetForObservation::usage =
  "instrumentNetForObservation[net] \:306f net \:306e\:5404 transition \:306e Handler \:3092" <>
  " \:89b3\:6e2c\:30e9\:30c3\:30d1\:3067\:5305\:3093\:3060\:65b0\:3057\:3044 net \:3092\:8fd4\:3059\:3002$ObservedHandlerLog \:306b handler \:547c\:3073\:51fa\:3057\:306e" <>
  " binding / output / messages \:304c\:8a18\:9332\:3055\:308c\:308b\:3088\:3046\:306b\:306a\:308b\:3002" <>
  " Symbol handler \:3082 Function \:30e9\:30c3\:30d1\:3067\:304f\:308b\:307e\:308c\:308b\:306e\:3067\:3001\:672c\:4f53\:5074 iExecutePureFunction \:306e" <>
  " Symbol/Function \:5224\:5b9a\:5dee\:30d0\:30b0\:3082\:540c\:6642\:306b\:56de\:907f\:3059\:308b\:3002";

instrumentNetForObservation[net_Association] :=
  Module[{transitions, newTransitions},
    transitions = Lookup[net, "Transitions", <||>];
    newTransitions = Association @ KeyValueMap[
      Function[{tname, tdef},
        tname -> instrumentNetForObservation[tdef, tname]],
      transitions];
    Append[net, "Transitions" -> newTransitions]
  ];

instrumentNetForObservation[trans_Association, tname_String] :=
  Module[{rs, handler, newHandler, newRs},
    rs       = Lookup[trans, "RuntimeSpec", <||>];
    handler  = Lookup[rs,    "Handler",     Identity];
    newHandler = iObsMakeHandlerWrapper[handler, tname];
    newRs    = Append[rs, "Handler" -> newHandler];
    Append[trans, "RuntimeSpec" -> newRs]
  ];

(* \:89b3\:6e2c\:30e9\:30c3\:30d1\:751f\:6210\:3002\:30af\:30ed\:30fc\:30b8\:30e3\:3068\:3057\:3066 handler / tname \:3092\:4fdd\:6301\:3059\:308b\:3002
   \:7f60 #15 \:56de\:907f: Map \:5185\:306e Function \:306b Return/Throw \:3092\:5165\:308c\:306a\:3044\:3001
   \:7f60 #16 \:56de\:907f: Quiet@Check \:306f\:4f7f\:308f\:305a Quiet[expr] \:306e\:307f + \:30d5\:30e9\:30b0\:5225\:53d6\:5f97\:3002 *)
iObsMakeHandlerWrapper[handler_, tname_String] :=
  Function[binding,
    Module[{t0, t1, output, msgs, bindingPayloads, outputPayload,
            payloadKeyMissing, rawKeys, payloadKeys, entry,
            handlerHead = Head[handler]},
      t0 = AbsoluteTime[];
      output = $Failed;
      msgs   = {};
      Block[{$CurrentObservedTransition = tname,
             $MessageList = {}},
        output = Quiet[
          Which[
            handler === Identity,            binding,
            handlerHead === Function,        handler[binding],
            handlerHead === Symbol,          handler[binding],
            (* CompoundExpression / pure delayed forms etc. *)
            True,                            handler[binding]
          ]];
        msgs = $MessageList;
      ];
      t1 = AbsoluteTime[];

      bindingPayloads = If[AssociationQ[binding],
        AssociationMap[
          Function[place,
            Module[{t = binding[[place]]},
              Which[
                AssociationQ[t] && KeyExistsQ[t, "Payload"], t[["Payload"]],
                ListQ[t], Map[
                  If[AssociationQ[#] && KeyExistsQ[#, "Payload"], #[["Payload"]], #] &,
                  t],
                True, t]]],
          Keys[binding]],
        <||>];

      outputPayload = Which[
        AssociationQ[output] && KeyExistsQ[output, "Payload"],
          output[["Payload"]],
        AssociationQ[output],
          "<no Payload key>",
        True,
          $Failed];
      payloadKeyMissing = !(AssociationQ[output] && KeyExistsQ[output, "Payload"]);
      rawKeys = If[AssociationQ[output], Keys[output], "<non-assoc>"];
      payloadKeys = If[AssociationQ[outputPayload], Keys[outputPayload], "<non-assoc>"];

      entry = <|
        "Index"             -> Length[$ObservedHandlerLog] + 1,
        "TransitionName"    -> tname,
        "Time"              -> t0,
        "TimeStr"           -> DateString[t0,
          {"Hour", ":", "Minute", ":", "Second"}],
        "Duration"          -> t1 - t0,
        "BindingKeys"       -> Keys[binding],
        "BindingPayloads"   -> bindingPayloads,
        "OutputRaw"         -> output,
        "OutputAssocQ"      -> AssociationQ[output],
        "OutputHead"        -> Head[output],
        "RawKeys"           -> rawKeys,
        "PayloadKeys"       -> payloadKeys,
        "PayloadKeyMissing" -> payloadKeyMissing,
        "OutputPayload"     -> outputPayload,
        (* v0.2.1 (2026-05-17): Z \:6848\:3067 handler \:304c <|Status -> "AwaitingLLM"|>
           \:3092\:8fd4\:3059\:5834\:5408\:3084\:3001\:30ef\:30fc\:30af\:30d5\:30ed\:30fc\:56fa\:6709\:306e <|Status -> "Skip"|> \:3092\:8fd4\:3059\:5834\:5408\:306b\:3001
           Status \:6587\:5b57\:5217\:3092\:4e00\:7d1a\:30d5\:30a3\:30fc\:30eb\:30c9\:3068\:3057\:3066\:8a18\:9332\:3059\:308b\:3002Missing[] = Status \:30ad\:30fc\:7121\:3057\:3002
           iObsDeriveStatus \:304c PayloadKeyMissing \:3088\:308a\:512a\:5148\:3067 AwaitingLLM \:7b49\:3092
           \:533a\:5225\:3067\:304d\:308b\:3088\:3046\:306b\:3059\:308b\:3002 *)
        "OutputStatus"      -> If[AssociationQ[output] && KeyExistsQ[output, "Status"],
          output[["Status"]], Missing[]],
        "Messages"          -> msgs,
        "FailedHead"        -> output === $Failed,
        "HandlerType"       -> ToString[handlerHead]
      |>;
      AppendTo[$ObservedHandlerLog, entry];
      output
    ]
  ];



(* ::Subsection:: *)
(* 3. withLLMLogging  *)


(* ============================================================
   \:751f\:6210\:30b3\:30fc\:30c9\:4e2d\:306e ClaudeQueryBg \:547c\:3073\:51fa\:3057\:3092 ClaudeQueryBgLogged \:306b
   \:7f6e\:63db\:3059\:308b\:3002\:95a2\:6570\:540d -> \:95a2\:6570\:540d \:306e\:7f6e\:63db\:306e\:307f\:3002Function \:3084 Module \:30b9\:30b3\:30fc\:30d7\:3001
   binding \:306b\:306f\:89e6\:308c\:306a\:3044\:3002Pitfall E (\:6587\:5b57\:5217\:30ec\:30d9\:30eb\:306e Function \:30e9\:30c3\:30d7\:3067
   \:8a55\:4fa1\:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:304c\:58ca\:308c\:305f\:554f\:984c) \:3068\:306f\:6027\:683c\:304c\:9055\:3046\:3002
   ============================================================ *)

withLLMLogging::usage =
  "withLLMLogging[code_String] \:306f code \:5185\:306e `ClaudeQueryBg` \:547c\:3073\:51fa\:3057\:3092" <>
  " `Global`ClaudeQueryBgLogged` \:306b\:7f6e\:63db\:3057\:305f\:65b0\:3057\:3044\:6587\:5b57\:5217\:3092\:8fd4\:3059\:3002" <>
  " ClaudeCode`ClaudeQueryBg \:3068\:7121\:4fee\:98fe ClaudeQueryBg \:306e\:4e21\:65b9\:3092\:6271\:3046\:3002" <>
  " \:95a2\:6570\:540d\:306e\:307f\:3092\:66f8\:304d\:63db\:3048\:308b\:306e\:3067\:3001Function \:30b9\:30b3\:30fc\:30d7 / \:5c40\:6240\:5909\:6570 / HoldAll \:306a\:3069\:306b\:306f\:5f71\:97ff\:3057\:306a\:3044\:3002";

withLLMLogging[code_String] :=
  StringReplace[code, {
    (* 1. context \:5b8c\:5168\:4fee\:98fe\:3092\:5148\:306b\:51e6\:7406 (\:3053\:308c\:4ee5\:964d\:306e\:30eb\:30fc\:30eb\:3067\:518d\:51e6\:7406\:3055\:308c\:306a\:3044) *)
    "ClaudeCode`ClaudeQueryBg" -> "Global`ClaudeQueryBgLogged",
    (* 2. \:7121\:4fee\:98fe ClaudeQueryBg\:3002\:524d\:5f8c\:3092\:8b58\:5225\:5b50\:6587\:5b57\:3067\:306a\:3044\:4f4d\:7f6e\:306b\:9650\:5b9a *)
    RegularExpression[
      "(?<![A-Za-z0-9`$])ClaudeQueryBg(?![A-Za-z0-9])"] :>
      "Global`ClaudeQueryBgLogged"
  }];



(* ::Subsection:: *)
(* 4. plotPetriNetDetail (Tooltip \:62e1\:5f35\:7248\:3001\:672c\:4f53 plotPetriNet \:3068\:5171\:5b58) *)


(* ============================================================
   plotPetriNetDetail \:306f\:672c\:4f53 petri_from_prompt.wl \:306e plotPetriNet \:3068\:306f
   \:72ec\:7acb\:306e\:5225\:95a2\:6570\:3002"TraceWid" -> wid \:3092\:6e21\:3059\:3068\:3001Place / Transition / Edge
   \:306b\:30db\:30d0\:30fc\:3067 token / handler trace / firing event \:306e\:8a73\:7d30\:3092\:8868\:793a\:3059\:308b\:3002

   \:672c\:4f53 plotPetriNet \:306f\:4e0a\:66f8\:304d\:305b\:305a\:6e29\:5b58\:3059\:308b (Imai \:5148\:751f\:306e\:6307\:793a, 2026-05-10)\:3002
   \:901a\:5e38\:306e\:30b0\:30e9\:30d5\:8868\:793a\:306b\:306f\:672c\:4f53 plotPetriNet \:3092\:4f7f\:3044\:3001Tooltip \:3042\:308a\:306e\:8a73\:7d30\:8868\:793a\:304c
   \:5fc5\:8981\:306a\:3068\:304d\:3060\:3051 plotPetriNetDetail \:3092\:547c\:3073\:51fa\:3059\:904b\:7528\:3068\:3059\:308b\:3002
   ============================================================ *)

iObsExtractEdges[net_Association] :=
  Module[{transitions},
    transitions = Lookup[net, "Transitions", <||>];
    Flatten @ KeyValueMap[
      Function[{tname, tdef},
        Module[{inArcs, outArcs},
          inArcs  = Lookup[tdef, "InputArcs",  {}];
          outArcs = Lookup[tdef, "OutputArcs", {}];
          Join[
            Map[Lookup[#, "Place"] -> tname &, inArcs],
            Map[tname -> Lookup[#, "Place"] &, outArcs]
          ]]],
      transitions]
  ];

iObsResolveNet[netOrWid_] :=
  Which[
    AssociationQ[netOrWid] && KeyExistsQ[netOrWid, "Places"],
      netOrWid,
    StringQ[netOrWid],
      Module[{state},
        (* \:7f60 #16 \:56de\:907f: Quiet@Check \:306f\:4f7f\:308f\:306a\:3044\:3002Association \:623b\:308a\:5024\:3092\:63e1\:308a\:6f70\:3059\:305f\:3081\:3002
           Quiet[expr] \:306e\:307f\:3067\:53d6\:5f97\:3057\:3001AssociationQ \:3067\:5224\:5b9a\:3059\:308b\:3002 *)
        state = Quiet[ClaudeOrchestrator`Workflow`Private`$iWorkflowNets[netOrWid]];
        If[AssociationQ[state] && KeyExistsQ[state, "Places"],
          state,
          (* fallback: ClaudeWorkflowState \:306f Marking \:3057\:304b\:8fd4\:3055\:306a\:3044\:306e\:3067
             net \:69cb\:9020\:304c\:7121\:3044\:3002$iWorkflowNets \:304c\:7121\:3044\:74b0\:5883\:3067\:306f plot \:4e0d\:53ef\:3002 *)
          $Failed]],
    True, $Failed];

iObsHandlerTraceFor[transName_String] :=
  Module[{observed, builtIn},
    observed = Select[$ObservedHandlerLog,
      Lookup[#, "TransitionName", ""] === transName &];
    builtIn = If[
      ValueQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog] &&
      ListQ[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog],
      Select[ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog,
        Lookup[#, "TransitionName", ""] === transName &],
      {}];
    Join[observed, builtIn]
  ];

iObsLLMCallsFor[transName_String] :=
  Select[$LLMCallLog, Lookup[#, "TransitionName", ""] === transName &];

iObsMkPlaceTooltip[wid_String, place_String] :=
  Module[{tokens, mkRow},
    (* \:7f60 #16 \:56de\:907f: Quiet@Check \:306f\:4f7f\:308f\:306a\:3044\:3002Quiet \:3067\:8a55\:4fa1\:3057 ListQ \:3067\:5224\:5b9a\:3002 *)
    tokens = Quiet[getTokensInPlace[wid, place]];
    If[!ListQ[tokens], tokens = {}];
    mkRow[t_] := If[AssociationQ[t],
      Column[{
        Row[{Style["TokenId: ", Bold], Lookup[t, "TokenId", "?"]}],
        Row[{Style["Kind:    ", Bold], Lookup[t, "Kind",    "?"]}],
        Style["Payload:", Bold],
        Short[Lookup[t, "Payload", <||>], 6]}, Frame -> All, FrameMargins -> 4],
      Short[t, 6]];
    Column[{
      Style["Place: " <> place, Bold, 12],
      "Tokens currently here: " <> ToString[Length[tokens]],
      If[Length[tokens] === 0,
        Style["(no tokens currently in place)", Italic, Gray],
        Pane[Column[Map[mkRow, tokens]],
             {520, 320}, Scrollbars -> {False, Automatic}]]
    }, Frame -> True, FrameMargins -> 6]
  ];

iObsMkTransitionTooltip[wid_String, trans_String] :=
  Module[{traces, llmCalls, mkTraceRow, mkLLMRow},
    traces   = iObsHandlerTraceFor[trans];
    llmCalls = iObsLLMCallsFor[trans];

    mkTraceRow[t_] :=
      Column[{
        Row[{Style["#", Bold], Lookup[t, "Index", "?"], "  ",
             Style["Time: ", Bold], Lookup[t, "TimeStr", "?"], "  ",
             Style["Dur: ", Bold],
               ToString[Round[Lookup[t, "Duration", 0.0], 0.001]] <> "s"}],
        Row[{Style["RawKeys:     ", Bold], ToString[Lookup[t, "RawKeys", "?"]]}],
        Row[{Style["PayloadKeys: ", Bold], ToString[Lookup[t, "PayloadKeys", "?"]]}],
        Row[{Style["FailedHead:  ", Bold], ToString[Lookup[t, "FailedHead", "?"]]}],
        Row[{Style["PayloadKeyMissing: ", Bold],
             ToString[Lookup[t, "PayloadKeyMissing", "?"]]}],
        Style["BindingPayloads:", Bold],
        Short[Lookup[t, "BindingPayloads", <||>], 5],
        Style["OutputPayload:", Bold],
        Short[Lookup[t, "OutputPayload", $Failed], 5],
        If[Length[Lookup[t, "Messages", {}]] > 0,
          Column[{
            Style["Messages (suppressed by Quiet):", Bold, Red],
            Lookup[t, "Messages", {}]}],
          ""]
      }, Frame -> All, FrameMargins -> 4];

    mkLLMRow[c_] :=
      Column[{
        Row[{Style["LLM #", Bold], Lookup[c, "Index", "?"], "  ",
             Style["Model: ", Bold], ToString[Lookup[c, "Model", "?"]], "  ",
             Style["Dur: ", Bold],
               ToString[Round[Lookup[c, "Duration", 0.0], 0.01]] <> "s"}],
        Row[{Style["PromptLen: ",   Bold], ToString[Lookup[c, "PromptLen",   0]],
             "    ",
             Style["ResponseLen: ", Bold], ToString[Lookup[c, "ResponseLen", 0]]}],
        Style["Prompt:", Bold, Darker[Green]],
        Pane[Lookup[c, "Prompt", ""],
             {500, 120}, Scrollbars -> {False, Automatic}],
        Style["Response:", Bold, Darker[Green]],
        Pane[Lookup[c, "Response", ""],
             {500, 120}, Scrollbars -> {False, Automatic}]
      }, Frame -> All, FrameMargins -> 4];

    Column[{
      Style["Transition: " <> trans, Bold, 12],
      Row[{"Handler invocations: ",
           Style[ToString[Length[traces]],   Bold]}],
      Row[{"LLM calls:           ",
           Style[ToString[Length[llmCalls]], Bold]}],
      "",
      Style["--- Handler trace ---", Bold, Darker[Blue]],
      If[Length[traces] > 0,
        Pane[Column[Map[mkTraceRow, traces]],
             {560, 280}, Scrollbars -> {False, Automatic}],
        Style[
          "(handler not invoked yet \[Dash] " <>
          "instrumentNetForObservation \:7d4c\:7531\:3067\:5b9f\:884c\:3055\:308c\:305f\:304b\:78ba\:8a8d)",
          Italic, Gray]],
      "",
      Style["--- LLM calls ---", Bold, Darker[Blue]],
      If[Length[llmCalls] > 0,
        Pane[Column[Map[mkLLMRow, llmCalls]],
             {560, 280}, Scrollbars -> {False, Automatic}],
        Style[
          "(no LLM calls recorded for this transition \[Dash] " <>
          "withLLMLogging \:3092\:901a\:3057\:305f\:304b\:78ba\:8a8d)",
          Italic, Gray]]
    }, Frame -> True, FrameMargins -> 6]
  ];

iObsMkEdgeTooltip[wid_String, src_String, dst_String, kind_String,
                  placesList_, transitionsList_] :=
  Module[{trace, related, mkRow, transName},
    (* \:7f60 #16 \:56de\:907f: Quiet@Check \:306f\:4f7f\:308f\:306a\:3044\:3002Quiet \:3067\:8a55\:4fa1\:3057 ListQ \:3067\:5224\:5b9a\:3002 *)
    trace = Quiet[ClaudeWorkflowTrace[wid]];
    If[!ListQ[trace], trace = {}];
    transName = If[kind === "InputArc", dst, src];
    related = Select[trace,
      MemberQ[{"TransitionFired", "TransitionFailed"}, #[["Event"]]] &&
        Lookup[#, "TransitionName", ""] === transName &];
    mkRow[ev_, idx_] := Column[{
      Row[{Style["Step ", Bold], idx, "    ",
           Style["Status: ", Bold], Lookup[ev, "ExecutorStatus", "?"]}],
      Row[{Style["ConsumedIds: ", Bold],
           StringRiffle[ToString /@ Lookup[ev, "ConsumedIds", {}], ", "]}],
      Row[{Style["ProducedIds: ", Bold],
           StringRiffle[ToString /@ Lookup[ev, "ProducedIds", {}], ", "]}]
    }, Frame -> All, FrameMargins -> 4];
    Column[{
      Style["Edge: " <> src <> " \[Rule] " <> dst, Bold, 12],
      Style["(" <> kind <> " of transition \"" <> transName <> "\")",
            Italic, Gray],
      "Firings of " <> transName <> ": " <> ToString[Length[related]],
      If[Length[related] > 0,
        Pane[Column[MapIndexed[mkRow[#1, First[#2]] &, related]],
             {500, 240}, Scrollbars -> {False, Automatic}],
        Style[
          "(no firing recorded yet \[Dash] " <>
          "ClaudeRunWorkflow \:5b8c\:8d70\:5f8c\:306b\:78ba\:8a8d)",
          Italic, Gray]]
    }, Frame -> True, FrameMargins -> 6]
  ];

(* plotPetriNetDetail \:306f\:672c\:4f53 plotPetriNet \:3068 OptionsPattern \:3092\:63c3\:3048\:3001
   \:304b\:3064\:8ffd\:52a0\:3067 "TraceWid" \:30aa\:30d7\:30b7\:30e7\:30f3\:3092\:53d7\:3051\:4ed8\:3051\:308b\:5f62\:306b\:3059\:308b\:3002
   \:3053\:3046\:3059\:308b\:3053\:3068\:3067\:672c\:4f53\:3068\:540c\:3058 Graph \:30aa\:30d7\:30b7\:30e7\:30f3 (VertexLabels \:306e\:8ffd\:52a0\:7b49) \:3082
   \:547c\:3073\:51fa\:3057\:5074\:304b\:3089\:6e21\:305b\:3001Graph[] \:8a55\:4fa1\:304c\:78ba\:5b9f\:306b\:6210\:7acb\:3059\:308b\:3002 *)
Options[plotPetriNetDetail] = Join[
  {"TraceWid" -> None},
  Options[Graph]
];

plotPetriNetDetail::usage =
  "plotPetriNetDetail[netOrWid] \:306f WorkflowNet \:3092\:30da\:30c8\:30ea\:30cd\:30c3\:30c8\:30b0\:30e9\:30d5\:3068\:3057\:3066\n" <>
  "\:63cf\:753b\:3059\:308b (\:672c\:4f53 plotPetriNet \:306e Tooltip \:62e1\:5f35\:7248)\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3 \"TraceWid\" -> wid \:3092\:6e21\:3059\:3068\:3001Place / Transition / Edge \:306b\n" <>
  "\:30db\:30d0\:30fc Tooltip \:3067\:30c8\:30fc\:30af\:30f3\:5185\:5bb9\:3068 handler \:547c\:3073\:51fa\:3057\:8a73\:7d30 (binding /\n" <>
  "OutputPayload / LLM Prompt / Response) \:3092\:8868\:793a\:3059\:308b\:3002\n" <>
  "wid \:6587\:5b57\:5217\:3092\:76f4\:63a5\:6e21\:3057\:305f\:5834\:5408\:306f\:81ea\:52d5\:7684\:306b \"TraceWid\" -> wid \:30e2\:30fc\:30c9\:306b\:306a\:308b\:3002\n" <>
  "\:901a\:5e38\:306e\:30b0\:30e9\:30d5\:8868\:793a\:306f\:672c\:4f53 plotPetriNet \:3092\:76f4\:63a5\:4f7f\:3046\:3053\:3068 (\:3053\:3061\:3089\:306f\:4e0a\:66f8\:304d\:3057\:306a\:3044)\:3002";

plotPetriNetDetail[netOrWid_,
    opts:OptionsPattern[{plotPetriNetDetail, Graph}]] :=
  Module[{net, traceWid, places, transitions, vertices, finalPlaces, sourcePlace,
          edges, vertexLabels, vertexShapeFn, vertexStyle, edgeLabels,
          isString = StringQ[netOrWid]},

    traceWid = OptionValue["TraceWid"];
    If[isString && traceWid === None, traceWid = netOrWid];

    net = iObsResolveNet[netOrWid];
    If[net === $Failed,
      Print[Style[
        "[plotPetriNetDetail] WorkflowNet \:3068\:3057\:3066\:8a8d\:8b58\:3067\:304d\:307e\:305b\:3093\:3002 " <>
        "wid \:6587\:5b57\:5217\:3092\:6e21\:3057\:305f\:5834\:5408\:306f $iWorkflowNets \:306b\:8a72\:5f53\:30a8\:30f3\:30c8\:30ea\:304c\:5fc5\:8981\:3067\:3059\:3002",
        Red]];
      Return[$Failed]];

    places      = Keys @ Lookup[net, "Places",      <||>];
    transitions = Keys @ Lookup[net, "Transitions", <||>];
    (* \:91cd\:8981: \:5b64\:7acb\:9802\:70b9 (FinalPlaces \:306e "Failed" \:7b49) \:3082\:542b\:3081\:308b\:305f\:3081\:3001\:660e\:793a\:7684\:306b
       \:9802\:70b9\:30ea\:30b9\:30c8\:3092\:69cb\:7bc9\:3059\:308b\:3002Graph[edges, ...] 1 \:5f15\:6570\:5f62\:5f0f\:306f\:8fba\:7aef\:70b9\:3060\:3051\:3057\:304b
       \:63a1\:7528\:305b\:305a\:3001VertexShapeFunction / VertexStyle / VertexLabels \:306e\:6307\:5b9a\:3068
       \:4e0d\:6574\:5408 \[RightArrow] Graph[] \:304c\:672a\:8a55\:4fa1\:3067\:6b8b\:308b\:30d0\:30b0 (review6.nb \:3067 Imai \:5148\:751f\:304c
       \:7279\:5b9a)\:3002 *)
    vertices    = Join[places, transitions];
    sourcePlace = Lookup[net, "SourcePlace", ""];
    finalPlaces = Lookup[net, "FinalPlaces", {}];
    edges       = iObsExtractEdges[net];

    (* === VertexLabels: Tooltip \:3042\:308a\:306a\:3057 === *)
    vertexLabels = If[StringQ[traceWid],
      Join[
        Map[
          # -> Placed[
            Tooltip[Style[#, 9],
                    iObsMkPlaceTooltip[traceWid, #]],
            Center] &,
          places],
        Map[
          # -> Placed[
            Tooltip[Style[#, Bold, White, 8],
                    iObsMkTransitionTooltip[traceWid, #]],
            Center] &,
          transitions]],
      Join[
        (# -> Placed[Style[#, 9], Center]) & /@ places,
        (# -> Placed[Style[#, Bold, White, 8], Center]) & /@ transitions]
    ];

    vertexStyle = Join[
      (# -> Directive[Lighter[Blue, 0.7], EdgeForm[Darker[Blue]]]) & /@ places,
      (# -> Directive[Darker[Red,  0.2], EdgeForm[Black]])         & /@ transitions,
      If[sourcePlace =!= "" && MemberQ[places, sourcePlace],
        {sourcePlace ->
          Directive[Lighter[Yellow, 0.3], EdgeForm[Darker[Yellow]]]},
        {}],
      Map[# -> Directive[Lighter[Green, 0.5], EdgeForm[Darker[Green]]] &,
        Cases[finalPlaces, _String]]];

    vertexShapeFn = Join[
      (# -> "Circle")    & /@ places,
      (* "Rectangle" \:306f Mathematica \:306e\:540d\:524d\:4ed8\:304d vertex shape \:306b\:5b58\:5728\:3057\:306a\:3044\:305f\:3081
         (\:516c\:5f0f\:30c9\:30ad\:30e5\:30e1\:30f3\:30c8: "Square", "Diamond", "ConcaveHexagon" \:306a\:3069\:306f\:6709\:308a\:3001
          "Rectangle" \:306f\:306a\:3057)\:3001Graph[] \:304c\:672a\:8a55\:4fa1\:306e\:307e\:307e\:6b8b\:308b\:30d0\:30b0\:3092\:907f\:3051\:308b\:305f\:3081
         "Square" \:3092\:4f7f\:7528\:3059\:308b\:3002 *)
      (# -> "Square")    & /@ transitions];

    edgeLabels = If[StringQ[traceWid],
      Map[
        Function[ed,
          Module[{src, dst, kind},
            src  = ed[[1]];
            dst  = ed[[2]];
            kind = If[MemberQ[places, src], "InputArc", "OutputArc"];
            ed -> Placed[
              Tooltip[
                Graphics[{
                  Lighter[Gray, 0.5], Disk[{0, 0}, 1]},
                  ImageSize -> 8],
                iObsMkEdgeTooltip[traceWid, src, dst, kind,
                                  places, transitions]],
              0.5]]],
        edges],
      {}];

    (* Imai \:5148\:751f\:306e\:30ec\:30dd\:30fc\:30c8 (review6.nb \:5206\:6790) \:306b\:5f93\:3044\:3001Graph \:306b\:306f\:660e\:793a\:7684\:306a
       \:9802\:70b9\:30ea\:30b9\:30c8\:3092\:6e21\:3059\:3002\:8fba\:3092\:6301\:305f\:306a\:3044\:5b64\:7acb Place ("Failed" \:7b49) \:304c
       FinalPlaces / Places \:306b\:5ba3\:8a00\:3055\:308c\:3066\:3044\:308b\:30b1\:30fc\:30b9\:3067 Graph[edges, ...]
       1 \:5f15\:6570\:5f62\:5f0f\:3060\:3068 VertexShapeFunction \:7b49\:306e\:6307\:5b9a\:3068\:4e0d\:6574\:5408\:306b\:306a\:308a Graph[]
       \:304c\:672a\:8a55\:4fa1\:3067\:6b8b\:308b (v0.1.6 \:3067\:540c\:3058\:4fee\:6b63\:3092\:4e00\:5ea6\:5165\:308c\:305f\:304c v0.1.7 \:3067\:8aa4\:3063\:3066
       \:64a4\:56de\:3057\:3066\:3044\:305f\:3002\:672c\:4fee\:6b63\:3067 v0.1.6 \:306e\:65b9\:5411\:306b\:623b\:3059)\:3002 *)
    Graph[vertices, edges,
      VertexLabels        -> vertexLabels,
      VertexStyle         -> vertexStyle,
      VertexShapeFunction -> vertexShapeFn,
      VertexSize          -> {"Scaled", 0.05},
      EdgeStyle           -> Directive[Gray, Arrowheads[0.022]],
      EdgeLabels          -> edgeLabels,
      ImageSize           -> 850,
      PlotLabel           -> Style[
        ToString[Length[places]] <> " places, " <>
        ToString[Length[transitions]] <> " transitions  " <>
        "(\:9ec4=Source / \:7dd1=Final / \:9752=Place / \:8d64=Transition" <>
        If[StringQ[traceWid], "; \:30db\:30d0\:30fc\:3067\:8a73\:7d30", ""] <> ")",
        13, Bold],
      Sequence @@ FilterRules[{opts}, Options[Graph]]
    ]
  ];

(* ============================================================
   checkPetriNetVertices: net \:306e\:9802\:70b9\:6574\:5408\:6027\:3092\:691c\:67fb\:3059\:308b\:8a3a\:65ad\:30e6\:30fc\:30c6\:30a3\:30ea\:30c6\:30a3\:3002
   Imai \:5148\:751f\:306e\:30ec\:30dd\:30fc\:30c8 (review6.nb) \:306b\:57fa\:3065\:304f\:5b9f\:88c5\:3002

   \:8fd4\:5024: <|
     "DeclaredVertices"         -> Places \:222a Transitions (\:5ba3\:8a00\:6e08\:307f\:9802\:70b9),
     "VerticesFromEdges"        -> \:8fba\:96c6\:5408\:304b\:3089\:5c0e\:51fa\:3055\:308c\:308b\:9802\:70b9,
     "IsolatedDeclaredVertices" -> \:5ba3\:8a00\:3060\:3051\:3067\:8fba\:3092\:6301\:305f\:306a\:3044\:9802\:70b9,
     "UnknownVerticesInEdges"   -> \:8fba\:306b\:73fe\:308c\:308b\:304c\:5ba3\:8a00\:304c\:7121\:3044\:9802\:70b9
   |>

   - IsolatedDeclaredVertices \:304c\:975e\:7a7a -> Graph[edges,...] (1\:5f15\:6570) \:3067\:306f\:63cf\:753b\:843d\:3061\:3002
     Graph[vertices, edges, ...] \:306e 2 \:5f15\:6570\:5f62\:5f0f\:3067\:6e21\:3059\:304b\:3001edges \:306b\:64ec\:4f3c\:8fba\:3092
     \:8db3\:3057\:3066\:53ef\:8996\:5316\:3059\:308b\:5fc5\:8981\:304c\:3042\:308b (plotPetriNet / plotPetriNetDetail \:306f
     \:65e2\:306b 2 \:5f15\:6570\:5f62\:5f0f\:306b\:5bfe\:5fdc\:6e08\:307f)\:3002
   - UnknownVerticesInEdges \:304c\:975e\:7a7a -> handler / iExtractEdges \:306e\:30d0\:30b0\:306e\:53ef\:80fd\:6027\:3002
     Places / Transitions \:306b\:767b\:9332\:6f0f\:308c\:306e\:9802\:70b9\:304c\:3042\:308b\:3002
   ============================================================ *)

checkPetriNetVertices::usage =
  "checkPetriNetVertices[net] \:306f net \:306e Places/Transitions \:5ba3\:8a00\:3068" <>
  " iObsExtractEdges[net] \:304c\:8fd4\:3059\:8fba\:96c6\:5408\:306e\:6574\:5408\:6027\:3092\:691c\:67fb\:3057\:3001" <>
  " IsolatedDeclaredVertices (\:5ba3\:8a00\:3060\:3051\:3067\:8fba\:306a\:3057) \:3068" <>
  " UnknownVerticesInEdges (\:8fba\:3060\:3051\:3067\:5ba3\:8a00\:306a\:3057) \:3092\:542b\:3080 Association \:3092\:8fd4\:3059\:3002";

checkPetriNetVertices[net_Association] :=
  Module[{places, transitions, edges, declared, fromEdges},
    places      = Keys @ Lookup[net, "Places",      <||>];
    transitions = Keys @ Lookup[net, "Transitions", <||>];
    edges       = iObsExtractEdges[net];
    declared    = Join[places, transitions];
    fromEdges   = DeleteDuplicates @ Flatten[List @@@ edges];
    <|
      "DeclaredVertices"         -> declared,
      "VerticesFromEdges"        -> fromEdges,
      "IsolatedDeclaredVertices" -> Complement[declared, fromEdges],
      "UnknownVerticesInEdges"   -> Complement[fromEdges, declared]
    |>
  ];

(* wid \:6587\:5b57\:5217\:3092\:53d7\:3051\:4ed8\:3051\:308b\:5f62 *)
checkPetriNetVertices[wid_String] :=
  Module[{net},
    net = iObsResolveNet[wid];
    If[net === $Failed,
      Print[Style[
        "[checkPetriNetVertices] WorkflowNet \:3068\:3057\:3066\:8a8d\:8b58\:3067\:304d\:307e\:305b\:3093\:3002",
        Red]];
      Return[$Failed]];
    checkPetriNetVertices[net]
  ];

checkPetriNetVertices[_] := $Failed;



(* ::Subsection:: *)
(* 5. traceTransitions: transition firing -> Dataset *)


(* ============================================================
   ClaudeWorkflowTrace[wid] \:306e TransitionFired event \:3092\:57fa\:5e95\:306b\:3001
   $ObservedHandlerLog \:304b\:3089\:30cf\:30f3\:30c9\:30e9\:8a73\:7d30\:3092\:3001$LLMCallLog \:304b\:3089 LLM
   \:547c\:3073\:51fa\:3057\:8a73\:7d30\:3092\:7d50\:5408\:3057\:305f Dataset \:3092\:8fd4\:3059\:3002

   "Detail" -> True \:3067 LLM \:547c\:3073\:51fa\:3057\:306e Model / Prompt \:629c\:7c8b / Response
   \:629c\:7c8b / Duration \:3092\:7d71\:5408\:3057\:305f\:62e1\:5f35 Dataset \:3092\:8fd4\:3059\:3002
   ============================================================ *)

(* ============================================================
   LLM \:5fdc\:7b54\:304c\:30a8\:30e9\:30fc\:30d1\:30bf\:30fc\:30f3\:304b\:5224\:5b9a\:3059\:308b\:3002
   handler \:304c API \:30a8\:30e9\:30fc\:6587\:5b57\:5217\:3092 Payload \:306b\:8a70\:3081\:3066 graceful \:5b8c\:4e86\:3059\:308b\:30b1\:30fc\:30b9
   (\:4f8b: ChatGPT 5.5 / gpt-4.5-preview \:7b49\:306e\:5b58\:5728\:3057\:306a\:3044\:30e2\:30c7\:30eb\:6307\:5b9a\:3067 API \:304c
   "Error: model: gpt-4.5-preview" \:3092\:8fd4\:3057\:305f\:306e\:3092 handler \:304c\:305d\:306e\:307e\:307e
   ReviewChatGPT \:30d5\:30a3\:30fc\:30eb\:30c9\:306b\:683c\:7d0d\:3057\:3066\:901a\:5e38\:7d42\:4e86\:3059\:308b\:30b1\:30fc\:30b9) \:3092\:89b3\:6e2c\:3059\:308b\:3002
   ============================================================ *)
iObsLLMErrorPatternQ[response_] :=
  Module[{s},
    s = ToString[response];
    Which[
      !StringQ[s] || StringLength[s] === 0, False,
      (* claudecode \:306e\:6a19\:6e96\:30a8\:30e9\:30fc\:5fdc\:7b54\:30d1\:30bf\:30fc\:30f3 *)
      StringStartsQ[s, "Error:"],                      True,
      StringStartsQ[s, "[ClaudeQuery error"],          True,
      StringStartsQ[s, "[Error]"],                     True,
      StringStartsQ[s, "[ClaudeQueryBg error"],        True,
      StringStartsQ[s, "$Failed"],                     True,
      (* JSON \:30a8\:30e9\:30fc\:5fdc\:7b54: { "error": ... } *)
      StringMatchQ[s,
        RegularExpression["(?is)^\\s*\\{[^}]*\"error\"[^}]*\\}.*"]],
                                                       True,
      (* \:77ed\:3044\:5fdc\:7b54\:306b "error" \:5358\:8a9e: API \:30b9\:30c6\:30fc\:30bf\:30b9\:6587\:5b57\:5217\:306e\:53ef\:80fd\:6027\:304c\:9ad8\:3044 *)
      StringLength[s] < 120 &&
        StringContainsQ[s, "error", IgnoreCase -> True], True,
      True,                                            False
    ]
  ];

(* transition \:540d + \:89b3\:6e2c\:6642\:523b\:3067 $LLMCallLog \:304b\:3089\:8a72\:5f53\:547c\:3073\:51fa\:3057\:3092\:62bd\:51fa\:3002
   refTime \:304c Missing \:306a\:3089 transition \:540d\:306e\:307f\:3067\:7167\:5408\:3002 *)
iObsLLMCallsForFiring[transName_String, refTime_, tol_:60.0] :=
  Module[{cands},
    cands = Select[$LLMCallLog,
      Lookup[#, "TransitionName", ""] === transName &];
    If[NumericQ[refTime] && Length[cands] > 1,
      Select[cands,
        NumericQ[Lookup[#, "Time", Missing[]]] &&
          Abs[Lookup[#, "Time", 0.0] - refTime] <= tol &],
      cands]
  ];

(* ============================================================
   Status \:5224\:5b9a (\:672c\:4f53 ExecutorStatus \:3092\:76f2\:4fe1\:305b\:305a\:3001\:89b3\:6e2c\:30ed\:30b0\:3092\:512a\:5148)\:3002

   \:80cc\:666f: \:672c\:4f53 iExecutePureFunction \:306e\:7f60 #16 (Quiet@Check) \:306b\:3088\:308a\:3001
        handler \:5185\:3067 $Failed \:3092\:8fd4\:3057\:3066\:3082\:30e1\:30c3\:30bb\:30fc\:30b8\:304c\:51fa\:3066\:3082\:3001
        ExecutorStatus \:306f "Success" \:306b\:306a\:308b\:5834\:5408\:304c\:3042\:308b\:3002
        \:89b3\:6e2c\:30e9\:30c3\:30d1 ($ObservedHandlerLog) \:304c\:6355\:307e\:3048\:305f\:5b9f\:614b\:3092\:512a\:5148\:3059\:308b\:3002

   \:3055\:3089\:306b v0.1.2 \:3067\:306f handler \:30ec\:30d9\:30eb\:304c OK \:3067\:3082 LLM \:30ec\:30d9\:30eb\:3067
   API \:304c\:30a8\:30e9\:30fc\:3092\:8fd4\:3057\:3066\:3044\:308b\:5834\:5408 ("Error: model: gpt-4.5-preview" \:7b49\:3092
   handler \:304c graceful \:306b Payload \:306b\:8a70\:3081\:308b\:30b1\:30fc\:30b9) \:3092\:691c\:51fa\:3059\:308b\:3002

   v0.2.1 (2026-05-17): Z \:6848 (handler \:5185\:975e\:540c\:671f LLM) \:3067 handler \:304c
   <|Status -> "AwaitingLLM"|> \:3092\:540c\:671f return \:3059\:308b\:30d1\:30bf\:30fc\:30f3\:3092\:6b63\:5f0f Status \:3068
   \:3057\:3066\:8b58\:5225\:3059\:308b\:3002\:3053\:308c\:306f\:300cPayload \:30ad\:30fc\:304c\:7121\:3044\:300d\:304c\:3001\:7570\:5e38\:3067\:306f\:306a\:304f\:300cLLM \:5fdc\:7b54\:3092
   \:5f85\:3063\:3066\:3044\:308b\:300d\:72b6\:614b\:3002PayloadKeyMissing \:5224\:5b9a\:3088\:308a\:524d\:306b\:7f6e\:304f\:5fc5\:8981\:304c\:3042\:308b\:3002
   \:540c\:69d8\:306b <|Status -> "Skip"|> \:3082\:4eca\:5f8c\:306e\:4f7f\:3044\:9053\:306b\:5099\:3048\:3066\:533a\:5225\:3059\:308b\:3002

   \:8fd4\:5024\:306e\:4f8b:
     "OK"                                  \:6b63\:5e38\:5b8c\:4e86
     "Failed ($Failed)"                    handler \:304c $Failed \:3092\:8fd4\:3057\:305f
     "Errored (3 msg)"                     $MessageList \:306b 3 \:4ef6\:30e1\:30c3\:30bb\:30fc\:30b8
     "BadOutput (String)"                  Association \:4ee5\:5916\:304c\:8fd4\:3063\:305f
     "AwaitingLLM"                         Z \:6848: handler \:304c\:975e\:540c\:671f LLM \:5f85\:3061
     "Skip"                                handler \:304c transition skip \:3092\:8981\:6c42
     "NoPayload"                           Association \:3060\:304c "Payload" \:30ad\:30fc\:306a\:3057
     "LLMError (1/1)"                      LLM \:547c\:3073\:51fa\:3057\:304c API \:30a8\:30e9\:30fc\:3092\:8fd4\:3057\:305f
                                            (handler \:306f graceful \:306b\:901a\:3057\:305f\:304c)
     "LLMError (1/2)"                      LLM \:547c\:3073\:51fa\:3057\:306e\:4e00\:90e8\:304c\:30a8\:30e9\:30fc
     "<ExecutorStatus>"                    \:89b3\:6e2c\:30ed\:30b0\:304c\:306a\:3044\:5834\:5408\:306e\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af
   ============================================================ *)
iObsDeriveStatus[execStatus_, obs_, llmCalls_:{}] :=
  Module[{nMsg, hasObs, llmTotal, llmErr, outStatus},
    hasObs = AssociationQ[obs] && KeyExistsQ[obs, "Index"];
    llmTotal = If[ListQ[llmCalls], Length[llmCalls], 0];
    llmErr = If[llmTotal > 0,
      Count[llmCalls,
        c_ /; iObsLLMErrorPatternQ[Lookup[c, "Response", ""]]],
      0];
    If[!hasObs,
      Return[
        If[llmErr > 0,
          "LLMError (" <> ToString[llmErr] <> "/" <> ToString[llmTotal] <> ")",
          ToString[execStatus]]
      ]];
    nMsg = Length[Lookup[obs, "Messages", {}]];
    outStatus = Lookup[obs, "OutputStatus", Missing[]];
    Which[
      TrueQ[Lookup[obs, "FailedHead", False]],
        "Failed ($Failed)",
      nMsg > 0,
        "Errored (" <> ToString[nMsg] <> " msg)",
      !TrueQ[Lookup[obs, "OutputAssocQ", False]],
        "BadOutput (" <> ToString[Lookup[obs, "OutputHead", "?"]] <> ")",
      (* v0.2.1: Status \:4e00\:7d1a\:30d5\:30a3\:30fc\:30eb\:30c9\:3067\:8b58\:5225 (PayloadKeyMissing \:3088\:308a\:524d) *)
      outStatus === "AwaitingLLM",
        "AwaitingLLM",
      outStatus === "Skip",
        "Skip",
      TrueQ[Lookup[obs, "PayloadKeyMissing", False]],
        "NoPayload",
      llmErr > 0,
        "LLMError (" <> ToString[llmErr] <> "/" <> ToString[llmTotal] <> ")",
      True,
        "OK"
    ]
  ];

Options[traceTransitions] = {
  "Detail"             -> False,
  "PromptPreviewLen"   -> 200,
  "ResponsePreviewLen" -> 200,
  "TimeMatchTolerance" -> 60.0   (* sec; firing \:3068 LLM call \:306e\:6642\:523b\:30de\:30c3\:30c1\:8a31\:5bb9\:5e45 *)
};

traceTransitions::usage =
  "traceTransitions[wid] \:306f workflow id wid \:306e transition firing \:3092 Dataset \:3067\:8fd4\:3059\:3002\n" <>
  "\:30c7\:30d5\:30a9\:30eb\:30c8\:3067\:306f Step / Transition / Status / OutputAssoc? / OutputHead / RawKeys /\n" <>
  "PayloadKeys / PayloadKeyMissing / FailedHead / Messages / ConsumedIds / ProducedIds\n" <>
  "\:3092\:8868\:793a\:3059\:308b\:3002\n" <>
  "Status \:30ab\:30e9\:30e0\:304c\:53d6\:308a\:3046\:308b\:5024:\n" <>
  "  OK / Failed ($Failed) / Errored (N msg) / BadOutput / AwaitingLLM / Skip /\n" <>
  "  NoPayload / LLMError (M/N) / <ExecutorStatus>\n" <>
  "  - AwaitingLLM: handler \:304c <|Status -> \"AwaitingLLM\"|> \:3092\:8fd4\:3057\:305f\:72b6\:614b (Z \:6848)\n" <>
  "  - Skip:        handler \:304c <|Status -> \"Skip\"|> \:3092\:8fd4\:3057\:305f\:72b6\:614b\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3 \"Detail\" -> True \:3067\:5404 firing \:306b\:5bfe\:5fdc\:3059\:308b LLM \:547c\:3073\:51fa\:3057 (Model / Prompt /\n" <>
  "Response \:306e\:629c\:7c8b / Duration) \:3092\:7d71\:5408\:3057\:305f\:62e1\:5f35 Dataset \:3092\:8fd4\:3059\:3002";

(* \:540c\:3058 transition \:304c\:4f55\:5ea6\:767a\:706b\:3059\:308b\:30b1\:30fc\:30b9\:306b\:5099\:3048\:3001firing \:6642\:523b\:3068 handler trace \:6642\:523b\:304c
   \:6700\:3082\:8fd1\:3044 1 \:4ef6\:3092\:9078\:3076\:3002Workflow trace \:306e "Timestamp" \:306f Mathematica \:306e AbsoluteTime
   \:5f62\:5f0f\:3068\:9650\:3089\:306a\:3044\:305f\:3081\:3001\:6570\:5024\:30de\:30c3\:30c1\:306b\:5931\:6557\:3057\:305f\:3089\:9806\:5e8f\:30d9\:30fc\:30b9\:3067\:53d6\:308b\:3002 *)
iObsObservedFor[transName_String, ts_, alreadyTaken_List] :=
  Module[{cands, available, chosen},
    cands = Select[$ObservedHandlerLog,
      Lookup[#, "TransitionName", ""] === transName &];
    available = Select[cands,
      !MemberQ[alreadyTaken, Lookup[#, "Index", -1]] &];
    If[Length[available] === 0,
      Return[<||>]];
    chosen = If[NumericQ[ts] && Length[available] > 1,
      First @ MinimalBy[available, Abs[Lookup[#, "Time", 0.0] - ts] &],
      First[available]];
    chosen
  ];

traceTransitions[wid_String, opts:OptionsPattern[]] :=
  Module[{trace, fired, detail, plen, rlen, tol,
          takenObs, llmCands, llmFor, baseRows},

    detail = TrueQ[OptionValue["Detail"]];
    plen   = OptionValue["PromptPreviewLen"];
    rlen   = OptionValue["ResponsePreviewLen"];
    tol    = OptionValue["TimeMatchTolerance"];

    trace = Quiet[ClaudeWorkflowTrace[wid]];
    If[!ListQ[trace], trace = {}];
    (* TransitionFired \:3068 TransitionFailed (\:65b0: atomic rollback \:3055\:308c\:305f fire) \:306e
       \:4e21\:65b9\:3092\:62fe\:3046\:3002Fired \:7cfb\:3068\:3057\:3066\:6271\:3044\:3001\:5f8c\:6bb5\:306e iObsDeriveStatus \:304c ExecutorStatus
       \:306b\:57fa\:3065\:304d Status \:30ab\:30e9\:30e0\:3092\:6b63\:3057\:304f "Failed (...)" \:7b49\:306b\:8868\:793a\:3059\:308b\:3002 *)
    fired = Select[trace,
      MemberQ[{"TransitionFired", "TransitionFailed"}, #[["Event"]]] &];

    If[Length[fired] === 0 && Length[$ObservedHandlerLog] === 0,
      Print[Style[
        "[traceTransitions] firing trace \:3082 $ObservedHandlerLog \:3082\:7a7a\:3067\:3059\:3002",
        Orange]];
      Return[Dataset[{}]]];

    (* fired \:304c\:7a7a\:3067\:3082 $ObservedHandlerLog \:304c\:3042\:308b\:5834\:5408\:306f handler log \:304b\:3089\:7d44\:3080\:3002
       (\:4f8b: ClaudeWorkflowTrace \:304c\:7121\:3044\:74b0\:5883\:3001\:307e\:305f\:306f\:624b\:52d5 handler \:547c\:3073\:51fa\:3057) *)
    If[Length[fired] === 0,
      fired = MapIndexed[
        <|"Event"          -> "TransitionFired",
          "TransitionName" -> Lookup[#1, "TransitionName", "?"],
          "ExecutorStatus" -> If[TrueQ[Lookup[#1, "FailedHead", False]],
                                "Failed", "Success"],
          "ConsumedIds"    -> {},
          "ProducedIds"    -> {},
          "Timestamp"      -> Lookup[#1, "Time", AbsoluteTime[]]|> &,
        $ObservedHandlerLog];
    ];

    (* \:5404 firing \:306b handler trace \:3092 1:1 \:3067\:30de\:30c3\:30c1\:3002\:540c\:3058 transition \:306e\:8907\:6570 firing \:306f
       \:6642\:523b\:9806 (= log \:9806) \:3067\:305a\:3089\:3057\:306a\:304c\:3089\:53d6\:308b\:3002 *)
    takenObs = {};
    baseRows = MapIndexed[
      Module[{step = First[#2], ev = #1, obs, ts, execStatus,
              derivedStatus, transName, refTime, llmCallsForRow},
        ts = Lookup[ev, "Timestamp", Missing[]];
        transName = Lookup[ev, "TransitionName", "?"];
        obs = iObsObservedFor[transName, ts, takenObs];
        If[AssociationQ[obs] && KeyExistsQ[obs, "Index"],
          AppendTo[takenObs, obs[["Index"]]]];
        execStatus    = Lookup[ev, "ExecutorStatus", "?"];
        refTime       = Lookup[obs, "Time", Missing[]];
        llmCallsForRow = iObsLLMCallsForFiring[transName, refTime, tol];
        derivedStatus = iObsDeriveStatus[execStatus, obs, llmCallsForRow];
        <|"Step"              -> step,
          "Transition"        -> transName,
          "Status"            -> derivedStatus,
          "Attempt"           -> Lookup[ev, "AttemptCount", Missing[]],
          "OutputAssoc?"      -> Lookup[obs, "OutputAssocQ", Missing[]],
          "OutputHead"        -> ToString[Lookup[obs, "OutputHead", Missing[]]],
          "RawKeys"           -> Lookup[obs, "RawKeys", Missing[]],
          "PayloadKeys"       -> Lookup[obs, "PayloadKeys", Missing[]],
          "PayloadKeyMissing" -> Lookup[obs, "PayloadKeyMissing", Missing[]],
          "FailedHead"        -> Lookup[obs, "FailedHead", Missing[]],
          "Messages"          -> Length[Lookup[obs, "Messages", {}]],
          "ConsumedIds"       -> Length[Lookup[ev, "ConsumedIds", {}]],
          "ProducedIds"       -> Length[Lookup[ev, "ProducedIds", {}]],
          (* Detail \:30e2\:30fc\:30c9\:3067\:4f7f\:3046\:8ffd\:52a0\:60c5\:5831\:3092\:57cb\:3081\:8fbc\:3093\:3067\:304a\:304f (\:975eDetail \:3067\:306f\:524a\:308b) *)
          "_execStatus"       -> ToString[execStatus],
          "_obsTime"          -> Lookup[obs, "Time", Missing[]],
          "_obsDuration"      -> Lookup[obs, "Duration", Missing[]],
          "_bindingKeys"      -> Lookup[obs, "BindingKeys", Missing[]]|>] &,
      fired];

    If[!detail,
      Return[Dataset[
        Map[KeyDrop[#, {"_execStatus", "_obsTime", "_obsDuration",
                        "_bindingKeys"}] &,
          baseRows]]]];

    (* === Detail \:30e2\:30fc\:30c9: LLM \:547c\:3073\:51fa\:3057\:3092 transition + \:6642\:523b\:3067\:30de\:30c3\:30c1 === *)
    (* \:5404 firing \:306b\:5bfe\:3057\:3001$LLMCallLog \:304b\:3089
         (a) TransitionName \:4e00\:81f4
         (b) Time \:304c _obsTime \[PlusMinus] tol \:4ee5\:5185 (handler \:8d77\:52d5\:6642\:523b\:306b\:8fd1\:3044)
       \:306e 1 \:4ef6\:4ee5\:4e0a\:3092\:53d6\:308b\:3002\:8907\:6570\:3042\:308c\:3070 prompt/response \:3092\:7d50\:5408\:8868\:793a\:3002 *)
    llmCands = $LLMCallLog;
    llmFor[transName_, refTime_] :=
      Module[{cands},
        cands = Select[llmCands,
          Lookup[#, "TransitionName", ""] === transName &&
          (NumericQ[refTime] && NumericQ[Lookup[#, "Time", Missing[]]] &&
           Abs[Lookup[#, "Time", 0.0] - refTime] <= tol) &];
        cands];

    Dataset[
      Map[
        Function[r,
          Module[{calls, callRow, refTime},
            refTime = Lookup[r, "_obsTime", Missing[]];
            calls = If[NumericQ[refTime],
              llmFor[r[["Transition"]], refTime],
              Select[llmCands,
                Lookup[#, "TransitionName", ""] === r[["Transition"]] &]];
            callRow = If[Length[calls] === 0,
              <|"LLMCalls"          -> 0,
                "Model"             -> Missing[],
                "PromptLen"         -> 0,
                "ResponseLen"       -> 0,
                "Duration(s)"       -> 0,
                "Prompt(preview)"   -> "",
                "Response(preview)" -> ""|>,
              Module[{c = First[calls]},
                <|"LLMCalls"        -> Length[calls],
                  "Model"           -> ToString[Lookup[c, "Model", "?"]],
                  "PromptLen"       -> Lookup[c, "PromptLen", 0],
                  "ResponseLen"     -> Lookup[c, "ResponseLen", 0],
                  "Duration(s)"     -> Round[Lookup[c, "Duration", 0.0], 0.01],
                  "Prompt(preview)" -> StringTake[
                    ToString[Lookup[c, "Prompt", ""]], UpTo[plen]],
                  "Response(preview)" -> StringTake[
                    ToString[Lookup[c, "Response", ""]], UpTo[rlen]]|>]];
            <|"Step"              -> r[["Step"]],
              "Transition"        -> r[["Transition"]],
              "Status"            -> r[["Status"]],
              "ExecStatus"        -> r[["_execStatus"]],
              "RawKeys"           -> r[["RawKeys"]],
              "PayloadKeys"       -> r[["PayloadKeys"]],
              "PayloadKeyMissing" -> r[["PayloadKeyMissing"]],
              "FailedHead"        -> r[["FailedHead"]],
              "Messages"          -> r[["Messages"]],
              "BindingKeys"       -> r[["_bindingKeys"]],
              "HandlerDur(s)"     -> Round[
                If[NumericQ[Lookup[r, "_obsDuration", Missing[]]],
                  Lookup[r, "_obsDuration", 0.0], 0.0], 0.001],
              "LLMCalls"          -> callRow[["LLMCalls"]],
              "Model"             -> callRow[["Model"]],
              "PromptLen"         -> callRow[["PromptLen"]],
              "ResponseLen"       -> callRow[["ResponseLen"]],
              "LLMDur(s)"         -> callRow[["Duration(s)"]],
              "Prompt(preview)"   -> callRow[["Prompt(preview)"]],
              "Response(preview)" -> callRow[["Response(preview)"]]
            |>]],
        baseRows]
    ]
  ];

