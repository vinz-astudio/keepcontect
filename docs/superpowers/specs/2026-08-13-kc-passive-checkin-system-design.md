# Keep Contact Passive Check-In System Design

## Metadata

| Field | Value |
|---|---|
| ID | KC-PASSIVE-CHECKIN-SPEC-001 |
| Revision | 2 |
| Status | Proposed; conceptual direction approved 2026-08-13; revision 2 written review pending |
| Change class | Product-UX / M3 |
| Proposed decision | ADR-0041 |
| Replaces if accepted | ADR-0037 learned silence as live alert authority; ADR-0040 D2 automatic contextual thresholds; legacy inactivity and dark-device alert triggers for accounts migrated to the passive-check-in engine |
| Preserves if accepted | ADR-0039 explicit alert resolution, protection-health, Guardian/Ward and Store-first invariants; ADR-0040 platform-specific collection and platform-neutral normalization; existing self → group → community escalation |
| Implementation authority | None. Human acceptance of this written revision is required before an implementation plan, source change, migration, deployment, release or Store action. |

## Normative Language

“Must”, “must not”, “only”, “never” and exact formulas in this document are implementation requirements. “May” describes an allowed option. An implementation cannot claim conformance by substituting a different alert-affecting rule.

## Decision Summary

Keep Contact becomes an account-level **passive check-in system**.

Ordinary use or carriage of any correctly bound personal device may produce a qualified check-in. The user owns the two active alert-sensitivity controls:

1. collection interval `D`, any whole minute from 20 through 360 minutes; and
2. consecutive-miss count `N`, any positive integer from 1 through 1,000,000.

The configured silence horizon is:

```text
H = D × N
```

`H` is always shown in plain language. A collector decision deadline can add bounded processing delay after the last window; a configured sleep/post-wake gate can delay alert creation further. Those delays are shown separately and never hidden inside `H`.

Learning continuously estimates a personal reference `R` and converts it into a recommendation. It has no authority to modify active `D`, active `N`, a miss counter or an alert.

The existing escalation funnel remains:

```text
N consecutive complete misses
  -> explicit self-confirmation alert
  -> group escalation if the user does not respond
  -> community escalation under the existing rules
```

Passive evidence after alert creation never resolves, retracts or answers that alert.

## Product Meaning and Limits

The protected subject is the account, not a device. Devices are equal evidence providers and are never primary or secondary.

A passive check-in means:

> KC received credible recent activity associated with this account and one of its bound personal-device surfaces, so the inactivity funnel does not need to start yet.

It does **not** prove identity, consciousness, location or safety. A borrowed, shared, stolen or automated device can create device-associated evidence without proving who caused it. The product must explain this limitation and provide device removal and passive-protection disable controls.

A `missed` result means “no signal supported by the declared collector contract was observed under complete coverage.” It must not be described as proof that the device was unused or that the person is unsafe.

## Non-Negotiable Invariants

1. Every enabled monitoring window is deterministically `checked_in`, `missed`, `unknown` or internally `superseded`.
2. Only `missed` advances the consecutive-miss counter.
3. `checked_in`, `unknown`, `superseded`, an explicit alert resolution and a monitoring-epoch change terminate the current consecutive-miss chain.
4. Any qualified evidence from any correctly bound signed-in surface makes the account window `checked_in`.
5. Collector failure, permission loss, shutdown, force-stop, missing history, background delay and upload failure can never be converted into `missed`.
6. A late positive event may correct history, but late absence/coverage may never retroactively create a miss.
7. Learning writes recommendations only.
8. Passive evidence never resolves an open alert.
9. One collector installation can provide operating-system passive evidence to only one protected-subject account at a time.
10. Guardian activity, external confirmation, notification acknowledgement, wake execution and collector heartbeat are not Ward activity.
11. Legacy thresholds and fixed dark-device timers cannot independently create an inactivity alert for an account whose engine mode is `passive_checkin`.

## Human Requirement Trace

| Human requirement | Normative closure in this revision |
|---|---|
| Collection must be reviewable by platform stores | Platform contracts minimize data, use purpose-specific consent, avoid prohibited core dependencies and require Play/App Store evidence before Ready. |
| Platforms may collect differently but must share one logic | Platform collectors emit the same evidence/coverage contracts; the account state machine contains no platform-specific branch. |
| Passive use should avoid changing normal device habits | Historical/system signals and quiet background opportunities are used; persistent notifications and repeated prompts are not core requirements. |
| Evidence may be complex but must credibly indicate the person/device is active | Only qualified direct use, personal motion, stable power transitions and explicit self activity check in; technical/environmental signals alone do not. |
| Charging plug/unplug is credible | Stable observed power transitions qualify; initial state and battery drift do not. |
| All devices are equal | Any correctly bound device can check in; no primary/secondary role exists. |
| User chooses interval and consecutive misses | `D` is any whole minute from 20–360; `N` is any positive integer within the explicit storage bound; active values change only by user action. |
| Learning should reuse the old silence idea only as advice | `R` is learned from coverage-valid silence and maps to `N_suggested`; the learner has no active-setting or alert authority. |
| Alert escalation stays as before | Only the inactivity trigger changes; self → group → community and explicit resolution remain governed by accepted alert contracts. |

## Domain Terms

| Term | Meaning |
|---|---|
| Protected account | The Ward/self account whose inactivity is evaluated. |
| Surface | A native installation, Tauri installation, PWA/browser session or Shortcut credential. |
| Collector | Platform code that qualifies evidence and/or proves coverage. |
| Decision-grade collector | A collector allowed to contribute complete coverage and therefore participate in a `missed` decision. |
| Positive-only surface | A surface that may check in the account but can never prove absence or create `missed`. |
| Account contract version | Immutable settings and enrolled decision-grade collector roster used for a sequence of windows. |
| Monitoring epoch | A continuous counter lifetime beginning at enablement, settings/roster replacement or explicit alert resolution. |
| Coverage | Proof that a declared collector contract observed or reconstructed an exact interval, independent of whether activity occurred. |
| Evidence | A qualified user/device-associated event with a real occurrence time. |

