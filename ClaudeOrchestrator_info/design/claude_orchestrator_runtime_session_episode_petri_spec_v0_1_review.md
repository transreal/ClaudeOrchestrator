# RuntimeSession episode / Petri-net 統合仕様 v0.1 レビュー

**中核原則(episode 粒度の Petri 管理・turn/tool loop の Runtime 閉じ込め)は実コード検証でも支持できる。ただし v0.2 で解消すべき構造欠陥が Petri net の event 到達性に 1 件、engine 変更リストの欠落が 1 件、Runtime 側作業量の過小評価が 3 件、attempt スコープの穴が 1 件ある。**

- 対象: claude_orchestrator_runtime_session_episode_petri_spec_v0_1.md(1722 行)
- 日付: 2026-07-10
- レビュー方法: 仕様精読に加え、仕様が引用する現行資産を実測検証
  - ClaudeRuntime.wl(4253 行)/ ClaudeOrchestrator_workflow.wl(5227 行)/ ClaudeRuntime_externalrunner.wl(1246 行)/ NBAccess.wl(11054 行)
  - conductor policy spec v0.2・同 review・multi_agent_orchestration_spec との整合照合

---

## 1. 結論

### 1.1 総合判定

| 対象 | 判定 | 理由 |
|---|---|---|
| 中核原則(§0–§1: episode 境界のみ Petri 管理) | **Go** | granularity 条件は妥当。AwaitingLLM one-shot 契約(1 consume / 1 produce / entry 削除)は実コードで確認でき、§10.2「転用しない」判断は正しい |
| Petri net 構造(§9) | **条件付き Go** | ROUTE が EpisodeRunning のみを入力とするため、待機 place 滞留中の terminal event に消費経路がない(→ §3.1)。pairing guard の engine 実装手段が §10 に無い(→ §3.2) |
| durable bridge(§11) | **条件付き Go** | attempt スコープの穴(→ §3.3)と dedup 判定材料の詰め(→ §4.7)が必要。方式自体(at-least-once + effectively-once)は健全 |
| Runtime session facade(§12) | **条件付き Go** | §12.2 の mapping 表で「変換」と書かれた 3 機構(tool 単位 approval / BudgetInterrupt pause / tool journal)は現行 Runtime に存在せず全て新設(→ §2) |
| in-kernel MVP backend(§8.2) | **条件付き Go** | 「誰が内部 loop を回すか」の実行モデルが未規定。FE 凍結の既往(mailfetch / schedule-noescalate)がある環境なので tick 契約の明文化が必須(→ §3.5) |
| external session runner(Inc9) | **Go(後段)** | 下位 primitive(launcher / pid.json identity / orphan recovery / atomic status / encrypted bundle)は実在・流用可。双方向 command/event protocol は全面新規だが、仕様 §2.2 の不足認識と一致しており見積は正しい |
| conductor v0.2 / multi_agent との統合 | **条件付き Go** | 階層合成(RunController → child → episode subnet)は矛盾なく成立。ただし予算フィールド名の不一致、approval/durable completion の二重実装、PrivacyLabel スケール未固定を freeze 前に解消要(→ §5) |

### 1.2 実測で確認できた強み

- **行番号アンカー 8 点すべて正確**(ClaudeRuntime.wl:519/1497/2552/3474、workflow.wl:126/810/1439–1484/1886–1947、externalrunner.wl:1104)。仕様は現物コードを正しく参照している。
- **AwaitingLLMTransitions の one-shot 契約は実装どおり**(consume=1437、registry 追加=1439–1442、callback で produce+KeyDrop=1925/1944–1947、二重 callback は silent discard)。「session の複数 boundary event に転用しない」(§10.2)というこの仕様の中心的判断は、コードで裏付けられた。
- **backend registry の前例が engine 側に既存**(`$ClaudeExternalBackends` + `ClaudeRegisterExternalBackend`、workflow.wl:3063–3100)。§8.1 の session backend registry は同じパターンの複製で作れる。
- **NBAccess の canonical EffectClass 機構(override 表 + fallback 分類 + 最厳 eligibility 集約)は §16.3 の要求をすでに満たす**。PolicySnapshot の SHA256 digest(KeySort + Sort + InputForm 正規化、NBAccess:10923–11049)は fail-closed 検証込みで完備。
- **§2.2 の不足リストは概ね正確**。特に「AwaitingLLM は複数 event に合わない」「checkpoint は in-memory」「snapshot は宣言的復元しない」は全て実測一致。

