# Keep Contact Passive Check-In System Design

## Metadata

| Field | Value |
|---|---|
| ID | KC-PASSIVE-CHECKIN-SPEC-001 |
| Status | Proposed; conceptual design approved 2026-08-13, written human review pending |
| Change class | Product-UX / M3 |
| Proposed decision | ADR-0041 |
| Replaces if accepted | The current threshold-controlled collection and alert-triggering direction in ADR-0037 and ADR-0040 D2; preserves ADR-0039 alert resolution and protection-health invariants and ADR-0040 cross-platform normalization |
| Implementation authority | None |

## Decision Summary

Keep Contact becomes a **passive check-in system**. Ordinary use or carriage of any signed-in personal device can produce a qualified check-in for the account. The user directly controls:

1. a collection interval `D`, freely adjustable from 20 minutes through 6 hours; and
2. a positive consecutive-miss count `N`.

The nominal time before the existing self-confirmation alert begins is `H = D × N`. The product always displays `H` in plain language.

Learning remains, but its authority changes. It continuously estimates the user's usual upper silence reference `R` and converts it into **recommendations only**. It never changes active `D` or `N` automatically. The user may accept, ignore, or override every recommendation.

The existing alert funnel remains unchanged:

```text
consecutive qualified misses
  -> explicit self confirmation
  -> group escalation if the user does not respond
  -> community escalation under the existing rules
```

Passive activity never resolves an open alert.

## Root Requirement Trace

| Field | Decision / evidence |
|---|---|
| Work type | Product design delivery rooted in a verified collector/learner reliability defect |
| Trace status | Validated |
| Source | Human decisions in Codex Desktop on 2026-08-13; ADR-0039; ADR-0040; `Coordination/Threads/KC Native Collector Evidence Loss Claude to Codex Handoff 2026-08-13.md`; current Android, iOS, Tauri and Supabase source |
| Root requirement | A user receives understandable, privacy-limited protection from ordinary use or carriage of any signed-in personal device, while retaining final control over protection sensitivity. |
| Invariant | Every account window is `checked_in`, `missed`, or `unknown`; only complete observed misses advance the user's counter; any qualified evidence from any signed-in device checks in the account; learning updates recommendations only; passive evidence never resolves an alert. |
| Observed gap | Native evidence is received and stored but discarded from liveness, while collector blindness is learned as normal silence. Production has produced opaque thresholds as loose as 99.6 hours. |
| Causal root | Platform evidence is not consistently normalized; user activity and collector coverage are conflated; missing evidence enters learning as silence; the resulting threshold silently controls protection. |
| Cause-owning layer | Multi-layer implementation after this design is accepted: platform collection, normalized contract, database window state, advisory learner and settings UX. |
| Root verification | Cross-platform contract tests plus real-device window-history, outage, permission, restart, force-stop and multi-device tests. |
| User path | A user chooses `D` and `N`, receives check-ins from any signed-in device, sees truthful `unknown/Limited` states, and enters the unchanged alert funnel only after `N` qualified misses. |

## Product Meaning

KC does not claim that passive evidence proves a person is safe. It establishes that there is sufficiently credible recent activity associated with the person and one of their personal devices, so there is not yet a reason to start the explicit confirmation funnel.

The account is the protected subject. Devices are equal evidence providers, not independent protected subjects and not primary/secondary authorities.

## User-Controlled Settings

### Collection interval `D`

- The UI provides a continuous duration control from 20 minutes through 6 hours, rather than a list of fixed presets.
- The stored value is an exact duration supported by the implementation; the UI displays the exact selected duration.
- Shorter intervals mean finer observation, more collection work and potentially greater platform/battery pressure.
- Platform inability to honor a selected interval is exposed as `Limited`; it is never hidden by manufacturing `missed` results.

### Consecutive-miss count `N`

