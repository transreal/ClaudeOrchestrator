# ClaudeOrchestrator API リファレンス

LLM 向け API 仕様。ClaudeRuntime の上に乗る multi-agent orchestration 層。

## バージョン

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン。

### ClaudeOrchestrator\`$DirectivesVersion
型: String, 初期値: "v2026-04-26-phase-a4x-stage2-fix2"
Directives 統合モジュールのバージョン。

### ClaudeOrchestrator\`$RoutingVersion
型: String, 初期値: "v2026-04-26-phase-a4-5-stage1"
Routing 統合モジュールのバージョン。

### ClaudeOrchestrator\`$ClaudeCommitSafetyVersion
型: String, 初期値: "v2026-04-26-phase-a42-stage4-inlinecode"
CommitSafety 統合モジュールのバージョン。

### ClaudeOrchestrator\`$A4StubVersion
型: String, 初期値: "v2026-04-26-phase-a44-stub"
A4 hook stub のバージョン。

## Orchestration コア API

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...}|>`
Options: Planner -> Automatic (プランナー関数、mock fallback), MaxTasks -> 10 (最大タスク数)

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証。`<|"Valid"->True/False, "Errors"->{...}|>` を返す。

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し artifact を収集する。
→ `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: WorkerAdapterBuilder -> Automatic (Role -> TaskSpec から adapter を返す関数), MaxParallelism -> 1 (現状 1、Stage 2 以降で拡張)

### ClaudeCollectArtifacts[spawnResult] → Dataset
spawnResult["Artifacts"] を Dataset として返す。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証。`<|"Valid"->True/False, "Errors"->{...}|>` を返す。

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し ReducedArtifact を返す。
→ `<|"ArtifactType"->"Reduced", "Payload"->..., "Sources"->...|>`
Options: Reducer -> Automatic (artifacts を受け取り ReducedArtifact を返す関数)

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime で reducedArtifact を target notebook に反映。committer の HeldExpr は EvaluationNotebook[] / CreateNotebook[...] が targetNotebook に ReplaceAll で書換えられる。
→ `<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->..., "Details"->...|>`
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" ("Direct" | "Transactional"), Verifier -> Automatic (fn[buffer, cells] -> True/False)
Transactional モードでは shadow buffer に書いてから verify / flush し、失敗時は target notebook を無変更のまま rollback する。

### ClaudeRunOrchestration[input, opts]
Planning → Spawn → Reduce → (optional) Commit を直列に回す。
→ 4 フェーズの結果を束ねた Association
Options: TargetNotebook -> None (Commit するなら指定), Planner -> Automatic, WorkerAdapterBuilder -> Automatic, Reducer -> Automatic, CommitterAdapterBuilder -> Automatic, MaxTasks -> 10, MaxParallelism -> 1, Confirm -> False

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッション維持のまま batchInstructions の prompt を ClaudeContinueTurn で順次投入。notebook 共有問題の現実解。
→ `{<|"Index"->i, "Prompt"->..., "Result"->...|>, ...}`
Options: WaitBetween -> Quantity[1, "Seconds"]

## Async Orchestration API

### ClaudeRunOrchestrationAsync[input, opts] → String
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行。orchJobId を即座に返す。フロントエンドをブロックしない。opts は ClaudeRunOrchestration と同じ。

### ClaudeOrchestrationStatus[orchJobId] → Association
orchestration ジョブの現在状態。`<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->..., "ElapsedSecs"->..., "PlanJobId"->..., "SpawnJobId"->...|>`

### ClaudeOrchestrationResult[orchJobId] → Association | Missing
完了済み orchestration の最終結果。未完了なら Missing を返す。

### ClaudeOrchestrationWait[orchJobId, timeoutSec] → Association
orchestration 完了まで待機 (テスト・スクリプト専用、対話セルでは避ける)。既定タイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId] → Null
実行中の DAG を中止しレジストリから除去する。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧。

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True
$ClaudeEvalHook が非同期経路 (ClaudeRunOrchestrationAsync) と同期経路 (ClaudeRunOrchestration) のどちらを使うかを制御。False で旧同期挙動。

## Role / Capability 定数

### $ClaudeOrchestratorRoles
型: List, 初期値: {"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}
許容 Role のリスト。

### $ClaudeOrchestratorCapabilities
型: Association
Role -> Capability リストの Association。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential など)。

