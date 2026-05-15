# ClaudeOrchestrator_observability API リファレンス

petri_from_prompt.wl 用の観測 (observability) 補完モジュール。LLM 呼び出しログ、Handler 観測、生成コードへの logger 注入、Tooltip 付き可視化、transition 追跡 Dataset を提供する。本体 `ClaudeQueryBg` / `parsePetriCode` / `plotPetriNet` は上書きせず、別関数として共存させる設計。

依存: `ClaudeOrchestrator`Workflow``, `ClaudeCode`ClaudeQueryBg`, petri_from_prompt.wl (v0.10.0+)。

## バージョン

### $petriObservabilityVersion
型: String, 初期値: "0.2.0 (2026-05-11)"
パッケージのバージョン文字列。

## LLM 呼び出しログ

### $LLMCallLog
型: List of Association, 初期値: {}
`ClaudeQueryBgLogged` が記録した全 LLM 呼び出しのログ。各エントリは `<|"Index", "Time", "TimeStr", "Duration", "TransitionName", "Model", "Fallback", "Prompt", "PromptLen", "Response", "ResponseLen", "OptionList"|>`。既存ログを温存するため、未定義のときだけ初期化される。

### ClaudeQueryBgLogged[prompt, opts]
`ClaudeCode`ClaudeQueryBg` を呼び出し、開始時刻 / 所要時間 / Model / Fallback / プロンプト / 応答を `$LLMCallLog` に追記する。呼び出し中に `$CurrentObservedTransition` が束縛されていれば transition 名も記録する。`ClaudeQueryBg` 本体は変更しないので Options / Protect / Context の整合は壊れない。
→ ClaudeQueryBg の戻り値

