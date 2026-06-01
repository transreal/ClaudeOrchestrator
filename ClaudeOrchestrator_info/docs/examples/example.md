# ClaudeOrchestrator 使用例集

ClaudeOrchestrator パッケージの代表的な使用例をまとめています。

このドキュメントは大きく 2 部構成です。

- **Part A. ペトリネット (Workflow / Observability)** — `proposePetriNet` を使って自然言語の目標から WorkflowNet を生成し、可視化・観測装着・実行・トレース・snapshot までを一連の流れで体験します。
- **Part B. オーケストレーション (Plan → Spawn → Reduce → Commit)** — DAG ベースのオーケストレーター本体の API を例で示します。

各例は前の例の結果をそのまま使う前提で書かれています。新規セッションで途中の例から走らせる場合は、依存する例を先に実行してください。

---

## 事前準備

```mathematica
(* メイン: ClaudeOrchestrator.wl をロードすれば Workflow エンジンと
   Observability サブモジュールは自動的に取り込まれる。 *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator.wl"}]]];

(* 本ドキュメント Part A で使う proposePetriNet / reviewPetriProposal /
   parsePetriCode は docs/examples/petri_from_prompt.wl が提供する
   サンプル兼ライブラリ。ClaudeOrchestrator パッケージ本体には含まれない
   ので、ここで明示的に Get する。実環境に合わせてパスを調整すること。 *)
Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator_info",
  "docs", "examples", "petri_from_prompt.wl"}]];

(* バージョン確認 *)
{$ClaudeOrchestratorVersion,
 ClaudeOrchestrator`Workflow`$WorkflowVersion,
 $petriObservabilityVersion}
```

**期待される出力例:**

```
{"2026-04-28-phase36-lmstudio-worker-async",
 "2026-05-10-retry-policy-enforcement",
 "0.2.0 (2026-05-11)"}
```

> **メモ:** `$petriObservabilityVersion` が `$petriObservabilityVersion` のまま(未評価のまま)出てくる場合は、`ClaudeOrchestrator_observability.wl` の自動ロードに失敗しています。`Get["ClaudeOrchestrator_observability.wl"]` を手動で実行するか、ファイルが `$Path` 上にあるか確認してください。観測モジュールがロードされていないと、例 A-5 以降の `checkPetriNetVertices` / `instrumentNetForObservation` / `plotPetriNetDetail` / `traceTransitions` / `showLLMCallLog` が**未評価式のまま残ります**。

---

# Part A. ペトリネット — proposePetriNet から実行・観測まで

このセクションでは、自然言語で書いた目標から LLM がペトリネット (WorkflowNet) のコードを生成し、それを実行 → 可視化 → 観測 → トレースする一連の流れを体験します。

ストーリー:

> 「3 つの異なる方法 (モンテカルロ法、ライプニッツ級数、Wallis 積) で π を近似計算し、結果を比較する」というワークフローをペトリネットとして実装したい。

---

## 例 A-1: proposePetriNet で自然文から WorkflowNet コードを生成

```mathematica
goal = "3 つの異なる方法 (モンテカルロ法、ライプニッツ級数、Wallis 積) で\n" <>
       "円周率 π を近似計算し、結果をマージして比較レポートを作る。";

proposal = proposePetriNet[goal];

(* 結果 Association のキーを確認 *)
Keys[proposal]
```

**期待される出力例:**

```
{"Goal", "BuilderName", "Code", "CodeLength", "RawResponse",
 "ResponseLength", "Truncated", "ForbiddenFound", "SharedInputPlaces",
 "DuplicatedTransitions", "RetryGuardIssues", "PayloadAccessIssues",
 "IsErrorResponse", "Attempts"}
```

`proposal["Code"]` には LLM が生成した Wolfram コードが入っており、典型的には `buildPiComparisonNet[] := WorkflowNet[<|...|>]` のような builder 関数を定義します。

```mathematica
(* 生成された builder 名 *)
proposal["BuilderName"]
(* 例: "buildPiComparisonNet" *)

(* コードの長さ・LLM 応答の検証指標 *)
<|"CodeLen"        -> proposal["CodeLength"],
  "ResponseLen"    -> proposal["ResponseLength"],
  "Truncated"      -> proposal["Truncated"],
  "Forbidden"      -> proposal["ForbiddenFound"],
  "SharedInputs"   -> proposal["SharedInputPlaces"],
  "Duplicated"     -> proposal["DuplicatedTransitions"],
  "Attempts"       -> proposal["Attempts"]|>
```

**期待される出力例(健全な提案):**