## Auto ゲート定数 (Phase 32 Task 3.2)

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるためのテクニカルマーカーリスト (パッケージ名、関数名、拡張子等)。プロンプトに含まれかつタスクが 300 文字未満・複雑さ指標なしの場合、Orchestrator 経路を通らず Single パスで処理される。ユーザはリストを拡張して特有名称を追加可能。

### $ClaudeEvalAutoFactualEndings
型: List
Auto モードで Single フォールバックさせるための「調査・質問型」の語尾・フレーズリスト「を調べて」「を教えて」check if compare 等。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき「複雑タスク」を識別するマーカーリスト。スライド・レポート・プレゼン・複数の成果物要求などが含まれる。短いタスクでも Orchestrator 経路を通すようになる。

## Real LLM 統合

### $ClaudeOrchestratorRealLLMEndpoint
型: None | String | Function, 初期値: None
real LLM endpoint 設定:
- None (既定): 統合テストをスキップ
- "ClaudeCode": ClaudeCode\`ClaudeQueryBg (同期版) を使う
- "CLI": claude CLI を RunProcess で呼ぶ
- fn[prompt]: カスタム関数

環境変数 CLAUDE_ORCH_REAL_LLM でも opt-in 可。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode で起動する実行ファイル名/フルパス。Automatic で OS 別 ("claude" / "claude.cmd")。環境変数 CLAUDE_ORCH_CLI_PATH で上書き可。

### ClaudeRealLLMAvailable[] → Boolean
real-LLM 統合が設定済みなら True。$ClaudeOrchestratorRealLLMEndpoint と env CLAUDE_ORCH_REAL_LLM を見る。

### ClaudeRealLLMQuery[prompt] → String | $Failed
設定済み real-LLM endpoint で prompt を実行し response を返す。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し診断情報を返す (endpoint, CLI パス, ExitCode, raw stdout, unwrap 結果, JSON parse 可否)。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ、plan 結果、raw LLM 応答 head、 task count、status、error 情報を返す。

## Directives 統合 (Phase 34 A4.x Stage 2)

### ClaudeOrchestrator\`DirectivesEnabledQ[] → Boolean
ClaudeDirectives がロードされリポジトリが利用可能なら True。False で hook は passthrough。

### ClaudeOrchestrator\`DirectivesPreviewPrefix[role, model, goal] → String
ClaudeInjectDirectivePrefix が prepend する directive prefix を hook を介さず取得 (デバッグ用)。

### ClaudeOrchestrator\`DirectivesSelected[role, model, goal] → Association
bundle の DirectiveMeta から `<|"Rules"->{...}, "Skills"->{...}, "Mode"->modeStr, "Tokens"->n, "Model"->resolvedModelStr|>` を返す。

### ClaudeOrchestrator\`DirectivesResolveBundle[taskSpec, opts]
TaskSpec から ClaudeDirectives bundle を解決する。Role / Goal / Inputs / DependsOn から bridges。
→ bundle Association
Options: "Model" -> spec, "Mode" -> Automatic ("Automatic"|"Full"|"Summary"|"Index"|"Lazy"), "TokenBudget" -> Automatic (Integer|Automatic), "MaxSkills" -> Integer

### ClaudeOrchestrator\`DirectivesInvalidateCache[] → Null
キャッシュ済み ClaudeDirectives リポジトリを破棄し再ロードを強制。

### ClaudeOrchestrator\`DirectivesNormalizeModel[modelSpec, role] → String
String / List ({provider, model, url}) / Automatic / None を統一して文字列モデル名へ正規化。

### ClaudeOrchestrator\`DirectivesAutoLoadStatus[] → String
最近の ClaudeDirectives リポジトリ自動ロード試行結果を記述する文字列。EnabledQ[] が False を返す原因の診断用。

### ClaudeOrchestrator\`DirectivesForceLoad[] / [path]
ClaudeDirectives リポジトリの再ロードを試行する (path 省略で既定パス)。auto-load 試行フラグをリセットし EnabledQ[] が再試行するようにする。
→ Boolean (成功時 True)

### ClaudeOrchestrator\`$DirectivesVerbose
型: Boolean, 初期値: False
True にすると directive prefix 構築のたびに診断メッセージを出力する。

## Routing 統合 (Phase 34 A4.5)

### ClaudeOrchestrator\`RoutingEnabledQ[] → Boolean
少なくとも 1 つの query path (CLI = ClaudeQueryBg または API = iQueryViaAPI) が呼び出し可能なら True。

### ClaudeOrchestrator\`RoutingPreviewModel[role, model] → spec
role-aware default lookup と qwen→$ClaudePrivateModel expansion 後の解決済み model spec を返す。引数省略可 ([] / [role]) で既定値は role="", model=Automatic。

### ClaudeOrchestrator\`RoutingGetInfo[role, model] → Association
`<|"Source"->str, "Path"->"CLI"|"API"|"Default", "Model"->resolved, "Role"->role, "QueryFunction"->fn|>` を返す。

### ClaudeOrchestrator\`RoutingListPaths[] → Association
利用可能 routing パスを示す `<|"CLI"->Boolean, "API"->Boolean, "PrivateModel"->Boolean, "RoleDefaults"->Boolean|>`。

### ClaudeOrchestrator\`$RoutingVerbose
型: Boolean, 初期値: False
True にすると ClaudeResolveQueryFnForRole 呼び出しごとに診断メッセージを出力。

## A4 Hook API

### ClaudeOrchestrator\`A4ResolveQueryFnForRole[queryFn, model, role] → Association
role / model に応じた queryFn を解決。
→ `<|"QueryFunction"->fn, "Source"->str, "Path"->"CLI"|"API"|"Empty"|"Explicit", "Model"->resolved, "Role"->role|>`
動作:
- 明示的 queryFn (Symbol/Function) → passthrough
- List spec ({prov, model, url}) かつ API 可 → API queryFn 構築
- "qwen*"/"llama*"/"mistral*"/"phi-*"/"deepseek*"/"gemma*" 文字列 → $ClaudePrivateModel に展開し API 経路
- それ以外 → CLI 経路 (Model オプションは渡さない、CLI default 使用)
- いずれも不可 → empty fn (空文字列を返す)

### ClaudeOrchestrator\`A4ResolveModelForRole[role, model] → spec
role / model を解決し String または List ({prov, model, url}) を返す。Automatic/None/"" は role 別 default ($ClaudeRoleDefaultModels) を引く。

### ClaudeOrchestrator\`A4InjectDirectivePrefix[prompt, role, model, goal] → String
directive prefix を prompt の前に prepend する。ClaudeDirectives 未配備なら passthrough (prompt をそのまま返す)。失敗時もユーザー副作用なし。

## 機能オン/オフフラグ

### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True
Directives 統合モジュールの有効化。BeginPackage より前に設定する必要あり。

### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True
Routing 統合モジュールの有効化。

### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True
CommitSafety 統合 (3rd-tier commit fallback) の有効化。

### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True
A4Stub (hook 最小実装) の有効化。Directives / Routing が本格実装で上書きする。

## TaskSpec データ構造

TaskSpec Association キー:
- "TaskId" → String (一意 ID)
- "Role" → String ($ClaudeOrchestratorRoles のいずれか)
- "Goal" → String (タスクの目的)
- "Inputs" → List (入力 artifact ID リスト)
- "Outputs" → List (出力 artifact ID リスト)
- "Capabilities" → List (許可される tool capability)
- "DependsOn" → List (依存 TaskId リスト)
- "ExpectedArtifactType" → String (期待される artifact 型)
- "OutputSchema" → Association (payload schema)

## Artifact データ構造

Artifact Association キー:
- "ArtifactType" → String
- "Payload" → Any (OutputSchema 準拠)
- "Sources" → List (生成元 TaskId)
- "TaskId" → String (生成元タスク)

## 使用パターン例

非同期 orchestration の典型フロー:

```
jobId = ClaudeRunOrchestrationAsync["スライドを作成", TargetNotebook -> nb];
While[ClaudeOrchestrationStatus[jobId]["Status"] =!= "Done",
  Pause[1]];
result = ClaudeOrchestrationResult[jobId]
```

Routing 経路の確認:

```
ClaudeOrchestrator`RoutingGetInfo["Verify", "qwen3.6-27b"]
(* → <|"QueryFunction"->fn, "Path"->"API", "Model"->{"lmstudio",...}, ...|> *)
```

CommitArtifacts の Transactional モード:

```
ClaudeCommitArtifacts[nb, reduced,
  CommitMode -> "Transactional",
  Verifier -> Function[{buf, cells}, Length[cells] >= 3]]