---

## 2. 仕様の現状認識の誤差(実測との差分)

§2.1 の資産表は概ね正しいが、以下は仕様の記述が実態より楽観的で、**Inc4/Inc5 の作業量を過小評価させる**。v0.2 で §2.2(不足リスト)へ移すべき。

### 2.1 Runtime の非ブロック基盤は AwaitingLLM 系ではない

ClaudeRuntime の非同期化は「LLMGraphDAG の onComplete handler + shared polling tick(`iAsyncExecutionTickFn`/`iAsyncToolExecTickFn` が `WaitNext[{future}, 0.01]` でポーリング)」であり、Orchestrator の URLSubmit/`ClaudeCompleteHandlerOutput` 経路とは**別実装**。`ClaudeCompleteHandlerOutput`・`URLSubmit` は ClaudeRuntime.wl に一切出現しない。

**影響**: §12.3「最初の turn だけを facade が起動し、以後は Runtime 内部で継続」は、in-kernel backend では「Runtime の既存 tick 群が継続を駆動する」ことを意味する。これを §12 に明記しないと、実装時に「誰が session loop を pump するのか」で迷走する(§3.5 と連動)。

### 2.2 AwaitingApproval は proposal 粒度であり、tool 単位の実行前 pause は存在しない

現行の `AwaitingApproval`(状態 + `PendingApproval` 退避 + `ClaudeApproveProposal`/`ClaudeDenyProposal`)は **LLM 提案 expression の実行前承認**。§12.4/§13.2 が要求する「pre-authorized 外 tool を検出して ToolCallId 付き ApprovalRequired を発行し pause する」機構は、async tool loop(`iToolUseAndContinue`/AsyncToolExec)に**存在しない**。純 pipeline API 側には「approval は Workflow 層が担当」と明記されている(ClaudeRuntime.wl:202/209)。

**推奨修正**: §12.2 の mapping 行「approval boundary: Runtime AwaitingApproval を control event に変換」を「**tool loop 内に新設する pre-execution approval gate** + 既存 AwaitingApproval の control event 化」に改め、Inc4 の作業項目・受け入れ条件に含める(現行 Inc4 受け入れ「Runtime AwaitingApproval で tool は未実行のまま停止」は、この新設なしには検証不能)。

### 2.3 BudgetExhausted は Failed 終了であり pause-resume-with-grant が無い

`BudgetExhausted`/`ToolLoopBudgetExhausted` は EventTrace 上のイベントで、直後の turn outcome は `Failed`。**「停止して grant を待ち、累積上限を書き換えて同一 episode を再開する」状態機械は未実装**。§12.2「BudgetExhausted → BudgetInterrupt に変換」はソース信号の転用に見えるが、実際は Runtime 内部に suspend 状態と grant 受理・上限差し替え・再開の一式を新設する話である。Inc5 の作業項目として明記すべき。

### 2.4 tool journal・privacy label は Runtime state に皆無

`ToolCallId` / idempotency key / Prepared–Committed–Failed journal は 0 件(最近縁は UpdatePackage 用 transaction pipeline で用途が別)。runtime state に privacy 系フィールドも無い(RedactResult と ConfidentialLeakRisk 分類のみ)。これは §2.2 で不足と認識済みだが、**§12.4 の tool call 7 ステップ(ToolCallId 発行→NBAccess 検証→予約→journal→実行→記録→Commit/Fail)は既存 loop の全 tool 実行経路の改修**であることを Inc4/Inc6 の規模感として書いておくべき。

### 2.5 "LLM" Executor は存在しない

engine の Executor は `PureFunction`/`ClaudeRuntime`/`PackageManager`(stub)/`External`/`Subkernel` で、AwaitingLLM は「handler が `Status->"AwaitingLLM"` を返す」status 契約で実現される。§20.1「WorkerKind="LLMCall" は従来の atomic AwaitingLLM transition に compile」は正しいが、"LLM executor" という語を使う箇所があれば status 契約ベースに言い換えること。

### 2.6 PackageManager executor は stub