- The user may enter any positive integer representable by the settings contract.
- The product does not impose a semantic preset or automatically chosen active value.
- The UI validates that `N >= 1` and shows the resulting nominal time `H = D × N`.

### Initial and learned recommendations

- With insufficient personal evidence, the initial recommendation is `D = 2 hours`, `N = 3`, therefore `H = 6 hours`.
- A recommendation is visually distinct from the active setting.
- The user can apply a recommendation explicitly, ignore it, or enter another value.
- Changing `D` updates the displayed recommended `N` without changing the active `N`.
- Changing `N` immediately updates the displayed active `H`.
- Changing either active setting starts a new settings version at the next account window. The incomplete old window becomes `superseded`, not `missed`, and the old consecutive-miss streak resets so different contracts are never mixed.

## Account Window State Machine

Each settings version produces consecutive half-open account windows:

```text
[window_start, window_end)
```

Every window resolves to one public domain state:

| State | Meaning | Counter effect |
|---|---|---|
| `checked_in` | At least one signed-in device produced qualified evidence whose real occurrence time lies in the window. | Reset consecutive misses to zero. |
| `missed` | No qualified evidence exists and every device participating in passive protection provided complete coverage for the window. | Increment consecutive misses by one. |
| `unknown` | No qualified evidence exists and at least one participating device could not prove complete coverage, or no passive-protection device was enabled. | Do not increment and do not reset; show technical `Limited`. |

`checked_in` dominates all other device results. No device hierarchy exists.

A platform collector may run late and reconstruct an earlier window from system-maintained history. Evidence is assigned by its true `observed_at`, never by upload time. A window remains pending until its participating collectors report or their capability-specific reporting deadline expires. Expiry produces `unknown`, never `missed`.

Late evidence may revise a historical `unknown` or `missed` to `checked_in` with an audit record and may correct future derived streak state. It cannot silently resolve or retract an alert that has already opened; the existing explicit-resolution contract governs that alert.

## Multi-Device Aggregation

### Equal contribution

- Qualified evidence from any signed-in device checks in the account.
- Android use, iOS personal motion, Tauri input, a captured charge transition, KC foreground use and a qualified Shortcut event have the same account-level effect after qualification.
- A device need not participate in background protection to contribute a positive check-in.

### Passive-protection participation

- Only a device on which the user explicitly enables passive protection participates in the completeness calculation for `missed` versus `unknown`.
- A normal browser, temporary login or PWA without a background collector can contribute positive evidence but does not become a required coverage source merely by signing in.
- A participating device is never silently removed because it stopped reporting. It remains a visible `Limited` cause until the user repairs it, signs out, disables passive protection on it, or removes it from the account.
- Explicit disable/removal is versioned and affects future windows; it does not rewrite completed historical windows.

### Account aggregation function

```text
if any signed-in device has qualified evidence in the window:
    checked_in
else if at least one passive-protection device is enrolled
        and every enrolled device proves complete window coverage
        and every enrolled device reports no qualified evidence:
    missed
else:
    unknown
```

## Evidence Qualification

Qualification happens in the platform collection layer that understands the signal. The server consumes a normalized assertion and must not infer platform semantics from `source`, `kind`, operating-system names or client channels.

### Evidence that can complete a passive check-in

| Normalized class | Examples | Qualification rule |
|---|---|---|
| `direct_device_use` | Android unlock/App interaction; Tauri keyboard or mouse input; KC foreground/interaction; user-configured Shortcut App-open event | A timestamped operating-system or foreground event tied to the signed-in personal device. App names, URLs and input content are not uploaded. |
| `personal_device_motion` | iOS or Android historical steps or floors | Positive steps or floors within the exact window, with automotive activity excluded. Raw motion series and routes remain on-device. |
| `power_transition` | Cable connected/disconnected; device placed on or removed from a wireless charger | A timestamped power-source transition actually observed by the collector. Current charging state, charge completion or battery-level difference is insufficient. |
| `explicit_self_activity` | An ordinary user action in KC before an alert opens | The signed-in user deliberately interacts with KC. Alert-response actions remain separately classified and excluded from passive learning. |

