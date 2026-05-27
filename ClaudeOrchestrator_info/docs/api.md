# ClaudeOrchestrator API リファレンス

Multi-Agent Orchestration Layer。ClaudeRuntime の上に乗り、タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit を提供する。

## バージョン

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン文字列。

## ロールと能力

### $ClaudeOrchestratorRoles
型: List, 値: {"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}
許容 Role のリスト。

### $ClaudeOrchestratorCapabilities
型: Association
Role -> Capability リストの Association。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head リスト (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential など)。

## Auto ゲート定数

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるテクニカルマーカーリスト (パッケージ名、関数名、拡張子等)。

### $ClaudeEvalAutoFactualEndings
型: List
Single フォールバック判定用の「調査・質問型」の語尾・フレーズリスト (「を調べて」「を教えて」check if compare 等)。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき「複雑タスク」識別マーカー (スライド・レポート・プレゼン・複数成果物要求など)。

## Planning

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ Association (<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...}|>)
Options: Planner -> Automatic (プランナー関数。Automatic は mock を使う), MaxTasks -> 10

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証し、<|"Valid"->True/False, "Errors"->{...}|> を返す。

## Spawn / Collect

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し、各 task の artifact を収集する。
→ Association (<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>)
Options: WorkerAdapterBuilder -> Automatic (Role -> TaskSpec を受け取り adapter を返す関数), MaxParallelism -> 1 (現状 1。Stage 2 以降で拡張)

### ClaudeCollectArtifacts[spawnResult] → Dataset
spawnResult["Artifacts"] を Dataset として返す。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証する。<|"Valid"->True/False, "Errors"->{...}|>

## Reduce

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し、中間成果物 (ReducedArtifact) を返す。
→ Association (<|"ArtifactType"->"Reduced", "Payload"->..., "Sources"->...|>)
Options: Reducer -> Automatic (artifacts を受け取り ReducedArtifact を返す関数)

## Commit

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し、reducedArtifact を target notebook に反映する。committer の HeldExpr 内の EvaluationNotebook[] / CreateNotebook[...] は targetNotebook に ReplaceAll で書換えられる。Transactional モードでは shadow buffer に書いてから verify / flush し、失敗時は target notebook を無変更のまま rollback する。
→ Association (<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->..., "Details"->...|>)
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" ("Direct" または "Transactional"), Verifier -> Automatic (fn[buffer, cells] -> True/False)

## 統合実行 (同期)

### ClaudeRunOrchestration[input, opts]
Planning -> Spawn -> Reduce -> (optional) Commit の全フェーズを直列に回す。
→ Association (4 フェーズの結果を束ねた Association)
Options: TargetNotebook -> None (Commit するなら指定), Planner -> Automatic, WorkerAdapterBuilder -> Automatic, Reducer -> Automatic, CommitterAdapterBuilder -> Automatic, MaxTasks -> 10, MaxParallelism -> 1, Confirm -> False

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま、batchInstructions に含まれる prompt を ClaudeContinueTurn で順次投入する。notebook 共有問題を回避する現実解。
→ List ({<|"Index"->i, "Prompt"->..., "Result"->...|>, ...})
Options: WaitBetween -> Quantity[1, "Seconds"]

## 非同期実行

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True
$ClaudeEvalHook が非同期経路 (ClaudeRunOrchestrationAsync) と同期経路 (ClaudeRunOrchestration) のどちらを使うかを制御する。False で旧同期挙動に戻る。

### ClaudeRunOrchestrationAsync[input, opts] → orchJobId
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し、orchJobId を即座に返す。フロントエンドをブロックしない。opts は ClaudeRunOrchestration と同じ。

### ClaudeOrchestrationStatus[orchJobId] → Association
orchestration ジョブの現在状態を返す。<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->..., "ElapsedSecs"->..., "PlanJobId"->..., "SpawnJobId"->...|>