§9.3 が CommitArtifact を PackageManager/FinalActionQueue に割り当てるが、engine の `"PackageManager"` branch は stub(workflow.wl:1545–1549)。Inc8 の依存作業として明記。

### 2.7 既存 "ClaudeRuntime" executor との関係が未記述

engine には既に `iExecuteClaudeRuntimeBranch`(workflow.wl:1702、Day 4c)がある。新設する `"RuntimeSession"` executor とどう住み分けるか(単発 turn 用として維持? deprecate?)を §10.1 に一文追加すべき。放置すると「Runtime を呼ぶ executor が 2 系統」になり、後続の保守で混乱する。

---

## 3. 設計上の問題点(P0 — 実装着手前に仕様改訂)

### 3.1 event routing の place 到達性欠落(最重要)

§9.1 の net では `RouteControlEvent` が **EpisodeRunning(RUN)+ SessionEvents(EV)** を入力とする。しかし lease token は ObservationWait / CommandPending / BudgetReview / ArtifactPending / CheckpointReview に滞留し得る。その間に Runtime が `Failed` / `EnvironmentLost` / `Cancelled` を発行すると、**RUN に token が無いため event を消費できる transition が存在しない**。

具体的な死路:

~~~text
episode が ObservationWait(人間の回答待ち)
→ runtime が idle timeout で Failed event (seq N+1) を発行
→ bridge は deposit できる(seq N は appl用済み)が、
   ROUTE は RUN token を要求 → 発火不能
→ Failed event が SessionEvents に滞留、episode は永久に ObservationWait
~~~

同型の問題は Cancel にもある: `ClaudeRuntimeSessionCancel` → QueueSessionCommand は lease がどの place にあっても発火できなければならないが、§9 にはその arcs が無い。

**推奨修正**: §9 に **event 種別 × lease place の到達性行列**を追加し、次のいずれかを規定する。

1. 各待機 place ごとに terminal/interrupt event 消費 transition を張る(place 数 × event 種別ぶんの transition 追加。Petri としては素直だが transition 数が増える)。
2. lease を単一 place(EpisodeActive)に置き、制御状態を token payload の `ControlState` フィールドで表す(place 遷移は Requested → Active → Terminal のみ。event routing は全て EpisodeActive + SessionEvents の guard 付き transition で行う)。状態爆発を避けるという本仕様の思想には (2) の方が整合的。

どちらを採るにせよ、「Failed/Cancelled/EnvironmentLost はすべての非 terminal 状態から消費可能」「Cancel command はすべての非 terminal 状態から発行可能」を不変条件(I13)として追加すべき。§24.2 の integration テストにも「ObservationWait 中の runtime 死亡 → EpisodeFailed 到達」を加える(→ §7)。

### 3.2 pairing guard の実装手段が §10 の engine 最小変更に無い

§9.4 の pairing guard(event と lease の EpisodeId/SessionId/Attempt/EventSeq/hash 照合)は、**2 種類の input token の join 条件**である。実測では engine の binding 列挙(`iEnumerateBindings`)は arc の TokenKind フィルタのみを持ち、**token 間の値結合(event.EpisodeId == lease.EpisodeId)を binding 時に評価する guard 機構は存在しない**。

guard 無しで発火してから handler 内で不一致を検出しても、token は既に consume されている(consume は fire 時)。「不一致 event は consume せず quarantine へ」(§9.4)を実現するには、**binding 列挙段階で guard を評価する engine 拡張**が必要であり、これは §10.1 の Token kind / Executor 追加と同格の engine 変更である。

**推奨修正**: §10.1 に「WorkflowTransition に `Guard`(binding → True|False)を追加し、iEnumerateBindings が multi-input binding ごとに評価する」を明記。複数 episode 並走時(§24.2 test 10)の誤 pairing 防止はこの guard が唯一の防壁なので、Inc2 の受け入れ条件に guard の単体テストを追加する。

### 3.3 SessionCommand に Attempt が無く、spool/cursor も attempt スコープでない

