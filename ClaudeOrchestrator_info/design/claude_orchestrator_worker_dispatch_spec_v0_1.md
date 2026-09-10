# ClaudeOrchestrator worker dispatch 仕様 v0.1

**ワーカーは「モデル名」ではなく「必要な能力」を要求する。束縛は試行ごとにやり直す。**

- 日付: 2026-08-30
- ステータス: v0.1 ドラフト（未レビュー）
- 対象:
  - claudecode.wl（`$ClaudeLLMTierTable` / `$ClaudeTaskClassTable` / `ClaudeResolveLLMTier` / `ClaudeBackendAvailableQ` / `ClaudeRateLimitStatus`）
  - ClaudeOrchestrator_workflow.wl（Petri エンジン、ループ規約）
  - 新規 ClaudeOrchestrator_dispatch.wl（context `ClaudeOrchestrator`Dispatch``）
  - NBAccess.wl（`NBModelCanHandleAccessLevel` — 参照のみ、変更なし）
- 関連仕様:
  - `ドキュメント/claude_orchestrator_conductor_policy_spec_v0_2.md`（本仕様の上位。§7 worker binding / §8 会計）
  - `claude_orchestrator_runtime_session_episode_petri_spec_v0_1.md`（episode 境界。ループの所有権）
  - `Claude Directives/rules/107-local-llm-network-trust.md`（ローカル LLM の信頼境界）

---

## 0. 目的とスコープ

### 0.1 なぜ今これが要るか

クラウド API 経由のモデル（GPT / GLM / Kimi）には**クライアント側ツールループを与えない**方針が確定した（2026-08-30 実測・[[cloud-provider-toolloop-and-gates]]）。理由はツール結果が外部へ出るためで、これは維持する。

その帰結として、**反復を要する処理はモデル内部のループではなく Petri ネットのワークフローとして記述する**ことになる。ワークフローが反復を所有するなら、各反復ステップで「どのモデルに実行させるか」を決める機構の質が、そのままワークフロー全体の性能と信頼性になる。

### 0.2 スコープ

1. ワーカーが要求する**能力**（heavy / medium / light ほか）から実行 backend を決める束縛層。
2. **重要度（Criticality）** を PL と独立した軸として導入し、「失敗できないタスクには消費の大きいモデルを割り当てる」判断を宣言的に表す。
3. 刻々変わる**可用性**（rate-limit 窓、ローカルモデルのロード状態、サーバ死活）の観測と、それに追随する再束縛。
4. Petri ネット上の**ループ規約**（試行 → 検証 → 昇格 → 再試行）の標準フラグメント。

前提とする provider の組み合わせは **Claude Code CLI + Codex CLI（いずれも定額・API 課金なし）+ LM Studio / llama.cpp（ローカル）** に限る。

### 0.3 非スコープ

- 従量課金 API の金額予算・PriceCatalog・予約 ledger → Conductor v0.2 §8 が所有する。本仕様は「現金が制約にならない領域」を扱う。
- 学習型 policy・tuner → v0.2 §10。
- 評価フレームワーク（judge / rubric）→ v0.2 §9。
- agent 内部の turn / tool ループ → episode 仕様が所有する。本仕様は **episode 1 個をどのワーカーに割り当てるか**だけを決める。

---

## 1. 現状（実装済みのもの）

コード上の根拠を伴う事実。設計はここからの差分として書く。

| 機構 | 実体 | 現状 |
|---|---|---|
| ティア表 | `$ClaudeLLMTierTable` | TaskClass → backend 候補列（静的・優先順） |
| クラス属性 | `$ClaudeTaskClassTable` | `AllowEscalation`(bool) / `RequiresValidator` / `MaxCostClass`(local-only<cheap<premium) / `DefaultTimeout` |
| 束縛 | `ClaudeResolveLLMTier[class]` | 候補列を先頭から走査し、spend ブロックと preflight を通った**最初の 1 個**を選ぶ |
| 可用性 | `ClaudeBackendAvailableQ[spec]` | 60 秒キャッシュ。`iClaudeBackendAvailCompute` が lmstudio / freetoken / llamacpp / claudecode に定義済み |
| rate limit | `ClaudeRateLimitStatus[provider\|All]` | `Detected` / `Source` / `RateLimitType` / `ResetsAt` |
| PL ゲート | `NBModelCanHandleAccessLevel[spec, level]` | provider 上限と接続先距離で判定（rule 107） |
| 信頼ドメイン | `SourceVaultResolvePromptDeliveryProfile` | TrustDomain / TrustCeiling / PromptStrategy |

