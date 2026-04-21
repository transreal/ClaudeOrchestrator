# ClaudeRuntime / ClaudeTestKit 向けマルチエージェント分解・並列作業機構 仕様案

## 1. 目的

ClaudeRuntime / ClaudeTestKit 上で、複雑な問題を安全かつ安定に分解し、複数のエージェント相当の作業単位へ配車し、最後に一つの整合した成果物へ集約するための機構を定義する。

本仕様は、既存の `ClaudeRuntime` を **単一エージェント実行核**として維持しつつ、その上位に **分解・配車・集約・コミット** を担当するオーケストレーション層を追加することを前提とする。

---

## 2. 背景と問題認識

既存の分解方式では、サブターンを独立した CLI プロセスとして起動し、それぞれに notebook への直接書き込みを期待した。しかしこの方式では、以下の問題が発生した。

- サブターン間で Mathematica 変数が共有されない
- `EvaluationNotebook[]` が現在の notebook を安定に指さない
- `CreateNotebook[...]` による意図しない新規 notebook 作成が起こる
- `<tool_call>` タグと Mathematica proposal が混線する
- 先行サブターン結果が空や `Null` で依存解決に失敗する
- 結果として「部分的には成功」と見えても、現在の notebook には何も書かれない

したがって、**並列 worker に live notebook への直接副作用を持たせる設計は採用しない**。この判断は、Phase 31 の引継ぎメモに記された到達点と限界、および当面は段階的 `ClaudeContinueTurn` を使うべきという結論に基づく。fileciteturn9file0

---

## 3. 基本設計方針

### 3.1 中核方針

1. `ClaudeRuntime` は **1 agent kernel** のまま維持する
2. 複数エージェント化は `ClaudeRuntime` の外側の **オーケストレータ層**で行う
3. 並列 worker は **artifact producer** としてのみ動作する
4. 実 notebook への最終書き込みは **single committer** のみが担当する
5. worker 間の共有状態は Mathematica 変数ではなく **明示的 artifact / JSON / Association** で受け渡す

### 3.2 非目標

本仕様は以下を当面の非目標とする。

- 複数 worker による live notebook への同時直接書き込み
- 暗黙的な Mathematica 変数共有
- `EvaluationNotebook[]` 依存の分散作業
- 自由文だけで依存を受け渡す曖昧な分解

---

## 4. 全体アーキテクチャ

```text
NBAccess
  ↑
claudecode_base
  ↑
ClaudeRuntime            ← 単一エージェント実行核
  ↑
ClaudeOrchestrator       ← 新設
  ↑
claudecode
```

### 4.1 ClaudeRuntime の責務

- `BuildContext`
- `QueryProvider`
- `ParseProposal`
- `ValidateProposal`
- `DispatchDecision`
- 1ターン実行
- 承認待ち
- continuation
- transaction
- trace / state

### 4.2 ClaudeOrchestrator の責務

- 親タスクの分解
- Task DAG の生成
- worker runtime の起動
- artifact の収集
- reducer / verifier の実行
- single committer の起動
- 進捗・失敗・再試行の管理

---

## 5. 役割分離

### 5.1 Planner
親タスクを Task DAG に分解する。

### 5.2 Worker
個別タスクを実行し、artifact を返す。  
**NotebookWrite は禁止**。

### 5.3 Reducer
複数 artifact を統合し、整合した中間成果物を作る。  
**NotebookWrite は禁止**。

### 5.4 Verifier
artifact や reducer 結果を検証し、不足・矛盾・根拠不足を検出する。  
**NotebookWrite は禁止**。

### 5.5 Committer
最終成果物を target notebook へ反映する唯一の runtime。  
**NotebookWrite を許可**するが、対象 notebook は固定注入する。

---

## 6. 並列化の対象と禁止対象

### 6.1 並列化してよいもの

- 調査
- WebSearch
- ファイル探索
- 資料要約
- 比較
- 構成案作成
- セクション草稿
- 検証
- 引用整理
- 依存関係抽出

### 6.2 並列化してはいけないもの

- 実 notebook への最終 `NotebookWrite`
- `CreateNotebook[...]`
- `EvaluationNotebook[]` 依存の処理
- mutable な Mathematica state に依存する処理
- notebook object を前提にした副作用

---

## 7. TaskSpec 仕様

Planner の出力は自由文ではなく **厳密な TaskSpec** とする。

