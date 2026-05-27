# ClaudeOrchestrator_promptworkflow API リファレンス

LLM が提案する WorkflowNet コードを安全にパース・検証する層 (spec 23.5)。評価せずに静的検査・ホールド済みパース・ホワイトリスト評価を行う。

## 変数

### $ClaudePromptWorkflowVersion
型: String
PromptWorkflow 拡張のバージョン文字列。

## ステータス

### ClaudePromptWorkflowStatus[] → Association
PromptWorkflow 拡張の状態を返す。バージョン、実装フェーズ、禁止パターン登録数を含む。

## 禁止パターン

### ClaudeWorkflowForbiddenPatternRegistry[] → List of Association
LLM 提案コードで禁止されるパターンの統合レジストリ (spec 23.5.3)。rule 00 の AutoEvaluate 禁止ヘッドと、ワークフロー固有のファイル/ネットワーク/プロセス/資格情報/ノートブック改変パターンを併せ持つ。各エントリは Name, Token, Category キーを持つ Association。

### ClaudeWorkflowCheckForbidden[code_String] → Association
コード文字列を評価せずに静的スキャンする。word-boundary マッチ。
→ <|Status -> "Clean" | "ForbiddenDetected", Findings -> {...}|>

## 安全パーサ

### ClaudeParseWorkflowNetCode[input_String, opts]
LLM 提案 WorkflowNet コードの安全パーサ (spec 23.5.4)。フェンス付きコードブロック抽出 → 禁止パターン静的検査 → HoldComplete によるホールドパース → AST からの WorkflowNet[spec] 抽出 → ホワイトリスト評価 → well-formedness 検証、の 6 段階。ビルダーは決して呼び出さず、`SetDelayed[buildName[], WorkflowNet[spec]]` の RHS のみを AST から取り出す。
→ WorkflowParseResult Association
Options: (なし)

戻り値キー (Status 別):
- Status -> "Parsed": WorkflowNetHeld (HoldComplete 包装), Spec, Builder, ForbiddenCheck -> "Clean", WellFormed -> True, ParserStage -> "FullPipeline"
- Status -> "Rejected": Reason ("NoCodeFound" | "ForbiddenPatterns" | "NonWhitelistedSymbols"), Findings または ForbiddenSymbols
- Status -> "ParseFailed": Reason -> "HeldParseFailed"
- Status -> "NoWorkflowNet": Reason -> "NoWorkflowNetFormInAST"
- Status -> "NeedsRepair": Reason -> "NotWellFormed", Issues, Builder

### ClaudeWorkflowNetWellFormedQ[spec_Association] → Association
WorkflowNet 宣言的 spec の well-formedness をチェック (spec 17.9)。Places と Transitions がリストであること、各エントリが String の Name を持つ Association であることを確認する。
→ <|Type -> "WorkflowNetValidation", Status -> "WellFormed" | "Malformed", Issues -> {...}|>

Issues の値: "PlacesNotList", "TransitionsNotList", "PlaceMissingName", "TransitionMissingName", "SpecNotAssociation"

## 提案 API

