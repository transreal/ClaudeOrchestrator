# ClaudeOrchestrator PromptWorkflow API リファレンス

LLM が提案した WorkflowNet コードを安全に解析・検証するための ClaudeOrchestrator 拡張（unified spec 23.5）。すべての公開シンボルは `ClaudeOrchestrator`` コンテキストに属する。評価フリーの静的検査・held パース・ホワイトリスト評価を通して、ファイル/ネットワーク/プロセス副作用を起こさずに WorkflowNet 宣言仕様を抽出する。

## 変数

### $ClaudePromptWorkflowVersion
型: String
PromptWorkflow 拡張のバージョン文字列。各 API の戻り値に `ProposerVersion` / `DetectorVersion` / `RouterVersion` として埋め込まれる。

## ステータス・レジストリ

### ClaudePromptWorkflowStatus[] → Association
拡張の状態を返す。version, implementation phase, forbidden-pattern registry のサイズを含む。

### ClaudeWorkflowForbiddenPatternRegistry[] → {Association...}
LLM 提案ワークフローコードで禁止されるパターンの単一マージレジストリ（spec 23.5.3）。rule 00 の AutoEvaluate 禁止ヘッド＋ワークフロー固有のファイル/ネットワーク/プロセス/クレデンシャル/ノートブック変更パターン。各エントリは `<|Name, Token, Category|>`。

### ClaudeWorkflowCheckForbidden[code_String] → Association
コード文字列を評価せず静的スキャンし禁止パターンを検出。語境界マッチなので長い識別子の部分文字列で誤検出しない。
→ `<|"Status" -> "Clean" | "ForbiddenDetected", "Findings" -> {...}|>`

## 安全パーサー

### ClaudeParseWorkflowNetCode[input_String, opts]
LLM 提案 WorkflowNet コードの安全パーサー（spec 23.5.4）。パイプライン: (1) フェンス付きコードブロック抽出（無ければ全体をコードとみなす）、(2) 静的禁止検査（パース前）、(3) `ToExpression[code, InputForm, HoldComplete]` による held パース（評価なし）、(4) AST から `WorkflowNet[spec]` 抽出、(5) ホワイトリスト評価で宣言仕様構築、(6) well-formedness 検証。ビルダー `buildName[] := WorkflowNet[spec]` の右辺のみ取り出し、`buildName[]` は決して評価しない。
→ WorkflowParseResult Association
Status 値と主フィールド:
- `Parsed`: `WorkflowNetHeld`(HoldComplete 包み), `Spec`, `Builder`, `ForbiddenCheck->"Clean"`, `WellFormed->True`, `ParserStage->"FullPipeline"`
- `Rejected`: Reason = `NoCodeFound` / `ForbiddenPatterns`(+`Findings`) / `NonWhitelistedSymbols`(+`ForbiddenSymbols`,`Builder`)
- `ParseFailed`: Reason = `HeldParseFailed`
- `NoWorkflowNet`: Reason = `NoWorkflowNetFormInAST`
- `NeedsRepair`: Reason = `NotWellFormed`, +`Issues`, `Builder`
- `Failed`: Reason = `InvalidArguments`
Options: なし（`Options[...] = {}`）

### ClaudeWorkflowNetWellFormedQ[spec_Association] → Association
WorkflowNet 宣言仕様の well-formedness 検査（spec 17.9）。`Places` / `Transitions` がリストで、各要素が String の `Name` を持つ Association であること。
→ `<|"Type"->"WorkflowNetValidation", "Status"->"WellFormed"|"Malformed", "Issues"->{...}|>`
Issues 値: `PlacesNotList`, `TransitionsNotList`, `PlaceMissingName`, `TransitionMissingName`, `SpecNotAssociation`(非 Association 引数時)。

## 提案 API

### ClaudeProposeWorkflowNetFromPrompt[prompt_String, opts]
自然言語ゴールを WorkflowNet 提案に変換（spec 23.4.1）。コードプロバイダにコード生成を依頼→安全パーサーに通し、失敗時は静的診断をフィードバックとして返し `MaxProposalAttempts` まで再試行。提案のみで実行・登録はしない。
→ WorkflowProposal Association
Options:
- `MaxProposalAttempts` -> 3 (再試行上限、1未満は3に補正)
- `ProviderPolicy` -> Automatic
- `FeedbackMode` -> "StaticDiagnostics"
- `CodeProvider` -> Automatic (Automatic は弱呼び出し `ClaudeCode`ClaudeQuery`、Function を渡すと LLM なしでコード直接供給)
戻りフィールド: `Status`(`Proposed`/`NeedsRepair`/`Rejected`/`Failed`), `Prompt`("sha256:..."), `Attempts`, `AttemptTrace`({`<|Attempt,Status|>`...}), `Code`, `BuilderName`, `WorkflowNetSpec`, `Diagnostics`(`<|FinalParseStatus, LastFeedback|>`), `ProposerVersion`。
例: ClaudeProposeWorkflowNetFromPrompt["抽出して要約", "CodeProvider" -> (myCode &), "MaxProposalAttempts" -> 2]