### 1.1 確認済みの欠落

1. **`ClaudeResolveLLMTier` は PL を見ない。** 候補が扱えるアクセスレベルを検査しないまま選ぶ。privacy 側の機構（`NBModelCanHandleAccessLevel` / delivery profile）と未統合。Conductor v0.1 が「この 2 機構は未統合だったのが空白」と指摘した箇所そのもの。
2. **重要度の軸がない。** `AllowEscalation` は真偽値で、「どこまで上げてよいか」「何回試してよいか」を表せない。
3. **chatgptcodex の可用性判定が無い。** `iClaudeBackendAvailCompute[_, _]` の総称定義に落ち、常に `Available -> True, "Unchecked"` になる。Codex を前提に置く以上これは埋める必要がある。
4. **可用性が二値で、余力（headroom）を持たない。** claudecode は `RateLimited` か `OK` かのみ。「あと少しで枯れる」を表現できないので、重要タスクのために窓を温存する判断ができない。
5. **候補選択に順位付けがない。** 「利用可能な最初の 1 個」なので、目的（速度優先／品質優先）を反映できない。
6. **束縛が試行をまたいで固定される。** ループの 2 回目に状況が変わっていても、同じ backend が使われる前提になっている。

---

## 2. 設計判断

**D1. ワーカーは能力を要求し、モデルを指名しない。**
Petri ネットの transition は `CapabilityRequest` を宣言する。モデル名・provider 名をネット定義に書かない。書いてよいのは「明示的にこのモデルで再現したい」評価用ネットだけで、その場合も `Pinned` として理由を伴う。

**D2. Criticality は PL とも品質目的とも独立の第三軸。**
PL は「どこへ出してよいか」（許可）。Objective は「速さと品質のどちらを選ぶか」（選好）。Criticality は「失敗の許容度」であり、**昇格予算（試行回数・許容ティア上限・待機許容時間）** に写る。PL を緩める力は一切持たない。

**D3. 可用性は真偽値ではなく余力付きの観測。**
`AvailabilityView` は provider ごとに `State`（Ready / Degraded / Exhausted / Down / Unknown）と、可能なら `Headroom`（0.0–1.0）と `ResetsAt` を持つ。二値では「温存」という判断ができない。

**D4. 束縛は試行ごとにやり直す。**
ループの各反復で `BindWorker` を再実行する。前回の選択は入力の一つ（`AvoidBackends`）にすぎない。可用性が刻々変わる前提では、これが唯一の正しい既定。

**D5. 現金は制約にしない。**
本スコープの希少資源は 3 つ：**定額プランの rate-limit 窓**（claudecode / codex、時間で回復）、**ローカル GPU の直列性**（同時 1 本、VRAM で決まる）、**壁時計**。金額 ledger は持たない。ただし v0.2 §8.2 の多通貨 ledger に載る形で記録は残す（`SubscriptionUnits` / `LocalGPUSeconds`）。

**D6. fail-closed。**
候補が尽きたら黙って降格しない。`Failure["NoWorkerAvailable", <|"Rejected" -> {...}|>]` を返し、ネット側が待機・縮退・中止のどれを選ぶかを決める。特に `LocalOnly` と `securityjudge` 系は cloud へ落ちてはならない。

---

## 3. 用語

| 語 | 意味 |
|---|---|
| WorkerClass | 実行能力の粗い階層。`heavy` / `medium` / `light` |
| ExecutionSite | `Local`（LM Studio / llama.cpp）/ `Subscription`（Claude Code / Codex CLI） |
| CapabilityRequest | transition が宣言する必要能力 |
| Criticality | 失敗許容度。`routine` / `important` / `critical` |
| AvailabilityView | ある時点の provider 群の状態スナップショット |
| BindingDecision | 束縛の結果。選択・理由・却下理由を含む |
| Attempt | ループ 1 反復。1 Attempt = 1 束縛 = 1 episode |

