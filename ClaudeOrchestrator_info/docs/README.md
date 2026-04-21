# ClaudeOrchestrator

Mathematica / Wolfram Language 向けマルチエージェント・オーケストレーション層パッケージ

## 設計思想と実装の概要

ClaudeOrchestrator は、[ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) を「単一エージェント実行核」として保持したまま、その上位レイヤーとして動作するマルチエージェント分解・並列ワーカー配車・アーティファクト収集・統合・コミット機構です。

### なぜこの設計が必要か

以前の設計では、サブターンを独立した CLI プロセスとして起動し、それぞれに Mathematica ノートブックへの直接書き込みを期待していました。しかし、この方式では次のような根本的な問題が生じることが分かりました。

- サブターン間で Mathematica 変数が共有されない
- `EvaluationNotebook[]` が現在のノートブックを安定に指さない
- `CreateNotebook[...]` による意図しない新規ノートブック作成が発生する
- ツール呼び出しタグと Mathematica プロポーザルが混線する
- 先行サブターンの結果が空または `Null` となり、依存解決に失敗する

これらの教訓から、**並列ワーカーに live ノートブックへの直接副作用を持たせる設計は採用しない**という原則が確立されました。

### 設計上の不変条件

1. **ClaudeRuntime は単一エージェントカーネルのまま維持する** — オーケストレーション層は ClaudeRuntime の外側に置く
2. **並列ワーカーはアーティファクト生成のみ** — `NotebookWrite` の直接呼び出しは禁止
3. **実ノートブックへの書き込みは single committer のみ** — 書き込み競合を根本から排除する
4. **ワーカー間共有状態は明示的な Association / JSON / アーティファクトのみ** — 暗黙的な変数共有を行わない
5. **`EvaluationNotebook[]` / `CreateNotebook[...]` は worker 内で deny** — committer だけが制御された方法でノートブックを操作する

### アーキテクチャの全体像

```
NBAccess
  ↑
claudecode_base
  ↑
ClaudeRuntime            ← 単一エージェント実行核
  ↑
ClaudeOrchestrator       ← 本パッケージ
  ↑
claudecode
```

### フェーズ構成

パイプラインは次の 4 フェーズで構成されます。

**Planning フェーズ** では、`ClaudePlanTasks` が親タスクを TaskSpec の DAG（有向非巡回グラフ）に分解します。各 TaskSpec は `TaskId`・`Role`・`Goal`・`Inputs`・`Outputs`・`Capabilities`・`DependsOn`・`ExpectedArtifactType`・`OutputSchema` を持ちます。デフォルトではモックプランナーを使用しますが、実 LLM を呼ぶカスタム関数も渡せます。また `"Planner" -> "LLM"` を指定することで、`$ClaudeOrchestratorRealLLMEndpoint` に設定したエンドポイント経由で実際の LLM にタスク分解を依頼できます。

**Spawn フェーズ** では、`ClaudeSpawnWorkers` がトポロジカルソートした依存順に worker runtime を順次起動し、各タスクのアーティファクトを収集します。worker は `Explore`・`Plan`・`Draft`・`Verify`・`Reduce` のいずれかの Role で動作し、`$ClaudeOrchestratorDenyHeads` に列挙された危険な操作（`NotebookWrite`・`RunProcess`・`SystemCredential` など）を提案することを禁止されています。

**Reduce フェーズ** では、`ClaudeReduceArtifacts` が複数のアーティファクトを統合し、整合した `ReducedArtifact` を生成します。

**Commit フェーズ** では、`ClaudeCommitArtifacts` が single committer runtime を起動し、`ReducedArtifact` をターゲットノートブックに反映します。スライド生成が検出された場合、ユーザーの作業ノートブックを保護するために `CreateDocument` で新規ノートブックを自動生成してコミット先とします。

### 非同期実行と状態管理

`ClaudeRunOrchestrationAsync` は Planning → Spawn → Reduce → Commit の全フェーズを DAG コールバックチェーンで非同期実行し、呼び出し元をブロックせずに `orchJobId` を即座に返します。`ClaudeOrchestrationStatus`・`ClaudeOrchestrationResult`・`ClaudeOrchestrationWait`・`ClaudeOrchestrationCancel` でジョブのライフサイクルを制御できます。

