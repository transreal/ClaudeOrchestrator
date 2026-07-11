# RuntimeSession episode / Petri-net 統合仕様 v0.1-r1 レビュー (r2)

**r1 レビューの P0 7 件・P1 8 件・P2 4 件は実質すべて誠実に反映され、§0.1 の反論(既存 Guard 機構の存在)はコード再検証の結果こちらの誤りでスペック側が正しい。構造は実装着手可能な水準に達した。残るのは「Runtime が沈黙したまま死んだとき」と「command が拒否されたとき」の 2 経路 — いずれも仕様自身が言及しながら schema/net が追随していない箇所 — の P0 2 件と、少数の P1 詰めである。**

- 対象: claude_orchestrator_runtime_session_episode_petri_spec_v0_1.md(v0.1-r1、1992 行)
- 日付: 2026-07-10
- 前レビュー: claude_orchestrator_runtime_session_episode_petri_spec_v0_1_review.md(r1)
- レビュー方法: 更新版全文精読 + r1 反映状況の逐条照合 + 争点(Guard 機構)の実コード再検証

---

## 1. 結論

### 1.1 総合判定

| 対象 | 判定 | 理由 |
|---|---|---|
| §9 単一 EpisodeActive + ControlState 再設計 | **Go** | r1 §3.1 の死路を正しく解消。I13/I14、到達性行列、CancelBeforeStart、terminal preemption まで一貫 |
| §9.4 pairing Guard(既存 Guard 機構の利用) | **Go** | §0.1 の反論はコードで裏付けられた(→ §2)。fail-closed validator の要求は現行実装の fail-open 既定に正しく対応 |
| §7/§8/§11 protocol(Attempt scope、cursor、hash、quarantine) | **Go** | r1 P0-3/P1 群を全て反映。ExpectedAfterEventSeq の precondition 化も明確 |
| §12/§23 Runtime 新設範囲の明示 | **Go** | 「変換」→「新設」への改訂、sync/async 両経路の共通 wrapper 要求(§12.4)は r1 の意図以上に踏み込んでいる |
| 予算・privacy・approval の conductor 整合(§7.3/§13.3/§14.5/§16.4) | **Go** | 語彙統一、[0,1] スケール、階層正本、episode→run 一方向集約すべて明文化 |
| **死亡 session への合成 terminal event** | **条件付き Go** | §15.2-8/§18.4 が event「投入」を前提にするが、合成 event が EventSeq/pairing guard 体系を通る方法が未定義(→ §3.1) |
| **command 拒否時の net 経路** | **条件付き Go** | §7.8 が Rejected 時の再評価を規定するが、CommandPending からの脱出 transition と行列行が無い(→ §3.2) |

### 1.2 r1 指摘の反映確認(逐条)

| r1 指摘 | 反映 | 評価 |
|---|---|---|
| P0-1 event×place 到達性 | §9.1–9.5、I13、テスト 24.2-11〜13 | **完全反映**。単一 EpisodeActive + immutable 次世代 lease は r1 推奨案 (2) どおり |
| P0-2 binding guard | §0.1 で現状認識に反論、§9.4/§10.1 で既存 Guard 必須化 + fail-closed validator | **反論が正しい**(→ §2)。対応は適切 |
| P0-3 Attempt scope | §7.7/§7.8(Attempt 必須)、§8.1(cursor= {Attempt,EventSeq})、§11.1(attempts/<attempt>/) | 完全反映 |
| P0-4 checkpoint 二層化 | §7.5 Routine/Boundary、§15.1-7、24.5 実 policy 検査 | 完全反映 |
| P0-5 in-kernel 実行モデル | §11.5(200ms、reentry guard、禁止事項)、§12.3、Inc4 受け入れ | 完全反映 |
| P0-6 「変換」→「新設」 | §2.2 項 8–11、§12.2 太字、§12.4 末尾、Inc4/5/6 | 完全反映 |
| P0-7 予算語彙 + PrivacyLabel | §7.3/§7.4(MaxCostUSD/ActualUSD/ReservedUSD/MaxCalls/PerStep)、§16.4([0,1]、0.5、fail-closed) | 完全反映 |
| P1 8 件(applied 定義/正本/expiry/dedup/hash/quarantine/ExpectedAfterEventSeq/reconciliation) | §11.2/§10.5/§13.1/§10.3/§7.9/§11.4+I14/§7.8/§15.4 | 完全反映 |
| P2 4 件(seat/Notebook/EffectClass/approval 正本/executor 住み分け/adapter/role) | §20.3/§8.2+§17.3/§16.3/§13.3/§10.1/§21.3/§20.2 | 完全反映 |

