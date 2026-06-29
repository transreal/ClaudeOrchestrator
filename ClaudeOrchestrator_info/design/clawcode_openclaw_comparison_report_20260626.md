# ClawCode / OpenClaw / Mathematica-SourceVault 系 比較レポート

作成日: 2026-06-26  
対象: NBAccess, claudecode, ClaudeRuntime, ClaudeOrchestrator, SourceVault, ClaudeTestKit, PDFIndex, github  
比較対象: `ultraworkers/claw-code`, `openclaw/openclaw`

## 0. 要約

本システムは、ClawCode や OpenClaw と同じく LLM agent を実作業に接続する基盤である。ただし、設計重心は大きく異なる。

- **ClawCode** は、Claude Code 風の CLI agent harness を Rust で再実装し、ファイル操作・bash・MCP・skills・agents・permission mode・JSON 出力・mock parity harness を備える、開発者向け CLI runtime である。
- **OpenClaw** は、単一ユーザー向けの常駐 Gateway を中心に、WhatsApp / Telegram / Slack / Discord / iMessage / WebChat などのチャネル、nodes、voice、canvas、skills、sandbox を束ねる personal AI assistant platform である。
- **本システム** は、Mathematica notebook を作業空間・知識空間・実行空間として扱い、NBAccess によるセル/値/ファイル単位の privacy control、ClaudeRuntime の Expression-Proposal ループ、ClaudeOrchestrator の Petri net / multi-agent workflow、SourceVault の source-first knowledge vault / release gate / encrypted storage / search service、PDFIndex の privacy-aware PDF retrieval、github の WL-native package publishing を統合する、研究・開発・知識管理向けの privacy-aware computational notebook agent platform である。

結論として、本システムは「汎用 CLI agent」や「常駐 personal assistant」と競合するというより、**Mathematica notebook を中心に、研究資料・コード・実行履歴・検証・公開制御を同じ graph に載せる垂直統合基盤**である。強みはプライバシー境界、source provenance、notebook-aware execution、deterministic route、release policy、テスト可能な安全核にある。一方、弱みは導入面の複雑さ、Mathematica / Windows 依存、UI/チャネル統合の不足、公開エコシステムの薄さである。

## 1. 比較対象の位置づけ

### 1.1 ClawCode

`ultraworkers/claw-code` は、公開 README で Rust workspace の `claw` CLI binary を現在の正規 runtime surface としている。構成は `rust/` を中心に、CLI、interactive REPL、one-shot prompt、permission mode、model/provider routing、MCP、skills、agents、plugin surface、session persistence、doctor/status/sandbox などを提供する。

主な特徴:

- Rust 実装による CLI agent harness。
- Anthropic / OpenAI-compatible / xAI / DashScope / Ollama 等への provider routing。
- `read-only`, `workspace-write`, `danger-full-access` の permission mode。
- `read_file`, `glob`, `grep`, `write`, `edit`, `bash`, web tools, MCP, skills, agents, subagent surface。
- `--output-format json` による automation-friendly な機械可読出力。
- mock Anthropic-compatible service と parity harness による CLI 挙動検証。
- Project memory として `CLAUDE.md`, `CLAW.md`, `AGENTS.md` を読む。

注意点として、README は `cargo install claw-code` ではなく repo から build する形を案内しており、ACP/Zed daemon はまだ未提供で status surface に留まるとしている。

### 1.2 OpenClaw

`openclaw/openclaw` は、単一ユーザーの personal AI assistant を Gateway daemon として常駐させる設計である。README は OpenClaw を「自分のデバイス上で動かし、普段使うチャネルで応答する assistant」と位置づける。Gateway は制御面であり、実体は assistant / channels / nodes / tools / sessions の統合体である。

主な特徴:

- Node 24 系の npm package として導入する Gateway daemon。
- WhatsApp, Telegram, Slack, Discord, Google Chat, Signal, iMessage, Matrix, LINE, WeChat, WebChat など多数の messaging channel。
- WebSocket typed API、device pairing、node role、canvas host、voice wake / talk mode。
- Multi-agent routing、per-agent workspace/session、skills、cron、webhook、Gmail Pub/Sub 等。
- Security guidance は personal assistant trust model を明示し、host / config / operator boundary を重視する。
- non-main sessions を Docker / SSH / OpenShell 等の sandbox backend に入れるモデルを持つ。