### ClaudeOrchestrationResult[orchJobId] → Association | Missing
完了済み orchestration の最終結果 (ClaudeRunOrchestration と同形の Association) を返す。未完了なら Missing。

### ClaudeOrchestrationWait[orchJobId, timeoutSec] → Association
orchestration 完了まで待機する (テスト・スクリプト専用。対話セルでは使用を避ける)。既定タイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId] → Null
実行中の DAG を中止しレジストリから除去する。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧を Dataset で返す。

## Real LLM 統合

### $ClaudeOrchestratorRealLLMEndpoint
型: None | String | Function, 初期値: None
real LLM 統合エンドポイント設定。None (スキップ) / "ClaudeCode" (ClaudeQueryBg 同期版) / "CLI" (claude CLI を RunProcess) / fn[prompt] (カスタム関数)。環境変数 CLAUDE_ORCH_REAL_LLM でも opt-in 可能。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode で起動する実行ファイル名/フルパス。Automatic は OS に応じて "claude" (Unix) / "claude.cmd" (Windows)。環境変数 CLAUDE_ORCH_CLI_PATH でも上書き可能。

### ClaudeRealLLMAvailable[] → Boolean
real-LLM 統合が構成されているか返す。$ClaudeOrchestratorRealLLMEndpoint と環境変数 CLAUDE_ORCH_REAL_LLM をチェック。

### ClaudeRealLLMQuery[prompt] → String | $Failed
構成された real-LLM エンドポイントで prompt を実行。応答 String または $Failed。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し、診断情報 (endpoint / CLI パス / ExitCode / raw stdout / unwrap 結果 / JSON parse 可否) を Association で返す。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ、plan 結果と raw LLM 応答 head、task count、status、error 情報を Association で返す。

## サブモジュール有効化フラグ

### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True
Directives 統合モジュール有効化フラグ。BeginPackage 前に設定する。

### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True
Routing 統合モジュール有効化フラグ。

### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True
CommitSafety 統合モジュール有効化フラグ。

### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True
A4Stub 統合モジュール有効化フラグ。

## Directives API

### $DirectivesVersion
型: String
Directives 統合モジュールのバージョン文字列。

### $DirectivesVerbose
型: Boolean, 初期値: False
True で directive prefix 構築時に診断メッセージを出力。

### DirectivesEnabledQ[] → Boolean
ClaudeDirectives がロードされ、リポジトリも有効なら True。False は hook が passthrough であることを意味する。

### DirectivesPreviewPrefix[role, model, goal] → String
ClaudeInjectDirectivePrefix が prepend する directive prefix 文字列を、orchestrator hook を経由せず直接返す。デバッグ用。

### DirectivesSelected[role, model, goal] → Association
bundle の DirectiveMeta から選択された rule/skill を返す。<|"Rules"->{...}, "Skills"->{...}, "Mode"->..., "Tokens"->n, "Model"->...|>

### DirectivesResolveBundle[taskSpec, opts]
TaskSpec の "Role" / "Goal" / "DependsOn" / "Inputs" などから ClaudeDirectives bundle を解決する。
→ ClaudeDirectives bundle
Options: "Model" -> spec, "Mode" -> Automatic ("Full" | "Summary" | "Index" | "Lazy"), "TokenBudget" -> Automatic (Integer も可), "MaxSkills" -> Integer

### DirectivesInvalidateCache[] → Null
ClaudeDirectives リポジトリキャッシュを破棄し、次回呼び出しでディスクから再読み込みさせる。

### DirectivesNormalizeModel[modelSpec, role] → String
directive 投影に使う string モデル名を返す。String / List ({provider, model, url}) / Automatic / None を扱う。

### DirectivesAutoLoadStatus[] → String
直近の ClaudeDirectives リポジトリ auto-load 試行結果を記述する文字列を返す。EnabledQ[] が False を返す原因の診断に使う。