## User-Controlled Settings

### Collection interval `D`

- Valid values are integer minutes `20 <= D <= 360`.
- The duration slider uses one-minute steps. Keyboard arrows change one minute; Page Up/Down change ten minutes.
- An accessible numeric-duration input exposes the same range and value.
- No platform silently rounds the stored value.
- A shorter `D` creates more windows. It does not guarantee that an operating system will wake a collector exactly every `D`.
- If a device cannot satisfy the selected interval and its decision deadline, affected windows become `unknown` and protection becomes `Limited`.

### Consecutive-miss count `N`

- Valid values are integers `1 <= N <= 1,000,000`.
- The range is a transport/storage bound, not a product preset.
- The UI uses a numeric input/stepper, accepts direct entry and exposes an accessible label.
- Values that make `H > 30 days` remain allowed but show a non-blocking warning that protection may be too slow for urgent use.
- Duration arithmetic uses integer minutes and arbitrary-precision or checked 64-bit arithmetic. It must not overflow JavaScript number or database interval calculations.

### Initial active values

- A new user who explicitly enables passive protection starts with active `D = 120 minutes` and active `N = 3`.
- Existing users are not silently migrated to these values.
- The initial values are editable before confirmation.

### Saving settings

- A settings save becomes authoritative only after authenticated server acknowledgement.
- If no alert is open, the server transaction timestamp is `effective_at`; client clocks do not choose it.
- Saving `D`, `N` or the decision-grade collector roster then creates a new account contract version and monitoring epoch at `effective_at`.
- The partial old window becomes `superseded`; it cannot become a miss. The old chain terminates and the new version starts with counter zero.
- If an alert is open, the save creates an acknowledged `pending_after_resolution` version with `created_at` but no `effective_at`. It cannot change the open alert, its causal snapshot or its escalation. The latest acknowledged pending version becomes effective at `resolved_at` and starts the new post-resolution epoch.
- Offline edits are drafts only. They do not affect protection until acknowledged.
- Retried identical requests use an idempotency key and return the already-created version.

### Learned recommendation

- The recommendation is visually and semantically separate from active settings.
- Applying it requires an explicit authenticated user action and follows the normal settings-version rule.
- Ignoring or dismissing it changes no active state.
- Moving the `D` slider previews the recommended `N` for that `D` without changing active `N`.

## Authoritative Time and Window Construction

All window bounds are UTC instants. `D` is elapsed time, so daylight-saving or timezone changes never lengthen or shorten a window.

For contract version `v`:

```text
anchor(v) = v.effective_at
window(v, k) = [anchor(v) + kD, anchor(v) + (k + 1)D), k >= 0
```

Evidence exactly at `window_end` belongs to the next window.

The user’s timezone is used only for display, sleep-wall-clock interpretation and local-date learning rules. A timezone change does not rewrite completed window bounds.

Windows are evaluated chronologically. A later window may receive evidence early, but alert eligibility cannot skip an earlier `pending` window.

## Internal and Public Window States

| State | Public | Meaning | Counter effect |
|---|---:|---|---|
| `pending` | No | Window has not ended or required reports have not reached their deadline. | None yet. |
| `checked_in` | Yes | At least one qualified event occurred inside the window. | Set counter to zero. |
| `missed` | Yes | No qualified event exists and every enrolled decision-grade collector proved complete coverage before its deadline. | Increment by one. |
| `unknown` | Yes | No qualified event exists and completeness was not proven by the decision deadline. | Set counter to zero and show `Limited`. |
| `superseded` | No | A settings/roster/epoch change ended a partial window. | Set counter to zero. |

`unknown` terminates a consecutive chain. The following sequence contains two separate one-miss chains, not two consecutive misses:

```text
missed -> unknown -> missed
```

### State precedence and transitions

1. Qualified evidence immediately establishes `checked_in`.
2. Before `window_end`, a no-evidence result cannot establish `missed` or `unknown`.
3. At or after `window_end`, complete reports from all enrolled decision-grade collectors with no evidence establish `missed`.
4. If completeness is absent at the account decision deadline, the window becomes `unknown`.
5. A terminal `missed` or `unknown` may become `checked_in` only through trusted late positive evidence within the correction horizon.
6. A terminal `unknown` can never become `missed`.
7. `checked_in` and `superseded` never become `missed`.

Every state change records old state, new state, reason code, policy version, actor, transaction time and causal evidence IDs.

## Collector Reporting Deadlines

Decision deadlines bound how long a no-evidence window may remain pending:

| Decision-grade contract | Maximum report lag after `window_end` |
|---|---:|
| Tauri continuous runtime + native idle contract | 12 minutes |
| Android UsageStats history contract | 35 minutes |
| iOS Core Motion history contract | 35 minutes |

For an account with multiple enrolled collectors:

```text
account_decision_deadline =
  window_end + max(enrolled collector report lags)
```

The values preserve the verified 5-minute Tauri and 15-minute native/server collection cadences and allow bounded missed beats. A future collector contract may use another deadline only through a versioned design change and real-device evidence.

The maximum non-sleep decision time shown by the UI is:

```text
configured horizon = D × N
maximum collector grace = max enrolled report lag
```

The grace is not added to `D`, does not create extra misses and does not change the recommendation formula.

## Sleep and Post-Wake Interaction

The accepted local-wall-clock sleep model remains authoritative:

- `sleep_start_local`, `sleep_end_local` and the IANA timezone retain their existing meaning;
- cross-midnight handling remains;
- `private.sleep_relaxed` retains the existing two-hour post-wake grace;
- the accepted bounded dynamic sleep extension remains;
- changing timezone changes how “now” is interpreted but does not rewrite the configured local clock numbers.

Passive windows and evidence collection continue during sleep. This is necessary so activity during the night can check in the account and collector failures remain visible.

Miss windows may accumulate during sleep, but the system must not open or escalate an inactivity alert while the canonical sleep/post-wake gate is active. On the first evaluator run after the gate ends:

- if the current chain still contains at least `N` consecutive misses, open the self-confirmation alert;
- if a `checked_in`, `unknown`, `superseded` or epoch reset occurred, do not open from the old chain.

Sleep delays alert creation; it does not fabricate a check-in and does not reset a miss chain.

If an alert is already open when sleep begins, existing accepted pause/resume behavior applies to escalation deadlines. Sleep never resolves the alert and must not be reported as detected personal activity.

The settings UI therefore shows:

- nominal `H`;
- maximum collector grace;
- “Your sleep and post-wake window can delay alerts” when configured.

## Device Identity, Account Binding and Roles

### One passive subject per installation

- Each native or Tauri installation has one stable `collector_instance_id` and one active protected-account binding.
- Operating-system passive signals from that installation may be uploaded only for that bound subject.
- Switching protected accounts revokes the old binding and credential before creating the new one.
- Logout, device removal and account deletion revoke upload credentials and erase the local unsent queue for that subject.
- A revoked installation cannot upload old queued evidence.
- Separate browser profiles or Shortcuts may have separate positive-only credentials, but each event is attributed only to the authenticated subject encoded by its scoped credential.

### Guardian/Ward boundary

- A Guardian’s device use is never Ward evidence.
- Viewing Ward data, sending Concern, acknowledging a notification or externally confirming safety never checks in the Ward and never trains the Ward learner.
- A person who is both a Guardian and a protected user has separate role contexts. Only activity collected under that person’s own protected-subject binding counts for them.

### Shared-device disclosure

Enrollment requires confirmation that the device is normally carried or used by the protected person. Shared-device use remains allowed, but the UI warns that activity from another person may create a check-in.

## Evidence Ingest and Trust Contract

Every normalized evidence assertion contains:

- protected `account_id`;
- registered `collector_instance_id` or scoped positive-only credential ID;
- globally unique `event_id`;
- non-reusable local `sequence`;
- `observed_at` and `received_at`;
- normalized evidence class and qualification-policy version;
- collector contract/version and client version;
- source-local correlation identity;
- minimum qualification facts;
- payload hash.

The server verifies:

1. authenticated subject and active device/account binding;
2. credential scope and revocation state;
3. allowed evidence class for the declared collector;
4. unique event ID and sequence;
5. timestamp and correction-horizon rules;
6. immutable payload identity on retry;
7. account/window assignment from server-owned UTC bounds.

Duplicate `event_id` plus identical payload is idempotent. Reuse of an event ID or sequence with a different payload is rejected and logged as a security incident.

Out-of-order unused sequences may be accepted for offline history; order alone does not decide occurrence time.

### Clock rules

- A real-time event may be at most five minutes in the future relative to server receipt.
- A device clock discontinuity greater than five minutes starts a new collector time epoch and makes uncovered time `unknown`.
- Historical system-query events may be older than receipt time only when the declared collector contract supports history and supplies a successful query interval containing the event.
- Upload time is never activity time.

### Correction horizon

- The hard positive-evidence correction horizon is seven days, matching the iOS Core Motion historical availability bound.
- Evidence older than seven days is retained only as rejected audit metadata and cannot change windows, counters, alerts or learning.
- Late positive evidence inside seven days may change `missed` or `unknown` to `checked_in`.
- Late negative reports or late coverage cannot change `unknown` to `missed`.
- If no alert opened, derived later counters are recomputed from the earliest corrected window.
- If an alert opened, its causal snapshot is immutable. The historical window may be corrected, but the alert is not resolved, retracted or relabeled.

## Qualified Evidence

Qualification occurs in the platform layer that understands the signal. The server consumes the normalized contract and must not infer semantics from package names, operating-system strings or legacy `kind/source` values.

### Evidence that can check in

| Normalized class | Examples | Exact qualification |
|---|---|---|
| `direct_device_use` | Android keyguard hidden/unlock or foreground interaction; Tauri keyboard/mouse input; authenticated KC pointer/key interaction; user-opened PWA; user-configured App-open Shortcut | Timestamped user-interaction event tied to the bound/scoped surface. Screen-on, background resume, page refresh or process launch alone is insufficient. |
| `personal_device_motion` | Positive iOS/Android steps or floors | Positive pedestrian steps/floors in the exact interval; automotive-only activity excluded; raw series and routes stay on-device. |
| `power_transition` | Cable or wireless power source connected/disconnected | A real transition between two confirmed stable states, not an initial observation or inferred battery change. |
| `explicit_self_activity` | Ordinary deliberate KC action before any alert opens | Authenticated subject action that is not an alert response, notification acknowledgement, Guardian action or automated refresh. |

All qualified classes have equal window effect: one or more events make the account `checked_in`.

### Power-transition rules

- Initial or restored charging state is baseline state, never evidence.
- Both old and new states must be known.
- The new state must remain stable for five seconds before qualification.
- Repeated callbacks that do not change the stable state are ignored.
- All edges from the same collector inside 60 seconds share one correlation group for learning, although raw audit may retain both edges.
- Battery percentage movement, full-charge completion and estimated time remaining cannot invent an edge.

### Signals that cannot check in alone

