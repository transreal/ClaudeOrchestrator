# ClaudeOrchestrator / ClaudeRuntime / StateGraph 統合仕様書

## 0. 文書の目的

本書は、現在進行中の Mathematica–Claude Code ブリッジシステムの設計変更について、背景・設計意図・責務分担・移行手順を整理した仕様書である。

対象となる主なモジュールは以下である。

- `claudecode.wl`
- `ClaudeRuntime.wl`
- `ClaudeRuntime_stategraph.wl`
- `ClaudeOrchestrator.wl`
- `ClaudePackageManager.wl`
- `NBAccess.wl`
- `LLMGraph`

中心的な設計判断は、現在 `ClaudeRuntime_stategraph.wl` として並立的に進められている stategraph / Petri-net-like な実装を、長期的には `ClaudeOrchestrator.wl` 側の workflow engine として統合し、`ClaudeRuntime.wl` は DAG execution / transition executor として純化する、というものである。

---

# 1. 背景

## 1.1 現在のシステム構成

現在の Mathematica–Claude Code ブリッジシステムでは、`ClaudeEval` を中心に、ノートブック上から Claude Code CLI、Anthropic API、OpenAI API、LMStudio などの LLM 呼び出しを行う構造が形成されている。

既存構成では、概念的に次のような層が存在する。

```text
claudecode.wl
    UI / legacy API / ClaudeEval front-end

ClaudeRuntime.wl
    Expression-Proposal loop / single-agent runtime

ClaudeOrchestrator.wl
    planner / worker / reducer / committer / multi-agent orchestration

NBAccess.wl
    notebook authority / cell access / credential access / privacy control

LLMGraph
    LLM 呼び出し履歴・依存関係・snapshot / restore の基盤
```

これに加えて、現在は `ClaudeRuntime_stategraph.wl` が並立的に実装されている。

これは、Runtime の内部に stategraph 的、あるいは Petri net 的な状態遷移モデルを導入しようとする試みであると解釈できる。

---

## 1.2 なぜ問題になるのか

現在の設計では、次の三者がそれぞれ workflow state を持ちうる。

```text
ClaudeRuntime.wl
    proposal loop / continuation / approval / dispatch state

ClaudeRuntime_stategraph.wl
    stategraph / transition / token-like state

ClaudeOrchestrator.wl
    task DAG / worker / reducer / committer / retry state
```

このまま進めると、以下の問題が生じる。

1. workflow state の所有者が曖昧になる。
2. retry / repair / approval / pause / resume の責務が Runtime と Orchestrator に分散する。
3. `ClaudeRuntime_stategraph.wl` が Runtime の一部なのか、Orchestrator の原型なのか不明確になる。
4. LLMGraph との永続化境界が曖昧になる。
5. Package maintenance workflow をどの層で扱うべきか不明確になる。

したがって、DAG ベースの実行系と Petri net 的な orchestration layer の界面を明確化する必要がある。

---

# 2. 基本設計判断

## 2.1 採用する基本構造

本仕様では、次の二層構造を採用する。

```text
Petri Net orchestration + DAG execution
```

すなわち、

```text
上位層:
    Petri net / stategraph 的 workflow orchestration

下位層:
    DAG ベースの deterministic / semi-deterministic execution
```

である。

---

## 2.2 モジュール対応

この二層構造を既存モジュールに対応させると、次のようになる。

| 概念層 | 実装モジュール | 主な責務 |
|---|---|---|
| Petri net orchestration layer | `ClaudeOrchestrator.wl` | workflow state, token, worker, retry, approval, restore |
| DAG execution layer | `ClaudeRuntime.wl` | BuildContext, QueryProvider, ParseProposal, ValidateProposal, DispatchDecision |
| domain service | `ClaudePackageManager.wl` | package file discovery, diff, patch, refresh, test support |
| notebook authority | `NBAccess.wl` | notebook access, credential access, privacy / IFC enforcement |
| compatibility / UI facade | `claudecode.wl` | ClaudeEval UI, legacy API, front-end integration |
| persistence / trace | `LLMGraph` | runtime graph, workflow trace, snapshot / restore |

---

## 2.3 結論

`ClaudeRuntime_stategraph.wl` は、長期的には `ClaudeRuntime.wl` の一部として育てるのではなく、`ClaudeOrchestrator.wl` の workflow engine として吸収・統合するべきである。

より正確には、次の再解釈を行う。