特に評価できる点: §16.3 の path canonicalize に symlink/reparse traversal を含めたこと(Windows junction 対策として r1 指摘の先を行く)、§21.3 の legacy ArtifactSpec 逆変換の既定禁止、§13.1 の idle clock 所有権の明確化。

---

## 2. §0.1 の反論(Guard 機構)への回答 — スペック側が正しい

r1 §3.2 の「binding 列挙は TokenKind フィルタのみで token 間 join guard 機構が無い」は**誤りだった**。実コードを再検証した結果:

- `iEvaluateGuard[trans, binding]` は実在する(ClaudeOrchestrator_workflow.wl:1223–1231)。
- enabled transition 列挙(`ClaudeEnabledTransitions`)は `iEnumerateBindings` の**各 binding ごと**に `iEvaluateGuard === True` を検査する(:1116)。binding には input arc ごとの token が含まれるため、event×lease の値結合は Guard Function で表現できる。
- `ClaudeFireTransition` も NBAccess check の後、**consume 前**に Guard を再評価し、False なら `Blocked/GuardFailed` で token を消費しない(:1329–1334)。

したがって §9.4「net compiler が pairing 条件を既存 Guard に Function として設定する」は新 engine 機構なしで成立する。仕様の記述どおり。

あわせて実装が確認できた注意点(仕様の validator 要求を裏書きする):

1. `guard === None` → True(fail-open)。
2. **guard が Function 以外の値(壊れた設定・restore 劣化)でも catch-all で True(fail-open)**(:1229)。
3. Function の場合は `TrueQ[Quiet @ guard[binding]]`(:1228)— 非 True・評価エラーは False に落ちるが、`Quiet` が診断 message を握り潰す。

(1)(2) が fail-open である以上、§9.4/§10.1 の「Guard 欠落・非 Function・例外を session event transition では fail-closed とする validator」は**単なる防御ではなく必須**であり、仕様の failure mode 列挙は現行実装と正確に一致している。追加提案が一つだけある: pairing Guard は列挙時と fire 時の**二回**呼ばれるため、副作用なし・軽量(純フィールド比較)であることを net compiler の契約に一文加える。また `Quiet` により guard 内部エラーが無音で False になるので、session net の Guard は自前で例外を捕捉して quarantine 向け診断 record を残す wrapper にすることを推奨する(fail-closed は保ったまま、原因を可視化する)。

---

## 3. 残存する設計上の問題点(P0 — 実装着手前に仕様追記)

### 3.1 合成 terminal event が EventSeq/pairing guard 体系を通れない

仕様は 2 箇所で「Runtime 以外が event を投入する」ことを前提にしている:

- §15.2 step 8: 「unrecoverable なら EnvironmentLost/Failed event を投入」(restore 時)
- §18.4: episode wall-clock/idle timeout の Orchestrator watchdog(生死不明のまま heartbeat が絶えた場合、terminal failure event とする)

しかし §7.7 の event schema と §9.4 の Guard は「Runtime が journal に書いた EventSeq 連番 + EventHash + 同一 policy hash」を前提とする。**死んだ・沈黙した Runtime は event を書けない**ので、合成 event には自然な EventSeq が無く:

- `normalSeqQ`(seq = last+1)を満たす値を bridge が勝手に採番すると、遅延して届く本物の Runtime event と seq が衝突する(例: watchdog が seq N+1 で EnvironmentLost を合成した後、実は生きていた Runtime の seq N+1 ObservationRequired が到着 → dedup key 衝突・どちらが正か判定不能)。
- 採番しないと Guard(normalSeqQ / terminalPreemptQ)を通れない。

