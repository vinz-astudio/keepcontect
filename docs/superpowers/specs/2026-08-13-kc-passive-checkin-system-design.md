# Keep Contact Passive Check-In System Design

## Metadata

| Field | Value |
|---|---|
| ID | KC-PASSIVE-CHECKIN-SPEC-001 |
| Revision | 8 |
| Status | Proposed. Revision 5 cut the design to the revision 4 goal; Codex peer review agreed the cuts and option A, returning five findings. Revisions 6–8 closed them across three review passes, each pass catching a contradiction the previous revision had introduced. Codex re-review of revision 8 pending; human written acceptance pending. Two Open Decisions remain, both requiring the human or real-device data rather than more design. |
| Change class | Product-UX / M3 |
| Proposed decision | ADR-0042 (renumbered 2026-08-14; ADR-0041 is the accepted Brain-global “Caveman Internal Communication”) |
| Replaces if accepted | ADR-0037 learned silence as live alert authority; ADR-0040 D2 automatic contextual thresholds |
| Preserves if accepted | ADR-0039 explicit alert resolution and Guardian/Ward boundaries (**with one flagged conflict, see Open Decision 1**); ADR-0040 platform-specific collection with platform-neutral normalization; existing self → group → community escalation |
| Implementation authority | None. Human acceptance required before any implementation plan, source change, migration, deployment, release or Store action. |

## Goal (authoritative; do not remove or reword in later revisions)

Human decision, 2026-08-14. This statement outranks every capability argument in this document. Verbatim source:

> 用户按自设的频率和时长"被动签到",如果连续超出了自设的漏签次数,就进入告警流程。学习功能主要只是提供用户合适设置的推荐值罢了。
>
> 我已经意识到很难去"人出事了有人知道",尤其要非常贴合与即时。我现在只是希望 app 的运作比市场上一般的那种"需要用户每天自己手动签到"的 app 要再方便一点点,这样罢了。

Normative form:

1. KC's passive check-in **does not promise timely or reliable detection of a real emergency**. It must never be described, tested or accepted as if it did.
2. Its purpose is to let a user enter the **existing** alert funnel on their own configured terms — their own `D`, their own `N` — and to **replace most manual check-in actions with ordinary device use**.
3. The comparison baseline is the ordinary market product that asks the user to check in manually once a day. KC must be **modestly more convenient than that baseline**.
4. Learning produces **recommended values only**.

### Operational acceptance criterion

The dominant failure mode under this goal is **not a false miss. It is being more annoying than a manual check-in App.** That is measurable, and the measurement gates rollout.

**An interruption** is a passive-engine event delivered to the subject that demands their attention:

- a self-confirmation alert opening, and
- a collector-repair notice.

Not interruptions: silent recommendation updates, in-app status the user was not notified about, and anything the subject never receives as a notification. Escalations that reach the group or community are counted and reported **separately**; they are the funnel's concern, not this metric's.

```text
numerator   = interruptions delivered to the subject
denominator = subject-days with passive protection active and >= 1 bound surface
metric      = interruptions per subject-day

gate (all must hold, per platform-mix cohort):
  median subject   <= 0.2 per day
  p90 subject      <= 1.0 per day
  measured over    >= 14 consecutive days
  cohort size      >= 20 subjects; smaller cohorts are reported but do not gate
```

`p90 <= 1.0` is the hard line: it is the point at which a user is being asked as often as a once-a-day manual check-in App would ask, which is the baseline this product exists to improve on. `median <= 0.2` is the target: a typical user is asked about once every five days.

### Direct consequences

- A device that cannot prove absence is **not** a device that disqualifies its owner from protection. Passive evidence buys silence; its absence means the funnel's first stage asks the user, which is the market baseline and is an acceptable outcome.
- Cost of a wrongly derived `missed`: the subject is asked once. Only an **unanswered** first stage reaches the group.
- Recommended values must be **generous where the platform is weak**, so ordinary daily activity almost always covers them.

## Normative Language

“Must”, “must not”, “only”, “never” and exact formulas are implementation requirements. “May” describes an allowed option. An implementation cannot claim conformance by substituting a different alert-affecting rule.

## Open Decisions (human must resolve before acceptance)

### Open Decision 1 — may a silent collector eventually reach the group?

Revisions 1–4 held that technical failure can never become a safety escalation (ADR-0039, and invariant “collector failure can never be converted into `missed`”). That is why `unknown` existed as a blocking state and why the coverage/witness machinery existed to produce it.

Revision 5's goal accepts the cost of a wrongly derived `missed`, which removes the reason for that machinery. But it also means: **a phone whose battery dies produces no evidence, accrues misses, and — if the user never answers the first-stage prompt — eventually reaches the group.**

| Option | Behaviour | Cost |
|---|---|---|
| **A (recommended)** | A dead collector is treated the same as a missed manual check-in. It counts. The group message must say KC lost contact, not that the person is in danger. | Contradicts ADR-0039's technical/safety separation. Requires an explicit ADR-0039 amendment. |
| **B** | `unknown` remains a blocking state; a dead collector never counts. | Brings back coverage proof, per-device health gating, and the multi-device veto problem. Keeps KC silent in the case a manual check-in App would have caught. |

Revision 5 is **written for option A**, because option B reintroduces exactly the complexity this revision removed and produces behaviour worse than the manual-check-in baseline. **This is flagged, not decided.** If the human chooses B, the aggregation and chain sections must be rewritten.

### Open Decision 2 — the iOS `H_floor` number

The platform floor for an iOS-only account is currently a provisional engineering estimate (6–8 hours), not a measured value. It must be replaced by measured data before it can be a production default. See “Platform floor”.

## What Revisions 6–8 Closed

Codex peer review, 2026-08-14 (`Coordination/Threads/KC Passive Check-In Spec Revision 5 Review.md`). It agreed that none of the five revision 5 removals is still necessary, that the flat arrival allowance loses no load-bearing counting semantics, and that option A is right. It returned four sufficiency gaps and one overreach, then re-reviewed revision 6 and marked two still PARTIAL.

