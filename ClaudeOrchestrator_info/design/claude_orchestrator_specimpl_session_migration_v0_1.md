# spec-impl の RuntimeSession episode 移行 v0.1

- 日付: 2026-07-12
- ステータス: v0.1 実装済み。headless suite 22/22 green
  (test codes/claudecode_specimpl_session_test.wl、席不要) +
  実 launcher T5 16/16 green
  (test codes/claudecode_specimpl_session_t5_real.wl、実子プロセス。
   R2 = 実 worker + MockMode で SourceVault/RunSpecImpl/動的ゲート込み
   Approved 完走)。
- **NB 実機済み** (2026-07-12, 20260622-株価推移ワークフロー3.nb):
  パレット Impl → session 経路で実走 (spool 実物確認: 実子 40 分走行 →
  ArtifactProposed → commit → Disposed → write-back)。基盤は完動。
  ただし実装ループ自体が旧 MaxWait 2400s を超過 (実測 1 round ≈ 13-15 分
  × 3 rounds) し、RunSpecImpl が FinalStatus "Unknown" の抜け殻 summary を
  返して「Done/Unknown」表示になった。対処 (legacy とパリティ):
  (1) FinalStatus "Unknown" は Done でなく Error として報告 (fail-closed、
      worker/legacy driver 両方)。
  (2) cfg に MaxWaitSeconds を明示供給 ($iSpecImplMaxWaitSeconds=5400)、
      FE backstop は job 起動時に BackstopSeconds=Max[backstop, MaxWait+300]
      で確定 (リロード残留の旧 2700s による誤 kill 防止)。
- 学び: SourceVault_workflows/<slug>/ に補助 .wl を置いてはならない
  (iSVWFMainFile が Sort 順最初の *.wl を workflow 本体として解決するため
   SourceVaultLoadWorkflow が壊れる)。補助ファイルは .wls にする。
- 親仕様: claude_orchestrator_runtime_session_episode_petri_spec_v0_1.md
- 対象:
  - ClaudeRuntime_sessionrunner.wl (worker seam 追加 = IncE 相当)
  - SourceVault_workflows/spec-impl/session_impl_worker.wls (新規。
    .wls なのは workflow レジストリの iSVWFMainFile が slug フォルダ内の
    Sort 順最初の *.wl を workflow 本体と解決するため — .wl で置くと
    SourceVaultLoadWorkflow["spec-impl"] が壊れる)
  - claudecode.wl (spec-impl FE adapter)
  - test codes/claudecode_specimpl_session_test.wl (新規)

---

## 0. 目的

パレット「Impl」(spec 実装フロー) の実行基盤を、手組みの
StartProcess + progress polling + wall-clock backstop から
RuntimeSession episode 基盤 (episode net + external process backend +
durable spool) へ載せ替える pilot。spec-review / docext の後続移行の型を作る。

得るもの:
- PID identity / 誤kill防止 / orphan reattach (tick-count 誤タイムアウト病理の構造的解消)
- artifact candidate 検証 + single commit (result の正本化)
- cancel / synthetic terminal の体系化
- 3系統に重複した start/poll/timeout/write-back の一本化への第一歩

守るもの (互換):
- パレット UI・NB write-back セル・progress 表示は無変更
- 既存 driver (palette_impl_driver.wls) は無傷で残し fallback に使う
- RunSpecImpl (SVWorkflow_SpecImpl.wl) は無変更

## 1. 層マッピング

| legacy | episode 基盤 |
|---|---|
| StartProcess wolframscript driver | StartEpisode → launcher seam → 実 wolframscript 子 (ClaudeRunSessionFromSpool worker mode) |
| progress.wl polling (status area) | 継続 (routine telemetry。control event にしない = 仕様 §7.5) |
| result.wl 出現 = 完了合図 | ArtifactProposed → ValidateArtifact → ArtifactStore commit → FinalizeCommittedArtifact terminal |
| ProcGoneSince + 6s grace | PID probe + synthetic Failed (evidence 付き §11.2.1) |
| $iSpecImplMaxSeconds kill | Cancel command + pid-verified Dispose + synthetic Cancelled |
| $iSpecImplJobs 手動管理 | episode net が正本。FE job entry は表示/変換用の薄い adapter |