さらに §9.4 では terminal event 自身が sameHashQ を要求するため、「Runtime 側の hash が壊れた」ケースでは Runtime 発の Failed event すら quarantine 行きとなり、episode を終端させる手段が watchdog 合成 event **しか無い**。つまりこの経路は例外処理ではなく安全網の本線である。

**推奨修正**: SyntheticControlEvent を一級市民として §7.7/§9.4 に追加する。

1. schema: `"Source" -> "Runtime" | "OrchestratorWatchdog" | "RecoveryScan"` を追加。合成 event は `EventSeq -> None`、`SyntheticSeq -> (lease の LastAppliedEventSeq)`、Type は {Failed, EnvironmentLost, Cancelled} に限定。
2. Guard に第三分岐 `syntheticTerminalQ` を追加: Source が非 Runtime かつ Type が terminal かつ sameEpisodeQ(Attempt 一致)のとき、seq/hash 検査を免除して受理。ただし発行条件を「backend Recover が LostUnrecoverable を返した」「heartbeat が policy 閾値を超えて途絶」「quarantine された terminal event の existence」のいずれかに限定し、発行者・根拠 ref を event に記録する。
3. 競合解消規則: 合成 terminal 適用後に本物の Runtime event が届いた場合は quarantine/late-events に記録して適用しない(terminal 後の event は監査のみ)。逆に、合成 event の発行判定中に本物の event が deposit されたら合成を中止する(bridge 内で directory lock/check-then-write)。
4. §24 に「heartbeat 途絶 → watchdog 合成 EnvironmentLost → EpisodeFailed → lease 返却」「合成後に遅延 Runtime event 到着 → 適用されず監査記録」のテストを追加。

### 3.2 command 拒否時の net 経路が無い(CommandPending が死路になり得る)

§7.8 は Rejected(StaleContext)/Rejected(StaleAttempt) と、その後の Orchestrator の再評価(「最新 event を取り込み、旧 command を Superseded と記録して新しい CommandId で意図を再評価」)を規定した。しかし net 側にその受け皿が無い:

1. §9.5 の行列で CommandPending から適用できる event は CommandAccepted のみ。command が拒否される典型原因は「Runtime が並行して新 event を emit した」ことだが、**その新 event(例: BudgetInterrupt)は行列上 Running/CheckpointReview からしか適用できず**、CommandPending の lease に対しては Guard で弾かれ quarantine 行きになる。結果: command は拒否済み・新 event は quarantine・lease は CommandPending のまま、という三すくみで episode が停止する。
2. Rejected は SendCommand の同期戻り値であり event ではないため、poll tick が記録した後に lease を CommandPending から動かす transition が §9.3 に存在しない(AcknowledgeSessionCommand は Accepted 専用)。

**推奨修正**:

1. §9.3 に `HandleCommandRejected`(PureFunction)を追加: poll tick が command-index に Rejected を記録した後、CommandPending lease を consume し、旧 command を Superseded と記録して lease を直前の要求元 state(または Running)へ戻す。トリガーは合成 control token(Type -> "CommandRejected"、Source -> "Bridge")とするのが §11.2 の搬送路と揃う — §3.1 の SyntheticControlEvent を導入するなら同じ仕組みに載る。
2. §9.5 の行列を改訂: CommandPending からも Runtime 発 event(ObservationRequired 以外の boundary event と terminal)を適用可能にするか、少なくとも「CommandRejected 適用後に再評価する」旨を規定する。前者なら「event 適用が pending command を暗黙 Supersede する」規則を明記する(ExpectedAfterEventSeq の precondition と整合する: event が進んだ時点でその command はどのみち Runtime に拒否される)。
3. §24.2 に「command 発行と Runtime event emit の競合 → Rejected → Superseded 記録 → 新 CommandId で再発行 → 完走」を追加。

---

## 4. P1(Inc1–3 実装中に確定)