### Real LLM 統合

`$ClaudeOrchestratorRealLLMEndpoint` を `"ClaudeCode"`（ClaudeCode パッケージ経由）・`"CLI"`（claude CLI を RunProcess で呼ぶ）・カスタム関数のいずれかに設定することで、実際の LLM をプランナーとして利用できます。デフォルト（`None`）はモックのみで動作するため、CI 環境でも安全に使用できます。Windows 環境では `claude.cmd` を自動検出し、UTF-8 の文字化けを防ぐためにファイル経由の stdout 取得方式（`chcp 65001` + リダイレクト）を採用しています。

---

## 詳細説明

### 動作環境

| 項目 | 最低バージョン |
|------|--------------|
| Mathematica / Wolfram Engine | 13.3 以上 |
| Claude CLI (`claude.cmd`) | 最新版（Anthropic 公式） |
| ClaudeRuntime パッケージ | 同梱または別途取得 |
| ClaudeCode パッケージ | 同梱または別途取得 |

> **注意:** 動作検証は Windows 11 上で行っています。macOS・Linux での動作は未検証です（生成 AI の処理で対応可能と想定されます）。

### インストール

#### 1. Claude CLI のインストール

[Anthropic 公式ドキュメント](https://docs.anthropic.com/ja/docs/claude-code/setup) に従い、`claude.cmd` をインストールしてください。インストール後、以下でバージョンを確認します。

```
claude --version
```

PATH が通っている状態（`claude.cmd` がどのディレクトリからも呼べる状態）にしてください。

#### 2. パッケージの取得

```
git clone https://github.com/transreal/ClaudeOrchestrator
```

依存パッケージも同じ `$packageDirectory` に配置します。

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [claudecode](https://github.com/transreal/claudecode)

#### 3. `$Path` の設定

すべての `.wl` ファイルは `$packageDirectory` 直下に置きます。**サブディレクトリを `$Path` に追加しないでください。**

```mathematica
$packageDirectory = "C:\\Users\\YourName\\MyPackages";  (* 実際のパスに変更 *)
If[!MemberQ[$Path, $packageDirectory],
   AppendTo[$Path, $packageDirectory]];
```

`claudecode` パッケージを使用している場合、`$Path` は自動的に設定されます。

#### 4. パッケージの読み込み

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];
```

依存パッケージが自動読み込みされない場合は先に読み込みます。

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeRuntime`",      "ClaudeRuntime.wl"];
  Needs["ClaudeCode`",         "claudecode.wl"];
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];
```

#### 5. API キーの設定

Anthropic API キーは環境変数 `ANTHROPIC_API_KEY` として設定します。

**PowerShell（セッション限定）:**

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

**システム環境変数（恒久設定）:**
「システムの詳細設定」→「環境変数」→「システム環境変数」に `ANTHROPIC_API_KEY` を追加してください。Mathematica を再起動すると反映されます。

---

### クイックスタート

以下のコードで、モックプランナーを使った最小動作を確認できます。

```mathematica
(* 1. パッケージ読み込み *)
$packageDirectory = "C:\\Users\\YourName\\MyPackages";
If[!MemberQ[$Path, $packageDirectory], AppendTo[$Path, $packageDirectory]];

Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeRuntime`",      "ClaudeRuntime.wl"];
  Needs["ClaudeCode`",         "claudecode.wl"];
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];

(* 2. バージョン確認 *)
$ClaudeOrchestratorVersion

(* 3. フルパイプラインの実行（モックプランナー使用） *)
result = ClaudeRunOrchestration[
  "Mathematica で素数リストを生成して CSV に保存する",
  TargetNotebook -> InputNotebook[],
  MaxTasks -> 5
];
result[["Status"]]
(* "Complete" または "Partial" が返れば成功 *)
```

**実 LLM を使う場合の追加設定:**

| 変数 | 既定値 | 説明 |
|------|--------|------|
| `$ClaudeOrchestratorRealLLMEndpoint` | `None` | `"ClaudeCode"` / `"CLI"` / カスタム関数 |
| `$ClaudeOrchestratorCLICommand` | `Automatic` | CLI 実行ファイルのパス（Windows では `claude.cmd`）|
| `$ClaudeOrchestratorAsyncMode` | `True` | `True`: 非同期、`False`: 同期 |

環境変数による設定も可能です。

| 環境変数 | 対応する変数 |
|---------|------------|
| `CLAUDE_ORCH_REAL_LLM` | `$ClaudeOrchestratorRealLLMEndpoint` |
| `CLAUDE_ORCH_CLI_PATH` | `$ClaudeOrchestratorCLICommand` |

```mathematica
(* CLI 経由で実 LLM を使う例 *)
$ClaudeOrchestratorRealLLMEndpoint = "CLI";
ClaudeRealLLMAvailable[]  (* True が返れば OK *)