### ClaudeProposeWorkflowNetFromPrompt[prompt_String, opts]
自然言語ゴールから WorkflowNet 提案を生成する (spec 23.4.1)。コードプロバイダにコードを要求し、安全パーサに通し、失敗時には静的診断をフィードバックして MaxProposalAttempts 回まで再試行する。提案のみで実行・登録は行わない。
→ WorkflowProposal Association
Options:
- "MaxProposalAttempts" -> 3 (最大再試行回数, IntegerQ かつ >= 1)
- "ProviderPolicy" -> Automatic
- "FeedbackMode" -> "StaticDiagnostics"
- "CodeProvider" -> Automatic (Automatic で ClaudeCode\`ClaudeQuery を weak-call、Function を渡すと直接呼ぶ)

戻り値キー: Type -> "WorkflowProposal", Status ("Proposed" | "NeedsRepair" | "Rejected"), Prompt (SHA256), Attempts, AttemptTrace, Code, BuilderName, WorkflowNetSpec, Diagnostics (FinalParseStatus, LastFeedback), ProposerVersion

例:
```
ClaudeProposeWorkflowNetFromPrompt["extract then summarize",
  "CodeProvider" -> (Function[p, "buildA[] := WorkflowNet[<|...|>]"]),
  "MaxProposalAttempts" -> 2]
```

## ドラフト作成

### ClaudeCreateWorkflowRouteDraft[prompt_String, proposal_Association, opts]
Order 8 の成功した提案を WorkflowRouteDraft に変換する (spec 23.8)。コード本体は SourceVault PrivateVault 配下の `promptrouter/artifacts/wf-code/sha256-<h>.wl` に保存し、ドラフトメタデータは CodeHash と CodeStorage 参照のみを保持する。Status は常に NeedsApproval で作成され、自動登録・自動実行はされない (spec 23.9 rule 6)。
→ WorkflowRouteDraft Association
Options:
- "DryRun" -> True (rule 103 既定。True なら計画のみ報告し書き込まない)
- "PrivacyLevel" -> 0.75 (>= 0.5 で AllowedModelClasses は {"Local", "Private"}、未満で {"Cloud", "Private", "Local"})
- "WorkflowTemplateId" -> Automatic

戻り値キー (DryRun 時): Type, Status -> "DryRun", DraftId, CodeHash, PlannedStatus -> "NeedsApproval", PlannedArtifactKind -> "PrivateArtifactRef", ParsedNetSummary, PrivacyLevel

戻り値キー (実書き込み成功時): Type, DraftId, Status -> "NeedsApproval", PromptFingerprint, WorkflowTemplateId, WorkflowVersion -> 1, CodeHash, CodeStorage (Kind, ArtifactPath), ParsedNetSummary (PlaceCount, TransitionCount, HandlerMode), ProposalTrace, PrivacyLevel, AllowedModelClasses, RequiresApproval -> True

失敗時 Reason: "ProposalNotProposed", "ProposalHasNoCode", "NoPrivateVault", "OpenFailed", "RenameFailed", "ArtifactSaveFailed"

## 複雑性検出

### ClaudeWorkflowComplexPromptQ[prompt_String] → Association
決定的・評価不要の複雑プロンプト検出器 (spec 23.6, ClaudeEval step 5)。ルーター LLM 呼び出しの前にローカル実行されるため、ワークフロー候補性テストのために秘密プロンプトが外部送信されることはない。
→ <|Type -> "ComplexPromptDecision", Decision, Reason, Signals, DetectorVersion|>

判定ロジック:
- explicitHits >= 1 → Decision: "WorkflowCandidate", Reason: "ExplicitWorkflowRequest"
- verbHits >= 2 → "WorkflowCandidate", "MultipleSubTaskVerbs"
- verbHits >= 1 かつ controlHits >= 1 → "WorkflowCandidate", "SubTaskWithControlFlow"
- それ以外 → "NotComplex", "SingleStepOrUnclear"

Signals: ExplicitRequestHits, SubTaskVerbHits, ControlWordHits

キュー語彙 (日本語・英語混在): 制御語 ("まず", "次に", "それから", "最後に", "必要なら", first/then/next/finally/"after that"), タスク動詞 ("抽出", "要約", "比較", "並べ替", "ソート", "承認", "連携", extract/summarize/compare/sort/approve), 明示要求 ("ワークフロー化", "手順として保存", "Petri netにして", workflow)。

## ルート決定統合

### ClaudeWorkflowRouteFromPrompt[prompt_String, opts]
ClaudeEval ワークフロー統合フロー (spec 23.7) を統括し、spec 23.9 の競合回避ルールを強制する。決定順序:
1. 既存ユニーク FunctionRoute / WorkflowRoute 一致 → そのまま使用 (spec 23.9-1/2)
2. ローカルで決定的複雑性検出器を実行 (LLM 不使用)
3. NotComplex → Decision: NeedsHeavyLLM
4. WorkflowCandidate → 提案 (Order 8) → WorkflowRouteDraft 作成 (Order 9)

新規生成されたワークフローは常に NeedsApproval で停止する。auto-run 例外は初期版未実装。
→ WorkflowRouteDecision Association
Options:
- "MaxProposalAttempts" -> 3
- "CodeProvider" -> Automatic
- "DryRunDraft" -> True

戻り値キー (共通): Type -> "WorkflowRouteDecision", PromptFingerprint (SHA256), RouterVersion

戻り値 Decision 値:
- "UseExistingRoute": Reason -> "ExistingRouteMatchedUniquely", ExistingDecision
- "NeedsHeavyLLM": Reason -> "NotAWorkflowCandidate", Complexity
- "WorkflowProposalFailed": Reason, Complexity, Proposal
- "WorkflowDraftCreated": Reason -> "NewWorkflowNeedsApproval", Complexity, Draft, NextStep -> "AwaitUserApproval"
- "WorkflowDraftFailed": Reason, Draft
- "Failed" (引数不正時): Reason -> "InvalidArguments", Hint

既存ルート探索は `SourceVault\`SourceVaultResolvePromptRoute` を weak-call で利用するため、ルーター不在環境でも本層はロード可能。

## 関連パッケージ

- [SourceVault_promptrouter](https://github.com/transreal/SourceVault_promptrouter) — 既存プロンプトルート解決
- [SourceVault](https://github.com/transreal/SourceVault) — PrivateVault ルート提供
- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) — 親パッケージ
- [claudecode](https://github.com/transreal/claudecode) — `ClaudeQuery` を提供するコードプロバイダ