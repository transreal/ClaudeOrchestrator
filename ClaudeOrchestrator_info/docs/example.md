# ClaudeOrchestrator 使用例集

本書は ClaudeOrchestrator パッケージの実践的な使用例を集めたものです。基本的な同期実行から、Phase 32 以降に追加された非同期実行、ペトリネット拡張、real LLM 統合まで、シナリオごとに動くコード例を示します。

---

## 0. 前提となるロード手順

すべての例は以下のロードを前提とします。

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Get["ClaudeRuntime.wl"];
  Get["ClaudeOrchestrator.wl"]
];

(* バージョン確認 *)
ClaudeOrchestrator`$ClaudeOrchestratorVersion
```

`ClaudeOrchestrator` は `ClaudeRuntime` を依存先として暗黙ロードしますが、明示的に `ClaudeRuntime.wl` を先に読み込んでおくと診断時の挙動が安定します。`NBAccess.wl` は `BeginPackage` 内で自動的に `Needs` されます。

---

## 1. 基本シナリオ ― Plan → Spawn → Reduce → Commit

最小構成の同期実行です。Planner / Worker / Reducer を Automatic に任せ、target notebook へ commit せずに artifact を確認します。

```mathematica
result = ClaudeRunOrchestration[
  "フィボナッチ数を求める関数を Wolfram Language で書いてください。",
  "Planner" -> Automatic,
  "MaxTasks" -> 3,
  "Confirm" -> False
];

result["Status"]
result["Plan"]["Tasks"] // Dataset
ClaudeCollectArtifacts[result["Spawn"]]
```

`Confirm -> False` のとき commit phase はスキップされ、Reduce までで完結します。Commit する場合は `TargetNotebook -> EvaluationNotebook[]` を Worker 側ではなく orchestration の最上位 option として渡してください（worker は notebook を直接触りません）。

---

## 2. LLM Planner を有効化する

Stage 2 以降の LLM ベースタスク分解を使う場合は、`"Planner" -> "LLM"` を指定します。

```mathematica
plan = ClaudePlanTasks[
  "ある CSV を読み込み、月次集計のグラフを描いてください。",
  "Planner" -> "LLM",
  "MaxTasks" -> 6
];

plan["Tasks"] // Length
ClaudeValidateTaskSpec[plan]
```

`ClaudeValidateTaskSpec` は `<|"Valid" -> True/False, "Errors" -> {...}|>` を返します。Role 値が `$ClaudeOrchestratorRoles` に含まれること、依存グラフが DAG であること等が検証されます。

---

## 3. 非同期実行（Phase 32 拡張）

Phase 32 から `ClaudeRunOrchestrationAsync` が公開され、フロントエンドをブロックせずに DAG を回せます。

```mathematica
orchJobId = ClaudeRunOrchestrationAsync[
  "テスト用の小さなレポートを作ってください。",
  "MaxTasks" -> 4,
  "MaxParallelism" -> 2
];

(* 状況を監視 *)
ClaudeOrchestrationStatus[orchJobId]

(* 現在追跡中のジョブ一覧 *)
ClaudeOrchestrationJobs[]

(* テスト・スクリプト専用の同期待機 (対話セッションでは推奨しない) *)
ClaudeOrchestrationWait[orchJobId, 300];

(* 完了したら最終結果を取得 *)
ClaudeOrchestrationResult[orchJobId]
```

途中で中止したい場合は `ClaudeOrchestrationCancel[orchJobId]` を呼びます。`$ClaudeOrchestratorAsyncMode = False` にすると、`$ClaudeEvalHook` 経由の自動実行を旧同期挙動に戻せます。

---

## 4. Auto ゲートで Single / Orchestrator を切り替える

Phase 32 Task 3.2 で追加された Auto ゲート用ターミナル定数を確認・拡張する例です。

```mathematica
(* 現在の定数を確認 *)
$ClaudeEvalAutoSkipKeywords     // Short
$ClaudeEvalAutoFactualEndings   // Short
$ClaudeEvalAutoComplexMarkers   // Short

(* プロジェクト固有のシンボル名を追加 *)
AppendTo[$ClaudeEvalAutoSkipKeywords, "MyProjectSymbol"];

(* 短い factual query は Orchestrator を経由せず Single に流れる *)
(* "MyProjectSymbol の引数は?" のような問い合わせがフォールバック対象になる *)
```