## 2. sessionrunner worker seam (IncE, 純加法)

Inc9 の子プロセス本体は simulator 台本ループ固定。任意の長時間作業を
episode protocol で走らせる seam を追加する。

1. `ClaudeRuntimeExternalProcessBackendSpec` に option 追加:
   - `"WorkerSpec" -> None | <|"InitFiles" -> {abs path...}, "Function" -> "Context`symbol"|>`
     (データのみ。Function 本体は渡さない。manifest に `WorkerSpec` として保存 = ref-only I4 準拠)
   - `"Launcher" -> Automatic | fn`
     per-backend launcher。Automatic = 従来どおり `$ClaudeSessionRunnerLauncher`。
     グローバル seam を flow ごとに mutate しないための口。
2. `ClaudeRunSessionFromSpool`: manifest に WorkerSpec があれば worker mode。
   - start-spec.wxf から full startSpec を読む (fallback = manifest 由来 minimal)。
   - InitFiles を Get (失敗 = status Failed + `Failed` event、fail-closed)。
   - `Function` symbol を解決して `worker[ctx]` を呼ぶ。ctx =
     `<|"SpoolDir","Manifest","StartSpec","BackendInstanceId",
        "Emit"(type,payloadRefs), "PollCommands", "AckCommand",
        "CancelRequestedQ", "WriteStatus", "CanonicalHash", "NewId"|>`
   - worker 例外 → `Failed` event (Reason=WorkerException)。
   - backstop: worker 終了時、inbox 最終 event が
     {ArtifactProposed, Completed, Failed, Cancelled, EnvironmentLost}
     のいずれでもなければ `Failed` (Reason=WorkerNoTerminalEvent) を emit。
   - worker mode では MaxRunSeconds の sim ループは使わない
     (作業の時間管理は worker 自身 + FE backstop + budget)。
3. `iRunnerBackendDispose`: 「NotAlive + spool status が terminal
   (Completed/Failed/Disposed)」は正常終了後の後始末として `Disposed`
   (Killed->False) を返す。Quarantined は identity 不明のまま生存疑いが
   残る場合に限定 (§18.3 の意図の明確化)。

子が ArtifactProposed を最終 event として exit するのは正当
(terminal 化は orchestrator 側 FinalizeCommittedArtifact が行う)。
repair 経路 (Repairable な検証失敗 → Running へ差し戻し) は one-shot worker
では応答者がいないため非対応 = FE backstop / synthetic terminal が回収する。
worker は emit 前に SelfChecks を自己検証して repair 到達を避ける。

## 3. spec-impl worker (新規 session_impl_worker.wls)

Context: `SourceVaultWorkflow`SpecImplSession``。
公開: `SpecImplEpisodeWorker[ctx]`。

- cfg = Get[manifest GoalRef] (legacy config.wl と同一フォーマット。追加キー不要)
- cancel 先行チェック → `Cancelled` emit して終了
- SourceVault.wl ロード → SourceVaultLoadWorkflow["spec-impl"] → RunSpecImpl
  (mock seam・progress file・引数は palette_impl_driver.wls と同一)
- result 連想 (legacy と同一キー) を組み、
  (a) cfg ResultFile に Put (legacy 互換・デバッグ/fallback 用)
  (b) staging (= runDir) に WXF 化し ArtifactCandidate を構築して
      `ArtifactProposed` emit
- candidate: ArtifactType="SpecImplResult", ArtifactRef=staging wxf path,
  ContentHash=ctx CanonicalHash, SelfChecks=<|"ResultWellFormed"->True|>
  (Status/Name/TargetDir キー存在を自己検証), Provenance=
  <|InputRefs->{SpecRef}, ToolJournalRef->None, Model->implModel,
    RuntimeTraceRef->None|>, PrivacyLabel=1.0
- RunSpecImpl 失敗 → result error 連想を Put + `Failed` emit

## 4. FE adapter (claudecode.wl)

