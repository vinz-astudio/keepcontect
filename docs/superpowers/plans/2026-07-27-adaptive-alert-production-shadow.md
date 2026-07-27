# Adaptive Alert Production Shadow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and locally audit ADR-0028’s production-quality, no-notification adaptive alert shadow pipeline, including trustworthy Android/Tauri coverage provenance, without granting it live alert authority or enabling production scheduling.

**Architecture:** Integrate the already audited fixture/replay candidate onto current `main`, then add three append-only operational migrations: coverage acceptance/finalization, bounded producers/storage, and the scheduler-off cycle/dispatcher. Android reuses its existing 15-minute WorkManager path; Tauri uses a native health command plus a five-minute authenticated RPC loop. All shadow data stays private, all live alert functions/tables remain outside the write path, and production deployment/publication/canary/Cron activation remain later tasks.

**Tech Stack:** React 18 + Vite + TypeScript + Vitest; Supabase Postgres/pgTAP/Edge Functions; Capacitor Android Java + WorkManager + JUnit; Tauri 2 Rust + Cargo tests; Node migration replay tooling.

## Global Constraints

- Binding decision: ADR-0028; accepted design: `docs/superpowers/specs/2026-07-27-adaptive-alert-production-shadow-design.md`.
- Start implementation from `main@46b73a7` or a descendant containing only reviewed documentation changes.
- Keep `process_escalations()`, `private.notify_stage()`, `private.silence_threshold()`, `private.is_in_sleep_window()`, `private.apply_liveness_side_effects()`, live notification dispatch, and the ADR-0022 Cron job unchanged.
- Shadow code may write only adaptive shadow, coverage, invalidation, and aggregate objects. It may never write `public.alerts`, `public.alert_events`, or `public.notifications`.
- Import candidate commits `947f01f`, `276ec3d`, `f5efb8d`, `6593204`, `cfdf88f`, `d467ae7`, `bb51f18`, `e97c4db`, `034ddee`, `38c2a3a`, `963d894`, `b9878c0`, and `e8b5d92`; exclude `dddde10` and `20260726011500_explicit_data_api_acl_baseline.sql`.
- Preserve `20260727090000_scope_group_alerts_to_monitoring_direction.sql` and its pgTAP regression.
- Add new database behavior only through migrations later than `20260727090000`; never edit an applied migration.
- Base implementation contains no `cron.schedule`, `cron.alter_job`, or `cron.unschedule` call and leaves `enabled=false`, `accept_coverage_leases=false`.
- Continuous coverage v1 is supported only for `android-passive-v1` and `tauri-idle-v1`. Plain browser, installed-PWA-only, Shortcut, manual, Guardian, and a single behavior ping cannot claim continuous coverage.
- Android lease cadence is the existing 15-minute WorkManager cadence; do not add a five-minute Android loop.
- Tauri lease cadence is five minutes and maximum accepted consecutive server gap is 12 minutes. Android maximum accepted consecutive server gap is 35 minutes.
- Per-user/client detail retention is 35 days; per-user decision persistence is capped at 36 rows per UTC day.
- Personal evidence may be evaluated without sharing consent; cohort contribution requires current `profiles.consent_data_sharing=true`; long-term segmented reports require at least 10 eligible contributors.
- The implementation task stops after isolated code, local replay/tests/builds, and independent audit. It does not deploy production migrations, enable lease acceptance, publish web/APK/Tauri artifacts, run a production canary, add Cron, or promote adaptive live authority.
- Use free/included tooling only. No external AI receives production or shadow data.

---

## File and Interface Map

### Audited source integration

- Create `scripts/adaptive-shadow-source-manifest.mjs`: canonical imported-commit, migration-hash, excluded-file, and protected-live-file manifest.
- Create `scripts/adaptive-shadow-source-manifest.test.mjs`: Node test that fails on missing/changed imported migration bytes, ACL migration inclusion, group-fix loss, or protected live-path edits.
- Modify `package.json`: add `"adaptive:source:check": "node scripts/adaptive-shadow-source-manifest.mjs"`; retain replay scripts from `276ec3d`.
- Import the eight adaptive migrations and their pgTAP files from `codex/adaptive-alert-shadow@e8b5d92` byte-for-byte.

### Coverage contract and token wrapper

- Create `supabase/migrations/20260727173000_adaptive_alert_shadow_coverage_contract.sql`: runtime config singleton, private lease table, authenticated RPC, service-only wrapper, finalizer, cleanup, ACL/RLS/publication guards.
- Create `supabase/tests/adaptive_alert_shadow_coverage_contract.sql`: lease validation, idempotency, interval finalization, unsupported-surface, consent-independent personal coverage, ACL, and retention tests.
- Create `supabase/functions/shadow-coverage-lease/contract.ts`: Deno-free request parser and stable failure-code mapper.
- Create `supabase/functions/shadow-coverage-lease/contract.test.ts`: Vitest tests for token-wrapper request validation.
- Create `supabase/functions/shadow-coverage-lease/index.ts`: heartbeat-token lookup and service-only wrapper call; it does not call any behavior-ping/live-alert function.
- Modify `vitest.config.ts`: include `supabase/functions/**/*.test.ts` in the imported candidate config.

Locked SQL interfaces:

```sql
public.record_alert_shadow_coverage_lease(
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
) returns text

public.record_alert_shadow_coverage_lease_for_user(
  _user_id uuid,
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
) returns text

private.finalize_alert_shadow_coverage(
  _version_id uuid,
  _through timestamptz,
  _max_leases integer
) returns jsonb
```

The `_for_user` wrapper is Data-API-visible only so the Edge Function can call it: revoke execute from `PUBLIC`, `anon`, and `authenticated`, and grant execute only to `service_role`. Its core validator and every operational worker remain in `private`.

Stable RPC results: `inserted`, `duplicate`, `disabled`, `invalid`, `unsupported`, `unregistered_client`, `capability_mismatch`.

### Shared client identity and Android collector