```
<|"CodeLen" -> 1840, "ResponseLen" -> 2200, "Truncated" -> False,
  "Forbidden" -> {}, "SharedInputs" -> {}, "Duplicated" -> {},
  "Attempts" -> 1|>
```

`Forbidden` や `SharedInputs` が空でないときは設計上の問題が検出されており、`MaxRetries` で自動再生成されます。

---

## 例 A-2: reviewPetriProposal でレビュー表示

生成コードを目視確認したい場合は `reviewPetriProposal` を使います。コード本体・builder 名・診断指標を Frame 付きで一望できます。

```mathematica
reviewPetriProposal[goal]
```

**期待される出力例(イメージ):**

```
┌────────────────────────────────────────────┐
│ Goal:                                       │
│ 3 つの異なる方法 (モンテカルロ法、ライプニッツ ...│
│                                             │
│ Status:                                     │
│ [OK] コードも関数定義も検出されました         │
│                                             │
│ BuilderName: buildPiComparisonNet           │
│ SharedInputPlaces: (none)                   │
│ ResponseLen: 2200   CodeLen: 1840           │
│                                             │
│ Generated code:                             │
│ buildPiComparisonNet[] := WorkflowNet[<|... │
│   "SourcePlace"  -> "Seed",                 │
│   "FinalPlaces"  -> {"Done"},               │
│   "Places"       -> <|...|>,                │
│   "Transitions"  -> <|...|>                 │
│ |>];                                        │
└────────────────────────────────────────────┘
```

---

## 例 A-3: parsePetriCode で WorkflowNet Association を生成

生成コードを評価して `WorkflowNet[...]` の Association を取り出します。

```mathematica
net = parsePetriCode[proposal["Code"]];

(* net は Association — 主要キー *)
{Keys[net], Length[net["Places"]], Length[net["Transitions"]]}
```

**期待される出力例:**

```
{{"WorkflowId", "FormatVersion", "SourcePlace", "FinalPlaces",
  "Places", "Transitions", "Tokens", "InitialMarking", "Workers",
  "Policy", "Trace", "Status", "TransitionFailureCounts", "Metadata"},
 7, 6}
```

`parsePetriCode` が返す Association は workflow.wl の `WorkflowNet[opts]` ビルダーが返すフル構造で、`Tokens` / `Trace` / `Status` 等の実行時フィールドも含みますが、この時点ではまだ `ClaudeCreateWorkflowNet` で registry に登録されていません(`WorkflowId` は仮の値)。実行可能にするには次の例 A-7 で `ClaudeCreateWorkflowNet` を呼ぶ必要があります。

`Places` と `Transitions` の各キーを覗くと、ペトリネットの構造が分かります。

```mathematica
{Keys[net["Places"]], Keys[net["Transitions"]]}
```

**期待される出力例:**

```
{{"Start", "PoolMC", "PoolLeibniz", "PoolWallis", "ResultPool", "Verdict", "Done"},
 {"Distribute", "WorkerMC", "WorkerLeibniz", "WorkerWallis", "Aggregate", "Finalize"}}
```

(LLM の生成結果なので、Place / Transition の名前や数は毎回少しずつ違います。)

---

## 例 A-4: plotPetriNet で基本構造を可視化

実行する前に、まずネットの形を確認します。

```mathematica
plotPetriNet[net]
```

**期待される出力例:**
ペトリネットの構造図。青い円が Place(`Seed` は黄、`Done` は緑)、赤い四角が Transition で、矢印で繋がる Graph オブジェクトが描画されます。

---

## 例 A-5: checkPetriNetVertices で構造整合性チェック

LLM が生成したネットは、ときどき孤立 Place や未宣言頂点を含みます。本格的に実行する前にチェックします。

```mathematica
checkPetriNetVertices[net]
```

**期待される出力例:**

```
<|"DeclaredVertices" -> {"Seed", "PartialResults", "Done",
                         "ComputeMC", "ComputeLeibniz",
                         "ComputeWallis", "MergeResults"},
  "VerticesFromEdges" -> {"Seed", "ComputeMC", "ComputeLeibniz",
                         "ComputeWallis", "PartialResults",
                         "MergeResults", "Done"},
  "IsolatedDeclaredVertices" -> {},
  "UnknownVerticesInEdges"   -> {}|>
```

- `IsolatedDeclaredVertices` が空でない → 宣言だけで辺を持たない頂点があります(`plotPetriNetDetail` は OK、本体 `plotPetriNet` も 2 引数形式で OK)。
- `UnknownVerticesInEdges` が空でない → 辺に現れるが宣言にない頂点があります。LLM 生成の品質問題なので `proposePetriNet` を `MaxRetries` 増やして再試行するか、手で `Places` / `Transitions` に追加します。