OpenClaw は「常駐・多チャネル・生活/業務 assistant」としての完成度が高い一方、notebook cell、Mathematica expression safety、研究 source provenance、release gate などは本システム側の独自領域である。

### 1.3 本システム

本システムは、以下の層が疎結合に連携する。

- **NBAccess**: Mathematica notebook のセル読み書き、privacy filtering、confidential dependency graph、ObjectSpec、鍵隔離層、安全な式検証。
- **claudecode**: Notebook から Claude Code CLI / Codex CLI / API fallback / LM Studio を呼ぶ統合層。セッション、directive projection、package update、documentation update、palette、SourceVault PromptRouter bridge を持つ。
- **ClaudeRuntime**: LLM が提案した `HoldComplete[...]` 式を BuildContext → QueryProvider → ParseProposal → ValidateProposal → DispatchDecision で進める Expression-Proposal 状態機械。
- **ClaudeOrchestrator**: ClaudeRuntime を単一 agent kernel として保持し、Planning → Spawn → Reduce → Commit の multi-agent orchestration、Petri net workflow、observability、PromptWorkflow を提供する。
- **SourceVault**: URL / arXiv / PDF / Notebook / text を first-class source として ingest し、snapshot lifecycle、claim、Evidence Bundle、PromptRouter、release context gate、encrypted storage、mail / identity / Eagle / MCP / Web service を束ねる。
- **PDFIndex**: PDF extraction, OCR fallback, structured chunking, hybrid search, privacy score による local/public 分離、LLM/PDF QA を提供する。
- **ClaudeTestKit**: MockProvider / MockAdapter / ScenarioRunner / assertion による runtime と orchestration の安全性回帰テスト。
- **github**: WL notebook から GitHub REST API を扱い、manifest-driven publish、PR/commit UI、docs freshness gate 付き auto commit を行う。

## 2. アーキテクチャ比較

| 観点 | ClawCode | OpenClaw | 本システム |
|---|---|---|---|
| 中心概念 | CLI agent harness | Long-lived Gateway personal assistant | Mathematica notebook + SourceVault graph |
| 主 runtime | Rust CLI | Node Gateway daemon | Wolfram Language packages + Claude/Codex/LM Studio |
| 操作面 | terminal / REPL / JSON CLI | messaging channels / app / web / nodes | Mathematica notebook / palette / WL functions |
| agent 実行単位 | prompt/session/tool turn | session/agent/channel/node | expression proposal / runtime state / workflow token |
| workflow | tasks, agents, subagents, skills | multi-agent routing, cron, webhooks | Petri net, DAG, PromptWorkflow, SourceVault workflow registry |
| data model | workspace files, sessions, memory files | Gateway state, sessions, channel messages, workspace | cell, value, file ObjectSpec, source, snapshot, claim, bundle, index |
| privacy | permission mode, workspace boundary, sandbox/tool gate | personal trust boundary, pairing, sandbox for non-main | privacy score/label, dependency propagation, release context, encryption |
| test strategy | mock parity harness, Rust tests | docs mention audits/doctor/security audit | ClaudeTestKit + NBAccess public API + orchestration assertions |
| publication | CLI project repo | npm package + docs + channel ecosystem | github.wl package publishing + docs freshness gate |

## 3. Security / Privacy Model

### 3.1 ClawCode

ClawCode の安全性は、CLI permission mode と workspace/tool boundary に寄っている。`read-only` はローカル inspection tool に限定され、`workspace-write` は workspace 内編集を許可しつつ network / shell / subagent 等を explicit escalation に寄せ、`danger-full-access` は明示 opt-in の強権モードである。PARITY では path traversal / symlink escape / binary detection / size limit / permission enforcement などの file-tool guard が明示されている。

本システムとの違いは、ClawCode の privacy は主に「tool が何を読めるか/書けるか」というファイル・コマンド境界であり、**Mathematica の変数依存・セル依存・関数 head の効果分類・値のスキーマだけ送る**といった意味論的 privacy までは扱わない点である。

### 3.2 OpenClaw

OpenClaw は security docs で personal assistant trust model を明示している。1 Gateway は 1 trusted operator boundary を前提とし、互いに敵対的な複数ユーザーを 1 gateway / 1 agent に混在させる security boundary ではない。Channel DM は pairing/allowlist を基本とし、group/channel exposure は delegation risk として扱う。host tool は personal setup では強く許されるが、non-main sessions には sandbox を推奨する。

