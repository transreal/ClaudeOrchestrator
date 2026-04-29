# ClaudeOrchestrator API リファレンス (LLM 最適化版)

パッケージ名: `ClaudeOrchestrator`
ソース: `ClaudeOrchestrator.wl`
GitHub: https://github.com/transreal/ClaudeOrchestrator

ClaudeRuntime (単一エージェント実行核) の上に乗るマルチエージェントオーケストレーション層。タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit を担う。

ロード:
```mathematica
Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]
```

依存: ClaudeRuntime`、ClaudeCode` (claudecode.wl)

## パッケージ変数

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン文字列。

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True
True のとき `$ClaudeEvalHook` が非同期経路 (ClaudeRunOrchestrationAsync) を使う。False にすると旧同期挙動に戻る。

### $ClaudeOrchestratorRoles
型: List
許容 Role のリスト: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`

### $ClaudeOrchestratorCapabilities
型: Association
Role -> Capability リストの Association。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト。`NotebookWrite`, `CreateNotebook`, `EvaluationNotebook`, `RunProcess`, `SystemCredential` 等を含む。

### $ClaudeOrchestratorRealLLMEndpoint
型: None | String | Function, 初期値: None
real LLM 統合エンドポイント設定。`None`: 統合テストをスキップ。`"ClaudeCode"`: ClaudeCode`ClaudeQueryBg (同期版) を使う。`"CLI"`: claude CLI を RunProcess で呼ぶ。`fn[prompt]`: カスタム関数。環境変数 `CLAUDE_ORCH_REAL_LLM` でも opt-in 可能。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI モードで起動する実行ファイル名/フルパス。Automatic のとき OS に応じて `"claude"` (Unix) または `"claude.cmd"` (Windows) を選択する。環境変数 `CLAUDE_ORCH_CLI_PATH` でも上書き可能。

## サブモジュール有効化フラグ

BeginPackage より前に設定した場合のみ効果あり。デフォルトはすべて True。

### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True
Directives 統合サブモジュールの有効化フラグ。

### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True
Routing 統合サブモジュールの有効化フラグ。

### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True
CommitSafety 統合サブモジュールの有効化フラグ。

### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True
A4Stub 統合サブモジュールの有効化フラグ。

## Auto ゲート変数 (Phase 32)

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるためのテクニカルマーカーリスト (パッケージ名・関数名・拡張子等)。これらのトークンのいずれかがプロンプトに含まれ、かつタスクが 300 文字未満かつ複雑さ指標なしの場合、Orchestrator 経路を通らず Single パスで処理される。ユーザーはリストを拡張してプロジェクト固有の名称を追加できる。

### $ClaudeEvalAutoFactualEndings
型: List
Auto モードで Single フォールバックさせるための「調査・質問型」の語尾・フレーズリスト。「を調べて」「を教えて」`check if`、`compare` 等を含む。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき「複雑タスク」を識別するためのマーカーリスト。スライド・レポート・プレゼン・複数の成果物要求などが含まれる。これらがプロンプトに現れると、短いタスクでも Orchestrator 経路を通す。

## コア関数

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...|>}`
Options: `Planner -> Automatic` (Automatic は mock プランナーを使う。カスタム関数は `fn[input] -> taskList` 形式), `MaxTasks -> 10` (生成タスク数上限)

### ClaudeValidateTaskSpec[taskSpec]
TaskSpec の妥当性を検証する。
→ `<|"Valid" -> True|False, "Errors" -> {...}|>`

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し、各 task の artifact を収集する (直列または順次)。
→ `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: `WorkerAdapterBuilder -> Automatic` (Role と TaskSpec を受け取り adapter を返す関数), `MaxParallelism -> 1` (現状 1。Stage 2 以降で拡張予定)

### ClaudeCollectArtifacts[spawnResult] → Dataset
spawnResult["Artifacts"] を Dataset として返す。ノートブック上での確認用。

### ClaudeValidateArtifact[artifact, outputSchema]
artifact の payload が OutputSchema を満たすか検証する。
→ `<|"Valid" -> True|False, "Errors" -> {...}|>`

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し ReducedArtifact を返す。
→ `<|"ArtifactType" -> "Reduced", "Payload" -> ..., "Sources" -> ...|>`
Options: `Reducer -> Automatic` (Automatic はデフォルト reducer を使う。カスタム関数は `fn[artifacts] -> reducedArtifact` 形式)

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し、reducedArtifact を target notebook に反映する。committer の HeldExpr 内の `EvaluationNotebook[]` / `CreateNotebook[...]` 参照は targetNotebook に ReplaceAll で書き換えられる。
→ `<|"Status" -> "Committed"|"Failed"|"RolledBack", "Mode" -> ..., "Details" -> ...|>`
Options: `CommitterAdapterBuilder -> Automatic`, `CommitMode -> "Direct"` ("Direct": 即時書き込み。"Transactional": shadow buffer に書いてから verify/flush し、失敗時は target notebook を無変更のまま rollback する (spec §12.3)), `Verifier -> Automatic` (fn[buffer, cells] -> True/False 形式)

