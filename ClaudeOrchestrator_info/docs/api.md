# ClaudeOrchestrator API リファレンス

ClaudeRuntime の上に乗る、タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit の機構。

## バージョン

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン文字列。

### ClaudeOrchestrator`$DirectivesVersion
型: String, 値: "v2026-04-26-phase-a4x-stage2-fix2"
Directives 統合モジュールのバージョン。

### ClaudeOrchestrator`$RoutingVersion
型: String, 値: "v2026-04-26-phase-a4-5-stage1"
Routing 統合モジュールのバージョン。

### ClaudeOrchestrator`$ClaudeCommitSafetyVersion
型: String, 値: "v2026-04-26-phase-a42-stage4-inlinecode"
CommitSafety パッチのバージョン。

### ClaudeOrchestrator`$A4StubVersion
型: String, 値: "v2026-04-26-phase-a44-stub"
A4 hook stub のバージョン。

## コア orchestration API

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {<|"TaskId"->_, "Role"->_, "Goal"->_, "Inputs"->_, "Outputs"->_, "Capabilities"->_, "DependsOn"->_, "ExpectedArtifactType"->_, "OutputSchema"->_|>, ...}|>`
Options: Planner -> Automatic (プランナー関数 fn または Automatic で mock), MaxTasks -> 10 (最大タスク数)

### ClaudeValidateTaskSpec[taskSpec]
TaskSpec の妥当性を検証する。
→ `<|"Valid"->True|False, "Errors"->{...}|>`

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し、各 task の artifact を収集する。
→ `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: WorkerAdapterBuilder -> Automatic (Role -> TaskSpec を受け取り adapter を返す関数), MaxParallelism -> 1 (Stage 2 以降で拡張)

### ClaudeCollectArtifacts[spawnResult]
spawnResult の Artifacts を Dataset として返す。
→ Dataset

### ClaudeValidateArtifact[artifact, outputSchema]
artifact の payload が OutputSchema を満たすか検証する。
→ `<|"Valid"->True|False, "Errors"->{...}|>`

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物 (ReducedArtifact) を返す。
→ `<|"ArtifactType"->"Reduced", "Payload"->_, "Sources"->_|>`
Options: Reducer -> Automatic (artifacts を受け取り ReducedArtifact を返す関数または Automatic)

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し、reducedArtifact を target notebook に反映する。committer の HeldExpr 内の EvaluationNotebook[] / CreateNotebook[...] 参照は targetNotebook に ReplaceAll で書換えられる。
→ `<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->_, "Details"->_|>`
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" ("Direct" | "Transactional"), Verifier -> Automatic (fn[buffer, cells] -> True/False)

### ClaudeRunOrchestration[input, opts]
Planning -> Spawn -> Reduce -> (optional) Commit の全フェーズを直列実行する。
→ 4 フェーズの結果を束ねた Association
Options: TargetNotebook -> None (Commit するなら指定), Planner -> Automatic, WorkerAdapterBuilder -> Automatic, Reducer -> Automatic, CommitterAdapterBuilder -> Automatic, MaxTasks -> 10, MaxParallelism -> 1, Confirm -> False

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま batchInstructions の prompt を ClaudeContinueTurn で順次投入する。notebook 共有問題を回避する現実解。
→ `{<|"Index"->i, "Prompt"->_, "Result"->_|>, ...}`
Options: WaitBetween -> Quantity[1, "Seconds"] (各投入の間隔)

## 非同期 orchestration API

### ClaudeRunOrchestrationAsync[input, opts]
Plan -> Spawn -> Reduce -> Commit を DAG コールバックチェーンで非同期実行し、orchJobId を即座に返す。フロントエンドをブロックしない。
→ orchJobId
Options: ClaudeRunOrchestration と同じ

### ClaudeOrchestrationStatus[orchJobId]
orchestration ジョブの現在状態を返す。
→ `<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->_, "ElapsedSecs"->_, "PlanJobId"->_, "SpawnJobId"->_|>`

### ClaudeOrchestrationResult[orchJobId]
完了済み orchestration の最終結果 (ClaudeRunOrchestration と同形の Association) を返す。未完了なら Missing。
→ Association | Missing

### ClaudeOrchestrationWait[orchJobId, timeoutSec]
orchestration 完了まで待機する。テスト・スクリプト専用。対話セルでは避ける。timeoutSec の既定は 300 秒。
→ Association | $Failed

### ClaudeOrchestrationCancel[orchJobId]
実行中の DAG を中止しレジストリから除去する。
→ True | False

### ClaudeOrchestrationJobs[]
現在追跡中の orchestration ジョブ一覧を Dataset で返す。
→ Dataset

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True
$ClaudeEvalHook が非同期経路 (ClaudeRunOrchestrationAsync) と同期経路 (ClaudeRunOrchestration) のどちらを使うかを制御する。False にすると旧同期挙動。

## Role / Capability 定数

### $ClaudeOrchestratorRoles
型: List, 値: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`
許容 Role リスト。

### $ClaudeOrchestratorCapabilities
型: Association
Role -> Capability リストの対応表。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential など)。

## Auto ゲートフィルタ定数 (Phase 32 Task 3.2)

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるテクニカルマーカー (パッケージ名・関数名・拡張子等)。

### $ClaudeEvalAutoFactualEndings
型: List
Auto モードで Single フォールバックさせる「調査・質問型」の語尾・フレーズ (「を調べて」「を教えて」"check" "compare" 等)。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき「複雑タスク」を識別するマーカー (スライド・レポート・プレゼン・複数成果物要求など)。

## Real LLM 統合

### $ClaudeOrchestratorRealLLMEndpoint
型: None | "ClaudeCode" | "CLI" | Function, 初期値: None
real LLM 統合の選択。None でスキップ、"ClaudeCode" で ClaudeCode`ClaudeQueryBg、"CLI" で claude CLI を RunProcess 呼び出し、fn[prompt] でカスタム関数。環境変数 CLAUDE_ORCH_REAL_LLM でも opt-in 可。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode で起動する実行ファイル名/フルパス。Automatic では OS に応じて "claude" (Unix) / "claude.cmd" (Windows)。環境変数 CLAUDE_ORCH_CLI_PATH でも上書き可。