- battery level rising or falling;
- continuously charging state;
- screen-on without unlock/interaction;
- other audio playing;
- raw accelerometer variance without qualified personal motion;
- push delivery, background wake, job execution or heartbeat;
- network traffic or successful upload;
- runtime/coverage lease;
- automotive motion;
- Guardian/external confirmation;
- Concern or notification acknowledgement;
- replay receipt time.

These may support diagnostics, qualification or coverage, but never account activity by themselves.

## Deduplication and Learning Sessionization

Window state is naturally idempotent: any number of qualified events still produces one `checked_in`.

For storage and learning:

- identical event IDs are deduplicated at ingest;
- events with the same collector correlation identity are one action;
- power transitions inside the 60-second correlation group are one action;
- qualified account events no more than two minutes apart are one cross-source observation cluster;
- successive observation clusters separated by ten minutes or less form one active-use episode;
- a silence gap runs from the last event of one episode to the first event of the next.

This prevents one human action observed by Native, PWA and Shortcut from creating artificial learning density. Shortcut and manual/self-declared events may check in but remain excluded from personal-silence training under ADR-0039.

## Coverage Contract

Activity and coverage are independent facts.

A complete coverage assertion contains:

- account and collector identity;
- collector contract/version and capability hash;
- exact UTC interval;
- permission/capability state;
- runtime state;
- query/observation result;
- query execution time;
- client/app version;
- stable idempotency identity and payload hash.

A heartbeat proves only that a collector ran. It is not activity, and it is not complete coverage unless a declared continuous-runtime contract uses adjacent authenticated leases to construct exact intervals.

The ADR-0040 four runtime states map as follows:

| Runtime state | Coverage meaning | Alert effect |
|---|---|---|
| `app_foreground` | May support complete coverage under the platform contract. | Normal window evaluation. |
| `app_background` | May support complete coverage if the collector independently observes/reconstructs the interval. | Normal window evaluation. |
| `app_killed` | Incomplete coverage; server may attempt a platform-permitted wake and show one protection-health repair notice. | `unknown`, never human-safety alert. |
| `device_off` | Incomplete known technical state. | `unknown`, never human-safety alert. |

Push delivery outcome may support the diagnostic distinction between `app_killed` and `device_off`, but because delivery is best-effort it cannot by itself establish either state or complete coverage.

Permission loss, force-stop, suspension, shutdown, failed history access, insufficient history retention, client clock discontinuity, unresolved upload failure and missed decision deadline all make coverage incomplete.

## Platform Capability Contracts

### Android Native / Play AAB

Decision-grade contract: `android_usage_history_v1`.

- Requires explicit Usage Access granted through system settings and the Play-facing prominent disclosure.
- Queries `UsageStatsManager` for the exact UTC window.
- Qualifying direct use includes keyguard-hidden/unlock and genuine foreground interaction. Package names are processed locally and discarded.
- A successful query covering the exact interval plus a valid capability state can assert complete coverage even when no qualifying event exists.
- A null/failed query, locked-after-reboot state, expired system history or revoked access is incomplete.
- WorkManager and the existing server wake path are execution opportunities; they do not define activity and are not exact timers.
- Historical reconstruction tolerates scheduling delay only inside the 35-minute report deadline.
- Power broadcasts follow the power-transition rules.
- APK and AAB share the collector, but Play AAB review and behavior are the release standard.
- No package/App name, URL or per-App timeline leaves the device.

Android’s `UsageStatsManager.queryEvents` uses inclusive begin/exclusive end Unix-time bounds, requires Usage Access for other Apps and keeps event history only for a limited number of days. The implementation must fail to `unknown` when those prerequisites are not satisfied.

### iOS Native

Decision-grade contract: `ios_pedometer_history_v1`.

- Requires Motion permission and a successful `CMPedometer.queryPedometerData` result for the exact window.
- Positive steps/floors are `personal_device_motion`.
- A successful exact-window query with zero qualifying motion may assert complete coverage for the **personal-motion contract only**.
- The resulting `missed` means no qualified personal motion was observed; it does not mean the iPhone was unused.
- Foreground user interaction and captured power transitions are additional positive evidence, but their absence cannot support complete coverage because iOS does not provide a general retrospective stream for them.
- Silent APNs, BGTask, HealthKit/Core Motion wake and foreground launch are execution opportunities only.
- If iOS does not wake KC and the exact-window result is not uploaded by the 35-minute deadline, the window is `unknown`.
- Force-quit, Motion denial, unavailable pedometer data, query failure or insufficient result bounds are incomplete.
- Core Motion historical queries are limited to the past seven days; KC’s alert deadline is intentionally much shorter.
- Raw motion/Health data, routes and time series remain on-device.

This contract is decision-grade only after the real-device release gate passes. Until then, iOS Native is positive-only and must display `Limited`.

Screen Time/DeviceActivity is not a core dependency. A future direct-use contract requires a separate accepted design, explicit person authorization, the required Family Controls/App and Website Usage entitlements, Apple distribution approval, privacy review and Store evidence. It cannot be silently substituted into this contract.

### Tauri desktop

Decision-grade contract: `tauri_idle_runtime_v1`.

- Windows and macOS use native last-input/idle APIs.
- Authenticated runtime leases at the existing five-minute cadence build continuous coverage only when adjacent accepted leases leave no gap greater than 12 minutes.
- Native last-input data reconstructs the latest keyboard/mouse event inside the window.
- Startup/background operation requires explicit consent.
- App exit, failed startup, suspend without valid resume coverage, unsupported API or lease gap greater than 12 minutes is incomplete.
- Sleep/resume splits coverage unless native history proves the interval.
- Linux is positive-only until a native decision-grade contract passes the same review and device gates.

