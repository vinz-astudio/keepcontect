# KC S1 Product and Platform Contract Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic test-only contracts that freeze ADR-0039 truth and classify S0 as PASS, RED, or BLOCKED without repairing runtime behavior.

**Architecture:** Three isolated packs: pgTAP for database behavior/authority, Vitest for repository/platform truth, and a Node catalog/runner that records each result and route. All RED cases fail at target assertions; no production source or migration changes.

**Tech Stack:** Node.js 22, Vitest 3.2.6, Supabase CLI 2.109.1, pgTAP, PowerShell, Git worktrees.

## Global Constraints

- Base is `8f2144d31c08b464892dd174b13f161258cab648`; spec commit is `1437aef55b7b8028331351c71dd4c9fed1605e14`.
- Allowed writes: new S1 tests, test-only helpers/runner, S1 baseline report, this plan, guarded Brain evidence.
- No production TypeScript, SQL function, migration, Edge Function, Java, Swift, Rust, manifest, entitlement, package version, release artifact, or existing-test expectation edit.
- No linked/remote Supabase, push, deploy, release, tag, version bump, account/permission mutation, or online App interruption.
- Existing migrations remain byte-for-byte unchanged.
- Expected RED is valid only when the fixture/precondition passes and the named ADR-0039 assertion fails deterministically.
- `BLOCKED` means unavailable external entitlement/store/device evidence; it is not PASS.
- Executor notes/prompts use terse caveman English; Manager owns semantics and final Chinese report.

---

### Task 1: Contract catalog and runner

**Files:**
- Create: `scripts/s1-contract-catalog.mjs`
- Create: `scripts/s1-contract-catalog.test.mjs`
- Create: `scripts/run-s1-contracts.mjs`
- Create: `scripts/run-s1-contracts.test.mjs`

**Interfaces:**
- Produces: `S1_CONTRACTS`, `validateCatalog(rows, root, { final })`, `classifyAssertion(expected, id, output)`, `renderBaseline(results, meta)`.
- Consumers: Tasks 2–6 add catalog rows; Task 6 runs the catalog and writes the report.

- [ ] **Step 1: Write catalog tests first**

```js
test('catalog ids and files are deterministic', () => {
  const result = validateCatalog(S1_CONTRACTS, process.cwd(), { final: false })
  expect(result.errors).toEqual([])
})

test('red requires failed target assertion, not harness abort', () => {
  expect(classifyAssertion('red', 'ADR0039-CONCERN-01', 'not ok 3 - ADR0039-CONCERN-01')).toBe('RED')
  expect(classifyAssertion('red', 'ADR0039-CONCERN-01', 'Bail out! fixture failed')).toBe('HARNESS_FAILURE')
})
```

- [ ] **Step 2: Run RED**

Run: `npm exec -- vitest run scripts/s1-contract-catalog.test.mjs scripts/run-s1-contracts.test.mjs`

Expected: FAIL because modules/exports do not exist.

- [ ] **Step 3: Implement minimal catalog/runner**

Catalog row shape:

```js
{
  id: 'ADR0039-CONCERN-01',
  pack: 'alert-activity',
  layer: 'pgtap',
  file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
  expected: 'red',
  route: 'S3',
  invariant: 'Concern requires an existing active alert'
}
```

Rules:

- enum: `layer=pgtap|vitest|external`, `expected=pass|red|blocked`, `route=S1|S2|S3|S4|human`;
- unique ID; build-phase validation checks currently registered files; final validation additionally requires all four packs and every non-external file;
- `classifyAssertion`: matching `ok ... <id>` => PASS, matching `not ok ... <id>` with no `Bail out!/ERROR/compile` => RED, external => BLOCKED, otherwise HARNESS_FAILURE;
- runner executes each unique file once, then classifies every catalog row from its named TAP/Vitest assertion; one RED must not hide PASS rows in the same file;
- runner captures command/exit/output SHA-256, never connects without explicit `--local`, and renders Markdown only to a caller-supplied path.

