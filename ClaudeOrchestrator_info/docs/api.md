# ClaudeOrchestrator API リファレンス

ClaudeRuntime 単一エージェント実行核の上に、タスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit を載せる多エージェントオーケストレーション層。
依存: [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)、[claudecode](https://github.com/transreal/claudecode)、[NBAccess](https://github.com/transreal/NBAccess)。optional: [claudecode_directives](https://github.com/transreal/claudecode_directives)。
ロード: `Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeOrchestrator.wl"]]`
不変条件: worker は artifact producer に限定 (NotebookWrite 禁止)。実 notebook 書込みは single committer のみ。EvaluationNotebook[] / CreateNotebook[...] は deny。

## バージョン変数
### $ClaudeOrchestratorVersion
型: String。パッケージバージョン。

## コアパイプライン関数
### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ `<|"Tasks" -> {<|"TaskId"->_,"Role"->_,"Goal"->_,"Inputs"->_,"Outputs"->_,"Capabilities"->_,"DependsOn"->_,"ExpectedArtifactType"->_,"OutputSchema"->_|>, ...}|>`
Options: Planner -> Automatic (プランナー関数 fn または mock), MaxTasks -> 10 (最大タスク数)

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証。`<|"Valid"->True/False, "Errors"->{...}|>` を返す。

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し各 task の artifact を収集 (直列/順次)。
→ `<|"Artifacts"-><|taskId->artifact,...|>, "Failures"->{...}, "Status"->"Complete"|"Partial"|"Failed"|>`
Options: WorkerAdapterBuilder -> fn (Role -> TaskSpec を受け adapter を返す), MaxParallelism -> 1 (現状 1)

### ClaudeCollectArtifacts[spawnResult] → Dataset
spawnResult["Artifacts"] を Dataset として返す。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証。`<|"Valid"->True/False, "Errors"->{...}|>`。

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物 (ReducedArtifact) を返す。
→ `<|"ArtifactType"->"Reduced", "Payload"->_, "Sources"->_|>`
Options: Reducer -> Automatic (artifacts を受け ReducedArtifact を返す関数)

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し reducedArtifact を target notebook に反映。committer の HeldExpr 内の EvaluationNotebook[]/CreateNotebook[...] 参照は targetNotebook に ReplaceAll で書換えられる。
→ `<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->_, "Details"->_|>`
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" ("Direct"|"Transactional"; Transactional は shadow buffer に書いてから verify/flush し失敗時 rollback), Verifier -> Automatic (fn[buffer, cells] -> True/False)

### ClaudeRunOrchestration[input, opts]
Planning -> Spawn -> Reduce -> (optional) Commit を直列実行。
→ 4 フェーズの結果を束ねた Association
Options: TargetNotebook -> _ (Commit するなら指定), Planner, WorkerAdapterBuilder, Reducer, CommitterAdapterBuilder, MaxTasks, MaxParallelism, Confirm -> False

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま batchInstructions の prompt を ClaudeContinueTurn で順次投入。
→ `{<|"Index"->i, "Prompt"->_, "Result"->_|>, ...}`
Options: WaitBetween -> Quantity[1, "Seconds"]

## 非同期オーケストレーション API
### ClaudeRunOrchestrationAsync[input, opts] → orchJobId
Plan->Spawn->Reduce->Commit を DAG コールバックチェーンで非同期実行し orchJobId を即座に返す。フロントエンドをブロックしない。opts は ClaudeRunOrchestration と同じ。

### ClaudeOrchestrationStatus[orchJobId] → Association
ジョブの現在状態。`<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->_, "ElapsedSecs"->_, "PlanJobId"->_, "SpawnJobId"->_|>`。

### ClaudeOrchestrationResult[orchJobId]
完了済み orchestration の最終結果 (ClaudeRunOrchestration と同形 Association)。未完了なら Missing を返す。

### ClaudeOrchestrationWait[orchJobId, timeoutSec]
orchestration 完了まで待機 (テスト/スクリプト専用、対話セルでは避ける)。既定タイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId]
実行中の DAG を中止しレジストリから除去。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧。

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True。$ClaudeEvalHook が非同期経路 (Async) と同期経路 (ClaudeRunOrchestration) のどちらを使うか制御。False で旧同期挙動。

