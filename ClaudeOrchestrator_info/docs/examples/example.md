# ClaudeOrchestrator 使用例集

ClaudeOrchestrator パッケージの代表的な使用例をまとめています。

---

## 事前準備

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$packageDirectory, "ClaudeOrchestrator.wl"}]]
]
```

---

## 例 1: バージョン確認

```mathematica
$ClaudeOrchestratorVersion
```

**期待される出力例:** `"1.0.0"`

---

## 例 2: タスク分解 (モック planner)

```mathematica
plan = ClaudePlanTasks["Mathematica で素数リストを生成して CSV に保存する"];
plan["Tasks"][[All, {"TaskId", "Role", "Goal"}]]
```

**期待される出力例:** `{<|"TaskId"->"t1","Role"->"Explore","Goal"->"要件確認"|>, <|"TaskId"->"t2","Role"->"Draft","Goal"->"コード生成"|>, ...}`

---

## 例 3: TaskSpec の検証

```mathematica
spec = <|
  "TaskId" -> "t1", "Role" -> "Draft",
  "Goal" -> "素数リストを生成する",
  "Inputs" -> {}, "Outputs" -> {"primes.csv"},
  "Capabilities" -> {"FileWrite"}, "DependsOn" -> {},
  "ExpectedArtifactType" -> "File", "OutputSchema" -> <||>
|>;
ClaudeValidateTaskSpec[spec]
```

**期待される出力例:** `<|"Valid" -> True, "Errors" -> {}|>`

---

## 例 4: Worker の起動と Artifact 収集

```mathematica
tasks = plan["Tasks"];
spawnResult = ClaudeSpawnWorkers[tasks];
ClaudeCollectArtifacts[spawnResult]
```

**期待される出力例:** `Dataset[<|"t1" -> <|"ArtifactType"->"Text","Payload"->...|>, ...|>]`

---

## 例 5: Artifact の統合 (Reduce)

```mathematica
artifacts = spawnResult["Artifacts"];
reduced = ClaudeReduceArtifacts[artifacts];
reduced[["ArtifactType"]]
```

**期待される出力例:** `"Reduced"`

---

## 例 6: ノートブックへのコミット

```mathematica
nb = InputNotebook[];
result = ClaudeCommitArtifacts[nb, reduced];
result[["Status"]]
```

**期待される出力例:** `"Committed"`

---

## 例 7: フルパイプラインの同期実行

```mathematica
result = ClaudeRunOrchestration[
  "フィボナッチ数列を計算して表示する",
  TargetNotebook -> InputNotebook[],
  MaxTasks -> 5
];
result[["ReducePhase", "ArtifactType"]]
```

**期待される出力例:** `"Reduced"`

---

## 例 8: 非同期オーケストレーションと状態監視

```mathematica
(* ジョブを非同期で起動 *)
jobId = ClaudeRunOrchestrationAsync[
  "行列の固有値を求めてレポートを生成する",
  MaxTasks -> 4
];

(* 状態を確認 *)
ClaudeOrchestrationStatus[jobId][["Status"]]
```

**期待される出力例:** `"Planning"` (後に `"Done"` へ遷移)

```mathematica
(* 完了を待機してから結果取得 *)
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["SpawnPhase", "Status"]]
```

**期待される出力例:** `"Complete"`

---

## 例 9: バッチ処理 (単一セッション継続)

```mathematica
runtime = First @ ClaudeSpawnWorkers[tasks]["Artifacts"];
runtimeId = runtime["RuntimeId"];

results = ClaudeContinueBatch[
  runtimeId,
  {"ステップ 1 を実行", "ステップ 2 を実行", "結果を要約"},
  WaitBetween -> Quantity[2, "Seconds"]
];
results[[All, "Index"]]
```

**期待される出力例:** `{1, 2, 3}`

---

## 例 10: real LLM 統合の診断

```mathematica
$ClaudeOrchestratorRealLLMEndpoint = "ClaudeCode";
diag = ClaudeRealLLMDiagnose["Hello, world!"];
diag[["ExitCode"]]
```

**期待される出力例:** `0`

---

## 例 11: ジョブ一覧と中断

```mathematica
(* 現在実行中のジョブを確認 *)
ClaudeOrchestrationJobs[]

(* 不要なジョブを中断 *)
ClaudeOrchestrationCancel[jobId]
```

**期待される出力例:** `Dataset[{<|"JobId"->..., "Status"->"Running", ...|>}]` / `True`