### showLLMCallLog[] → Dataset | $Failed
`$LLMCallLog` を Dataset (#, Time, Trans, Model, PromptLen, ResponseLen, Duration, Preview の各列) で表示する。空なら $Failed を返す。

### showLLMCallLog[idx_Integer] → Column | $Failed
`$LLMCallLog[[idx]]` の Prompt / Response を含む詳細を Pretty Print する。範囲外なら $Failed。

### clearLLMCallLog[] → String
`$LLMCallLog` を `{}` にリセットする。"$LLMCallLog cleared" を返す。

## Handler 観測

### $ObservedHandlerLog
型: List of Association, 初期値: {}
`instrumentNetForObservation` で包んだ handler の呼び出し記録。各エントリは `<|"Index", "TransitionName", "Time", "TimeStr", "Duration", "BindingKeys", "BindingPayloads", "OutputRaw", "OutputAssocQ", "OutputHead", "RawKeys", "PayloadKeys", "PayloadKeyMissing", "OutputPayload", "Messages", "FailedHead", "HandlerType"|>`。

### $CurrentObservedTransition
型: String, 初期値: "?"
観測ラッパが `Block[{$CurrentObservedTransition = tname}, ...]` で動的束縛する transition 名。`ClaudeQueryBgLogged` がこの値を参照してログに transition 名を埋める。

### instrumentNetForObservation[net_Association] → net'
net の全 transition の Handler を観測ラッパで包んだ新しい net を返す。副次効果として Symbol handler も明示的に `handler[binding]` 形式の Function でくるまれるので、本体 `iExecutePureFunction` の Symbol/Function 判定差バグも回避できる。Block で `$CurrentObservedTransition` を局所束縛するので、handler 内の `ClaudeQueryBgLogged` が transition 名を取得できる。

### instrumentNetForObservation[trans_Association, tname_String] → trans'
単一 transition Association の Handler のみを観測ラッパで包む下位 API。

### clearObservedHandlerLog[] → String
`$ObservedHandlerLog` を `{}` にリセットする。"$ObservedHandlerLog cleared" を返す。

## 生成コードへの logger 注入

### withLLMLogging[code_String] → String
code 内の `ClaudeCode`ClaudeQueryBg` および無修飾 `ClaudeQueryBg` 呼び出しを `Global`ClaudeQueryBgLogged` に置換した新しい文字列を返す。関数名のみを書き換えるので、Function スコープ / 局所変数 / HoldAll などには影響しない。完全修飾を先に処理し、無修飾は前後を識別子文字でない位置に限定する正規表現で照合する。

## 可視化

### plotPetriNetDetail[netOrWid, opts]
WorkflowNet をペトリネットグラフとして描画する Tooltip 拡張版。本体 `plotPetriNet` は上書きしない別関数。`"TraceWid" -> wid` で Place / Transition / Edge にホバー Tooltip (トークン内容 / handler binding / OutputPayload / LLM Prompt / Response / firing event) を表示する。wid 文字列を直接渡した場合は自動的に `"TraceWid" -> wid` モードになる。net 解決失敗時は `$Failed`。
→ Graph | $Failed
Options:
- "TraceWid" -> None (wid 文字列。Tooltip 用の trace 元 workflow id)
- Options[Graph] のすべて (VertexLayout, ImageSize 等が透過に渡せる)

例: `plotPetriNetDetail[wid, VertexLayout -> "LayeredDigraphEmbedding"]`

### checkPetriNetVertices[net_Association] → Association
net の Places/Transitions 宣言と `iObsExtractEdges[net]` の辺集合の整合性を検査する。返値は `<|"DeclaredVertices", "VerticesFromEdges", "IsolatedDeclaredVertices", "UnknownVerticesInEdges"|>`。`IsolatedDeclaredVertices` が非空なら `Graph[edges,...]` 1 引数形式では描画落ちする (2 引数形式が必要)。`UnknownVerticesInEdges` が非空なら Places/Transitions の登録漏れを示す。

### checkPetriNetVertices[wid_String] → Association | $Failed
wid から net を解決して `checkPetriNetVertices[net]` を呼ぶ。解決失敗時は $Failed。

### checkPetriNetVertices[_] → $Failed
それ以外の引数では `$Failed`。

## transition 追跡 Dataset

### traceTransitions[wid_String, opts]
workflow id wid の transition firing を Dataset で返す。`ClaudeWorkflowTrace[wid]` の `TransitionFired` / `TransitionFailed` event を基底に、`$ObservedHandlerLog` から handler 詳細、`$LLMCallLog` から LLM 呼び出し詳細を結合する。firing trace が空でも `$ObservedHandlerLog` があれば handler log から行を組む。
→ Dataset
列 (デフォルト): Step / Transition / Status / Attempt / OutputAssoc? / OutputHead / RawKeys / PayloadKeys / PayloadKeyMissing / FailedHead / Messages / ConsumedIds / ProducedIds
列 (Detail): Step / Transition / Status / ExecStatus / RawKeys / PayloadKeys / PayloadKeyMissing / FailedHead / Messages / BindingKeys / HandlerDur(s) / LLMCalls / Model / PromptLen / ResponseLen / LLMDur(s) / Prompt(preview) / Response(preview)
Options:
- "Detail" -> False (True で LLM Prompt/Response 抜粋と本体 ExecStatus を含む拡張 Dataset)
- "PromptPreviewLen" -> 200 (Detail モードでの Prompt 抜粋長)
- "ResponsePreviewLen" -> 200 (Detail モードでの Response 抜粋長)
- "TimeMatchTolerance" -> 60.0 (sec; firing と LLM call の時刻マッチ許容幅)

Status の値:
- `"OK"` 正常完了
- `"Failed ($Failed)"` handler が $Failed を返した
- `"Errored (N msg)"` $MessageList に N 件メッセージ
- `"BadOutput (<Head>)"` Association 以外が返った
- `"NoPayload"` Association だが "Payload" キーなし
- `"LLMError (M/N)"` LLM 呼び出し N 件中 M 件が API エラー応答 (handler は graceful に通したが API が "Error: ..." 等を返したケース)
- それ以外は本体 ExecutorStatus を文字列化

例:
```
traceTransitions[wid]
traceTransitions[wid, "Detail" -> True, "PromptPreviewLen" -> 500]
```

## 内部 API (アンダースコア相当、外部から直接使わない)

### iObsExtractEdges[net_Association] → List
net の Transitions から InputArcs / OutputArcs を辿って `place -> tname` / `tname -> place` の有向辺リストを返す。

### iObsMakeHandlerWrapper[handler_, tname_String] → Function
observed wrapper を生成する。クロージャとして handler / tname を保持し、`Block[{$CurrentObservedTransition = tname, $MessageList = {}}, ...]` の中で `Quiet[handler[binding]]` を実行、出力と $MessageList を `$ObservedHandlerLog` に追記する。Symbol/Function/Identity/CompoundExpression いずれの handler でも `handler[binding]` 形式に統一して呼ぶ。

### iObsHandlerTraceFor[transName_String] → List
`$ObservedHandlerLog` と `ClaudeOrchestrator`Workflow`Private`$iHandlerTraceLog` から該当 transition のエントリを連結して返す。

### iObsLLMCallsFor[transName_String] → List
`$LLMCallLog` から transition 名一致のエントリを返す。

### iObsLLMCallsForFiring[transName_String, refTime_, tol_:60.0] → List
transition 名一致のうち、refTime ± tol 以内のものを返す。候補が 1 件以下なら時刻フィルタを掛けず全件返す。

### iObsLLMErrorPatternQ[response_] → True | False
response が LLM API エラーパターンか判定する。`"Error:"` / `"[ClaudeQuery error"` / `"[Error]"` / `"[ClaudeQueryBg error"` / `"$Failed"` で始まる、JSON `{"error": ...}` 形式、または短い応答 (<120 文字) で "error" を含むケースを True と判定する。

### iObsMkPlaceTooltip[wid_String, place_String] → Column
Place ホバー時の Tooltip 表示用 Column。`getTokensInPlace[wid, place]` で取得したトークンの TokenId / Kind / Payload を一覧表示する。

### iObsMkTransitionTooltip[wid_String, trans_String] → Column
Transition ホバー時の Tooltip。handler trace 行 (RawKeys / PayloadKeys / FailedHead / PayloadKeyMissing / BindingPayloads / OutputPayload / Messages) と LLM call 行 (Model / Duration / PromptLen / ResponseLen / Prompt / Response) を表示。

### iObsMkEdgeTooltip[wid_String, src_String, dst_String, kind_String, placesList_, transitionsList_] → Column
Edge ホバー時の Tooltip。`ClaudeWorkflowTrace[wid]` から該当 transition の `TransitionFired` / `TransitionFailed` event を抽出し、Step / Status / ConsumedIds / ProducedIds を表示。kind は `"InputArc"` か `"OutputArc"`。

### iObsResolveNet[netOrWid_] → Association | $Failed
引数が net Association ("Places" を含む) ならそのまま返し、String なら `ClaudeOrchestrator`Workflow`Private`$iWorkflowNets[wid]` から取得する。失敗時は $Failed。

### iObsObservedFor[transName_String, ts_, alreadyTaken_List] → Association
`$ObservedHandlerLog` から transition 名一致のうち、`alreadyTaken` (Index リスト) に含まれない 1 件を時刻ベースで選ぶ。数値時刻が無ければ順序ベース (List 先頭)。該当無しは `<||>`。

### iObsDeriveStatus[execStatus_, obs_, llmCalls_:{}] → String
Status カラムの文字列を導出する。観測ログ (obs) を優先し、`FailedHead` → Messages 件数 → OutputAssocQ → PayloadKeyMissing → LLM エラー件数 の順で判定。観測ログが無ければ execStatus の文字列化、ただし LLM エラーがあれば `"LLMError (M/N)"`。

## 推奨フロー

```
Needs["ClaudeOrchestrator`Workflow`"]
Get["petri_from_prompt.wl"]
Get["ClaudeOrchestrator_observability.wl"]

prop = proposePetriNet[
  "Claude Opus と ChatGPT 5.5 で並列レビュー",
  "Providers" -> {"anthropic", "openai"},
  "InputPayloadKeys" -> {"Text"}];

loggedCode = withLLMLogging[prop[["Code"]]];
net0 = parsePetriCode[loggedCode];
net  = instrumentNetForObservation[net0];

clearLLMCallLog[]; clearObservedHandlerLog[];

wid = ClaudeCreateWorkflowNet[net];
ClaudeSubmitToken[wid,
  WorkflowToken["Kind" -> "Task", "Payload" -> <|"Text" -> $exampleDraftAbstract|>],
  "Source"];
ClaudeRunWorkflow[wid, "Async" -> True];

plotPetriNet[wid]
plotPetriNetDetail[wid]
traceTransitions[wid]
traceTransitions[wid, "Detail" -> True]
showLLMCallLog[]
showLLMCallLog[3]