## Real LLM 統合
### $ClaudeOrchestratorRealLLMEndpoint
型: None|String|Function, 初期値: None。None=統合テストスキップ, "ClaudeCode"=ClaudeQueryBg 同期版, "CLI"=claude CLI を RunProcess, fn[prompt]=カスタム関数。環境変数 CLAUDE_ORCH_REAL_LLM でも opt-in。

### $ClaudeOrchestratorCLICommand
型: Automatic|String, 初期値: Automatic。CLI mode の実行ファイル。Automatic= "claude" (Unix)/"claude.cmd" (Windows)。環境変数 CLAUDE_ORCH_CLI_PATH で上書き可。

### ClaudeRealLLMAvailable[] → Boolean
real-LLM 統合が設定済みなら True。$ClaudeOrchestratorRealLLMEndpoint と env を確認。

### ClaudeRealLLMQuery[prompt] → String | $Failed
設定済み real-LLM endpoint で prompt を実行し応答を返す。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し診断情報 (endpoint/CLI パス/ExitCode/raw stdout/unwrap 結果/JSON parse 可否) を返す。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ plan 結果・raw LLM 応答 head・task count・status・error 情報を返す。

## Auto ゲート定数 (Phase 32)
### $ClaudeEvalAutoSkipKeywords
型: List。Auto モードで短い factual query を Single パスにフォールバックさせるテクニカルマーカー (パッケージ名・関数名・拡張子等)。これらが含まれ、タスクが 300 文字未満かつ複雑さ指標なしなら Orchestrator 経路を通らず Single 処理。ユーザ拡張可。

### $ClaudeEvalAutoFactualEndings
型: List。Single フォールバック用の調査・質問型語尾/フレーズ ("を調べて"「を教えて」check if compare 等)。

### $ClaudeEvalAutoComplexMarkers
型: List。Orchestrator 経路を通すべき複雑タスク識別マーカー (スライド・レポート・プレゼン・複数成果物要求等)。プロンプトに現れると短いタスクでも Orchestrator 経路を通す。

## Role / Capability 定数
### $ClaudeOrchestratorRoles
型: List, 値: {"Explore","Plan","Draft","Verify","Reduce","Commit"}。許容 Role リスト。

### $ClaudeOrchestratorCapabilities
型: Association。Role -> Capability リストの対応。

### $ClaudeOrchestratorDenyHeads
型: List。worker が提案してはいけない head (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential 等)。

## サブモジュール有効化フラグ
BeginPackage より前に設定して効果あり。デフォルト全て True。
### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True。Directives 統合の有効化。
### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True。Routing 統合の有効化。
### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True。CommitSafety 統合の有効化。
### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True。A4Stub 統合の有効化。