```text
ClaudeRuntime_stategraph.wl
    = Runtime の拡張ではなく、
      Orchestrator workflow engine の原型
```

したがって、最終的な方向性は次である。

```text
ClaudeRuntime_stategraph.wl
    ↓
ClaudeOrchestrator の WorkflowNet / StateGraph / PetriNet engine へ昇格

ClaudeRuntime.wl
    ↓
Workflow transition を実行する DAG executor として純化
```

---

# 3. DAG と Petri net の役割分担

## 3.1 DAG execution が担当するもの

DAG は、依存関係が明確で、基本的に非循環な計算に向いている。

担当すべき処理は次である。

- prompt construction
- context assembly
- expression parsing
- validation pipeline
- symbolic transformation
- deterministic notebook inspection
- LLM provider invocation pipeline
- output normalization
- redaction
- small-scale parallel map / reduce

例：`ClaudeRuntime` の Expression-Proposal loop。

```text
BuildContext
    ↓
QueryProvider
    ↓
ParseProposal
    ↓
ValidateProposal
    ↓
DispatchDecision
    ↓
RedactResult
```

これは DAG execution として自然である。

---

## 3.2 Petri net orchestration が担当するもの

Petri net / stategraph は、状態遷移・並行性・待機・復元に向いている。

担当すべき処理は次である。

- task token management
- worker token management
- retry / repair loop
- human approval wait
- pause / resume
- long-running workflow
- multi-worker scheduling
- artifact collection
- reducer / verifier / committer coordination
- package update transaction
- privacy-aware routing
- workflow snapshot / restore

例：multi-agent package update workflow。

```text
[PackageUpdateRequested]
      ↓
(InspectPackage)
      ↓
[PackageSnapshotReady]
      ↓
(ProposePatch)
      ↓
[PatchProposalReady]
      ↓
(ValidatePatch)
      ↓
[PatchApproved]
      ↓
(ApplyPatch)
      ↓
[PackagePatched]
      ↓
(ReloadAndTest)
      ↓
[TestsPassed]
      ↓
(PrepareCommit)
      ↓
[CommitReady]
```

---

# 4. ClaudeOrchestrator の仕様

## 4.1 位置づけ

`ClaudeOrchestrator.wl` は、Petri-net-like workflow engine を所有する。

これは以下を管理する。

```text
Place
Transition
Token
Worker token
Artifact token
Approval token
Retry state
Failure state
Snapshot state
```

---

## 4.2 Orchestrator の責務

`ClaudeOrchestrator` の責務は次である。

1. 親タスクを workflow に変換する。
2. 必要に応じて planner を呼ぶ。
3. task token を発行する。
4. worker registry を参照して worker token を割り当てる。
5. transition firing 条件を判定する。
6. `ClaudeRuntime` を transition executor として呼ぶ。
7. 成果物 artifact を収集する。
8. reducer / verifier / committer を起動する。
9. retry / repair / approval / pause / resume を管理する。
10. workflow snapshot を保存・復元する。

---

## 4.3 Orchestrator が持つべき抽象型

### WorkflowNet

```wl
<|
  "WorkflowId" -> workflowId,
  "Places" -> <| ... |>,
  "Transitions" -> <| ... |>,
  "Tokens" -> <| ... |>,
  "Workers" -> <| ... |>,
  "Artifacts" -> <| ... |>,
  "Policy" -> <| ... |>,
  "Trace" -> {...}
|>
```

### Place

```wl
<|
  "Name" -> "TaskReady",
  "TokenIds" -> {...},
  "Capacity" -> Infinity,
  "Visibility" -> "Internal" | "UserVisible"
|>
```

### Transition

```wl
<|
  "Name" -> "RunWorker",
  "InputPlaces" -> {"TaskReady", "WorkerIdle"},
  "OutputPlaces" -> {"ArtifactReady", "WorkerIdle"},
  "Guard" -> guardFunction,
  "Executor" -> "ClaudeRuntime" | "PackageManager" | "PureFunction",
  "RuntimeSpec" -> <| ... |>,
  "RetryPolicy" -> <| ... |>,
  "AccessPolicy" -> <| ... |>
|>
```

### Token

```wl
<|
  "TokenId" -> tokenId,
  "Kind" -> "Task" | "Worker" | "Artifact" | "Approval" | "PackageTransaction",
  "Payload" -> <| ... |>,
  "PrivacyLabel" -> 0.0,
  "Status" -> "Ready" | "Running" | "Waiting" | "Failed" | "Done",
  "Trace" -> {...}
|>
```

