# ClaudeOrchestrator`TurnWiki` API リファレンス

WikiSkill 型 (arXiv:2608.27454) の LLM turn 自己改善ループ。
仕様: `ドキュメント/claude_turnwiki_wikiskill_spec_v0_1.md`
実装: `ClaudeOrchestrator_turnwiki.wl` (ClaudeOrchestrator.wl が自動ロード。
実ロードマーカー `$TurnWikiVersion`)

3 層ワークスペース (`$ClaudeTurnWikiRoot`, 既定 `<MyPackages>/Claude TurnWiki/`):
`raw/`(不変トレース) / `wiki/`(パターン集+進化ログ+skill-impact 台帳。決して
ロールバックしない) / `skills/`(昇格済み手順書。`archive/` で版管理)。

設計不変条件: **I1** wiki は append/compound のみ **I2** 全提案(却下含む)を台帳追記
**I3** 手順書は検証ゲート(score > RBest)通過時のみ更新・悪化時は手順書のみ戻す・
probe 0 件では昇格しない(fail-closed) **I4** 実行役(推論 turn)には手順書だけ注入
(wiki は directive root の外。起動時検査)。

## ループ

### ClaudeTurnWikiRunIteration[opts]
1 反復 = collect(層化サンプル) → maintain(Wiki Maintainer, LLM 1 呼) →
propose(Skill Proposer, ReAct) → stage → validate(probe 採点) →
gate(Accepted は Promote+注入具現化 / Rejected は staging 破棄) → 台帳追記。
`"UseOrchestrator"->Automatic` で ClaudeOrchestrator`Workflow` 可用時は Petri net
実行(分岐は Guard 純関数、LLM は handler のみ)、不可なら直接ループ(同じ step 関数)。
隔離検査 (I4) 違反時は `Status->"IsolationViolation"` で停止。
→ `<|"Status", "Iteration", "Mode", "Traces", "Maintain", "Proposal", "Decision", "Validation", "RBest"|>`
Options: `"LLMFn"` -> Automatic (fn[prompt, sys]→String|Missing。既定=
SourceVaultQueryLocalLLM 弱結合), `"TracesFn"` -> Automatic, `"EvalFn"` -> Automatic,
`"UseOrchestrator"` -> Automatic, `"MaxProposerTurns"` -> 12, `"MaxFail"` -> 5, `"MaxPass"` -> 3,
`"ModelProfile"` -> Automatic (Automatic="default"=全モデル/global state、"provider:model"=そのプロファイルのトレース/RBest/ActiveSkills/検証のみ)

### ClaudeTurnWikiRun[k, opts]
最大 k 反復。RBest>=1.0 で早期終了 (論文 Algorithm 1)。IsolationViolation/LLMUnavailable で中断。
Options: RunIteration と同じ (`Options[ClaudeTurnWikiRun] = Options[ClaudeTurnWikiRunIteration]`)
→ 反復サマリの List

## Raw Layer

### ClaudeTurnWikiCollectTraces[opts]
層化サンプル (fail<=MaxFail + pass<=MaxPass、1 件 <=MaxChars 字) を採取し
`raw/iter-<k>/` へ write-once 保存。原資 = 生きている ClaudeRuntime EventTrace +
SourceVault llmlog (どちらも弱結合) / `"TracesFn"` 注入。llmlog は ClaudeEval 単発
(SessionKind=harness) を優先し、直近 `"LLMLogTranscriptLimit"` (10) 件は
`SourceVaultClaudeCodeSessionTranscript` の全文 (末尾優先で MaxChars に収める) を、
残りは digest 要約を使う (transcript は 1 件 1-5s)。`$ClaudeTurnWikiMinTraceChars`
(200) 未満の自動採取トレースは捨てる (TracesFn 注入は対象外)。
Options: `"TracesFn"`->Automatic, `"MaxFail"`->5, `"MaxPass"`->3, `"MaxChars"`->15000, `"Persist"`->True,
`"LLMLogScanLimit"`->30, `"LLMLogTranscriptLimit"`->10, `"ExcludeTraceIds"`->{}, `"ModelProfile"`->Automatic
→ `{<|"TraceId","Kind"("pass"|"fail"),"Task","Text","Source","Provider","Model","Profile"|>..}`