- §7.8 SessionCommand は SessionId/EpisodeId/ExpectedAfterEventSeq を持つが **Attempt が無い**。outbox は crash 後 replay されるため(§11.3)、attempt 1 で queue された `ProvideObservation` が resume 後の attempt 2 プロセスへ配送され得る。CommandId 冪等では防げない(attempt 2 にとっては未知の CommandId なので受理してしまう)。
- §12.5 で EventSeq は attempt ごとに 1 から再開するのに、§11.1 の spool は `inbox/<event-seq>-<event-id>.wxf` のフラット構成で、§8.1 の `PollEvents[handleRef, afterSeq]` の cursor も attempt を持たない。attempt を跨いだ seq の衝突・cursor の曖昧さが生じる。

**推奨修正**: (a) SessionCommand に `Attempt` を必須追加し、Runtime は不一致 attempt の command を `Rejected(StaleAttempt)` にする。(b) spool を `<episode-id>/<attempt>/inbox/...` と attempt サブディレクトリ化するか、cursor を `(Attempt, EventSeq)` の組にする。(c) §9.4 と同様に「旧 attempt の command が新 attempt を動かしてはならない」を不変条件へ(I6/I7 の command 側対称)。

### 3.4 granularity 条件と CheckpointPolicy の干渉

§1.4/§9.5 は「内部 turn 数が増えても boundary event 数 B が同じなら transition 数は増えない」を構造条件とするが、§7.5 の既定 `CheckpointPolicy["AfterToolCalls"->5, "EverySeconds"->300]` では **CheckpointCreated が内部活動量に比例して発生し、その各件が control event として RouteControlEvent → CheckpointReview → RUN を回す**。50 tool call の episode は 5 tool call の episode より checkpoint 系 transition が約 10 倍多く、§24.5 の granularity テストは mock(同一 script)でしか成立しない。

**推奨修正**: checkpoint を二層に分ける。

- **routine checkpoint**(AfterToolCalls/EverySeconds 由来): Runtime が journal に記録し、**telemetry として ref のみ**を残す。Petri へは流さない(次の control event の `LatestCheckpointRef` に piggyback、または lease 更新のみ)。
- **boundary checkpoint**(BeforeNonIdempotentTool / AtSoftBudgetThreshold / OnInterrupt / 明示 RequestCheckpoint): これだけを CheckpointCreated control event として Petri に載せる。

これで §9.5 の O(1+B) が実 policy 下でも成立し、§24.5 に「実 CheckpointPolicy での再測定」を追加できる。

### 3.5 in-kernel backend の実行モデル未規定

`ClaudeRuntimeInKernel` は MVP の主役だが、「誰が session の内部 loop を進めるか」「poll tick と Runtime tick の関係」「main kernel をどれだけ占有してよいか」が仕様に無い。実測どおり Runtime の継続は polling tick 駆動(§2.1)なので実現手段はあるが、この環境には **poll-tick 内の同期処理が FE を凍らせた既往が複数ある**(メール fetch の同期 IMAP 120s 占有、schedule 照会の poll-tick 内 NotebookWrite × Dynamic デッドロック)。

**推奨修正**: §8.2 の ClaudeRuntimeInKernel 行、または §11.2 に次を明記する。

1. session の内部 loop は Runtime の既存 async tick(DAG onComplete + AsyncToolExec tick)が駆動し、`ClaudeRuntimeSessionPollTick` は **event の搬送のみ**を行う(model call や tool 実行を tick 内で同期実行しない)。
2. tick 1 回の実行時間上限(例: 200ms)と、tick 内での NotebookWrite / Dynamic 依存操作の禁止。
3. tick の再入 guard(前回 tick 未完了なら skip)。二重 tick は §11.2 の「temp → rename → submit → mark」列の途中競合を生む。
4. tick の実行主体(FE ScheduledTask / SessionSubmit / service のどれか)と、既存の `ClaudeExternalJobPollTick`・Runtime async tick との統合方針(tick 系統が 3 つに増えるので、少なくとも起動・停止・監視を一元化する)。

---

## 4. 設計上の課題(P1 — Inc1–3 実装中に確定)

### 4.1 「一度に一個の未解決 control event」の定義と head-of-line blocking

§11.2 の「LastAppliedEventSeq が進むまで次を投入しない」は、「applied」の定義次第で挙動が変わる。**applied = RouteControlEvent が consume して routing した時点**(解決 = observation 提供済み、ではない)と明記すべき。さもないと ObservationWait 解決待ちの間 Failed event が搬入されず、§3.1 の修正を入れても bridge 側で詰まる。あわせて「terminal event(Failed/Cancelled/EnvironmentLost)は順序保証の例外として先行 event を追い越して搬入してよいか」を決めること(推奨: 追い越し可、ただし搬入時に未解決 event を quarantine ではなく superseded として記録)。

