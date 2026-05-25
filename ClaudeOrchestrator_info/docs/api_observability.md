# ClaudeOrchestrator_observability API リファレンス

petri_from_prompt.wl (proposePetriNet 統一版) への observability 補完モジュール。LLM 呼び出しログ、handler 観測、生成コードへの logger 注入、Tooltip 付き Petri net 可視化、transition firing 追跡 Dataset を提供する。

## 依存

- `ClaudeOrchestrator\`Workflow\`` (ClaudeWorkflowTrace, ClaudeWorkflowState のみ使用)
- petri_from_prompt.wl (plotPetriNet, getTokensInPlace, iExtractEdges)
- ClaudeCode`ClaudeQueryBg

## バージョン変数

### $petriObservabilityVersion
型: String, 初期値: `"0.2.1 (2026-05-17)"`
パッケージのバージョン文字列。

## LLM 呼び出しログ

### $LLMCallLog
型: List of Association, 初期値: `{}`
ClaudeQueryBgLogged が追記する LLM 呼び出しエントリのリスト。各エントリは以下のキーを持つ: `Index`, `Time`, `TimeStr`, `Duration`, `TransitionName`, `Model`, `Fallback`, `Prompt`, `PromptLen`, `Response`, `ResponseLen`, `OptionList`。

### $CurrentObservedTransition
型: String, 初期値: `"?"`
handler 内で Block 束縛される現在の transition 名。ClaudeQueryBgLogged はこの値を読んで `TransitionName` フィールドに記録する。

### ClaudeQueryBgLogged[prompt, opts]
ClaudeCode`ClaudeQueryBg と同じ呼び出しを行い、開始時刻 / 所要時間 / Model / Fallback / プロンプト / 応答を `$LLMCallLog` に追記する。ClaudeQueryBg 本体・Options・DownValues は一切変更しない。
→ ClaudeQueryBg の戻り値そのまま
opts: ClaudeCode`ClaudeQueryBg と同じ。`ClaudeCode\`Model`, `ClaudeCode\`Fallback` を Lookup する。

### clearLLMCallLog[] → String
`$LLMCallLog` を空にする。`"$LLMCallLog cleared"` を返す。

### showLLMCallLog[] → Dataset | $Failed
`$LLMCallLog` を `#`, `Time`, `Trans`, `Model`, `PromptLen`, `ResponseLen`, `Duration`, `Preview` (応答先頭 60 文字) の Dataset で返す。空なら警告して `$Failed`。

### showLLMCallLog[idx_Integer] → Column | $Failed
1 件のエントリを Pretty Print (Column + Pane) で表示。範囲外なら警告して `$Failed`。

## Handler 観測

### $ObservedHandlerLog
型: List of Association, 初期値: `{}`
instrumentNetForObservation で挿入された観測ラッパが追記する handler 呼び出しログ。キー: `Index`, `TransitionName`, `Time`, `TimeStr`, `Duration`, `BindingKeys`, `BindingPayloads`, `OutputRaw`, `OutputAssocQ`, `OutputHead`, `RawKeys`, `PayloadKeys`, `PayloadKeyMissing`, `OutputPayload`, `OutputStatus`, `Messages`, `FailedHead`, `HandlerType`。

### clearObservedHandlerLog[] → String
`$ObservedHandlerLog` を空にする。`"$ObservedHandlerLog cleared"` を返す。

### instrumentNetForObservation[net_Association] → Association
net 内全 transition の Handler を観測ラッパで包んだ新しい net を返す。Symbol handler も Function ラッパで包まれるため、本体側 iExecutePureFunction の Symbol/Function 判定差バグも回避する。handler 実行は `Block[{$CurrentObservedTransition = tname, $MessageList = {}}, ...]` で囲まれ、内部の ClaudeQueryBgLogged が transition 名を取得できる。
副作用: handler 呼び出しのたび `$ObservedHandlerLog` にエントリ追加。

### instrumentNetForObservation[trans_Association, tname_String] → Association
単一 transition Association の `RuntimeSpec.Handler` のみラップした新 transition Association を返す (内部利用)。

## コード文字列への logger 注入

### withLLMLogging[code_String] → String
code 内の `ClaudeCode\`ClaudeQueryBg` および無修飾 `ClaudeQueryBg` 呼び出しを `Global\`ClaudeQueryBgLogged` に置換した文字列を返す。関数名 → 関数名 の置換のみ。Function スコープ / 局所変数 / HoldAll などには影響しない。識別子境界は RegularExpression `(?<![A-Za-z0-9\`$])ClaudeQueryBg(?![A-Za-z0-9])` で判定。

## 可視化 (Tooltip 拡張)

### plotPetriNetDetail[netOrWid, opts]
WorkflowNet を Petri net グラフとして描画する Tooltip 拡張版。本体 plotPetriNet とは独立した別関数 (本体は上書きしない)。Place / Transition / Edge にホバーで token / handler trace / firing event の詳細を表示する。Graph[vertices, edges, ...] 2 引数形式で生成 (孤立 Place を含めるため)。
→ Graph | $Failed
Options:
- `"TraceWid" -> None` (wid 文字列。指定で Tooltip モード。netOrWid が文字列ならその wid を自動採用)
- 加えて `Options[Graph]` 全部 (VertexLayout 等もそのまま受け取る)