### PWA, browser and Shortcuts

- PWA/browser surfaces are positive-only.
- A deliberate authenticated foreground interaction may check in.
- Page visibility, service-worker wake, push receipt, refresh and open background tab are not evidence.
- WebKit Web Push requires a user-visible notification and cannot provide silent periodic collection.
- A PWA closing or being evicted never creates `missed` and never blocks an enrolled native collector.
- A scoped user-configured Shortcut may contribute a timestamped qualified event.
- Shortcut credentials are revocable, subject-bound and positive-only.
- Shortcut/manual evidence cannot train `R`.
- iOS PWA is not a substitute for the iOS Native decision-grade history contract.

## Multi-Device Account Aggregation

Only explicitly enrolled decision-grade collectors participate in completeness. Any correctly bound positive-only surface may contribute positive evidence.

The enrolled roster is snapshotted in the account contract version. A roster change supersedes the partial window and begins a new epoch.

```text
if qualified evidence exists from any correctly bound surface:
    checked_in
else if no decision-grade collector is enrolled:
    unknown
else if every enrolled collector reported complete exact-window coverage
        by the account decision deadline:
    missed
else:
    unknown
```

A stale enrolled collector is never silently removed. It remains a visible `Limited` cause until the user repairs, disables, signs out or removes it.

Global passive protection Off creates no new monitoring windows. Enabling it requires at least one surface, but the UI must distinguish:

- **Ready**: at least one decision-grade collector is enrolled and every enrolled collector is currently healthy;
- **Limited**: protection is enabled but a collector/permission/deadline/capability problem prevents dependable miss decisions;
- **Positive-only**: check-ins can occur but no decision-grade collector is enrolled;
- **Off**: no passive monitoring epoch is active.

## Consecutive Miss and Alert State Machine

The counter is derived from ordered terminal windows in the current monitoring epoch.

```text
checked_in  => streak = 0
missed      => streak = streak + 1
unknown     => streak = 0
superseded  => streak = 0
new epoch   => streak = 0
```

When `streak >= N`:

1. wait for the canonical sleep/post-wake gate to be inactive;
2. acquire an account-level idempotent alert lock;
3. verify no open self/group/community inactivity alert exists;
4. persist an immutable causal snapshot;
5. open exactly one existing self-confirmation alert.

The evaluator runs on the existing one-minute server schedule. After the final required window and collector deadline are eligible, server scheduling adds at most one normal evaluator minute unless the scheduler is unhealthy. Scheduler failure makes protection `Limited`; it does not silently extend `H`.

The causal snapshot contains:

- account contract and monitoring-epoch IDs;
- active `D` and `N`;
- the exact `N` missed window IDs;
- evidence cutoff and account decision deadline;
- collector roster and coverage result IDs;
- sleep-gate result and evaluation time;
- alert-policy version.

### Open alert behavior

- Window/evidence history may continue after alert creation.
- No passive event answers, closes or downgrades the open alert.
- New missed windows cannot create a duplicate alert.
- Changing `D`, `N` or devices while an alert is open affects only the post-resolution monitoring epoch.
- The existing self → group → community escalation and explicit self/Guardian/GM resolution semantics remain.

### Resolution and restart

After an accepted explicit resolution:

- close/pause the existing alert according to its canonical reason;
- start a new monitoring epoch at `resolved_at` using the latest acknowledged account contract;
- set streak to zero;
- start the first new window at `resolved_at`.

Late evidence from before `resolved_at` cannot affect the new epoch.

### Legacy inactivity triggers

For `engine_mode='passive_checkin'`:

- learned threshold silence cannot open an alert;
- fixed 18-hour dark-device/device-off logic cannot open an inactivity alert;
- killed/offline states are protection-health incidents;
- manual SOS and non-inactivity alert types retain their own accepted authority.

This prevents a technical outage from bypassing the user’s selected `D/N` contract.

## Protection Health and User Notices

- The server owns Ready/Limited/Positive-only/Off truth.
- One incident has a stable incident ID, start, reason, affected collectors and recovery evidence.
- Dismissing a notice does not restore Ready.
- Recovery requires new valid coverage under the current collector contract.
- Technical failure never enters self/group/community safety escalation.
- The subject receives at most one protection-health notice per incident, plus persistent in-App status.
- Additional background notifications require explicit opt-in and platform/store permission.
- Existing “special concern” and Guardian visibility rules remain; notices must say coverage stopped and does not prove danger.

## Advisory Learning

### Authority boundary

The learner can write only recommendation and provenance state. Database privileges and tests must prove no path from learner code to:

- active `D` or `N`;
- account contract versions;
- window outcomes or streak;
- alert creation, resolution, escalation or notification.

### Eligible personal silence episodes

An episode is eligible only when:

- both bounding events are qualified self-observed evidence;
- all intervening windows have terminal `checked_in` or `missed` outcomes with complete decision-grade coverage;
- no `unknown`, `superseded`, clock discontinuity or contract-version boundary intersects it;
- it does not cross alert creation/resolution;
- neither bound is Guardian/external confirmation, Concern, manual declaration, Shortcut, replay receipt, notification acknowledgement or alert response;
- real occurrence timestamps define the gap.

Configured sleep and accepted post-wake intervals are unioned and subtracted from the gap. Missing evidence can never extend sleep or reduce the effective gap.

`unknown` ends an episode. A right-censored current absence is never training data.

### Session and lookback

- Use the deduplicated activity episodes defined above.
- Rolling lookback is 30 complete UTC days ending at the last completed day.
- Evidence days count distinct user-local dates containing eligible decision-grade coverage.
- The false-recommendation budget `B` is fixed at 1 per 30 evidence days for revision 2.

### Personal reference estimator