- [ ] **Step 4: Run GREEN**

Run: `npm exec -- vitest run scripts/s1-contract-catalog.test.mjs scripts/run-s1-contracts.test.mjs`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/s1-contract-catalog.mjs scripts/s1-contract-catalog.test.mjs scripts/run-s1-contracts.mjs scripts/run-s1-contracts.test.mjs
git diff --cached --check
git commit -m "test: add S1 contract catalog runner"
```

---

### Task 2: Alert, activity, Concern, and confirmation provenance

**Files:**
- Create: `supabase/tests/s1_alert_activity_concern_contract.sql`
- Modify: `scripts/s1-contract-catalog.mjs`

**Interfaces:**
- Consumes: Task 1 catalog schema.
- Produces: IDs `ADR0039-ACTIVITY-01`, `ADR0039-CONCERN-01..04`, `ADR0039-GUARDIAN-CONFIRM-01..02`.

- [ ] **Step 1: Write pgTAP fixture and assertions**

Use fixed UUIDs, `.invalid` emails, `BEGIN/ROLLBACK`, explicit auth claims, and precondition assertions. Core target cases:

```sql
SELECT throws_ok(
  $$ SELECT public.send_concern('...ward...'::uuid) $$,
  'active alert required',
  'ADR0039-CONCERN-01 Concern cannot create an alert'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alerts WHERE user_id = '...ward...' AND status = 'open'),
  0,
  'ADR0039-CONCERN-02 rejected Concern leaves alert count unchanged'
);
```

Repeat no-alert rejection for `gm_send_concern`. With one seeded open alert, call `send_concern` and assert:

- open alert count/id/status unchanged;
- exactly one `concern` notification bound to that alert;
- zero new `behavior_pings`;
- zero `resolved/auto_resolved/confirmed_safe` events.

For Guardian confirmation, seed active guardianship + alert with `paused_by=guardian`, call `resolve_alert`, then assert:

- actor is Guardian and event kind is `confirmed_safe`;
- zero Ward `manual_checkin` rows;
- Ward's last passive activity is unchanged.

Catalog existing `activity_never_answers_an_alert_in_cron.sql` as expected PASS rather than duplicating it.

- [ ] **Step 2: Run single-file RED**

Run: `npm exec --package=supabase@2.109.1 -- supabase test db --local supabase/tests/s1_alert_activity_concern_contract.sql`

Expected: fixture/preconditions PASS; Concern no-alert assertions RED because S0 creates `cause='concern'`; Guardian no-ping assertions PASS.

- [ ] **Step 3: Repair test harness only if needed**

Allowed fixes: auth claims, fixture ordering, deterministic counts, pgTAP plan count. Forbidden: migration/function/runtime edits or weaker expected values.

- [ ] **Step 4: Re-run and classify**

Expected: same target RED/PASS set on two consecutive runs.

- [ ] **Step 5: Commit**

```powershell
git add supabase/tests/s1_alert_activity_concern_contract.sql scripts/s1-contract-catalog.mjs
git diff --cached --check
git commit -m "test: freeze alert activity and Concern contracts"
```

---

### Task 3: Coverage-valid learning and protection health

**Files:**
- Create: `supabase/tests/s1_coverage_learning_health_contract.sql`
- Modify: `scripts/s1-contract-catalog.mjs`

**Interfaces:**
- Produces: `ADR0039-LEARN-01..04`, `ADR0039-HEALTH-01..03`.

- [ ] **Step 1: Write catalog-safe DB assertions**

Use `pg_get_functiondef` and catalog existence checks so missing S3 APIs produce assertions, not aborts:

```sql
SELECT like(
  pg_get_functiondef('private.rebuild_account_normal_bounds(date,integer,numeric,integer,integer,integer,integer)'::regprocedure),
  '%alert_observation_coverage_intervals%',
  'ADR0039-LEARN-01 normal bounds require coverage intervals'
);