The qualification policy is versioned. Adding a signal requires a stated causal relationship to recent user-associated activity, a privacy assessment, platform-review evidence and false-positive tests.

### Signals that cannot complete a check-in alone

- battery level rising or falling;
- continuously charging state;
- other audio playing;
- raw motion variance without qualified personal motion;
- push delivery, background wake or collector heartbeat;
- network activity, scheduled job execution or coverage lease;
- automotive movement;
- Guardian/external confirmation;
- replay upload time.

These signals may support collector health, qualification or diagnostics, but they cannot become account activity by themselves.

## Coverage Contract

Activity and coverage are separate facts:

- activity asks whether qualified user-associated evidence occurred;
- coverage asks whether a collector was capable of observing and reconstructing the whole window under its declared contract.

A complete device coverage assertion includes the device, collector contract/version, exact interval, permissions/capabilities, history-query result, real observation time and idempotent event identity. A heartbeat proves only that the collector ran; it does not check in the user.

Permission loss, force-stop behavior, background suspension, device shutdown, unsupported platform behavior, failed history access, unresolved upload failure or missing expected collector reports make coverage incomplete. They therefore produce account `unknown` unless another device checks in.

## Platform Design

### Android Native / AAB

- Use `UsageStatsManager` history to obtain real activity timestamps for each window after the user grants Usage Access.
- Preserve the existing Play-facing prominent disclosure.
- Use WorkManager and existing server wake paths as execution opportunities; scheduling delay is tolerated by historical reconstruction and is never itself a miss.
- Capture real power connected/disconnected events with occurrence timestamps.
- Upload normalized evidence only; do not upload package names or per-App histories.
- APK and AAB use the same collector and acceptance standard.

### iOS Native

- KC foreground/interaction is direct-use evidence.
- Query Core Motion historical steps/floors for the exact window; positive non-automotive personal motion can check in the account.
- Capture real power-state transitions when iOS actually delivers them; a later battery-level comparison cannot invent an event timestamp.
- Silent APNs, HealthKit/Core Motion wakes and foreground launches are execution opportunities and coverage evidence, not check-ins by themselves.
- Screen Time/DeviceActivity remains an optional future enhancement, not a dependency for the core product or its App Store acceptance.
- Motion/Health permission requests are one-time, purpose-specific, optional where the platform permits, and accurately reflected in readiness. Raw health/motion data stays on-device.

### Tauri desktop

- Windows and macOS use native last-input/idle APIs to reconstruct recent keyboard/mouse activity.
- Capture timestamped power-source transitions when supported.
- Passive protection requires explicit user consent for startup/background operation.
- App exit, unsupported idle APIs or failed startup produce incomplete coverage, not a miss.
- Linux remains unsupported for full passive protection until a native idle collector passes the same contract and real-device tests; ordinary foreground use may still contribute positive check-ins.

### PWA and Shortcuts

- A PWA may contribute its own foreground/interaction evidence.
- iOS Web Push cannot be used as silent periodic collection because WebKit requires user-visible notifications.
- A user-configured Shortcut may contribute a timestamped qualified event, but setup is optional and it is not a complete passive-protection collector.
- Closing a browser/PWA never creates `missed` or blocks a native collector's coverage calculation.

## Advisory Learning

### Authority boundary

The learner writes only recommendation state. It has no write path to active `D`, active `N`, alert counters or alert decisions. Applying a recommendation requires an explicit authenticated user action and creates a new settings version.

### Learned reference

The learner estimates the account's usual upper silence reference `R` from qualified account check-in gaps. The accepted ADR-0037 top-end order-statistic principle remains the initial estimator, but it operates only on qualified episodes and its result is advisory rather than authoritative.

New-system training eligibility requires:

