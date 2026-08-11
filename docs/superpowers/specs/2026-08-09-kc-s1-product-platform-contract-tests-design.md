# KC S1 Product and Platform Contract Tests Design

**Status:** Human-selected approach A on 2026-08-09
**Base:** `8f2144d31c08b464892dd174b13f161258cab648`
**Authority:** ADR-0039
**Purpose:** Freeze executable product/platform truth before any behavioral repair.

## 1. Outcome

S1 adds tests and test infrastructure only. It does not repair product behavior.

The result is a deterministic contract baseline that says, per assertion:

- `PASS`: S0 already matches ADR-0039;
- `RED`: product/runtime is missing or contradicts ADR-0039;
- `BLOCKED`: the platform harness cannot yet execute the contract.

S1 is complete when each required contract has a stable result and a routed follow-up. The whole suite is not required to be green. Compile errors, missing fixtures, linked-project access, or ambiguous assertions are not acceptable RED evidence.

## 2. Hard Boundaries

Allowed:

- new test files;
- test-only fixtures/helpers;
- a local S1 runner/report generator;
- S1 design, plan, and baseline reports.

Forbidden:

- production TypeScript, SQL functions, migrations, Edge Functions, Android/iOS/Tauri runtime code;
- edits to existing tests merely to change expected results;
- remote or linked Supabase execution;
- push, deploy, release, tag, version bump, artifact rebuild, account/permission change;
- hiding an ADR-0039 contradiction behind skip, snapshot update, weaker assertion, or expected-failure middleware.

Old migrations remain byte-for-byte unchanged. New S1 pgTAP files inspect S0 runtime truth; they do not install fixes.

## 3. Contract Packs

### 3.1 Alert and activity separation

Executable DB contracts prove:

- passive activity never creates, resolves, pauses, or acknowledges an alert;
- passive activity may update activity/coverage evidence only;
- Concern requires a pre-existing active alert and cannot create one;
- Concern is not activity, self confirmation, Guardian confirmation, or resolution;
- sleep/post-wake automatic clearance retains an explicit non-activity reason;
- user self response, caregiver/Guardian confirmation, GM action, technical recovery, and notification acknowledgement remain distinct provenance.

Existing `activity_never_answers_an_alert_in_cron.sql` is reused as evidence. S1 adds only missing contract cases.

### 3.2 Healthy learning and protection health

Executable DB contracts prove:

- only continuous, server-verifiable, trusted native coverage can qualify a silent interval for learning;
- outage, unknown, browser/PWA focus, replay, manual, Shortcut, Guardian, alert, and known exception intervals do not train normal silence;
- one exceptional long gap cannot move the learned upper bound;
- at least two independent, comparable, coverage-valid samples on different dates are required after a long gap;
- outage is technical health state, never an automatic personal-danger alert;
- recovery requires new continuous healthy coverage; dismissing a prompt cannot restore `Ready`.

Where S0 lacks a public health-state contract, tests assert the missing schema/RPC explicitly through catalog checks. They must fail as assertions, not abort the file.

### 3.3 Ordinary member, Special Attention, Guardian/Ward

Executable authorization contracts prove:

- ordinary members can read the permitted member-list health projection but receive no outage push by default;
- Special Attention defaults off, is private to the subscriber, adds notification eligibility only, and grants no extra data/action authority;
- only an active relationship can subscribe; revoked/inactive relationships cannot receive future outage notifications;
- Guardian/Ward is explicit, visible, revocable, and the broadest care relationship;
- Guardian can access ADR-0039 care surfaces, but cannot write Ward activity, self response, identity, credentials, device consent, unlock, account deletion, or learning evidence;
- Guardian external confirmation has caregiver provenance and never inserts Ward `manual_checkin` behavior evidence.

Missing tables/RPCs are stable RED contracts routed to S3. Existing over-broad ACL findings remain S2 defects and are not repaired here.

### 3.4 Platform honesty: AAB, Tauri, iOS Native

Executable repository contracts inspect actual manifests/config/source boundaries:

- target products are AAB, Tauri, and iOS Native; APK/iOS PWA are transitional and cannot satisfy native capability gates;
- Android store build cannot rely on an undisclosed or ineligible AccessibilityService path;
- notification denial, background restriction, unsupported collector, force-stop-equivalent state, and stale coverage map to `Limited` or `Unknown`, never `Ready`;
- iOS silent push is best-effort and cannot be the sole safety/coverage proof;
- DeviceActivity/Family Controls capability is gated by real entitlement/configuration, not documentation claims;
- CoreMotion activity cannot resolve an alert or prove identity;
- Tauri requires its own notification/background/update capability evidence; Web build success is insufficient.

Repository checks may validate manifests, entitlements, config, capability declarations, and adapter contracts. They must not pretend to prove App Store/Play approval or real-device background reliability. Missing device/store evidence is `BLOCKED`, with an exact S4 gate.

## 4. Test Architecture

S1 uses three independent layers:

1. **pgTAP contract files** — database lifecycle, provenance, RLS/ACL, learning eligibility, state transitions.
2. **Vitest/Node repository contracts** — frontend presentation eligibility and package/platform configuration without modifying production modules.
3. **Contract runner + report** — runs only S1 files, records command, assertion identity, result, routing (`S2`, `S3`, or `S4`), and evidence hash.

No layer may convert RED to PASS through mocks. Fixtures may create users, relationships, alerts, pings, coverage intervals, and notifications only inside rolled-back local tests.

## 5. Deterministic RED Rules

Every intended RED case must:

- name the ADR-0039 invariant;
- fail at one assertion with an expected `have`/`want` or catalog absence;
- identify the production change class that would make it pass;
- avoid depending on wall clock, cron history, test order, network, credentials, or production rows;
- pass fixture/precondition assertions before the target assertion;
- reproduce in a single-file/local command.

If a test aborts, flakes, or fails before its target assertion, S1 fixes the test harness only. It does not classify that output as a product RED.

## 6. Result Routing

| Result | Route |
|---|---|
| Existing DB security/runtime defect | S2 append-only migration repair |
| ADR-0039 product behavior/schema missing | S3 implementation |
| Native entitlement, signing, store, or real-device evidence missing | S4 platform gate |
| Test isolation or fixture failure | S1 test repair |
| Conflict with accepted ADR or production truth | Human/Manager checkpoint |

## 7. Acceptance

S1 acceptance requires:

- all contract packs represented;
- each S1 test runnable alone;
- expected RED assertions fail for the intended semantic reason;
- existing PASS assertions remain passing;
- BLOCKED platform items state the unavailable external evidence and exact S4 verification;
- no production/runtime/migration/release file changed;
- no online/remote operation;
- one hash-addressed baseline report and clean test-only diff;
- Manager review of every contract and result classification.

## 8. Non-Goals

- no DB repair;
- no Special Attention implementation;
- no Guardian expansion;
- no new health-state API/UI;
- no AAB, Tauri, TestFlight, or App Store release;
- no attempt to make the inherited S0 Vitest/pgTAP suites globally green;
- no decision on disputed historical shadow-model/hash contracts.