| Finding | Closed by | Verdict |
|---|---|---|
| **F1** Arrival-allowance input set undefined for PWA/Shortcut/Linux, so `max` was not exhaustively implementable | **Surface registry** — one closed table, five columns, no implicit default; a surface type absent from it cannot be bound | CLOSED in rev 6 |
| **F4** “well below 1” had no threshold, numerator, cohort, window or sample minimum | Interruption defined by enumeration; numerator, denominator, `median <= 0.2`, `p90 <= 1.0`, `>= 14 days`, `>= 20 subjects per cohort` | CLOSED in rev 6 |
| **F5** iOS `force-quit` claims exceeded the verified fact — Apple documents relaunch after `terminated` and is silent on user force-quit | Wording changed to `terminated` throughout, with a Terminology note stating the limit; the iOS real-device gate now settles force-quit by measurement and writes the result back | CLOSED in rev 6 |
| **F2** Ready/Limited and the learner's outage exclusion need per-surface state that revision 5 deleted | Rev 6 added **Surface Health** current state. Codex: PARTIAL — current fields cannot answer “did this episode overlap an outage”, because once a surface recovers the history is gone. Rev 7 adds **persisted health intervals** with explicit open/close/recovery semantics and a retention floor of lookback + correction horizon | CLOSED in rev 7 |
| **F3** Platform floor mixed `D_floor` rows with an `H_floor(surface mix)` formula; mixed-surface precedence and `D_suggested` undefined | Rev 6 added best-surface minimums and the full formula, but left `D_floor(account) = min(∅)` for PWA/Shortcut-only accounts and contradicted its own registry. Rev 7 gives **every** registry row both values — surfaces without a tight floor carry the manual-baseline `360 min / 12 h` — so the empty set cannot arise and the contradictory fallback clause is gone | CLOSED in rev 7 |
| **F6** (rev 7 regression) `tauri_native_linux` was given a 5-minute cadence in the registry while the prose called it non-scheduled, which would manufacture false `silent` intervals | Rev 8 separates the two reasons a surface carries the manual-baseline floor: **no scheduled contact** (`pwa_browser`, `shortcut` — cadence `—`, never `silent`) versus **scheduled contact but an unreviewed idle collector** (`tauri_native_linux` — cadence 5 min, can be `silent`, floors move to `tauri_native`'s when the review passes) | CLOSED in rev 8 |
| **F7** (rev 7 regression) the worked manual-baseline result was stated unconditionally, but holds only for `R <= 12 h`; the learner caps nothing | Rev 8 qualifies the result to `R <= 12 h` and states that above it the mapping dominates. `R` is deliberately **not** capped to the floor: capping the learned value would reintroduce the removed learned-threshold behaviour through the recommendation path, and a genuine 18-hour quiet recommended at 12 hours manufactures interruptions | CLOSED in rev 8 |

## What Revision 5 Removed From Revision 4, And Why

Revisions 1–4 were written against a higher goal, where a wrongly derived `missed` was expensive. The revision 4 goal accepts that cost. Everything below existed to prevent that one outcome and is therefore no longer paid for. Revision 4's full text remains in git history.

| Removed | Why |
|---|---|
| Three-level device model: `decision-grade` / `witness-capable` / `eligible witness`, and witness enrollment | Its only job was deciding whose absence counts. Under this goal, absence counts regardless of which device failed to report. |
| Complete-coverage assertion contract, capability hash, `account_collector_grace` | Proof that a collector was watching is no longer required to conclude anything. Collector health survives as an honest UI signal that gates nothing. |
| `Umax`, `unknown_budget`, `chain_deadline`, chain invalidation, the reliability regression model and the pinned 19.8732-window / 6.6244-hour acceptance number | All downstream of `unknown` being a blocking state. With `unknown` no longer blocking, a chain is simply N consecutive windows with no evidence. |
| 95% decision-deadline real-device gates, “zero false complete-coverage assertions” | Measured absence-proving quality. The gate that matters now is interruption rate. |
| iOS-only accounts denied inactivity-alert authority | Contradicted the goal: it made KC worse than the manual-check-in baseline it must improve on. |

**Kept unchanged and independent of goal level:** learner-writes-recommendations-only (the ADR-0037 defect correction), evidence qualification rules, device binding / credential revocation / idempotency / clock rules, privacy, retention, access and Store contracts, the existing funnel, passive-evidence-never-resolves-an-alert, the sleep gate and its required explicit choice, and engine modes / shadow / migration / rollback.

## Decision Summary

Keep Contact becomes an account-level **passive check-in system**.

Ordinary use or carriage of any correctly bound personal device may produce a qualified check-in. The user owns the two alert-sensitivity controls:

1. collection interval `D`, any whole minute from 20 through 360; and
2. consecutive-miss count `N`, any positive integer from 1 through 1,000,000.

```text
H = D × N
```

`H` is always shown in plain language. A configured sleep/post-wake gate and a bounded evidence-arrival allowance can delay alert creation; each is shown separately and never hidden inside `H`.

Learning estimates a personal reference `R` and converts it into a recommendation. It has no authority to modify active `D`, active `N`, a miss counter or an alert.

```text
N consecutive windows with no qualified evidence
  -> explicit self-confirmation alert
  -> group escalation if the user does not respond
  -> community escalation under the existing rules
```

Passive evidence after alert creation never resolves, retracts or answers that alert.

## Product Meaning and Limits

The protected subject is the account, not a device. Devices are equal evidence providers and are never primary or secondary.

A passive check-in means:

> KC received credible recent activity associated with this account and one of its bound personal-device surfaces, so it does not need to ask.

It does **not** prove identity, consciousness, location or safety. A borrowed, shared, stolen or automated device can create device-associated evidence without proving who caused it. The product must explain this and provide device removal and disable controls.

A `missed` result means “no qualified evidence reached KC in this window.” It must not be described as proof that the device was unused, or that the person is unsafe.

## Invariants

1. Every enabled monitoring window is deterministically `checked_in`, `missed`, or internally `superseded`.
2. Only `missed` advances the consecutive-miss counter.
3. `checked_in`, `superseded`, an explicit alert resolution and a monitoring-epoch change terminate the current chain.
4. Any qualified evidence from any correctly bound signed-in surface makes the account window `checked_in`.
5. A late positive event may correct history; late absence may never retroactively create a miss.
6. Learning writes recommendations only.
7. Passive evidence never resolves an open alert.
8. One collector installation can provide operating-system passive evidence to only one protected-subject account at a time.
9. Guardian activity, external confirmation, notification acknowledgement, wake execution and collector heartbeat are not Ward activity.
10. Legacy thresholds and fixed dark-device timers cannot independently create an inactivity alert for an account whose engine mode is `passive_checkin`.
11. Recommended settings must not be published for a platform mix that cannot usually satisfy them (see “Platform floor”).

## Domain Terms

| Term | Meaning |
|---|---|
| Protected account | The Ward/self account whose inactivity is evaluated. |
| Surface | A native installation, Tauri installation, PWA/browser session or Shortcut credential. |
| Collector | Platform code that produces qualified evidence. |
| Account contract version | Immutable settings and sleep-policy choice used for a sequence of windows. |
| Monitoring epoch | A counter lifetime beginning at enablement, settings replacement or explicit alert resolution. |
| Evidence | A qualified user/device-associated event with a real occurrence time. |
| Collector health | An honest per-device display of whether a collector is currently reporting. It gates nothing. |

## User-Controlled Settings

### Collection interval `D`

- Valid values are integer minutes `20 <= D <= 360`.
- One-minute slider steps, plus an accessible numeric input over the same range.
- No platform silently rounds the stored value.
- A shorter `D` creates more windows. It does not guarantee that an operating system will wake a collector every `D`, and below the platform floor it raises the interruption rate rather than the sensitivity.

### Consecutive-miss count `N`

- Valid values are integers `1 <= N <= 1,000,000`. This is a storage bound, not a product preset.
- Values that make `H > 30 days` remain allowed with a non-blocking warning.
- Duration arithmetic uses integer minutes and checked 64-bit or arbitrary-precision arithmetic.

### Initial active values

- A new user who explicitly enables passive protection starts with active `D = 120 minutes` and `N = 3`, raised to the platform floor where applicable, and only after the sleep-policy choice below.
- Existing users are never silently migrated to these values.

### Required sleep-policy choice

Passive protection cannot become active until the user explicitly chooses one of:

1. **Configured sleep protection (recommended):** save a valid local sleep start/end and IANA timezone; or
2. **No sleep gate:** acknowledge that overnight inactivity counts toward missed check-ins.

There is no preselected answer. A null or equal sleep window without a recorded choice is an onboarding-incomplete state and cannot activate passive protection. Changing this choice is alert-affecting and follows the settings-version rule.

### Saving settings

- A save becomes authoritative only after authenticated server acknowledgement; the server transaction timestamp is `effective_at`.
- Saving `D`, `N` or the sleep-policy choice creates a new account contract version and monitoring epoch at `effective_at`.
- The partial old window becomes `superseded`; it cannot become a miss. The old chain terminates and the new version starts at zero.
- If an alert is open, the save creates an acknowledged `pending_after_resolution` version that cannot touch the open alert; it becomes effective at `resolved_at`.
- Offline edits are drafts. Retried identical requests use an idempotency key.

## Time and Window Construction

All window bounds are UTC instants. `D` is elapsed time, so daylight-saving or timezone changes never lengthen or shorten a window.

```text
anchor(v) = v.effective_at
window(v, k) = [anchor(v) + kD, anchor(v) + (k + 1)D), k >= 0
```

Evidence exactly at `window_end` belongs to the next window. The user's timezone is used only for display, sleep-wall-clock interpretation and local-date learning rules. Windows are evaluated chronologically.

## Window States

| State | Public | Meaning | Counter effect |
|---|---:|---|---|
| `pending` | No | Window has not ended, or the evidence-arrival allowance has not elapsed. | None yet. |
| `checked_in` | Yes | At least one qualified event occurred inside the window. | Set counter to zero. |
| `missed` | Yes | No qualified event reached KC for this window by the allowance. | Increment by one. |
| `superseded` | No | A settings/epoch change ended a partial window. | Set counter to zero. |

There is no `unknown` state in the counting path. A window in which nothing arrived is a `missed` window, whatever the reason. Whether the cause was the person being quiet or a collector being broken is a **collector-health** question, surfaced honestly in the UI (see “Collector Health”), and it does not change the count.

### Surface registry

Every quantity in this document that is defined “per surface” reads from one closed registry. A surface type that is not in the registry **cannot be bound**; there is no implicit default and no open-ended fallback. This is what makes the `max` and `min` expressions below exhaustively implementable rather than aspirational.

| Surface type | Arrival allowance | Expected contact cadence | `D_floor` | `H_floor` |
|---|---:|---:|---:|---:|
| `tauri_native` (Windows, macOS) | 12 min | 5 min | 10 min | 30 min |
| `tauri_native_linux` | 12 min | 5 min | 360 min | 12 h |
| `android_native` | 35 min | 15 min | 35 min | 2 h |
| `ios_native` | 90 min | 60 min | 60 min | 6–8 h *(provisional, Open Decision 2)* |
| `pwa_browser` | 5 min | — | 360 min | 12 h |
| `shortcut` | 5 min | — | 360 min | 12 h |

- **Arrival allowance** — how long after `window_end` this surface may still deliver evidence for that window. `pwa_browser` and `shortcut` have no background schedule: they upload at the moment the user acts, so their allowance covers network retry only.
- **Expected contact cadence** — how often this surface is expected to contact the server at all when healthy. `—` means the surface has no scheduled contact, so its silence is not a health signal and it can never be `silent`.
- **`D_floor` / `H_floor`** — recommendation floors, see “Recommendation mapping and platform floor”. **Every surface type has both values defined**, so the minimums taken there are never over an empty set. Three surfaces carry the **manual-baseline floor** of `360 min / 12 h` — the coarsest permitted `D` and a 12-hour horizon — but for two different reasons, and the difference matters for health:
  - `pwa_browser` and `shortcut` have **no scheduled contact at all** (cadence `—`). They produce evidence only when the user acts, so there is no value in subdividing the horizon, and they can never be `silent`.
  - `tauri_native_linux` **does** contact on a schedule (cadence 5 min) and therefore can be `silent` and can produce health intervals. It carries the manual-baseline floor for a different reason: its idle collector has not passed the review the Windows/macOS one has, so it cannot claim a tight recommendation floor even though its delivery path is sound. When that review passes, its floors move to `tauri_native`'s and its cadence is unchanged.

Adding a surface type requires a versioned registry change with all five columns populated — none may be left undefined — and real-device evidence for the timing columns.

### Evidence-arrival allowance

A window is not finalized at `window_end`, because evidence is uploaded by collectors the operating system wakes on its own schedule.

```text
account_arrival_allowance = max(arrival_allowance(s) for each surface s bound to the account)
```

The account must have at least one bound surface for a monitoring epoch to exist, so this `max` is never taken over an empty set. The allowance delays finalization only. It never creates a miss, never changes the recommendation formula, and is displayed separately from `H`.

### State precedence

1. Qualified evidence immediately establishes `checked_in`.
2. Before `window_end`, a no-evidence result establishes nothing.
3. At `window_end + account_arrival_allowance`, a window with no qualified evidence becomes `missed`.
4. A terminal `missed` may become `checked_in` through trusted late positive evidence inside the correction horizon.
5. `checked_in` and `superseded` never become `missed`.

Every state change records old state, new state, reason code, policy version, actor, transaction time and causal evidence IDs.

## Surface Health

Two things still need to know whether a surface was working: the Ready/Limited display, and the learner's exclusion of episodes that span an outage. Both are served by the **narrow contract below**. It is deliberately not the removed coverage-assertion contract: it carries no interval proof, no capability hash, and no authority over any window.

### Current state

Per bound surface, the server maintains:

```text
last_evidence_at    -- last qualified evidence from this surface
last_contact_at     -- last authenticated request from this surface, evidence or not
permission_state    -- granted | denied | revoked | not_applicable
capability_state    -- ok | unsupported | degraded
reported_at         -- when the surface last asserted the two states above
```

A surface is **silent** when its expected contact cadence is defined and `now - last_contact_at > 2 × cadence`. A surface whose cadence is `—` in the registry is never silent, because it was never expected to contact on a schedule; its health is `permission_state`/`capability_state` only.

### Persisted health intervals

Current state alone cannot serve the learner. Excluding an episode that overlaps an outage requires knowing **when** that surface was unhealthy, and once it recovers `last_contact_at` no longer contains that history. Unhealthy periods are therefore recorded as closed intervals:

```text
surface_health_interval(surface_id, started_at, ended_at, reason)
  reason = silent | permission_denied | permission_revoked
         | capability_unsupported | capability_degraded
```

- An interval **opens** at the moment the surface first satisfies an unhealthy condition. For `silent`, that instant is `last_contact_at + 2 × cadence` — the moment the expectation was actually breached — not the moment the evaluator noticed it.
- An interval **closes** at the first authenticated contact that clears the condition: for `silent`, the first contact received; for the permission and capability reasons, the first report asserting a healthy state. `ended_at` is that contact's `received_at`.
- An interval with `ended_at IS NULL` is open, and for exclusion purposes extends to `now`.
- Overlapping intervals with different reasons are stored separately; the learner unions them.
- Intervals are retained for at least the learner's 30-day lookback plus the 7-day correction horizon, so an episode can never be evaluated against health history that has already been pruned.

A surface whose registry cadence is `—` can never produce a `silent` interval, but can still produce permission and capability intervals.

### The only two uses

1. **Display.** `Ready` when no bound surface is silent, denied, revoked, unsupported or degraded. `Limited` otherwise, naming the affected device and the exact repair reason. `Off` when no monitoring epoch is active.
2. **Learner exclusion.** An episode is excluded from training when it overlaps any `surface_health_interval` of any surface bound to that account at the time. This is the ADR-0037 defect: a collector outage must not be learned as the person's normal quiet.

### The boundary

Surface health **must not** be an input to window state, the miss chain, alert creation, or escalation. A test must prove that no code path reads surface health while deriving any of those. Collector failure never enters the self/group/community path as a safety signal; the existing ADR-0039 protection-health incident and notice machinery is retained unchanged for repair prompts.

`Limited` copy must state the real consequence in the user's terms — *KC may ask you more often than necessary* — never a claim about protection strength.

## Sleep and Post-Wake

The accepted local-wall-clock sleep model remains authoritative: `sleep_start_local`, `sleep_end_local` and the IANA timezone retain their meaning; cross-midnight handling remains; `private.sleep_relaxed` retains the two-hour post-wake grace; the accepted bounded dynamic extension remains pinned to the current `private.is_in_sleep_window` contract (qualifying activity inside the hour before configured sleep may extend the end to `min(last_active + configured window duration, configured end + 3 hours)`).

That gate applies only when the account contract records the explicit **Configured sleep protection** choice.

Passive windows and evidence collection continue during sleep, so night activity can check in and collector failures stay visible. Misses may accumulate during sleep, but no inactivity alert may open or escalate while the gate is active. On the first evaluator run after the gate ends:

- if the chain still contains at least `N` consecutive misses, open the self-confirmation alert;
- if a `checked_in`, `superseded` or epoch reset occurred, do not open from the old chain.

Sleep delays alert creation; it does not fabricate a check-in and does not reset a chain. If an alert is already open when sleep begins, existing pause/resume behaviour applies to escalation deadlines.

## Device Identity and Account Binding

- Each native or Tauri installation has one stable `collector_instance_id` and one active protected-account binding.
- Operating-system passive signals from that installation may be uploaded only for that bound subject.
- Switching accounts revokes the old binding and credential before creating the new one.
- Logout, device removal and account deletion revoke upload credentials and erase the local unsent queue.
- A revoked installation cannot upload old queued evidence.
- Separate browser profiles or Shortcuts may have separate scoped credentials; each event is attributed only to the authenticated subject encoded by its credential.

### Guardian/Ward boundary

A Guardian's device use is never Ward evidence. Viewing Ward data, sending Concern, acknowledging a notification or externally confirming safety never checks in the Ward and never trains the Ward learner. A person who is both a Guardian and a protected user has separate role contexts.

### Shared-device disclosure

Enrollment requires confirmation that the device is normally carried or used by the protected person. Shared-device use remains allowed, with a UI warning that another person's activity may create a check-in.

## Evidence Ingest and Trust

Every normalized evidence assertion contains: protected `account_id`; registered `collector_instance_id` or scoped credential ID; globally unique `event_id`; non-reusable local `sequence`; `observed_at` and `received_at`; normalized evidence class and qualification-policy version; collector contract/version and client version; source-local correlation identity; minimum qualification facts; payload hash.

The server verifies: authenticated subject and active binding; credential scope and revocation state; allowed evidence class for the declared collector; unique event ID and sequence; timestamp and correction-horizon rules; immutable payload identity on retry; window assignment from server-owned UTC bounds.

Duplicate `event_id` plus identical payload is idempotent. Reuse of an event ID or sequence with a different payload is rejected and logged as a security incident. Out-of-order unused sequences may be accepted for offline history; order alone does not decide occurrence time.

### Clock rules

- A real-time event may be at most five minutes in the future relative to server receipt.
- A device clock discontinuity greater than five minutes starts a new collector time epoch.
- Historical system-query events may be older than receipt time only when the declared collector contract supports history and supplies a successful query interval containing the event.
- Upload time is never activity time.

### Correction horizon

- The hard positive-evidence correction horizon is seven days, matching the iOS Core Motion historical bound.
- Older evidence is retained only as rejected audit metadata.
- Late positive evidence inside seven days may change `missed` to `checked_in`.
- If no alert opened, derived later counters are recomputed from the earliest corrected window.
- If an alert opened, its causal snapshot is immutable. The historical window may be corrected, but the alert is not resolved, retracted or relabeled.

## Qualified Evidence

Qualification occurs in the platform layer that understands the signal. The server consumes the normalized contract and must not infer semantics from package names, operating-system strings or legacy `kind/source` values.

| Normalized class | Examples | Exact qualification |
|---|---|---|
| `direct_device_use` | Android keyguard-hidden/unlock or foreground interaction; Tauri keyboard/mouse input; authenticated KC interaction; user-opened PWA; user-configured App-open Shortcut | Timestamped user-interaction event tied to the bound surface. Screen-on, background resume, page refresh or process launch alone is insufficient. |
| `personal_device_motion` | Positive iOS/Android steps or floors | Positive pedestrian steps/floors in the exact interval; automotive-only activity excluded; raw series and routes stay on-device. |
| `power_transition` | Cable or wireless power connected/disconnected | A real transition between two confirmed stable states, not an initial observation or inferred battery change. |
| `explicit_self_activity` | Ordinary deliberate KC action before any alert opens | Authenticated subject action that is not an alert response, notification acknowledgement, Guardian action or automated refresh. |

All qualified classes have equal window effect.

### Power-transition rules

Initial or restored charging state is baseline, never evidence. Both old and new states must be known. The new state must remain stable for five seconds. Repeated callbacks that do not change the stable state are ignored. All edges from the same collector inside 60 seconds share one correlation group for learning. Battery percentage movement, full-charge completion and estimated time remaining cannot invent an edge.

### Signals that cannot check in alone

Battery level change; continuously charging state; screen-on without unlock/interaction; other audio playing; raw accelerometer variance without qualified personal motion; push delivery, background wake, job execution or heartbeat; network traffic or successful upload; **significant location change or any location event**; automotive motion; Guardian/external confirmation; Concern or notification acknowledgement; replay receipt time.

These may support diagnostics, qualification or collector health, but never account activity by themselves. Location in particular is a **wake mechanism only**: it relaunches a terminated iOS app so that real evidence can be collected and uploaded, and no coordinate is ever read, stored or sent.

## Deduplication and Learning Sessionization

Window state is naturally idempotent. For storage and learning: identical event IDs are deduplicated at ingest; events with the same collector correlation identity are one action; power transitions inside the 60-second group are one action; qualified account events no more than two minutes apart are one cross-source observation cluster; successive clusters separated by ten minutes or less form one active-use episode; a silence gap runs from the last event of one episode to the first of the next.

Shortcut and manual/self-declared events may check in but remain excluded from personal-silence training under ADR-0039.

## Platform Collection Contracts

Every platform's job is the same: **when the operating system lets the collector run, reconstruct what happened since last time and upload it with its real occurrence timestamps.** No platform is required to prove it was watching.

### Android Native / Play AAB

- Requires explicit Usage Access granted through system settings, with the Play-facing prominent disclosure.
- Queries `UsageStatsManager` for the exact UTC window; keyguard-hidden and genuine foreground interaction qualify. Package names are processed locally and discarded.
- **The collector must upload the historical activity timestamp it already knows** (`queryLastActiveTime`), not merely the fact that it is currently awake. Reporting `observed_at = now` while holding proof of an earlier real interaction is the defect this contract exists to close.
- WorkManager and the server FCM wake path are execution opportunities, not exact timers. Historical reconstruction tolerates scheduling delay inside the arrival allowance.
- `ACTION_POWER_CONNECTED` / `ACTION_POWER_DISCONNECTED` / `ACTION_USER_PRESENT` / `SCREEN_ON` are **not** exempt from Android 8.0 implicit-broadcast restrictions and must never be declared in the manifest. They are foreground-only extras via runtime registration; background evidence comes from the UsageStats look-back.
- No package name, URL or per-App timeline leaves the device.

### iOS Native

iOS provides no retrospective proof that a phone was used, and a zero-step pedometer result proves only that no pedestrian motion was recorded — never that the person was inactive. iOS therefore contributes **positive evidence only**, and never manufactures a negative conclusion.

Under this revision's goal that is sufficient: absence of evidence lets the funnel ask, exactly as a missed manual check-in would. **An iOS-only account has full funnel access.**

Wake sources, in order of dependability:

| Source | Covers | Survives process termination |
|---|---|:-:|
| HealthKit background delivery (`HKObserverQuery`) | Indoor and outdoor movement; capped near hourly for step data | No |
| Silent push | Server-initiated confirmation that the device is reachable | No |
| `BGAppRefreshTask` | Opportunistic top-up | No |
| Significant-change location monitoring | **Relaunching a terminated app** so the others can be re-armed | **Yes, for `terminated`** |

**Terminology, held to what Apple actually documents.** `startMonitoringSignificantLocationChanges()` states that if the app "is subsequently **terminated**, the system automatically relaunches the app into the background if a new event arrives", and that **on relaunch the app must reconfigure a location manager and call the method again** or it will receive nothing further. HealthKit's `enableBackgroundDelivery` likewise describes the system **launching** the app. Neither page addresses **user-initiated force-quit** as a distinct case. This document therefore says `terminated` and makes no claim about force-quit; the iOS real-device gate must measure that case rather than assume it in either direction.

Location is register-and-forget: `startMonitoringSignificantLocationChanges` with **no** `startUpdatingLocation` and **no** `allowsBackgroundLocationUpdates`, so there is no continuous session, no status-bar indicator and no battery baseline. It requires Always authorization but **not** the `UIBackgroundModes: location` declaration, which must stay removed (human decision 2026-08-10: declaring a background mode the app never used for location made KC look more protective than it was). It fires only on movement between cell towers, so it does nothing for someone who stays home; indoor coverage is HealthKit's job.

Core Motion historical queries are limited to seven days. Raw motion/Health data, routes and coordinates remain on-device. Screen Time/DeviceActivity is not a core dependency and cannot be silently substituted.

### Tauri desktop

- Windows and macOS use native last-input/idle APIs; the existing five-minute lease cadence reconstructs recent keyboard/mouse activity with its true time.
- Startup/background operation requires explicit consent.
- App exit, sleep without resume reconstruction, or an unsupported API simply produces no evidence for that interval.
- Linux contributes foreground evidence only until a native idle collector passes the same review.

### PWA, browser and Shortcuts

- A deliberate authenticated foreground interaction may check in.
- Page visibility, service-worker wake, push receipt, refresh and open background tab are not evidence.
- WebKit Web Push requires a user-visible notification and cannot provide silent periodic collection.
- A scoped user-configured Shortcut may contribute a timestamped qualified event; Shortcut credentials are revocable and subject-bound, and Shortcut evidence cannot train `R`.

## Multi-Device Aggregation

```text
if qualified evidence exists from any correctly bound surface in the window:
    checked_in
else:
    missed
```

That is the whole rule. No device can veto another, no device outranks another, and no device's failure to report changes the outcome for the account — because the account-level question is only whether evidence arrived at all.

Adding a device can therefore only ever help. A device that stops reporting appears in collector health as a repair item and nothing more.

## Miss Chain and Alert

```text
checked_in  => clear chain
missed      => start chain if absent; confirmed_misses += 1
superseded  => clear chain
new epoch   => clear chain
```

When `confirmed_misses >= N`:

1. wait for the canonical sleep/post-wake gate to be inactive;
2. acquire an account-level idempotent alert lock;
3. verify no open self/group/community inactivity alert exists;
4. persist an immutable causal snapshot;
5. open exactly one existing self-confirmation alert.

The evaluator runs on the existing one-minute server schedule. Scheduler failure marks the account `Limited`; it does not silently extend `H`.

The causal snapshot contains: account contract and monitoring-epoch IDs; active `D` and `N`; the exact `N` missed window IDs; evidence cutoff and arrival allowance; per-surface last-evidence state; sleep-gate result and evaluation time; alert-policy version; all evidence IDs used.

### Open alert behaviour

Window and evidence history continue after alert creation. No passive event answers, closes or downgrades the open alert. New missed windows cannot create a duplicate alert. Changing settings while an alert is open affects only the post-resolution epoch. Existing self → group → community escalation and explicit resolution semantics remain.

### Resolution and restart

After an accepted explicit resolution: close or pause the alert per its canonical reason; start a new monitoring epoch at `resolved_at` using the latest acknowledged contract; clear the chain; start the first new window at `resolved_at`. Late evidence from before `resolved_at` cannot affect the new epoch.

### Legacy inactivity triggers

For `engine_mode='passive_checkin'`: learned threshold silence cannot open an alert; fixed 18-hour dark-device logic cannot open an inactivity alert; manual SOS and non-inactivity alert types retain their own accepted authority.

## Advisory Learning

### Authority boundary

The learner writes only recommendation and provenance state. Database privileges and tests must prove no path from learner code to active `D` or `N`, account contract versions, window outcomes, chain state, or alert creation/resolution/escalation/notification.

### Eligible personal silence episodes

An episode is eligible only when both bounding events are qualified self-observed evidence; all intervening windows are terminal `checked_in` or `missed`; no `superseded`, clock discontinuity or contract-version boundary intersects it; it does not cross alert creation/resolution; neither bound is Guardian/external confirmation, Concern, manual declaration, Shortcut, replay receipt, notification acknowledgement or alert response; and real occurrence timestamps define the gap.

Configured sleep and accepted post-wake intervals are unioned and subtracted. A right-censored current absence is never training data.

**Episodes spanning a period in which a bound surface was not reporting must be excluded from training.** This is the one place collector health still matters mechanically: it must not gate an alert, but it must not be learned as the person's normal quiet either. That conflation is the ADR-0037 defect.

### Session, lookback and estimator

Use the deduplicated activity episodes above. Rolling lookback is 30 complete UTC days ending at the last completed day. Evidence days count distinct user-local dates containing eligible evidence. The false-recommendation budget `B` is fixed at 1 per 30 evidence days.

```text
i = 1 + round(B × evidence_days / 30)
i = min(i, eligible_gap_count)
R_candidate = gap at rank i
```

No floor, cap, cohort prior or old active threshold is added. An episode longer than 150% of the published `R` may influence `R_candidate` only after a second episode on a different user-local date, independently valid, with `max/min <= 1.25`.

### Evidence sufficiency

| State | Requirement | Source |
|---|---|---|
| Insufficient | Fewer than 3 episodes or 3 evidence days | Transparent default `R = 6 hours`, labelled “personal evidence insufficient” |
| Low | ≥3 episodes and 3 evidence days | Personal `R`, low confidence |
| Medium | ≥10 episodes and 7 evidence days | Personal `R`, medium confidence |
| High | ≥30 episodes and 21 evidence days | Personal `R`, high confidence |

Confidence never changes active settings. Recompute after an eligible episode closes and in daily aggregation. Round published `R` to five minutes. Publish a change when it differs by at least the greater of 15 minutes or 10%, or when it changes `N_suggested`. Recommendation updates are silent; the user sees them in settings and never receives wording implying a setting changed.

### Recommendation mapping and platform floor

An unfloored mapping can recommend `D = 20 minutes, N = 18` to an account whose only surface is an iPhone — a combination iOS mechanics cannot usually satisfy, which raises interruptions above the manual-check-in baseline.

Both floors come from the surface registry, and both take the **minimum over bound surfaces**, because evidence may arrive from any one of them: an account's capability is that of its **best** surface, not its worst. Every registry row defines both values and an account must have at least one bound surface, so neither minimum is ever taken over an empty set.

```text
D_floor(account) = min(D_floor(s) for each bound surface s)
H_floor(account) = min(H_floor(s) for each bound surface s)

D_effective   = max(D_active, D_floor(account))
N_suggested   = max(1, ceil(R / D_effective))
H_suggested   = max(D_effective × N_suggested, H_floor(account))
N_final       = ceil(H_suggested / D_effective)
D_suggested   = D_effective
```

The recommendation published to the user is the pair `(D_suggested, N_final)`, with `H_suggested = D_suggested × N_final`.

An account whose every bound surface carries the manual-baseline floor — PWA and Shortcut only, or Linux only — has `D_floor(account) = 360 min` and `H_floor(account) = 12 h`. **For `R <= 12 h` that lands on `D_suggested = 360 min, N_final = 2, H_suggested = 12 h`.** For a larger `R` the mapping's own result dominates the floor and `N_final` rises accordingly; the floor only ever raises a recommendation, it never caps one.

`R` is deliberately **not** capped to the floor. If a person's learned quiet is genuinely 18 hours, recommending a 12-hour horizon would manufacture interruptions, and capping the learned value would smuggle the removed learned-threshold behaviour back in through the recommendation path.

An account in this state **is effectively a manual check-in product**: it produces evidence only when the user acts. The UI must say that plainly rather than presenting it as passive protection.

Both floors are static, explainable engineering constants. Neither is a learned live threshold: they do not come from this account's behaviour, they do not drift, and they only raise a **recommendation** — never an active setting the user chose.

| Registry basis | Confidence |
|---|---|
| `tauri_native` — existing five-minute lease cadence; continuous runtime, not OS-throttled | Measured |
| `android_native` — existing 35-minute arrival allowance; OEM battery-restricted devices sit at the slow end | Measured base case; OEM tail needs the real-device gate |
| `ios_native` — HealthKit background delivery, `BGAppRefreshTask` and silent push are all system-opportunistic with no guaranteed interval, and all stop once the process is terminated until a location relaunch or the user opens KC. The reliable source is the user's own ordinary daily device contact. | **Provisional engineering estimate — Open Decision 2. Must be replaced by the measured p95 evidence-arrival gap from the iOS real-device gate.** |

If a user manually sets values below the floor, the value is allowed and the UI must show the realistic expected interruption rate instead of the nominal `H`.

Contextual sleep/day/workday/weekend recommendations are outside this revision.

## Privacy, Security and Store Review

### Data minimization

The server may receive only: normalized evidence class and timestamps; device/collector/account/window identities; policy/contract/client versions; collector health reason; minimum qualification facts and hashes required for audit.

The server must not receive: App/package names; URLs, browsing history or typed/input content; raw keyboard/mouse data; raw accelerometer/pedometer series; **any location coordinate, route or passive GPS**; complete HealthKit records; audio content or currently playing media.

Existing user-controlled SOS/GPS features remain a separate purpose and permission.

### Retention

| Data | Retention |
|---|---:|
| Raw normalized evidence and ingest audit | 35 days |
| Window outcomes, collector-health incidents and recommendation snapshots | 90 days |
| Local encrypted offline evidence queue | 7 days maximum |
| Alert causal snapshots and explicit resolution audit | Lifetime of the parent alert record |

Expired records are removed by an observable scheduled job. Logout and device removal delete the local subject queue and revoke credentials immediately.

### Access

The protected user may read their own summarized evidence, windows, devices, settings and recommendations. An active Guardian may read the existing authorized Ward summary scope, not raw payloads or credentials. Raw collector and ingest tables are private, RLS-protected, absent from Realtime, and inaccessible to `anon` or `authenticated`. Every cross-account denial is tested.

### Local security

Native/Tauri device credentials and queued evidence use platform secure storage and encryption at rest. Shortcut tokens are random, scoped, revocable and never embedded in public URLs or logs. Logs redact tokens, payloads and raw device identifiers.

### Permission and review behaviour

Permission requests are purpose-specific, preceded by prominent disclosure, and made only after user action. Denial has a repair/disable path and truthful collector-health state. No persistent notification, exact alarm, full-screen intent, background location mode, or unapproved managed entitlement is a mandatory core dependency. Android Usage Access collection and uploaded-data limits must match Play declarations. iOS Motion/Health and location wording must match actual on-device processing — in particular, the location purpose string must state that KC uses it only to restart its guardian and never reads, stores or sends location.

## UX Requirements

The settings surface must: expose the one-minute `D` slider and a numeric alternative; expose a numeric `N` input; show active `D`, `N`, nominal `H`, the arrival allowance and the sleep-delay note; show the recommendation separately with Apply, evidence period, counts and confidence; never auto-apply a recommendation; show Ready/Limited/Off at account level with per-device repair reasons; avoid primary/secondary device language; allow explicit device disable, sign-out and removal; require the sleep-policy choice before enablement with neither option preselected; explain shared-device limitations; explain that evidence is not proof of safety; and show saved state only after server acknowledgement.

Below the platform floor, the surface must show the estimated real interruption rate rather than presenting the nominal `H` as achievable.

Accessibility: all controls have localized accessible names, values, ranges and error text; the slider is keyboard and screen-reader operable; numeric fields do not depend on drag gestures; color is never the only readiness signal; focus order and validation messages are announced without stealing focus.

## Compatibility and Migration

### Per-account engine modes

| Mode | Meaning |
|---|---|
| `legacy` | Existing threshold path remains live. Passive-check-in data may not affect alerts. |
| `shadow` | New windows and recommendations are computed and compared, with zero alert authority. |
| `passive_checkin` | This specification is the only inactivity-alert authority. |

Both engines must never create inactivity alerts for the same account.

### Existing users

1. Deploy schema and collectors disabled; run local and integration verification.
2. Run `shadow` for at least 14 consecutive days, measuring the interruption rate that would have resulted.
3. Offer an explicit migration screen showing `D`, `N`, `H`, the platform floor for that user's devices, and the recommendation source.
4. Require an explicit sleep-policy choice before creating the first passive contract.
5. Users who do not choose remain `legacy`; no values are silently activated.
6. An open legacy alert completes under its original lifecycle before migration begins.

### Old clients

Old clients may continue sending accepted legacy evidence. They cannot edit passive settings unless they implement the contract version. An account cannot enter `passive_checkin` until its active client can display collector health and manage settings. Server APIs remain additive during the compatibility window.

### Historical data

Old learned threshold numbers are never copied into `R`. Historical raw evidence may seed `R` only after passing the identity, qualification, deduplication, sleep and outage rules. If fewer than three eligible episodes remain, use the transparent 6-hour default.

### Rollback

A global kill switch stops new passive inactivity alerts and marks affected accounts `Limited`. It must not silently substitute a legacy threshold. Returning a migrated account to `legacy` requires separate human authorization, preserved open-alert state and a user-visible explanation. No rollback rewrites completed windows or alert causal snapshots.

## Observability

**The goal's acceptance metric outranks the rest and must gate rollout:**

- user-facing interruptions per user per day, and the share of days with zero interruption, segmented by platform mix.

Also required, segmented by platform/contract/client version without raw personal payloads: pending, checked-in, missed and superseded window counts; pending beyond allowance; per-surface evidence-arrival gap distribution (this is the input for the platform floor); late positive correction count, **segmented by whether the corrected window fell inside an opened alert's causal snapshot** — that segment is the false-alert rate; duplicate/replay/conflicting-ID rejection count; cross-account/binding rejection count; miss-chain and alert-eligibility transitions; passive alert opens and duplicate-lock suppressions; recommendation source/confidence/change rate; cleanup and retention job health.

Hard invariant alarms: any late absence creating a miss; any passive event resolving an alert; any Guardian/external event becoming Ward evidence; any cross-account collector acceptance; both engines opening inactivity alerts for one account; any prohibited raw field — especially a location coordinate — leaving a collector.

Operational degradation: an evaluator schedule gap greater than three minutes marks server protection `Limited`; one subject failure must not abort processing for others; scheduler, cleanup and notification jobs expose last success, last error and skipped-subject counts.

## Verification and Acceptance

### Contract cases

1. Evidence at `window_start` belongs to that window; evidence at `window_end` belongs to the next.
2. DST and timezone changes do not change UTC window duration.
3. A settings change supersedes the partial window and starts counter zero at server `effective_at`.
4. Any qualified bound-surface event produces `checked_in`.
5. A window with no evidence from any surface produces `missed`, regardless of which collectors were healthy.
6. One surface being unhealthy never changes the outcome of a window in which another surface produced evidence.
7. An iOS-only account can accumulate misses and open a self-confirmation alert.
8. Exactly `N` consecutive misses creates one self-confirmation alert.
9. No later missed window duplicates an open alert.
10. Passive evidence after alert creation cannot resolve it.
11. Explicit resolution starts a new epoch and window at `resolved_at`.
12. Sleep permits miss accumulation but suppresses alert creation until the canonical grace ends.
13. A sleep-time check-in clears the chain.
14. A missing sleep-policy choice prevents enablement.
15. Legacy threshold and dark-device rules cannot create passive-mode inactivity alerts.
16. A recommendation below the platform floor is never published.

### Trust and identity cases

One collector cannot be bound to two accounts; account switch revokes the old credential and queue; Guardian activity cannot create Ward evidence; identical retry is idempotent; the same event ID with a changed payload is rejected and audited; a future timestamp over five minutes is rejected; positive history inside seven days may correct to checked-in; late absence cannot create a miss; evidence older than seven days cannot affect derived state.

### Evidence cases

Android keyguard-hidden and foreground interaction qualify, screen-on alone does not; **Android uploads its known historical activity timestamp rather than `now`**; Android package names never leave the device; positive pedestrian steps/floors qualify and automotive-only motion does not; an iOS zero-step result never produces a negative conclusion; initial charging state does not qualify while a confirmed stable transition does; callback flap and battery increase do not qualify; Tauri input uses its reconstructed time; PWA deliberate interaction qualifies while push and page visibility do not; heartbeat, wake, notification acknowledgement and network success never check in; **a significant location change never checks in and no coordinate is ever read, stored or sent**; cross-source duplicates do not distort learning sessions.

### Learning cases

Superseded, outage, alert-response, Guardian, Shortcut and replay intervals do not train; **episodes spanning a non-reporting surface do not train**; sleep and post-wake intervals are subtracted; right-censored absence does not train; fewer than three episodes shows the default 6-hour recommendation; the estimator uses `B=1` over 30 evidence days; a single >150% gap cannot change `R`; two comparable different-date gaps may; the mapping uses `ceil(R/D)` and is then raised to the platform floor; recommendation writes cannot mutate active settings, windows, chains or alerts.

### Privacy cases

Payload inspection finds no package name, URL, typed content, route, coordinate, raw motion or Health record; authenticated users cannot read private ingest tables; the subject reads only their own summaries; a Guardian gets authorized summaries only; device removal revokes credentials and clears the local queue; retention jobs remove 35/90-day records; raw tables are absent from Realtime.

### Platform real-device gates

Each platform gate now measures **evidence arrival**, not absence proof.

- **Android AAB:** at least three physical devices spanning major OEM restrictions; 20-minute, 2-hour and 6-hour settings; unlock/use, no-use, Doze, reboot, Usage Access denial and revocation, locked-after-reboot, network outage, OEM battery restriction; Play disclosure and data-safety payload inspection; **measured evidence-arrival gap distribution**; historical timestamps land in their true windows.
- **iOS Native/TestFlight:** at least three iPhone/OS combinations; foreground use, sedentary and pedestrian scenarios, charging transition, Motion denial and revocation, suspension, **user force-quit followed by movement (does a location relaunch actually occur?) and user force-quit without movement (does anything at all recover?)** — Apple documents relaunch after `terminated` but is silent on force-quit, so this gate exists to settle it by measurement, and its result must be written back into the “Terminology” note in the iOS contract; restart, network outage, silent-push delay and drop; **measure the gap between consecutive positive-evidence arrivals and publish the p95 as `H_floor`**, replacing the provisional estimate; zero coordinates in any payload; no zero-motion result promoted to a negative conclusion.
- **Tauri:** Windows and macOS; startup consent, five-minute leases, input and no-input, sleep/resume, exit, network outage, clock change; measured arrival gaps; zero browser/Tauri channel confusion.

### Rollout gates

14 days shadow with zero hard-invariant violation; **the measured interruption rate meets the goal's acceptance criterion for every platform mix**; no account receives alerts from both engines; shadow replay explains every outcome by causal IDs; the false-alert segment of late positive corrections is quantified; migration flow and accessibility pass; kill switch tested without production mutation; independent non-author review has no blocker; production, deploy, release and Store authority obtained separately.

## Implementation Packages After Written Acceptance

1. Database contracts: engine mode, account contract version, monitoring epoch, windows, evidence, causal snapshot, RLS and pgTAP.
2. Trust and ingest: device binding, credential revocation, idempotency, sequence, timestamp, correction and retention.
3. Android collector: historical timestamp upload and device tests.
4. iOS collector: positive evidence, wake-source layering including location relaunch, and TestFlight evidence.
5. Tauri collector and Windows/macOS evidence.
6. Aggregation, chain, sleep integration, alert idempotency and legacy-trigger retirement.
7. Advisory learner, platform floor and provenance.
8. Settings, collector-health and migration UX with accessibility.
9. Shadow comparison, observability, rollback and integrated verification.

Each package receives a separate exact write set and TDD plan. Spec-complete isolated database packages are candidates for agy or V4 under locked hash-addressed orders. Codex owns semantic integration and final verification.

## Non-Scope

- Source or migration implementation in this design task.
- Production mutation, deployment, release or Store submission.
- Automatic setting changes.
- Passive automatic alert resolution.
- Identity or safety proof from device activity.
- **Any use of location beyond relaunching a terminated iOS process.**
- Cohort or AI-controlled live alert rules.
- Context-dependent active schedules beyond the existing user-configured sleep gate.
- Family Controls/DeviceActivity as a required core dependency.

## Authoritative References

- Human decisions in Codex Desktop on 2026-08-13; goal reduction 2026-08-14; location restore decision 2026-08-14.
- `Projects/Keep Contact/Decisions.md` ADR-0037, ADR-0039, ADR-0040.
- `Projects/Keep Contact/Business Logic/Sleep Window.md`.
- `Coordination/Threads/KC Native Collector Evidence Loss Claude to Codex Handoff 2026-08-13.md`.
- `android/PLAY-CONSTRAINTS.md`.
- [Android UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager.html) · [implicit broadcast exceptions](https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions) · [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent).
- [Apple CMPedometer historical queries](https://developer.apple.com/documentation/coremotion/cmpedometer/querypedometerdata%28from%3Ato%3Awithhandler%3A%29) · [background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) · [background push limits](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) · [monitoring location changes](https://developer.apple.com/documentation/corelocation/monitoring-location-changes-with-core-location).
- [WebKit Web Push user-visible requirement](https://webkit.org/blog/16535/meet-declarative-web-push/).
- Microsoft `GetLastInputInfo` documentation.
