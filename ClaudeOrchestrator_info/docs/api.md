# ClaudeOrchestrator API リファレンス

ClaudeRuntime の上に乗る Multi-Agent Orchestration 層。タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit を提供する。

## バージョン

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン。

## 定数

### $ClaudeOrchestratorRoles
型: List
許容 Role のリスト: {"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}

### $ClaudeOrchestratorCapabilities
型: Association
Role -> Capability リストの対応表。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential 等)。

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるテクニカルマーカーリスト (パッケージ名・関数名・拡張子等)。ユーザーは拡張可。

### $ClaudeEvalAutoFactualEndings
型: List
Auto モードで Single フォールバックさせる調査・質問型の語尾・フレーズリスト ("を調べて" "を教えて" "check" "if" "compare" 等)。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき複雑タスクを識別するマーカーリスト (スライド・レポート・プレゼン・複数成果物要求など)。

### $ClaudeOrchestratorRealLLMEndpoint
型: None | String | Function, 初期値: None
real LLM 統合の選択: None (スキップ) | "ClaudeCode" (ClaudeQueryBg) | "CLI" (claude CLI を RunProcess) | fn[prompt] (カスタム関数)。環境変数 CLAUDE_ORCH_REAL_LLM でも opt-in 可。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode で起動する実行ファイル名/フルパス。Automatic は OS 依存 ("claude" / "claude.cmd")。環境変数 CLAUDE_ORCH_CLI_PATH で上書き可。

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True
$ClaudeEvalHook が ClaudeRunOrchestrationAsync (非同期) と ClaudeRunOrchestration (同期) のどちらを使うかを制御。False で旧同期挙動。

### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True
Directives 統合モジュールの有効化フラグ (BeginPackage 前に設定)。

### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True
Routing 統合モジュールの有効化フラグ。

### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True
CommitSafety 統合モジュールの有効化フラグ。

### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True
A4Stub 統合モジュールの有効化フラグ。

### $DirectivesVersion
型: String
Directives 統合モジュールのバージョン文字列。

### $DirectivesVerbose
型: Boolean, 初期値: False
True で directive prefix 構築のたびに診断メッセージを出す。

### $RoutingVersion
型: String
Routing 統合モジュールのバージョン文字列。

### $RoutingVerbose
型: Boolean, 初期値: False
True で ClaudeResolveQueryFnForRole 呼び出しのたびに診断メッセージを出す。

### $A4StubVersion
型: String
A4 hook stub のバージョン文字列。

### $ClaudeCommitSafetyVersion
型: String
Phase A4.2 commit safety patch のバージョン文字列。

## Planning フェーズ

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ Association `<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...}|>`
Options: Planner -> Automatic (プランナー関数 | Automatic で mock), MaxTasks -> 10

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証。`<|"Valid"->True/False, "Errors"->{...}|>` を返す。