- Modify `src/lib/clientReport.ts`: export `getClientId()`; keep the same `kc.clientId` storage key and `report_client` behavior.
- Modify `src/features/passive/native.ts`: pass `clientId`, `appVersion`, and the fixed collector contract to Android configuration.
- Modify `android/app/src/main/java/com/keepcontact/app/PassivePingPlugin.java`: validate and forward the new configuration fields.
- Modify `android/app/src/main/java/com/keepcontact/app/PassivePing.java`: persist native client/version fields and expose only package-private getters required by the reporter.
- Create `android/app/src/main/java/com/keepcontact/app/AlertShadowCoverageContract.java`: pure eligibility, canonical capability payload, and endpoint-body builder.
- Create `android/app/src/main/java/com/keepcontact/app/AlertShadowCoverageReporter.java`: one bounded token-authenticated POST to `/functions/v1/shadow-coverage-lease`.
- Modify `android/app/src/main/java/com/keepcontact/app/NotifyWorker.java`: call the reporter once per existing WorkManager execution before notification-permission early return; reporting failure does not fail notification polling.
- Create `android/app/src/test/java/com/keepcontact/app/AlertShadowCoverageContractTest.java`: pure JUnit contract tests.

Locked Android capability input:

```java
record CapabilityInput(
    boolean configured,
    boolean usageStatsAllowed,
    boolean usageStatsGranted,
    boolean workerExecuting,
    String clientId,
    String appVersion
) {}
```

The reporter emits `collector_state="operational"` only when all booleans are true and `clientId/appVersion` are nonblank; otherwise it sends nothing. Its SHA-256 input is the exact UTF-8 string `{"appVersion":"<version>","channel":"android-apk","collectorContract":"android-passive-v1","usageStatsGranted":true,"workerExecuting":true}` with keys in that order.

### Tauri collector

- Modify `src-tauri/src/lib.rs`: add `get_alert_shadow_coverage_capability` command and Rust unit tests; register it in `generate_handler!`.
- Create `src/features/passive/shadowCoverage.ts`: canonical capability hashing, authenticated RPC submission, five-minute Tauri loop, and hard browser/Capacitor gating.
- Create `src/features/passive/shadowCoverage.test.ts`: fake-timer Vitest contract tests.
- Modify `src/features/passive/PassivePingBoot.tsx`: start/stop the Tauri loop after session bootstrap; Android continues through native WorkManager.

Locked Tauri command result:

```ts
export interface TauriCoverageCapability {
  collectorContract: 'tauri-idle-v1'
  collectorState: 'operational' | 'unavailable'
  idleProbeAvailable: boolean
  appVersion: string
  channel: 'tauri'
}
```

Locked client function:

```ts
export function startTauriShadowCoverage(
  deps?: ShadowCoverageDeps,
): () => void
```

### Operational database pipeline

- Create `supabase/migrations/20260727174000_adaptive_alert_shadow_operational_schema.sql`: private current-state/run/daily-report/dirty-queue objects plus context/intervention/consent invalidation and cleanup producers.
- Create `supabase/tests/adaptive_alert_shadow_operational_schema.sql`: population/context/intervention/consent/retention/k-suppression tests.
- Create `supabase/migrations/20260727175000_adaptive_alert_shadow_operational_cycle.sql`: operational recorder, cycle, dispatcher, kill switch, current-transaction live-write guard; no schedule.
- Create `supabase/tests/adaptive_alert_shadow_operational_cycle.sql`: population, idempotency, 36-row cap, advisory lock, timeout/failure disable, live DML guard, ACL, and no-Cron tests.
- Create `src/features/alerts/adaptiveShadowSecurity.test.ts`: source-level protected-path and scheduler-absence regression gate.

Locked operational interfaces:

```sql
private.capture_alert_shadow_subject_contexts(
  _version_id uuid,
  _captured_at timestamptz,
  _max_users integer
) returns jsonb

private.capture_alert_shadow_interventions(
  _version_id uuid,
  _through timestamptz,
  _max_rows integer
) returns jsonb

private.record_alert_judgment_shadow_operational(
  _version_id uuid,
  _evaluated_at timestamptz,
  _max_population integer
) returns jsonb

private.run_adaptive_alert_shadow_cycle(
  _version_id uuid,
  _evaluated_at timestamptz
) returns jsonb

private.dispatch_adaptive_alert_shadow_cycle() returns void

private.disable_adaptive_alert_shadow(_failure_code text) returns void

private.maintain_adaptive_alert_shadow(
  _through timestamptz,
  _max_rows integer
) returns jsonb
```

---

### Task 1: AS-01 — Integrate the audited candidate with a fail-closed source manifest

**Owner:** agy Executor package A under a locked Codex order; Codex verifies every hash and diff.

**Files:**

- Create: `scripts/adaptive-shadow-source-manifest.mjs`
- Create: `scripts/adaptive-shadow-source-manifest.test.mjs`
- Modify: `package.json`
- Import: `docs/superpowers/plans/2026-07-25-migration-replay-compat.md`
- Import: `scripts/local-supabase-replay-core.mjs`
- Import: `scripts/local-supabase-replay.mjs`
- Import: `scripts/local-supabase-replay.test.mjs`
- Import: `src/features/baseline/RoutineSettings.tsx`
- Import: `src/features/baseline/routineMode.ts`
- Import: `src/features/baseline/routineMode.test.ts`
- Import: `src/features/baseline/routineModeCopy.ts`
- Import: `src/features/profile/profileApi.ts`
- Import: `vitest.config.ts`
- Import: `supabase/migrations/20260725160000_canonicalize_routine_modes.sql`
- Import: `supabase/migrations/20260725161000_adaptive_alert_shadow_schema.sql`
- Import: `supabase/migrations/20260725162000_adaptive_sleep_candidate.sql`
- Import: `supabase/migrations/20260725163000_adaptive_alert_gap_profiles.sql`
- Import: `supabase/migrations/20260725164000_routine_mode_cohort_priors.sql`
- Import: `supabase/migrations/20260725165000_adaptive_alert_candidate_evaluator.sql`
- Import: `supabase/migrations/20260725170000_adaptive_alert_replay.sql`
- Import: `supabase/migrations/20260725171000_adaptive_alert_shadow_recorder.sql`
- Import tests: `supabase/tests/adaptive_alert_*.sql`, `supabase/tests/adaptive_sleep_candidate.sql`, `supabase/tests/routine_mode_cohort_priors.sql`