### ClaudeTurnWikiClassifyRuntimeTrace[trace] (純関数)
EventTrace を分類。修復系イベント (FatalFailure/ExecutionFailed/FormatRetry/
TextOnlyRepair/ValidationRepairAttempt/Decision=Deny 等) が 1 つでもあれば "fail"。
→ `<|"Kind"->"pass"|"fail"|"unknown", "Signals"->{..}|>`

### ClaudeTurnWikiRenderTrace[trace, maxChars:15000] (純関数)
EventTrace を LLM 向けコンパクトテキストへ。→ String

## Wiki Layer

### ClaudeTurnWikiMaintain[traces, opts]
Wiki Maintainer。LLM 1 呼び出しで JSON (create_patterns/update_patterns(patch ops)/
update_index/append_log) を得て純関数適用。
Options: `"LLMFn"`->Automatic, `"Iteration"`->Automatic
→ `<|"Status"("LLMUnavailable"|"NoTraces"|"LLMFailed"|"ParseFailed"|..),"Created","Updated",...,"RawKeys"|>`

### ClaudeTurnWikiApplyMaintainerOutput[out, opts] / ClaudeTurnWikiApplyPatchOps[content, edits]
Maintainer 出力の機械適用 (Option `"Iteration"`->Automatic) / patch ops (append|replace|insert_after, target は
既存本文の完全部分文字列) エンジン (純関数)。→ ApplyPatchOps: `<|"Content","Applied","Failed"|>`

### ClaudeTurnWikiAppendSkillImpact[entry] / ClaudeTurnWikiSkillImpact[]
skill-impact 台帳 (md+jsonl) への機械追記 / md テキスト読み出し ("" if absent)。却下案の全文も残る (I2)。

## Skill Layer

### ClaudeTurnWikiParseProposal[assoc] → Association (純関数)
Skill Proposer 提案の検証/正規化。→ `<|"Action","Name","SkillMD","PurposeMD","Edits","Rationale","Status"|>`

### ClaudeTurnWikiPropose[opts]
Skill Proposer。ReAct 型クライアント側ツールループ (read_file =
wiki/traces/skills 限定サンドボックス + finish)。skill-impact を先に読み、
却下済み案を繰り返さない。堂々巡り/parse 失敗ガードつき。
Options: `"LLMFn"`->Automatic, `"MaxTurns"`->12, `"MaxFileChars"`->16000, `"TaskSummary"`->Automatic, `"ModelProfile"`->Automatic
→ `<|"Action"->"create"|"patch"|"no_action", "Name", "SkillMD", "Edits", "Rationale", "Status", "TurnsUsed"|>`

### ClaudeTurnWikiApplyProposal[proposal]
staging/ へ候補適用 (本番 skills/ 不干渉)。→ `<|"Status","Name","CandidateSkills"|>`

### ClaudeTurnWikiValidate[opts]
probe 群で skill set を採点。probe 0 件 → `Status->"NoProbes"`, `Score->Missing["NoProbes"]` (昇格不可)。
既定 EvalFn = 手順書注入 1 発 LLM 回答への Expected 包含判定。
検証 LLM = 明示 "LLMFn" > `$ClaudeTurnWikiProfileLLMFns[profile]` > 既定ローカル LLM。
Options: `"Skills"`->Automatic(=active of profile), `"Probes"`->Automatic, `"EvalFn"`->Automatic (fn[probe, skillsText]), `"LLMFn"`->Automatic, `"ModelProfile"`->Automatic
→ `<|"Status","Score","Passed","Failed","Runs"|>`

### ClaudeTurnWikiGateDecision[candScore, rBest] (純関数)
数値同士の厳密な `>` のみ "Accepted"。それ以外は "Rejected" (fail-closed)。

### ClaudeTurnWikiPromote[name, skillMD, purposeMD, score, meta]
前版を archive → skills/ へ設置 → state (ActiveSkills/RBest) 更新 → 注入具現化。meta に `<|"Profile"->key|>` で名前付きプロファイル昇格。

### ClaudeTurnWikiReject[name] / ClaudeTurnWikiRollbackSkill[name, profile:Automatic]
候補破棄 / 手順書のみロールバック (archive 前版復元、無ければ非活性化。
RBest は Missing に戻し次反復で再ベースライン。wiki は不変 = I3)。
名前付きプロファイル指定時は非活性化のみ (ファイルは共有のため内容復元は default の操作)。他プロファイルで活性なら具現化の models を絞り直す。
→ `<|"Status"("Deactivated"|..),"Name","Profile"|>`