- `$ClaudeSpecImplUseSession` = Automatic | True | False。
  Automatic/True では Impl 実行時に session モジュール群
  (orchestrator workflow/session + runtime 4本) を **on-demand 自動ロード**
  (`iSpecImplEnsureSessionModules`)。ロード済み判定は Names でなく
  DownValues/OwnValues (claudecode.wl 自身の symbol 参照で Names が
  false-positive になるため)。ロード失敗は legacy fallback。
- `CreateImplementationWorkflow`: cfg/pending cell 構築までは共通。
  session 経路の起動が Failure なら legacy StartProcess へ自動 fallback
  (docext の $ClaudeDocUpdateExternal と同じ型)。
- 起動 (`iSpecImplSessionLaunch`):
  - backend 登録 `"SpecImplExternalProcess"` =
    ClaudeRuntimeExternalProcessBackendSpec[WorkerSpec=session_impl_worker,
    Launcher=$iSpecImplSessionLauncher (Automatic=real launcher
    MaxRunSeconds=$iSpecImplMaxSeconds、テストは in-kernel launcher 注入)]
  - startSpec = ClaudeSessionStartSpecTemplate を base に
    Task/Worker/Environment/ArtifactContract/BudgetGrant を override
    (GrantHash 再計算)。GoalRef=cfgFile、staging=runDir、
    CommitMode="ArtifactStore"、CommitTargetRef=runDir/artifact-store、
    RequiredChecks={"ResultWellFormed"}、IsolationLevel="ExternalProcess"
  - ClaudeCreateRuntimeSessionEpisodeNet → ClaudeStartRuntimeSessionEpisode
  - job entry に Kind="Session"/Wid/EpisodeId/SessionId/SpoolDir/Proc を追加
- tick (`iSpecImplTick` の session 分岐):
  - progress → status area (legacy と共通コード)
  - ClaudeRuntimeSessionPumpOnce + ClaudeStepWorkflow drain (≤24/tick)
  - terminal 検出: ControlState ∈ {Completed,Committed,Closed} →
    harvest (receipt TargetRef の WXF → 無ければ result.wl) →
    既存 iSpecImplWriteBack (無変更) へ
  - ControlState ∈ {Failed,StartFailed} → error 変換 → write-back
  - dead-proc: Proc 死亡 + grace 6s + 非 terminal →
    synthetic Failed 注入 (evidence=runDir) + iSpecImplDeadProcResult write-back
  - timeout: $iSpecImplMaxSeconds 超過 → kill + Cancel + synthetic Cancelled +
    Timeout write-back (従来と同じ表示)
- kill/ClaudeAbort: session job は Proc が None の場合に耐性化 +
  best-effort Cancel/synthetic

## 5. 非目標 (v0.1)

- spec-review (仕様生成 consensus) / docext の移行 — 本 pilot の型を流用する後続
- budget interrupt / GrantBudget の UI (episode 側機構はあるが FE 未配線)
- repair 経路への worker 応答 (one-shot worker のため)
- session reuse (ReusePolicy=Never 固定)
- 生成パッケージ file 群自体の episode commit 化
  (targetDir=workflow stage "testing" への配置は既存機構のまま。
   episode artifact は result 連想の正本化に限定)

## 6. テスト

test codes/claudecode_specimpl_session_test.wl (wolframscript, 席不要):
- T1 worker mode 単体: null launcher で StartEpisode → 同一 kernel 内で
  ClaudeRunSessionFromSpool を子の代役として実行 (tiny test worker) →
  pump → ArtifactProposed → commit → terminal
- T2 FE 経路 e2e: $iSpecImplSessionLauncher に in-kernel 同期 launcher を注入、
  session launch → tick 相当の pump/drain → harvest が legacy result 形を返す
- T3 fallback: launcher 失敗 → CreateImplementationWorkflow が legacy へ
  (legacy start を Block で stub)
- T4 dead-proc/timeout 分岐のユニット
- T5 (席あり・実機): 実 launcher + tiny worker で Windows spool/PID 検証。
  さらに MockMode cfg の full e2e (LLM 非依存)。席枯渇時は NB スニペットで
  ユーザー検証に引き渡す