**Interfaces:**

- Consumes: current `main`, candidate branch `codex/adaptive-alert-shadow@e8b5d92`, exact hash list below.
- Produces: byte-pinned candidate DB/evaluator/replay foundation and `npm run adaptive:source:check`.

- [ ] **Step 1: Create an isolated execution worktree**

Run from the main worktree:

```powershell
git status --short
git worktree add .worktrees/adaptive-shadow-prod-impl -b codex/adaptive-shadow-prod-impl 46b73a7
```

Expected: main is clean; new worktree is on `codex/adaptive-shadow-prod-impl` at `46b73a7`.

- [ ] **Step 2: Write the failing source-manifest test**

Create `scripts/adaptive-shadow-source-manifest.test.mjs`:

```js
import test from 'node:test'
import assert from 'node:assert/strict'
import { verifyAdaptiveShadowSource } from './adaptive-shadow-source-manifest.mjs'

test('accepts only the audited adaptive source set', async () => {
  const result = await verifyAdaptiveShadowSource(process.cwd())
  assert.deepEqual(result.unexpected, [])
  assert.equal(result.groupFixPresent, true)
  assert.equal(result.excludedAclPresent, false)
  assert.equal(result.protectedLiveDrift.length, 0)
})
```

- [ ] **Step 3: Run RED**

Run:

```powershell
node --test scripts/adaptive-shadow-source-manifest.test.mjs
```

Expected: FAIL because `adaptive-shadow-source-manifest.mjs` does not exist.

- [ ] **Step 4: Import the explicit commit set and stop on conflict**

Run:

```powershell
git cherry-pick 947f01f 276ec3d f5efb8d 6593204 cfdf88f d467ae7 bb51f18 e97c4db 034ddee 38c2a3a 963d894 b9878c0 e8b5d92
```

Expected: only the listed commits apply. If a conflict occurs, stop the agy order with evidence; the Executor must not choose a semantic resolution.

- [ ] **Step 5: Implement the exact manifest**

Create `scripts/adaptive-shadow-source-manifest.mjs` with the eight expected migration hashes:

```js
export const EXPECTED_MIGRATIONS = Object.freeze({
  '20260725160000_canonicalize_routine_modes.sql': '413b6231c78c1872125c8ac9a0f0ef4e10dd00280b64d491b3488d1026c78bbc',
  '20260725161000_adaptive_alert_shadow_schema.sql': 'c81654fff67fa547903ae65464bc2d0383e1e3e130f8318e5e4119ccdc03fe4c',
  '20260725162000_adaptive_sleep_candidate.sql': '0d2ac3f7676112d96d9e8cdc9b6fb7662296654130904239543a63c384feffd3',
  '20260725163000_adaptive_alert_gap_profiles.sql': 'a69404823027e2f4ac7d62c317c424538ed53ef32eeebd2f8948e190764940ad',
  '20260725164000_routine_mode_cohort_priors.sql': 'ca3682c85e644758f56323abe960dc1b5b2778b6600e0958bc155803b4c5e08b',
  '20260725165000_adaptive_alert_candidate_evaluator.sql': '4f1942f19c231fb2038a7eac57da8808d45047eda527ec1815777d1a6bde9aaa',
  '20260725170000_adaptive_alert_replay.sql': '4e2485692468fdd3ea2ff3e4b27feb4a22cd86c2eb31746ebd5ce662e5745905',
  '20260725171000_adaptive_alert_shadow_recorder.sql': '74d869b2edc5d4c919e3c377e351fbd0beac6d739a3f23ba6ed7df758ed9d004',
})

export const EXCLUDED = Object.freeze([
  'supabase/migrations/20260726011500_explicit_data_api_acl_baseline.sql',
  'supabase/tests/data_api_acl.sql',
])

export const PROTECTED_LIVE = Object.freeze([
  'supabase/migrations/20260719154339_correct_gate1_sensitivity_contract.sql',
  'supabase/migrations/20260720150000_keep_notifications_on_auto_resolve.sql',
  'supabase/migrations/20260727090000_scope_group_alerts_to_monitoring_direction.sql',
])
```

Implement `verifyAdaptiveShadowSource(root)` using `node:crypto`, `node:fs/promises`, and `git diff --name-only 46b73a7...HEAD`. It must report a missing/hash-mismatched migration, either excluded path, a missing group-fix migration, or any protected-live path in the diff.

Add to `package.json`:

```json
"adaptive:source:check": "node scripts/adaptive-shadow-source-manifest.mjs"
```

- [ ] **Step 6: Run GREEN and focused candidate tests**

Run:

```powershell
node --test scripts/adaptive-shadow-source-manifest.test.mjs scripts/local-supabase-replay.test.mjs
npm run typecheck
npm test -- --run src/features/baseline/routineMode.test.ts
```

Expected: PASS; manifest reports eight exact migrations, excluded ACL absent, group fix present, protected live drift empty.

- [ ] **Step 7: Commit**

```powershell
git add package.json vitest.config.ts scripts src/features/baseline src/features/profile supabase/migrations supabase/tests
git commit -m "feat(alerts): integrate audited adaptive shadow candidate"
```

Expected: commit excludes `20260726011500_explicit_data_api_acl_baseline.sql`, `data_api_acl.sql`, production deploy files, and generated replay databases.

---

### Task 2: AS-02 — Add the private coverage lease contract and finalizer

**Owner:** agy Executor package A, same locked order after AS-01 GREEN; Codex reviews SQL semantics before accepting the artifact.

**Files:**

- Create: `supabase/tests/adaptive_alert_shadow_coverage_contract.sql`
- Create: `supabase/migrations/20260727173000_adaptive_alert_shadow_coverage_contract.sql`

**Interfaces:**