---

## 4. データモデル

### 4.1 CapabilityRequest

```wl
<|
  "WorkerClass"   -> "heavy" | "medium" | "light",   (* 粗い階層。必須 *)
  "MinContext"    -> _Integer | Automatic,           (* 必要文脈長 (トークン) *)
  "NeedsTools"    -> True | False,                   (* SourceVault ツールループが要るか *)
  "NeedsVision"   -> True | False,
  "Determinism"   -> "Any" | "Preferred",            (* 再現性が要るか *)
  "MaxLatency"    -> _Quantity | Automatic,          (* 壁時計の上限 *)
  "PrivacyLevel"  -> _Real,                          (* 扱うデータの PL。許可の根拠 *)
  "LocalOnly"     -> True | False,
  "Criticality"   -> "routine" | "important" | "critical",
  "Objective"     -> "Balanced" | "MaxQuality" | "MinLatency",
  "Pinned"        -> None | {provider, model},       (* 評価用。理由必須 *)
  "PinReason"     -> _String
|>
```

`NeedsTools -> True` は **ローカル provider に限定される**（クラウドにツールを渡さない方針）。この制約は Criticality でも緩まない。

### 4.2 Criticality 方策表

```wl
$ClaudeCriticalityTable = <|
  "routine"   -> <|"MaxAttempts" -> 1, "MaxTierUp" -> 0, "MaxWaitForTier" -> 0,
                   "RequireVerify" -> False, "AllowDegrade" -> True|>,
  "important" -> <|"MaxAttempts" -> 3, "MaxTierUp" -> 1, "MaxWaitForTier" -> 180,
                   "RequireVerify" -> True,  "AllowDegrade" -> True|>,
  "critical"  -> <|"MaxAttempts" -> 5, "MaxTierUp" -> 2, "MaxWaitForTier" -> 900,
                   "RequireVerify" -> True,  "AllowDegrade" -> False|>
|>
```

- `MaxTierUp`: 失敗時に上げてよいティア段数。`critical` は light → heavy まで到達できる。
- `MaxWaitForTier`（秒）: 望むティアが rate-limit で塞がっているとき、**降格せずに待つ**上限。`critical` は 15 分待ってでも heavy を使う。これが「トークン消費が大きなモデルを割り当ててよい」という判断の実体。
- `AllowDegrade -> False`: `critical` は下位ティアへ落ちない。待つか失敗するかの二択。
- **この表は PL 判定に一切影響しない。** `critical` でも PL 上限を超える backend は選ばれない。

### 4.3 AvailabilityView

```wl
<|
  "At" -> _AbsoluteTime,
  "Providers" -> <|
    "claudecode" -> <|"State" -> "Ready"|"Degraded"|"Exhausted"|"Down"|"Unknown",
                      "Headroom" -> _Real | Missing[], "ResetsAt" -> _ | None,
                      "Site" -> "Subscription"|>,
    "chatgptcodex" -> <|...|>,
    "llamacpp"   -> <|"State" -> _, "LoadedModels" -> {_String..}, "Site" -> "Local"|>,
    "lmstudio"   -> <|...|>
  |>
|>
```

- TTL は既存 `$iClaudeBackendAvailTTL`（60 秒）を流用。`"Refresh" -> True` で強制更新。
- `Exhausted` と `Down` を区別する。前者は待てば回復し、後者は待っても回復しない。**待機判断の前提**なのでこの区別は必須。
- `Headroom` が取れない provider は `Missing[]`。**推定値を入れない**（0 として扱う誤りを避ける）。

### 4.4 BindingDecision

```wl
<|
  "Selected"   -> {provider, model} | None,
  "WorkerClass"-> _String,
  "Site"       -> "Local" | "Subscription",
  "Rationale"  -> _String,
  "Rejected"   -> {<|"Backend" -> _, "Reason" -> _String|>..},
  "TierUpUsed" -> _Integer,
  "WaitedFor"  -> _Real,
  "BoundAt"    -> _AbsoluteTime,
  "AvailabilitySnapshotId" -> _String
|>
```