本システムとの違いは、OpenClaw が「誰が Gateway に話せるか」「どの channel / node / session がどの tool authority を持つか」を中心にするのに対し、本システムは「この notebook cell / source chunk / PDF page / mail body / prompt route をどの LLM / route / release context に出してよいか」を中心にする点である。

### 3.3 本システム

本システムの security/privacy は多層である。

- NBAccess は cell privacy level、confidential variables、dependency graph、provider access level、ObjectSpec、Allowed Expression Surface を持つ。
- ClaudeRuntime は LLM 生成式を `HoldComplete` のまま検証し、`Permit` / `NeedsApproval` / `Deny` / `RepairNeeded` / `TextOnly` / `ToolUse` へ分岐する。
- SourceVault は raw bytes を PrivateVault に置き、外部 LLM には sanitized snippet のみを渡す。`SourceVaultSearch` は release context gate を通った chunk だけを返し、生 path を外へ出さない。
- SourceVault_crypto / NBAccess_crypto は KeyRef による鍵隔離、encrypt-then-MAC、可搬鍵バンドル、mail body 暗号化を担う。
- PDFIndex は privacy score > 0.5 の PDF を local-only に分離し、公開可能 chunk だけを cloud route へ出す。
- ClaudeTestKit は secret leak, validation denied, budget, worker notebook mutation, single committer, reducer deterministic 等を検証する。

このモデルは ClawCode / OpenClaw より導入は重いが、**研究資料・個人情報・ノートブック実行状態・公開可能断片が混ざる環境**ではより細かく制御できる。

## 4. Workflow / Orchestration

### 4.1 ClawCode との比較

ClawCode は CLI 内で slash commands, skills, agents, subagents, task registry, team/cron registry, MCP lifecycle, LSP client などを提供する。`/ultraplan`, `/teleport`, `/bughunter` のような操作は、開発者が terminal で codebase を探索・修正する用途に向いている。

本システムの ClaudeOrchestrator は、worker が notebook へ直接副作用を持つことを禁止し、parallel worker は artifact 生成だけに限定する。実 notebook への書き込みは single committer が行う。この原則は、ClawCode の workspace editing より制約が強いが、Mathematica notebook の FrontEnd / kernel state / cell output の競合を避けるために重要である。

また、本システムは WorkflowNet / Petri net を使い、DAG では表しにくい並行・同期・選択・token flow を直接扱う。ClawCode の task/subagent は CLI automation に自然だが、workflow trace を SourceVault snapshot / notebook history / Evidence Bundle と統合する発想は本システムの方が深い。

### 4.2 OpenClaw との比較

OpenClaw は Gateway が channel / agent / node / cron / webhook を束ね、複数の入口から assistant を起動する。外部世界との接点は OpenClaw が圧倒的に広い。

一方、本システムは外部チャネルよりも、notebook 内の計算・資料・TODO・PDF・メール・source snapshot・公開検索サービスを一貫して扱う。OpenClaw の workflow が「メッセージやイベントに反応する assistant operation」なら、本システムの workflow は「計算可能な研究/開発 artifact を安全に生成・検証・保存・公開する pipeline」である。

## 5. Knowledge / Retrieval / Provenance

### 5.1 ClawCode

ClawCode は project memory files、session persistence、file context (`@path`) を持つ。これは codebase navigation には十分有効である。ただし、source snapshot lifecycle、claim extraction、Evidence Bundle、release gate、immutable corpus snapshot といった knowledge provenance は主機能ではない。

### 5.2 OpenClaw

OpenClaw は session/memory engine、active memory、compaction、channels、inferred commitments など personal assistant memory の方向に発展している。生活・業務 assistant としては自然だが、研究文献や PDF corpus のページ単位 provenance / release policy 付き検索は主目的ではない。

### 5.3 本システム

SourceVault と PDFIndex により、本システムは retrieval/provenance 面で最も強い。

- source を raw hash / snapshot / parsed pages / meta JSON に分解して永続化。
- snapshot lifecycle により Current / Stale / Frozen / Invalidated を管理。
- claim と Evidence Bundle を content hash と依存関係で管理。
- release context により公開可能 chunk だけを返す。
- PDFIndex legacy adapter と native projection index を併用できる。
- notebook 自体も source として index し、Header / Todo / Deadline / lint を抽出する。
- Eagle, mail, web ingest, MCP gateway, SearXNG まで SourceVault graph に接続できる。