### 4.2 LastAppliedEventSeq の二重管理

lease token(§9.2)と ActiveSessionEpisodes registry(§10.5)の双方が LastAppliedEventSeq を持ち、乖離し得る。**正本は lease token とし、registry は lease から導出される index(poll/recovery 対象の列挙用)** と明記する。registry 更新は transition の副作用として同一箇所で行い、restore 時は marking から再構築する。

### 4.3 ObservationWait / ApprovalWait の時計と期限

- `MaxIdleSeconds`(§7.3)は observation/approval 待ちの間も進むのか。進むなら人間の返答が遅いだけで episode が死ぬ。進まないなら放棄された episode が lease を掴んだまま workflow MaxWait まで生きる。**推奨**: Runtime idle clock は「Runtime が動ける状態での無活動」のみ計測し、外部待ちは Orchestrator 側の per-wait 期限で管理する。
- ApprovalRequired には `ExpiresAt` があるが **ObservationRequired には無い**(§13.1)。対称に追加し、期限切れの既定遷移(FinalizePartial / Failed)を定める。

### 4.4 TokenId dedup の判定材料

実測では `ClaudeSubmitToken` に dedup は皆無で、consume された token は Tokens registry から KeyDrop される。よって §10.3 の「Tokens または marking に存在」だけでは**適用済み event の再投入を防げない**。Trace の TokenSubmitted は恒久保持されるが、event ごとの Trace 全走査は O(trace 長)。**推奨**: 判定の正本は §11.1 の delivery-index(durable、episode 局所、O(1))とし、engine 側 dedup は「同一 TokenId が現 marking に居る場合の二重投入防止」という補助線に限定する、と役割分担を明記。

### 4.5 ライセンス席と SessionSlots の接続

この環境の実測では独立 wolframscript プロセスは 4 席(subkernel は 16)。`ClaudeRuntimeExternalProcess` backend は 1 session = 1 独立プロセスなので、**MCP 共有カーネル + サービス + FE が常駐する実運用では同時 external session は 1–2 が上限**になり得る。§9.2 の SessionSlots/EnvironmentSlots を静的定数にせず、seat probe(SourceVault_diagnostics の実測 probe / SeatBroker)と接続すること、および席不足時の分岐(in-kernel/subkernel への降格 or 待機)を §20.2 の resolver 条件に加えることを推奨。Inc9 の受け入れに「席飽和時に誤って 5 本目を起動しない」を追加。

### 4.6 Notebook commit の FE 依存と receipt 順序

§17.3 の CommitMode "Notebook" は FinalActionQueue 経由だが、FinalActionQueue は FE 前提かつ非同期になり得る。「receipt 永続化成功後にのみ成功 path へ進む」(§17.3)を満たすには、**committer transition が FinalAction の完了と notebook 書込み結果を同期確認できる API 契約**が要る。headless(service / 配車ノード)では "Notebook" mode は不可なので、CommitMode を backend/environment capability として gate する(§8.1 Capabilities に "NotebookCommit" を追加)。

### 4.7 hash 正規化仕様

EventHash / CommandHash / GrantHash / ContentHash の計算法(対象フィールド集合、Association の canonical 化)が未規定。WL の Association はキー順が保存されるため、**KeySort 再帰 + WXF bytes(または InputForm)→ SHA256** の canonical 化を一箇所で定義しないと、書き手と検証側で hash が割れる。NBAccess の `iNBNormalizePolicySnapshotPayload`(KeySort + Sort + InputForm、version 非依存)が既製の前例なので流用を明記。また **AccessSpecHash は現状どこにも存在しない**(PolicySnapshot digest のみ完備)ため、Inc1 の schema 実装項目に「AccessSpec canonical hash 関数の新設」を明記。

### 4.8 quarantine の保管先・期限・解放条件