`Rejected` は必ず埋める。**「なぜその選択になったか」を後から再構成できることが、この層の主要な観測要件**である。

---

## 5. 束縛アルゴリズム

Conductor v0.2 §7.1 の filter/rank 形を継承する。

```
candidates = 列挙(WorkerClass, ExecutionSite)          (* ティア表 + PolicyStore 上書き *)
  |> filter: PL          — NBModelCanHandleAccessLevel[spec, PrivacyLevel]
  |> filter: LocalOnly   — LocalOnly なら Site == "Local" のみ
  |> filter: NeedsTools  — True なら iLocalOAIProviderQ を満たす provider のみ
  |> filter: 可用性      — AvailabilityView.State ∈ {Ready, Degraded}
  |> filter: 能力        — MinContext / NeedsVision を満たす
  |> rank:   Objective   — MaxQuality: ティア降順 / MinLatency: 実測 p50 昇順 / Balanced: Site=Local 優先
  |> first
```

空集合になった場合の分岐（**この順序が本仕様の核**）:

1. 望むティアが `Exhausted` で、`MaxWaitForTier > 0` かつ `ResetsAt` が待機上限内 → **待機**（Petri の `WaitingForCapacity` place へ）。
2. 待てない、かつ `AllowDegrade` → 1 段下のティアで再列挙。
3. 降格不可（`critical` / `LocalOnly` / `NeedsTools`）→ `Failure["NoWorkerAvailable"]`。

**黙って降格しない。** 降格したら `BindingDecision.Rationale` に必ず記録し、`Degraded` イベントを emit する。

---

## 6. Petri ネットのループ規約

ワークフローが反復を所有する以上、反復の形を標準化する。以下を net compiler が提供する再利用フラグメントとする。

### 6.1 bounded retry with escalation

```
   [Ready]
      |
      v
 (Bind)  -- 束縛失敗 --> [WaitingForCapacity] --(Timer)--> (Bind)
      |                          |
      | 束縛成功                  +-- 待機上限超過 --> [Failed]
      v
 [Attempting] --(RunEpisode)--> [Attempted]
      |
      v
 (Verify) --成功--> [Accepted]
      |
      +--失敗--> (Escalate) --試行残あり--> [Ready]   (WorkerClass を 1 段上げ、AvoidBackends に追加)
                     |
                     +--試行尽き--> [Failed]
```

不変条件:

- **`Attempting` の token 数 ≤ 1**（1 論理ステップにつき episode 1 個）。fan-out は別フラグメント。
- `Escalate` は `MaxAttempts` と `MaxTierUp` の**両方**を減らす。どちらかが尽きれば `Failed`。
- `WaitingForCapacity` からの復帰は `ResetsAt` 由来のタイマーで、ポーリングしない。
- 各 `Bind` は新しい `AvailabilityView` を取る。**前回の束縛を再利用しない**（D4）。
- `Verify` の要否は Criticality の `RequireVerify` が決める。`routine` は検証なしで受理してよい。

### 6.2 検証者の束縛

`Verify` 自身もワーカーを要る。規約：**検証は生成と異なる backend に割り当てる**（同一モデルの自己検証を避ける）。実現できない場合（ローカル 1 モデルのみ等）は `SelfVerify` として記録し、検証の重みを下げる。

---

## 7. 会計（現金なし領域）

v0.2 §8.2 の多通貨 ledger の部分実装として、本スコープでは 2 通貨のみ扱う。

- `SubscriptionUnits`: claudecode / codex のトークン数を代理単位として加算。**hard cap は設けない**（rate limit が実質の cap）。用途は事後の配分分析と、Criticality 方策表のチューニング根拠。
- `LocalGPUSeconds`: ローカル推論の壁時計。ローカルは直列なので、これが**実質的な待ち行列長**になる。

`MarginalCashUSD` は本スコープでは常に 0。ただしフィールドは持つ（v0.2 と schema を分岐させない）。

---

## 8. 公開 API 案