```wl
<|
  "Tasks" -> {
    <|
      "TaskId" -> "t1",
      "Role" -> "Explore",
      "Goal" -> "テンプレート notebook の構造を把握する",
      "Inputs" -> {"templateSnapshot"},
      "Outputs" -> {"templateSummary"},
      "Capabilities" -> {"ReadNotebookSnapshot", "StructuredOutput"},
      "DependsOn" -> {},
      "ExpectedArtifactType" -> "TemplateSummary",
      "OutputSchema" -> <|
        "Headings" -> "List[String]",
        "SlidePatterns" -> "List[Association]",
        "Constraints" -> "List[String]"
      |>
    |>,
    <|
      "TaskId" -> "t2",
      "Role" -> "Plan",
      "Goal" -> "30ページ構成案を作る",
      "Inputs" -> {"templateSummary", "sourceNotes"},
      "Outputs" -> {"outline"},
      "Capabilities" -> {"StructuredOutput"},
      "DependsOn" -> {"t1"},
      "ExpectedArtifactType" -> "Outline",
      "OutputSchema" -> <|
        "Sections" -> "List[Association]",
        "Assumptions" -> "List[String]",
        "OpenQuestions" -> "List[String]"
      |>
    |>
  }
|>
```

### 7.1 必須キー

- `TaskId`
- `Role`
- `Goal`
- `Inputs`
- `Outputs`
- `Capabilities`
- `DependsOn`
- `ExpectedArtifactType`
- `OutputSchema`

### 7.2 Role の初期セット

- `Explore`
- `Plan`
- `Draft`
- `Verify`
- `Reduce`
- `Commit`

---

## 8. ArtifactSpec 仕様

worker / reducer / verifier は artifact を返す。

```wl
<|
  "TaskId" -> "t2",
  "Status" -> "Success",
  "ArtifactType" -> "Outline",
  "Payload" -> <|
    "Sections" -> {
      <|"Title" -> "導入", "Pages" -> {1,2}, "Purpose" -> "..."|>,
      <|"Title" -> "背景", "Pages" -> {3,4,5}, "Purpose" -> "..."|>
    },
    "Assumptions" -> {"テンプレートは横長スライドである"},
    "OpenQuestions" -> {"参考文献の数が不足している"}
  |>,
  "Diagnostics" -> <|
    "Warnings" -> {},
    "SourcesUsed" -> {"templateSnapshot", "sourceNotes"}
  |>
|>
```

### 8.1 必須キー

- `TaskId`
- `Status`
- `ArtifactType`
- `Payload`

### 8.2 任意キー

- `Diagnostics`
- `Warnings`
- `Confidence`
- `Notes`

---

## 9. BuildContext の改修方針

worker 用 `BuildContext` は notebook object を直接渡さず、以下を渡す。

- 正規化済み notebook snapshot
- 依存 artifact 群
- その worker の role
- 許可 capability
- expected output schema
- task goal
- 必要なら source excerpts

### 9.1 worker 用 contextPacket 例

```wl
<|
  "TaskSpec" -> taskSpec,
  "Role" -> "Explore",
  "NotebookSnapshot" -> notebookSnapshot,
  "DependencyArtifacts" -> depArtifacts,
  "AllowedCapabilities" -> {"ReadNotebookSnapshot", "StructuredOutput"},
  "OutputSchema" -> <|...|>,
  "RouteAdvice" -> <|"Route" -> "PrivateLLM"|>
|>
```

### 9.2 committer 用 contextPacket 例

```wl
<|
  "Role" -> "Commit",
  "TargetNotebook" -> targetNotebook,
  "ReducedArtifact" -> reducedArtifact,
  "AllowedCapabilities" -> {"NotebookWrite"},
  "CommitPolicy" -> <|
    "DenyCreateNotebook" -> True,
    "RewriteEvaluationNotebook" -> True
  |>
|>
```

---

## 10. Capability / Permission 設計

### 10.1 worker の capability

role ごとに許可 capability を絞る。

#### Explore
- `ReadNotebookSnapshot`
- `ReadArtifacts`
- `StructuredOutput`

#### Plan
- `ReadArtifacts`
- `StructuredOutput`

#### Draft
- `ReadArtifacts`
- `StructuredOutput`

#### Verify
- `ReadArtifacts`
- `StructuredOutput`

#### Reduce
- `ReadArtifacts`
- `StructuredOutput`

#### Commit
- `ReadArtifacts`
- `StructuredOutput`
- `NotebookWrite`

### 10.2 強制禁止事項

worker / reducer / verifier では以下を拒否する。

- `CreateNotebook`
- `NotebookWrite`
- `EvaluationNotebook`
- `RunProcess`
- `SystemCredential`
- `URLRead` など、タスクで明示許可されていない capability

### 10.3 committer の特殊ルール

- `CreateNotebook[...]` を Deny
- `EvaluationNotebook[]` は target notebook に置換
- 必要なら `With[{nb = targetNotebook}, heldExpr]` で注入
- notebook 書き込みは commit policy 下でのみ許可

---

## 11. 実行フェーズ仕様

### Phase A: Planning
親タスクを受け、Planner runtime が Task DAG を返す。

### Phase B: Worker Execution
依存が満たされた task を worker runtime として起動し、artifact を得る。

### Phase C: Reduction / Verification
artifact を reducer が統合し、必要に応じ verifier が検証する。

### Phase D: Commit
committer runtime が reduced artifact を target notebook へ反映する。