- both bounding check-ins are qualified user-associated evidence;
- every intervening account window is `checked_in` or `missed` with complete coverage;
- no `unknown` or superseded window intersects the episode;
- the episode is not created by replay time, Guardian/external confirmation, technical recovery, notification acknowledgement or an alert-response action;
- real occurrence timestamps, not receipt timestamps, define the gap.

`unknown` terminates an episode. Collector blindness can never lengthen `R`.

### Initial historical seed

- Existing learned threshold numbers are not imported directly.
- The seed is recomputed from historical raw activity evidence after excluding known outage, replay and non-user sources.
- Historical intervals with verified coverage may contribute normally.
- Historical evidence without enough coverage may be shown only as a low-confidence advisory observation; it cannot replace the default recommendation or affect active settings.
- If a trustworthy seed cannot be established, the system uses the transparent default recommendation of 2 hours × 3 misses.

### Recommendation mapping

For the active or previewed interval `D`:

```text
N_suggested = max(1, ceil(R / D))
H_suggested = D × N_suggested
```

Example for `R = 6 hours`:

| `D` | `N_suggested` | `H_suggested` |
|---:|---:|---:|
| 20 minutes | 18 | 6 hours |
| 1 hour | 6 | 6 hours |
| 2 hours | 3 | 6 hours |
| 3 hours | 2 | 6 hours |
| 6 hours | 1 | 6 hours |

The UI shows the recommendation's evidence period, qualified episode count, confidence and last update. A changed recommendation never changes the active settings or generates a notification that implies settings already changed.

Contextual learning may later produce separate advisory references for sleep, daytime, workdays or weekends. It requires a separately reviewed UX for user-controlled schedules and does not silently introduce context-dependent active alert rules.

## Alert and Protection-Health Integration

- `checked_in` resets the consecutive-miss streak only while no alert is open.
- `missed` advances the streak only after the window is complete.
- `unknown` pauses the streak and makes protection visibly `Limited`; it neither advances nor resets the streak.
- When the streak reaches active `N`, the existing self-confirmation stage opens.
- Group/community escalation, explicit self unlock, Guardian/external confirmation and GM authority retain their existing accepted semantics.
- Passive evidence after alert creation updates activity history but never resolves the alert.
- Technical coverage outage never becomes a human-safety alert.

## Privacy and Store-Review Contract

- Collect the minimum information necessary to produce normalized evidence.
- Do not upload App/package names, URLs, typed content, raw input, raw motion samples, routes, complete HealthKit records or browsing history.
- Upload timestamps, normalized evidence class, qualification-policy version, device/client identity, account-window identity, coverage interval and the minimum qualification facts required for audit.
- Permissions are requested once with platform-specific purpose text and a repair/disable path.
- Background collection is quiet where the platform allows it; no permanent visible notification or special reviewed capability is a mandatory core dependency.
- A capability that is unavailable, denied or unreliable degrades to incomplete coverage and visible `Limited`, not fabricated readiness.

## UX Requirements

- The settings surface uses a duration slider covering the full 20-minute-to-6-hour range and a positive-integer control for consecutive misses.
- It always displays the active nominal alert time in ordinary language.
- It separately displays the current learned recommendation, evidence/confidence and an explicit Apply action.
- It explains that shorter intervals increase collection frequency and may not be fully supported on every device.
- It displays account-level protection state and per-device collector problems without labeling devices primary or secondary.
- It allows explicit enable, disable, sign-out and removal of a passive-protection device.
- It never describes passive evidence as proof that a person is safe.

## Compatibility and Migration Direction

- The uncommitted iOS device-sample promotion migration and test remain candidate evidence for the new qualification layer; they are not authorized for deployment and must be rebased onto the accepted window/evidence contract.
- Android `queryLastActiveTime` becomes a real timestamped evidence producer rather than a trigger for a `now` ping.
- Tauri native idle data becomes normalized evidence with its true reconstructed activity time.
- The withdrawn coverage-learning migration remains withdrawn. It is not restored under a new name.
- Existing polluted bounds may be analyzed for migration evidence but cannot control active settings or seed recommendations directly.
- Existing user alert escalation and explicit resolution paths remain in place.

