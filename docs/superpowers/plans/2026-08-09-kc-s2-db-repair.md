# KC S2 Database Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair proven Data API ACL drift, add safe local replay, and produce a root-cause classification for remaining S0 database failures without changing disputed product behavior.

**Architecture:** A test-first ACL pack drives one append-only `REVOKE ALL` migration. A separate Node replay wrapper creates a hash-pinned disposable Supabase tree, neutralizes five production URLs only in that copy, disables local cron through a disposable final migration, then runs local reset and pgTAP. Remaining failures are evidence, not targets for opportunistic repair.

**Tech Stack:** PostgreSQL 17, Supabase CLI 2.109.1, pgTAP, Node.js 22, Vitest 3.2.6, Git worktree.

## Global Constraints

- Base: `57e74c79348218110d6898736e7153369f32518d` on `codex/kc-s2-db-diagnosis`.
- Online KC, production Supabase, `main`, remotes, releases, versions, Edge Functions and native projects remain unchanged.
- Existing migrations and migration archives stay byte-for-byte unchanged.
- One new append-only migration only; create it using `supabase migration new` after the ACL test is RED.
- Do not change threshold, escalation, shadow runtime, cron definitions, alert lifecycle, S1 expectations, or inherited test expectations.
- Local test commands use `--local`; fresh reset runs only through the safe replay wrapper.
- Executor scratch and receipts use terse English; Manager final report uses plain Chinese.

---

### Task 1: Safe local replay wrapper

**Files:**
- Create: `scripts/s2-safe-db-replay-core.mjs`
- Create: `scripts/s2-safe-db-replay.test.mjs`
- Create: `scripts/s2-safe-db-replay.mjs`

**Interfaces:**
- Produces: `prepareSafeReplay({ repoRoot, disposableProjectRoot })`, `buildReplayCommands(root)`, `runSafeReplay({ repoRoot, spawnImpl })`.
- Constants: pinned baseline SHA-256, five exact URL replacements, disposable filename `20991231235959_local_test_disable_cron.sql`.

- [ ] **Step 1: Write wrapper unit tests**

Tests must prove: source baseline bytes unchanged; copied baseline has exactly five production-prefix replacements and no production hostname; unexpected source hash or replacement count fails closed; output escapes/symlink escapes are rejected; only the local cron-disable migration is added; commands are exactly local reset then local pgTAP and contain no linked/remote/push/repair operation; first failed child command stops the run.

- [ ] **Step 2: Run RED**

Run: `npm exec -- vitest run scripts/s2-safe-db-replay.test.mjs`

Expected: FAIL because the core module does not exist.

- [ ] **Step 3: Implement minimal wrapper**

The disposable migration body is exactly:

```sql
-- Local test safety only; generated in disposable copy, never production.
select cron.alter_job(jobid, null, null, null, null, false)
from cron.job;
```

The URL replacement maps the exact production prefix to `http://127.0.0.1:1/functions/v1/` only in the copied baseline. Use `fs/promises`, `realpath`, `relative`, `spawn`; do not add dependencies.

- [ ] **Step 4: Run GREEN**

Run: `npm exec -- vitest run scripts/s2-safe-db-replay.test.mjs`

Expected: PASS.

---

### Task 2: ACL regression test

**Files:**
- Create: `supabase/tests/s2_data_api_acl_repair.sql`

**Interfaces:**
- Consumes the fifteen-table contract in the S2 design.
- Produces deterministic pgTAP assertions `S2-ACL-01..06`.

- [ ] **Step 1: Write the failing pgTAP file**

Use `BEGIN`, `plan(6)`, `finish`, `ROLLBACK`. Assertions:

1. all eight table actions are absent for `anon/authenticated/service_role` across the fourteen internal tables;
2. no `PUBLIC` ACL entry exists on those tables;
3. all eight actions are absent for the three Data API roles on `gm_mutes`;
4. no `PUBLIC` ACL entry exists on `gm_mutes`;
5. all fifteen tables retain RLS enabled;
6. authenticated retains execute on `public.gm_mute_user(uuid,timestamptz,text)`.

