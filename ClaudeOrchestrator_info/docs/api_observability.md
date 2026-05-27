# ClaudeOrchestrator_observability API リファレンス

`petri_from_prompt.wl` ベースの WorkflowNet 実行に対する観測 (observability) 補完モジュール。LLM 呼び出しログ・Handler 観測・transition 追跡・Tooltip 付き可視化を提供する。

依存: `petri_from_prompt.wl` (plotPetriNet, getTokensInPlace, iExtractEdges), [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) (`ClaudeWorkflowTrace`, `ClaudeWorkflowState`), [claudecode](https://github.com/transreal/claudecode) (`ClaudeQueryBg`)。

## 変数

### $petriObservabilityVersion
型: String, 初期値: "0.3.0 (2026-05-26)"
バージョン文字列。

### $LLMCallLog
型: List of Association, 初期値: {}
ClaudeQueryBgLogged 呼び出し履歴。各エントリは Index, Time, TimeStr, Duration, TransitionName, Model, Fallback, Prompt, PromptLen, Response, ResponseLen, OptionList, ProviderKind, ProviderDisplayName, HarnessBundleId, DirectiveSnapshotId, RuntimeEnvironmentHash, ProviderResultMetadata を持つ。

### $ObservedHandlerLog
型: List of Association, 初期値: {}
instrumentNetForObservation 経由で記録された handler 呼び出しログ。各エントリは Index, TransitionName, Time, TimeStr, Duration, BindingKeys, BindingPayloads, OutputRaw, OutputAssocQ, OutputHead, RawKeys, PayloadKeys, PayloadKeyMissing, OutputPayload, OutputStatus, Messages, FailedHead, HandlerType を持つ。

### $CurrentObservedTransition
型: String, 初期値: "?"
観測ラッパが Block で束縛する現在の transition 名。ClaudeQueryBgLogged がこれを参照して log entry に記録する。

## LLM 呼び出しログ

### ClaudeQueryBgLogged[prompt, opts]
ClaudeCode\`ClaudeQueryBg と同一引数で呼び出し、開始時刻 / 所要時間 / Model / Fallback / Prompt / Response を $LLMCallLog に追記してから応答をそのまま返す。$CurrentObservedTransition が束縛中ならその transition 名も記録。ClaudeQueryBg 本体・Options・Protect は一切変更しない。応答が ProviderResultMetadata を持つ Association ならその provenance キーを log entry に lift する。
→ ClaudeQueryBg の戻り値そのまま

### clearLLMCallLog[] → String
$LLMCallLog を {} に戻す。"$LLMCallLog cleared" を返す。

### showLLMCallLog[] → Dataset | $Failed
$LLMCallLog 一覧を #, Time, Trans, Provider, Model, PromptLen, ResponseLen, Duration, Preview カラムの Dataset として返す。空なら警告を Print して $Failed。

### showLLMCallLog[idx_Integer] → Column | $Failed
idx 番目のエントリを Pretty Print する Column を返す。範囲外なら警告を Print して $Failed。Time, Transition, Provider, Model, Fallback, Duration, PromptLen, ResponseLen, HarnessBundle / DirectiveSnapshot / RuntimeEnvHash (Missing 以外のとき), Prompt, Response を表示する。

## Handler 観測

### instrumentNetForObservation[net_Association] → net'
net 内の全 transition の Handler を観測ラッパで包んだ新しい net を返す。元の net は破壊しない。Symbol handler も明示的に handler[binding] を呼ぶ Function ラッパで包む (本体 iExecutePureFunction の Symbol/Function 判定差バグ回避)。各呼び出し時に Block で $CurrentObservedTransition = tname を束縛し、$ObservedHandlerLog にエントリを追記する。

### instrumentNetForObservation[trans_Association, tname_String] → trans'
単一 transition Association を観測用にラップして返す内部多重定義。RuntimeSpec の Handler を差し替える。

### clearObservedHandlerLog[] → String
$ObservedHandlerLog を {} に戻す。"$ObservedHandlerLog cleared" を返す。

## logger 注入

### withLLMLogging[code_String] → String
code 内の `ClaudeCode\`ClaudeQueryBg` および無修飾 `ClaudeQueryBg` 呼び出しを `Global\`ClaudeQueryBgLogged` に置換した文字列を返す。関数名のみを書き換え、Function スコープ / 局所変数 / HoldAll などには触れない。識別子境界を正規表現で限定して安全に置換する。

## 可視化

### plotPetriNetDetail[netOrWid, opts]
WorkflowNet を Tooltip 付きペトリネットグラフとして描画する。本体 plotPetriNet は上書きせず別関数として共存。netOrWid が String なら $iWorkflowNets から net を解決し自動的に "TraceWid" -> netOrWid モードになる。"TraceWid" -> wid が有効な場合、Place には現在のトークン、Transition には handler / LLM 呼び出し詳細、Edge には firing event をホバー Tooltip で表示する。Graph の vertex list は Join[places, transitions] を明示的に渡し、孤立 Place ("Failed" 等) も描画される。
→ Graph | $Failed
Options:
- "TraceWid" -> None (workflow id 文字列。None ならツールチップなし)
- Options[Graph] の全オプション (VertexLayout 等もそのまま透過)

例: `plotPetriNetDetail[wid]` / `plotPetriNetDetail[net, "TraceWid" -> wid, VertexLayout -> "LayeredDigraphEmbedding"]`

### checkPetriNetVertices[net_Association] → Association
net の頂点整合性を診断する。
→ <|"DeclaredVertices" -> {...}, "VerticesFromEdges" -> {...}, "IsolatedDeclaredVertices" -> {...}, "UnknownVerticesInEdges" -> {...}|>
IsolatedDeclaredVertices が非空なら Graph[edges,...] 1 引数形式では描画落ちする可能性、UnknownVerticesInEdges が非空なら handler / iExtractEdges 側のバグ可能性を示す。

### checkPetriNetVertices[wid_String] → Association | $Failed
wid から net を解決して同上の診断を返す。解決失敗時は Print して $Failed。

### checkPetriNetVertices[_] → $Failed
それ以外は $Failed。

## Transition 追跡

### traceTransitions[wid_String, opts]
wid の TransitionFired / TransitionFailed event を ClaudeWorkflowTrace から取得し、$ObservedHandlerLog の handler 詳細・$LLMCallLog の LLM 呼び出し詳細を結合した Dataset を返す。Status カラムは観測ログ優先で判定し、本体 ExecutorStatus を盲信しない。
→ Dataset
Options:
- "Detail" -> False (True で LLM 呼び出しの Model / Prompt 抜粋 / Response 抜粋 / Duration / Attempt を統合した拡張 Dataset を返す)
- "PromptPreviewLen" -> 200 (Detail モードでの Prompt 抜粋長)
- "ResponsePreviewLen" -> 200 (Detail モードでの Response 抜粋長)
- "TimeMatchTolerance" -> 60.0 (firing と LLM call の時刻マッチ許容秒数)

Status が取りうる値:
- "OK" 正常完了
- "Failed ($Failed)" handler が $Failed を返した
- "Errored (N msg)" $MessageList に N 件メッセージ
- "BadOutput (Head)" Association 以外が返った
- "AwaitingLLM" handler が <|Status -> "AwaitingLLM"|> を返した (Z 案: 非同期 LLM 待ち)
- "Skip" handler が <|Status -> "Skip"|> を返した
- "NoPayload" Association だが "Payload" キーなし
- "LLMError (M/N)" N 件の LLM 呼び出しのうち M 件が API エラー応答
- "<ExecutorStatus>" 観測ログが無い場合のフォールバック

例: `traceTransitions[wid, "Detail" -> True]`

## 内部 API (補助)

### iProviderDisplayName[id_String] → String
provider id ("chatgptcodex", "ChatGPTCodexCLI", "claude" 等) を UI 表示名 ("ChatGPT Codex", "Claude", "LM Studio", "OpenAI", "Unknown") に正規化。未知 id はそのまま返す。

### iProviderDisplayName[___] → "Unknown"
非文字列 fallback。

### iObsExtractEdges[net_Association] → List of Rule
net の Transitions から InputArcs / OutputArcs を走査し、place -> transition / transition -> place の Rule リストを返す。

### iObsResolveNet[netOrWid] → net | $Failed
Association ならそのまま、String なら ClaudeOrchestrator\`Workflow\`Private\`$iWorkflowNets から検索。失敗時 $Failed。

### iObsHandlerTraceFor[transName_String] → List
$ObservedHandlerLog と ClaudeOrchestrator\`Workflow\`Private\`$iHandlerTraceLog から transName 一致分を連結して返す。

### iObsLLMCallsFor[transName_String] → List
$LLMCallLog から TransitionName == transName のエントリを返す。

### iObsLLMCallsForFiring[transName_String, refTime_, tol_:60.0] → List
$LLMCallLog から transition 名一致 + refTime が NumericQ なら ±tol 秒以内のものを返す。

### iObsMkPlaceTooltip[wid_String, place_String] → Column
place の現トークン (getTokensInPlace) を Tooltip 用 Column として整形。

### iObsMkTransitionTooltip[wid_String, trans_String] → Column
transition の handler trace と LLM 呼び出し詳細を Tooltip 用 Column として整形。

### iObsMkEdgeTooltip[wid, src, dst, kind, placesList, transitionsList] → Column
edge の firing event (TransitionFired / TransitionFailed) ConsumedIds / ProducedIds を Tooltip 用 Column として整形。kind は "InputArc" | "OutputArc"。

### iObsMakeHandlerWrapper[handler, tname_String] → Function
handler を観測ラップする Function を返す。Block[{$CurrentObservedTransition = tname, $MessageList = {}}, ...] 内で Quiet[handler[binding]] を呼び、$ObservedHandlerLog にエントリを追記して output を返す。handlerHead で Identity / Function / Symbol / その他を分岐する。

### iObsObservedFor[transName_String, ts_, alreadyTaken_List] → Association
$ObservedHandlerLog から transName 一致かつ Index が alreadyTaken に無いものを抽出し、ts が NumericQ なら時刻最近接、それ以外は先頭を選ぶ。

### iObsLLMErrorPatternQ[response_] → Bool
LLM 応答が API エラーパターン ("Error:", "[ClaudeQuery error", "[Error]", "[ClaudeQueryBg error", "$Failed", JSON `{"error":...}`, 短文中の "error" 単語) に該当するかを判定する。

### iObsDeriveStatus[execStatus_, obs_, llmCalls_:{}] → String
本体 ExecutorStatus を盲信せず、handler 観測ログ obs と LLM 呼び出し llmCalls から Status 文字列を導出する。優先順位: FailedHead > Messages 数 > OutputAssocQ 否定 > OutputStatus=="AwaitingLLM" > OutputStatus=="Skip" > PayloadKeyMissing > LLM エラー数 > "OK"。obs が空なら LLMError 判定のみ後 execStatus 文字列化を返す。