## Acceptance and Verification

### Contract tests

- Any qualified evidence from any signed-in device produces account `checked_in`.
- All enrolled protection devices complete with no evidence produces `missed`.
- Any incomplete enrolled collector with no positive evidence produces `unknown`.
- A browser/PWA login without passive protection does not block or create `missed`.
- `unknown` does not increment or reset the streak.
- A settings change supersedes the partial window and resets the old streak.
- `N` complete consecutive misses opens only the existing self-confirmation stage.
- Passive evidence never resolves an open alert.
- A stale enrolled collector is not silently removed.
- Recommendation writes cannot mutate active settings or alert counters.

### Evidence tests

- Android historical use is assigned to its true window and uploads no package name.
- Tauri recent input is assigned to its true window.
- Positive non-automotive steps/floors qualify; automotive motion does not.
- A captured power connect/disconnect qualifies; current charging state and battery increase do not.
- Push wake, heartbeat, audio playback and raw motion variance cannot check in alone.
- Offline/late upload uses `observed_at`, remains idempotent and cannot resolve an alert.

### Failure-path tests

- permission denial and revocation;
- App force-stop/force-quit;
- operating-system background delay;
- network outage and replay;
- device restart and clock change;
- explicit device disable/removal;
- multiple devices crossing the same window;
- missing collector history;
- delayed evidence after alert creation.

### Platform release gates

- Android APK/AAB real-device soak at representative intervals, including Doze and OEM battery restrictions.
- iOS Native real-device/TestFlight soak covering foreground, Core Motion history, power transitions, silent wake limitations and force-quit behavior.
- Tauri Windows/macOS startup, background, idle/input, sleep/resume and exit tests.
- Privacy payload inspection proving prohibited raw data is absent.
- Store declarations and permission copy match actual collection.
- No production deployment, package release or Store submission is authorized by this design.

## Implementation Package Boundaries After Written Approval

1. Normalized evidence, window, settings-version and advisory-learning database contracts plus pgTAP.
2. Android timestamped historical-use and power-transition collector plus unit/device tests.
3. iOS Native historical-motion, foreground, captured power-transition and coverage collector plus TestFlight verification.
4. Tauri timestamped idle/input and power-transition collector plus Windows/macOS tests.
5. Settings and recommendation UX plus account/device protection-health presentation.
6. Integrated local replay, platform soak, privacy inspection and one release decision.

Each package receives a separate exact write set and TDD cycle. Database and isolated mechanical packages are candidates for V4 and agy only after their locked orders are complete. Codex retains semantic integration and acceptance. Production, deployment, packaging and release remain separate human-authority gates.

## Non-Scope

- Implementing source code or migrations in this design task.
- Deploying to Supabase or any hosted service.
- Building or releasing Android, iOS, Tauri or Web artifacts.
- Automatically changing active user settings.
- Automatically resolving alerts from passive evidence.
- Making Screen Time/DeviceActivity entitlement a core dependency.
- Adding automatic contextual schedules without separate human-reviewed UX.

## Authoritative References

- Human design decisions in the Codex Desktop conversation on 2026-08-13.
- `Projects/Keep Contact/Decisions.md` ADR-0037, ADR-0039 and ADR-0040.
- `Coordination/Threads/KC Native Collector Evidence Loss Claude to Codex Handoff 2026-08-13.md`.
- `android/PLAY-CONSTRAINTS.md`.
- Android `UsageStatsManager` and WorkManager official documentation.
- Apple Core Motion, Family Controls, BackgroundTasks, App Review and WebKit Web Push official documentation.
- Microsoft `GetLastInputInfo` official documentation.