SELECT has_function(
  'public', 'my_protection_health', ARRAY[]::text[],
  'ADR0039-HEALTH-01 server exposes protection health'
);
```

Additional assertions:

- normal-bound definition excludes non-valid coverage and cannot learn from `manual_checkin`/Guardian/Shortcut/replay;
- definition contains a two-independent-date/comparable-sample gate for exceptional long gaps;
- health projection exposes `ready|limited|unknown` plus incident/recovery evidence;
- prompt acknowledgement is separate from recovery state;
- outage cannot create a personal alert.

Where an API/table is absent, assert exact absence as RED, then use catalog metadata for deferred semantic checks; do not call a missing object.

- [ ] **Step 2: Run single-file RED twice**

Run: `npm exec --package=supabase@2.109.1 -- supabase test db --local supabase/tests/s1_coverage_learning_health_contract.sql`

Expected: stable RED for missing coverage qualification/two-sample gate/health API; no `Bail out!` or SQL error.

- [ ] **Step 3: Commit**

```powershell
git add supabase/tests/s1_coverage_learning_health_contract.sql scripts/s1-contract-catalog.mjs
git diff --cached --check
git commit -m "test: freeze coverage learning and health contracts"
```

---

### Task 4: Special Attention and Guardian/Ward authority

**Files:**
- Create: `supabase/tests/s1_care_authority_contract.sql`
- Modify: `scripts/s1-contract-catalog.mjs`

**Interfaces:**
- Produces: `ADR0039-SPECIAL-01..05`, `ADR0039-GUARDIAN-01..06`.

- [ ] **Step 1: Write existence/privacy/authority assertions**

```sql
SELECT has_table(
  'public', 'special_attention_subscriptions',
  'ADR0039-SPECIAL-01 private Special Attention subscription exists'
);

SELECT has_function(
  'public', 'set_special_attention', ARRAY['uuid','boolean'],
  'ADR0039-SPECIAL-02 subscription has explicit default-off setter'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.behavior_pings', 'INSERT'),
  'ADR0039-GUARDIAN-01 Guardian cannot insert Ward activity through Data API'
);
```

Also assert:

- inactive/revoked relationship is not notification-eligible;
- subscriber identity is private to owner/service path;
- subscription grants no alert, emergency-data, task, or Guardian authority;
- guardianship status supports pending/active/revoked and active relationship is visible to both parties;
- Guardian cannot alter Ward auth/credentials/device consent/account deletion through KC RPC surface;
- external confirmation cannot create Ward behavior evidence.

Missing Special Attention objects are intended S3 RED. Existing Guardian boundary assertions should PASS or route concrete ACL defects to S2.

- [ ] **Step 2: Run single-file RED twice**

Run: `npm exec --package=supabase@2.109.1 -- supabase test db --local supabase/tests/s1_care_authority_contract.sql`

Expected: Special Attention existence RED; Guardian non-impersonation assertions deterministic; no harness abort.

- [ ] **Step 3: Commit**

```powershell
git add supabase/tests/s1_care_authority_contract.sql scripts/s1-contract-catalog.mjs
git diff --cached --check
git commit -m "test: freeze care authority contracts"
```

---

### Task 5: AAB, iOS Native, and Tauri honesty contracts

**Files:**
- Create: `scripts/s1-platform-contract.test.mjs`
- Modify: `scripts/s1-contract-catalog.mjs`

**Interfaces:**
- Produces: `ADR0039-AAB-01..04`, `ADR0039-IOS-01..05`, `ADR0039-TAURI-01..03`, external BLOCKED rows.

- [ ] **Step 1: Write Vitest repository contracts**

Read real files with `readFileSync`. Required checks:

```js
test('ADR0039-AAB-01 store manifest has no AccessibilityService', () => {
  expect(androidManifest).not.toMatch(/BIND_ACCESSIBILITY_SERVICE|AppActivityService/)
})

test('ADR0039-IOS-01 background location is not used only as a relaunch hack', () => {
  expect(infoPlist).not.toMatch(/<string>location<\/string>[\s\S]*restart its guardian/)
})