```wl
ClaudeDispatchAvailability[opts]          (* AvailabilityView。"Refresh"->True で強制更新 *)
ClaudeBindWorker[capReq, opts]            (* BindingDecision。"Avoid"->{...} で再束縛 *)
ClaudeCapabilityRequest[class, opts]      (* TaskClass から CapabilityRequest の既定を組む *)
ClaudeDispatchExplain[decision]           (* Rejected を含む人間可読の説明 (式中心1セル) *)
$ClaudeCriticalityTable                   (* §4.2。上書き可 *)
$ClaudeWorkerClassTable                   (* WorkerClass × Site → backend 候補列 *)
```

`ClaudeResolveLLMTier` は**残す**。既存呼び出し元を壊さないため、内部で `ClaudeBindWorker` に委譲する薄いラッパへ置き換える（TaskClass → CapabilityRequest の既定変換を挟む）。

---

## 9. 実装インクリメント

各 Inc は独立に検証可能で、前の Inc を壊さないこと。

| Inc | 内容 | 受け入れ条件 |
|---|---|---|
| **Inc1** | `AvailabilityView` 新設。chatgptcodex の `iClaudeBackendAvailCompute` を実装。`Exhausted`/`Down` の区別と `ResetsAt` の伝播 | claudecode を rate-limit 状態に模擬したとき `Exhausted` + `ResetsAt` が返る。codex が `Unchecked` でなくなる。ローカル 3 種は既存動作のまま（無回帰） |
| **Inc2** | `CapabilityRequest` / `ClaudeBindWorker` の filter 部（PL・LocalOnly・NeedsTools・可用性・能力）。rank は Balanced 固定 | PL 0.85 の要求で claudecode が `Rejected(PrivacyLevel)` になる。`NeedsTools->True` でクラウドが全除外される。`Rejected` が全候補分埋まる |
| **Inc3** | Criticality 方策表と昇格・待機・降格の分岐 | `critical` + heavy が `Exhausted` → 降格せず待機を選ぶ。`routine` は即降格。`critical` で候補尽き → `Failure`（黙って降格しない） |
| **Inc4** | Petri フラグメント（§6.1）を net compiler に追加 | `Attempting` token ≤ 1 が交差 binding テストで保たれる。`MaxAttempts` 到達で `Failed` に落ちる。各 Attempt で `BoundAt` が異なる |
| **Inc5** | `ClaudeResolveLLMTier` を委譲ラッパ化 | 既存の tier 系テストが全て green のまま（無回帰が受け入れ条件） |
| **Inc6** | rank（Objective 別）と `SubscriptionUnits`/`LocalGPUSeconds` 記録 | MinLatency でローカルが優先される。ledger に 2 通貨が載る |
| **Inc7** | `ClaudeDispatchExplain` と観測（Degraded / Waiting / Escalated イベント） | 1 run の全束縛判断が事後に再構成できる |

**Inc1–Inc3 だけで「刻々変わる制約下で適切なモデルを選ぶ」は成立する。** Inc4 以降はワークフロー統合と最適化。

---

## 10. テスト仕様

可用性は外部状態なので、**注入可能にする**（`$ClaudeDispatchAvailabilityOverride`）。実機依存のテストは別立てにする。

必須ケース:

1. PL 境界：PL 0.25 / 0.5 / 0.85 / 1.0 × 各 provider で許可・却下が rule 107 と一致。
2. `NeedsTools -> True` でクラウドが必ず除外される（ツール結果の外部流出防止が崩れていないこと）。
3. `LocalOnly` で Subscription が必ず除外される。
4. `critical` が降格しない。`routine` が降格する。
5. heavy `Exhausted` + `ResetsAt` 60 秒後 + `critical` → 待機を選ぶ。同条件 `routine` → 降格。
6. 候補全滅で `Failure["NoWorkerAvailable"]`、`Rejected` に全候補と理由。
7. 再束縛：同じ `CapabilityRequest` でも可用性が変われば別 backend を返す。
8. 無回帰：既存 `ClaudeResolveLLMTier` の返り値 schema が変わらない。

---

## 11. Conductor v0.2 との関係

本仕様は v0.2 の**部分集合かつ先行実装**である。競合しない。

