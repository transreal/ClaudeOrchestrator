# ClaudeOrchestrator

Mathematica / Wolfram Language 向けマルチエージェント・オーケストレーション層パッケージ

[ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) を「単一エージェント実行核」として保持したまま、その上位でタスク分解・並列ワーカー配車・アーティファクト収集・統合・single-committer コミットを提供します。タスク分解の結果は **ペトリネット (Workflow Net)** として表現・実行でき、自然文プロンプトから直接ペトリネットを構築して可視化・追跡する拡張、`ClaudeEval` の複雑プロンプトを WorkflowNet として再実行する **PromptWorkflow** 拡張を同梱します。

> このリポジトリのドキュメントは、概要を示す **本 README**、詳細な使い方の **`user_manual.md`**、全関数仕様の **`api*.md`**、動くコード例の **`example.md`** に役割分担しています。本 README は全体像と最小の動作確認までを扱い、各機能の網羅的な解説や全 API は `user_manual.md` と `api*.md` を参照してください。

## 設計思想

### なぜこの設計が必要か

以前の設計では、サブターンを独立した CLI プロセスとして起動し、それぞれに Mathematica ノートブックへの直接書き込みを期待していました。しかしこの方式では、サブターン間で変数が共有されない、`EvaluationNotebook[]` が現在のノートブックを安定に指さない、`CreateNotebook[...]` による意図しない新規作成が起きる、ツール呼び出しタグとプロポーザルが混線する、先行サブターンの結果が空や `Null` になり依存解決に失敗する、といった根本的な問題が生じました。

この教訓から、**並列ワーカーに live ノートブックへの直接副作用を持たせない**という原則が確立されました。

### 設計上の不変条件

1. **ClaudeRuntime は単一エージェントカーネルのまま維持する** — オーケストレーション層はその外側に置く
2. **並列ワーカーはアーティファクト生成のみ** — `NotebookWrite` の直接呼び出しは禁止
3. **実ノートブックへの書き込みは single committer のみ** — 書き込み競合を根本から排除する
4. **ワーカー間共有状態は明示的な Association / JSON / アーティファクトのみ** — 暗黙的な変数共有を行わない
5. **`EvaluationNotebook[]` / `CreateNotebook[...]` は worker 内で deny** — committer だけが制御された方法でノートブックを操作する

### アーキテクチャと 4 フェーズ

```
NBAccess → claudecode_base → ClaudeRuntime (単一エージェント実行核)
                                   ↑
                            ClaudeOrchestrator (本パッケージ)
                              ├─ Workflow        (multi-token Petri net エンジン)
                              ├─ Observability   (LLM/Handler 観測・Tooltip 可視化)
                              └─ PromptWorkflow   (ClaudeEval 複雑プロンプト → workflow)
                                   ↑
                              claudecode
```

パイプラインは **Planning → Spawn → Reduce → Commit** の 4 フェーズで構成されます。

- **Planning** — `ClaudePlanTasks` が親タスクを TaskSpec の DAG に分解する。モックプランナーのほか、`Planner -> "LLM"` で実 LLM にも分解を依頼できる。
- **Spawn** — `ClaudeSpawnWorkers` が依存順に worker を起動しアーティファクトを収集する。worker は `$ClaudeOrchestratorDenyHeads` の危険操作を提案できない。
- **Reduce** — `ClaudeReduceArtifacts` が複数アーティファクトを統合する。
- **Commit** — `ClaudeCommitArtifacts` が single committer でターゲットノートブックに反映する。`CommitMode -> "Transactional"` でシャドーバッファ経由の安全なコミットも可能。

各フェーズ・各関数の引数とオプションは `user_manual.md` と `api.md` を参照してください。

## モジュール構成と自動ロード

`ClaudeOrchestrator.wl` のロードは、**本体にインライン統合された旧サブモジュール**と、**自動ロードされる 3 つの外部サブモジュール**の二層に整理されています。

**本体にインライン統合済み (Phase 36, 2026-04-28 以降)** — 別ファイルのロード不要。`Get["ClaudeOrchestrator.wl"]` ひとつで利用できます。

- 旧 `ClaudeOrchestratorDirectives` (ディレクティブ管理: Role / Capability / 禁止 Head) — `$DirectivesVersion`
- 旧 `ClaudeOrchestratorRouting` (ローカル LLM 名・モデル名のルーティング) — `$RoutingVersion`
- 旧 `claudecode_commit_safety.wl` (コミット前後の整合性チェック) — `$ClaudeCommitSafetyVersion`
- 旧 `claudecode_a4_stub.wl` / `ClaudeOrchestratorA4` (A4 フェーズ用フック群) — `$A4StubVersion`