- Consumes: candidate `alert_model_versions`, `alert_observation_coverage_intervals`, `clients`, `profiles`, authenticated user identity.
- Produces: the three locked coverage SQL interfaces and default-disabled runtime config used by Android, Tauri, and AS-05/AS-06.

- [ ] **Step 1: Write RED pgTAP coverage cases**

Create `supabase/tests/adaptive_alert_shadow_coverage_contract.sql` with `BEGIN; SELECT plan(34);` and explicit assertions for:

```sql
SELECT has_function('public', 'record_alert_shadow_coverage_lease',
  ARRAY['text','text','text','text','text','timestamp with time zone','uuid']);
SELECT has_function('public', 'record_alert_shadow_coverage_lease_for_user',
  ARRAY['uuid','text','text','text','text','text','timestamp with time zone','uuid']);
SELECT has_function('private', 'finalize_alert_shadow_coverage',
  ARRAY['uuid','timestamp with time zone','integer']);
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'client-a','tauri','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'disabled',
  'lease acceptance fails closed by default'
);
```

The remaining assertions must insert deterministic fixtures and prove: one lease yields no interval; two Tauri leases 5 minutes apart yield exactly `[first_received_at,second_received_at)`; a 13-minute Tauri gap and 36-minute Android gap yield `unknown`; duplicate event ID is idempotent; out-of-order/stale/drifted timestamps do not extend coverage; client/capability/timezone/app-version changes split intervals; unregistered client and browser/PWA/manual/Guardian channels return stable rejection codes; authenticated cannot read lease/coverage tables; authenticated can execute only the public RPC; `service_role` cannot execute private operational workers through Data API; no Realtime publication; cleanup removes source-identifiable rows older than 35 days.

- [ ] **Step 2: Run RED**

Run:

```powershell
npm run db:replay:compat
```

Expected: FAIL at the first `has_function` because the migration does not exist.

- [ ] **Step 3: Implement the migration with fail-closed defaults**

Create the runtime singleton:

```sql
CREATE TABLE private.adaptive_alert_shadow_runtime_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  version_id uuid NULL REFERENCES public.alert_model_versions(id),
  enabled boolean NOT NULL DEFAULT false,
  accept_coverage_leases boolean NOT NULL DEFAULT false,
  max_population integer NOT NULL DEFAULT 10000 CHECK (max_population BETWEEN 1 AND 10000),
  detail_retention_days integer NOT NULL DEFAULT 35 CHECK (detail_retention_days = 35),
  cycle_timeout_seconds integer NOT NULL DEFAULT 120 CHECK (cycle_timeout_seconds = 120),
  max_consecutive_failures integer NOT NULL DEFAULT 3 CHECK (max_consecutive_failures = 3),
  consecutive_failures integer NOT NULL DEFAULT 0 CHECK (consecutive_failures BETWEEN 0 AND 3),
  last_failure_code text NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private.adaptive_alert_shadow_runtime_config(singleton) VALUES (true);
```

Create a private lease table keyed by `(user_id,event_id)` with server `received_at`, metadata `observed_at`, channel/contract/state/client/app version/capability hash, and no client policies. The public RPC must derive `auth.uid()`, verify `clients.id/user_id/platform/version`, accept only `tauri + tauri-idle-v1` or `android-apk + android-passive-v1`, enforce five-minute observed-time drift, and write no other table. The service-only public wrapper accepts `_user_id` only for the token Edge path and calls the same private validator. Revoke it from `PUBLIC`, `anon`, and `authenticated`; grant only `service_role`. This is the sole non-authenticated-user Data API bridge and is not an operational worker.

The finalizer must use `lag(received_at)` partitioned by `(user_id,client_id,channel,collector_contract,capability_sha256,app_version,timezone,utc_offset_minutes)`, require a positive gap within 12 or 35 minutes, and insert only the closed interval. Use an immutable provenance SHA-256 over version/user/client/bounds/capability/context fields. It must never extend beyond the second lease.

Every `SECURITY DEFINER` function must include:

```sql
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
```

Revoke `PUBLIC/anon/authenticated/service_role` table access; grant authenticated execute only on the public RPC; keep both private functions owner-only.

- [ ] **Step 4: Run GREEN**

Run:

```powershell
npm run db:replay:compat
```

Expected: all coverage assertions and existing profile assertions PASS.

- [ ] **Step 5: Run static no-scheduler/no-live-DML checks**

Run:

```powershell
rg -n "cron\\.(schedule|alter_job|unschedule)|INSERT INTO public\\.(alerts|alert_events|notifications)|UPDATE public\\.(alerts|alert_events|notifications)|DELETE FROM public\\.(alerts|alert_events|notifications)" supabase/migrations/20260727173000_adaptive_alert_shadow_coverage_contract.sql
```

Expected: no matches.

- [ ] **Step 6: Commit**

```powershell
git add supabase/migrations/20260727173000_adaptive_alert_shadow_coverage_contract.sql supabase/tests/adaptive_alert_shadow_coverage_contract.sql
git commit -m "feat(alerts): add private shadow coverage leases"
```

---

### Task 3: AS-03 — Add the token wrapper and Android 15-minute coverage reporter

**Owner:** agy Executor package B under a new locked order. The order contains only the files listed below and the already locked SQL result codes.

**Files:**

- Create: `supabase/functions/shadow-coverage-lease/contract.ts`
- Create: `supabase/functions/shadow-coverage-lease/contract.test.ts`
- Create: `supabase/functions/shadow-coverage-lease/index.ts`
- Modify: `vitest.config.ts`
- Modify: `src/lib/clientReport.ts`
- Modify: `src/features/passive/native.ts`
- Modify: `android/app/src/main/java/com/keepcontact/app/PassivePingPlugin.java`
- Modify: `android/app/src/main/java/com/keepcontact/app/PassivePing.java`
- Create: `android/app/src/main/java/com/keepcontact/app/AlertShadowCoverageContract.java`
- Create: `android/app/src/main/java/com/keepcontact/app/AlertShadowCoverageReporter.java`
- Modify: `android/app/src/main/java/com/keepcontact/app/NotifyWorker.java`
- Create: `android/app/src/test/java/com/keepcontact/app/AlertShadowCoverageContractTest.java`

