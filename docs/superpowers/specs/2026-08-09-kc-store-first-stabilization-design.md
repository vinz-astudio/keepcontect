# KC Store-First Stabilization Design

**Date:** 2026-08-09

**Status:** Human-approved design; implementation not yet authorized

**Scope:** Stabilization workflow, product authority boundaries, Store-readiness contract, and release gates

**Long-term platforms:** Tauri desktop, Google Play AAB, iOS Native

**Transitional channels:** Android APK, iOS PWA

## 1. Goal

Stabilize Keep Contact without interrupting the currently operating app, converge repository and production truth, repair safety/privacy defects, and make every future feature reviewable for Tauri, Google Play AAB, and iOS Native before it is implemented.

KC is complete only when a feature is functionally correct, produces truthful safety evidence, degrades honestly when capability is unavailable, remains compatible with the released client during rollout, builds on the formal target platforms, and has Store declarations that match its actual behavior.

## 2. Product invariant

KC is an ambient safety product, not a surveillance product and not a medical diagnosis system.

The governing invariant is:

> Healthy protection may be quiet. Missing protection must be visible. Missing evidence is never user activity, never normal behavior, and never proof of danger.

Consequences:

- Passive activity never resolves or trains an alert unless it is canonical activity from the protected user's own healthy collector.
- Guardian action is trusted external care evidence but never impersonates the Ward's own device activity.
- A permission denial, dead collector, device outage, app outage, or unsupported platform produces `Limited` or `Unknown`, not `Ready`.
- A technical outage never creates a safety alert by itself.
- Server, UI, notification copy, Store disclosure, and privacy policy must describe the same fact.

## 3. Operating model

### 3.1 Four controlled lanes

1. **Production lane** — the current app, database, and Edge services remain operational. Development does not use production as a speculative test environment.
2. **Stabilization integration lane** — one isolated source line reconciles local `main`, the Claude database worktree, remote `main`, production migration ledger, and deployed Edge versions.
3. **Executor worktrees** — one bounded worktree per approved repair package. Executors cannot merge, deploy, change product semantics, or expand their write set.
4. **Release candidate lane** — only reviewed packages enter the candidate. The candidate must pass the full platform and database matrix before any release request.

The normal flow is:

`locked requirement -> failing test -> minimal implementation -> package tests -> Manager semantic review -> integrated regression -> release candidate`

Production adds a separate gate:

`impact and compatibility statement -> roll-forward/rollback plan -> human approval -> deployment -> watch window -> Brain release truth`

### 3.2 Delegation

Codex remains Manager and owns product semantics, architecture, integration, verification, and completion.

V4 and agy are conditional Executors. They may be used only when all of the following are true:

- the requirement is fully decided;
- the exact write set is isolated;
- interfaces and test commands are locked;
- the package is mechanically verifiable;
- delegation has positive time/token economics;
- a complete hash-addressed order is installed through the Brain runtime;
- the Executor cannot subdelegate, merge, deploy, or fill a product gap.

Small, coupled, exploratory, schema-authority, release, and product-decision work remains Manager-direct.

## 4. Stabilization packages

### S0 — Truth convergence

**Outcome:** one explainable source line without changing online behavior.

- Reconcile local `main`, remote `main`, the Claude database worktree, production migration ledger, and deployed Edge versions.
- Preserve the production database baseline established by ADR-0038.
- Bring every live database/Edge repair back into canonical source.
- Classify stale Active Work, Known Issues, status, iOS, Play, alert, notification, Guardian, and Routine notes.
- Correct stale policy claims instead of allowing agents to choose between conflicting notes.

**Gate:** repository commits, migration ledger, Edge versions, release artifacts, and Brain truth can all be traced to exact states. No production mutation is part of S0.

### S1 — Safety evidence and privacy

**Outcome:** the app cannot manufacture activity, hide lost protection, or expose a production preview identity.

- Remove or development-gate the visible Fast Preview login and hard-coded shared credentials.
- Restore and test Android activity emission throttling.
- minimize Android receiver exposure and prove which system events can reach it.
- Replace false auto-resolution copy such as “activity resumed” when the real cause is sleep/post-wake grace.
- Make emergency GPS consent device-local and purpose-limited.
- Give protection outages a truthful incident lifecycle.