### ClaudeRunOrchestration[input, opts]
Planning → Spawn → Reduce → (optional) Commit の全フェーズを直列に実行する。
→ 4 フェーズの結果を束ねた Association
Options: `TargetNotebook -> None` (Commit するなら指定), `Planner -> Automatic`, `WorkerAdapterBuilder -> Automatic`, `Reducer -> Automatic`, `CommitterAdapterBuilder -> Automatic`, `MaxTasks -> 10`, `MaxParallelism -> 1`, `Confirm -> False`

例:
```mathematica
ClaudeRunOrchestration["Explore the ClaudeRuntime API and summarize",
  TargetNotebook -> EvaluationNotebook[]]
```

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま、batchInstructions に含まれる prompt を ClaudeContinueTurn で順次投入する。notebook 共有問題を回避する現実解 (spec §17.1)。
→ `{<|"Index" -> i, "Prompt" -> ..., "Result" -> ...|>, ...}`
Options: `WaitBetween -> Quantity[1, "Seconds"]` (投入間隔)

## 非同期オーケストレーション API

### ClaudeRunOrchestrationAsync[input, opts]
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し、orchJobId を即座に返す。フロントエンドをブロックしない。opts は ClaudeRunOrchestration と同じ。
→ orchJobId (String)

### ClaudeOrchestrationStatus[orchJobId]
orchestration ジョブの現在状態を返す。
→ `<|"Status" -> "Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase" -> ..., "ElapsedSecs" -> ..., "PlanJobId" -> ..., "SpawnJobId" -> ...|>`

### ClaudeOrchestrationResult[orchJobId]
完了済み orchestration の最終結果 (ClaudeRunOrchestration と同形の Association) を返す。未完了なら Missing を返す。

### ClaudeOrchestrationWait[orchJobId, timeoutSec]
orchestration 完了まで待機する (テスト・スクリプト専用。対話セルでは使用を避ける)。デフォルトタイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId]
実行中の DAG を中断しレジストリから除去する。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧を Dataset で返す。

## Real LLM 統合

### ClaudeRealLLMAvailable[] → Boolean
real LLM 統合が設定済みか確認する。`$ClaudeOrchestratorRealLLMEndpoint` と環境変数 `CLAUDE_ORCH_REAL_LLM` を確認する。

### ClaudeRealLLMQuery[prompt] → String | $Failed
設定済みの real LLM エンドポイントを通じて prompt を実行する。失敗時は $Failed を返す。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し、診断情報 (endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否) を Association で返す。W1-W3 等の失敗切り分けに使用する。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ、plan 結果と raw LLM 応答 head・task count・status・error 情報を Association で返す。W1 の失敗切り分け用。

## Directives モジュール

Phase 34 A4.x / Stage 2 (2026-04-26) 統合。ClaudeDirectives 経由で role / model / goal に応じた directive prefix を worker prompt に注入する。`$ClaudeOrchestratorEnableDirectives = True` のときのみ有効。

### $DirectivesVersion
型: String
Directives モジュールのバージョン文字列。

### $DirectivesVerbose
型: Boolean, 初期値: False
True のとき、directive prefix 構築のたびに診断メッセージを Print する。

### DirectivesEnabledQ[] → Boolean
ClaudeDirectives がロードされ、リポジトリも読み込まれていれば True。False のときはフックが passthrough になる。

### DirectivesAutoLoadStatus[] → String
直近の ClaudeDirectives リポジトリ自動ロード試行結果を返す文字列。EnabledQ[] が False を返す原因の診断に使用する。

### DirectivesForceLoad[] → Null
### DirectivesForceLoad[path] → Null
ClaudeDirectives リポジトリの再ロードを試行する (オプションで root path を指定)。自動ロード試行フラグをリセットするため、以降の EnabledQ[] が再試行する。

### DirectivesInvalidateCache[] → Null
ClaudeDirectives リポジトリキャッシュを破棄する。次回呼び出し時にディスクから再ロードする。

### DirectivesNormalizeModel[modelSpec, role] → String
directive 投影に使用する文字列モデル名を返す。String・List ({provider, model, url})・Automatic/None の 3 系統を処理する。

### DirectivesPreviewPrefix[role, model, goal] → String
ClaudeInjectDirectivePrefix がフック経由で prepend する directive prefix 文字列を直接取得する。デバッグ用。

