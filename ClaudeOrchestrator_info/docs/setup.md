# ClaudeOrchestrator — インストール手順書

macOS/Linux ではパス区切りやシェルコマンドを適宜読み替えてください。

---

## 動作要件

| 項目 | 最低バージョン |
|------|--------------|
| Mathematica / Wolfram Engine | 13.3 以上 |
| Claude CLI (`claude.cmd`) | 最新版（Anthropic 公式） |
| ClaudeRuntime パッケージ | 同梱または別途取得 |
| ClaudeCode パッケージ | 同梱または別途取得（任意・下記参照） |

`ClaudeCode` は Markdown → セル変換（`MarkdownToCells`）を提供しますが、未ロードの場合でも
ClaudeOrchestrator はローカルのフォールバック実装で同等の変換（見出し・コードブロック・
セルスタイルの整形を含む）を行うため、commit safety 系の機能は `ClaudeCode` なしでも動作します。
ただし `ClaudeCode` の高機能な変換ロジックを使うには、依存パッケージとして導入してください。

---

## 外部ツール

### Claude CLI のインストール

[Anthropic 公式ドキュメント](https://docs.anthropic.com/ja/docs/claude-code/setup) に従い、  
`claude.cmd` をインストールしてください。  
インストール後、以下でバージョンを確認します。

```
claude --version
```

PATH が通っている状態（`claude.cmd` がどのディレクトリからも呼べる状態）にしてください。

---

## パッケージの取得

### github パッケージによる簡単インストール

[github](https://github.com/transreal/github) パッケージがインストール済みの場合は、`GitHubInstallPackage` でリポジトリから `$packageDirectory` へ直接インストールできます。

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["GitHub`", "github.wl"]];

GitHubInstallPackage["ClaudeOrchestrator",
  "https://github.com/transreal/ClaudeOrchestrator"]
```

サブモジュール（Directives・Routing・CommitSafety・A4Stub）は PHASE 36（2026-04-28）以降、本体 `ClaudeOrchestrator.wl` に統合されています。別途ファイルを用意する必要はありません。

一方、以下のコンパニオンファイルは本体とは別ファイルのまま、同じディレクトリ（`$packageDirectory`）から**自動ロード**されます（`ClaudeOrchestrator.wl` 末尾の自動ロード機構）。いずれも欠けていても本体は壊れず、該当機能だけが無効化されて読み込みがスキップされます。

- `ClaudeOrchestrator_workflow.wl`（`ClaudeOrchestrator`Workflow` — Petri net workflow engine）
- `ClaudeOrchestrator_observability.wl`（LLM 呼び出しログ / workflow trace 可視化）
- `ClaudeOrchestrator_promptworkflow.wl`（LLM 提案 WorkflowNet コードの安全パーサ）
- `ClaudeOrchestrator_session.wl`（`ClaudeOrchestrator`Session` — RuntimeSession episode 層）
- `ClaudeOrchestrator_turnwiki.wl`（`ClaudeOrchestrator`TurnWiki` — WikiSkill 型 LLM turn 自己改善ループ、2026-09-01 追加）

これらは個別リポジトリとしても取得できます。

```mathematica
GitHubInstallPackage["ClaudeOrchestrator_workflow",
  "https://github.com/transreal/ClaudeOrchestrator_workflow"]
GitHubInstallPackage["ClaudeOrchestrator_observability",
  "https://github.com/transreal/ClaudeOrchestrator_observability"]
GitHubInstallPackage["ClaudeOrchestrator_promptworkflow",
  "https://github.com/transreal/ClaudeOrchestrator_promptworkflow"]
GitHubInstallPackage["ClaudeOrchestrator_session",
  "https://github.com/transreal/ClaudeOrchestrator_session"]
GitHubInstallPackage["ClaudeOrchestrator_turnwiki",
  "https://github.com/transreal/ClaudeOrchestrator_turnwiki"]
```

依存パッケージも同様にインストールできます。

```mathematica
GitHubInstallPackage["ClaudeRuntime",
  "https://github.com/transreal/ClaudeRuntime"]
GitHubInstallPackage["claudecode",
  "https://github.com/transreal/claudecode"]
```

一度インストールしたパッケージは、`GitHubUpdatePackage` でリポジトリの最新版に更新できます。

```mathematica
GitHubUpdatePackage["ClaudeOrchestrator"]
```

### git clone による取得

github パッケージを使わない場合は、`git clone` で取得します。

```
git clone https://github.com/transreal/ClaudeOrchestrator
```

いずれの場合も、依存パッケージおよび上記コンパニオンファイルも同じディレクトリ（`$packageDirectory`）に配置します。

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [claudecode](https://github.com/transreal/claudecode)
- [github](https://github.com/transreal/github)（インストールの簡略化に使用）
- [ClaudeOrchestrator_workflow](https://github.com/transreal/ClaudeOrchestrator_workflow)
- [ClaudeOrchestrator_observability](https://github.com/transreal/ClaudeOrchestrator_observability)
- [ClaudeOrchestrator_promptworkflow](https://github.com/transreal/ClaudeOrchestrator_promptworkflow)
- [ClaudeOrchestrator_session](https://github.com/transreal/ClaudeOrchestrator_session)
- [ClaudeOrchestrator_turnwiki](https://github.com/transreal/ClaudeOrchestrator_turnwiki)

---

## $Path の設定

すべての `.wl` ファイルは `$packageDirectory` 直下に置きます。  
**サブディレクトリを `$Path` に追加しないでください。**

Mathematica ノートブックで以下を一度実行します。

```mathematica
$packageDirectory = "C:\\Users\\YourName\\MyPackages";  (* 実際のパスに変更 *)
If[!MemberQ[$Path, $packageDirectory],
   AppendTo[$Path, $packageDirectory]];
```

`claudecode` パッケージを使用している場合、`$Path` は自動的に設定されます。

---

## パッケージの読み込み

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

`ClaudeOrchestrator.wl` の読み込み中に、上記コンパニオンファイル（`ClaudeOrchestrator_workflow.wl` / `_observability.wl` / `_promptworkflow.wl` / `_session.wl` / `_turnwiki.wl`）が `$packageDirectory` 内に存在すれば自動的に `Get` されます。各ファイルはロード完了を示す実ロードマーカー（例: `ClaudeOrchestrator`Workflow`$WorkflowVersion`、`ClaudeOrchestrator`TurnWiki`$TurnWikiVersion`）を設定しており、これらの有無で成否が判定されます（シンボルの単純な参照だけでは判定しません）。ファイルが見つからない、または読み込みに失敗した場合は警告メッセージが表示されますが、`ClaudeOrchestrator` 本体のロードは継続され、他の機能には影響しません。

---

## API キーの設定

Anthropic API キーは **環境変数** `ANTHROPIC_API_KEY` として設定します。

**PowerShell（セッション限定）:**

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

**システム環境変数（恒久設定）:**  
「システムの詳細設定」→「環境変数」→「システム環境変数」に `ANTHROPIC_API_KEY` を追加してください。  
Mathematica を再起動すると反映されます。

---

## オーケストレーター設定変数

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

---

## 動作確認

### バージョン確認

```mathematica
$ClaudeOrchestratorVersion
```

### CLI 接続確認

```mathematica
$ClaudeOrchestratorRealLLMEndpoint = "CLI";
ClaudeRealLLMAvailable[]
(* True が返れば OK *)
```

### 診断

```mathematica
ClaudeRealLLMDiagnose["Hello, world!"]
```

### 最小動作テスト（モック使用）

```mathematica
result = ClaudeRunOrchestration[
  "簡単なテストタスク",
  Planner -> Automatic  (* モックプランナーを使用 *)
];
result["Status"]
(* "Complete" または "Partial" が返れば成功 *)
```

### コンパニオンファイルのロード確認

```mathematica
ValueQ[ClaudeOrchestrator`Workflow`$WorkflowVersion]
ValueQ[ClaudeOrchestrator`TurnWiki`$TurnWikiVersion]
(* いずれも True なら該当コンパニオンファイルは正常にロードされている *)
```

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `ClaudeRealLLMAvailable[]` が `False` | `CLAUDE_ORCH_REAL_LLM` 環境変数または `$ClaudeOrchestratorRealLLMEndpoint` を設定 |
| `claude.cmd` が見つからない | PATH を確認し、`$ClaudeOrchestratorCLICommand` にフルパスを指定 |
| 文字化け | `Block[{$CharacterEncoding="UTF-8"}, ...]` で読み込んでいるか確認 |
| `Needs` でパッケージが見つからない | `$Path` に `$packageDirectory` が含まれているか確認 |
| ロード時に「〜の自動ロードに失敗 (skip)」と表示される | 該当のコンパニオンファイル（例: `ClaudeOrchestrator_turnwiki.wl`）が `$packageDirectory` 直下に無い。本体は壊れないが該当機能は使えないため、必要なら個別に取得して配置する |