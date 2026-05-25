# ClaudeOrchestrator API リファレンス

LLM 向け API リファレンス。Multi-Agent Orchestration Layer (ClaudeRuntime 上のタスク分解・並列 worker 配車・artifact 収集・reduction・single-committer commit 機構)。

## バージョン・定数

### $ClaudeOrchestratorVersion
型: String
パッケージバージョン。

### $ClaudeOrchestratorRoles
型: List
許容 Role リスト: `{"Explore", "Plan", "Draft", "Verify", "Reduce", "Commit"}`

### $ClaudeOrchestratorCapabilities
型: Association
Role → Capability リストの Association。

### $ClaudeOrchestratorDenyHeads
型: List
worker が提案してはいけない head のリスト (NotebookWrite, CreateNotebook, EvaluationNotebook, RunProcess, SystemCredential など)。

### $ClaudeEvalAutoSkipKeywords
型: List
Auto モードで短い factual query を Single パスにフォールバックさせるためのテクニカルキーワードリスト (パッケージ名、関数名、拡張子等)。プロンプトに含まれ、かつタスクが 300 文字未満・複雑さ指標なしの場合、Orchestrator 経路を通らず従来の Single パスで直接処理される。

### $ClaudeEvalAutoFactualEndings
型: List
Auto モードで Single フォールバックさせる「調査・質問型」の語尾・フレーズリスト「を調べて」「を教えて」check if compare 等。

### $ClaudeEvalAutoComplexMarkers
型: List
Orchestrator 経路を通すべき「複雑タスク」を識別するマーカーリスト。スライド・レポート・プレゼン・複数の成果物要求など。