---

## 例 A-6: instrumentNetForObservation で観測ラッパを装着

`$ObservedHandlerLog` に handler 呼び出し詳細(binding、OutputPayload、Messages)を残すよう、ネットを観測版で包みます。

```mathematica
clearObservedHandlerLog[];
clearLLMCallLog[];

observedNet = instrumentNetForObservation[net];

(* 観測版でも構造は同じ。Transition の Handler だけがラッパで置き換わる *)
Length[observedNet["Transitions"]] === Length[net["Transitions"]]
```

**期待される出力例:** `True`

---

## 例 A-7: ClaudeCreateWorkflowNet で WorkflowId を発行・登録

```mathematica
wid = ClaudeCreateWorkflowNet[observedNet];
wid
```

**期待される出力例:**

```
"wf-1778820123-45678"
```

この `wid` で以後すべての操作を行います。`ClaudeWorkflowList[]` で登録状態を確認できます。

```mathematica
ClaudeWorkflowList[]
```

---

## 例 A-8: ClaudeSubmitToken で初期トークンを投入

`SourcePlace`(この例では `"Seed"`)に Token を 1 つ投入します。Payload には各 transition が必要とする初期値を入れます。

```mathematica
seedToken = WorkflowToken[
  "Kind"    -> "Task",
  "Payload" -> <|"NumSamples" -> 100000, "NumTerms" -> 50000|>];

ClaudeSubmitToken[wid, seedToken];

(* 現在の marking を確認 *)
ClaudeWorkflowStatus[wid]
```

**期待される出力例:**

```
<|"Status" -> "Ready",
  "CurrentMarking" -> <|"Seed" -> 1, "PartialResults" -> 0, "Done" -> 0|>,
  "ElapsedSec" -> 0.|>
```

---

## 例 A-9: plotPetriNetDetail で Tooltip 付き表示

実行前に、token がどこにあるか、各 transition がどの handler / binding を持つか、ホバーで確認できる詳細版を表示します。**`wid` 文字列を直接渡す**と自動的に TraceWid モードになります。

```mathematica
plotPetriNetDetail[wid]
```

**期待される出力例:**
ペトリネット Graph。マウスを乗せると:

- **Place** の上 → 現在その place にあるトークンの TokenId / Kind / Payload を表示
- **Transition** の上 → handler 呼び出し履歴(まだ実行前なら空)・LLM 呼び出し履歴を表示
- **Edge** の上 → アークの種類(InputArc / OutputArc)・端点の役割を表示

実行後にもう一度呼び出せば、Tooltip の内容が更新されます。

---

## 例 A-10: ClaudeEnabledTransitions で発火可能な遷移を確認

```mathematica
ClaudeEnabledTransitions[wid]
```

**期待される出力例:**

```
{<|"Name" -> "ComputeMC",
   "Binding" -> <|"Seed" -> <|"TokenId" -> "tok-1", "Payload" -> <|...|>|>|>,
   "Priority" -> 0|>,
 <|"Name" -> "ComputeLeibniz", ...|>,
 <|"Name" -> "ComputeWallis", ...|>}
```

3 つの並列 transition が `Seed` トークンを取り合える状態にあることが分かります。

---

## 例 A-11: ClaudeRunWorkflow で同期実行

```mathematica
runResult = ClaudeRunWorkflow[wid, "Async" -> False, "MaxSteps" -> 50];
<|"Status"      -> runResult["Status"],
  "Termination" -> runResult["TerminationReason"],
  "Steps"       -> runResult["Steps"],
  "ElapsedSec"  -> Round[runResult["ElapsedSec"], 0.01],
  "FinalMarking" -> runResult["FinalMarking"]|>
```

**期待される出力例:**

```
<|"Status"      -> "Completed",
  "Termination" -> "SinkReached",
  "Steps"       -> 4,
  "ElapsedSec"  -> 2.31,
  "FinalMarking" -> <|"Seed" -> 0, "PartialResults" -> 0, "Done" -> 1|>|>
```

3 つの並列 compute → merge と進み、最終的に `Done` に 1 トークンが届きました。

---

## 例 A-12: ClaudeWorkflowState で最終トークンの Payload を見る

```mathematica
state = ClaudeWorkflowState[wid];
finalTokens = state["Marking"]["Done"];      (* TokenId のリスト *)
finalTokenPayloads = state["Tokens"][[#]]["Payload"] & /@ finalTokens;
finalTokenPayloads
```

**期待される出力例:**