**Gate:** TypeScript, unit tests, Android native tests/build, security scenarios, and copy/state contract tests pass.

### S2 — Database and emergency-data integrity

**Outcome:** no unexplained database red tests and no crisis UI backed by serialized JSON in legacy scalar fields.

- Separate obsolete pgTAP expectations from current defects.
- Repair real ACL/grant/RLS issues, including internal-table access and GM mute visibility.
- Replace emergency-contact and address JSON serialization with normalized records and server-enforced projections.
- Maintain backward-compatible reads for released 0.5.25 clients during migration.
- Audit every emergency-data read.

**Gate:** the current database suite has no unexplained failure; role tests prove access boundaries; a real alert projection renders usable contacts and addresses.

### S3 — Product-rule unification

**Outcome:** UI, RPC, notifications, Brain, and tests enforce the same accepted rules.

- Concern eligibility and effects.
- Healthy-coverage admission for routine learning.
- Protection-outage presentation and subscriptions.
- Ordinary member, Special Attention, Guardian, and Ward authority hierarchy.
- Emergency-data disclosure stages.
- Platform capability and Store-review fallbacks.

**Gate:** each rule has server enforcement, frontend behavior, automated contract tests, and one canonical Brain owner.

### S4 — Release verification

**Outcome:** a coherent, review-ready release candidate.

- Run the complete Web, database, Android, notification, and cross-account test matrix.
- Validate Android AAB on physical devices, including denied permissions, OEM background limits, reboot, force-stop, FCM, WorkManager, and notification channels.
- Build iOS Native in the macOS CI path, verify signing/entitlements, and validate on a physical TestFlight device.
- Build and verify signed Tauri artifacts and native notification/collector behavior.
- Update all version authorities together.
- Prepare Store disclosures, review notes, screenshots/video, Data Safety/App Privacy declarations, account deletion, and rollback/watch procedures.

**Gate:** no unexplained red test, no unverified required entitlement, no claim based only on an emulator or local build, and no mismatch between Store disclosure and runtime behavior.

## 5. Accepted product contracts

### 5.1 Concern

- Concern is available only when the target already has an active alert.
- Concern cannot create a new alert.
- Only an authorized same-Circle relationship may send it.
- Concern is not activity evidence and does not resolve an alert.
- Concern strengthens the need for the target's explicit self response and records delivery/acknowledgement separately from contact claims or Guardian external confirmation.
- The server enforces eligibility; hiding a button is not authorization.

### 5.2 Healthy-coverage learning

ADR-0037 is revised only at its evidence-admission boundary. The learned value remains the account's own observed normal silence upper bound with no universal floor, ceiling, preset, or cohort template.

A silence interval is eligible to train the normal upper bound only when:

- one identified native collector has continuous, server-received healthy coverage for the interval;
- the device and KC collector remained operational;
- the interval has no collector gap, permission loss, outage, unsupported runtime, or uncertain provenance;
- it is not an alert, known exceptional period, replayed history without continuous proof, ordinary browser/PWA focus event, Guardian action, Shortcut action, or manual event masquerading as passive coverage.

An unusually long silence changes the upper bound only after at least two independent, comparable, coverage-valid normal episodes. A single extreme episode cannot redefine normal.

When coverage is missing or uncertain, the stable result is `Unknown/insufficient evidence`; it does not train, extend sleep, refresh liveness, or prove danger.

### 5.3 Protection health and outage incidents

- Protection health is evaluated from server-visible platform coverage, not solely by a worker judging its own wake-up punctuality.
- A platform-specific health policy converts repeated missed expected coverage into one outage incident.
- The protected user receives one clear prompt per incident and a persistent `Limited` status with a direct repair path.
- Dismissing the prompt does not restore `Ready`.
- Recovery requires new continuous healthy evidence; a button tap or app foreground event alone is insufficient.
- Learning stops for the unhealthy interval.
- A technical outage never becomes an alert about the person's safety.

### 5.4 Ordinary members and Special Attention

