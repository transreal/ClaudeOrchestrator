# ClaudeOrchestrator ユーザーマニュアル

## 目次

1. [概要](#概要)
2. [基本的な使い方](#基本的な使い方)
3. [タスク分解・計画フェーズ](#タスク分解計画フェーズ)
4. [ワーカー起動・アーティファクト収集フェーズ](#ワーカー起動アーティファクト収集フェーズ)
5. [アーティファクト統合フェーズ](#アーティファクト統合フェーズ)
6. [コミットフェーズ](#コミットフェーズ)
7. [一括実行](#一括実行)
8. [非同期実行 API](#非同期実行-api)
9. [バッチ実行](#バッチ実行)
10. [Real LLM 統合](#real-llm-統合)
11. [グローバル設定変数](#グローバル設定変数)
12. [エラーと検証](#エラーと検証)

---

## 概要

ClaudeOrchestrator は [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) の上位レイヤーとして動作する、マルチエージェント分解・並列ワーカー配車・アーティファクト収集・統合・コミット機構です。

**設計上の基本原則:**

- ClaudeRuntime は単一エージェント実行核として維持します。
- 並列ワーカーはアーティファクト生成のみを担当し、`NotebookWrite` を直接呼び出しません。
- 実ノートブックへの書き込みは **single committer** のみが行います。
- ワーカー間の共有状態は明示的な `Association` / JSON / アーティファクトで受け渡します。

```
NBAccess → claudecode_base → ClaudeRuntime → ClaudeOrchestrator → claudecode
```

**ClaudeEval の非同期化（v2026-04-20 以降）:**

`$ClaudeEvalHook`（ClaudeEval）はデフォルトで **非同期モード** で動作します。`$ClaudeOrchestratorAsyncMode` が `True`（既定値）の場合、`$ClaudeEvalHook` はオーケストレーションを `ClaudeRunOrchestrationAsync` 経由で起動し、フロントエンド（ノートブック UI）をブロックせずに `orchJobId` を即座に返します。完了後の結果は `ClaudeOrchestrationResult` で取得できます。同期動作に戻したい場合は `$ClaudeOrchestratorAsyncMode = False` に設定してください。

---

## 基本的な使い方

```wolfram
(* パッケージ読み込み *)
Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]
Needs["ClaudeOrchestrator`"]
```

最もシンプルな使い方は `ClaudeRunOrchestration` による一括実行です。

```wolfram
result = ClaudeRunOrchestration[
  "30ページのスライド資料を作成する",
  MaxTasks -> 5
];
result["Status"]
(* "Complete" *)
```

フロントエンドをブロックせずに実行したい場合（既定の動作）は `ClaudeRunOrchestrationAsync` を使用します。

```wolfram
jobId = ClaudeRunOrchestrationAsync[
  "30ページのスライド資料を作成する",
  MaxTasks -> 5
];
(* すぐに orchJobId が返る — ノートブック UI はブロックされない *)
ClaudeOrchestrationResult[jobId]  (* 完了後に結果を取得 *)
```

---

## タスク分解・計画フェーズ

### ClaudePlanTasks

親タスクを TaskSpec の DAG (有向非巡回グラフ) に分解します。

**シグネチャ:**
```wolfram
ClaudePlanTasks[input, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `Planner` | `Automatic` | プランナー関数（省略時はモック） |
| `MaxTasks` | `10` | 生成するタスクの最大数 |

**戻り値の構造:**
```wolfram
<|
  "Tasks" -> {
    <|
      "TaskId" -> "t1",
      "Role" -> "Explore",
      "Goal" -> "テンプレートの構造を把握する",
      "Inputs" -> {"templateSnapshot"},
      "Outputs" -> {"templateSummary"},
      "Capabilities" -> {"ReadNotebookSnapshot", "StructuredOutput"},
      "DependsOn" -> {},
      "ExpectedArtifactType" -> "TemplateSummary",
      "OutputSchema" -> <|"Headings" -> "List[String]", ...|>
    |>,
    ...
  }
|>
```

**使用例:**
```wolfram
plan = ClaudePlanTasks[
  "Mathematica パッケージのドキュメントを自動生成する",
  MaxTasks -> 4
];
plan["Tasks"] // Length
(* 4 *)
```

---

### ClaudeValidateTaskSpec

TaskSpec の妥当性 (必須キーの存在、Role の整合性など) を検証します。

**シグネチャ:**
```wolfram
ClaudeValidateTaskSpec[taskSpec]
```

**戻り値:** `<|"Valid" -> True/False, "Errors" -> {...}|>`

**使用例:**
```wolfram
validation = ClaudeValidateTaskSpec[plan];
If[validation["Valid"],
  Print["TaskSpec is valid."],
  Print[validation["Errors"]]
]
```

---

## ワーカー起動・アーティファクト収集フェーズ

### ClaudeSpawnWorkers

TaskSpec の依存順に従ってワーカー runtime を起動し、各タスクのアーティファクトを収集します。現バージョンは順次実行（`MaxParallelism -> 1`）です。

**シグネチャ:**
```wolfram
ClaudeSpawnWorkers[tasks, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `WorkerAdapterBuilder` | `Automatic` | `(Role, TaskSpec) -> adapter` を返す関数 |
| `MaxParallelism` | `1` | 並列数（Stage 2 以降で拡張予定） |

**戻り値:**
```wolfram
<|
  "Artifacts" -> <|"t1" -> artifact1, "t2" -> artifact2, ...|>,
  "Failures"  -> {},
  "Status"    -> "Complete"  (* "Complete" | "Partial" | "Failed" *)
|>
```

**使用例:**
```wolfram
spawnResult = ClaudeSpawnWorkers[plan["Tasks"]];
spawnResult["Status"]
(* "Complete" *)
```

---

### ClaudeCollectArtifacts

`ClaudeSpawnWorkers` の結果からアーティファクトを `Dataset` として取得します。ノートブック上で確認しやすい形式で返します。

**シグネチャ:**
```wolfram
ClaudeCollectArtifacts[spawnResult]
```

**使用例:**
```wolfram
artifacts = ClaudeCollectArtifacts[spawnResult];
artifacts  (* Dataset として表示 *)
```

---

### ClaudeValidateArtifact

アーティファクトの `Payload` が `OutputSchema` を満たすか検証します。

**シグネチャ:**
```wolfram
ClaudeValidateArtifact[artifact, outputSchema]
```

**戻り値:** `<|"Valid" -> True/False, "Errors" -> {...}|>`

**使用例:**
```wolfram
schema = <|"Headings" -> "List[String]", "Constraints" -> "List[String]"|>;
ClaudeValidateArtifact[artifacts["t1"], schema]
(* <|"Valid" -> True, "Errors" -> {}|> *)
```

---

## アーティファクト統合フェーズ

### ClaudeReduceArtifacts

複数のアーティファクトを統合し、ReducedArtifact を生成します。

**シグネチャ:**
```wolfram
ClaudeReduceArtifacts[artifacts, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `Reducer` | `Automatic` | `artifacts -> ReducedArtifact` を返す関数 |

**戻り値:**
```wolfram
<|
  "ArtifactType" -> "Reduced",
  "Payload"      -> <| ... |>,
  "Sources"      -> {"t1", "t2", ...}
|>
```

**使用例:**
```wolfram
reduced = ClaudeReduceArtifacts[
  spawnResult["Artifacts"],
  Reducer -> Function[arts, <|"Summary" -> arts|>]
];
reduced["ArtifactType"]
(* "Reduced" *)
```

---

## コミットフェーズ

### ClaudeCommitArtifacts

single committer runtime を起動し、`reducedArtifact` を対象ノートブックに反映します。

**重要:** `EvaluationNotebook[]` / `CreateNotebook[...]` への参照は、指定した `targetNotebook` に自動置換されます。

**シグネチャ:**
```wolfram
ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `CommitterAdapterBuilder` | `Automatic` | committer adapter 構築関数 |
| `CommitMode` | `"Direct"` | `"Direct"` または `"Transactional"` |
| `Verifier` | `Automatic` | `(buffer, cells) -> True/False` |

**`"Transactional"` モード:** shadow buffer に書いてから検証・フラッシュします。失敗時は対象ノートブックを無変更のまま rollback します (spec §12.3)。

**戻り値:**
```wolfram
<|
  "Status"  -> "Committed"  (* "Committed" | "Failed" | "RolledBack" *),
  "Mode"    -> "Direct",
  "Details" -> <| ... |>
|>
```

**使用例:**
```wolfram
nb = InputNotebook[];
commitResult = ClaudeCommitArtifacts[nb, reduced,
  CommitMode -> "Transactional"
];
commitResult["Status"]
(* "Committed" *)
```

---

## 一括実行

### ClaudeRunOrchestration

Planning → Spawn → Reduce → Commit の全フェーズを直列で実行します。小〜中規模のタスクに適しています。

フロントエンドをブロックしない非同期版は [`ClaudeRunOrchestrationAsync`](#clauderunorchestrationasync) を使用してください。`$ClaudeEvalHook` は既定でこちらを使います。

**シグネチャ:**
```wolfram
ClaudeRunOrchestration[input, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `TargetNotebook` | (なし) | Commit 先ノートブック（指定時のみ Commit フェーズを実行） |
| `Planner` | `Automatic` | プランナー関数 |
| `WorkerAdapterBuilder` | `Automatic` | ワーカー adapter 構築関数 |
| `Reducer` | `Automatic` | Reducer 関数 |
| `CommitterAdapterBuilder` | `Automatic` | Committer adapter 構築関数 |
| `MaxTasks` | `10` | タスク上限数 |
| `MaxParallelism` | `1` | 並列数 |
| `Confirm` | `False` | 各フェーズ前に確認を求めるか |

**戻り値:** 4 フェーズの結果を束ねた `Association`

**使用例（Commit なし）:**
```wolfram
result = ClaudeRunOrchestration[
  "パッケージの使用例を 5 つ生成する",
  MaxTasks -> 3
];
result["SpawnResult", "Status"]
(* "Complete" *)
```

**使用例（Commit あり）:**
```wolfram
result = ClaudeRunOrchestration[
  "レポートの草稿をノートブックに書く",
  TargetNotebook -> InputNotebook[],
  MaxTasks -> 5,
  CommitMode -> "Transactional"
];
```

---

## 非同期実行 API

長時間かかるオーケストレーションはフロントエンドをブロックしないよう非同期実行が推奨です。

**v2026-04-20 以降、`$ClaudeEvalHook`（ClaudeEval）はデフォルトで非同期モードで動作します。** `$ClaudeOrchestratorAsyncMode` が `True`（既定）のとき、`$ClaudeEvalHook` はオーケストレーションを `ClaudeRunOrchestrationAsync` 経由で起動し、`orchJobId` を即座に返します。フロントエンドのセル評価はブロックされません。

同期モードに戻すには `$ClaudeOrchestratorAsyncMode = False` を設定してください（詳細は[グローバル設定変数](#グローバル設定変数)を参照）。

### ClaudeRunOrchestrationAsync

Planning → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し、`orchJobId` を即座に返します。

**シグネチャ:**
```wolfram
ClaudeRunOrchestrationAsync[input, opts]
```

オプションは `ClaudeRunOrchestration` と同じです。

**`$ClaudeEvalHook` との関係:**

`$ClaudeOrchestratorAsyncMode` が `True` のとき、`$ClaudeEvalHook` は内部的にこの関数を呼び出します。ノートブックのセルを評価するとバックグラウンドでオーケストレーションが開始され、セルの評価は即座に完了します。結果は `ClaudeOrchestrationResult` で後から取得します。

```wolfram
(* $ClaudeEvalHook 経由の動作イメージ（内部） *)
(* $ClaudeOrchestratorAsyncMode = True のとき *)
jobId = ClaudeRunOrchestrationAsync["論文要約を 3 つ作成する", MaxTasks -> 3];
jobId
(* "orch-20260421-001" — フロントエンドはここで返る *)
```

**直接呼び出しの例:**
```wolfram
jobId = ClaudeRunOrchestrationAsync["論文要約を 3 つ作成する", MaxTasks -> 3];
jobId
(* "orch-20260421-001" *)
```

---

### ClaudeOrchestrationStatus

実行中ジョブの現在フェーズと経過時間を返します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationStatus[orchJobId]
```

**戻り値例:**
```wolfram
<|
  "Status"      -> "Spawning",
  "Phase"       -> "worker-t2",
  "ElapsedSecs" -> 12.4,
  "PlanJobId"   -> "plan-001",
  "SpawnJobId"  -> "spawn-001"
|>
```

---

### ClaudeOrchestrationResult

完了済みジョブの最終結果を返します。未完了の場合は `Missing` を返します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationResult[orchJobId]
```

**使用例:**
```wolfram
(* ポーリング例 *)
While[ClaudeOrchestrationStatus[jobId]["Status"] =!= "Done", Pause[5]];
ClaudeOrchestrationResult[jobId]
```

---

### ClaudeOrchestrationWait

ジョブ完了まで待機します（テスト・スクリプト専用。対話セルでは使用を避けてください）。

**シグネチャ:**
```wolfram
ClaudeOrchestrationWait[orchJobId, timeoutSec]
```

既定タイムアウトは 300 秒です。

**使用例:**
```wolfram
ClaudeOrchestrationWait[jobId, 120]
ClaudeOrchestrationResult[jobId]
```

---

### ClaudeOrchestrationCancel

実行中の DAG を中断し、レジストリから除去します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationCancel[orchJobId]
```

**使用例:**
```wolfram
ClaudeOrchestrationCancel[jobId]
```

---

### ClaudeOrchestrationJobs

追跡中のジョブ一覧を `Dataset` で返します。

**シグネチャ:**
```wolfram
ClaudeOrchestrationJobs[]
```

**使用例:**
```wolfram
ClaudeOrchestrationJobs[]
(* Dataset[<|"orch-001" -> <|"Status" -> "Done", ...|>, ...|>] *)
```

---

## バッチ実行

### ClaudeContinueBatch

単一の runtime セッションを維持したまま、複数の prompt を `ClaudeContinueTurn` で順次投入します。ノートブック共有問題を回避する現実解です（spec §17.1）。

**シグネチャ:**
```wolfram
ClaudeContinueBatch[runtimeId, batchInstructions, opts]
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `WaitBetween` | `Quantity[1, "Seconds"]` | 各プロンプト間の待機時間 |

**戻り値:** `{<|"Index" -> i, "Prompt" -> ..., "Result" -> ...|>, ...}`

**使用例:**
```wolfram
rt = CreateClaudeRuntime[...];  (* ClaudeRuntime より *)
batchResult = ClaudeContinueBatch[
  rt["RuntimeId"],
  {"第1章を要約せよ", "第2章を要約せよ", "全体をまとめよ"},
  WaitBetween -> Quantity[2, "Seconds"]
];
batchResult[[All, "Result"]]
```

---

## Real LLM 統合

テスト・開発時はモック動作しますが、本物の LLM エンドポイントに接続することもできます。

### ClaudeRealLLMAvailable

Real LLM 統合が設定済みかどうかを確認します。

**シグネチャ:**
```wolfram
ClaudeRealLLMAvailable[]
(* True / False *)
```

---

### ClaudeRealLLMQuery

設定済みのエンドポイントを使って prompt を実行します。

**シグネチャ:**
```wolfram
ClaudeRealLLMQuery[prompt]
(* 応答 String または $Failed *)
```

**使用例:**
```wolfram
$ClaudeOrchestratorRealLLMEndpoint = "ClaudeCode";
ClaudeRealLLMQuery["Wolfram Language で Hello World を書いてください"]
(* "Print[\"Hello World\"]" *)
```

---

### ClaudeRealLLMDiagnose

Real LLM 呼び出しを実行し、エンドポイント・CLIパス・終了コード・raw stdout・JSON パース可否などの診断情報を返します。呼び出し失敗時の切り分けに使います。

**シグネチャ:**
```wolfram
ClaudeRealLLMDiagnose[prompt]
```

**使用例:**
```wolfram
diag = ClaudeRealLLMDiagnose["test"];
diag["ExitCode"]    (* 0 *)
diag["JsonParsed"]  (* True / False *)
```

---

### ClaudeRealLLMDiagnosePlan

Real LLM planner パイプライン全体を実行し、プラン結果・raw LLM 応答・タスク数・ステータス・エラー情報を返します。プランニングフェーズの失敗切り分けに使います。

**シグネチャ:**
```wolfram
ClaudeRealLLMDiagnosePlan[input]
```

**使用例:**
```wolfram
pd = ClaudeRealLLMDiagnosePlan["ドキュメントを自動生成する"];
pd["TaskCount"]  (* 3 *)
pd["Status"]     (* "OK" / "Failed" *)
```

---

## グローバル設定変数

| 変数 | 既定値 | 説明 |
|---|---|---|
| `$ClaudeOrchestratorVersion` | (文字列) | パッケージバージョン |
| `$ClaudeOrchestratorRoles` | `{"Explore","Plan","Draft","Verify","Reduce","Commit"}` | 許容 Role 一覧 |
| `$ClaudeOrchestratorCapabilities` | `Association` | Role → Capability リスト |
| `$ClaudeOrchestratorDenyHeads` | `{NotebookWrite, CreateNotebook, ...}` | ワーカー禁止ヘッド一覧 |
| `$ClaudeOrchestratorRealLLMEndpoint` | `None` | Real LLM エンドポイント設定 |
| `$ClaudeOrchestratorCLICommand` | `Automatic` | CLI コマンド名/パス |
| `$ClaudeOrchestratorAsyncMode` | `True` | `$ClaudeEvalHook` の非同期モード有効/無効 |

### `$ClaudeOrchestratorRealLLMEndpoint` の設定値

| 値 | 動作 |
|---|---|
| `None` | Real LLM テストをスキップ（既定） |
| `"ClaudeCode"` | `ClaudeCode``ClaudeQueryBg`（同期版）を使用 |
| `"CLI"` | `claude` CLI を `RunProcess` 経由で呼び出す |
| `fn[prompt]` | カスタム関数を使用 |

環境変数 `CLAUDE_ORCH_REAL_LLM` でも opt-in できます。

### `$ClaudeOrchestratorAsyncMode` の切り替え

`$ClaudeOrchestratorAsyncMode` は `$ClaudeEvalHook`（ClaudeEval）が非同期経路（`ClaudeRunOrchestrationAsync`）と同期経路（`ClaudeRunOrchestration`）のどちらを使うかを制御します。

**既定は `True`（非同期）です。** ノートブックのセル評価はブロックされず、バックグラウンドでオーケストレーションが実行されます。

```wolfram
(* 同期モードに切り替える（旧来の挙動） *)
$ClaudeOrchestratorAsyncMode = False;

(* 非同期モードに戻す（既定） *)
$ClaudeOrchestratorAsyncMode = True;
```

**非同期モード（`True`）の動作フロー:**

1. `$ClaudeEvalHook` が `ClaudeRunOrchestrationAsync` を呼び出し、`orchJobId` を即座に返す
2. バックグラウンドで DAG コールバックチェーンが Planning → Spawn → Reduce → Commit を実行
3. `ClaudeOrchestrationStatus[jobId]` で進捗を確認
4. `ClaudeOrchestrationResult[jobId]` で完了後の結果を取得

**同期モード（`False`）の動作フロー:**

1. `$ClaudeEvalHook` が `ClaudeRunOrchestration` を呼び出す
2. 全フェーズ完了まで評価セルがブロックされる
3. 完了時に結果が直接返される

---

## エラーと検証

### よくあるエラーと対処法

| 症状 | 原因 | 対処 |
|---|---|---|
| `ClaudeValidateTaskSpec` が `"Valid" -> False` を返す | TaskSpec に必須キーが不足している | `"Errors"` の内容を確認し、全必須キーを補完する |
| `SpawnResult["Status"] == "Partial"` | 一部ワーカーが失敗 | `SpawnResult["Failures"]` を確認し、該当タスクを再実行する |
| `CommitResult["Status"] == "RolledBack"` | Verifier が検証失敗 | `CommitResult["Details"]` を確認し、reduced artifact を修正する |
| `ClaudeRealLLMQuery` が `$Failed` を返す | エンドポイントの設定誤り | `ClaudeRealLLMDiagnose` で詳細を確認する |
| `ClaudeOrchestrationResult[jobId]` が `Missing` を返す | ジョブが未完了 | `ClaudeOrchestrationStatus[jobId]["Status"]` で進捗を確認する |
| 非同期ジョブが `"Failed"` 状態になる | バックグラウンド実行中のエラー | `ClaudeOrchestrationResult[jobId]["Failures"]` でエラー詳細を確認する |

### TaskSpec の必須キー

`ClaudeValidateTaskSpec` は以下のキーをすべて要求します。

```wolfram
{"TaskId", "Role", "Goal", "Inputs", "Outputs",
 "Capabilities", "DependsOn", "ExpectedArtifactType", "OutputSchema"}
```

### 許容 Role

```wolfram
$ClaudeOrchestratorRoles
(* {"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"} *)