### ClaudeTurnWikiActiveSkills[profile:Automatic]
→ `<|name -> SKILL.md content, ..|>`

### ClaudeTurnWikiTransferSkill[name, toProfile, opts]
既存スキルを別プロファイルで検証し、そこの RBest を上回るときだけ昇格 (cross-model transfer。台帳 Action "transfer")。
Options: `"LLMFn"`, `"EvalFn"`

## Probes (validation split 相当)

### ClaudeTurnWikiAddProbe[probe] / [task, expected] / ClaudeTurnWikiProbes[] / ClaudeTurnWikiProbeFromTrace[trace]
probe = `<|"ProbeId","Task","Expected","Kind"|>` を probes/ に保存 / 一覧 /
失敗トレースから雛形生成 (純関数、Expected は Missing でユーザーが確定)。

## 注入 (I4)

### ClaudeTurnWikiWireInjection[] / ClaudeTurnWikiUnwireInjection[] / ClaudeTurnWikiInjectionStatus[]
active スキルを `Claude Directives/rules/evolved-turn-<name>.md` として具現化し
`ClaudeDirectives`$ClaudeAlwaysOnRules` へ登録 (single 経路は always-on ルール
しか届かないため。106 ルール前例)。冪等・defensive。同時具現化は
`$ClaudeTurnWikiMaxActiveSkills` (既定 3) まで。ロード時に既採用分を自動復元
(`$ClaudeTurnWikiAutoWire`)。具現化されるのは SKILL.md 本文のみ —
PURPOSE.md/パターン/台帳は決して注入されない。Unwire は全 evolved-turn-* ルールと登録を除去しキャッシュ無効化。
Summary 投影は先頭 400 字に切り詰めるため、Proposer は必須事項を冒頭に凝縮する
規約 (プロンプトで強制)。

## 定期維持 tick (観測モードの自動化)

### ClaudeTurnWikiMaintainTick[opts]
service heartbeat から呼ばれる定期ステップ = **Collect (watermark で未消費トレースのみ) +
Maintain** だけ。提案・ゲート・手順書変更は行わず Iteration も進めない (パターン集だけが
育つ)。ガード: 永続 AutoMaintain フラグ (`"Force"`->True で無視) → 最小間隔
(`MaintainIntervalSeconds`, 既定 6h) → 排他ロック `locks/maintain-tick.lock`
(対話/service カーネルの同時実行防止。`"LockStaleSeconds"` 1800 で stale は奪う) →
LLM 可用性 (`"AvailabilityFn"`; Automatic = LLMFn 明示なら常に可、
`ClaudeCode`ClaudeBackendAvailableQ` があればそれ、無ければ軽量 ping)。
消費済みマークは Maintainer 成功時のみ (失敗分は次回再挑戦)。最終 tick 時刻は毎回更新
(LLM 連打防止)。**毒トレースガード**: 同一トレース集合で連続 `$ClaudeTurnWikiMaxFailStreak`
(既定 3) 回失敗したら消費済みにして `"GaveUp"` (watermark の FailStreak/FailSetKey)。
AutoLevel が True なら Advice+Apply も行い戻り値に "Levels"。
JSON は `Developer\`ReadRawJSONString` 優先 (ImportString RawJSON は日本語で失敗する)。
→ `<|"Status"->"OK"|"Disabled"|"IntervalNotElapsed"|"Locked"|"LLMUnavailable"|"NoNewTraces"|"ParseFailed"|"GaveUp"|..., "Traces", "Maintain", "Consumed", "FailStreak", "Levels"|>`
Options: `"Force"`->False, `"LLMFn"`, `"TracesFn"`, `"AvailabilityFn"`, `"MinIntervalSeconds"`->Automatic, `"MaxFail"`->5, `"MaxPass"`->3, `"LockStaleSeconds"`->1800