## Directives 統合 (ClaudeOrchestrator` 名前空間)
worker prompt に role/model/goal に応じた directive prefix を [claudecode_directives](https://github.com/transreal/claudecode_directives) 経由で前置する。未ロード時は passthrough。
### ClaudeOrchestrator`$DirectivesVersion
型: String。directives 統合のバージョン文字列。
### ClaudeOrchestrator`DirectivesEnabledQ[] → Boolean
ClaudeDirectives がロードされリポジトリも有効なら True。False なら hook は passthrough。
### ClaudeOrchestrator`DirectivesPreviewPrefix[role, model, goal] → String
hook を介さず directive prefix 文字列を取得 (debug 用)。
### ClaudeOrchestrator`DirectivesSelected[role, model, goal] → Association
`<|"Rules"->{names}, "Skills"->{names}, "Mode"->modeStr, "Tokens"->n, "Model"->resolvedModelStr|>`。
### ClaudeOrchestrator`DirectivesResolveBundle[taskSpec, opts]
TaskSpec (Association) の Role/Goal/Inputs/DependsOn から ClaudeDirectives bundle を解決。
Options: "Model" -> spec, "Mode" -> Automatic|"Full"|"Summary"|"Index"|"Lazy", "TokenBudget" -> Integer|Automatic, "MaxSkills" -> Integer
### ClaudeOrchestrator`DirectivesInvalidateCache[]
キャッシュ済みリポジトリを破棄し次回ディスク再読込。
### ClaudeOrchestrator`DirectivesNormalizeModel[modelSpec, role] → String
directive projection 用のモデル名文字列を返す。String, List ({provider,model,url}), Automatic/None を処理。
### ClaudeOrchestrator`$DirectivesVerbose
型: Boolean, 初期値: False。True で prefix 構築毎に診断出力。
### ClaudeOrchestrator`DirectivesAutoLoadStatus[] → String
直近の ClaudeDirectives リポジトリ auto-load 結果を説明する文字列。EnabledQ[] が False の原因診断用。
### ClaudeOrchestrator`DirectivesForceLoad[] / DirectivesForceLoad[path]
リポジトリ読込を再試行 (path で root 指定可)。auto-load 試行フラグをリセットし EnabledQ[] が再試行する。

## Routing 統合 (ClaudeOrchestrator` 名前空間)
model spec を解析し適切な queryFn (CLI/API) を返す。"qwen"等ローカル LLM 名は $ClaudePrivateModel に自動展開して API 経路へ。
### ClaudeOrchestrator`$RoutingVersion
型: String。routing モジュールのバージョン文字列。
### ClaudeOrchestrator`RoutingEnabledQ[] → Boolean
CLI (ClaudeQueryBg) または API (iQueryViaAPI) のいずれかが呼出可能なら True。
### ClaudeOrchestrator`RoutingPreviewModel[role:"", model:Automatic]
role 別 default 引き + qwen->$ClaudePrivateModel 展開後の解決済み model spec を返す。
### ClaudeOrchestrator`RoutingGetInfo[role:"", model:Automatic] → Association
`<|"Source"->str, "Path"->"CLI"|"API"|"Explicit"|"Empty", "Model"->resolved, "Role"->role, "QueryFunction"->fn|>`。
### ClaudeOrchestrator`RoutingListPaths[] → Association
`<|"CLI"->_, "API"->_, "PrivateModel"->_, "RoleDefaults"->_|>` の bool。現セッションで利用可能な routing 経路。
### ClaudeOrchestrator`$RoutingVerbose
型: Boolean, 初期値: False。True で queryFn 解決毎に診断出力。

## A4 hook (ClaudeOrchestrator` 名前空間)
### ClaudeOrchestrator`$A4StubVersion
型: String。A4 hook stub のバージョン文字列。
### ClaudeOrchestrator`A4InjectDirectivePrefix[prompt, role, model, goal] → String
prompt に directive prefix を前置 (Directives 統合がロードされていれば本格動作、未ロードなら passthrough)。
### ClaudeOrchestrator`A4ResolveQueryFnForRole[queryFn, model, role] → Association
role/model から queryFn を解決。`<|"QueryFunction"->fn, "Source"->_, "Path"->"CLI"|"API"|"Explicit"|"Empty", "Model"->resolved, "Role"->role|>`。queryFn が明示関数なら passthrough。
### ClaudeOrchestrator`A4ResolveModelForRole[role, model]
role に応じた model 解決。List spec はそのまま、String は展開、Automatic/None は role 別 default。

## CommitSafety 統合
LLM-backed commit と iDeterministicSlideCommit がいずれも失敗/不十分時の 3rd-tier fallback。payload を Markdown 解析して Cell list を生成し target notebook へ書込む (Title->Section, Summary/Description->Text, Code->Input, KeyPoints->ItemParagraph, heading->Section/Subsection, bullet->ItemParagraph)。
### ClaudeOrchestrator`$ClaudeCommitSafetyVersion
型: String。commit safety パッチのバージョン文字列。

## 自動ロードされるコンパニオンパッケージ
ClaudeOrchestrator.wl ロード時に以下を自動ロード (失敗しても本体ロードは壊れない):
- [ClaudeOrchestrator_workflow](https://github.com/transreal/ClaudeOrchestrator_workflow) (workflow engine + shim)
- ClaudeOrchestrator_stategraph (ClaudeStateGraph` namespace)
- [ClaudeOrchestrator_observability](https://github.com/transreal/ClaudeOrchestrator_observability) ($petriObservabilityVersion で重複回避。ClaudeQueryBgLogged / plotPetriNetDetail / traceTransitions / showLLMCallLog / withLLMLogging 等)
- [ClaudeOrchestrator_promptworkflow](https://github.com/transreal/ClaudeOrchestrator_promptworkflow) ($ClaudePromptWorkflowVersion で重複回避。`Global`$ClaudeOrchestratorDisablePromptWorkflowAutoLoad = True` でロード前に無効化可)