「スライド」「レポート」「プレゼン」など `$ClaudeEvalAutoComplexMarkers` に含まれる語がプロンプトにあれば、短い文字数でも Orchestrator 経路を通します。

---

## 5. Reduce と Commit を別々に扱う

`ClaudeRunOrchestration` が内部で行っていることを段階的に確認します。

```mathematica
plan      = ClaudePlanTasks[input, "Planner" -> "LLM"];
spawn     = ClaudeSpawnWorkers[plan, "MaxParallelism" -> 2];
artifacts = ClaudeCollectArtifacts[spawn];
reduced   = ClaudeReduceArtifacts[spawn["Artifacts"]];

ClaudeValidateArtifact[reduced, plan["Tasks"][[-1, "OutputSchema"]]]

(* 確認後にだけ commit *)
ClaudeCommitArtifacts[
  EvaluationNotebook[], reduced,
  "CommitMode" -> "Transactional",
  "CommitRetryMax" -> 2
]
```

`"CommitMode" -> "Transactional"` を指定すると shadow buffer に書き込んだ後に verify が走り、失敗時には target notebook を無変更のまま rollback します。返値 `<|"Status" -> "Committed" | "Failed" | "RolledBack", ...|>` を必ず確認してください。

---

## 6. ClaudeContinueBatch で同一 runtime に複数 prompt を流す

複数の小タスクを単一 runtime で順次回し、notebook 共有問題を避ける現実解です。

```mathematica
rt = CreateClaudeRuntime[];
results = ClaudeContinueBatch[
  rt,
  {
    "1. このノートブックの目次を作ってください。",
    "2. 目次の各章に対応する図を 1 枚ずつ提案してください。",
    "3. 章ごとに 100 字程度の要約を書いてください。"
  },
  "WaitBetween" -> Quantity[1, "Seconds"]
];

results // Dataset
```

戻り値は `{<|"Index" -> i, "Prompt" -> ..., "Result" -> ...|>, ...}` です。

---

## 7. ペトリネット拡張で「自然文 → ペトリネット → 実行」

Phase 36 以降、`docs/examples/` 配下に自然文プロンプトからペトリネットを構築し実行するサンプルが同梱されています。本節のメインユースケースです。

### 7.1 同梱サンプルをロードして実行する

```mathematica
(* パッケージ配置ディレクトリを基準にサンプルを解決 *)
petriExampleFile = FileNameJoin[{
  Quiet @ Check[NotebookDirectory[], $packageDirectory],
  "ClaudeOrchestrator", "docs", "examples", "petri_from_prompt.wl"
}];

(* 自分の環境にあわせて存在を確認 *)
FileExistsQ[petriExampleFile]

(* スクリプトを評価 *)
Get[petriExampleFile]
```

`petri_from_prompt.wl` は次のような流れを 1 ファイルで実演します。

1. `ClaudeOrchestrator` をロードし、Auto ゲート（`$ClaudeEvalAutoComplexMarkers` 等）でペトリネット要求を Orchestrator 経路に確実に振り分ける。
2. 自然文プロンプト（例: 「在庫補充プロセスを 3 プレース・2 トランジションのペトリネットでモデル化してください」）を `ClaudeRunOrchestration` に渡し、`Plan → Spawn → Reduce` を経て place / transition / arc を含む artifact を生成。
3. Reduce で得られた構造を `Places`, `Transitions`, `Arcs`, `InitialMarking` の Association に正規化し、トークンの推移を `NestList` で展開して可視化する。

実行が終わると、ノートブック側には `petriResult` のような変数（サンプル先頭で説明されています）に最終 marking 列と図が束ねられた Association が残ります。

### 7.2 サンプルを改造してカスタム要求を出す

ファイル末尾の `prompt = "..."` 行を書き換えるだけで他のシステムに適用できます。

```mathematica
(* サンプル内部で定義されている関数を再利用 (Get 済みであることが前提) *)
customResult = ClaudeOrchestratorPetriFromPrompt[
  "信号機を Place=赤/黄/青、Transition=遷移3つのペトリネットでモデル化し、\
   初期マーキングは赤に1トークン置いてください。"
];

customResult["Places"]
customResult["Transitions"]
customResult["InitialMarking"]
customResult["Diagram"]
```

`Diagram` には `GraphPlot` ベースの可視化が、`Trace` には `NestList` による marking 履歴が入ります。

