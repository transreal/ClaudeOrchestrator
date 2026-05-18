# ClaudeOrchestrator_observability API

petri_from_prompt.wl への観測補完モジュール。LLM 呼び出しログ、Handler 観測、Petri ネット可視化、transition 追跡を提供する。

依存: `ClaudeOrchestrator`Workflow``, `ClaudeCode`ClaudeQueryBg`, petri_from_prompt.wl (v0.10.0+)。

## バージョン変数

### $petriObservabilityVersion
型: String, 初期値: "0.2.1 (2026-05-17)"
パッケージバージョン文字列。

## LLM 呼び出しログ

### $LLMCallLog
型: List[Association], 初期値: {}
全 LLM 呼び出しの記録。各 entry は `"Index"`, `"Time"`, `"TimeStr"`, `"Duration"`, `"TransitionName"`, `"Model"`, `"Fallback"`, `"Prompt"`, `"PromptLen"`, `"Response"`, `"ResponseLen"`, `"OptionList"` を持つ。既存ログ温存のため未定義時のみ初期化。

### ClaudeQueryBgLogged[prompt, opts] → response
`ClaudeCode`ClaudeQueryBg` を呼び出し、開始時刻 / 所要時間 / Model / Fallback / Prompt / Response を `$LLMCallLog` に追記する。`$CurrentObservedTransition` が束縛されていれば transition 名も記録。本体 `ClaudeQueryBg` の Options / Protect / Context は変更しない。
受け付ける opts は `ClaudeCode`ClaudeQueryBg` のもの (`ClaudeCode`Model`, `ClaudeCode`Fallback` 等)。

### clearLLMCallLog[] → String
`$LLMCallLog` を `{}` にリセット。"$LLMCallLog cleared" を返す。

### showLLMCallLog[] → Dataset | $Failed
`$LLMCallLog` を Dataset で表示 (`#`, `Time`, `Trans`, `Model`, `PromptLen`, `ResponseLen`, `Duration`, `Preview` カラム)。空なら警告を Print して `$Failed`。

### showLLMCallLog[idx_Integer] → Column | $Failed
`idx` 番目の entry を Pretty Print (Time / Transition / Model / Fallback / Duration / PromptLen / ResponseLen / Prompt / Response)。範囲外なら警告 Print して `$Failed`。

## Handler 観測

### $ObservedHandlerLog
型: List[Association], 初期値: {}
Handler 呼び出しの記録。各 entry は `"Index"`, `"TransitionName"`, `"Time"`, `"TimeStr"`, `"Duration"`, `"BindingKeys"`, `"BindingPayloads"`, `"OutputRaw"`, `"OutputAssocQ"`, `"OutputHead"`, `"RawKeys"`, `"PayloadKeys"`, `"PayloadKeyMissing"`, `"OutputPayload"`, `"OutputStatus"`, `"Messages"`, `"FailedHead"`, `"HandlerType"` を持つ。

### $CurrentObservedTransition
型: String, 初期値: "?"
現在観測中の transition 名。観測ラッパが Block で局所束縛する。`ClaudeQueryBgLogged` がこれを読んで transition 名を記録。

### clearObservedHandlerLog[] → String
`$ObservedHandlerLog` を `{}` にリセット。"$ObservedHandlerLog cleared" を返す。

### instrumentNetForObservation[net_Association] → Association
net の各 transition の Handler を観測ラッパで包んだ新しい net を返す。Symbol handler も Function ラッパで包むため、本体 `iExecutePureFunction` の Symbol/Function 判定差バグも回避。

### instrumentNetForObservation[trans_Association, tname_String] → Association
単一 transition Association を観測ラッパでくるみ返す。`net` 引数版が KeyValueMap で呼び出す。

## コード変換

### withLLMLogging[code_String] → String
`code` 内の `ClaudeCode`ClaudeQueryBg` および無修飾 `ClaudeQueryBg` を `Global`ClaudeQueryBgLogged` に置換した文字列を返す。関数名のみの置換で Function スコープ / 局所変数 / HoldAll に影響しない。

## Petri ネット可視化