**Interfaces:**

- Consumes: AS-02 service wrapper; existing heartbeat token; existing unique 15-minute `kc-notify-poll`; stable `kc.clientId`; `APP_VERSION`.
- Produces: Android `android-passive-v1` operational leases without a new periodic worker or live activity write.

- [ ] **Step 1: Write RED token-contract tests**

Create a pure parser:

```ts
export interface CoverageLeaseRequest {
  token: string
  client_id: string
  channel: 'android-apk'
  collector_contract: 'android-passive-v1'
  collector_state: 'operational'
  capability_sha256: string
  observed_at: string
  event_id: string
}
```

In `contract.test.ts`, assert malformed JSON, missing/invalid UUID, non-64-hex capability, wrong channel/contract/state, and future/stale observed times return fixed 400/422 codes. Assert a valid request is normalized without logging or returning the token.

- [ ] **Step 2: Write RED Android pure-contract tests**

Create JUnit cases:

```java
@Test public void operationalRequiresAllHealthInputs() {
  assertFalse(AlertShadowCoverageContract.isOperational(
      new CapabilityInput(true, true, false, true, "c1", "0.5.20")));
  assertTrue(AlertShadowCoverageContract.isOperational(
      new CapabilityInput(true, true, true, true, "c1", "0.5.20")));
}

@Test public void bodyNeverContainsActivityOrNotificationFields() {
  String body = AlertShadowCoverageContract.body("token", "c1", "0.5.20",
      repeat("a", 64), "2026-07-27T10:00:00.000Z", UUID.fromString(
      "00000000-0000-4000-8000-000000000001"));
  assertFalse(body.contains("behavior"));
  assertFalse(body.contains("notification"));
  assertTrue(body.contains("\"collector_contract\":\"android-passive-v1\""));
}
```

- [ ] **Step 3: Run RED**

Run:

```powershell
npm test -- --run supabase/functions/shadow-coverage-lease/contract.test.ts
Set-Location android
.\gradlew.bat testDebugUnitTest --tests com.keepcontact.app.AlertShadowCoverageContractTest
```

Expected: FAIL because parser and Java contract classes do not exist.

- [ ] **Step 4: Implement the Edge wrapper**

`index.ts` must:

1. parse with `parseCoverageLeaseRequest`;
2. look up `heartbeat_tokens.user_id` using service role without logging the token;
3. call service-role-only `public.record_alert_shadow_coverage_lease_for_user`;
4. map only the stable SQL result to `{ok,status}`;
5. return generic `database_error` without raw Postgres text.

It must not import or call `record_behavior_ping_for_user`, `process_escalations`, push dispatch, or notification tables.

- [ ] **Step 5: Implement stable shared client ID**

Rename the private `clientId()` function to:

```ts
export function getClientId(): string
```

Keep `reportClient()` calling `getClientId()` and preserve the `kc.clientId` key. In `native.ts`, pass:

```ts
clientId: getClientId(),
appVersion: APP_VERSION,
collectorContract: 'android-passive-v1',
```

- [ ] **Step 6: Implement Android reporting on the existing worker**

Persist the three fields in `PassivePing.configure`. `NotifyWorker.doWork()` calls:

```java
AlertShadowCoverageReporter.reportIfOperational(context);
```

after the existing UsageStats health query and before:

```java
if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
    return Result.success();
}
```

The reporter returns immediately unless configured, UsageStats is enabled and granted, the current worker is executing, client/version are present, and the last successful lease is at least 14 minutes old. It uses an eight-second connect/read timeout and updates `last_shadow_coverage_lease_at` only on `inserted` or `duplicate`.

- [ ] **Step 7: Run GREEN and Android regression tests**

Run:

```powershell
npm test -- --run supabase/functions/shadow-coverage-lease/contract.test.ts src/features/passive/contract.test.ts src/features/signals/sensors.test.ts
npm run typecheck
Set-Location android
.\gradlew.bat testDebugUnitTest
.\gradlew.bat assembleDebug
```

Expected: PASS; exactly one debug APK is produced; no release version file changes.

- [ ] **Step 8: Commit**

```powershell
git add supabase/functions/shadow-coverage-lease vitest.config.ts src/lib/clientReport.ts src/features/passive/native.ts android/app/src
git commit -m "feat(android): report healthy shadow coverage leases"
```

---

### Task 4: AS-04 — Add the Tauri native-health five-minute lease loop

**Owner:** agy Executor package C under a new locked order.

**Files:**

- Modify: `src-tauri/src/lib.rs`
- Create: `src/features/passive/shadowCoverage.ts`
- Create: `src/features/passive/shadowCoverage.test.ts`
- Modify: `src/features/passive/PassivePingBoot.tsx`

**Interfaces:**

- Consumes: AS-02 authenticated RPC, `getClientId()`, `APP_VERSION`, Tauri idle probe.
- Produces: `startTauriShadowCoverage()` and native `get_alert_shadow_coverage_capability`.

- [ ] **Step 1: Write RED Rust tests**

Inside `src-tauri/src/lib.rs`, add tests against a pure builder:

```rust
#[test]
fn tauri_capability_is_unavailable_when_idle_probe_is_missing() {
    let value = build_shadow_coverage_capability(false, "0.5.20");
    assert_eq!(value.collector_state, "unavailable");
    assert!(!value.idle_probe_available);
}

#[test]
fn tauri_capability_contract_is_fixed() {
    let value = build_shadow_coverage_capability(true, "0.5.20");
    assert_eq!(value.collector_contract, "tauri-idle-v1");
    assert_eq!(value.channel, "tauri");
}
```

- [ ] **Step 2: Write RED Vitest fake-timer cases**

`shadowCoverage.test.ts` must prove:

- plain browser and Capacitor Android call neither Tauri invoke nor Supabase RPC;
- unavailable native capability sends nothing;
- operational Tauri sends immediately and every five minutes;
- overlapping timer ticks do not overlap requests;
- cleanup cancels the timer;
- RPC args exactly use `getClientId()`, `tauri`, `tauri-idle-v1`, `operational`, a 64-hex SHA-256, ISO observed time, and UUID;
- RPC error waits until the next normal tick and never writes a behavior ping.

