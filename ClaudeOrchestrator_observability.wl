(* ::Package:: *)

(* ::Title:: *)
(* ClaudeOrchestrator_observability.wl *)

(* ::Text:: *)
(* 旧名: petri_observability.wl (v0.1.9 まで)。
   v0.2.0 (2026-05-11) で ClaudeOrchestrator_observability.wl に改名。
   petri_from_prompt.wl と petri_from_prompt_chatgpt.wl のマージ
   (proposePetriNetWithProvider → proposePetriNet 統一) に合わせ、
   名称の整合性を取った。
   内部 API / 公開シンボル / 動作は完全互換。 *)

(* ::Subsection:: *)
(* 概要 *)

(* ============================================================
   petri_from_prompt.wl (v0.10.0+ 統合版、旧 petri_from_prompt_chatgpt.wl の
   機能を吸収済み) への観測 (observability) 補完モジュール。

   目的:
     「no review が出ない」ような不可解な現象に対して、
       1. そもそもモデル選択ができていない
       2. LLM に渡るプロンプトがおかしい
       3. LLM の出力がおかしい
       4. LLM の出力は OK だが、その後の抽出に失敗
     のどこに起因するか *瞬時に* 判別できる観測手段を提供する。

   設計原則 (Session_Pitfalls_Summary.md の教訓を反映):
     - ClaudeQueryBg 本体を wrap しない。新関数 ClaudeQueryBgLogged を作る。
       (Pitfall C: Options/Context/Protect 整合の崩壊回避)
     - parsePetriCode に手を入れない。net Association 取得 *後* に instrument。
       (Pitfall D: Return 経路に副作用を挟む危険を回避)
     - 静的検査は追加しない。false positive で LLM をミスリードしない。
       (Pitfall A の回避)
     - 文字列置換は「関数名 -> 関数名」のみ。Function/Module スコープに触れない。
       (Pitfall E: 文字列レベルでの Function ラップによる scope 破壊と区別)
     - 観測 API を 1 件入れた瞬間に真因が見える設計を優先。
       (Pitfall F: 観測なしで仮説を膨らませない)

   提供する公開シンボル:

     --- LLM 呼び出しログ ---
     ClaudeQueryBgLogged[prompt, opts]
     $LLMCallLog
     showLLMCallLog[]                Dataset 一覧
     showLLMCallLog[idx]             1 件 Pretty Print
     clearLLMCallLog[]

     --- Handler 観測 (本体パッチ非依存) ---
     instrumentNetForObservation[net]
     $ObservedHandlerLog
     clearObservedHandlerLog[]

     --- 生成コードへの logger 注入 ---
     withLLMLogging[code_String]

     --- 可視化 (本体 plotPetriNet とは独立の別関数) ---
     plotPetriNetDetail[netOrWid, opts]
       Tooltip 付き詳細表示。本体 plotPetriNet は上書きせず温存する。
       オプション "TraceWid" -> wid を渡すと Tooltip でノード/辺の情報を表示。
       wid を直接渡した場合は自動的に Tooltip モードになる。
       Graph のオプション (VertexLayout 等) もそのまま渡せる
       (Options[plotPetriNetDetail] = Join[..., Options[Graph]] のため)。

     --- transition 追跡 Dataset ---
     traceTransitions[wid, opts]
       Status は観測ログ優先で判定 (本体 ExecutorStatus を盲信しない)。
         OK / Failed ($Failed) / Errored (N msg) / BadOutput /
         AwaitingLLM / Skip / NoPayload / LLMError (M/N)
       "Detail" -> True で LLM 呼び出し詳細 + 本体 ExecStatus を併記。

   依存関係:
     - petri_from_prompt.wl  (plotPetriNet, getTokensInPlace, iExtractEdges)
     - ClaudeOrchestrator`Workflow`
       (ClaudeWorkflowTrace, ClaudeWorkflowState 公開 API のみ使用)
     - ClaudeCode`ClaudeQueryBg

   バージョン:
     v0.1.0 (2026-05-10): 初版。
     v0.1.1 (2026-05-10): Status 判定を観測ログ優先に変更。
       本体 iExecutePureFunction の罠 #16 で握り潰された $Failed や
       抑制メッセージを Status カラムに反映する。Detail モードに
       本体由来の ExecStatus カラムを追加して両者の食い違いを可視化。
     v0.1.2 (2026-05-10): LLM 応答エラーパターン検出を追加。
       handler が API エラー文字列 ("Error: model: gpt-4.5-preview" 等)
       を Payload に graceful 格納するケースを Status に反映:
       LLMError (1/1) のように LLM レイヤー失敗を表示。
     v0.1.3 (2026-05-10): traceTransitions / plotPetriNet Tooltip が
       TransitionFailed event (atomic firing rollback) も取り込むよう拡張。
     v0.1.4 (2026-05-10): traceTransitions Dataset に Attempt カラム追加
       (RetryPolicy で複数回試行された transition の attempts 数を可視化)。
     v0.1.5 (2026-05-10): plotPetriNet 末尾の FilterRules[...] を
       Sequence @@ で展開する修正 (review2.nb で Graph[] が `{}` を末尾
       引数として受け取り未評価で残る問題への対応)。
     v0.1.6 (2026-05-10, 撤回済): Graph 2 引数形式 (頂点リスト, edge リスト)
       への切替を試みたが review3/4.nb で改善せず、Imai 先生から本体
       plotPetriNet 上書き方針自体への異議を受領。
     v0.1.7 (2026-05-10): 設計方針を転換。本体 petri_from_prompt.wl の
       plotPetriNet は上書きせず温存。Tooltip 拡張は別関数
       plotPetriNetDetail として提供 (Imai 先生の指示)。
       - 本体 plotPetriNet は標準のグラフ描画を担う (動作実績あり)
       - plotPetriNetDetail[wid] / plotPetriNetDetail[net, "TraceWid"->wid]
         を Tooltip 付き観測用に使う
       - Options[plotPetriNetDetail] = Join[{"TraceWid"->None}, Options[Graph]]
         として、Graph オプション (VertexLayout 等) もそのまま受け取れる
     v0.1.8 (2026-05-11): "Rectangle" vertex shape バグ修正。
       VertexShapeFunction -> {..., transition -> "Rectangle", ...} の
       "Rectangle" は Mathematica の名前付き vertex shape として未定義
       (公式ドキュメント: "Square", "Diamond", "ConcaveHexagon" 等は
       あるが "Rectangle" は無し)。"Square" に置換した。
     v0.1.9 (2026-05-11): plotPetriNet 描画失敗の真因にようやく到達。
       Imai 先生の review6.nb 分析レポートに従い、Graph に明示的な頂点
       リストを渡す 2 引数形式 Graph[vertices, edges, ...] に変更
       (vertices = Join[places, transitions])。
       これは v0.1.6 で一度実施した修正と同じだが、当時 Imai 先生の
       「以前の plotPetriNet 定義に戻ってほしい」を「2 引数形式の撤回まで
       含む」と過剰解釈して v0.1.7 で誤って撤回していた。実際のご指示の
       趣旨は「本体上書きをやめてドキュメントを読み直せ」であり、
       2 引数形式そのものは否定されていなかった。

       真因の整理 (review.nb 〜 review6.nb の一連):
         - "Failed" のような孤立 Place (FinalPlaces にあるが辺を持たない)
           が含まれる net で、Graph[edges, ...] の 1 引数形式は辺端点しか
           頂点採用しない -> VertexShapeFunction / VertexStyle / VertexLabels
           の指定と不整合 -> Graph[] が未評価のまま残る (review2-6.nb)
         - 本体 petri_from_prompt.wl の plotPetriNet も同じバグを持つ
           ので本ファイルと同梱で本体側も修正する
         - v0.1.5 (Sequence @@ FilterRules), v0.1.8 ("Rectangle" -> "Square")
           は別の小バグ修正で、本質的修正は本 v0.1.9 のみ

       同時に Imai 先生提示の検査ユーティリティ checkPetriNetVertices を
       追加。net の頂点整合性 (IsolatedDeclaredVertices /
       UnknownVerticesInEdges) を診断できる。

     v0.2.0 (2026-05-11): ファイル名を ClaudeOrchestrator_observability.wl
       に改名。petri_from_prompt.wl と petri_from_prompt_chatgpt.wl の
       マージ (proposePetriNet 統一) と並行した命名整合化。
       内部 API / 公開シンボル / 動作は完全互換。
       コメント中の Get["petri_from_prompt_chatgpt.wl"] 言及を削除し、
       proposePetriNetWithProvider への参照を proposePetriNet に統一。
     v0.2.1 (2026-05-17): Z 案 (handler 内非同期 LLM) との連携対応。
       handler が <|Status -> "AwaitingLLM"|> を同期 return するパターンを
       Status カラムで正式に区別できるようにした。
       - iObsMakeHandlerWrapper の log entry に OutputStatus フィールド追加
         (output が Association + Status キーを持つときに値を記録)
       - iObsDeriveStatus の Which に AwaitingLLM / Skip 分岐を追加
         (PayloadKeyMissing 判定より前で優先評価)
       - これにより Z 案 handler の正常な AwaitingLLM 戻り値が "NoPayload"
         に誤分類されるのを防ぐ。
       - completion 側 (ClaudeCompleteHandlerOutput 経由の finalize) の
         観測は本 patch の対象外。Stage 2-B / C で別途扱う。
*)

Needs["ClaudeOrchestrator`Workflow`"];

(* ::Subsection:: *)
(* 公開シンボル宣言 *)

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
  (* Plot extension - 本体 plotPetriNet は上書きせず、別関数として提供 *)
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
  iObsDeriveStatus
];

$petriObservabilityVersion = "0.2.1 (2026-05-17)";

(* 既存ログを温存するため、未定義のときだけ初期化 *)
If[!ListQ[$LLMCallLog],         $LLMCallLog = {}];
If[!ListQ[$ObservedHandlerLog], $ObservedHandlerLog = {}];
If[!StringQ[$CurrentObservedTransition], $CurrentObservedTransition = "?"];

(* ::Subsection:: *)
(* 1. ClaudeQueryBgLogged *)

(* ============================================================
   ClaudeQueryBgLogged は ClaudeQueryBg を *呼び出す側* の関数として
   実装し、ClaudeQueryBg 本体 / Options / DownValues は一切変更しない。
   handler ラッパが Block[{$CurrentObservedTransition = tname}, ...] で
   囲むので、ここで $CurrentObservedTransition を読めば transition 名が
   取れる。
   ============================================================ *)

ClaudeQueryBgLogged::usage =
  "ClaudeQueryBgLogged[prompt, opts] は ClaudeCode`ClaudeQueryBg と同じ呼び出しを行い、" <>
  " 開始時刻 / 所要時間 / Model / Fallback / プロンプト / 応答を $LLMCallLog に追記する。" <>
  " 呼び出し中に $CurrentObservedTransition が束縛されていれば、その transition 名も記録する。" <>
  " ClaudeQueryBg 本体は変更しないので、Options / Protect / Context の整合は壊れない。";

ClaudeQueryBgLogged[prompt_, opts:OptionsPattern[]] :=
  Module[{t0, t1, response, transName, optAssoc, model, fallback, entry},
    t0 = AbsoluteTime[];
    transName = If[StringQ[$CurrentObservedTransition],
      $CurrentObservedTransition, "?"];

    optAssoc = Association[opts];
    model    = Lookup[optAssoc, ClaudeCode`Model,    Automatic];
    fallback = Lookup[optAssoc, ClaudeCode`Fallback, False];

    response = ClaudeCode`ClaudeQueryBg[prompt, opts];
    t1 = AbsoluteTime[];

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
      "OptionList"     -> {opts}
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
      Row[{Style["Model:       ", Bold], ToString[Lookup[entry, "Model", "?"]]}],
      Row[{Style["Fallback:    ", Bold], ToString[Lookup[entry, "Fallback", False]]}],
      Row[{Style["Duration:    ", Bold],
        ToString[Round[Lookup[entry, "Duration", 0.0], 0.001]] <> " s"}],
      Row[{Style["PromptLen:   ", Bold], ToString[Lookup[entry, "PromptLen", 0]]}],
      Row[{Style["ResponseLen: ", Bold], ToString[Lookup[entry, "ResponseLen", 0]]}],
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
   net 内の全 transition の Handler を観測ラッパで包んだ新しい net を返す。
   副次効果:
     - Symbol handler でも明示的に handler[binding] を呼ぶラッパで包むので、
       本体 iExecutePureFunction の Symbol/Function 判定差バグ (Bug 2) を回避。
     - Block で $CurrentObservedTransition を局所束縛するので、handler 内で
       ClaudeQueryBgLogged が transition 名を知ることができる。
   ============================================================ *)

clearObservedHandlerLog[] := ($ObservedHandlerLog = {}; "$ObservedHandlerLog cleared");

instrumentNetForObservation::usage =
  "instrumentNetForObservation[net] は net の各 transition の Handler を" <>
  " 観測ラッパで包んだ新しい net を返す。$ObservedHandlerLog に handler 呼び出しの" <>
  " binding / output / messages が記録されるようになる。" <>
  " Symbol handler も Function ラッパでくるまれるので、本体側 iExecutePureFunction の" <>
  " Symbol/Function 判定差バグも同時に回避する。";

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

(* 観測ラッパ生成。クロージャとして handler / tname を保持する。
   罠 #15 回避: Map 内の Function に Return/Throw を入れない、
   罠 #16 回避: Quiet@Check は使わず Quiet[expr] のみ + フラグ別取得。 *)
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
        (* v0.2.1 (2026-05-17): Z 案で handler が <|Status -> "AwaitingLLM"|>
           を返す場合や、ワークフロー固有の <|Status -> "Skip"|> を返す場合に、
           Status 文字列を一級フィールドとして記録する。Missing[] = Status キー無し。
           iObsDeriveStatus が PayloadKeyMissing より優先で AwaitingLLM 等を
           区別できるようにする。 *)
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
   生成コード中の ClaudeQueryBg 呼び出しを ClaudeQueryBgLogged に
   置換する。関数名 -> 関数名 の置換のみ。Function や Module スコープ、
   binding には触れない。Pitfall E (文字列レベルの Function ラップで
   評価コンテキストが壊れた問題) とは性格が違う。
   ============================================================ *)

withLLMLogging::usage =
  "withLLMLogging[code_String] は code 内の `ClaudeQueryBg` 呼び出しを" <>
  " `Global`ClaudeQueryBgLogged` に置換した新しい文字列を返す。" <>
  " ClaudeCode`ClaudeQueryBg と無修飾 ClaudeQueryBg の両方を扱う。" <>
  " 関数名のみを書き換えるので、Function スコープ / 局所変数 / HoldAll などには影響しない。";

withLLMLogging[code_String] :=
  StringReplace[code, {
    (* 1. context 完全修飾を先に処理 (これ以降のルールで再処理されない) *)
    "ClaudeCode`ClaudeQueryBg" -> "Global`ClaudeQueryBgLogged",
    (* 2. 無修飾 ClaudeQueryBg。前後を識別子文字でない位置に限定 *)
    RegularExpression[
      "(?<![A-Za-z0-9`$])ClaudeQueryBg(?![A-Za-z0-9])"] :>
      "Global`ClaudeQueryBgLogged"
  }];

(* ::Subsection:: *)
(* 4. plotPetriNetDetail (Tooltip 拡張版、本体 plotPetriNet と共存) *)

(* ============================================================
   plotPetriNetDetail は本体 petri_from_prompt.wl の plotPetriNet とは
   独立の別関数。"TraceWid" -> wid を渡すと、Place / Transition / Edge
   にホバーで token / handler trace / firing event の詳細を表示する。

   本体 plotPetriNet は上書きせず温存する (Imai 先生の指示, 2026-05-10)。
   通常のグラフ表示には本体 plotPetriNet を使い、Tooltip ありの詳細表示が
   必要なときだけ plotPetriNetDetail を呼び出す運用とする。
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
        (* 罠 #16 回避: Quiet@Check は使わない。Association 戻り値を握り潰すため。
           Quiet[expr] のみで取得し、AssociationQ で判定する。 *)
        state = Quiet[ClaudeOrchestrator`Workflow`Private`$iWorkflowNets[netOrWid]];
        If[AssociationQ[state] && KeyExistsQ[state, "Places"],
          state,
          (* fallback: ClaudeWorkflowState は Marking しか返さないので
             net 構造が無い。$iWorkflowNets が無い環境では plot 不可。 *)
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
    (* 罠 #16 回避: Quiet@Check は使わない。Quiet で評価し ListQ で判定。 *)
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
    (* 罠 #16 回避: Quiet@Check は使わない。Quiet で評価し ListQ で判定。 *)
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

(* plotPetriNetDetail は本体 plotPetriNet と OptionsPattern を揃え、
   かつ追加で "TraceWid" オプションを受け付ける形にする。
   こうすることで本体と同じ Graph オプション (VertexLabels の追加等) も
   呼び出し側から渡せ、Graph[] 評価が確実に成立する。 *)
Options[plotPetriNetDetail] = Join[
  {"TraceWid" -> None},
  Options[Graph]
];

plotPetriNetDetail::usage =
  "plotPetriNetDetail[netOrWid] は WorkflowNet をペトリネットグラフとして\n" <>
  "描画する (本体 plotPetriNet の Tooltip 拡張版)。\n" <>
  "オプション \"TraceWid\" -> wid を渡すと、Place / Transition / Edge に\n" <>
  "ホバー Tooltip でトークン内容と handler 呼び出し詳細 (binding /\n" <>
  "OutputPayload / LLM Prompt / Response) を表示する。\n" <>
  "wid 文字列を直接渡した場合は自動的に \"TraceWid\" -> wid モードになる。\n" <>
  "通常のグラフ表示は本体 plotPetriNet を直接使うこと (こちらは上書きしない)。";

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
    (* 重要: 孤立頂点 (FinalPlaces の "Failed" 等) も含めるため、明示的に
       頂点リストを構築する。Graph[edges, ...] 1 引数形式は辺端点だけしか
       採用せず、VertexShapeFunction / VertexStyle / VertexLabels の指定と
       不整合 → Graph[] が未評価で残るバグ (review6.nb で Imai 先生が
       特定)。 *)
    vertices    = Join[places, transitions];
    sourcePlace = Lookup[net, "SourcePlace", ""];
    finalPlaces = Lookup[net, "FinalPlaces", {}];
    edges       = iObsExtractEdges[net];

    (* === VertexLabels: Tooltip ありなし === *)
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

    (* Imai 先生のレポート (review6.nb 分析) に従い、Graph には明示的な
       頂点リストを渡す。辺を持たない孤立 Place ("Failed" 等) が
       FinalPlaces / Places に宣言されているケースで Graph[edges, ...]
       1 引数形式だと VertexShapeFunction 等の指定と不整合になり Graph[]
       が未評価で残る (v0.1.6 で同じ修正を一度入れたが v0.1.7 で誤って
       撤回していた。本修正で v0.1.6 の方向に戻す)。 *)
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
   checkPetriNetVertices: net の頂点整合性を検査する診断ユーティリティ。
   Imai 先生のレポート (review6.nb) に基づく実装。

   返値: <|
     "DeclaredVertices"         -> Places ∪ Transitions (宣言済み頂点),
     "VerticesFromEdges"        -> 辺集合から導出される頂点,
     "IsolatedDeclaredVertices" -> 宣言だけで辺を持たない頂点,
     "UnknownVerticesInEdges"   -> 辺に現れるが宣言が無い頂点
   |>

   - IsolatedDeclaredVertices が非空 -> Graph[edges,...] (1引数) では描画落ち。
     Graph[vertices, edges, ...] の 2 引数形式で渡すか、edges に擬似辺を
     足して可視化する必要がある (plotPetriNet / plotPetriNetDetail は
     既に 2 引数形式に対応済み)。
   - UnknownVerticesInEdges が非空 -> handler / iExtractEdges のバグの可能性。
     Places / Transitions に登録漏れの頂点がある。
   ============================================================ *)

checkPetriNetVertices::usage =
  "checkPetriNetVertices[net] は net の Places/Transitions 宣言と" <>
  " iObsExtractEdges[net] が返す辺集合の整合性を検査し、" <>
  " IsolatedDeclaredVertices (宣言だけで辺なし) と" <>
  " UnknownVerticesInEdges (辺だけで宣言なし) を含む Association を返す。";

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

(* wid 文字列を受け付ける形 *)
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
   ClaudeWorkflowTrace[wid] の TransitionFired event を基底に、
   $ObservedHandlerLog からハンドラ詳細を、$LLMCallLog から LLM
   呼び出し詳細を結合した Dataset を返す。

   "Detail" -> True で LLM 呼び出しの Model / Prompt 抜粋 / Response
   抜粋 / Duration を統合した拡張 Dataset を返す。
   ============================================================ *)

(* ============================================================
   LLM 応答がエラーパターンか判定する。
   handler が API エラー文字列を Payload に詰めて graceful 完了するケース
   (例: ChatGPT 5.5 / gpt-4.5-preview 等の存在しないモデル指定で API が
   "Error: model: gpt-4.5-preview" を返したのを handler がそのまま
   ReviewChatGPT フィールドに格納して通常終了するケース) を観測する。
   ============================================================ *)
iObsLLMErrorPatternQ[response_] :=
  Module[{s},
    s = ToString[response];
    Which[
      !StringQ[s] || StringLength[s] === 0, False,
      (* claudecode の標準エラー応答パターン *)
      StringStartsQ[s, "Error:"],                      True,
      StringStartsQ[s, "[ClaudeQuery error"],          True,
      StringStartsQ[s, "[Error]"],                     True,
      StringStartsQ[s, "[ClaudeQueryBg error"],        True,
      StringStartsQ[s, "$Failed"],                     True,
      (* JSON エラー応答: { "error": ... } *)
      StringMatchQ[s,
        RegularExpression["(?is)^\\s*\\{[^}]*\"error\"[^}]*\\}.*"]],
                                                       True,
      (* 短い応答に "error" 単語: API ステータス文字列の可能性が高い *)
      StringLength[s] < 120 &&
        StringContainsQ[s, "error", IgnoreCase -> True], True,
      True,                                            False
    ]
  ];

(* transition 名 + 観測時刻で $LLMCallLog から該当呼び出しを抽出。
   refTime が Missing なら transition 名のみで照合。 *)
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
   Status 判定 (本体 ExecutorStatus を盲信せず、観測ログを優先)。

   背景: 本体 iExecutePureFunction の罠 #16 (Quiet@Check) により、
        handler 内で $Failed を返してもメッセージが出ても、
        ExecutorStatus は "Success" になる場合がある。
        観測ラッパ ($ObservedHandlerLog) が捕まえた実態を優先する。

   さらに v0.1.2 では handler レベルが OK でも LLM レベルで
   API がエラーを返している場合 ("Error: model: gpt-4.5-preview" 等を
   handler が graceful に Payload に詰めるケース) を検出する。

   v0.2.1 (2026-05-17): Z 案 (handler 内非同期 LLM) で handler が
   <|Status -> "AwaitingLLM"|> を同期 return するパターンを正式 Status と
   して識別する。これは「Payload キーが無い」が、異常ではなく「LLM 応答を
   待っている」状態。PayloadKeyMissing 判定より前に置く必要がある。
   同様に <|Status -> "Skip"|> も今後の使い道に備えて区別する。

   返値の例:
     "OK"                                  正常完了
     "Failed ($Failed)"                    handler が $Failed を返した
     "Errored (3 msg)"                     $MessageList に 3 件メッセージ
     "BadOutput (String)"                  Association 以外が返った
     "AwaitingLLM"                         Z 案: handler が非同期 LLM 待ち
     "Skip"                                handler が transition skip を要求
     "NoPayload"                           Association だが "Payload" キーなし
     "LLMError (1/1)"                      LLM 呼び出しが API エラーを返した
                                            (handler は graceful に通したが)
     "LLMError (1/2)"                      LLM 呼び出しの一部がエラー
     "<ExecutorStatus>"                    観測ログがない場合のフォールバック
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
      (* v0.2.1: Status 一級フィールドで識別 (PayloadKeyMissing より前) *)
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
  "TimeMatchTolerance" -> 60.0   (* sec; firing と LLM call の時刻マッチ許容幅 *)
};

traceTransitions::usage =
  "traceTransitions[wid] は workflow id wid の transition firing を Dataset で返す。\n" <>
  "デフォルトでは Step / Transition / Status / OutputAssoc? / OutputHead / RawKeys /\n" <>
  "PayloadKeys / PayloadKeyMissing / FailedHead / Messages / ConsumedIds / ProducedIds\n" <>
  "を表示する。\n" <>
  "Status カラムが取りうる値:\n" <>
  "  OK / Failed ($Failed) / Errored (N msg) / BadOutput / AwaitingLLM / Skip /\n" <>
  "  NoPayload / LLMError (M/N) / <ExecutorStatus>\n" <>
  "  - AwaitingLLM: handler が <|Status -> \"AwaitingLLM\"|> を返した状態 (Z 案)\n" <>
  "  - Skip:        handler が <|Status -> \"Skip\"|> を返した状態\n" <>
  "オプション \"Detail\" -> True で各 firing に対応する LLM 呼び出し (Model / Prompt /\n" <>
  "Response の抜粋 / Duration) を統合した拡張 Dataset を返す。";

(* 同じ transition が何度発火するケースに備え、firing 時刻と handler trace 時刻が
   最も近い 1 件を選ぶ。Workflow trace の "Timestamp" は Mathematica の AbsoluteTime
   形式と限らないため、数値マッチに失敗したら順序ベースで取る。 *)
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
    (* TransitionFired と TransitionFailed (新: atomic rollback された fire) の
       両方を拾う。Fired 系として扱い、後段の iObsDeriveStatus が ExecutorStatus
       に基づき Status カラムを正しく "Failed (...)" 等に表示する。 *)
    fired = Select[trace,
      MemberQ[{"TransitionFired", "TransitionFailed"}, #[["Event"]]] &];

    If[Length[fired] === 0 && Length[$ObservedHandlerLog] === 0,
      Print[Style[
        "[traceTransitions] firing trace \:3082 $ObservedHandlerLog \:3082\:7a7a\:3067\:3059\:3002",
        Orange]];
      Return[Dataset[{}]]];

    (* fired が空でも $ObservedHandlerLog がある場合は handler log から組む。
       (例: ClaudeWorkflowTrace が無い環境、または手動 handler 呼び出し) *)
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

    (* 各 firing に handler trace を 1:1 でマッチ。同じ transition の複数 firing は
       時刻順 (= log 順) でずらしながら取る。 *)
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
          (* Detail モードで使う追加情報を埋め込んでおく (非Detail では削る) *)
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

    (* === Detail モード: LLM 呼び出しを transition + 時刻でマッチ === *)
    (* 各 firing に対し、$LLMCallLog から
         (a) TransitionName 一致
         (b) Time が _obsTime ± tol 以内 (handler 起動時刻に近い)
       の 1 件以上を取る。複数あれば prompt/response を結合表示。 *)
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

(* ::Subsection:: *)
(* 6. \:30ed\:30fc\:30c9\:5b8c\:4e86\:30e1\:30c3\:30bb\:30fc\:30b8 *)

Print[Style[
  "ClaudeOrchestrator_observability v" <> $petriObservabilityVersion <>
  " \:304c\:30ed\:30fc\:30c9\:3055\:308c\:307e\:3057\:305f\:3002", Bold]];
Print["
\:516c\:958b API:

  --- LLM \:547c\:3073\:51fa\:3057\:30ed\:30b0 ---
  ClaudeQueryBgLogged[prompt, opts]    \[RightArrow] ClaudeQueryBg + \:30ed\:30b0\:8a18\:9332
  $LLMCallLog                          \[RightArrow] \:5168 LLM \:547c\:3073\:51fa\:3057\:306e\:8a18\:9332 (List)
  showLLMCallLog[]                     \[RightArrow] Dataset \:8868\:793a
  showLLMCallLog[idx]                  \[RightArrow] 1 \:4ef6\:306e prompt/response \:3092 Pretty Print
  clearLLMCallLog[]

  --- Handler \:89b3\:6e2c (\:672c\:4f53\:30d1\:30c3\:30c1\:975e\:4f9d\:5b58) ---
  instrumentNetForObservation[net]     \[RightArrow] \:5168 handler \:3092\:89b3\:6e2c\:30e9\:30c3\:30d1\:3067\:5305\:3080
                                          \:526f\:6b21\:52b9\:679c: Symbol handler \:3082 Function \:5316
  $ObservedHandlerLog                  \[RightArrow] \:89b3\:6e2c\:30ed\:30b0
  clearObservedHandlerLog[]

  --- \:751f\:6210\:30b3\:30fc\:30c9\:3078\:306e logger \:6ce8\:5165 ---
  withLLMLogging[code_String]          \[RightArrow] ClaudeQueryBg \[RightArrow] ClaudeQueryBgLogged

  --- \:53ef\:8996\:5316 (\:672c\:4f53 plotPetriNet \:3068\:306f\:5225\:95a2\:6570\:3001\:540c\:6642\:4f7f\:7528\:53ef) ---
  plotPetriNet[net]                       \[RightArrow] \:672c\:4f53\:306e\:5358\:7d14\:30b0\:30e9\:30d5 (petri_from_prompt.wl)
  plotPetriNetDetail[net]                 \[RightArrow] Tooltip \:7121\:3057\:7248
  plotPetriNetDetail[net, \"TraceWid\" -> wid]
                                          \[RightArrow] Place / Transition / Edge \:306b Tooltip
  plotPetriNetDetail[wid]                 \[RightArrow] wid \:304b\:3089\:81ea\:52d5\:7684\:306b net \:53d6\:5f97 + Tooltip
  checkPetriNetVertices[net]              \[RightArrow] \:9802\:70b9\:6574\:5408\:6027\:691c\:67fb (\:5b64\:7acb\:9802\:70b9/\:672a\:5b9a\:7fa9\:9802\:70b9\:306e\:691c\:51fa)

  --- transition \:8ffd\:8de1 Dataset ---
  traceTransitions[wid]                \[RightArrow] \:57fa\:672c Dataset
                                          (Status / RawKeys / PayloadKeys /
                                          FailedHead / Messages \:7b49)
                                          Status \:306f\:89b3\:6e2c\:30ed\:30b0\:512a\:5148\:3067\:5224\:5b9a:
                                            OK / Failed (\\$Failed) /
                                            Errored (N msg) / BadOutput /
                                            NoPayload / LLMError (M/N)
                                          LLMError \:306f handler \:306f\:6210\:529f\:3057\:305f\:304c
                                          API \:5fdc\:7b54\:304c\:30a8\:30e9\:30fc\:6587\:5b57\:5217\:306e\:30b1\:30fc\:30b9
                                          (\:4f8b: \"Error: model: ...\")
  traceTransitions[wid, \"Detail\" -> True]
                                       \[RightArrow] LLM Prompt / Response \:629c\:7c8b
                                          \:3068 ExecStatus (\:672c\:4f53\:5224\:5b9a) \:3092\:542b\:3080

\:63a8\:5968\:30d5\:30ed\:30fc (Pitfall A-F \:5168\:56de\:907f\:578b):

  Needs[\"ClaudeOrchestrator`Workflow`\"]
  Get[\"petri_from_prompt.wl\"]                       (* v0.10.0+ \:7d71\:5408\:7248 *)
  Get[\"ClaudeOrchestrator_observability.wl\"]

  prop = proposePetriNet[
    \"Claude Opus \:3068 ChatGPT 5.5 \:3067\:4e26\:5217\:30ec\:30d3\:30e5\:30fc\",
    \"Providers\" -> {\"anthropic\", \"openai\"},
    \"InputPayloadKeys\" -> {\"Text\"}];

  loggedCode = withLLMLogging[prop[[\"Code\"]]];     (* LLM \:30ed\:30b0\:6ce8\:5165 *)
  net0 = parsePetriCode[loggedCode];                (* \:65e2\:5b58 parser \:3092\:4f7f\:3046 *)
  net  = instrumentNetForObservation[net0];          (* handler \:89b3\:6e2c\:30e9\:30c3\:30d1 *)

  clearLLMCallLog[]; clearObservedHandlerLog[];

  wid = ClaudeCreateWorkflowNet[net];
  ClaudeSubmitToken[wid, WorkflowToken[\"Kind\" -> \"Task\",
    \"Payload\" -> <|\"Text\" -> $exampleDraftAbstract|>], \"Source\"];
  ClaudeRunWorkflow[wid, \"Async\" -> True];

  (* \:5b8c\:8d70\:5f8c\:306e\:89b3\:6e2c *)
  plotPetriNet[wid]                                 (* \:672c\:4f53\:306e\:5358\:7d14\:30b0\:30e9\:30d5 *)
  plotPetriNetDetail[wid]                           (* \:30c8\:30fc\:30af\:30f3\:5185\:5bb9\:30fbhandler\:8a73\:7d30\:3092Tooltip\:8868\:793a *)
  traceTransitions[wid]                             (* \:57fa\:672c Dataset *)
  traceTransitions[wid, \"Detail\" -> True]           (* LLM \:8a73\:7d30\:542b\:3080 *)
  showLLMCallLog[]                                  (* \:5168 LLM \:547c\:3073\:51fa\:3057\:4e00\:89a7 *)
  showLLMCallLog[3]                                 (* 3 \:4ef6\:76ee\:306e prompt/response *)
"];