---

## 4.4 Orchestrator API 案

```wl
ClaudeCreateWorkflowNet[workflowSpec_, opts___]
ClaudeSubmitToken[workflow_, token_, opts___]
ClaudeEnabledTransitions[workflow_, opts___]
ClaudeFireTransition[workflow_, transitionId_, opts___]
ClaudeStepWorkflow[workflow_, opts___]
ClaudeRunWorkflow[workflow_, opts___]
ClaudePauseWorkflow[workflowId_]
ClaudeResumeWorkflow[workflowId_]
ClaudeSnapshotWorkflow[workflowId_]
ClaudeRestoreWorkflow[snapshot_]
ClaudeWorkflowTrace[workflowId_]
```

---

# 5. ClaudeRuntime の仕様

## 5.1 位置づけ

`ClaudeRuntime.wl` は、Orchestrator の transition から呼び出される DAG execution engine である。

Runtime は workflow 全体の状態を持たない。

Runtime が扱うのは、原則として次の単位である。

```text
1 transition input
    →
1 transition result packet
```

---

## 5.2 Runtime の責務

`ClaudeRuntime` の責務は次である。

- BuildContext
- QueryProvider
- ParseProposal
- ValidateProposal
- DispatchDecision
- ExecuteProposal
- RedactResult
- NormalizeResult
- ReturnDiagnostics

ただし、以下は Runtime の責務ではない。

- multi-worker scheduling
- long-running workflow state
- retry policy ownership
- global approval wait management
- notebook write commit ordering
- package update transaction ownership
- workflow snapshot / restore ownership

---

## 5.3 Runtime transition executor API

```wl
ClaudeRuntimeExecuteTransition[runtime_, transitionInput_, opts___]
```

### 入力例

```wl
<|
  "WorkflowId" -> wid,
  "TokenId" -> tid,
  "TransitionId" -> "RunWorker",
  "Role" -> "Explore",
  "ContextPacket" -> contextPacket,
  "AllowedCapabilities" -> {"ReadNotebook", "ReadPackageFile"},
  "ExpectedArtifactType" -> "PatchProposal",
  "OutputSchema" -> schema,
  "RuntimeOptions" -> <| ... |>
|>
```

### 出力例

```wl
<|
  "TokenId" -> tid,
  "Status" -> "Success" | "Failed" | "NeedsApproval" | "NeedsRepair",
  "ProducedTokens" -> {...},
  "Artifact" -> artifact,
  "Decision" -> decision,
  "Trace" -> trace,
  "Diagnostics" -> diagnostics
|>
```

---

# 6. ClaudeRuntime_stategraph.wl の扱い

## 6.1 推奨方針

`ClaudeRuntime_stategraph.wl` は、長期的には独立した主要実装として残さない。

ただし、すぐに削除せず、段階的に `ClaudeOrchestrator.wl` に吸収する。

---

## 6.2 移行段階

### Stage 0: 現状維持

`ClaudeRuntime_stategraph.wl` は実験実装として残す。

目的：

- state / transition / token の実験
- snapshot / restore の実験
- Runtime loop の状態遷移化の検証

---

### Stage 1: 抽象の抽出

`ClaudeRuntime_stategraph.wl` から以下を抽出する。

```text
state definitions
transition definitions
token-like associations
guard functions
retry / failure handling
snapshot / restore logic
worker routing logic
Runtime invocation points
```

---

### Stage 2: Orchestrator WorkflowNet へ移植

抽出した stategraph 抽象を、`ClaudeOrchestrator.wl` の `WorkflowNet` 実装へ移す。

この段階で、`ClaudeRuntime_stategraph.wl` は Orchestrator の wrapper に近づく。

---

### Stage 3: Runtime の純化

`ClaudeRuntime.wl` から workflow state の所有を減らす。

Runtime は transition executor として、入力 packet を受け取り、結果 packet を返すことに集中する。

---

### Stage 4: 互換 layer 化

最終的に `ClaudeRuntime_stategraph.wl` は次のような compatibility shim にする。

```wl
(* deprecated compatibility layer *)

Needs["ClaudeOrchestrator`"]

ClaudeRuntimeStateGraphRun[args___] :=
  ClaudeOrchestrator`ClaudeRunWorkflow[
    ClaudeOrchestrator`ClaudeCreateWorkflowNet[args]
  ]