§9.4(不一致 event)と §18.3(ack 無し kill session)の quarantine について、(a) 保管先(episode spool 内 `quarantine/`?)、(b) 誰がいつ reconcile するか(`ClaudeRecoverRuntimeSessions` の責務?)、(c) cash/environment lease の解放条件と上限時間、が未規定。放置すると「lease が返らない episode」が溜まる。I10(lease 高々一回返却)の裏面として「有限時間内に必ず返却される」ことも運用条件に入れる。

### 4.9 ExpectedAfterEventSeq の意味

§7.8 の `ExpectedAfterEventSeq` の判定規則が無い。「Runtime は自分の最新 emit 済み seq がこれと一致する場合のみ受理(不一致は Rejected(StaleContext))」なのか、単なる参考情報なのかを定義する。前者なら command と event の競合(command 発行と同時に Runtime が新 event を emit)時の再発行手順も書く。

### 4.10 budget reservation の resume 時 reconciliation

§14.2 の予約は Runtime local だが、crash 時に予約が残ったまま checkpoint に `ReservedCashUSD` が記録される。resume(Attempt+1)時に **未確定予約をどう解消するか**(tool journal の Prepared と突き合わせて解放 or 保守的に消費扱い)が未規定。あわせて §15.1 の「BudgetSnapshot が ledger より後退していない」検査について、**単調性を要求するフィールドの列挙**(累積 counter は単調、Reserved は増減可)を §7.4 に付記する。

### 4.11 staging root と EffectClass の語彙マッピング

NBAccess の書込み境界は「AllowedDirectories allowlist + mode enum」であり、§16.2 の「単一 WritableStagingRoot + final target 到達不能 + staging 外 temp 禁止」はその上に新設する semantics になる。また §16.3 の EffectClass 語彙(FileRead/FileWrite/Network/…)と NBAccess 現行語彙(PureComputation/NotebookMutation/ReadOnlyFileSystem/DesktopAction/…)は不一致なので、**対応表を仕様付録に置く**(canonical は NBAccess 側、と §16.3 の原則どおり明記)。ToolCallId 単位 scoped permit は NBAccess 内で Phase 2b として予告のみ(未実装)である点も §2.2 不足リストに追加。

---

## 5. 関連仕様との整合(v0.2 で明文化すべき統合規定)

### 5.1 Inc0 と conductor v0.2 Inc0A–0D の対応を明示する

新仕様 Inc0 の 4 項目は conductor **Inc0A + Inc0B と厳密一致**。一方 conductor **Inc0C(予約 ledger / status 語彙 / 多重上限 counter)と Inc0D(RunController 二層 / approval-resume / durable completion / snapshot 整合)は新 Inc0 に含まれず**、本仕様は同等機能を episode レイヤに自前実装する(Inc5 / §13 / §17.3 / §10.4)。これ自体は選択として成立するが、**「Inc0 = conductor Inc0A/0B を指す。Inc0C/0D 相当は本仕様 Inc5/§13/§17.3 が episode レイヤで引き受け、run レイヤの conductor 実装とは §5.3 の正本規定で接続する」という一文を §23 に置く**こと。無言のままだと同じ概念が二重実装される。

### 5.2 予算フィールド名の統一(schema freeze 前に必須)

episode 層(本仕様)と run 層(conductor CostLedger / reservation ledger)は別オブジェクトだが、集約経路(BudgetSnapshot → run ledger)で突き合わせるため、命名は揃えるべき:

| 概念 | conductor v0.2 | 本仕様 v0.1 | 推奨 |
|---|---|---|---|
| 現金上限 | MaxCostUSD | MaxCashUSD | どちらかへ統一 |
| 実績現金 | ActualUSD | ActualCashUSD | 〃 |
| 予約現金 | ReservedUSD | ReservedCashUSD | 〃 |
| context 上限 | MaxContextTokensPerStep | MaxContextTokensPerCall | 〃(意味が同じなら) |
| call 上限 | MaxCalls | MaxModelCalls + MaxTurns | 対応関係を定義 |
| 予約式 | Actual + Reserved + New ≤ MaxCostUSD | Used + Reserved + New ≤ GrantedLimit | 用語を揃える |

`UnknownCostPolicy` と `CostSource` の enum は既に完全一致しており、これは維持する。

### 5.3 approval / durable completion の正本一元化

