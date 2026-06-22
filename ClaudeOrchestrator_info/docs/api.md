# ClaudeOrchestrator API リファレンス

ClaudeRuntime (単一エージェント実行核) の上に乗る、タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit の多エージェントオーケストレーション層。

設計上の不変条件: (1) ClaudeRuntime は 1 agent kernel のまま、(2) 並列 worker は artifact producer 限定 (NotebookWrite 禁止)、(3) 実 notebook への書き込みは single committer のみ、(4) worker 間共有は明示的 artifact/JSON/Association のみ、(5) EvaluationNotebook[] / CreateNotebook[] は deny。

依存: [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime), [claudecode](https://github.com/transreal/claudecode), [NBAccess](https://github.com/transreal/NBAccess) (file_contents handler から NBFileImport/NBFileExport を弱呼び出し)。
companion 自動ロード (3): [ClaudeOrchestrator_workflow](https://github.com/transreal/ClaudeOrchestrator_workflow), [ClaudeOrchestrator_observability](https://github.com/transreal/ClaudeOrchestrator_observability), [ClaudeOrchestrator_promptworkflow](https://github.com/transreal/ClaudeOrchestrator_promptworkflow)。※ `ClaudeOrchestrator_stategraph` は deprecated で既定ロードなし (`$ClaudeOrchestratorEnableStateGraphCompat = True` でオプトイン可)。

ロード: `Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]`

## TaskSpec / Artifact データ構造
TaskSpec (Association): `"TaskId"`, `"Role"`, `"Goal"`, `"Inputs"`, `"Outputs"`, `"Capabilities"`, `"DependsOn"`, `"ExpectedArtifactType"`, `"OutputSchema"`。
Artifact (Association): `"ArtifactType"`, `"Payload"` (内部に `"HeldExpr"` を持ちうる), `"Sources"` など。Role は `$ClaudeOrchestratorRoles` の値。

## Planning フェーズ
### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {taskSpec, ...}|>`
Options: Planner -> Automatic (プランナー関数 fn、Automatic は mock), MaxTasks -> 10

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証。→ `<|"Valid"->True/False, "Errors"->{...}|>`

## Spawn / Artifact フェーズ
### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し各 task の artifact を収集 (直列/順次)。
→ `<|"Artifacts"-><|taskId->artifact,...|>, "Failures"->{...}, "Status"->"Complete"|"Partial"|"Failed"|>`
Options: WorkerAdapterBuilder -> fn (Role->TaskSpec を受け adapter を返す), MaxParallelism -> 1 (現状 1)

### ClaudeCollectArtifacts[spawnResult] → Dataset
spawnResult["Artifacts"] を Dataset として返す (ノートブック確認用)。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証。→ `<|"Valid"->True/False, "Errors"->{...}|>`

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物 (ReducedArtifact) を返す。
→ `<|"ArtifactType"->"Reduced", "Payload"->..., "Sources"->...|>`
Options: Reducer -> Automatic (artifacts を受け ReducedArtifact を返す fn、または Automatic)

## Commit フェーズ
### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し reducedArtifact を target notebook に反映。committer の HeldExpr 内 EvaluationNotebook[]/CreateNotebook[] 参照は targetNotebook へ ReplaceAll で書換えられる。
→ `<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->..., "Details"->...|>`
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" ("Transactional" は shadow buffer に書いて verify/flush、失敗時 target 無変更で rollback), Verifier -> Automatic (fn[buffer, cells] -> True/False)

## オーケストレーション (同期)
### ClaudeRunOrchestration[input, opts]
Planning -> Spawn -> Reduce -> (optional) Commit の全フェーズを直列実行。
→ 4 フェーズの結果を束ねた Association
Options: TargetNotebook -> (Commit するなら指定), Planner, WorkerAdapterBuilder, Reducer, CommitterAdapterBuilder, MaxTasks, MaxParallelism, Confirm -> False
例: `ClaudeRunOrchestration["スライド3枚生成", TargetNotebook -> nb, MaxTasks -> 5]`

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま batchInstructions の prompt を ClaudeContinueTurn で順次投入 (notebook 共有問題回避の現実解)。
→ `{<|"Index"->i, "Prompt"->..., "Result"->...|>, ...}`
Options: WaitBetween -> Quantity[1, "Seconds"]

## オーケストレーション (非同期)
### ClaudeRunOrchestrationAsync[input, opts]
Plan->Spawn->Reduce->Commit を DAG コールバックチェーンで非同期実行し orchJobId を即座に返す (フロントエンドをブロックしない)。opts は ClaudeRunOrchestration と同じ。
→ orchJobId

### ClaudeOrchestrationStatus[orchJobId] → Association
ジョブの現在状態。→ `<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->..., "ElapsedSecs"->..., "PlanJobId"->..., "SpawnJobId"->...|>`

### ClaudeOrchestrationResult[orchJobId] → Association | Missing
完了済みジョブの最終結果 (ClaudeRunOrchestration と同形)。未完了なら Missing。

### ClaudeOrchestrationWait[orchJobId, timeoutSec] → Association
完了まで待機 (テスト/スクリプト専用、対話セルでは避ける)。timeoutSec 既定 300。

### ClaudeOrchestrationCancel[orchJobId]
実行中 DAG を中止しレジストリから除去。

### ClaudeOrchestrationJobs[] → Dataset
追跡中の orchestration ジョブ一覧。

### $ClaudeOrchestratorAsyncMode
型: True/False, 初期値: True
$ClaudeEvalHook が非同期 (ClaudeRunOrchestrationAsync) と同期 (ClaudeRunOrchestration) のどちらを使うかを制御。False で旧同期挙動。

## Final Action 分離 (spec I11 / 罠 #30)
desktop/FrontEnd 操作 (SystemOpen 等) は scheduled task では効かないため、final action を分離しユーザーのメインカーネル評価で実行する。

### ClaudeOrchestratorClassifyArtifactActions[artifacts, accessSpec] → Association
各 artifact の HeldExpr を NBValidateHeldExpr で判定し safe computation node と final action node に振り分ける。artifacts は taskId->artifact の Association または artifact の List。HeldExpr/Payload["HeldExpr"] 無しは Safe 扱い。
→ `<|"Safe"->{...}, "Final"->{...}, "Diagnostics"->{...}|>`
各 Final 要素: `<|"TaskId", "Artifact", "Validation", "ExecutionPlacement", "BlockingRisk", "EffectClass", "Decision"|>`

### ClaudeOrchestratorExtractFinalActions[orchestrationResult, accessSpec] → Association
ClaudeRunOrchestration 結果から RequiresFinalNode な action を分離。元 result に `"FinalActions"`/`"SafeArtifacts"`/`"HasFinalActions"` を加えた Association。final action は自動実行せず承認後にメインカーネル評価で実行する前提。

### ClaudeOrchestrationShowFinalActions[orchJobId] → Integer
async orchestration 完了後、分離された final action を承認ボタンセルとして notebook に提示。必ずユーザーのメインカーネル評価で呼ぶこと (scheduled task から呼ぶと SystemOpen/notebook 書込が無反応)。ボタン本体 (Method->Queued) 押下時に初めて SystemOpen 実行。→ 提示件数。

### ClaudeOrchestratorPresentFinalActions[finalActions, accessSpec, opts] → Association
分離済み final action を承認 UI 提示形に整える。
→ `<|"Mode", "Items"->{...}, "Count"|>`
Options: Mode -> "Present" (UI 用 record を返すのみ) | "Enqueue" (NBEnqueueFinalAction で queue 化し AsyncActive 解除後の実行に委ねる)

## Real LLM 統合
### ClaudeRealLLMAvailable[] → True/False
real-LLM 統合が構成済みか ($ClaudeOrchestratorRealLLMEndpoint と env CLAUDE_ORCH_REAL_LLM をチェック)。

### ClaudeRealLLMQuery[prompt] → String | $Failed
構成済み endpoint に prompt を投げ応答 String を返す。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し診断情報 (endpoint/CLI パス/ExitCode/raw stdout/unwrap 結果/JSON parse 可否) を返す。W1-W3 失敗の切り分け用。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ、plan 結果・raw LLM 応答 head・task count・status・error 情報を返す。W1 失敗切り分け用。

## Artifact deposit / handler 登録
### ClaudeOrchestratorDepositArtifacts[artifacts, opts] → Association
worker 成果物 (taskId->artifact の Association) をメインカーネル (単一書き手) から SourceVault へ append-only deposit し各 sv://artifact/.. URI を返す。SourceVault`SourceVaultMCPDeposit を弱呼び出し、未ロードなら Status->Skipped。認可は provider 'orchestrator-worker' の AccessProfile 経由。
→ `<|Status, Deposits (taskId-><|Status, URI, Detail|>), URIs|>`
Options: "Provider"->"orchestrator-worker", "ModelId"->"worker", "SessionId"->Automatic, "PrivacyLevel"->Automatic, "Mode"->"commit"

### ClaudeWorkflowRegisterHandler[functionId, spec] → Association
非SourceVault callable を Orchestrator 所有の handler allowlist に登録 (SourceVault PromptRouter の拡張点)。同一 functionId は置換。→ 登録エントリ。
spec keys: "Symbol" (必須・評価しないシンボル), "UseAsFunctionRoute" (既定 True), "UseAsHandlerRef" (既定 True), "SideEffectClass" ("ReadOnly"|"SafeCreate"|.. 既定 "ReadOnly"), "OwnerPackage" (String)

### ClaudeWorkflowHandlerAllowlist[] → Association
登録済み handler allowlist (FunctionId -> エントリ)。空なら `<||>`。

### $ClaudeWorkflowHandlerRegistry
型: Association (FunctionId -> エントリ)
登録済み handler。Get 再ロードでも保持 (未設定時のみ初期化)。

## Directives 統合 (ClaudeOrchestrator` 名前空間)
worker prompt 前置 (= LLM に何を読ませるか) を扱う。[claudecode_directives](https://github.com/transreal/claudecode_directives) 連携。未ロード/repository 未読込なら passthrough。

### ClaudeOrchestrator`DirectivesEnabledQ[] → True/False
ClaudeDirectives がロードされ repository も読込済みなら True。False なら hook は passthrough。

### ClaudeOrchestrator`DirectivesPreviewPrefix[role, model, goal] → String
hook を介さず directive prefix 文字列を直接取得 (デバッグ用)。

### ClaudeOrchestrator`DirectivesSelected[role, model, goal] → Association
bundle の DirectiveMeta から選択結果を返す。→ `<|"Rules"->{...}, "Skills"->{...}, "Mode"->modeStr, "Tokens"->n, "Model"->resolvedModelStr|>`

### ClaudeOrchestrator`DirectivesResolveBundle[taskSpec, opts] → bundle
TaskSpec の Role/Goal/Inputs/DependsOn から ClaudeDirectives bundle を解決。
Options: "Model" -> spec, "Mode" -> Automatic|"Full"|"Summary"|"Index"|"Lazy", "TokenBudget" -> Integer|Automatic, "MaxSkills" -> Integer

### ClaudeOrchestrator`DirectivesNormalizeModel[modelSpec, role] → String
directive projection 用のモデル名文字列を返す。String / List ({provider,model,url}) / Automatic / None を処理。

### ClaudeOrchestrator`DirectivesInvalidateCache[]
キャッシュ済み ClaudeDirectives repository を破棄し次回ディスク再読込。

### ClaudeOrchestrator`DirectivesAutoLoadStatus[] → String
直近の repository auto-load 試行結果の説明文字列。EnabledQ[] が False の診断用。

### ClaudeOrchestrator`DirectivesForceLoad[] / [path]
repository 読込を再試行 (path 指定可)。auto-load フラグをリセットし EnabledQ[] を再試行させる。

### ClaudeOrchestrator`$DirectivesVerbose
型: True/False, 初期値: False
True で directive prefix 構築のたびに診断出力。

## Routing 統合 (ClaudeOrchestrator` 名前空間)
queryFn 振り分け (= どの LLM が走るか) を扱う。CLI = ClaudeQueryBg / API = iQueryViaAPI。Model spec: String "claude-*" -> CLI、ローカル名 "qwen.."/"llama.."/"mistral.."/"phi-.."/"deepseek.."/"gemma.." -> $ClaudePrivateModel に展開して API、List {prov,model,url} -> API、Automatic+role -> role 別 default。

### ClaudeOrchestrator`RoutingEnabledQ[] → True/False
CLI または API の少なくとも一方が呼び出し可能なら True。

### ClaudeOrchestrator`RoutingPreviewModel[role, model] → spec
role-aware default lookup と qwen->$ClaudePrivateModel 展開後の解決済み model spec。引数省略時 role:"", model:Automatic。

### ClaudeOrchestrator`RoutingGetInfo[role, model] → Association
→ `<|"Source"->str, "Path"->"CLI"|"API"|"Explicit"|"Empty", "Model"->resolved, "Role"->role, "QueryFunction"->fn|>`

### ClaudeOrchestrator`RoutingListPaths[] → Association
利用可能な routing path。→ `<|"CLI"->bool, "API"->bool, "PrivateModel"->bool, "RoleDefaults"->bool|>`

### ClaudeOrchestrator`$RoutingVerbose
型: True/False, 初期値: False
True で ResolveQueryFnForRole 呼出のたびに診断出力。

## A4 hook (ClaudeOrchestrator` 名前空間)
Directives/Routing が本格実装で再定義する低レベル hook。

### ClaudeOrchestrator`A4InjectDirectivePrefix[prompt, role, model, goal] → String
prompt に directive prefix を前置 (Directives 未ロード時 passthrough)。

### ClaudeOrchestrator`A4ResolveQueryFnForRole[queryFn, model, role] → Association
queryFn が明示なら respect、Automatic なら role/model から CLI/API closure を構築。→ `<|"QueryFunction"->fn, "Source"->str, "Path"->..., "Model"->resolved, "Role"->role|>`

### ClaudeOrchestrator`A4ResolveModelForRole[role, model] → spec
role に応じた model 解決 (iResolveModelInternal)。

## CommitSafety 統合
LLM-backed commit と iDeterministicSlideCommit がいずれも失敗/不十分時の 3rd-tier fallback。payload を Markdown 解析して Cell list を生成し target notebook へ書込む (Title->Section, Summary/Description->Text, Code->Input, KeyPoints->ItemParagraph, heading->Section/Subsection, bullet->ItemParagraph)。

### ClaudeOrchestrator`$ClaudeCommitSafetyVersion
型: String。commit safety パッチのバージョン文字列。

## 変数・定数
### $ClaudeOrchestratorVersion
型: String — パッケージバージョン。

### $ClaudeOrchestratorRoles
型: List — 許容 Role: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`

### $ClaudeOrchestratorCapabilities
型: Association — Role -> Capability リスト。

### $ClaudeOrchestratorDenyHeads
型: List — worker が提案禁止の head (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential 等)。

### $ClaudeOrchestratorRealLLMEndpoint
型: None | "ClaudeCode" | "CLI" | fn[prompt], 初期値: None
real LLM 統合先。None で統合テストスキップ、"ClaudeCode" で ClaudeCode`ClaudeQueryBg (同期版)、"CLI" で claude CLI を RunProcess 呼出、fn[prompt] でカスタム関数。env CLAUDE_ORCH_REAL_LLM でも opt-in 可。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode の実行ファイル名/フルパス。Automatic は OS 依存 ("claude"/Unix, "claude.cmd"/Windows)。env CLAUDE_ORCH_CLI_PATH で上書き可。

### $ClaudeEvalAutoSkipKeywords
型: List (String)
Auto モードで短い factual query を Single パスにフォールバックさせるためのテクニカルマーカーリスト (パッケージ名・関数名・拡張子等)。ユーザ拡張可。

### $ClaudeEvalAutoFactualEndings
型: List (String)
Auto モードで Single フォールバックさせる「調査・質問型」の語尾・フレーズ ("を調べて"「を教えて」check if compare 等)。

### $ClaudeEvalAutoComplexMarkers
型: List (String)
Orchestrator 経路を通すべき複雑タスクを識別するマーカー (スライド・レポート・プレゼン・複数成果物要求など)。

### ClaudeOrchestrator`$DirectivesVersion / $RoutingVersion / $A4StubVersion / $ClaudeCommitSafetyVersion / $ClaudePromptWorkflowVersion
型: String — 各統合サブモジュールのバージョン文字列。

### 機能オン/オフフラグ (BeginPackage 前に設定で効果)
型: True/False, 初期値: いずれも True
`$ClaudeOrchestratorEnableDirectives`, `$ClaudeOrchestratorEnableRouting`, `$ClaudeOrchestratorEnableCommitSafety`, `$ClaudeOrchestratorEnableA4Stub` — 対応する統合サブモジュールの読込を制御。
`Global`$ClaudeOrchestratorDisablePromptWorkflowAutoLoad = True` でロード前に設定すると promptworkflow 自動ロードを抑止。