Let eligible effective gaps be sorted from longest to shortest. Let:

```text
i = 1 + round(B × evidence_days / 30)
i = min(i, eligible_gap_count)
R_candidate = gap at rank i
```

No floor, cap, cohort prior or old active threshold is added.

An episode longer than 150% of the currently published `R` is an exceptional-long candidate. It may influence `R_candidate` only after a second episode:

- occurs on a different user-local date;
- is independently coverage-valid; and
- has `max(gap1, gap2) / min(gap1, gap2) <= 1.25`.

This implements ADR-0039’s repeated-comparable-long-gap rule without letting one outage rewrite advice.

### Evidence sufficiency and confidence

| State | Requirement | Recommendation source |
|---|---|---|
| Insufficient | Fewer than 3 eligible episodes or fewer than 3 evidence days | Transparent default `R = 6 hours`; label “personal evidence insufficient” |
| Low | At least 3 episodes and 3 evidence days | Personal `R`, low confidence |
| Medium | At least 10 episodes and 7 evidence days | Personal `R`, medium confidence |
| High | At least 30 episodes and 21 evidence days | Personal `R`, high confidence |

Confidence never changes active settings.

### Publication and stability

- Recompute after an eligible episode closes and in the daily aggregation.
- Round displayed/published `R` to the nearest five minutes; retain exact internal provenance.
- Publish a changed `R` when it differs from the current published value by at least the greater of 15 minutes or 10%, or when it changes `N_suggested` for active `D`.
- A loss of evidence sufficiency publishes the default/insufficient state; it never changes active settings.
- Recommendation updates are silent in the background. The user sees them in settings; they do not receive wording implying a setting changed.

### Recommendation mapping

```text
N_suggested = max(1, ceil(R / D))
H_suggested = D × N_suggested
```

For `R = 6 hours`:

| `D` | `N_suggested` | `H_suggested` |
|---:|---:|---:|
| 20 minutes | 18 | 6 hours |
| 1 hour | 6 | 6 hours |
| 2 hours | 3 | 6 hours |
| 3 hours | 2 | 6 hours |
| 6 hours | 1 | 6 hours |

The UI shows source, lookback, episode count, evidence days, confidence and last calculation time.

Contextual sleep/day/workday/weekend recommendations are outside revision 2. Adding them requires separately visible advice and cannot introduce automatic context-dependent active rules.

## Privacy, Security and Store-Review Contract

### Data minimization

The server may receive only:

- normalized evidence class and timestamps;
- device/collector/account/window identities;
- policy/contract/client versions;
- coverage interval and health reason;
- minimum qualification facts and hashes required for audit.

The server must not receive:

- App/package names;
- URLs, browsing history or typed/input content;
- raw keyboard/mouse data;
- raw accelerometer/pedometer series;
- routes or passive GPS;
- complete HealthKit records;
- audio content or currently playing media.

Existing user-controlled SOS/GPS features remain separate purposes and permissions.

### Retention

| Data | Retention |
|---|---:|
| Raw normalized evidence, coverage assertions and ingest audit | 35 days |
| Window outcomes, protection-health incidents and recommendation snapshots | 90 days |
| Local encrypted offline evidence queue | 7 days maximum |
| Alert causal snapshots and explicit resolution audit | Same lifetime as the parent alert record; removed only by the existing alert/account deletion path |

Expired records are removed by an observable scheduled job. Aggregates retained beyond raw detail must not contain package names, locations or source-identifiable raw motion.

Logout/device removal deletes the local subject queue and revokes credentials immediately. Account deletion removes active-database passive-check-in data through the account-deletion transaction; backup expiry follows the disclosed infrastructure backup lifecycle.

### Access

- The protected user may read their own summarized evidence, windows, devices, settings and recommendations.
- An active Guardian may read the existing authorized Ward summary/health/timeline scope, not raw collector payloads or credentials.
- Ordinary group/community members see only the already-authorized protection/alert summaries.
- Raw collector and ingest tables are private, RLS-protected, absent from Realtime and inaccessible directly to `anon` or `authenticated`.
- Operational workers use owner/service-only functions with per-subject failure isolation.
- Every cross-account denial is tested.

### Local security

- Native/Tauri device credentials and queued evidence use platform secure storage and encryption at rest.
- Shortcut tokens are random, scoped, revocable and never embedded in public URLs or logs.
- Logs redact tokens, event payloads and raw device identifiers.

### Permission and review behavior

- Permission requests are purpose-specific, preceded by prominent disclosure and made only after user action.
- Denial has a repair/disable path and truthful Positive-only/Limited state.
- No persistent notification, exact alarm, full-screen intent, background location or unapproved managed entitlement is a mandatory core dependency.
- Android Usage Access collection and uploaded-data limits must match Play declarations.
- iOS Motion/Health wording must match actual on-device processing.
- Family Controls/DeviceActivity cannot ship until Apple grants required distribution capability and the submitted purpose matches actual behavior.

## UX Requirements

The settings surface must:

- expose one-minute `D` slider and numeric alternative;
- expose numeric `N` input;
- show active `D`, active `N`, nominal `H`, maximum collector grace and sleep-delay note;
- show recommendation separately with Apply, evidence period, counts and confidence;
- never auto-apply a recommendation;
- show Ready/Limited/Positive-only/Off at account level;
- show each device’s platform, last healthy coverage, decision-grade/positive-only capability and exact repair reason;
- avoid primary/secondary device language;
- allow explicit enrollment, disable, sign-out and removal;
- explain shared/borrowed-device limitations;
- explain that evidence is not proof of safety;
- show saved state only after server acknowledgement.

Accessibility requirements:

- all controls have localized accessible names, values, ranges and error text;
- slider operation is possible by keyboard and screen reader;
- numeric fields do not depend on drag gestures;
- color is never the only readiness/confidence signal;
- focus order, dynamic recommendation updates and validation messages are announced without stealing focus.

If a selected `D` is shorter than a device’s proven capability, the value remains allowed but the device displays:

> This device may not complete every selected window. Unobserved windows become Unknown, not missed check-ins.

## Compatibility and Migration

### Per-account engine modes

Exactly one mode is authoritative per account:

| Mode | Meaning |
|---|---|
| `legacy` | Existing threshold path remains live. Passive-check-in data may not affect alerts. |
| `shadow` | New windows/recommendations are computed and compared, with zero alert authority. |
| `passive_checkin` | This specification is the only inactivity-alert authority. |

Both engines must never create inactivity alerts for the same account.

### Existing users

1. Deploy schema/collectors disabled and run local/integration verification.
2. Run `shadow` for at least 14 consecutive days.
3. Offer an explicit migration screen showing `D`, `N`, `H`, device capability and recommendation source.
4. Migrate only after user acknowledgement and server creation of the first passive contract.
5. Existing users who do not choose remain `legacy`; no default values are silently activated.
6. An open legacy alert completes under its original causal lifecycle. Engine migration begins only after it closes.

### New users

After production promotion, onboarding may offer passive protection with initial active 2 hours × 3 misses. Permission and device enrollment remain explicit.

### Old clients

- Old clients may continue sending accepted legacy evidence during rollout.
- They cannot edit passive settings or claim Ready unless they implement the contract version.
- An account cannot enter `passive_checkin` until its active client can display Limited/Unknown and manage devices/settings.
- Server APIs remain additive during the compatibility window.

### Historical data

- Old learned threshold numbers are never copied into `R`.
- Historical raw evidence may seed `R` only after it passes the new identity, qualification, coverage, deduplication, sleep and outage rules.
- Unknown or unverifiable history is excluded.
- If fewer than three eligible episodes/days remain, use the transparent 6-hour default recommendation.
- The uncommitted iOS device-sample promotion migration/test are candidate implementation material only and must be rebased onto this contract.
- The withdrawn coverage-learning migration remains withdrawn.

### Rollback

- A global/platform kill switch stops new passive inactivity alerts and marks affected accounts Limited.
- It must not silently substitute a legacy threshold.
- Returning an already migrated account to `legacy` requires a separate human-authorized rollback, preserved open-alert state and user-visible explanation.
- No rollback rewrites completed windows or alert causal snapshots.

## Observability and Operational Safety

Required metrics, segmented by platform/contract/client version without raw personal payloads:

- pending, checked-in, missed, unknown and superseded window counts;
- pending beyond deadline;
- unknown reason and duration;
- collector deadline success rate;
- late positive correction count;
- duplicate/replay/conflicting-ID rejection count;
- cross-account/binding rejection count;
- miss streak and alert-eligibility transitions;
- passive alert opens and duplicate-lock suppressions;
- passive evidence received after open alert;
- recommendation source/confidence/change rate;
- cleanup/retention job health.

Hard invariant alarms:

- any `unknown -> missed` transition;
- any passive event resolving an alert;
- any Guardian/external event becoming Ward evidence;
- any cross-account collector acceptance;
- both legacy and passive engines opening inactivity alerts;
- any prohibited raw field leaving a collector.

Operational degradation rules:

- an account evaluator or window-finalizer schedule gap greater than three minutes marks server protection Limited;
- a nominally healthy platform/contract version missing more than 5% of decision deadlines over a rolling 24 hours is removed from Ready and rollout stops;
- one subject failure must not abort processing for other accounts;
- scheduler, cleanup and notification jobs expose last success, last error and skipped-subject counts.

## Verification and Acceptance

### Deterministic contract cases

1. Evidence at `window_start` belongs to that window; evidence at `window_end` belongs to the next.
2. DST and timezone changes do not change UTC window duration.
3. A settings/roster change supersedes the partial window and starts counter zero at server `effective_at`.
4. Any qualified bound-device event produces `checked_in`.
5. All enrolled decision-grade collectors complete with no evidence produces `missed`.
6. Any incomplete enrolled collector with no positive evidence produces `unknown`.
7. No enrolled decision-grade collector produces Positive-only/Limited and `unknown`, never `missed`.
8. `missed -> unknown -> missed` leaves streak 1.
9. Exactly `N` chronologically consecutive misses creates one self-confirmation alert.
10. No later missed window duplicates an open alert.
11. Passive evidence after alert creation cannot resolve it.
12. Explicit resolution starts a new epoch/window at `resolved_at`.
13. Sleep permits window collection and miss accumulation but suppresses alert creation until canonical grace ends.
14. A sleep-time check-in resets the chain.
15. A sleep-time unknown terminates the chain.
16. Legacy threshold and dark-device rules cannot create passive-mode inactivity alerts.

### Trust and identity cases

1. One native/Tauri collector cannot be actively bound to two protected accounts.
2. Account switch revokes the old credential and local queue.
3. Guardian activity cannot create Ward evidence.
4. Identical retry is idempotent.
5. Same event ID/sequence with changed payload is rejected and audited.
6. Future timestamp over five minutes is rejected.
7. Clock discontinuity splits coverage and yields unknown for the gap.
8. Positive history inside seven days may correct to checked-in.
9. Late negative/coverage cannot create a miss.
10. Evidence older than seven days cannot affect derived state.

### Evidence cases