- [ ] **Step 2: Run RED twice**

Run: `npm exec --package=supabase@2.109.1 -- supabase test db --local supabase/tests/s2_data_api_acl_repair.sql`

Expected: assertions 1 and 3 fail for `MAINTAIN`/broad `gm_mutes`; fixture/harness does not abort; identical twice.

---

### Task 3: Append-only ACL migration

**Files:**
- Create with CLI: `supabase/migrations/20260809123646_s2_internal_data_api_acl_repair.sql`

**Interfaces:**
- Consumes Task 2 RED.
- Produces zero direct table authority for the exact fifteen-table set.

- [ ] **Step 1: Confirm the Manager-created empty migration file**

The Manager already ran `npm exec --package=supabase@2.109.1 -- supabase migration new s2_internal_data_api_acl_repair`, producing `supabase/migrations/20260809123646_s2_internal_data_api_acl_repair.sql`. It must remain empty until Task 2 RED is observed.

- [ ] **Step 2: Add the minimal repair**

```sql
-- ADR-0039 / S2: private operational state stays RPC-only.
revoke all privileges on table
  public.account_gap_profiles,
  public.account_normal_bounds,
  public.account_threshold_shadow,
  public.alert_gap_profiles,
  public.alert_intervention_events,
  public.alert_judgment_evaluations,
  public.alert_judgment_shadow_decisions,
  public.alert_judgment_subject_contexts,
  public.alert_model_versions,
  public.alert_observation_coverage_intervals,
  public.alert_sleep_night_contexts,
  public.routine_mode_cohort_generations,
  public.routine_mode_cohort_invalidations,
  public.routine_mode_cohort_priors,
  public.gm_mutes
from public, anon, authenticated, service_role;
```

Do not add policies or grants. Existing RPC execute grants remain untouched.

- [ ] **Step 3: Apply locally and run GREEN**

Run migration locally only, then re-run `s2_data_api_acl_repair.sql` twice. Expected: 6/6 PASS both times.

- [ ] **Step 4: Run inherited ACL-bearing files**

Run the six files reproduced before repair. Expected: their ACL assertions pass; unrelated hash/activation/trigger failures remain unchanged.

---

### Task 4: Full safe replay and diagnosis

**Files:**
- Create: `docs/stabilization/s2-db-root-cause-diagnosis.md`

**Interfaces:**
- Consumes safe replay output, full pgTAP output, S0/S1 baselines.
- Produces one row per inherited failing file: `FIXED`, `CONFLICT`, `DIAGNOSED-UNFIXED`, or `BLOCKED`.

- [ ] **Step 1: Run safe replay**

Run: `node scripts/s2-safe-db-replay.mjs`

Expected: disposable copy verified; no production hostname remains; reset/test local only. pgTAP may exit nonzero only for recorded non-ACL failures.

- [ ] **Step 2: Pin earliest remaining failures**

Run individually: `routine_safety.sql`, `adaptive_alert_routine_modes.sql`, `routine_mode_cohort_priors.sql`, `adaptive_alert_shadow_operational_schema.sql`. Record the first failing assertion and owning function/fixture branch. No edits.

- [ ] **Step 3: Write report**

Report exact totals, commands, output hashes, fixed ACL rows, remaining semantic conflicts, local-cron safety finding, and zero-production boundary. Do not call the suite green unless all non-conflict failures pass.

---

### Task 5: Verification and guarded handoff

**Files:**
- Brain guarded write set only after repository verification.

- [ ] Run safe replay wrapper tests, S2 pgTAP twice, inherited ACL files, full local pgTAP, typecheck, build, diff-check and source-hash checks.
- [ ] Verify only one new migration and S2 tests/scripts/spec/plan/report changed.
- [ ] Cross-provider integrated audit reads live diff and evidence; expected verdict is unprescribed.
- [ ] Record only durable truth and unresolved decision packet; no push/deploy/release.