### ClaudeTurnWikiSettings[] / ClaudeTurnWikiSetAutoMaintain[flag(, intervalSeconds)] / ClaudeTurnWikiAutoMaintainQ[]
設定は `<root>/settings.json` に永続化 (Dropbox 共有なので対話カーネルで ON にした値を
headless の service カーネルがそのまま読む)。Settings → `<|"AutoMaintain"(False),"MaintainIntervalSeconds"(21600),["AutoLevel"]|>`。
SetAutoMaintain → `<|"AutoMaintain","MaintainIntervalSeconds"|>`。claudecode パレット設定欄の
「Wiki: 自動維持/手動」トグル (Paid API と api.md の間) はこれを呼ぶ薄いミラー。

### ClaudeTurnWikiMaintainTickStatus[]
→ `<|"AutoMaintain","IntervalSeconds","LastTickAtUTC","TickCount","ConsumedTraces","LastResult","Lock"|>`

### service heartbeat への登録 (SourceVault_servicemanager.wl)
`SourceVaultServiceMain` の heartbeat ループが `$SourceVaultTurnWikiTickIntervalSeconds`
(既定 600s = 判定周期のみ) ごとに `ClaudeTurnWikiMaintainTick["MaxFail"->3,"MaxPass"->2]`
を `iSMSafeHook` (TimeConstrained 720s = LLM timeout 480s + 採取/適用) で呼ぶ。実際の発火は settings.json 側の
AutoMaintain / MaintainIntervalSeconds (既定 6h) が決める二段構え (Cane anomaly と同型)。
起動直後は 1 周期遅らせる (heartbeat 停止→watchdog 誤再起動の前例)。結果は
`heartbeat.json` の `"TurnWiki"->{LastTickAtUTC, LastStatus}` と service log
`TurnWikiMaintainTick` (Disabled/IntervalNotElapsed/NoNewTraces は記録しない) に出る。
service カーネルの `run.wls` に `SourceVault_mining.wl` (既定 LLM と /v1/models
プローブの所有元) と `ClaudeOrchestrator_turnwiki.wl` を単体 load するよう追加した
(`iGenRunWls`)。**ロード列は StartService 時にしか再生成されないので、反映には
`SourceVaultStartMCP["RestartService" -> True]` が必要** (`SourceVaultRestartService`
は serviceId 引数必須の低レベル API。引数なしで呼ぶと未評価で返る)。注意: Maintainer の local LLM 呼び出し
(timeout 480s) の間 heartbeat が止まるため、その数分間は health が Stale と出うる。

## モデルプロファイル (v0.2, 2026-09-08)

WikiSkill の知見 (進化スキルはモデル間で転移するが、どのスキルが効くか・どれだけ明示が要るかはモデル次第) を
**プロファイル "provider:model"** 単位の状態で実装。従来のトップレベル RBest/ActiveSkills/Iteration は
"default" プロファイル (全モデル・フィルタ無し) としてそのまま生きる (後方互換)。

- トレースに `Provider` / `Model` / `Profile` が付く。runtime トレースは `ProviderQueried` イベント
  (claudecode adapter → ClaudeRuntime, 2026-09-08)、llmlog は transcript の assistant `Model`
  (SourceVault_llmlog が持ち上げ) → digest の `Models` の順。
- `ClaudeTurnWikiProfileKey[provider, model]` / `[trace]` → `"provider:model"` (小文字、不明は "unknown")。
- `ClaudeTurnWikiCollectTraces` / `RunIteration` / `Validate` / `Propose` に `"ModelProfile" -> Automatic | key`。
  key 指定時: そのプロファイルのトレースだけ採取、RBest/ActiveSkills はそのプロファイル、検証は
  `$ClaudeTurnWikiProfileLLMFns[key]` (登録があればそのモデルで probe に答える)。
- `ClaudeTurnWikiPromote[..., <|"Profile"->key|>]` / `ClaudeTurnWikiRollbackSkill[name, key]`
  (名前付きプロファイルの rollback = そのプロファイルでの非活性化。内容復元は default の操作)。
- 具現化 rule は `tier: evolved` と `models:` (活性なプロファイル列。default で活性/未昇格なら models 行なし=全モデル) を持ち、ClaudeDirectives は
  そのモデルにだけ注入する (`ClaudeDirectiveRuleAppliesToModelQ`)。
- `ClaudeTurnWikiTransferSkill[name, toProfile]` = 既存スキルを別プロファイルで検証し、そこの RBest を
  上回るときだけ昇格 (論文の cross-model transfer。台帳 Action "transfer")。