**自動ロードされる外部サブモジュール (3 ファイル)** — `ClaudeOrchestrator.wl` のロード時に同一コンテキストへ取り込まれ、外から見ると単一パッケージのように扱えます。

| ファイル | 役割 | API リファレンス |
|---|---|---|
| [`ClaudeOrchestrator_workflow.wl`](https://github.com/transreal/ClaudeOrchestrator_workflow) | multi-token Petri net 実行エンジン (`ClaudeOrchestrator`Workflow`` 名前空間) | `api_workflow.md` |
| [`ClaudeOrchestrator_observability.wl`](https://github.com/transreal/ClaudeOrchestrator_observability) | LLM 呼び出し・transition handler のログ／Tooltip 付き可視化 (ChatGPT Codex を含む複数プロバイダの provenance 記録対応) | `api_observability.md` |
| [`ClaudeOrchestrator_promptworkflow.wl`](https://github.com/transreal/ClaudeOrchestrator_promptworkflow) | `ClaudeEval` の複雑プロンプトを WorkflowNet として再実行する経路 | `api_promptworkflow.md` |

自動ロードは存在チェック + 重複ロード回避を行うため、`ClaudeOrchestrator.wl` を 2 回 `Get` しても副作用はありません。手動ロード防止フラグ (例: `Global`$ClaudeOrchestratorDisablePromptWorkflowAutoLoad = True`) で個別に無効化できます。

なお、自然文プロンプトから WorkflowNet を生成するサンプル兼ライブラリ `docs/examples/petri_from_prompt.wl` がリポジトリに同梱されていますが、**これは example 段階の参考実装で本体には統合されておらず、自動ロードもされません**。試す場合は本体ロード後に別途 `Get` してください。

## 3 つの拡張の概要

### ペトリネット拡張 (Workflow)

DAG に閉じない並行・同期・選択を含むワークフローを **place / transition / arc / token / marking** の Petri net 用語のまま記述・実行できる multi-token Petri net エンジンです。`WorkflowToken` / `WorkflowPlace` / `WorkflowTransition` / `WorkflowNet` で net を組み、`ClaudeCreateWorkflowNet` で登録、`ClaudeSubmitToken` で投入、`ClaudeRunWorkflow` で実行します(`"Async" -> True` で非同期実行)。状態参照 (`ClaudeWorkflowState` 等)、ライフサイクル制御 (`ClaudePause/Resume/CancelWorkflow`)、Completion Hook、Snapshot / Restore を備えます。全 API は `api_workflow.md`、使い方は `user_manual.md` のペトリネット拡張節を参照。

### 観測 (Observability)

LLM 呼び出しログ (`ClaudeQueryBgLogged` / `showLLMCallLog`)、handler 観測 (`instrumentNetForObservation`)、Tooltip 付き可視化 (`plotPetriNetDetail`)、実行追跡 (`traceTransitions`) を提供します。ChatGPT Codex など Claude 以外のプロバイダの呼び出しも `ProviderKind` / `ProviderDisplayName` 付きで `$LLMCallLog` に記録され、混在運用のトレースが容易です。全 API は `api_observability.md`。

### PromptWorkflow

`ClaudeEval` に与えられた複雑プロンプト(複数サブタスクや順序制御を含むもの)を WorkflowNet として再実行する経路です。`ClaudeWorkflowComplexPromptQ` で複雑性を決定的に判定し(秘密プロンプトを外部送信しない)、`ClaudeProposeWorkflowNetFromPrompt` で提案、安全パーサ `ClaudeParseWorkflowNetCode`(評価せず静的検査 → HoldComplete パース → ホワイトリスト評価)を通します。新規ワークフローは常に `NeedsApproval` で停止し、自動実行はしません。全 API は `api_promptworkflow.md`。

## 動作環境

| 項目 | 最低バージョン |
|------|--------------|
| Mathematica / Wolfram Engine | 13.3 以上 |
| Claude CLI (`claude.cmd`) | 最新版(Anthropic 公式) |
| ClaudeRuntime パッケージ | 同梱または別途取得 |
| ClaudeCode パッケージ | 同梱または別途取得 |

> 動作検証は Windows 11 上で行っています。macOS・Linux での動作は未検証です(生成 AI の処理で対応可能と想定されます)。詳細な環境構築・トラブルシューティングは `setup.md` を参照。

## インストール

1. **Claude CLI** を [Anthropic 公式ドキュメント](https://docs.anthropic.com/ja/docs/claude-code/setup) に従いインストールし、`claude --version` が通る(PATH が通った)状態にする。

2. **パッケージの取得** — [github](https://github.com/transreal/github) パッケージがあれば直接インストールできます。

```mathematica
Block[{$CharacterEncoding = "UTF-8"}, Needs["GitHub`", "github.wl"]];
GitHubInstallPackage["ClaudeOrchestrator",
  "https://github.com/transreal/ClaudeOrchestrator"]
```

   github パッケージを使わない場合は `git clone https://github.com/transreal/ClaudeOrchestrator`。依存パッケージ([ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) / [claudecode](https://github.com/transreal/claudecode))も同じ `$packageDirectory` 直下に置きます。3 つの外部サブモジュールも同梱・自動ロードされます。

3. **`$Path` の設定** — すべての `.wl` を `$packageDirectory` 直下に置き、サブディレクトリは `$Path` に追加しないでください。

```mathematica
$packageDirectory = "C:\\Users\\YourName\\MyPackages";  (* 実際のパスに変更 *)
If[!MemberQ[$Path, $packageDirectory], AppendTo[$Path, $packageDirectory]];
```

4. **読み込み**

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeOrchestrator`", "ClaudeOrchestrator.wl"]];
```

5. **API キー** — Anthropic API キーを環境変数 `ANTHROPIC_API_KEY` に設定します(PowerShell: `$env:ANTHROPIC_API_KEY = "sk-ant-..."`、または恒久設定としてシステム環境変数に追加)。

## クイックスタート

モックプランナーを使った最小動作の確認:

```mathematica
$ClaudeOrchestratorVersion   (* バージョン確認 *)

(* オーケストレーションは非同期実行に統一されている *)
jobId = ClaudeRunOrchestrationAsync[
  "Mathematica で素数リストを生成して CSV に保存する",
  TargetNotebook -> InputNotebook[], MaxTasks -> 5];
ClaudeOrchestrationWait[jobId, 120];
ClaudeOrchestrationResult[jobId][["Status"]]
(* "Complete" または "Partial" が返れば成功 *)
```

ペトリネット拡張のクイック試用(同梱サンプルをロード):

```mathematica
Get[FileNameJoin[{Quiet @ Check[NotebookDirectory[], $packageDirectory],
  "ClaudeOrchestrator", "docs", "examples", "petri_from_prompt.wl"}]]
```

実 LLM を使う場合は `$ClaudeOrchestratorRealLLMEndpoint` を `"ClaudeCode"` / `"CLI"` / カスタム関数に設定します(環境変数 `CLAUDE_ORCH_REAL_LLM` / `CLAUDE_ORCH_CLI_PATH` でも設定可)。`ClaudeRealLLMAvailable[]` が `True` を返せば構成済みです。さらに踏み込んだ例は `example.md` を参照。

## ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| `README.md` | 本ファイル。全体像・設計思想・インストール・最小動作確認 |
| `user_manual.md` | ユーザーマニュアル。各フェーズ・非同期 API・ペトリネット 3 拡張の詳細な使い方 |
| `api.md` | 本体の API リファレンス(全関数・データ型・グローバル変数) |
| `api_workflow.md` | Workflow サブモジュールの API リファレンス |
| `api_observability.md` | Observability サブモジュールの API リファレンス |
| `api_promptworkflow.md` | PromptWorkflow 拡張の API リファレンス |
| `setup.md` | インストール手順書(動作要件・環境構築・トラブルシューティング) |
| `example.md` | 使用例集(バージョン確認からペトリネット拡張・バッチ処理まで) |
| `docs/examples/petri_from_prompt.wl` | 自然文 → ペトリネット → 実行のエンドツーエンドサンプル |

## 免責事項

本ソフトウェアは "as is"(現状有姿)で提供されており、明示・黙示を問わずいかなる保証もありません。本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。今後の動作保証のための更新が行われるとは限りません。本ソフトウェアとドキュメントはほぼすべてが生成 AI によって生成されたものです。Windows 11 上での実行を想定しており、macOS, Linux の Mathematica での動作検証は一切していません(生成 AI の処理で対応可能と想定されます)。

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