- [ ] **Step 3: Run RED**

Run:

```powershell
Set-Location src-tauri
cargo test tauri_capability
Set-Location ..
npm test -- --run src/features/passive/shadowCoverage.test.ts
```

Expected: FAIL because the native command and TS module do not exist.

- [ ] **Step 4: Implement the native capability command**

Add:

```rust
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TauriCoverageCapability {
    collector_contract: &'static str,
    collector_state: &'static str,
    idle_probe_available: bool,
    app_version: String,
    channel: &'static str,
}

#[tauri::command]
fn get_alert_shadow_coverage_capability(app: tauri::AppHandle) -> TauriCoverageCapability {
    let version = app.package_info().version.to_string();
    build_shadow_coverage_capability(sys_idle::get_idle_time_ms().is_some(), &version)
}
```

Register the command beside `get_system_idle_time_ms`.

- [ ] **Step 5: Implement the Tauri-only lease loop**

`shadowCoverage.ts` canonicalizes exactly:

```ts
const canonical = JSON.stringify({
  appVersion: capability.appVersion,
  channel: capability.channel,
  collectorContract: capability.collectorContract,
  idleProbeAvailable: capability.idleProbeAvailable,
})
```

Hash with `crypto.subtle.digest('SHA-256', TextEncoder.encode(canonical))`. Call `record_alert_shadow_coverage_lease` once immediately and with `setInterval(..., 5 * 60_000)`. If `isTauri()` is false, `Capacitor.isNativePlatform()` is true, the capability is unavailable, or a request is in flight, do nothing.

In `PassivePingBoot`, retain the stop function and call it during effect cleanup.

- [ ] **Step 6: Run GREEN**

Run:

```powershell
Set-Location src-tauri
cargo test
Set-Location ..
npm test -- --run src/features/passive/shadowCoverage.test.ts src/features/passive/contract.test.ts
npm run typecheck
npm run build
```

Expected: PASS; ordinary browser contract remains unable to submit a lease.

- [ ] **Step 7: Commit**

```powershell
git add src-tauri/src/lib.rs src/features/passive/shadowCoverage.ts src/features/passive/shadowCoverage.test.ts src/features/passive/PassivePingBoot.tsx
git commit -m "feat(tauri): report healthy shadow coverage leases"
```

---

### Task 5: AS-05 — Add bounded context, intervention, invalidation, retention, and aggregate producers

**Owner:** agy Executor package D under a new locked order; it receives the exact table/function contracts from this plan.

**Files:**

- Create: `supabase/tests/adaptive_alert_shadow_operational_schema.sql`
- Create: `supabase/migrations/20260727174000_adaptive_alert_shadow_operational_schema.sql`

**Interfaces:**

- Consumes: AS-02 coverage intervals; candidate context/profile/cohort tables; live sources read-only.
- Produces: private queues/state/runs/reports plus capture and maintenance functions used by AS-06.

- [ ] **Step 1: Write RED pgTAP schema/producer tests**

Plan at least 42 assertions that prove:

```sql
SELECT has_function('private', 'capture_alert_shadow_subject_contexts',
  ARRAY['uuid','timestamp with time zone','integer']);
SELECT has_function('private', 'capture_alert_shadow_interventions',
  ARRAY['uuid','timestamp with time zone','integer']);
SELECT has_function('private', 'maintain_adaptive_alert_shadow',
  ARRAY['timestamp with time zone','integer']);
```

Fixture cases must cover: population includes a user with `device_state` plus any active monitored membership regardless of current alert/Guardian/device status; monitored=false-only user excluded; sensitivity/routine/timezone/offset/version hash captured as-of; changed context closes/opens rather than rewriting history; malformed timezone/future source timestamp becomes stable unreplayable state; Guardian copied only as intervention; notification/concern/check-in source IDs are idempotent; consent withdrawal invalidates affected cohort modes immediately; no non-consenting contributor remains eligible while rebuild is pending; 35-day user/client detail cleanup; contributor<10 suppression; long-term rows have no user/client/event/alert ID or exact individual timestamp.

- [ ] **Step 2: Run RED**

Run:

```powershell
npm run db:replay:compat
```

Expected: FAIL because the operational schema/functions do not exist.

- [ ] **Step 3: Implement private operational objects**

Create private tables for:

```text
adaptive_alert_shadow_user_state
adaptive_alert_shadow_cycle_runs
adaptive_alert_shadow_daily_reports
adaptive_alert_shadow_profile_dirty
adaptive_alert_shadow_cohort_dirty
adaptive_alert_shadow_subject_context_state
adaptive_alert_shadow_intervention_cursor
```

All tables have explicit primary keys, bounded check constraints, owner-only privileges, no policies granting client rows, and no Realtime publication. Dirty queues use `ON CONFLICT ... DO UPDATE SET invalidated_at = greatest(...)`.

Subject context computes a stable SHA-256 from version, user, canonical sensitivity/routine, timezone/offset, source timestamps, and evidence version. Intervention capture stores only source kind/source ID/time/version/provenance needed for exclusion; it never updates the live source.

Maintenance deletes user-identifiable rows older than `through - interval '35 days'`, processes at most `_max_rows`, rebuilds consent-safe cohort cells, and writes only k-suppressed daily aggregates.

- [ ] **Step 4: Run GREEN and cohort regressions**

Run:

```powershell
npm run db:replay:compat
```

Expected: PASS; cohort consent and candidate evaluator behavior remain deterministic.

- [ ] **Step 5: Commit**

```powershell
git add supabase/migrations/20260727174000_adaptive_alert_shadow_operational_schema.sql supabase/tests/adaptive_alert_shadow_operational_schema.sql
git commit -m "feat(alerts): add bounded shadow evidence producers"
```

---

### Task 6: AS-06 — Add the scheduler-off operational recorder, cycle, dispatcher, and kill switch