---

## 12. 失敗時の取り扱い

### 12.1 Worker Failure
- 該当 task を `Failed`
- retry policy に従って再試行可
- 依存先 task は block
- reducer へは未完了扱いで渡さない

### 12.2 Partial Success
- artifact が schema を満たすなら `SuccessWithWarnings`
- reducer が採用可否を判断

### 12.3 Commit Failure
- target notebook への反映は transaction 的に扱う
- 失敗時は rollback または commit 前状態維持
- notebook への部分反映をできるだけ避ける

---

## 13. ClaudeTestKit 拡張仕様

### 13.1 新設する mock / helper

- `CreateMockPlanner`
- `CreateMockWorkerAdapter`
- `CreateMockReducer`
- `CreateMockCommitter`
- `RunClaudeOrchestrationScenario`

### 13.2 新設する assertion

- `AssertNoWorkerNotebookMutation`
- `AssertArtifactsRespectDependencies`
- `AssertSingleCommitterWrites`
- `AssertReducerDeterministic`
- `AssertNoCrossWorkerStateAssumption`
- `AssertTaskOutputMatchesSchema`

### 13.3 必須テストケース

1. worker が `NotebookWrite` を提案したら fail
2. worker が `CreateNotebook` を提案したら fail
3. committer だけが notebook へ書ける
4. dependency 未解決 task は実行されない
5. reducer が複数 artifact を決定的に統合する
6. failed worker の結果が commit に混入しない
7. target notebook 強制束縛が動作する

---

## 14. Claw-Code から導入すべき機構

Claw-Code の対応部分から、以下を参考実装として採用する。

### 14.1 導入すべきもの

- 独立 subagent / worker の起動
- role ごとの allowed tools / capabilities 制限
- worker control plane
- team / task registry 的な管理
- 親子セッション分離

### 14.2 そのまま導入してはいけないもの

- worker に live notebook mutation をさせる設計
- shared mutable Mathematica state を暗黙的に期待する設計

---

## 15. 既存 Phase 31 からの移行方針

### 15.1 廃止または縮退対象

以下の前提は撤回する。

- 「各サブターンが直接 notebook に書く」
- 「先行サブターン結果を自然言語要約だけで次に渡す」
- 「独立 CLI でも notebook 対象を暗黙共有できる」

### 15.2 当面の運用

当面は、引継ぎメモの結論どおり、**段階的 `ClaudeContinueTurn` 方式**を実用路線とする。fileciteturn9file0

ただし、その前段に以下を追加できる。

- Planner で分解
- Explore / Plan / Verify worker で並列 artifact 収集
- 親 runtime または single committer が `ClaudeContinueTurn` を用いて順次 notebook へ反映

この折衷案により、分解の利点を保ちつつ、notebook 共有問題を回避できる。

---

## 16. 導入順序

### Stage 1
Parallel Research Only を導入する。

- Planner
- Explore worker
- Plan worker
- Verify worker
- Artifact collection
- notebook 書き込みは従来どおり親 runtime

### Stage 2
Reducer を導入する。

- 複数 artifact を統合
- schema 検証
- 決定的 reduction

### Stage 3
Single Committer を導入する。

- target notebook 固定
- notebook 書き込みを committer へ一本化

### Stage 4
必要であれば shadow notebook / buffer ベースの段階的反映を検討する。

---

## 17. 提案 API

- `ClaudePlanTasks[input_, opts___]`
- `ClaudeSpawnWorkers[taskDag_, opts___]`
- `ClaudeCollectArtifacts[jobId_, opts___]`
- `ClaudeReduceArtifacts[artifacts_, opts___]`
- `ClaudeCommitArtifacts[targetNotebook_, reducedArtifact_, opts___]`
- `ClaudeRunOrchestration[input_, opts___]`

### 17.1 折衷案 API

- `ClaudeContinueBatch[rid_, batchInstructions_List, opts___]`

これは、当面の実用路線として、1つのセッションを維持したまま段階的に続きを書かせるための helper とする。

---

## 18. 成功条件

本仕様の導入が成功したとみなす条件は以下。

1. planner が Task DAG を安定生成できる
2. worker が schema 準拠 artifact を返せる
3. worker は notebook mutation を一切行わない
4. reducer が artifact を整合的に統合できる
5. committer だけが target notebook に書き込む
6. 分解ありでも、最終成果物が現在 notebook に確実に反映される
7. `ClaudeTestKit` の orchestrator 系テストが安定して通る

---

## 19. 要約

本仕様の核心は次の 3 点である。

1. **複数 worker は artifact producer に限定する**
2. **notebook を触るのは single committer だけにする**
3. **ClaudeRuntime 自体は単一エージェント核のまま保つ**

これにより、既存の Phase 31 で露呈した notebook 共有・副作用・状態共有の問題を回避しつつ、分解・並列化・集約の利点を導入できる。