conductor v0.2 は run レイヤに approval-resume(`ClaudeApproveWorkflow`、§6.4)と durable completion(Finalize transition、§6.5)を持つ。本仕様は episode レイヤに `GrantScopedApproval`(§13.2)と commit receipt(§17.3)を持つ。階層としては両立するが、**「workflow(step)承認は conductor 機構、episode 内 tool/artifact 承認は本仕様機構。後者の未解決 approval は前者の workflow status に集約表示する」等の正本規定**を §13 に一段追加する。UI(ClaudeRuntimeSessionApprove と ClaudeApproveWorkflow)の使い分けもここで決まる。

### 5.4 PrivacyLabel のスケールと境界を固定する

本仕様は `PrivacyLabel -> _?NumericQ` のみで範囲・境界が無い。conductor は [0,1] スケール・cloud 境界 0.5、NBAccess の PrivacyLevel/EffectiveRiskScore も同じ向き(大きいほど private、unknown → 1.0 最厳、混在 → Max)。**「本仕様の PrivacyLabel は conductor / NBAccess と同一の [0,1] スケール・同一 cloud 境界を用いる」と §16.4 に明記**する。§9.4 pairing guard や I2 の hash 対象にも影響するため freeze 前に。

### 5.5 語彙の細部統一

- SessionProfile サブフィールド: conductor §5.5 の `TurnBudget/ToolPolicy/EnvironmentRef` vs 本仕様 §20.1 の `BudgetProfile/ToolPolicyRef/CheckpointProfile`。本仕様側を正として conductor v0.3 で追随、と決めておく。
- Role 語彙: multi_agent は 6 role、conductor は 5 role、本仕様 §20.1 は無制約。マッピング表を一つ置く(本仕様は無制約で受け、conductor compile 時に検証、が現実的)。
- ArtifactSpec(multi_agent: inline Payload + Status)→ ArtifactCandidate(ref-only、Status は event Type へ移設)の互換規定: 既存 LLMCall worker の ArtifactSpec を episode 出力に変換する adapter の有無を §21.3 に一文。

---

## 6. 軽微な指摘

1. **SessionControlEvent に BackendInstanceId が無い**。StartEpisode は BackendInstanceId を返す(§8.1)ので、reattach 検証(§15.2 step 5「identity verified」)に使うなら event にも載せるか、検証は handleRef 側のみで行うと明記。
2. **EventHash は完全性のみで真正性が無い**。spool は同一ユーザーのローカル filesystem なので脅威モデル上は許容だが、「event の真正性は OS ユーザー境界に依存し、HMAC は将来拡張(universal MCP access の grant HMAC と同系)」と一文置くと良い。
3. **CommandPending の多重度**: 同時に複数 command(例: GrantBudget + RequestCheckpoint)を発行できるのか、1 episode 1 未解決 command なのかを §11.3 に明記(推奨: MVP は 1、event 側 §11.2 と対称)。
4. **start-spec.wxf.enc の鍵管理**: externalrunner の SourceVault crypto(SystemCredential backend、fail-closed)を流用と明記すれば Inc9 の設計が一意になる。
5. **`"Redacted"` ConfidentialHandling は現行 externalrunner に未実装**(EncryptedBundle/ReferenceOnly のみ)。enum に入れるなら Inc9 の作業項目へ。
6. **ResourceSlot token kind**: 現行 engine は kind 自由文字列 + per-place AcceptedKinds のみで、集中 validator は存在しない。§10.1 の「validator に追加」は「validator を新設し、その初期語彙に追加」と読み替えられるよう記述を調整。
7. §2.1 の表で「AwaitingLLMTransitions … model call/external job では維持」とあるが、external job の完了反映は AwaitingLLM とは別経路(status.json poll → `iExternalReflectCompletion`)なので、正確には「atomic な単発非同期作業では維持」。

---

## 7. テスト仕様(§24)への追加提案

§24 は crash window・granularity・safety とも水準が高い。以下を追加すると §3 の欠陥の再発を防げる。