```
{<|"PiMC"      -> 3.14148,
   "PiLeibniz" -> 3.14157,
   "PiWallis"  -> 3.14164,
   "Report"    -> "MC vs Leibniz: -0.00009, MC vs Wallis: -0.00016, ..."|>}
```

3 つの計算結果と比較レポートがマージされて 1 トークンに収まっています。

---

## 例 A-13: traceTransitions で firing トレースを表形式で確認

各 transition が実際に何時に・どの順序で・どの binding で発火し、出力がどんな形だったかを Dataset で見ます。

```mathematica
traceTransitions[wid]
```

**期待される出力例:**

```
Step│Transition       │Status │OutputAssoc?│OutputHead   │PayloadKeys
────┼─────────────────┼───────┼────────────┼─────────────┼─────────────
 1  │ComputeMC        │OK     │True        │Association  │{PiMC}
 2  │ComputeLeibniz   │OK     │True        │Association  │{PiLeibniz}
 3  │ComputeWallis    │OK     │True        │Association  │{PiWallis}
 4  │MergeResults     │OK     │True        │Association  │{PiMC,PiLeibniz,PiWallis,Report}
```

LLM 呼び出しがある transition では `"Detail" -> True` で Prompt / Response 抜粋も併せて表示できます。

```mathematica
traceTransitions[wid, "Detail" -> True,
  "PromptPreviewLen" -> 80, "ResponsePreviewLen" -> 80]
```

---

## 例 A-14: showLLMCallLog で LLM 呼び出しの一覧と詳細

handler の中で `ClaudeQueryBgLogged` が呼ばれた回数だけログが残ります(`instrumentNetForObservation` 経由で `ClaudeQueryBg` の呼び出しは自動的に `ClaudeQueryBgLogged` に書き換わります)。

```mathematica
showLLMCallLog[]
```

**期待される出力例:**

`$LLMCallLog` が空のときは Print と `$Failed`(本例の handler は純計算で LLM を呼ばないので、ここは通常空):

```
[showLLMCallLog] $LLMCallLog は空です。
$Failed
```

handler の中で `ClaudeQueryBg` を呼ぶ workflow なら以下のような Dataset が返ります:

```
 # │Time     │Trans         │Model           │PromptLen│ResponseLen│Duration│Preview
───┼─────────┼──────────────┼────────────────┼─────────┼───────────┼────────┼────────────────
 1 │14:23:11 │MergeResults  │claude-opus-4-7 │   612   │    188    │  3.4   │MC vs Leibniz: ...
```

```mathematica
(* 詳細表示 (Prompt 全文と Response 全文を Pane で) — ログが空でないときのみ意味がある *)
showLLMCallLog[1]
```

---

## 例 A-15: ClaudeSnapshotWorkflow で workflow を保存

成果と全 trace をディスクへ保存します。`$ClaudeWorkflowSnapshotDir` が既定の保存先です。

```mathematica
snapshotInfo = ClaudeSnapshotWorkflow[wid];
snapshotInfo
```

**期待される出力例:**

```
<|"WorkflowId"    -> "wf-1778820123-45678",
  "SnapshotDir"   -> "C:\\...\\workflow_snapshots\\snap-wf-1778820123-45678-...",
  "FormatVersion" -> 2,
  "SavedAt"       -> 3.9878...|>
```

戻り値は Association で、`"SnapshotDir"` キーに保存先パスが入っています。

```mathematica
(* 保存先パスを取り出す *)
snapDir = snapshotInfo["SnapshotDir"]

(* 全 snapshot 一覧 (wid は引数に取らない。snapshot ディレクトリ全体を走査する) *)
ClaudeListWorkflowSnapshots[]
```

別セッションから復元するには `SnapshotDir` パス(文字列)を渡します:

```mathematica
restoreInfo = ClaudeRestoreWorkflow[snapDir];
restoreInfo
(* → <|"WorkflowId" -> 新 wid, "OriginalWid" -> 元 wid, "Restored" -> True, ...|> *)

(* 復元された workflow の状態を見る *)
ClaudeWorkflowState[restoreInfo["WorkflowId"]]
(* token / marking 等が復元される *)
```

既定では `"AsNewWorkflowId" -> True` で新規 wid を発行(既存 wid との衝突回避)。元の wid で復元したい場合は `"AsNewWorkflowId" -> False` を指定します(debug 用途)。

---

## 例 A-16: 非同期実行 + 完了 hook

長時間かかる workflow は `"Async" -> True` で非同期に走らせます。フロントエンドはブロックされません。