test('ADR0039-TAURI-01 unavailable idle probe is an explicit non-operational state', () => {
  expect(tauriLib).toMatch(/idle_probe_available[\s\S]*"unavailable"/)
})
```

Also check:

- AAB build script exists and APK artifacts are not accepted as AAB evidence;
- full-screen intent/specialUse are optional capability paths, not unconditional readiness claims;
- iOS has native project/APNs entitlement, but silent push wording/code never claims guaranteed coverage;
- motion/HealthKit evidence cannot resolve alerts;
- no DeviceActivity/Family Controls entitlement => external S4 BLOCKED, not test PASS;
- Tauri exposes operational/unavailable capability and has autostart permission, but notification/background/update real-device evidence remains S4 BLOCKED;
- no platform file maps denied/unavailable capability to `Ready`.

- [ ] **Step 2: Run RED**

Run: `npm exec -- vitest run scripts/s1-platform-contract.test.mjs`

Expected: PASS for no AccessibilityService and Tauri unavailable state; RED for iOS background-location relaunch claim and any other explicit S0 contradiction. No parse/fixture error.

- [ ] **Step 3: Re-run for stability and commit**

```powershell
git add scripts/s1-platform-contract.test.mjs scripts/s1-contract-catalog.mjs
git diff --cached --check
git commit -m "test: freeze native platform honesty contracts"
```

---

### Task 6: Execute, classify, and publish the local S1 baseline

**Files:**
- Create: `docs/stabilization/s1-contract-baseline.md`
- Modify only if harness defects are found: S1 test/helper files from Tasks 1–5.

**Interfaces:**
- Consumes: complete catalog/runner and all S1 tests.
- Produces: hash-addressed baseline report; no runtime fix.

- [ ] **Step 1: Run catalog/runner unit tests**

Run: `npm exec -- vitest run scripts/s1-contract-catalog.test.mjs scripts/run-s1-contracts.test.mjs`

Expected: PASS.

- [ ] **Step 2: Run every S1 row locally**

Run: `node scripts/run-s1-contracts.mjs --local --out docs/stabilization/s1-contract-baseline.md`

Expected: runner exit nonzero only because catalog contains intentional RED; every row classified PASS/RED/BLOCKED, zero HARNESS_FAILURE.

- [ ] **Step 3: Re-run each RED file alone**

Run each pgTAP/Vitest command printed in the report twice. Expected same target assertion IDs and no order dependence.

- [ ] **Step 4: Verify write boundary and report**

```powershell
git diff 1437aef --name-only
git diff --check
rg -n "HARNESS_FAILURE|Bail out!|credential|token|password|@" docs/stabilization/s1-contract-baseline.md
```

Expected: only S1 tests/helpers/catalog/report/plan; zero secrets/personal identifiers; `HARNESS_FAILURE=0`; report explicitly says suite is not green.

- [ ] **Step 5: Run inherited non-DB gates only if test helpers affect them**

Run: `npm run typecheck` and `npm run build`.

Expected: PASS. Do not run release builds or modify generated platform files.

- [ ] **Step 6: Commit baseline**

```powershell
git add docs/stabilization/s1-contract-baseline.md
git diff --cached --check
git commit -m "docs: record S1 contract baseline"
```

---

### Task 7: Manager review, Brain writeback, and handoff

**Files:**
- Brain guarded write set only; no repository production file.

- [ ] Validate every catalog ID against ADR-0039 and the actual assertion.
- [ ] Reject any RED caused by compile error, missing fixture, clock, network, linked DB, or test order.
- [ ] Verify branch ancestry from `1437aef`, clean worktree, report SHA-256, and no runtime/migration/release diff.
- [ ] Record concise current truth: PASS/RED/BLOCKED totals and routes to S2/S3/S4.
- [ ] Finish guarded task only with fresh verification and complete delegation receipts.
- [ ] Do not begin S2/S3/S4 implicitly.

Expected: S1 is a stable test-only contract baseline; online KC unchanged.