| v0.2 の節 | 本仕様の扱い |
|---|---|
| §7 worker binding | filter/rank の形を継承し、**現金なし領域に限定して先に実装する**。§7.2（`InferenceTrustDomain` を見る）は本仕様も従う |
| §8 会計 | `SubscriptionUnits` / `LocalGPUSeconds` のみ実装。予約 ledger・PriceCatalog は v0.2 に残す |
| §5 RequirementProfile | 本仕様の `CapabilityRequest` + `Criticality` が対応。v0.2 実装時に統合する（**二重化させない**） |
| §6 二層実行構造 | 本仕様は child net 内の 1 ステップだけを扱う。RunController は v0.2 |
| §10 tuner | 非スコープ。ただし §4.2 の方策表は将来の 1 knob 実験対象として設計する |

v0.2 が先に動き出した場合、本仕様は v0.2 §7 の実装詳細として吸収してよい。

---

## 12. 懸念点

1. ~~**`Headroom` を取れる保証がない。**~~ **解消（2026-08-30 実測）。** Claude Code CLI 2.1.250 は通常の呼び出しで `rate_limit_event` を返し、**窓ごとの利用率を含む**:

   ```json
   {"status":"allowed_warning","utilization":0.75,"surpassedThreshold":0.75,
    "rateLimitType":"seven_day",
    "unifiedWindows":{"five_hour":{"utilization":0.16,"resetsAt":...},
                      "seven_day":{"utilization":0.75,"resetsAt":...}}}
   ```

   よって `Headroom = 1 - utilization` が **窓ごとに**取れる。§4.3 の `Headroom` は単一値ではなく **窓ごとの Association** に改める（`five_hour` と `seven_day` は独立に枯れる。5 時間窓に余裕があっても 7 日窓が尽きていれば使えない）。`critical` の温存戦略は成立する。

   実測時に **live なバグを 1 件発見・修正**した（下記 §12.6）。
2. **待機はワークフローを止める。** `MaxWaitForTier` を長くすると run が長時間ハングして見える。待機中であることが UI に見えないと事故になる（`WaitingForCapacity` の可視化は Inc4 の必須要件）。
3. **ローカルの直列性を過小評価しない。** llama.cpp は 1 モデル常駐で同時実行できない。fan-out でローカルを複数割り当てると直列化して待ち行列になる。rank の Balanced はこれを考慮する必要がある（Inc6）。
4. **Criticality の運用者依存。** 全部 `critical` と書かれたら意味がない。既定は `routine` とし、昇格は明示のみ。使用実績を Inc7 の観測で見て、必要なら方策表を締める。
5. **検証者の独立性が確保できない環境がある。** ローカル 1 モデルのみの構成では自己検証になる。`SelfVerify` の記録は必須。

6. **[実測中に発見・修正済] status の新値による誤った rate-limit 判定。** CLI 2.1.250 が返す `"allowed_warning"` を旧コードが `=== "allowed"` の完全一致で判定していたため、**まだ使える状態を制限ヒットとして記録**していた。連鎖は `ClaudeBackendAvailableQ -> Available:False` → `ClaudeResolveLLMTier["code"]` が定額 CLI を捨てて **従量課金 API へ黙って昇格**（候補が claudecode のみの `"design"` は `Selected -> None` で実行不能）。判定を「制限している status の明示列挙」へ反転し、**未知の status は制限していない側に倒す**ようにした（実際に制限されていれば 429/result 経路が確実に捕まえて自己修復するが、逆に倒すと課金という不可逆な副作用が出るため）。

   **教訓**: provider が返す enum に対する完全一致判定は、provider 側の値追加で静かに壊れる。しかもこの向きの壊れ方は「安全側」ではなく「課金側」だった。§4.3 の `State` 判定も同じ設計上の注意が要る。

---

## 13. 次の作業

1. 本仕様のレビュー（懸念 1 の事前確認 = CLI が rate-limit 余力を返すかの実測を含む）。
2. 承認後 Inc1 から実装。仕様生成／仕様実装の回収対象とする。
3. Inc3 完了時点で、実ワークフロー 1 本（例: メール要約 → 検証 → 再要約）をパイロットとして通す。