1. Android keyguard-hidden/foreground interaction qualifies; screen-on alone does not.
2. Android package names never leave the device.
3. Positive pedestrian steps/floors qualify; automotive-only motion does not.
4. Initial charging state does not qualify.
5. Confirmed stable connect/disconnect qualifies.
6. Callback flap/current charge/battery increase does not qualify.
7. Tauri keyboard/mouse input uses its reconstructed time.
8. PWA deliberate interaction qualifies; push/service-worker/page visibility alone does not.
9. Heartbeat, wake, notification acknowledgement and network success never check in.
10. Cross-source duplicates do not distort learning sessions.

### Learning cases

1. Unknown, superseded, outage, alert-response, Guardian, Shortcut and replay intervals do not train.
2. Sleep/post-wake intervals are unioned and subtracted.
3. Right-censored absence does not train.
4. Fewer than three episodes/days shows default 6-hour insufficient recommendation.
5. Top-end order statistic uses `B=1` and 30-day evidence-day count.
6. A single >150% exceptional gap cannot change `R`.
7. Two different-date gaps within the 1.25 ratio may change `R`.
8. Recommendation mapping uses `ceil(R/D)`.
9. Recommendation writes cannot mutate active settings, windows, streaks or alerts.
10. Changing `D` previews advice only.

### Privacy and ACL cases

1. Payload inspection finds no package name, URL, typed content, route, raw motion or Health record.
2. Authenticated users cannot directly read/write private ingest or coverage tables.
3. Subject reads own summaries only.
4. Guardian gets authorized summaries, not credentials/raw payloads.
5. Device removal revokes credentials and clears the local queue.
6. Retention jobs remove 35/90-day records and expose health.
7. Raw tables are absent from Realtime.

### Platform real-device gates

Android AAB:

- at least three physical devices spanning supported Android/major OEM restrictions;
- 20-minute, 2-hour and 6-hour settings;
- unlock/use, no-use, Doze, reboot, Usage Access denial/revocation, locked-after-reboot, network outage and OEM battery restriction;
- Play disclosure and data-safety payload inspection;
- at least 95% deadline completion while the contract claims healthy over seven consecutive days;
- zero false complete-coverage assertions.

iOS Native/TestFlight:

- at least three supported iPhone/OS combinations;
- 20-minute, 2-hour and 6-hour settings;
- foreground use, sedentary/no-motion, pedestrian motion, charging transition, Motion denial/revocation, suspension, force-quit, restart, network outage and silent-push delay/drop;
- exact-window pedometer result-bound verification;
- at least 95% deadline completion while the contract claims healthy over seven consecutive days;
- zero false complete-coverage assertions.

If the iOS gate fails, iOS Native remains positive-only/Limited. PWA cannot replace the failed gate.

Tauri:

- Windows and macOS physical-device tests;
- startup consent, five-minute leases, input/no-input, sleep/resume, exit, network outage, clock change and unsupported API;
- at least 95% deadline completion while healthy over seven consecutive days;
- zero browser/Tauri channel confusion and zero false complete coverage.

### Integrated rollout gates

- 14 days shadow with zero hard-invariant violation;
- no account receives alerts from both engines;
- shadow replay explains every checked-in/missed/unknown outcome by causal IDs;
- alert-time comparison includes `H`, collector grace and sleep delay;
- user migration flow and accessibility pass;
- rollback/kill switch tested without production mutation;
- independent non-author safety review has no blocker;
- production/deploy/release/Store authority obtained separately.

## Implementation Package Boundaries After Written Acceptance

1. Database contracts: engine mode, account contract version, monitoring epoch, windows, collector roster, evidence/coverage, causal snapshot, RLS and pgTAP.
2. Trust/ingest: device binding, credential revocation, idempotency, sequence, timestamp, correction and retention.
3. Android AAB collector and device tests.
4. iOS Native collector and TestFlight evidence.
5. Tauri collector and Windows/macOS evidence.
6. Account aggregation, sleep integration, alert idempotency and legacy-trigger retirement.
7. Advisory learner and provenance.
8. Settings/device/protection-health/migration UX and accessibility.
9. Shadow comparison, observability, rollback and integrated verification.

Each package receives a separate exact write set and TDD plan. Spec-complete isolated database/client packages are candidates for agy or V4 under locked hash-addressed orders. Codex owns semantic integration, cross-package review and final verification. Executors cannot choose missing product rules or subdelegate.

## Non-Scope

- Source or migration implementation in this design task.
- Production mutation, deployment, release or Store submission.
- Automatic setting changes.
- Passive automatic alert resolution.
- Identity/safety proof from device activity.
- Passive GPS/location collection.
- Cohort or AI-controlled live alert rules.
- Context-dependent active schedules beyond the existing user-configured sleep gate.
- Family Controls/DeviceActivity as a required core dependency.
- Linux decision-grade desktop protection.

## Authoritative References

- Human decisions in Codex Desktop on 2026-08-13 and written-completeness direction on 2026-08-14.
- `Projects/Keep Contact/Decisions.md` ADR-0037, ADR-0039 and ADR-0040.
- `Projects/Keep Contact/Business Logic/Sleep Window.md`.
- `Coordination/Threads/KC Native Collector Evidence Loss Claude to Codex Handoff 2026-08-13.md`.
- `android/PLAY-CONSTRAINTS.md`.
- [Android UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager.html).
- [Android WorkManager task scheduling](https://developer.android.com/develop/background-work/background-tasks/persistent).
- [Apple CMPedometer historical queries](https://developer.apple.com/documentation/coremotion/cmpedometer/querypedometerdata%28from%3Ato%3Awithhandler%3A%29).
- [Apple background strategy limits](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app).
- [Apple background push delivery limits](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).
- [Apple Family Controls distribution entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).
- [Apple App and Website Usage entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls.app-and-website-usage).
- [WebKit Web Push user-visible requirement](https://webkit.org/blog/16535/meet-declarative-web-push/).
- Microsoft `GetLastInputInfo` documentation.