- Ordinary Circle members can see `Ready/Limited/Unknown` when they inspect the member list but receive no protection-outage push by default.
- An ordinary member may privately mark another member as **Special Attention**.
- The control is default-off and explains: “Notify me if this person's KC protection remains interrupted.”
- Special Attention is a private notification subscription. It grants no additional data, emergency access, Guardian action, alert authority, or tracking capability.
- After the target's own outage prompt and an additional platform health grace period, one technical notification may be sent to each active Special Attention subscriber.
- Copy states that device/App coverage is interrupted and is not proof the person is in danger.
- Notifications are deduplicated per outage incident and stop after verified recovery.

### 5.5 Guardian and Ward

Guardian -> Ward is KC's highest, most comprehensive care relationship. It is established explicitly, remains visible and revocable, and is not equivalent to ordinary Circle membership or Special Attention.

An active Guardian has ongoing access to care-relevant Ward information and functions:

- protection readiness, device coverage, outage reasons, and recovery state;
- recent activity, routine evidence/limits, current and historical alerts;
- complete stored emergency contacts and addresses;
- all safety and protection-outage notifications;
- Ward check-in task creation, editing, and removal;
- Concern, contact coordination, and externally confirmed-safe recording;
- a dedicated Ward care surface with auditable actions.

The following are non-delegable even to a Guardian:

- generating the Ward's own passive activity evidence;
- completing the Ward's explicit unlock pattern;
- changing credentials, identity, encryption secrets, or deleting the Ward account;
- granting device permissions, device-local GPS consent, biometric approval, or OS authorization;
- converting external confirmation into learned personal behavior.

Guardian external confirmation may coordinate or temporarily suppress duplicate outward escalation under the existing bounded state machine, but it does not reset the Ward's effective silence, become a behavior ping, train Routine, or permanently replace self confirmation.

### 5.6 Emergency information

Emergency contacts, manual addresses, and live device location are separate data classes.

- Contacts are normalized records. When at least one contact exists, one may be designated Primary.
- Manual addresses are normalized labeled records such as Home or Office; addresses do not have a Primary flag.
- A Guardian has ongoing access after the explicit Guardian relationship is active.
- Ordinary Circle members receive full emergency information only during the Group stage of the target's active alert.
- Community responders receive only the minimum fields necessary for the active rescue path.
- Alert-scoped ordinary/community access ends when the alert ends.
- Server authorization and audit logging enforce access; client-side hiding is insufficient.
- Stored addresses never masquerade as current GPS.
- Live GPS is device-local, consented, purpose-limited, timestamped, accuracy-labeled, and associated with its reporting device.

### 5.7 Resolution truth

- User activity is not an automatic alert resolution mechanism.
- Explicit self unlock is required except for separately accepted sleep/post-wake grace classification.
- Every notification states the actual resolution reason.
- Sleep-grace resolution must never be described as observed activity.
- Guardian confirmation, Concern, technical coverage recovery, and notification acknowledgement remain distinct events.

## 6. Store-first platform contract

### 6.1 Common rules

- Platform UI shares product semantics, not unsupported capability claims.
- A denied managed entitlement or permission must have a tested fallback and a visible capability state.
- A Store-reviewed capability cannot be the sole path to KC's basic utility.
- Account deletion is available inside the app.
- Privacy policy, consent UI, retention/deletion behavior, Store declarations, and runtime telemetry use the same data-purpose vocabulary.

### 6.2 Android / Google Play AAB

- The AAB and APK use the same code and behavior; APK success alone is not acceptance.
- `specialUse` foreground service is optional enhancement, declared and demonstrated when used, not a hidden prerequisite.
- Full-screen intent is not required for the core alert path.
- Usage Access, notification, activity recognition, and location are requested only after prominent purpose disclosure.
- Missing permissions produce `Limited`, not silent pretend-success.
- The AAB gate includes Play Console declarations, Data Safety, account deletion, review video/screenshots, target SDK behavior, and physical Android 14+ verification.

Official references:

- https://support.google.com/googleplay/android-developer/answer/13392821
- https://support.google.com/googleplay/android-developer/answer/10144311

### 6.3 iOS Native / App Store

- iOS Native must provide meaningful native utility beyond a repackaged website.
- DeviceActivity is an optional managed-capability path. Family Controls distribution approval is required for the app and every Screen Time extension before TestFlight/App Store distribution.
- APNs background notifications are low-priority and not guaranteed; they cannot independently prove user activity or healthy coverage.
- External TestFlight is reviewable beta distribution, not a review bypass.
- Native notification actions, secure session persistence, device capability state, emergency flow, and account deletion must function without relying on the iOS PWA.
- The iOS design must pass without background location unless a later separately accepted requirement and review case justifies it.