### DirectivesForceLoad[] / DirectivesForceLoad[path] → Boolean
ClaudeDirectives リポジトリのロードを再試行する (任意で特定 root path から)。auto-load 試行フラグをリセットして EnabledQ[] が再試行するようにする。

## Routing API (Phase A4.5)

### $RoutingVersion
型: String
Routing モジュールのバージョン文字列。

### $RoutingVerbose
型: Boolean, 初期値: False
True で ResolveQueryFnForRole 呼び出し時に診断メッセージを出力。

### RoutingEnabledQ[] → Boolean
少なくとも 1 つの query path (CLI = ClaudeQueryBg または API = iQueryViaAPI) が呼び出し可能なら True。

### RoutingPreviewModel[role, model] → spec
role-aware default lookup と qwen->$ClaudePrivateModel 展開後の resolved model spec を返す。引数省略可 (role:"", model:Automatic)。

### RoutingGetInfo[role, model] → Association
<|"Source"->str, "Path"->"CLI"|"API"|"Default", "Model"->resolved, "Role"->role, "QueryFunction"->fn|> を返す。

### RoutingListPaths[] → Association
現セッションで利用可能な routing path 一覧を返す。<|"CLI"->Bool, "API"->Bool, "PrivateModel"->Bool, "RoleDefaults"->Bool|>

## A4 Hook API

### $A4StubVersion
型: String
A4 hook stub のバージョン文字列。

### A4InjectDirectivePrefix[prompt, role, model, goal] → String
prompt に role/model/goal に応じた directive prefix を prepend する。ClaudeDirectives が未配備なら passthrough。

### A4ResolveQueryFnForRole[queryFn, model, role] → Association
queryFn / model / role から実行 queryFn を解決する。<|"QueryFunction"->fn, "Source"->..., "Path"->..., "Model"->..., "Role"->...|>

### A4ResolveModelForRole[role, model] → spec
role に応じた model spec を解決する。明示的 List / String はそのまま、Automatic / None は default 展開。

## CommitSafety

### $ClaudeCommitSafetyVersion
型: String
Phase A4.2 commit safety パッチのバージョン文字列。iDeterministicSlideCommit を override し、不十分なら iSmartPayloadCommit (payload を直接 Markdown 解析して Cell list を生成) に自動チェーンする 3rd-tier fallback を提供する。

## 例: 基本オーケストレーション

```mathematica
result = ClaudeRunOrchestration["プレゼン資料を作成", 
  TargetNotebook -> nb, MaxTasks -> 5];
```

## 例: 非同期オーケストレーション

```mathematica
jobId = ClaudeRunOrchestrationAsync["長時間タスク"];
ClaudeOrchestrationStatus[jobId]
(* ... 後ほど *)
ClaudeOrchestrationResult[jobId]
```

## 例: Directives bundle 解決

```mathematica
ClaudeOrchestrator`DirectivesResolveBundle[
  <|"Role" -> "Verify", "Goal" -> "コード品質チェック"|>,
  "Model" -> "qwen3.6-27b", "Mode" -> "Summary", "TokenBudget" -> 2000]
```

## 依存パッケージ

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — 単一エージェント実行核
- [claudecode](https://github.com/transreal/claudecode) — ClaudeBuildRuntimeAdapter / ClaudeQueryBg
- [NBAccess](https://github.com/transreal/NBAccess) — NBFileImport / NBFileExport (Commit phase)
- [claudecode_directives](https://github.com/transreal/claudecode_directives) — Directives bundle (optional)
- [ClaudeOrchestrator_observability](https://github.com/transreal/ClaudeOrchestrator_observability) — auto-load される observability 拡張
- [ClaudeOrchestrator_promptworkflow](https://github.com/transreal/ClaudeOrchestrator_promptworkflow) — auto-load される PromptWorkflow 拡張
- [ClaudeOrchestrator_workflow](https://github.com/transreal/ClaudeOrchestrator_workflow) — workflow engine