## Spawn フェーズ

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し各 task の artifact を収集する。
→ Association `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: WorkerAdapterBuilder -> Automatic (Role -> TaskSpec を受け取り adapter を返す関数), MaxParallelism -> 1

### ClaudeCollectArtifacts[spawnResult] → Dataset
spawnResult["Artifacts"] を Dataset として返す。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証。`<|"Valid"->True/False, "Errors"->{...}|>`

## Reduce フェーズ

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物 (ReducedArtifact) を返す。
→ Association `<|"ArtifactType"->"Reduced", "Payload"->..., "Sources"->...|>`
Options: Reducer -> Automatic (artifacts を受け取り ReducedArtifact を返す関数 | Automatic)

## Commit フェーズ

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し reducedArtifact を target notebook に反映する。committer の HeldExpr 内の EvaluationNotebook[] / CreateNotebook[...] 参照は targetNotebook に ReplaceAll で書換えられる。Transactional モードでは shadow buffer に書いてから verify / flush し、失敗時は target notebook を無変更のまま rollback する。
→ Association `<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->..., "Details"->...|>`
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" ("Direct" | "Transactional"), Verifier -> Automatic (fn[buffer, cells] -> True/False)

## Orchestration (同期)

### ClaudeRunOrchestration[input, opts]
Planning -> Spawn -> Reduce -> (optional) Commit の全フェーズを直列に回す。
→ Association (4 フェーズ結果を束ねた構造)
Options: TargetNotebook -> None (指定すれば Commit), Planner -> Automatic, WorkerAdapterBuilder -> Automatic, Reducer -> Automatic, CommitterAdapterBuilder -> Automatic, MaxTasks -> 10, MaxParallelism -> 1, Confirm -> False

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま batchInstructions の prompt を ClaudeContinueTurn で順次投入する (notebook 共有問題の現実解)。
→ List `{<|"Index"->i, "Prompt"->..., "Result"->...|>, ...}`
Options: WaitBetween -> Quantity[1, "Seconds"]

## Orchestration (非同期)

### ClaudeRunOrchestrationAsync[input, opts] → String (orchJobId)
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し orchJobId を即座に返す。フロントエンドをブロックしない。opts は ClaudeRunOrchestration と同じ。

### ClaudeOrchestrationStatus[orchJobId] → Association
orchestration ジョブの現在状態。`<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->..., "ElapsedSecs"->..., "PlanJobId"->..., "SpawnJobId"->...|>`

### ClaudeOrchestrationResult[orchJobId] → Association | Missing
完了済み orchestration の最終結果 (ClaudeRunOrchestration と同形)。未完了なら Missing。

### ClaudeOrchestrationWait[orchJobId, timeoutSec] → Association
orchestration 完了まで待機 (テスト・スクリプト専用。対話セルでは避ける)。既定タイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId] → Boolean
実行中の DAG を中止しレジストリから除去する。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧。

## Real LLM 統合

### ClaudeRealLLMAvailable[] → Boolean
real-LLM 統合が設定されているか ($ClaudeOrchestratorRealLLMEndpoint と環境変数 CLAUDE_ORCH_REAL_LLM をチェック)。

### ClaudeRealLLMQuery[prompt] → String | $Failed
prompt を設定済み real-LLM エンドポイントで実行し応答 String を返す。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し診断情報 (endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否) を返す。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ plan 結果と raw LLM 応答 head、task count、status、error 情報を返す。

## Directives 統合

### DirectivesEnabledQ[] → Boolean
ClaudeDirectives がロードされリポジトリが利用可能なら True。False なら hook は passthrough。

### DirectivesPreviewPrefix[role, model, goal] → String
ClaudeInjectDirectivePrefix が prepend する directive prefix 文字列を、orchestrator hook を経由せずに返す (デバッグ用)。

### DirectivesSelected[role, model, goal] → Association
`<|"Rules"->{...}, "Skills"->{...}, "Mode"->modeStr, "Tokens"->n, "Model"->resolvedModelStr|>`

### DirectivesResolveBundle[taskSpec, opts]
TaskSpec の Role / Goal / Inputs / DependsOn から ClaudeDirectives bundle を解決し ClaudeResolveDirectiveBundle へブリッジする。
→ Association (bundle)
Options: "Model" -> spec, "Mode" -> Automatic ("Full"|"Summary"|"Index"|"Lazy"), "TokenBudget" -> Automatic | Integer, "MaxSkills" -> Integer

### DirectivesInvalidateCache[]
ClaudeDirectives リポジトリキャッシュを破棄し、次回呼び出しでディスクから再ロードさせる。

### DirectivesNormalizeModel[modelSpec, role] → String
directive projection に使う文字列モデル名を返す。String / List ({provider, model, url}) / Automatic / None を正規化する。

### DirectivesAutoLoadStatus[] → String
直近の ClaudeDirectives リポジトリ auto-load 試行の結果メッセージ。EnabledQ[] が False の原因切り分け用。

### DirectivesForceLoad[]
### DirectivesForceLoad[path]
ClaudeDirectives リポジトリの再ロードを試行する。auto-load 試行フラグもリセットされ EnabledQ[] が再試行可能になる。

## Routing 統合

### RoutingEnabledQ[] → Boolean
CLI = ClaudeQueryBg または API = iQueryViaAPI の少なくとも一方が呼び出し可能なら True。

### RoutingPreviewModel[role, model] → String | List
解決済み model spec (role-aware default lookup と qwen→$ClaudePrivateModel 展開後) を返す。role と model は省略可 (既定 "", Automatic)。

### RoutingGetInfo[role, model] → Association
`<|"Source"->str, "Path"->"CLI"|"API"|"Default", "Model"->resolved, "Role"->role, "QueryFunction"->fn|>`。role, model は省略可。

### RoutingListPaths[] → Association
セッションで利用可能な routing パスを示す Association。`<|"CLI"->Bool, "API"->Bool, "PrivateModel"->Bool, "RoleDefaults"->Bool|>`

## A4 Hook (low-level)

### A4InjectDirectivePrefix[prompt, role, model, goal] → String
directive prefix を prompt の前に prepend して返す。Directives 未配備時は passthrough。

### A4ResolveQueryFnForRole[queryFn, model, role] → Association
role / model に基づき queryFn (CLI または API closure) を解決。
→ `<|"QueryFunction"->fn, "Source"->str, "Path"->"CLI"|"API"|"Explicit"|"Empty", "Model"->resolved, "Role"->role|>`

### A4ResolveModelForRole[role, model] → String | List | Automatic
role と model spec から最終 model を解決。List 形式はそのまま、String はローカルモデル名なら $ClaudePrivateModel に展開、Automatic / None / "" は role 別 default。

例: 既存パイプラインで明示的 queryFn を渡さない場合
```
ClaudeOrchestrator`A4ResolveQueryFnForRole[Automatic, "qwen3.6-27b", "Verify"]
(* → API path に自動振り分け *)