**Owner:** agy Executor package D, same order after AS-05 GREEN; Codex reviews every protected-path query.

**Files:**

- Create: `supabase/tests/adaptive_alert_shadow_operational_cycle.sql`
- Create: `supabase/migrations/20260727175000_adaptive_alert_shadow_operational_cycle.sql`
- Create: `src/features/alerts/adaptiveShadowSecurity.test.ts`

**Interfaces:**

- Consumes: AS-02/AS-05 functions and candidate `private.resolve_alert_candidate`.
- Produces: operational recorder/cycle/dispatcher/disable interfaces; still no Cron job.

- [ ] **Step 1: Write RED cycle pgTAP**

Plan at least 46 assertions for: default dispatcher no-op; advisory lock skips overlap; exact monitored population; every user counted even when unreplayable; full row only on first/state change/hourly checkpoint; same-minute idempotency; 36 rows/user/day disables execution; aggregate run written every cycle; malformed evaluator result disables; current-transaction DML on a protected live table raises and rolls back; hash/ACL/publication drift disables; timeout code disables immediately; ordinary failure increments and third failure disables; success resets failures; client/service roles cannot execute workers; no raw error/PII stored; base migrations create zero shadow Cron jobs and do not alter the live job.

- [ ] **Step 2: Write RED static security test**

Create:

```ts
import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

const files = [
  'supabase/migrations/20260727173000_adaptive_alert_shadow_coverage_contract.sql',
  'supabase/migrations/20260727174000_adaptive_alert_shadow_operational_schema.sql',
  'supabase/migrations/20260727175000_adaptive_alert_shadow_operational_cycle.sql',
]

describe('ADR-0028 shadow isolation', () => {
  const source = files.map((f) => fs.readFileSync(f, 'utf8')).join('\n')
  it('contains no scheduler activation', () => {
    expect(source).not.toMatch(/cron\.(schedule|alter_job|unschedule)/i)
  })
  it('contains no live alert DML target', () => {
    expect(source).not.toMatch(/\b(insert\s+into|update|delete\s+from)\s+public\.(alerts|alert_events|notifications)\b/i)
  })
  it('does not call live escalation or notification functions', () => {
    expect(source).not.toMatch(/\b(process_escalations|notify_stage|push-dispatch)\b/i)
  })
})
```

- [ ] **Step 3: Run RED**

Run:

```powershell
npm run db:replay:compat
npm test -- --run src/features/alerts/adaptiveShadowSecurity.test.ts
```

Expected: FAIL because the cycle migration does not exist.

- [ ] **Step 4: Implement the operational recorder**

Call `private.resolve_alert_candidate(version_id,user_id,evaluated_at)`, validate every required key/type, calculate deterministic decision SHA-256, and compare against `adaptive_alert_shadow_user_state`. Persist detail only for first result, `would_alert` transition, basis/threshold/quality/reason change, or when the previous checkpoint is at least one hour old. Before insert, count the UTC-day rows and raise `shadow_detail_budget_exceeded` at 36.

- [ ] **Step 5: Implement cycle live-write proof**

At cycle start and immediately before success, read the current transaction’s `pg_stat_xact_user_tables` counters for the three protected tables. Compare `n_tup_ins + n_tup_upd + n_tup_del`; any delta raises `shadow_live_write_detected`. Do not compare global table timestamps as the authoritative proof.

The cycle order is lock → config/hash/ACL/publication/budget validation → coverage finalization → context/interventions → bounded rebuilds → recorder → live-write delta → aggregate summary.

- [ ] **Step 6: Implement dispatcher and disable path**

Dispatcher uses:

```sql
PERFORM set_config('statement_timeout', '120s', true);
PERFORM set_config('lock_timeout', '2s', true);
PERFORM set_config('TimeZone', 'UTC', true);
```

Map raw exceptions to fixed codes. Immediately disable for timeout, live write, hash/ACL/publication drift, malformed evaluator output, consent/privacy violation, or row-budget breach. Increment ordinary failures and disable at three. Store no raw exception text.

- [ ] **Step 7: Run GREEN**

Run:

```powershell
npm run db:replay:compat
npm test -- --run src/features/alerts/adaptiveShadowSecurity.test.ts
```

Expected: PASS; `cron.job` contains no `adaptive-alert-shadow-*` job.

- [ ] **Step 8: Commit**

```powershell
git add supabase/migrations/20260727175000_adaptive_alert_shadow_operational_cycle.sql supabase/tests/adaptive_alert_shadow_operational_cycle.sql src/features/alerts/adaptiveShadowSecurity.test.ts
git commit -m "feat(alerts): add scheduler-off shadow cycle"
```

---

### Task 7: AS-07 — Run the integrated deterministic verification gate

**Owner:** Codex Manager directly. No Executor repairs are allowed inside this gate.

**Files:**

- Verify only; any repair becomes a new exact-write-set task/order.

**Interfaces:**

- Consumes: accepted commits from AS-01 through AS-06.
- Produces: hash-pinned evidence packet for independent Claude audit.

- [ ] **Step 1: Verify source and worktree scope**

Run:

```powershell
git status --short
npm run adaptive:source:check
git diff 46b73a7...HEAD --name-only
git log --oneline --reverse 46b73a7..HEAD
```

Expected: clean worktree; only planned files; excluded ACL migration absent; protected group fix present.

- [ ] **Step 2: Run replay and all database tests**

Run:

```powershell
npm run db:replay:compat
npx supabase test db --local
```

Expected: fresh replay reaches `20260727175000`; all pgTAP files PASS; migration source hashes remain unchanged.

- [ ] **Step 3: Run application and contract tests**

Run:

```powershell
npm run typecheck
npm test
npm run build
npm run local:gate:static
```

Expected: PASS with no snapshot update and no generated source changes.

- [ ] **Step 4: Run Android tests and unsigned debug build**

Run:

```powershell
npm run cap:sync
Set-Location android
.\gradlew.bat testDebugUnitTest assembleDebug
Set-Location ..
```