result = ClaudeRunOrchestration[
  "行列の固有値を求めてレポートを生成する",
  Planner -> "LLM",
  MaxTasks -> 4
];
result[["Status"]]
```

---

### 主な機能

#### タスク計画

- **`ClaudePlanTasks[input, opts]`** — 親タスクを TaskSpec DAG に分解します。`Planner -> Automatic` でモック、`Planner -> "LLM"` で実 LLM を使用します。オプション: `MaxTasks -> 10`。
- **`ClaudeValidateTaskSpec[taskSpec]`** — TaskSpec の妥当性（必須キー・Role の整合性・依存関係）を検証し、`<|"Valid" -> True/False, "Errors" -> {...}|>` を返します。

#### ワーカー実行・アーティファクト収集

- **`ClaudeSpawnWorkers[tasks, opts]`** — 依存順に worker runtime を起動し、各タスクのアーティファクトを収集します。戻り値: `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`。
- **`ClaudeCollectArtifacts[spawnResult]`** — アーティファクト一覧を Dataset として返します。
- **`ClaudeValidateArtifact[artifact, outputSchema]`** — アーティファクトのペイロードが OutputSchema を満たすか検証します。

#### アーティファクト統合・コミット

- **`ClaudeReduceArtifacts[artifacts, opts]`** — 複数アーティファクトを統合し `ReducedArtifact` を返します。`Reducer -> fn` でカスタム統合関数を渡せます。
- **`ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]`** — single committer を起動し、アーティファクトをターゲットノートブックに反映します。`CommitMode -> "Transactional"` でシャドーバッファ経由の安全なコミットが可能です。

#### 一括・非同期実行

- **`ClaudeRunOrchestration[input, opts]`** — Planning → Spawn → Reduce → Commit の全フェーズを同期的に実行します。
- **`ClaudeRunOrchestrationAsync[input, opts]`** — 全フェーズを非同期実行し、`orchJobId` を即座に返します。フロントエンドをブロックしません。
- **`ClaudeOrchestrationStatus[orchJobId]`** — ジョブの現在状態を返します（`"Planning"` / `"Spawning"` / `"Reducing"` / `"Committing"` / `"Done"` / `"Failed"`）。
- **`ClaudeOrchestrationResult[orchJobId]`** — 完了済みジョブの最終結果を返します。
- **`ClaudeOrchestrationWait[orchJobId, timeoutSec]`** — ジョブ完了まで待機します（テスト・スクリプト専用）。
- **`ClaudeOrchestrationCancel[orchJobId]`** — 実行中のジョブを中断します。
- **`ClaudeOrchestrationJobs[]`** — 追跡中のジョブ一覧を Dataset で返します。
- **`ClaudeContinueBatch[runtimeId, batchInstructions, opts]`** — 単一 runtime セッションを維持したまま、複数プロンプトを `ClaudeContinueTurn` で順次投入します。ノートブック共有問題を回避する現実解です。

#### Real LLM 統合・診断

- **`ClaudeRealLLMAvailable[]`** — 実 LLM 統合が設定されているか確認します。
- **`ClaudeRealLLMQuery[prompt]`** — 設定済みエンドポイント経由でプロンプトを実行します。
- **`ClaudeRealLLMDiagnose[prompt]`** — エンドポイント・CLI パス・ExitCode・stdout・JSON パース結果などの診断情報を返します。
- **`ClaudeRealLLMDiagnosePlan[input]`** — 実 LLM プランナーパイプラインを走らせ、結果と診断情報を返します。

#### グローバル定数・変数

- **`$ClaudeOrchestratorVersion`** — パッケージバージョン文字列
- **`$ClaudeOrchestratorRoles`** — 許容 Role のリスト: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`
- **`$ClaudeOrchestratorCapabilities`** — Role → Capability リストの Association
- **`$ClaudeOrchestratorDenyHeads`** — worker が提案を禁止されている head のリスト
- **`$ClaudeOrchestratorRealLLMEndpoint`** — 実 LLM 統合モードの制御（既定: `None`）
- **`$ClaudeOrchestratorCLICommand`** — CLI 実行ファイルのパス（既定: `Automatic`）
- **`$ClaudeOrchestratorAsyncMode`** — 非同期/同期モードの切り替え（既定: `True`）
- **`$ClaudeSlidesTemplatePath`** — スライド生成時の StyleDefinitions テンプレートパス