```

---

### Stage 5: 廃止または thin wrapper 化

十分にテストが安定した段階で、`ClaudeRuntime_stategraph.wl` は deprecated とし、将来的に削除または thin wrapper として維持する。

---

# 7. ClaudePackageManager の仕様

## 7.1 位置づけ

`ClaudePackageManager.wl` は Orchestrator でも Runtime でもない。

これは package file maintenance のための domain service である。

---

## 7.2 ClaudePackageManager の責務

担当する処理は次である。

- package file discovery
- package source refresh
- dependency scan
- diff generation
- patch application
- reload support
- test support
- commit preparation
- package metadata inspection

---

## 7.3 ClaudePackageManager が持つべきでない責務

以下は持たせない。

- multi-agent orchestration
- worker scheduling
- retry / approval workflow
- LLM provider selection
- global privacy routing
- notebook mutation policy
- workflow snapshot / restore

---

## 7.4 API 案

```wl
ClaudePackageManagerInspect[packageSpec_, opts___]
ClaudePackageManagerRefresh[packageSpec_, opts___]
ClaudePackageManagerDiff[packageSpec_, opts___]
ClaudePackageManagerApplyPatch[packageSpec_, patch_, opts___]
ClaudePackageManagerReload[packageSpec_, opts___]
ClaudePackageManagerRunTests[packageSpec_, opts___]
ClaudePackageManagerPrepareCommit[packageSpec_, opts___]
```

---

# 8. claudecode.wl の縮退方針

## 8.1 現在の役割

`claudecode.wl` は、現在多くの責務を持っている。

- `ClaudeEval` UI
- CLI 呼び出し
- notebook 操作
- package maintenance
- LLM 呼び出し
- continuation
- palette integration

---

## 8.2 将来の役割

将来的には、`claudecode.wl` は次に限定する。

```text
UI facade
legacy API compatibility
ClaudeEval front-end
palette integration
user-facing convenience wrapper
```

具体的には、`claudecode.wl` は以下へ委譲する。

| 処理 | 委譲先 |
|---|---|
| Runtime execution | `ClaudeRuntime.wl` |
| workflow orchestration | `ClaudeOrchestrator.wl` |
| package file maintenance | `ClaudePackageManager.wl` |
| notebook access | `NBAccess.wl` |
| persistent execution graph | `LLMGraph` |

---

# 9. NotebookWrite / Committer 原則

## 9.1 原則

multi-worker workflow では、worker は原則として notebook を直接変更しない。

notebook mutation は single committer のみに許す。

---

## 9.2 worker capability policy

```text
Explore worker:
    NotebookWrite 禁止

Plan worker:
    NotebookWrite 禁止

Draft worker:
    NotebookWrite 禁止

Verify worker:
    NotebookWrite 禁止

Reducer:
    NotebookWrite 禁止

Committer:
    NotebookWrite 許可
```

---

## 9.3 Petri net 表現

```text
[ReducedArtifactReady]
        ↓
(CommitToNotebook)
        ↓
[NotebookUpdated]
```

この `CommitToNotebook` transition のみが notebook mutation capability を持つ。

---

# 10. 単純並列処理の扱い

## 10.1 原則

単純・同型・短時間・独立な並列処理は、Petri net layer ではなく DAG execution layer で扱う。

例：ノートブックの全セルのテキスト抽出。

---

## 10.2 Petri net 側

Petri net 側では coarse-grained な transition として表す。

```text
[NotebookSnapshotReady]
      ↓
(ExtractAllCellTexts)
      ↓
[CellTextsReady]
```

---

## 10.3 DAG 側

transition の内部で、DAG / parallel map として処理する。

```text
ListCells
   ↓
ExtractText /@ cells
   ↓
MergeTexts
```

---

## 10.4 判断基準

| 処理 | 担当 layer |
|---|---|
| セルごとの独立テキスト抽出 | DAG execution |
| ファイル一覧の map | DAG execution |
| prompt fragment assembly | DAG execution |
| worker ごとの長時間 LLM 呼び出し | Petri net orchestration |
| approval wait | Petri net orchestration |
| retry / repair loop | Petri net orchestration |
| package update transaction | Petri net orchestration |
| final notebook commit | Petri net orchestration |

---

# 11. Privacy / IFC との統合

## 11.1 Colored token と privacy label

Petri net token は privacy label を持つ。

```wl
<|
  "TokenId" -> tid,
  "Payload" -> payload,
  "PrivacyLabel" -> 0.7