## 適応 DirectiveLevel (v0.2)

ClaudeDirectives の DirectiveLevel (Minimal/Standard/Full = モデルがどれだけ明示指示を要るか) を失敗記録から調整する。
LLM 不使用の純算術。`$ClaudeTurnWikiLevelPolicy` = MinTraces 6 / EscalateFailRatio 0.4 / DeescalateFailRatio 0.1 / DeescalateMinTraces 12。

### ClaudeTurnWikiDirectiveLevelAdvice[opts] → {<|Profile, Provider, Model, Traces, Fails, FailRatio, Current, CurrentSource, Base, Advised, Change, Reason|>..}
プロファイルごとに Escalate (失敗率高) / Deescalate (十分な件数で失敗率低、ただし能力表の baseline より下げない) / Keep。
Options: `"Traces"` -> Automatic (raw ストア) | list。

### ClaudeTurnWikiApplyDirectiveLevels[advice | Automatic, opts]
`<root>/directive-levels.json` に永続化 (Dropbox 共有) + `ClaudeDirectives`ClaudeSetDirectiveLevelOverride` + 台帳に `LevelChanged` 追記。
ロード時に resolver フック (`ClaudeDirectives`$ClaudeDirectiveLevelResolver`) を登録するので、別カーネルでも永続値が効く。
Options: `"DryRun"` -> False
→ `<|"Status"("NoChange"|"DryRun"|"OK"),"Applied","Levels"|>`

### ClaudeTurnWikiDirectiveLevels[] / ClaudeTurnWikiSetAutoLevel[flag] / ClaudeTurnWikiAutoLevelQ[]
永続値の読み出し (profile -> `<|Level, At, Reason|>`) / settings.json の AutoLevel (True なら維持 tick が Advice+Apply も行う。tick 戻り値に "Levels") / フラグ読み出し。

## View (core/View 対, v0.2)

core = List[Association] (連鎖可能・上限なし)、View = `Pane[Dataset]` (`$ClaudeTurnWikiViewMaxRows` 既定 25、超過分は「... N more」表示)。

- `ClaudeTurnWikiLedger[opts]` / `ClaudeTurnWikiLedgerView[opts]` — skill-impact 台帳 (jsonl、新しい順: At, Iteration, Profile, Outcome, Action, Name, Score, RBest, Rationale, Content, Edits)。Options: `"Profile"`->All|key, `"Outcome"`->All|Accepted/Rejected/NoAction/RolledBack/LevelChanged, `"Limit"`->All|n。View 各行に SKILL.md を開くボタン。
- `ClaudeTurnWikiLog[opts]` / `ClaudeTurnWikiLogView[opts]` — Wiki Maintainer の進化ログ (logs.md) を `## <iso> iteration k` 単位に構造化 `{<|At, Iteration, Text|>..}` 新しい順。Option `"Limit"`。
- `ClaudeTurnWikiTraces[opts]` / `ClaudeTurnWikiTracesView[opts]` — raw トレースのメタ (本文なし: TraceId, Iteration, Kind, Provider, Model, Profile, Source, Task(冒頭 120 字), Chars, File)。Options: `"Iteration"`->All|k, `"Profile"`->All|key, `"Kind"`->All|"pass"|"fail"。SourceVault があれば PL 0.75 の private view で包む。
- `ClaudeTurnWikiProfiles[]` / `ClaudeTurnWikiProfilesView[]` — プロファイル別 Profile, Provider, Model, RBest, ActiveSkills, Traces, Fails, FailRatio, DirectiveLevel, LevelSource, LastLedgerAt, LedgerEntries, Iteration。
- `ClaudeTurnWikiTimelineView[]` — 台帳の検証 Score と RBest を時系列に (DateListPlot、プロファイル別。Score 無しなら notice)。
- `ClaudeTurnWikiDashboard[]` — 上記 (status, profiles, ledger, log, timeline, directive levels) を 1 枚に。

## raw 修復 (v0.2)

### ClaudeTurnWikiRepairRawEncoding[opts]
9/8 以前の raw トレースは `ExportString["RawJSON"]` (ISO-8859-1 バイト列) を UTF-8 ストリームに書いて二重符号化していた (23 件中 18 件が文字化け)。二重符号化 (全コード <256 かつ UTF-8 として復号可能) の Task/Text だけを復号し直す。`iTWToJSON` のフォールバックも `ExportByteArray`→UTF-8 に修正済。
Options: `"DryRun"` -> False
→ `<|"Scanned","Repaired","DryRun","Files"|>`