### ClaudeRealLLMAvailable[]
real LLM 統合が設定されているか判定する。
→ True | False

### ClaudeRealLLMQuery[prompt]
設定された real LLM endpoint で prompt を実行する。
→ String | $Failed

### ClaudeRealLLMDiagnose[prompt]
real LLM 呼び出しを実行し診断情報 (endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否) を返す。
→ Association

### ClaudeRealLLMDiagnosePlan[input]
実 LLM planner パイプラインを走らせ、plan 結果と raw LLM 応答 head・task count・status・error 情報を返す。
→ Association

## 統合サブモジュール有効化フラグ

### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True
Directives 統合の有効化フラグ。

### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True
Routing 統合の有効化フラグ。

### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True
CommitSafety 拡張の有効化フラグ。

### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True
A4 hook stub の有効化フラグ。

## Directives 統合 API

### ClaudeOrchestrator`DirectivesEnabledQ[]
ClaudeDirectives がロード済みかつリポジトリ利用可能なら True。False なら hook は passthrough。
→ True | False

### ClaudeOrchestrator`DirectivesPreviewPrefix[role, model, goal]
ClaudeInjectDirectivePrefix が prepend する directive prefix 文字列を hook を経由せずに返す。デバッグ用。
→ String

### ClaudeOrchestrator`DirectivesSelected[role, model, goal]
bundle の DirectiveMeta から選択された rule/skill 一覧などを返す。
→ `<|"Rules"->{...names...}, "Skills"->{...names...}, "Mode"->_, "Tokens"->_, "Model"->_|>`

### ClaudeOrchestrator`DirectivesResolveBundle[taskSpec, opts]
TaskSpec から ClaudeDirectives bundle を解決する。Role / Goal / Inputs / DependsOn を読み ClaudeResolveDirectiveBundle にブリッジする。
→ Association
Options: "Model" -> spec, "Mode" -> Automatic ("Full"|"Summary"|"Index"|"Lazy"), "TokenBudget" -> Automatic | Integer, "MaxSkills" -> Integer

### ClaudeOrchestrator`DirectivesInvalidateCache[]
ClaudeDirectives のリポジトリキャッシュを破棄し、次回呼び出しでディスクから再ロードさせる。
→ Null

### ClaudeOrchestrator`DirectivesNormalizeModel[modelSpec, role]
directive projection に使う文字列モデル名を返す。String / List ({provider, model, url}) / Automatic / None を扱う。
→ String

### ClaudeOrchestrator`DirectivesAutoLoadStatus[]
直近の ClaudeDirectives リポジトリ自動ロード試行の結果文字列を返す。EnabledQ[] が False の理由切り分けに使う。
→ String

### ClaudeOrchestrator`DirectivesForceLoad[]
### ClaudeOrchestrator`DirectivesForceLoad[path]
ClaudeDirectives リポジトリのロードを再試行する。path 指定でルートを明示可能。自動ロード試行フラグをリセットする。
→ True | False

### ClaudeOrchestrator`$DirectivesVerbose
型: Boolean, 初期値: False
True で directive prefix 構築時に診断メッセージを出力する。

## Routing 統合 API (Phase A4.5)

### ClaudeOrchestrator`RoutingEnabledQ[]
CLI (ClaudeQueryBg) または API (iQueryViaAPI) のいずれかが呼び出し可能なら True。
→ True | False

### ClaudeOrchestrator`RoutingPreviewModel[role, model]
role-aware default lookup と qwen->$ClaudePrivateModel 展開を施した解決済みモデルスペックを返す。
→ String | List
既定: role -> "", model -> Automatic

### ClaudeOrchestrator`RoutingGetInfo[role, model]
routing の解決結果を返す。
→ `<|"Source"->_, "Path"->"CLI"|"API"|"Default"|"Explicit"|"Empty", "Model"->_, "Role"->_, "QueryFunction"->fn|>`
既定: role -> "", model -> Automatic

### ClaudeOrchestrator`RoutingListPaths[]
現在のセッションで利用可能な routing 経路を Association で返す。
→ `<|"CLI"->_, "API"->_, "PrivateModel"->_, "RoleDefaults"->_|>`

### ClaudeOrchestrator`$RoutingVerbose
型: Boolean, 初期値: False
True で ClaudeResolveQueryFnForRole 呼び出しごとに診断メッセージを出力する。

## A4 Hook API

### ClaudeOrchestrator`A4InjectDirectivePrefix[prompt, role, model, goal]
worker prompt の前に role/model/goal に応じた directive prefix を prepend する。ClaudeDirectives 未配備時は passthrough。
→ String

### ClaudeOrchestrator`A4ResolveQueryFnForRole[queryFn, model, role]
role/model から実行する queryFn を解決する。明示的 queryFn は respect、Automatic なら role-aware model 解決を経て CLI/API の closure を構築する。
→ `<|"QueryFunction"->fn, "Source"->_, "Path"->"CLI"|"API"|"Explicit"|"Empty", "Model"->_, "Role"->_|>`

### ClaudeOrchestrator`A4ResolveModelForRole[role, model]
role に応じてモデルを解決する。明示 List/String はそのまま (qwen 系は $ClaudePrivateModel に展開)、Automatic/None は role 別 default を引く。
→ String | List | Automatic