|>
```

---

## 11.2 transition firing guard

transition firing では、worker clearance と token label を比較する。

```text
worker.clearance >= token.privacyLabel
```

または、将来的に半順序ラベルを導入する場合は、次のような関係に置き換える。

```text
token.label ⊑ worker.clearance
```

---

## 11.3 NBAccess の役割

`NBAccess.wl` は以下を管理する。

- notebook cell access
- credential access
- privacy label inference
- access approval
- forbidden head / approval head validation
- confidential output propagation

Orchestrator は NBAccess の判断を用いて routing する。

Runtime は NBAccess の判断を用いて validation / dispatch を行う。

---

# 12. 依存関係ルール

## 12.1 許可される依存

```text
claudecode.wl → ClaudeOrchestrator.wl
claudecode.wl → ClaudeRuntime.wl
claudecode.wl → ClaudePackageManager.wl
claudecode.wl → NBAccess.wl

ClaudeOrchestrator.wl → ClaudeRuntime.wl
ClaudeOrchestrator.wl → ClaudePackageManager.wl
ClaudeOrchestrator.wl → NBAccess.wl
ClaudeOrchestrator.wl → LLMGraph

ClaudeRuntime.wl → NBAccess.wl
ClaudeRuntime.wl → ClaudeCodeBase / claudecode_base.wl
ClaudeRuntime.wl → LLMGraph

ClaudePackageManager.wl → NBAccess.wl
```

---

## 12.2 禁止される依存

```text
ClaudeRuntime.wl → claudecode.wl
ClaudeRuntime.wl → ClaudeOrchestrator.wl
ClaudePackageManager.wl → ClaudeOrchestrator.wl
ClaudePackageManager.wl → claudecode.wl
NBAccess.wl → ClaudeRuntime.wl
NBAccess.wl → ClaudeOrchestrator.wl
claudecode.wl → ClaudeRuntime`Private` symbols
claudecode.wl → ClaudeOrchestrator`Private` symbols
```

---

# 13. LLMGraph の位置づけ

## 13.1 LLMGraph は永続化・履歴基盤

`LLMGraph` は次を保持する。

- Runtime DAG trace
- workflow transition trace
- token state snapshot
- artifact references
- notebook history references
- failed / paused / completed node state
- replay / restore metadata

---

## 13.2 Petri net state + DAG snapshot

最終的に、`LLMGraph` は次の合成体になる。

```text
LLMGraph
    =
Petri net workflow state
    +
Runtime DAG execution snapshots
    +
notebook history linkage
```

---

# 14. Package update workflow 仕様

## 14.1 workflow 全体

```text
[PackageUpdateRequested]
      ↓
(InspectPackage)
      ↓
[PackageSnapshotReady]
      ↓
(ProposePatch)
      ↓
[PatchProposalReady]
      ↓
(ValidatePatch)
      ↓
 ┌───────────────┐
 ↓               ↓
[PatchApproved] [NeedsRepair]
 ↓               ↓
(ApplyPatch)    (RepairPatch)
 ↓               ↓
[PackagePatched]←┘
      ↓
(ReloadAndTest)
      ↓
 ┌───────────────┐
 ↓               ↓
[TestsPassed] [TestsFailed]
 ↓               ↓
(PrepareCommit) (RepairPatch)
 ↓