### $ClaudeOrchestratorRealLLMEndpoint
型: None | String | Function, 初期値: None
real LLM 統合エンドポイント設定。
- `None`: real LLM 統合テストをスキップ
- `"ClaudeCode"`: ClaudeCode\`ClaudeQueryBg を使う
- `"CLI"`: claude CLI を RunProcess で呼ぶ
- `fn[prompt]`: カスタム関数を使う
環境変数 `CLAUDE_ORCH_REAL_LLM` でも opt-in 可能。

### $ClaudeOrchestratorCLICommand
型: Automatic | String, 初期値: Automatic
CLI mode で起動する実行ファイル名/フルパス。
- `Automatic`: OS に応じて "claude" (Unix) / "claude.cmd" (Windows)
- String: フルパスまたはコマンド名を明示
環境変数 `CLAUDE_ORCH_CLI_PATH` でも上書き可能。

### $ClaudeOrchestratorAsyncMode
型: Boolean, 初期値: True
`$ClaudeEvalHook` が非同期経路 (ClaudeRunOrchestrationAsync) と同期経路 (ClaudeRunOrchestration) のどちらを使うかを制御。False で旧同期挙動に戻る。

### $ClaudeOrchestratorEnableDirectives
型: Boolean, 初期値: True
Directives サブモジュール有効化フラグ。BeginPackage より前に設定して効果あり。

### $ClaudeOrchestratorEnableRouting
型: Boolean, 初期値: True
Routing サブモジュール有効化フラグ。

### $ClaudeOrchestratorEnableCommitSafety
型: Boolean, 初期値: True
CommitSafety サブモジュール有効化フラグ。

### $ClaudeOrchestratorEnableA4Stub
型: Boolean, 初期値: True
A4Stub サブモジュール有効化フラグ。

### $DirectivesVersion
型: String
Directives 統合モジュールのバージョン文字列。

### $DirectivesVerbose
型: Boolean, 初期値: False
True で directive prefix 構築時に診断メッセージを出力。

### $RoutingVersion
型: String
Routing 統合モジュールのバージョン文字列。

### $RoutingVerbose
型: Boolean, 初期値: False
True で ResolveQueryFnForRole 呼出時に診断メッセージを出力。

### $A4StubVersion
型: String
A4 hook stub のバージョン文字列。

### $ClaudeCommitSafetyVersion
型: String
Commit safety patch のバージョン文字列。

## Planning フェーズ

### ClaudePlanTasks[input, opts]
親タスク input を TaskSpec DAG に分解する。
→ Association `<|"Tasks" -> {<|"TaskId"->..., "Role"->..., "Goal"->..., "Inputs"->..., "Outputs"->..., "Capabilities"->..., "DependsOn"->..., "ExpectedArtifactType"->..., "OutputSchema"->...|>, ...}|>`
Options: Planner -> Automatic (プランナー関数, Automatic で mock), MaxTasks -> 10 (最大タスク数)

### ClaudeValidateTaskSpec[taskSpec] → Association
TaskSpec の妥当性を検証。`<|"Valid"->True/False, "Errors"->{...}|>` を返す。

## Worker spawn / Artifact フェーズ

### ClaudeSpawnWorkers[tasks, opts]
依存順に worker runtime を起動し、各 task の artifact を収集する。
→ Association `<|"Artifacts" -> <|taskId -> artifact, ...|>, "Failures" -> {...}, "Status" -> "Complete"|"Partial"|"Failed"|>`
Options: WorkerAdapterBuilder -> Automatic (Role -> TaskSpec を受け取り adapter を返す関数), MaxParallelism -> 1 (Stage 2 以降で拡張)

### ClaudeCollectArtifacts[spawnResult] → Dataset
`spawnResult["Artifacts"]` を Dataset として返す。

### ClaudeValidateArtifact[artifact, outputSchema] → Association
artifact の payload が OutputSchema を満たすか検証。`<|"Valid"->True/False, "Errors"->{...}|>`。

## Reduction フェーズ

### ClaudeReduceArtifacts[artifacts, opts]
複数 artifact を統合し中間成果物 (ReducedArtifact) を返す。
→ Association `<|"ArtifactType"->"Reduced", "Payload"->..., "Sources"->...|>`
Options: Reducer -> Automatic (artifacts を受け取り ReducedArtifact を返す関数)

## Commit フェーズ

### ClaudeCommitArtifacts[targetNotebook, reducedArtifact, opts]
single committer runtime を起動し、reducedArtifact を target notebook に反映。committer の HeldExpr 内 EvaluationNotebook[] / CreateNotebook[...] 参照は targetNotebook に ReplaceAll で書換えられる。
→ Association `<|"Status"->"Committed"|"Failed"|"RolledBack", "Mode"->..., "Details"->...|>`
Options: CommitterAdapterBuilder -> Automatic, CommitMode -> "Direct" (or "Transactional" : shadow buffer に書いてから verify/flush, 失敗時 rollback), Verifier -> Automatic (`fn[buffer, cells] -> True/False`)

## 全体 Orchestration (同期)

### ClaudeRunOrchestration[input, opts]
Planning → Spawn → Reduce → (optional) Commit の全フェーズを直列に回す。
→ Association (4 フェーズの結果を束ねたもの)
Options: TargetNotebook -> None (Commit するなら指定), Planner -> Automatic, WorkerAdapterBuilder -> Automatic, Reducer -> Automatic, CommitterAdapterBuilder -> Automatic, MaxTasks -> 10, MaxParallelism -> 1, Confirm -> False

### ClaudeContinueBatch[runtimeId, batchInstructions, opts]
単一 runtime セッションを維持したまま、batchInstructions に含まれる prompt を `ClaudeContinueTurn` で順次投入する。notebook 共有問題回避用の現実解。
→ List `{<|"Index"->i, "Prompt"->..., "Result"->...|>, ...}`
Options: WaitBetween -> Quantity[1, "Seconds"]

## 全体 Orchestration (非同期)

### ClaudeRunOrchestrationAsync[input, opts] → orchJobId
Plan → Spawn → Reduce → Commit を DAG コールバックチェーンで非同期実行し、orchJobId を即座に返す。フロントエンドをブロックしない。opts は ClaudeRunOrchestration と同じ。

### ClaudeOrchestrationStatus[orchJobId] → Association
orchestration ジョブの現在状態。`<|"Status"->"Planning"|"Spawning"|"Reducing"|"Committing"|"Done"|"Failed", "Phase"->..., "ElapsedSecs"->..., "PlanJobId"->..., "SpawnJobId"->...|>`。

### ClaudeOrchestrationResult[orchJobId] → Association | Missing
完了済み orchestration の最終結果 (ClaudeRunOrchestration と同形)。未完了なら Missing。

### ClaudeOrchestrationWait[orchJobId, timeoutSec]
orchestration 完了まで待機 (テスト・スクリプト専用。対話セルでは使用を避ける)。既定タイムアウト 300 秒。

### ClaudeOrchestrationCancel[orchJobId]
実行中の DAG を中止しレジストリから除去する。

### ClaudeOrchestrationJobs[] → Dataset
現在追跡中の orchestration ジョブ一覧。

## Real LLM 統合

### ClaudeRealLLMAvailable[] → Boolean
real-LLM 統合が設定済みなら True。`$ClaudeOrchestratorRealLLMEndpoint` と環境変数 `CLAUDE_ORCH_REAL_LLM` を確認。

### ClaudeRealLLMQuery[prompt] → String | $Failed
設定済みの real-LLM エンドポイントに prompt を投入する。

### ClaudeRealLLMDiagnose[prompt] → Association
real LLM 呼び出しを実行し、診断情報 (endpoint, CLI パス, ExitCode, raw stdout, unwrap 結果, JSON parse 可否) を返す。W1-W3 等の失敗切り分け用。

### ClaudeRealLLMDiagnosePlan[input] → Association
実 LLM planner パイプラインを走らせ、plan 結果, raw LLM 応答 head, task count, status, error 情報を返す。W1 失敗切り分け用。

## Directives 統合 API

### DirectivesEnabledQ[] → Boolean
ClaudeDirectives がロードされかつリポジトリ有効なら True。False ならフックは passthrough。

### DirectivesPreviewPrefix[role, model, goal] → String
`ClaudeInjectDirectivePrefix` が prepend する directive prefix を hook 経由せず取得 (デバッグ用)。

### DirectivesSelected[role, model, goal] → Association
→ `<|"Rules"->{...names...}, "Skills"->{...names...}, "Mode"->modeStr, "Tokens"->n, "Model"->resolvedModelStr|>`

### DirectivesResolveBundle[taskSpec_Association, opts] → Association
TaskSpec の Role / Goal / Inputs / DependsOn を読み取り ClaudeResolveDirectiveBundle にブリッジする。
Options: "Model" -> spec, "Mode" -> Automatic|"Full"|"Summary"|"Index"|"Lazy", "TokenBudget" -> Automatic (or Integer), "MaxSkills" -> Integer

### DirectivesInvalidateCache[]
キャッシュされた ClaudeDirectives リポジトリを破棄し次回呼び出しで再ロードさせる。

### DirectivesNormalizeModel[modelSpec, role] → String
directive projection 用の文字列モデル名を返す。String / List ({provider, model, url}) / Automatic / None を扱う。

### DirectivesAutoLoadStatus[] → String
最近の ClaudeDirectives リポジトリ自動ロード試行の結果を表す文字列。EnabledQ が False の理由診断用。

### DirectivesForceLoad[] / DirectivesForceLoad[path]
ClaudeDirectives リポジトリのロードを再試行する (path 指定可)。auto-load 試行フラグをリセットし EnabledQ がリトライするようにする。

## Routing 統合 API

### RoutingEnabledQ[] → Boolean
CLI (ClaudeQueryBg) または API (iQueryViaAPI) の少なくとも一方の query path が呼出可能なら True。

### RoutingPreviewModel[role, model] → spec
role-aware default lookup と qwen→$ClaudePrivateModel 展開後の解決済 model spec を返す。デフォルト引数: role="" , model=Automatic。

### RoutingGetInfo[role, model] → Association
→ `<|"Source"->str, "Path"->"CLI"|"API"|"Default", "Model"->resolved, "Role"->role, "QueryFunction"->fn|>`
デフォルト引数: role="" , model=Automatic。

### RoutingListPaths[] → Association
利用可能な routing path を Association で返す。
→ `<|"CLI"->Boolean, "API"->Boolean, "PrivateModel"->Boolean, "RoleDefaults"->Boolean|>`

## A4 hook API

### A4InjectDirectivePrefix[prompt, role, model, goal] → String
prompt の前に Role/Model/Goal に応じた directive prefix を prepend して返す。ClaudeDirectives 未ロード/未配備時は passthrough (prompt をそのまま返す)。

### A4ResolveQueryFnForRole[queryFn, model, role] → Association
queryFn が明示指定 (Automatic/None 以外) なら respect、それ以外は role-aware model 解決と spec に応じた closure を構築。
→ `<|"QueryFunction"->fn, "Source"->str, "Path"->"CLI"|"API"|"Explicit"|"Empty", "Model"->resolved, "Role"->role|>`

### A4ResolveModelForRole[role, model] → spec
role に応じた model 解決。
- List spec (len ≥ 2): そのまま
- non-empty String (≠ "Automatic"): ローカル LLM 名 (qwen/llama/mistral/phi-/deepseek/gemma) なら $ClaudePrivateModel に展開、それ以外はそのまま
- Automatic / None / "": role 別 default を引いてから上記展開