### 4.1 Stop command の livelock 可能性

§7.8 は Cancel だけを stale context 免除とした。graceful Stop は ExpectedAfterEventSeq 一致を要求されるため、boundary event を頻発する episode では拒否→再発行が反復し得る(毎回 event が 1 個進んでいる)。**推奨**: Stop も「Attempt 一致必須・seq 免除」に含めるか、N 回拒否で Cancel へ昇格する escalation 規則を §7.8 に一文。

### 4.2 SupersedesThroughSeq の検証が自明化している

§9.4 の `terminalPreemptQ` は `SupersedesThroughSeq === EventSeq - 1` を要求するが、Runtime が terminal event に常に `EventSeq - 1` を設定すれば恒真であり、検査として機能しない。実質的な意味は「飛ばされた区間の監査記録」(§11.2)にある。**推奨**: Guard 側の条件は維持してよいが、適用時に「LastAppliedEventSeq+1 .. SupersedesThroughSeq の各 seq が inbox または quarantine に存在するか、Missing として記録されるか」を bridge が検証・記録する、と §11.2 に明記(silent gap の検出)。

### 4.3 Guard = pairing ∧ ControlState 行列 の合成を明文化

§9.4 の pairing 条件には ControlState 検査が含まれず、§9.5 の行列は transition ごとの状態ゲートを暗黙に前提する。net compiler の契約として「session event transition の Guard = sameEpisodeQ ∧ seq 条件 ∧ sameHashQ ∧ stateAllowedQ(§9.5 行列)」と一箇所に書く。validator は 4 成分すべての存在を検査する。

### 4.4 StartEpisode の同期失敗経路

`StartEpisode -> Failed`(§8.1)は event ではなく executor の同期戻り値。EpisodeAllocated の lease がどこへ行くか(HandleFailure 経由で retry/terminal、SessionSlots 返却)が §9.3 に明示されていない。RuntimeSession executor branch の失敗時契約として一文追加。

### 4.5 「commit 成功 + session 死亡」の複合結果

行列では Failed が全 ControlState から terminal へ落ちるが、single committer が commit receipt を永続化した**後**、Runtime が AcceptArtifact/Completed 前に死んだ場合、episode は Failed でも **target は既に変更済み**である。§17.3 の再読込検証はこの半端を検出できる位置にあるので、「terminal 処理時に CommitReceiptRef が存在すれば Failure record に CommittedButSessionLost を記録し、Conductor へ artifact は有効として引き渡す(rollback しない)」という規定を §17.3 または §18.1 に追加。Conductor の replan がこれを見ないと同じ artifact を二重生成する。

### 4.6 NeedsRestartApproval と approval 系の期限の対称性

- §15.2 step 7 の NeedsRestartApproval は無期限に lease を保持し得る(I14 と衝突)。ExpiresAt/OnExpiry を他の待機と同様に付与する。
- §13.2 ApprovalRequired には ExpiresAt があるが OnExpiry が無い(§13.1 は両方ある)。期限切れの既定(Deny → repair/fail)を明記。

### 4.7 IdleSeconds の意味論

§7.4 の単調非減少リストから IdleSeconds は除外されているが、それが「現在の連続 idle 長(リセットされる)」なのか「累積 idle」なのか未定義。MaxIdleSeconds(§7.3)との照合は前者を要するはずなので、「IdleSeconds = 現在の連続 idle 秒。非単調」と一文で確定する。

### 4.8 CommitPermit の消費規則

§17.3「CommitPermit token を一個だけ作る」に対し、commit 失敗時に permit が残るか消えるかが未規定。single-use(commit 試行が成功失敗を問わず consume、再 validation が新 permit を発行)を明記しないと、失敗した permit の再利用で validation を飛ばした再 commit が可能になる。

---

## 5. 軽微な指摘