[CommitReady]
```

---

## 14.2 各 transition の担当

| Transition | 主担当 |
|---|---|
| InspectPackage | `ClaudePackageManager` |
| ProposePatch | `ClaudeRuntime` |
| ValidatePatch | `ClaudeRuntime` + `NBAccess` |
| RepairPatch | `ClaudeRuntime` |
| ApplyPatch | `ClaudePackageManager` |
| ReloadAndTest | `ClaudePackageManager` |
| PrepareCommit | `ClaudePackageManager` |
| CommitToNotebook / CommitToFiles | `ClaudeOrchestrator` 管理下の committer |

---

# 15. 移行計画

## Phase 1: 現状コードの分類

`ClaudeRuntime_stategraph.wl` の内容を以下に分類する。

```text
A. Orchestrator に移すもの
B. Runtime に残すもの
C. ClaudePackageManager に移すもの
D. ClaudeCodeBase に落とすもの
E. 削除するもの
```

---

## Phase 2: Orchestrator WorkflowNet core の追加

`ClaudeOrchestrator.wl` に次を追加する。

```wl
ClaudeCreateWorkflowNet
ClaudeStepWorkflow
ClaudeRunWorkflow
ClaudeSnapshotWorkflow
ClaudeRestoreWorkflow
```

この段階では mock transition でよい。

---

## Phase 3: Runtime transition executor の導入

`ClaudeRuntime.wl` に次を導入する。

```wl
ClaudeRuntimeExecuteTransition
```

既存の Expression-Proposal loop をこの API の内部 DAG として呼び出す。

---

## Phase 4: PackageManager workflow の接続

package update workflow を Orchestrator の WorkflowNet として定義する。

file maintenance 操作は `ClaudePackageManager` に委譲する。

---

## Phase 5: StateGraph wrapper 化

`ClaudeRuntime_stategraph.wl` を Orchestrator wrapper にする。

---

## Phase 6: Deprecated 化

十分なテスト後、`ClaudeRuntime_stategraph.wl` を deprecated とする。

---

# 16. テスト方針

## 16.1 Unit tests

- WorkflowNet creation
- token submission
- enabled transition detection
- guard evaluation
- transition firing
- retry policy
- snapshot / restore

---

## 16.2 Runtime tests

- transition input validation
- BuildContext DAG
- QueryProvider mock
- ParseProposal
- ValidateProposal
- DispatchDecision
- redaction
- result packet schema

---

## 16.3 Integration tests

- single `ClaudeEval`
- `ContinueEval[]`
- package update workflow
- failed patch repair
- approval wait
- notebook commit by single committer
- workflow restore after interruption

---

## 16.4 Safety tests

- worker cannot write notebook
- committer can write notebook
- secret token cannot route to cloud worker
- denied head is blocked
- approval head requests approval
- confidential-derived output is marked confidential

---

# 17. 受け入れ条件

## 17.1 構造条件

```text
ClaudeOrchestrator が workflow state を所有する
ClaudeRuntime は transition executor として機能する
ClaudeRuntime_stategraph.wl に主要 workflow logic が残っていない
ClaudePackageManager は orchestration を持たない
claudecode.wl は UI / facade / legacy compatibility に縮退している
```

---

## 17.2 依存条件

```text
ClaudeRuntime → claudecode.wl 依存なし
ClaudeRuntime → ClaudeOrchestrator 依存なし
ClaudeOrchestrator → ClaudeRuntime は許可
ClaudeOrchestrator → ClaudePackageManager は許可
ClaudePackageManager → ClaudeOrchestrator は禁止
NBAccess → Runtime / Orchestrator / PackageManager 依存なし
claudecode.wl → Private symbols 直接アクセスなし
```

---

## 17.3 動作条件

```text
単一 ClaudeEval が従来通り動く
ContinueEval[] が従来通り動く
package update workflow が Orchestrator 経由で動く
worker は notebook に直接書かない
single committer のみ notebook を変更する
workflow snapshot / restore が可能
Runtime trace と Workflow trace が LLMGraph 上で対応づく
```

---

# 18. 最終結論

本仕様変更の本質は、`ClaudeRuntime_stategraph.wl` を Runtime の内部機能として拡張し続けるのではなく、`ClaudeOrchestrator.wl` の workflow engine として昇格させることである。

最終構成は次である。

```text
ClaudeOrchestrator.wl
    Petri-net-like workflow orchestration

ClaudeRuntime.wl
    DAG-based transition execution

ClaudePackageManager.wl
    package maintenance domain service

NBAccess.wl
    notebook / credential / privacy authority

LLMGraph
    workflow state + runtime DAG snapshot + notebook history

claudecode.wl
    UI / facade / compatibility layer
```

この構造により、以下が明確に分離される。

```text
何を、いつ、どの worker で実行するか
    → ClaudeOrchestrator

その処理をどのような DAG として実行するか
    → ClaudeRuntime

package file をどう維持管理するか
    → ClaudePackageManager

notebook や秘密情報にどう安全にアクセスするか
    → NBAccess
```

したがって、今回の仕様変更は、単なるファイル分割ではなく、次の設計原理を実装に反映するものである。

```text
Petri Net orchestration + DAG execution
```

これは、Mathematica notebook 上で動作する iterative-loop LLM agent、multi-worker workflow、privacy-aware execution、package maintenance automation を統合するための基盤となる。