### DirectivesSelected[role, model, goal] → Association
bundle の DirectiveMeta から選択されたルール・スキル情報を返す。
→ `<|"Rules" -> {...names...}, "Skills" -> {...names...}, "Mode" -> modeStr, "Tokens" -> n, "Model" -> resolvedModelStr|>`

### DirectivesResolveBundle[taskSpec_Association, opts]
TaskSpec の "Role" / "Goal" / "Inputs" / "DependsOn" などから ClaudeDirectives bundle を解決する。Orchestrator の TaskSpec 慣習を ClaudeDirectives の opts 形式にブリッジする。
→ ClaudeDirectives bundle (Association)
Options: `"Model" -> Automatic`, `"Mode" -> Automatic` (Automatic | "Full" | "Summary" | "Index" | "Lazy"), `"TokenBudget" -> Automatic` (Integer | Automatic), `"MaxSkills" -> Automatic` (Integer)

## Routing モジュール

Phase 34 A4.5 (2026-04-26) 統合。worker ごとに適切な queryFn (CLI / API) を振り分ける。`$ClaudeOrchestratorEnableRouting = True` のときのみ有効。

### $RoutingVersion
型: String
Routing モジュールのバージョン文字列。

### $RoutingVerbose
型: Boolean, 初期値: False
True のとき、A4ResolveQueryFnForRole 呼び出しのたびに診断メッセージを Print する。

### RoutingEnabledQ[] → Boolean
CLI (ClaudeQueryBg) または API (iQueryViaAPI) の少なくとも一方が呼び出し可能なら True。

### RoutingPreviewModel[role, model] → String | List
role-aware default ルックアップと qwen→$ClaudePrivateModel 展開後の解決済みモデル spec を返す。

### RoutingGetInfo[role, model] → Association
→ `<|"Source" -> str, "Path" -> "CLI"|"API"|"Default", "Model" -> resolved, "Role" -> role, "QueryFunction" -> fn|>`

### RoutingListPaths[] → Association
現在セッションで利用可能なルーティングパスを示す Association を返す。
→ `<|"CLI" -> Bool, "API" -> Bool, "PrivateModel" -> Bool, "RoleDefaults" -> Bool|>`

## A4Stub モジュール

Phase 34 A4.4 (2026-04-26) 統合。ClaudeOrchestrator 本体の hook ポイントに差し込む queryFn・model・directive prefix 解決の実装。`$ClaudeOrchestratorEnableA4Stub = True` のときのみ有効。Routing / Directives モジュールがロード済みの場合はそれらが優先されるため、A4Stub は fallback として機能する。

### $A4StubVersion
型: String
A4Stub モジュールのバージョン文字列。

### A4ResolveQueryFnForRole[queryFn, model, role] → Association
queryFn が Automatic/None 以外の場合は passthrough。Automatic の場合は model と role に基づいて適切な queryFn を構築する (Routing モジュールが利用可能ならそちらが先に動作する)。
→ `<|"QueryFunction" -> fn, "Source" -> str, "Path" -> str, "Model" -> resolved, "Role" -> role|>`

### A4ResolveModelForRole[role, model] → String | List | Automatic
role に応じたモデル spec を解決する。Routing モジュールがロード済みの場合はそちらの実装が有効になる。stub では model を passthrough する。

### A4InjectDirectivePrefix[prompt, role, model, goal] → String
worker prompt の前に directive prefix を prepend する。Directives モジュールがロード済みの場合はそちらの実装が有効になる。stub では prompt を passthrough する。

## CommitSafety モジュール

Phase 34 A4.2 (2026-04-26) 統合。LLM-backed commit と iDeterministicSlideCommit のいずれも失敗/不十分だった場合の 3rd-tier fallback を提供する。`$ClaudeOrchestratorEnableCommitSafety = True` のときのみ有効。内部実装のみで追加の公開 API は持たない (内部の `iDeterministicSlideCommit` を自動拡張する)。

### $ClaudeCommitSafetyVersion
型: String
CommitSafety モジュールのバージョン文字列。

機能: payload (Association | String | List) を直接 Markdown 解析して Cell list を生成し target notebook に書き込む `iSmartPayloadCommit` を内部提供する。Markdown コードブロック (` ```mathematica ... ``` `) を Input セルに、見出し (#/##/###) を Section/Subsection セルに、bullet (- / *) を ItemParagraph セルに変換する。

## 設計上の不変条件

1. ClaudeRuntime は 1 agent kernel のまま維持する
2. 並列 worker は artifact producer に限定する (NotebookWrite 禁止)
3. 実 notebook への書き込みは single committer のみが行う
4. worker 間の共有状態は明示的 artifact / JSON / Association のみ
5. `EvaluationNotebook[]` / `CreateNotebook[...]` は worker から deny される