Expected: PASS; debug APK exists; `src/lib/version.ts`, `public/version.json`, `android/app/build.gradle`, and `src-tauri/tauri.conf.json` remain unchanged.

- [ ] **Step 5: Run Tauri tests and local build**

Run:

```powershell
Set-Location src-tauri
cargo test
cargo build --release
Set-Location ..
```

Expected: PASS; local binary exists; no installer is published.

- [ ] **Step 6: Run security/static boundary scans**

Run:

```powershell
rg -n -g "2026072717*.sql" "cron\\.(schedule|alter_job|unschedule)" supabase/migrations
rg -n -g "2026072717*.sql" "(INSERT INTO|UPDATE|DELETE FROM) public\\.(alerts|alert_events|notifications)" supabase/migrations
rg -n -g "2026072717*.sql" "process_escalations|private\\.notify_stage|push-dispatch" supabase/migrations supabase/functions/shadow-coverage-lease
```

Expected: no matches. References inside pgTAP/static tests are allowed only as negative assertions.

- [ ] **Step 7: Verify no production side effect**

Run:

```powershell
git status --short
git diff --exit-code 46b73a7 -- src/lib/version.ts public/version.json android/app/build.gradle src-tauri/tauri.conf.json
```

Expected: clean worktree; version files unchanged; no linked `supabase db push`, Vercel deploy, GitHub release, APK upload, Tauri installer upload, or Cron call appears in command evidence.

---

### Task 8: AS-08 — Conduct the independent non-author Claude audit

**Owner:** Claude Manager/auditor through `brain-task.mjs invoke-claude`; Codex writes one locked read-only order first.

**Files:**

- Read-only: accepted spec, ADR-0028, full `46b73a7...HEAD` diff, migration/test manifest, AS-07 evidence.
- Write: only the runtime-managed delegation artifact/receipt paths named by the Brain order.

**Interfaces:**

- Consumes: integrated evidence packet with `expected_verdict=null`.
- Produces: independent `APPROVE` or evidence-backed blocker list; no code mutation.

- [ ] **Step 1: Install the complete audit order**

The order must require Claude to independently verify:

1. no live alert/notification authority or DML path;
2. lease authenticity, interval closure, unsupported-surface rejection;
3. monitored population and consent/cohort behavior;
4. 35-day retention, k=10 suppression, 36-row/day budget;
5. owner-only operational ACLs and narrow authenticated lease RPC;
6. current-transaction live-write proof and failure/kill-switch semantics;
7. absence of base Cron;
8. Android existing-WorkManager cadence and Tauri five-minute health gating;
9. candidate hash manifest, group fix preservation, ACL migration exclusion;
10. test/build evidence and separate production/publication gates.

Set `can_subdelegate=false`, one review turn, read-only tools, and no expected verdict.

- [ ] **Step 2: Invoke Claude once**

Run from the Brain:

```powershell
node Coordination/tools/brain-task.mjs invoke-claude <implementation-task-id> <audit-delegation-id>
```

Expected: one authoritative invocation receipt and either `APPROVE` or a bounded blocker list.

- [ ] **Step 3: Resolve the audit result**

If `APPROVE`, Codex independently rechecks the final HEAD and receipt hashes. If blockers exist, create a new repair task with exact files and tests; do not let Claude mutate and do not silently widen the current order.

---

### Task 9: AS-09 — Freeze the local implementation and create separate release successors

**Owner:** Codex Manager.

**Files:**

- Brain write-back paths from the later implementation task only.
- No production or release file mutation in this plan.

**Interfaces:**

- Consumes: Claude approval and clean AS-07 rerun.
- Produces: audited local implementation commit and four blocked successor tasks.

- [ ] **Step 1: Record the audited implementation commit**

Record HEAD, parent, full tree hash, migration hashes, pgTAP totals, Vitest totals, Android debug APK SHA-256, and Tauri local binary SHA-256 in Brain truth/Dev Log through `brain-task update`.

- [ ] **Step 2: Create separate blocked successor definitions**

Create, but do not start or execute:

```text
AS-RELEASE-BASE   exact --include-all dry-run + scheduler-off base migrations + token-wrapper Edge Function
AS-RELEASE-CLIENTS web/APK/Tauri version bump, signed builds, publication, lease warm-up
AS-PROD-CANARY    one committed transaction-local manual cycle with scheduler absent
AS-PROD-ACTIVATE  new activation migration creating exactly two named Cron jobs
```

Each successor requires its own production/release authorization and task context.

- [ ] **Step 3: Finish the implementation task**

Run the later task’s required Brain verification/write-back/learning review and:

```powershell
node Coordination/tools/brain-task.mjs finish <implementation-task-id>
```

Expected: local implementation task completed; all four release successors remain blocked/unexecuted.

---

## Delegation Packaging

The implementation Manager must install one order per call:

| Package | Executor | Included tasks | Exact semantic boundary |
|---|---|---|---|
| A | agy | AS-01, AS-02 | Mechanical candidate import, hash manifest, DB lease contract/finalizer only |
| B | agy | AS-03 | Locked token-wrapper and Android existing-WorkManager reporter only |
| C | agy | AS-04 | Locked Tauri native capability and authenticated five-minute loop only |
| D | agy | AS-05, AS-06 | Locked private producers, bounded recorder/cycle/dispatcher, no Cron |
| Audit | Claude | AS-08 | Read-only independent integrated safety audit |

Codex owns all architecture, exact file/write sets, expected interfaces, review, merge acceptance, and final verification. agy must stop on missing inputs or conflicts and cannot subdelegate. Two rejected agy artifacts trigger Codex takeover rather than repeated open-ended repair loops.

## Self-Review Results

- Spec coverage: every accepted requirement maps to AS-01 through AS-09; production deployment, publication, canary, activation, and promotion are intentionally represented only as separately authorized successors.
- Placeholder scan: no incomplete implementation marker or “decide during coding” instruction remains.
- Type consistency: SQL, Android, Tauri, and TypeScript producer/consumer names match the locked interface map.
- Safety boundary: base migrations contain no Cron activation; local APK/Tauri builds are verification artifacts only and version/publication files stay unchanged.