1. §9.2 の表に CleanupPending place があるが §9.1 mermaid の CL は transition(CleanupAndRelease)として描かれている。terminal token → CleanupPending(place) → CleanupAndRelease(transition) → 返却、と図表を揃えると誤読がない。
2. §9.5 の行列は event 行が中心で、command 発行行(ProvideObservation は AwaitingObservation からのみ、GrantBudget は BudgetReview からのみ、等)が暗黙。1 行ずつ足すと validator の仕様がそのまま書ける。
3. §11.2 step 7 の「marking または workflow trace に TokenId が存在することを確認」は、§10.3 の「trace 全走査を通常経路にしない」と読み合わせると「submit 直後の確認は marking のみで足りる」はず。step 7 の文言を「marking(または直近 trace entry)」に絞ると誤実装(毎 event trace 走査)を防げる。
4. §0.1 の反論文中「現行 ClaudeEnabledTransitions は iEnumerateBindings 後に iEvaluateGuard を評価」— 正確には binding ごとに評価(:1116)。実装指針としてはそのままで問題ない。
5. Guard は列挙時と fire 時の二回評価されるため、pairing Function は副作用なし・O(フィールド数) であることを §10.1 の契約に一文(§2 で詳述)。

---

## 6. テスト仕様(§24)への追加提案

r1 提案の 9 件はすべて反映済み(24.2-11〜15、24.3 末尾、24.4、24.5 実 policy、24.6)。P0/P1 対応として以下を追加:

1. heartbeat 途絶 → watchdog 合成 EnvironmentLost → EpisodeFailed → lease 返却(§3.1)
2. 合成 terminal 適用後に遅延 Runtime event 到着 → 適用されず監査記録のみ(§3.1)
3. 合成 event 発行判定と本物 event deposit の競合 → 合成中止(§3.1)
4. command 発行と Runtime event の競合 → Rejected(StaleContext) → Superseded → 新 CommandId 再発行 → 完走(§3.2)
5. CommandPending 中の terminal event → 死路にならず terminal へ(§3.2)
6. Stop の反復拒否 → escalation 規則どおり Cancel 昇格または受理(§4.1)
7. commit receipt 永続化後に Runtime 死亡 → CommittedButSessionLost、artifact は有効、replan が二重生成しない(§4.5)
8. commit 失敗後に旧 CommitPermit で再 commit 不能(§4.8)
9. Guard に非 Function を設定した session net が validator で fail-closed 拒否される(§2 の engine 既定 fail-open の回帰防止)

---

## 7. 変更要求まとめ

**P0(実装着手前に v0.1-r2 へ追記)**

1. SyntheticControlEvent(Source/SyntheticSeq/発行条件/競合解消)を §7.7/§9.4/§11.2 に追加し、watchdog・recovery 投入 event を Guard 体系に載せる(§3.1)
2. HandleCommandRejected transition と CommandPending からの event 適用規則(暗黙 Supersede)を §9.3/§9.5 に追加(§3.2)

**P1(Inc1–3 実装中)**

3. Stop の stale-context 扱い(免除 or escalation)(§4.1)
4. SupersedesThroughSeq 区間の inbox/quarantine 存在検証(§4.2)
5. Guard 4 成分(pairing ∧ state 行列)の合成契約と validator 検査対象(§4.3)
6. StartEpisode 同期失敗の lease/slot 経路(§4.4)
7. CommittedButSessionLost の複合 terminal 規定(§4.5)
8. NeedsRestartApproval / ApprovalRequired の期限対称化(§4.6)
9. IdleSeconds 非単調の明記(§4.7)、CommitPermit single-use(§4.8)

**P2(該当 Inc 前)**

10. §5 の軽微 5 件(図表整合、command 行の行列化、step 7 文言、Guard 二回評価の契約)

---

## 8. 最終判断

> **v0.1-r1 は r1 の構造的欠陥をすべて解消し、争点だった Guard 機構も実コードで仕様側の正しさが確認できた。P0 は「Runtime が沈黙して死ぬ」「command が拒否される」という異常系 2 経路の schema/net 追記のみで、いずれも既存の SyntheticControlEvent 化という同一の仕組みで解ける。この 2 件を v0.1-r2 に反映すれば、Inc0(= conductor Inc0A/0B)→ Inc1 の実装着手を推奨する。**