Official references:

- https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- https://developer.apple.com/app-store/review/guidelines/

### 6.4 Tauri desktop

- Tauri is a formal desktop product, not merely the web page in WebView2.
- Native idle/coverage collection, notification/tray behavior, startup consent, installer signing, updater signing, secret handling, and uninstall behavior are independently verified.
- Background/startup behavior is user-consented and visible in settings.
- A Tauri collector must identify itself and provide server-verifiable coverage; normal browser activity cannot claim the same authority.
- Windows and Linux packaging are tracked separately where platform behavior differs.

## 7. Compatibility and deployment

- Current production and released 0.5.25 clients remain operational during stabilization.
- New server contracts are additive or dual-read/dual-write during the compatibility window.
- Old clients never receive a response shape that makes them crash or reinterpret unknown as safe.
- Database changes use append-only migrations and `supabase db push` only.
- Database rollback is normally a narrow forward repair; destructive schema rollback is not assumed.
- Edge/Web retains a known-good deploy target.
- Binary releases remain immutable; server compatibility continues until the adopted client floor is explicitly raised.
- Every production action requires a separate human checkpoint with exact scope and recovery procedure.

## 8. Verification matrix

| Area | Required evidence |
|---|---|
| Source convergence | Git graph, commit inventory, migration ledger, deployed function versions, artifact/version inventory |
| Web/client | TypeScript, unit/integration tests, production build, truthful loading/empty/limited/error states |
| Database | clean pgTAP classification, real-role ACL/RLS tests, migration dry run/replay, function contract checks |
| Android | native unit tests, lint/build/AAB, manifest/security tests, physical permission/outage/FCM/WorkManager flows |
| iOS Native | macOS CI compile/sign, entitlement inspection, TestFlight device flows, denied-capability behavior, APNs limitations |
| Tauri | native build/signing, installer launch, idle collector, notifications/tray, startup consent, updater behavior |
| Crisis flow | self -> Group -> Community, Concern, Guardian external confirm, emergency projection, explicit unlock |
| Store | privacy/data declarations, account deletion, review notes, demo media, runtime-copy consistency |

No unexplained red test is releaseable. Emulator/build evidence does not substitute for a required physical-device or Store-capability check.

## 9. Known truth conflicts S0 must resolve

- Production DB/Edge is ahead of canonical repository source.
- Local `main`, remote `main`, and the Claude database worktree are separate lines.
- ADR-0030's iOS-PWA-only target is superseded by this accepted iOS Native Store-first target.
- ADR-0037's admission of unproven old intervals is revised by the healthy-coverage requirement above.
- `Guardian Confirm.md` still says Guardian confirmation writes a behavior ping and resets silence; that is obsolete.
- `Google Play Store Compliance.md` retains an Accessibility route rejected by later decisions.
- `iOS Native TestFlight Pipeline.md` treats DeviceActivity approval, silent APNs delivery, and TestFlight review too optimistically.
- `Alert System.md`, `Behavior Pings.md`, `Notification Flow.md`, current status, and Known Issues contain stale runtime claims.

S0 updates canonical truth without rewriting historical evidence.

## 10. Completion criteria

The stabilization design is satisfied when:

1. one canonical integrated source line explains production and release state;
2. P0 safety-evidence, authentication, privacy, emergency-data, and resolution-copy defects are fixed;
3. database failures are either repaired or intentionally rewritten as obsolete expectations, with no unexplained red result;
4. accepted product authority contracts are enforced by server and client tests;
5. Tauri, AAB, and iOS Native candidates pass their platform gates;
6. Store disclosures match actual behavior and degraded paths;
7. current users remain operational throughout the rollout;
8. production deployment and release occur only after separate human approval;
9. Brain truth, source, artifacts, and production state agree at handoff.

## 11. Non-goals of this design task

- No source implementation, migration, deployment, release, account, permission, or production change.
- No promise that Apple or Google will approve a managed capability; the design must survive denial.
- No attempt to make APK or iOS PWA the long-term architecture authority.
- No use of V4/agy until an implementation package has a locked order and positive delegation economics.