これは、ClawCode / OpenClaw が workspace/session assistant であるのに対し、本システムが **source-first knowledge vault** であることを示す。

## 6. 開発体験

### 6.1 ClawCode が優位な点

- Rust binary として terminal から使いやすい。
- `doctor`, `status`, `sandbox`, `config`, `mcp`, `skills`, `agents` などの CLI diagnostics が整っている。
- JSON output が豊富で CI / script automation に向く。
- provider routing が CLI flag / env / config として明快。
- mock parity harness が CLI runtime の regression に向く。

### 6.2 OpenClaw が優位な点

- npm install + onboard + daemon という導入経路がユーザー体験として整理されている。
- 常駐 Gateway と多チャネル連携により、terminal を開かずに assistant を使える。
- mobile / desktop companion / voice / canvas など、human interaction surface が広い。
- channel pairing / exposure runbook / security audit など運用ドキュメントが充実している。

### 6.3 本システムが優位な点

- Mathematica notebook の cell / output / dependency / TaggingRules / FrontEnd を理解している。
- LLM 生成物を Wolfram expression として保持・検証・実行できる。
- SourceVault により、資料・PDF・Notebook・メール・検索 service が同じ privacy/provenance model に乗る。
- PDFIndex により、ローカル embedding / OCR fallback / structured table chunking / privacy-aware QA が可能。
- ClaudeTestKit により、security kernel と orchestration invariant を mock 付きで検証できる。
- github.wl により、WL package の docs freshness gate 付き publish が notebook 内で完結する。

## 7. 弱点と改善提案

### 7.1 本システムの弱点

1. **導入複雑性**  
   NBAccess, claudecode, ClaudeRuntime, ClaudeOrchestrator, SourceVault, PDFIndex, ClaudeTestKit, github が横断するため、新規ユーザーが全体像を掴みにくい。

2. **Mathematica / Windows 依存の強さ**  
   Wolfram Language を中心に設計されている点は強みだが、ClawCode / OpenClaw のような一般開発者向け導入経路に比べると対象ユーザーが狭い。

3. **常駐 assistant / channel surface の不足**  
   OpenClaw のような messaging channels, mobile nodes, voice, canvas, web admin は本システムでは主目的ではない。

4. **CLI diagnostics の統一不足**  
   ClawCode の `doctor --output-format json` や OpenClaw の `security audit` に相当する、全パッケージ横断 doctor があるとよい。

5. **公開エコシステムの弱さ**  
   ClawCode の skills/agents/plugin surface、OpenClaw の ClawHub 的な distribution surface に相当するものは、現状では local docs / github.wl 中心である。

### 7.2 改善提案

1. **System Doctor の追加**  
   `ClaudeSystemDoctor[]` あるいは `SourceVaultSystemDoctor[]` を作り、NBAccess keys、Claude/Codex/LM Studio、SourceVault roots、PDFIndex Python libs、WolframScript runner、GitHub token、MCP service、privacy gates を一括検査する。

2. **横断 architecture map の整備**  
   `ClaudeOrchestrator_info/design/system_architecture_map.md` として、各パッケージの責務・依存・データ境界・ロード順・失敗時 fallback を 1 枚にまとめる。

3. **Gateway ではなく Notebook Gateway の明確化**  
   OpenClaw と競合する常駐 Gateway を目指すのではなく、Mathematica notebook / SourceVault / local service / MCP を束ねる `Notebook Gateway` として位置づける。

4. **SourceVault release gate の demo 強化**  
   ClawCode / OpenClaw との差別化として、private PDF と public PDF が混在する corpus から release context gate 付き Web QA を公開する demo を整備する。

5. **ClaudeTestKit の golden scenario 増強**  
   ClawCode の parity harness に相当するものとして、PromptRouter, WorkflowNet, SourceVaultSearch, PDFIndex legacy adapter, github docs freshness gate まで含む end-to-end mock scenario を用意する。

6. **OpenClaw 連携の可能性**  
   OpenClaw の channel/Gateway を入口にし、実際の研究資料検索や notebook workflow は SourceVault / ClaudeOrchestrator に委譲する構成は相性がよい。OpenClaw 側には「チャネルとデバイス」、本システム側には「notebook/source/privacy/provenance」を担当させる。