### ClaudeCreateWorkflowRouteDraft[prompt_String, proposal_Association, opts]
成功した提案（Status="Proposed"）を WorkflowRouteDraft に変換（spec 23.8）。コード本体は SourceVault PrivateVault 配下の private artifact として保存し、ドラフトメタデータは `CodeHash` と `CodeStorage` 参照のみ持つ。Status は常に `NeedsApproval` で自動昇格・実行しない（spec 23.9 rule 6）。
→ WorkflowRouteDraft Association
Options:
- `DryRun` -> True (既定、rule 103。書込みせず計画のみ報告)
- `PrivacyLevel` -> 0.75 (非数値は0.75に補正。>=0.5 で AllowedModelClasses={"Local","Private"}、未満で {"Cloud","Private","Local"})
- `WorkflowTemplateId` -> Automatic
保存先: `<PrivateVault>/promptrouter/artifacts/wf-code/sha256-<h>.wl` と `.metadata.json`。
Status 値: `DryRun`(`DraftId`,`CodeHash`,`PlannedStatus->"NeedsApproval"`,`ParsedNetSummary`,`PrivacyLevel`), `NeedsApproval`(実書込み後の正規ドラフト), `Rejected`(Reason=`ProposalNotProposed`/`ProposalHasNoCode`), `Failed`(Reason=`NoPrivateVault`/書込み失敗/`InvalidArguments`)。
正規ドラフトフィールド: `DraftId`("wfdraft-"+hash12), `PromptFingerprint`, `WorkflowTemplateId`, `WorkflowVersion`->1, `CodeHash`, `CodeStorage`(`<|Kind->"PrivateArtifactRef", ArtifactPath|>`), `ParsedNetSummary`(`<|PlaceCount, TransitionCount, HandlerMode->"DeclarativeOnly"|>`), `ProposalTrace`, `PrivacyLevel`, `AllowedModelClasses`, `RequiresApproval`->True。

## 複雑プロンプト検出・統合

### ClaudeWorkflowComplexPromptQ[prompt_String] → Association
決定論的・評価フリーの複雑プロンプト検出器（spec 23.6, ClaudeEval flow step 5）。ルーター LLM 呼び出し前にローカル実行され、秘密プロンプトを候補判定だけのために外部送信しない。日英のキュー語をマッチ。
判定（いずれか成立で `WorkflowCandidate`）:
- 明示的ワークフロー要求 1件以上 → Reason `ExplicitWorkflowRequest`
- 異なるサブタスク動詞 2件以上 → Reason `MultipleSubTaskVerbs`
- サブタスク動詞1件＋制御語1件 → Reason `SubTaskWithControlFlow`
- いずれも不成立 → `NotComplex`, Reason `SingleStepOrUnclear`
→ `<|"Type"->"ComplexPromptDecision", "Decision"->"WorkflowCandidate"|"NotComplex", "Reason"->..., "Signals"-><|ExplicitRequestHits, SubTaskVerbHits, ControlWordHits|>, "DetectorVersion"->...|>`

### ClaudeWorkflowRouteFromPrompt[prompt_String, opts]
ClaudeEval ワークフロー統合フローのオーケストレーション（spec 23.7、衝突回避 spec 23.9）。判定順: (1) 既存の一意ルートがあればそのまま使用、(2) なければローカル複雑検出器を実行、(3) NotComplex なら NeedsHeavyLLM、(4) WorkflowCandidate なら提案（Order 8）→WorkflowRouteDraft 作成（Order 9）。新規生成ワークフローは「作って実行」と言われても常に NeedsApproval で停止し、自動登録・実行しない。既存ルート探索は `SourceVault`SourceVaultResolvePromptRoute` を弱呼び出し。
→ WorkflowRouteDecision Association
Options:
- `MaxProposalAttempts` -> 3 (1未満は3に補正)
- `CodeProvider` -> Automatic
- `DryRunDraft` -> True (ドラフト作成を DryRun にするか)
Decision 値: `UseExistingRoute`(Reason=`ExistingRouteMatchedUniquely`, +`ExistingDecision`), `NeedsHeavyLLM`(Reason=`NotAWorkflowCandidate`, +`Complexity`), `WorkflowProposalFailed`(+`Complexity`,`Proposal`), `WorkflowDraftFailed`(+`Draft`), `WorkflowDraftCreated`(Reason=`NewWorkflowNeedsApproval`, +`Complexity`,`Draft`,`NextStep->"AwaitUserApproval"`), `Failed`(Reason=`InvalidArguments`)。
共通フィールド: `Type->"WorkflowRouteDecision"`, `PromptFingerprint`("sha256:..."), `RouterVersion`。

## 重要な不変条件
- パーサーは絶対にビルダー `buildName[]` を呼ばない。AST 右辺の `WorkflowNet[spec]` を取り出すのみ。
- held WorkflowNet は HoldComplete に包んで返され、呼び出し側が誤って評価できない。
- ホワイトリスト許可シンボル: `Association`, `List`, `Rule`, `RuleDelayed`, `WorkflowNet`, `HoldComplete`, `Missing`, `Infinity`, `Automatic`, `True`, `False`, `Null`。整数/実数/文字列リテラルはシンボルでないため許可。それ以外（`Plus`, `StringJoin`, `Join`, `ToString` 等）は `NonWhitelistedSymbols` で拒否。
- 静的禁止検査はパースより前に実行される。