### plotPetriNetDetail[netOrWid, opts]
WorkflowNet をペトリネットグラフとして描画する Tooltip 拡張版。本体 `plotPetriNet` は上書きしない。`netOrWid` が Association なら直接 net、String なら wid から `$iWorkflowNets` で net を解決。wid 文字列を直接渡した場合は自動的に `"TraceWid" -> wid` モード。明示的な頂点リスト (`Join[places, transitions]`) を渡すことで孤立 Place を含む net でも `Graph[]` が確実に評価される。
→ Graph | $Failed
Options:
- "TraceWid" -> None (wid を指定すると Place / Transition / Edge に Tooltip を付ける)
- Options[Graph] のすべて (VertexLayout 等) も透過的に受け付ける

例: `plotPetriNetDetail[wid]` で wid から net を自動取得し Tooltip 付き描画。
例: `plotPetriNetDetail[net, "TraceWid" -> wid, VertexLayout -> "LayeredEmbedding"]`。

### checkPetriNetVertices[net_Association] → Association
net の Places/Transitions 宣言と `iObsExtractEdges[net]` の辺集合の整合性を検査。返り値は `"DeclaredVertices"` (Places ∪ Transitions), `"VerticesFromEdges"` (辺端点集合), `"IsolatedDeclaredVertices"` (宣言だけで辺なし), `"UnknownVerticesInEdges"` (辺だけで宣言なし) を含む Association。

### checkPetriNetVertices[wid_String] → Association | $Failed
wid から net を解決して頂点整合性検査を行う。解決失敗時は警告 Print + `$Failed`。

### checkPetriNetVertices[_] → $Failed
それ以外の引数では `$Failed`。

## Transition 追跡

### traceTransitions[wid_String, opts]
`ClaudeWorkflowTrace[wid]` の TransitionFired / TransitionFailed イベントを基底に、`$ObservedHandlerLog` / `$LLMCallLog` を結合した Dataset を返す。firing trace が空なら `$ObservedHandlerLog` から代替構成。
→ Dataset
Options:
- "Detail" -> False (True で LLM Prompt / Response 抜粋と本体 ExecStatus を含む拡張 Dataset)
- "PromptPreviewLen" -> 200 (Detail モード時の Prompt 抜粋文字数)
- "ResponsePreviewLen" -> 200 (Detail モード時の Response 抜粋文字数)
- "TimeMatchTolerance" -> 60.0 (firing と LLM call の時刻マッチ許容秒)

基本モードのカラム: `Step`, `Transition`, `Status`, `Attempt`, `OutputAssoc?`, `OutputHead`, `RawKeys`, `PayloadKeys`, `PayloadKeyMissing`, `FailedHead`, `Messages`, `ConsumedIds`, `ProducedIds`。

Detail モード追加カラム: `ExecStatus`, `BindingKeys`, `HandlerDur(s)`, `LLMCalls`, `Model`, `PromptLen`, `ResponseLen`, `LLMDur(s)`, `Prompt(preview)`, `Response(preview)`。

Status が取りうる値:
- `OK` 正常完了
- `Failed ($Failed)` handler が $Failed を返した
- `Errored (N msg)` `$MessageList` に N 件メッセージ
- `BadOutput (<Head>)` Association 以外が返った
- `AwaitingLLM` handler が `<|Status -> "AwaitingLLM"|>` を返した (Z 案非同期)
- `Skip` handler が `<|Status -> "Skip"|>` を返した
- `NoPayload` Association だが Payload キーなし
- `LLMError (M/N)` LLM 応答 M/N 件がエラーパターン文字列
- `<ExecutorStatus>` 観測ログがない場合のフォールバック

## 推奨フロー

```
Needs["ClaudeOrchestrator`Workflow`"]
Get["petri_from_prompt.wl"]
Get["ClaudeOrchestrator_observability.wl"]

prop = proposePetriNet[desc, "Providers" -> {"anthropic", "openai"},
  "InputPayloadKeys" -> {"Text"}];
loggedCode = withLLMLogging[prop[["Code"]]];
net0 = parsePetriCode[loggedCode];
net  = instrumentNetForObservation[net0];

clearLLMCallLog[]; clearObservedHandlerLog[];
wid = ClaudeCreateWorkflowNet[net];
ClaudeSubmitToken[wid, WorkflowToken[...], "Source"];
ClaudeRunWorkflow[wid, "Async" -> True];

plotPetriNetDetail[wid]
traceTransitions[wid, "Detail" -> True]
showLLMCallLog[]
```

## 関連パッケージ

- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator)
- [ClaudeOrchestrator_workflow](https://github.com/transreal/ClaudeOrchestrator_workflow)
- [claudecode](https://github.com/transreal/claudecode)