7. **ClawCode 連携の可能性**  
   ClawCode の Rust CLI / skills / agents を外部 worker として使い、本システムの SourceVault ObjectSpec と release gate をプロンプト投入前に適用する構成が考えられる。ただし、ClawCode 側の permission mode はファイル/ツール境界であり、NBAccess のセル依存 privacy と二重化するため、bridge では「パスを見せない」「materialized mirror は read-only」「SourceVault PublicManifest 経由」の原則を守る必要がある。

## 8. 競争軸ごとの結論

| 競争軸 | 最も強い候補 | 理由 |
|---|---|---|
| Terminal coding agent | ClawCode | Rust CLI、permission mode、JSON automation、skills/agents/MCP が強い |
| Personal always-on assistant | OpenClaw | Gateway、channels、nodes、voice、canvas、mobile/desktop surface が強い |
| Mathematica notebook agent | 本システム | cell/context/privacy/expression execution を native に扱う |
| Privacy-aware research vault | 本システム | SourceVault + PDFIndex + NBAccess_crypto + release context |
| Multi-agent workflow formalization | 本システム | Petri net / single committer / artifact reduction / workflow snapshots |
| Broad user onboarding | OpenClaw | npm/onboard/daemon/docs/channel setup が強い |
| CLI regression testing | ClawCode | mock parity harness と Rust tests が明確 |
| Security kernel testing | 本システム | ClaudeTestKit が NBAccess public API を使い secret leak / policy invariant を検証 |

## 9. 最終評価

ClawCode と OpenClaw は、どちらも「LLM assistant を実作業の tool surface に接続する」基盤である。しかし、ClawCode は terminal-first な coding harness、OpenClaw は gateway-first な personal assistant であり、本システムは notebook/source-first な research/dev platform である。

したがって、本システムの開発方針としては、ClawCode の CLI ergonomics と parity harness、OpenClaw の onboarding / doctor / security audit / channel gateway を参考にしつつ、競争する中心を「より汎用の assistant」に置くべきではない。むしろ、以下を核に据えるべきである。

- Mathematica expression を安全に提案・検証・実行する。
- Notebook の cell / output / dependency / history を privacy-aware に扱う。
- SourceVault により source / snapshot / claim / evidence / search / release を一貫管理する。
- PDFIndex と SourceVault_searchindex により、公開可能性を保った retrieval を提供する。
- ClaudeOrchestrator により、notebook へ直接副作用を持たない multi-agent workflow を実行する。
- ClaudeTestKit により、これらの安全不変条件を継続的に検証する。

この位置づけなら、本システムは ClawCode / OpenClaw の単なる亜種ではなく、**computational notebook と knowledge provenance を中心にした独自カテゴリ**として成立する。

## 参考資料

### 外部一次情報

- ultraworkers/claw-code README: https://github.com/ultraworkers/claw-code
- ClawCode USAGE.md: https://raw.githubusercontent.com/ultraworkers/claw-code/main/USAGE.md
- ClawCode rust/README.md: https://raw.githubusercontent.com/ultraworkers/claw-code/main/rust/README.md
- ClawCode PARITY.md: https://raw.githubusercontent.com/ultraworkers/claw-code/main/PARITY.md
- ClawCode SECURITY.md: https://raw.githubusercontent.com/ultraworkers/claw-code/main/SECURITY.md
- OpenClaw README: https://github.com/openclaw/openclaw
- OpenClaw Gateway architecture: https://docs.openclaw.ai/concepts/architecture
- OpenClaw Security: https://docs.openclaw.ai/gateway/security
- OpenClaw Sandboxing: https://docs.openclaw.ai/gateway/sandboxing
- OpenClaw Session management: https://docs.openclaw.ai/concepts/session

### ローカル参照ドキュメント

- `NBAccess_info/docs/README.md`
- `claudecode_info/docs/README.md`
- `ClaudeRuntime_info/docs/README.md`
- `ClaudeOrchestrator_info/docs/README.md`
- `SourceVault_info/docs/README.md`
- `SourceVault_info/docs/api_searchindex.md`
- `PDFIndex_info/docs/README.md`
- `ClaudeTestKit_info/docs/README.md`
- `github_info/docs/README.md`
- `SourceVault_info/design/sourcevault-spec-v0.13.md`
- `ClaudeOrchestrator_info/design/claude_multi_agent_orchestration_spec.md`
- `NBAccess_info/design/NBAccess_claudecode_privacy_spec_v0_1.md`