---

### ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| `api.md` | API リファレンス（全関数・データ型・グローバル変数の仕様） |
| `user_manual.md` | ユーザーマニュアル（各フェーズの詳細な使い方） |
| `setup.md` | インストール手順書（動作要件・環境構築・トラブルシューティング） |
| `example.md` | 使用例集（バージョン確認からバッチ処理まで 11 例） |

---

## 使用例・デモ

### 例 1: タスク分解（モックプランナー）

```mathematica
plan = ClaudePlanTasks["Mathematica で素数リストを生成して CSV に保存する"];
plan["Tasks"][[All, {"TaskId", "Role", "Goal"}]]
```

### 例 2: TaskSpec の検証

```mathematica
spec = <|
  "TaskId" -> "t1", "Role" -> "Draft",
  "Goal" -> "素数リストを生成する",
  "Inputs" -> {}, "Outputs" -> {"primes.csv"},
  "Capabilities" -> {"FileWrite"}, "DependsOn" -> {},
  "ExpectedArtifactType" -> "File", "OutputSchema" -> <||>
|>;
ClaudeValidateTaskSpec[spec]
(* <|"Valid" -> True, "Errors" -> {}|> *)
```

### 例 3: フルパイプライン（同期実行）

```mathematica
result = ClaudeRunOrchestration[
  "フィボナッチ数列を計算して表示する",
  TargetNotebook -> InputNotebook[],
  MaxTasks -> 5
];
result[["Status"]]
(* "Complete" *)
```

### 例 4: 非同期オーケストレーション

```mathematica
(* ジョブを非同期で起動 *)
jobId = ClaudeRunOrchestrationAsync[
  "行列の固有値を求めてレポートを生成する",
  MaxTasks -> 4
];

(* 状態を確認 *)
ClaudeOrchestrationStatus[jobId][["Status"]]
(* "Planning" → ... → "Done" *)

(* 完了を待機してから結果取得 *)
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["SpawnPhase", "Status"]]
(* "Complete" *)
```

### 例 5: バッチ処理（単一セッション継続）

```mathematica
runtime = First @ ClaudeSpawnWorkers[tasks]["Artifacts"];
runtimeId = runtime["RuntimeId"];

results = ClaudeContinueBatch[
  runtimeId,
  {"ステップ 1 を実行", "ステップ 2 を実行", "結果を要約"},
  WaitBetween -> Quantity[2, "Seconds"]
];
results[[All, "Index"]]
(* {1, 2, 3} *)
```

### 例 6: Real LLM 統合の診断

```mathematica
$ClaudeOrchestratorRealLLMEndpoint = "CLI";
ClaudeRealLLMAvailable[]
(* True *)

diag = ClaudeRealLLMDiagnose["Hello, world!"];
diag[["ExitCode"]]
(* 0 *)
```

### 例 7: ジョブ一覧と中断

```mathematica
ClaudeOrchestrationJobs[]
(* Dataset[{<|"JobId"->..., "Status"->"Running", ...|>}] *)

ClaudeOrchestrationCancel[jobId]
(* True *)
```

リポジトリ: [https://github.com/transreal/ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator)

---

## 免責事項

本ソフトウェアは "as is"（現状有姿）で提供されており、明示・黙示を問わずいかなる保証もありません。
本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。
今後の動作保証のための更新が行われるとは限りません。
本ソフトウェアとドキュメントはほぼすべてが生成AIによって生成されたものです。
Windows 11上での実行を想定しており、MacOS, LinuxのMathematicaでの動作検証は一切していません(生成AIの処理で対応可能と想定されます)。

---

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.