netOrWid: net Association (`"Places"` キーを持つ) または wid 文字列 (`ClaudeOrchestrator\`Workflow\`Private\`$iWorkflowNets[wid]` から解決)。wid からの解決に失敗すると赤メッセージを Print し `$Failed`。

頂点形状: Place → `"Circle"`, Transition → `"Square"` (`"Rectangle"` は未定義のため不可)。色: Source = Yellow, Final = Green, Place = Blue, Transition = Red。
例: `plotPetriNetDetail[wid, VertexLayout -> "LayeredDigraphEmbedding"]`

### checkPetriNetVertices[net_Association] → Association
net の頂点整合性を診断する。返却 Association のキー:
- `"DeclaredVertices"` — Places ∪ Transitions
- `"VerticesFromEdges"` — iObsExtractEdges から導出される頂点集合
- `"IsolatedDeclaredVertices"` — 宣言だけで辺を持たない頂点 (例: `"Failed"` Final Place)
- `"UnknownVerticesInEdges"` — 辺に現れるが宣言が無い頂点

### checkPetriNetVertices[wid_String] → Association | $Failed
wid から net を解決して同じ診断を返す。解決失敗で `$Failed`。

### checkPetriNetVertices[_] → $Failed
それ以外はフォールバック。

## Transition 追跡

### traceTransitions[wid_String, opts]
`ClaudeWorkflowTrace[wid]` の TransitionFired / TransitionFailed イベントを基底に、`$ObservedHandlerLog` から handler 詳細を、`$LLMCallLog` から LLM 呼び出し詳細を結合した Dataset を返す。firing trace も `$ObservedHandlerLog` も空なら警告して `Dataset[{}]`。firing trace が空でも `$ObservedHandlerLog` があれば handler log から組む。
→ Dataset
列 (デフォルト): `Step`, `Transition`, `Status`, `Attempt`, `OutputAssoc?`, `OutputHead`, `RawKeys`, `PayloadKeys`, `PayloadKeyMissing`, `FailedHead`, `Messages`, `ConsumedIds`, `ProducedIds`
"Detail" -> True で各 firing に対応する LLM 呼び出し (Model / Prompt 抜粋 / Response 抜粋 / Duration) を統合した拡張 Dataset。
Options:
- `"Detail" -> False` (LLM 呼び出し詳細列を追加するか)
- `"PromptPreviewLen" -> 200` (Detail モードでの Prompt 抜粋長)
- `"ResponsePreviewLen" -> 200` (Detail モードでの Response 抜粋長)
- `"TimeMatchTolerance" -> 60.0` (firing と LLM call の時刻マッチ許容秒)

Status カラムの取り得る値 (本体 ExecutorStatus を盲信せず観測ログ優先で判定):
- `"OK"` — 正常完了
- `"Failed ($Failed)"` — handler が $Failed を返した
- `"Errored (N msg)"` — $MessageList に N 件メッセージ
- `"BadOutput (<Head>)"` — Association 以外が返った
- `"AwaitingLLM"` — Z 案 (handler が `<|Status -> "AwaitingLLM"|>` を同期 return)
- `"Skip"` — handler が `<|Status -> "Skip"|>` を返した
- `"NoPayload"` — Association だが `"Payload"` キー無し
- `"LLMError (M/N)"` — LLM 呼び出し M 件が API エラー応答 (handler は graceful 通過)
- `"<ExecutorStatus>"` — 観測ログが無い場合のフォールバック

判定優先順 (iObsDeriveStatus 内): FailedHead → Messages → BadOutput → OutputStatus (AwaitingLLM / Skip) → PayloadKeyMissing → LLMError → OK。

## LLM 応答エラーパターン判定 (内部だが挙動把握用)

iObsLLMErrorPatternQ が true 判定する応答パターン:
- `"Error:"` で始まる
- `"[ClaudeQuery error"` / `"[Error]"` / `"[ClaudeQueryBg error"` で始まる
- `"$Failed"` で始まる
- 正規表現 `(?is)^\s*\{[^}]*"error"[^}]*\}.*` にマッチ (JSON エラー応答)
- 長さ < 120 で `"error"` (IgnoreCase) を含む

## 内部シンボル (ClearAll で宣言、参考)

`iObsExtractEdges`, `iObsMakeHandlerWrapper`, `iObsHandlerTraceFor`, `iObsLLMCallsFor`, `iObsLLMCallsForFiring`, `iObsLLMErrorPatternQ`, `iObsMkPlaceTooltip`, `iObsMkTransitionTooltip`, `iObsMkEdgeTooltip`, `iObsResolveNet`, `iObsObservedFor`, `iObsDeriveStatus`

## 典型ワークフロー

1. `net2 = instrumentNetForObservation[net]` で handler ラップ
2. handler 内コードを生成する場合は `code2 = withLLMLogging[code]` で logger に差し替え
3. `ClaudeRunWorkflow[net2, ...]` 等で実行 (本パッケージは workflow 実行 API は持たない)
4. `traceTransitions[wid, "Detail" -> True]` で結果確認
5. `plotPetriNetDetail[wid]` で Tooltip 付き可視化
6. 描画が崩れたら `checkPetriNetVertices[wid]` で頂点整合性を診断