```mathematica
(* 別 workflow を作って async で起動 *)
wid2 = ClaudeCreateWorkflowNet[observedNet];
ClaudeSubmitToken[wid2, seedToken];

(* 完了時のコールバックを登録 *)
ClaudeRegisterCompletionHook[wid2,
  Function[w,
    Print["Workflow ", w, " completed: ",
      ClaudeWorkflowStatus[w]["CurrentMarking"]]]];

(* 非同期起動: 即座に Association を返す *)
asyncInfo = ClaudeRunWorkflow[wid2, "Async" -> True];
asyncInfo
```

**期待される出力例:**

```
<|"WorkflowId" -> "wf-...",
  "Status"     -> "Async-Started",
  "PollKey"    -> "WorkflowAsync_wf-...",
  "StartTime"  -> 3.987...|>
```

```mathematica
(* 進捗を覗く *)
ClaudeAsyncJobInfo[wid2]

(* 完了まで待つ (同期化) *)
ClaudeWaitWorkflow[wid2, "MaxWait" -> Quantity[30, "Seconds"]]
(* 完了 hook が "Workflow wf-... completed: <|Done -> 1, ...|>" を Print *)
```

---

## 例 A-17: Pause / Resume / Cancel

長時間タスク中に止めて状態を見たい・破棄したい、というケース。

```mathematica
(* 走行中の wid に対して: *)
ClaudePauseWorkflow[wid2];     (* Status -> "Paused" *)
ClaudeWorkflowStatus[wid2]

(* もう一度走らせる *)
ClaudeResumeWorkflow[wid2];

(* 破棄 (再開不可) *)
ClaudeCancelWorkflow[wid2];

(* 終わった async ジョブを GC *)
ClaudeCleanupAsyncJob[wid2];
```

---

## 例 A-18: withLLMLogging で生成コードに logger を注入

LLM が生成した既存コードに `ClaudeQueryBg[...]` を呼ぶ handler が含まれていて、それを `$LLMCallLog` に記録したい場合:

```mathematica
loggedCode = withLLMLogging[proposal["Code"]];

(* "ClaudeQueryBg" が "Global`ClaudeQueryBgLogged" に置換されている *)
StringContainsQ[loggedCode, "ClaudeQueryBgLogged"]
```

**期待される出力例:** `True`(生成コード中に `ClaudeQueryBg` 呼び出しが含まれている場合)、`False`(含まれていない場合)。

本例の π 計算 workflow は handler 内で `ClaudeQueryBg` を呼ばない純計算なので `False` になります。LLM 呼出を含む workflow(例: コードレビューや要約など)を生成させると `True` になり、Pre 〜 Post の Prompt / Response が `$LLMCallLog` に記録できるようになります。

このコードを `parsePetriCode` に渡せば、`instrumentNetForObservation` 経由でなくても LLM 呼び出しがログに残ります。文字列レベルの置換なので Function スコープや HoldAll は壊しません。

---

## 例 A-19: Workflow API で直接 net を組む (proposePetriNet を使わない)

Part A はここまで「自然文 → LLM が生成 → 実行」の流れでしたが、`WorkflowPlace` / `WorkflowTransition` / `WorkflowNet` を直接書いて net を組むこともできます。LLM を介さないので、決定的なテストや、構造が既に分かっているワークフローに向きます。

```mathematica
(* Place / Transition / Net を組み立て、WorkflowId を発行 *)
src  = WorkflowPlace["Start"];
mid  = WorkflowPlace["Mid"];
dst  = WorkflowPlace["Done"];
t1   = WorkflowTransition["T1",
  "InputArcs"  -> {<|"Place" -> "Start", "Multiplicity" -> 1|>},
  "OutputArcs" -> {<|"Place" -> "Mid",   "Multiplicity" -> 1|>},
  "Executor"   -> "PureFunction",
  "RuntimeSpec"-> <|"Handler" -> (# &)|>];
t2   = WorkflowTransition["T2",
  "InputArcs"  -> {<|"Place" -> "Mid",   "Multiplicity" -> 1|>},
  "OutputArcs" -> {<|"Place" -> "Done",  "Multiplicity" -> 1|>},
  "Executor"   -> "PureFunction",
  "RuntimeSpec"-> <|"Handler" -> (# &)|>];
net2 = WorkflowNet[
  "SourcePlace" -> "Start",
  "FinalPlaces" -> {"Done"},
  "Places"      -> <|"Start" -> src, "Mid" -> mid, "Done" -> dst|>,
  "Transitions" -> <|"T1" -> t1, "T2" -> t2|>];
wid2 = ClaudeCreateWorkflowNet[net2];

(* トークン投入と実行 *)
ClaudeSubmitToken[wid2,
  WorkflowToken["Kind" -> "Task", "Payload" -> <|"id" -> 1|>]];
ClaudeRunWorkflow[wid2, "MaxSteps" -> 10][["Status"]]
```

**期待される出力例:** `"Done"`

この net も `instrumentNetForObservation` で包めば例 A-13 / A-14 と同様にトレース・LLM ログを取れます。型ビルダーの全オプション(`Capacity` / `AcceptedKinds` / `Guard` / `RetryPolicy` / `AccessPolicy` / `Timeout` / `Priority` 等)は `api_workflow.md` を参照してください。

---

## 例 A-20: ChatGPT Codex を含む複数プロバイダの混在トレース

`ClaudeOrchestrator_observability.wl` (2026-05-26 以降) は、応答に `ProviderResultMetadata` が含まれていれば自動的に provenance キーを `$LLMCallLog` に保存します。Codex 経由の呼び出しと Claude 経由の呼び出しを同じログから区別できます。

```mathematica
(* 観測ラッパ付きで workflow を実行(handler 内で複数プロバイダを呼ぶ前提) *)
clearLLMCallLog[];
clearObservedHandlerLog[];

netObs = instrumentNetForObservation[net];   (* 例 A-3 の net *)
widObs = ClaudeCreateWorkflowNet[netObs];
ClaudeSubmitToken[widObs, WorkflowToken[]];
ClaudeRunWorkflow[widObs];

(* Provider カラムで区別できる *)
showLLMCallLog[]
(* "ChatGPT Codex" / "Claude" / "LM Studio" 等が Provider 列に表示される *)

(* 個別 entry を詳細表示すると Provider / HarnessBundle /
   DirectiveSnapshot / RuntimeEnvHash も確認できる *)
showLLMCallLog[1]
```

**期待される出力例:** `$LLMCallLog` の各行に Provider 列が付いた Dataset。handler が LLM を呼ばない純計算 net の場合はログが空になるため、LLM 呼び出しを含む net(コードレビュー・要約など)で試してください。provenance フィールドの詳細は `api_observability.md` の `$LLMCallLog` を参照。

---

# Part B. オーケストレーション (Plan → Spawn → Reduce → Commit)

DAG ベースのオーケストレーター本体の API を例で示します。Part A のペトリネットは下位の Workflow エンジンを直接使う流れですが、Part B は LLM が分解した DAG を `ClaudeRunOrchestrationAsync` で非同期実行する高水準ラッパです(オーケストレーションはフロントエンドをブロックしない非同期実行に統一されています)。

---

## 例 B-0: ClaudeEval がオーケストレーターに切り替わることの確認

`ClaudeOrchestrator.wl` をロードすると、`ClaudeRuntime` 既定の `$ClaudeEvalHook` がオーケストレーター版に置き換わり、以降の `ClaudeEval` 呼び出しはすべてオーケストレーションパイプライン(非同期)を通るようになります。

```mathematica
(* ClaudeOrchestrator ロード前 — ClaudeRuntime ベースの ClaudeEval *)
Needs["ClaudeRuntime`", "ClaudeRuntime.wl"];
$ClaudeEvalHook   (* ClaudeRuntime 既定のフック *)

(* ClaudeOrchestrator をロード *)
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];

(* ロード後 — $ClaudeEvalHook がオーケストレーターに置き換わる *)
$ClaudeEvalHook   (* ClaudeOrchestrator ベースのフック関数が返る *)

(* 以降の ClaudeEval はすべてオーケストレーターパイプラインを通る(非同期) *)
ClaudeEval["フィボナッチ数列の最初の 10 項を求めて表示する"]
(* → ClaudeRunOrchestrationAsync 経由で非同期実行され、orchJobId を即座に返す *)
```

**期待される動作:** ロード前後で `$ClaudeEvalHook` の中身が変わり、ロード後の `ClaudeEval` は同期的に結果を返さず orchJobId を即座に返す(`$ClaudeOrchestratorAsyncMode` が `True` の場合)。同期挙動に戻すには `$ClaudeOrchestratorAsyncMode = False`。

---

## 例 B-1: タスク分解 (モック planner)

```mathematica
plan = ClaudePlanTasks["Mathematica で素数リストを生成して CSV に保存する"];
plan["Tasks"][[All, {"TaskId", "Role", "Goal"}]]
```

**期待される出力例:**

```
{<|"TaskId"->"t1","Role"->"Explore","Goal"->"要件確認"|>,
 <|"TaskId"->"t2","Role"->"Draft","Goal"->"コード生成"|>, ...}
```

---

## 例 B-2: TaskSpec の検証

`ClaudeValidateTaskSpec` は単一の TaskSpec ではなく**plan 全体**(`<|"Tasks" -> {...}, ...|>` の形)を受け取り、`"Tasks"` キーの各タスクを順に検査します。

```mathematica
ClaudeValidateTaskSpec[plan]
```

**期待される出力例:** `<|"Valid" -> True, "Errors" -> {}|>`

単一の task Association を直接渡すと `"Tasks キーがリストでない"` エラーが返ります。

---

## 例 B-3: Worker の起動と Artifact 収集

`ClaudeSpawnWorkers` は `plan["Tasks"]` の各タスクに対し worker adapter を呼び出して artifact を収集します。デフォルトの worker adapter はモック実装 (`iMockWorkerAdapter`) で、各タスクに対し空 / プレースホルダ artifact を返します。実 LLM を使う場合は `WorkerAdapterBuilder` オプション、または `ClaudeRunOrchestrationAsync` 全体で `Model` を指定します(例 B-6 参照)。

```mathematica
tasks = plan["Tasks"];
spawnResult = ClaudeSpawnWorkers[tasks];
ClaudeCollectArtifacts[spawnResult]
```

**期待される出力例(モック adapter の場合):** 各タスクに対し簡素な Association が入った Dataset:

```
Dataset[<|"t1" -> <|"ArtifactType" -> "Text",
                    "Payload"      -> <|"Output" -> "[mock] ..."|>,
                    "TaskId"       -> "t1", ...|>, ...|>]
```

---

## 例 B-4: Artifact の統合 (Reduce)

```mathematica
artifacts = spawnResult["Artifacts"];
reduced = ClaudeReduceArtifacts[artifacts];
reduced[["ArtifactType"]]
```

**期待される出力例:** 成功時は `"Reduced"`、失敗時は `"ReducedFailed"`。

- `"Reduced"` — Reducer (デフォルトは `iDefaultReducer`、`Reducer -> "LLM"` で LLM-backed reducer) が正常に Association を返した場合。
- `"ReducedFailed"` — Reducer の戻り値が非 Association だった場合(モック adapter の artifact が形式不一致を起こすと発生)。このときは `reduced["Error"]` に理由(例: `"ReducerReturnedNonAssociation"`、`"LLMReducerFailed"`)が入る。

> **メモ:** B-3 のモック adapter 由来の artifact では `"ReducedFailed"` が返るのは想定内です。実 LLM を使う `ClaudeRunOrchestrationAsync` (例 B-6)で `Model -> ...` を指定すると `"Reduced"` になる確率が高くなります。

---

## 例 B-5: ノートブックへのコミット

```mathematica
nb = InputNotebook[];
result = ClaudeCommitArtifacts[nb, reduced];
result[["Status"]]
```

**期待される出力例:** `"Committed"` (この API は reduced の中身が失敗を示していても、エラー報告セルを書き出して `"Committed"` を返します)。

成功状態と失敗状態を区別したい場合は `reduced["ArtifactType"]`(`"Reduced"` vs `"ReducedFailed"`)を併せて確認してください。

---

## 例 B-6: 非同期オーケストレーションと状態監視

オーケストレーションはフロントエンドをブロックしない**非同期実行に統一**されています。`ClaudeRunOrchestrationAsync` で起動し、`ClaudeOrchestrationStatus` で進捗を確認、`ClaudeOrchestrationWait` で完了を待ってから `ClaudeOrchestrationResult` で結果を取り出すのが標準的な流れです。

```mathematica
(* ジョブを非同期で起動 *)
jobId = ClaudeRunOrchestrationAsync[
  "行列の固有値を求めてレポートを生成する",
  MaxTasks -> 4];

(* 状態を確認 (即座に返る) *)
ClaudeOrchestrationStatus[jobId][["Status"]]
```

**期待される出力例:** `"Planning"`

進行を観察すると `"Planning"` → `"Spawning"` → `"Reducing"` → `"Committing"` → `"Done"` と遷移します。

```mathematica
(* 完了を待機してから最終ステータスを取得 *)
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["Status"]]
```

**期待される出力例:** `"Complete"` (Spawn/Reduce/Commit がすべて成功した場合)。失敗時は `"SpawnFailed"` / `"ReduceFailed"` / `"CommitFailed"` 等が入ります。

### 結果の読み出し

`ClaudeOrchestrationResult[jobId]` は `Plan` / `Spawn` / `Reduce` / `Commit` 各フェーズの結果を含む Association を返します。それぞれを取り出して内容を確認できます。

```mathematica
(* 全体構造のキー一覧 *)
res = ClaudeOrchestrationResult[jobId];
Keys[res]
(* {"Status", "OrchJobId", "PlanResult", "SpawnResult",
    "ReduceResult", "CommitResult", "ElapsedSecs"} *)

(* Plan 段階: 何タスクに分解されたか *)
res[["PlanResult", "Tasks"]][[All, {"TaskId", "Role", "Goal"}]]

(* Spawn 段階: ステータスと artifact 件数 *)
{res[["SpawnResult", "Status"]], Length[res[["SpawnResult", "Artifacts"]]]}

(* Reduce 段階: 統合された artifact の payload (Summary など) *)
res[["ReduceResult", "Payload"]]

(* Commit 段階: notebook 書き込みのステータス *)
res[["CommitResult", "Status"]]

(* 全体の所要時間(秒) *)
res[["ElapsedSecs"]]
```

**期待される出力例(モック adapter で MaxTasks -> 4 の場合):**

```
{"Status"->"Complete", "OrchJobId"->"orch-...", "PlanResult"->..., "SpawnResult"->..., ...}
{<|"TaskId"->"t1", "Role"->"Explore", "Goal"->"..."|>, ..., (4 件)}
{"Complete", 4}
<|"Summary" -> "[mock reduced]"|>
"Committed"
2.3
```

実 LLM (`Model -> "claude-opus-4-7"` などのオプションを `ClaudeRunOrchestrationAsync` に渡すか、`$ClaudeOrchestratorRealLLMEndpoint` を設定)を使うと、`ReduceResult["Payload"]` には統合された自然文の Summary、`CommitResult` には実際に notebook へ書き込まれた cell の情報が入ります。

---

## 例 B-7: バッチ処理 (単一セッション継続)

`ClaudeContinueBatch` は既に確立した runtime セッション(`ClaudeStartRuntime` の結果、または `ClaudeSpawnWorkers` で実 LLM Worker が返す runtime)に対して、複数の指示文を順次投入する API です。

```mathematica
(* 実 LLM Worker で runtime artifact を取得 (モック adapter ではこのキー構造ではない) *)
spawnResult = ClaudeSpawnWorkers[tasks,
  "WorkerAdapterBuilder" -> "ClaudeCode"];   (* 実 LLM の場合 *)
runtime     = First @ spawnResult["Artifacts"];
runtimeId   = runtime["RuntimeId"];

results = ClaudeContinueBatch[
  runtimeId,
  {"ステップ 1 を実行", "ステップ 2 を実行", "結果を要約"},
  WaitBetween -> Quantity[2, "Seconds"]];
results[[All, "Index"]]
```

**期待される出力例:** `{1, 2, 3}` (実 LLM 経路で `RuntimeId` が取れている場合)

> **メモ:** デフォルトのモック adapter は artifact に `"RuntimeId"` キーを持たないため、`runtime["RuntimeId"]` は `Missing[KeyAbsent, "RuntimeId"]` を返し、後続の `ClaudeContinueBatch` も `Missing[KeyAbsent, "Index"]` のリストになります。`ClaudeContinueBatch` を試したい場合は、`ClaudeStartRuntime[...]` で明示的に runtime を作るか、`WorkerAdapterBuilder` で実 LLM adapter を指定してください。

---

## 例 B-8: real LLM 統合の診断

```mathematica
$ClaudeOrchestratorRealLLMEndpoint = "ClaudeCode";
diag = ClaudeRealLLMDiagnose["Hello, world!"];
Keys[diag]
```

**期待される出力例(Keys 一覧):** `{"Status", "Endpoint", "RoundTrip", ...}` のような Association。

`ExitCode` キーは ClaudeCode CLI が直接返す場合のみ存在し、`$ClaudeOrchestratorRealLLMEndpoint` の設定や CLI のインストール状況によって構造が変わるため、まずは `Keys[diag]` で実際に返ってきたキーを確認してから個別のキーにアクセスするのが安全です。

```mathematica
(* よく使うキー *)
diag[["Status"]]      (* "OK" / "Failed" / "NotConfigured" など *)
diag[["RoundTrip"]]   (* 往復時間(秒) *)
```

---

## 例 B-9: ジョブ一覧と中断

```mathematica
(* 現在実行中のジョブを確認 *)
ClaudeOrchestrationJobs[]

(* 不要なジョブを中断 *)
ClaudeOrchestrationCancel[jobId]
```

**期待される出力例:** `Dataset[{<|"JobId"->..., "Status"->"Running", ...|>}]` / `True`

---

## 関連ドキュメント

- **`user_manual.md`** — 各 API の詳しい引数・オプション・戻り値の説明
- **`README.md`** — 設計思想・アーキテクチャ・インストール・主な機能の俯瞰
- **`docs/examples/petri_from_prompt.wl`** — 本ファイルの Part A で使ったサンプルパッケージ本体