## 状態・診断

### ClaudeTurnWikiInitialize[] / ClaudeTurnWikiStatus[] / ClaudeTurnWikiState[] / ClaudeTurnWikiCheckIsolation[]
ワークスペース作成(冪等、seed ファイル含む) / 概況 (Root, Iteration, RBest, ActiveSkills, Patterns, Probes, Isolation; v0.2: Profiles / AutoLevel / DirectiveLevels を含む) / ループ状態 (RBest/Iteration/ActiveSkills/Profiles/UpdatedAt) /
I4 隔離検査 `<|"OK","Detail"|>` (違反時は RunIteration が IsolationViolation で停止)。

## 設定変数

### $TurnWikiVersion
型: String, 初期値: "0.2 (2026-09-08)"
実ロードマーカー。

### $ClaudeTurnWikiRoot
型: Automatic|String, 初期値: Automatic (= `<pkg>/Claude TurnWiki`)

### $ClaudeTurnWikiLLMFn
型: Automatic|Function, 初期値: Automatic
fn[prompt, sys]→String|Missing。既定 LLM (SourceVaultQueryLocalLLM) を上書き。

### $ClaudeTurnWikiLLMTimeout
型: Integer(秒), 初期値: 480
既定ローカル LLM 呼び出しの timeout (27B は ~12 tok/s、Maintainer JSON が 1500 トークン超で 180s だと切断された)。

### $ClaudeTurnWikiMaxActiveSkills
型: Integer, 初期値: 3

### $ClaudeTurnWikiFailureMarkers
型: {String..} (regex), 初期値: SyntaxError, RepairRequest, ValidationRepair, \$Failed, FatalFailure, ExecutionFailed, TransportRetryExhausted, CallContractViolation, ToolLoopBudgetExhausted
llmlog 分類正規表現。

### $ClaudeTurnWikiMinTraceChars
型: Integer, 初期値: 200
自動採取トレースの最小文字数 (TracesFn 注入は対象外)。

### $ClaudeTurnWikiAutoWire
型: Boolean, 初期値: True
ロード時に採用済みスキルを再登録。

### $ClaudeTurnWikiInjectionEnabled
型: Boolean, 初期値: True
Promote/Wire による directive 具現化のゲート。

### $ClaudeTurnWikiMaxFailStreak
型: Integer, 初期値: 3
tick の毒トレースガード閾値 (到達で "GaveUp")。

### $ClaudeTurnWikiDirectiveRootOverride
型: Automatic|String, 初期値: Automatic
テスト用。本番は `ClaudeDirectives`ClaudeResolveDirectiveRoot`。

### $ClaudeTurnWikiProfileLLMFns
型: Association (profileKey -> fn[prompt, sys]), 初期値: <||>
そのプロファイルのモデルで probe に答えさせる検証用 LLM。無いプロファイルは既定ローカル LLM。

### $ClaudeTurnWikiLevelPolicy
型: Association, 初期値: MinTraces 6 / EscalateFailRatio 0.4 / DeescalateFailRatio 0.1 / DeescalateMinTraces 12
適応 DirectiveLevel の閾値。

### $ClaudeTurnWikiViewMaxRows
型: Integer, 初期値: 25
...View 関数の描画行上限 (core は無制限)。

## 検証

- headless: `wolframscript`/`wolfram.exe -noinit -noprompt -script` で
  `test codes/ClaudeOrchestrator_turnwiki_test.wl` (117 checks、密閉 temp root +
  mock LLM。実ストア/実 directives 不干渉)。
- 実 LLM は LM Studio (SourceVaultQueryLocalLLM) が既定 = トレース内容を cloud に
  出さない。cloud 利用は "LLMFn" 明示注入。SourceVaultQueryLocalLLM は
  `reasoning_effort: "none"` を送る (2026-09-02 実測: qwen3.8-27b は
  `enable_thinking: false` を無視して思考を数分続け、480s でも JSON に達しなかった。
  none 指定で 14s)。独自 "LLMFn" を注入するときも思考を切ること。