### 7.3 Worker 制約（重要）

ペトリネット生成タスクの worker は `$ClaudeOrchestratorDenyHeads`（`NotebookWrite`, `CreateNotebook`, `EvaluationNotebook`, `RunProcess`, `SystemCredential` ほか）を提案できません。したがって、worker は **構造データ（Association/JSON）のみ**を返し、グラフ描画や notebook への書き込みは single committer 側か `petri_from_prompt.wl` 内のローカルコードで行います。サンプルはこの分離原則を守った構造になっています。

---

## 8. Real LLM を使った診断

`$ClaudeOrchestratorRealLLMEndpoint` で real LLM 経路を有効化し、planner の入出力を切り分けて確認できます。

```mathematica
$ClaudeOrchestratorRealLLMEndpoint = "ClaudeCode";  (* または "CLI" / fn *)
ClaudeRealLLMAvailable[]

(* 単発の prompt 診断 *)
ClaudeRealLLMDiagnose["1+1 を計算してください。"]
(* -> <|"Endpoint" -> ..., "ExitCode" -> ..., "RawStdout" -> ...,
        "Unwrapped" -> ..., "JsonParseOK" -> True|False, ...|> *)

(* Planner パイプラインまで含めた診断 *)
ClaudeRealLLMDiagnosePlan["短いレポートを作ってください。"]
```

CLI モードを使う場合は `$ClaudeOrchestratorCLICommand` または環境変数 `CLAUDE_ORCH_CLI_PATH` で実行パスを上書きできます。実 LLM テストは `CLAUDE_ORCH_REAL_LLM` 環境変数でも opt-in 可能です。

---

## 9. 公開シンボル早見表（例で使ったもの）

| シンボル | 用途 |
| --- | --- |
| `ClaudePlanTasks` | プロンプトを TaskSpec DAG へ分解 |
| `ClaudeValidateTaskSpec` | TaskSpec の妥当性検証 |
| `ClaudeSpawnWorkers` | 依存順に worker を配車し artifact を収集 |
| `ClaudeCollectArtifacts` | spawn 結果を Dataset 化 |
| `ClaudeValidateArtifact` | OutputSchema 準拠を検査 |
| `ClaudeReduceArtifacts` | artifact 群を統合 |
| `ClaudeCommitArtifacts` | single committer で notebook に反映 |
| `ClaudeRunOrchestration` | 4 フェーズを直列に実行 |
| `ClaudeRunOrchestrationAsync` | 4 フェーズを非同期実行 |
| `ClaudeOrchestrationStatus` / `Result` / `Wait` / `Cancel` / `Jobs` | 非同期ジョブの管理 |
| `ClaudeContinueBatch` | 単一 runtime で連続 prompt |
| `ClaudeRealLLMAvailable` / `Query` / `Diagnose` / `DiagnosePlan` | real LLM 経路の検査 |
| `$ClaudeOrchestratorAsyncMode` | 非同期/同期モード切替 |
| `$ClaudeEvalAutoSkipKeywords` ほか | Auto ゲートのチューニング |
| `$ClaudeOrchestratorRealLLMEndpoint` / `$ClaudeOrchestratorCLICommand` | real LLM 経路の設定 |

---

## 10. トラブルシューティング Tips

- `ClaudeRunOrchestration` が即座に `Single` フォールバックされる場合、プロンプトが短く `$ClaudeEvalAutoSkipKeywords` / `$ClaudeEvalAutoFactualEndings` の条件に合致しています。`$ClaudeEvalAutoComplexMarkers` に該当語（「ペトリネット」「スライド」など）を追加するか、プロンプトに「複数の成果物を作ってください」のような複雑さ指標を含めてください。
- Commit が `Failed` / `RolledBack` を返す場合、`CommitResult["Diagnostics"]` に `HeldExprFound` / `LastProviderResponseHead` が付属します。診断に使えます。
- 非同期実行のジョブが残り続けるときは `ClaudeOrchestrationJobs[]` で一覧し、`ClaudeOrchestrationCancel` で明示的に解放してください。
- ペトリネットサンプルが見つからない場合は、`$packageDirectory` 直下の `ClaudeOrchestrator/docs/examples/petri_from_prompt.wl` の存在を `FileExistsQ` で確認し、無ければパッケージを最新版に更新してください。