1. **event × place 到達性行列テスト**: すべての非 terminal 待機 place(ObservationWait/CommandPending/BudgetReview/ArtifactPending/CheckpointReview)× {Failed, Cancelled, EnvironmentLost, BudgetInterrupt} で episode が正しく terminal / review へ到達すること。特に「ObservationWait 中の runtime 死亡 → EpisodeFailed → lease 返却」。
2. **待機中 Cancel**: 各待機 place で `ClaudeRuntimeSessionCancel` → §18.3 手順が完走すること。
3. **stale attempt command**: attempt 1 の outbox に残った command が attempt 2 の runtime に `Rejected(StaleAttempt)` されること(§3.3 の受け入れ)。
4. **pairing guard の binding テスト**: 2 episode 並走 + 交差 event で guard が誤 binding を binding 段階で弾くこと(consume されないこと)。
5. **poll tick 再入**: tick 実行中に次 tick が起動しても event/token が重複しないこと。
6. **席飽和**: SessionSlots=実測席数で、飽和時に新 episode が待機し、誤って起動もタイムアウト誤判定もしないこと。
7. **実 CheckpointPolicy での granularity 再測定**: mock script 一致テスト(§24.5)に加え、`AfterToolCalls->5` の実 policy 下で Case A/B の control transition 数が O(1+B) に収まること(§3.4 の二層化の検証)。
8. **FE 応答性**: in-kernel backend の 10 tool iteration 中、poll tick 1 回の壁時計時間が上限以下であること(§3.5-2 の検証)。
9. **Notebook commit receipt 順序**: FinalActionQueue 経由 commit で「receipt 永続化 → Completed」の順序が crash 挿入下でも保たれること。

---

## 8. v0.2 への変更要求まとめ

**P0(schema freeze・実装着手前)**

1. §9: event × place 到達性の再設計(単一 EpisodeActive place + ControlState 化を推奨)と不変条件 I13 追加(§3.1)
2. §10.1: transition Guard(multi-token join)を engine 変更として追加、Inc2 受け入れに guard テスト(§3.2)
3. §7.8/§11.1/§8.1: SessionCommand に Attempt、spool/cursor の attempt スコープ化(§3.3)
4. §7.5/§9.5: checkpoint の telemetry / control 二層化で granularity 条件との矛盾解消(§3.4)
5. §8.2/§11.2: in-kernel backend の実行モデル(pump 主体・tick 時間上限・NotebookWrite 禁止・再入 guard)(§3.5)
6. §12.2/§23: 「変換」3 項(tool 単位 approval / BudgetInterrupt pause / tool journal)を「新設」と改め Inc4/5/6 の作業項目へ(§2.2–2.4)
7. §5.2/§16.4: 予算フィールド名統一と PrivacyLabel [0,1]・cloud 境界の明記(§5.2, §5.4)

**P1(Inc1–3 実装中に確定)**

8. 「applied」の定義と terminal event の追い越し規則(§4.1)
9. LastAppliedEventSeq の正本規定(lease token 正・registry は導出 index)(§4.2)
10. ObservationRequired の ExpiresAt と待機中の時計の帰属(§4.3)
11. dedup 正本 = delivery-index、Trace は補助(§4.4)
12. hash canonical 化の一元定義 + AccessSpecHash 新設を Inc1 に(§4.7)
13. quarantine の保管先・reconcile 主体・lease 解放期限(§4.8)
14. ExpectedAfterEventSeq の判定規則(§4.9)
15. resume 時の reservation reconciliation と BudgetSnapshot 単調性フィールド列挙(§4.10)

**P2(Inc7–9 前に)**

16. SessionSlots と seat probe / SeatBroker の接続、席不足時の降格分岐(§4.5)
17. CommitMode の capability gating(headless で Notebook 不可)と FinalActionQueue 同期契約(§4.6)
18. EffectClass 語彙対応表・WritableStagingRoot semantics の NBAccess 側新設範囲(§4.11)
19. approval 正本の一元化規定(§5.3)、既存 ClaudeRuntime executor との住み分け(§2.7)

---

## 9. 最終判断

> **アーキテクチャの選択(episode 粒度の Petri 管理、one-shot AwaitingLLM の非転用、durable command/event protocol、mock-first の増分計画)は実コードの制約と正確に噛み合っており、このまま v0.2 改訂 → Inc0(= conductor Inc0A/0B)→ Inc1 着手でよい。ただし P0 の 7 件 — 特に event 到達性(§3.1)と binding guard(§3.2)は net 構造そのものの修正なので、Inc2 のコードを書く前に必ず仕様へ反映すること。**
