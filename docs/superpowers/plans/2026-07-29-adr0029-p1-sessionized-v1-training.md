# ADR-0029 P1 Sessionized v1 Training Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit `ingest_version=1` historical behavior pings to adaptive replay/shadow profile training only, after sessionization, through an auditable read-only normalized source.

**Architecture:** Add one owner-only `private.normalized_behavior_training_sessions(...)` function. It preserves the existing canonical-v2 `private.qualified_behavior_sessions(...)` path unchanged, adds an opt-in historical-v1 branch, and emits explicit source-version and provenance fields. Replace only `private.rebuild_alert_gap_profiles(...)` so profile training can consume v1 gaps; candidate evaluation, replay evaluation units, heartbeat, alert resolution, check-ins, and every live function remain canonical-v2-only.

**Tech Stack:** PostgreSQL 15/17-compatible SQL, Supabase CLI 2.110.0, pgTAP, existing local replay harness.

## Global Constraints

- ADR-0029 P1 only; do not implement P2 `known_idle` / `unknown` / `outage` weighting.
- Append-only migration `supabase/migrations/20260729171000_adr0029_p1_sessionized_v1_training.sql`; do not edit historical migrations.
- Preserve every `public.behavior_pings` row and its original `ingest_version`.
- Historical v1 is training-only. It must not refresh `device_state`, resolve alerts, satisfy check-ins, become a replay evaluation unit, or affect `private.silence_threshold`.
- Existing model versions remain canonical-v2-only unless their hashed config explicitly sets `sessionization.historical_v1_policy` to `sessionized_training_only_v1`.
- Historical v1 contributes only to `personal_global`; no current timezone, coverage, intervention, or sleep context may be projected backward.
- A gap may never bridge v1 and v2 provenance domains.
- No new table, trigger, publication, scheduler, public RPC, dependency, deployment, or release.
- New `SECURITY DEFINER` code stays in `private`, pins `search_path=''` and `TimeZone=UTC`, schema-qualifies every object, and revokes execution from `PUBLIC`, `anon`, `authenticated`, and `service_role`.
- Incremental spend remains US$0.

---

### Task 1: Lock the failing pgTAP contract

**Files:**
- Create: `supabase/tests/adr0029_p1_normalized_training_evidence.sql`
- Test: `supabase/tests/adr0029_p1_normalized_training_evidence.sql`

**Interfaces:**
- Consumes: `public.behavior_pings`, `public.alert_model_versions`, `private.qualified_behavior_sessions(uuid,timestamptz,timestamptz,uuid)`, `private.rebuild_alert_gap_profiles(uuid,date)`.
- Produces: A RED contract for `private.normalized_behavior_training_sessions(uuid,timestamptz,timestamptz,uuid)` and v1-backed `personal_global` profiles.

- [ ] **Step 1: Create isolated fixtures and literal expectations**

Use one replay model whose config contains:

```sql
"sessionization": {
  "gap_minutes": 30,
  "per_user_day_gap_cap": 8,
  "training_horizon_days": 35,
  "intervention_window_minutes": 30,
  "historical_v1_policy": "sessionized_training_only_v1"
}
```

Create a second otherwise-identical replay model without the policy key. Insert five v1 rows for one user at `00:00`, `00:05`, `00:10`, `04:00`, and `04:05` UTC. The hand-derived expected sessions are `[00:00,00:10]` with count 3 and `[04:00,04:05]` with count 2; the completed gap is exactly 230 minutes.

- [ ] **Step 2: Assert the normalized session contract**

Add pgTAP assertions equivalent to:

```sql
SELECT results_eq(
  $$
    SELECT session_start, session_end, evidence_count,
           source_ingest_version, training_provenance, context_key
    FROM private.normalized_behavior_training_sessions(
      '29100000-0000-4000-8000-000000000001',
      '2026-07-01 00:00+00',
      '2026-07-03 00:00+00',
      '29100000-0000-4000-8000-000000000010'
    )
    ORDER BY session_start
  $$,
  $$
    VALUES
      ('2026-07-01 00:00+00'::timestamptz,
       '2026-07-01 00:10+00'::timestamptz,
       3, 1::smallint, 'historical_v1_training_only'::text, NULL::text),
      ('2026-07-01 04:00+00'::timestamptz,
       '2026-07-01 04:05+00'::timestamptz,
       2, 1::smallint, 'historical_v1_training_only'::text, NULL::text)
  $$,
  'dense historical v1 rows collapse into provenance-marked training sessions'
);
```

Also assert both `provenance_sha256` values match `^[a-f0-9]{64}$`, are distinct between sessions, and are deterministic across two identical calls.

- [ ] **Step 3: Assert opt-in, live isolation, and profile behavior**

Add assertions that:

```sql
-- No policy key means no historical v1 admission.
SELECT is_empty($$
  SELECT *
  FROM private.normalized_behavior_training_sessions(
    '29100000-0000-4000-8000-000000000001',
    '2026-07-01 00:00+00',
    '2026-07-03 00:00+00',
    '29100000-0000-4000-8000-000000000020'
  )
$$, 'historical v1 admission is explicit per model version');

-- The canonical evaluator-facing source remains v2-only.
SELECT is_empty($$
  SELECT *
  FROM private.qualified_behavior_sessions(
    '29100000-0000-4000-8000-000000000001',
    '2026-07-01 00:00+00',
    '2026-07-03 00:00+00',
    '29100000-0000-4000-8000-000000000010'
  )
$$, 'v1 never becomes evaluator-facing liveness evidence');
```

Run `private.rebuild_alert_gap_profiles` for the opt-in model and assert one `personal_global` sample with `neutral_p95_minutes=230`. Assert no non-global context profile is created from v1. Run the control model and assert no profile is created.

- [ ] **Step 4: Assert immutability and authority boundaries**

Capture full-row hashes for `behavior_pings`, `device_state`, `alerts`, `alert_events`, and `notifications` before rebuild. Assert identical hashes after rebuild. Assert no adaptive Cron/publication/trigger is introduced and `private.silence_threshold` retains the pre-test definition hash.

Set each Data API role and assert permission denied for the normalized function:

```sql
SELECT throws_ok(
  $$ SET LOCAL ROLE authenticated;
     SELECT * FROM private.normalized_behavior_training_sessions(
       '29100000-0000-4000-8000-000000000001',
       '2026-07-01 00:00+00',
       '2026-07-03 00:00+00',
       '29100000-0000-4000-8000-000000000010'
     ) $$,
  '42501'::char(5),
  NULL,
  'authenticated cannot call the owner-only training source'
);
```

- [ ] **Step 5: Run RED and preserve the expected failure**

Run:

```powershell
npm run db:replay:compat -- --test supabase/tests/adr0029_p1_normalized_training_evidence.sql
```

Expected: FAIL because `private.normalized_behavior_training_sessions(...)` does not exist. Do not accept syntax, fixture, permission, or infrastructure failures as RED.

### Task 2: Implement the read-only normalized session source

**Files:**
- Modify: `supabase/migrations/20260729171000_adr0029_p1_sessionized_v1_training.sql`
- Test: `supabase/tests/adr0029_p1_normalized_training_evidence.sql`

**Interfaces:**
- Consumes: model config/hash/status, `private.qualified_behavior_sessions(...)`, and immutable `behavior_pings` rows.
- Produces:

```sql
private.normalized_behavior_training_sessions(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  session_start timestamptz,
  session_end timestamptz,
  context_key text,
  evidence_count integer,
  source_ingest_version smallint,
  training_provenance text,
  provenance_sha256 text,
  quality_state text
)
```

- [ ] **Step 1: Add the fail-closed config contract**

Add a named constraint allowing the new key to be absent or one of the two explicit values:

```sql
ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_historical_v1_policy_check
  CHECK (
    (config #> '{sessionization,historical_v1_policy}') IS NULL
    OR (
      jsonb_typeof(config #> '{sessionization,historical_v1_policy}') = 'string'
      AND config #>> '{sessionization,historical_v1_policy}'
        IN ('disabled', 'sessionized_training_only_v1')
    )
  );
```

- [ ] **Step 2: Implement canonical-v2 passthrough**

Validate version existence, `status IN ('replay','shadow')`, `evidence_version='canonical-v2'`, and exact config SHA-256. Call `private.qualified_behavior_sessions(...)`; emit `source_ingest_version=2`, `training_provenance='canonical_v2'`, and a deterministic SHA-256 over version, user, session bounds, context, count, and quality.

- [ ] **Step 3: Implement historical-v1 sessionization**

Only when the policy equals `sessionized_training_only_v1`, read v1 rows using their original `at` timestamp:

```sql
WITH admitted AS (
  SELECT p.id, p.at, p.received_at, p.ingest_version, p.source, p.kind
  FROM public.behavior_pings AS p
  WHERE p.user_id = _user_id
    AND p.ingest_version = 1
    AND p.at >= _from
    AND p.at < _to
),
marked AS (
  SELECT admitted.*,
    CASE
      WHEN lag(at) OVER (ORDER BY at, id) IS NULL
        OR at - lag(at) OVER (ORDER BY at, id)
          > make_interval(mins => _gap_minutes)
      THEN 1 ELSE 0
    END AS starts_session
  FROM admitted
)
```

Aggregate each session. Emit `context_key=NULL`, `source_ingest_version=1`, `training_provenance='historical_v1_training_only'`, `quality_state='valid'`, and a deterministic SHA-256 binding every source row’s `id`, UTC `at`, UTC `received_at`, original `ingest_version`, `source`, and `kind`. Never update or backfill source rows.

- [ ] **Step 4: Lock ownership and privileges**

Define the function as `STABLE SECURITY DEFINER SET search_path='' SET TimeZone='UTC'`. Revoke execution from `PUBLIC`, `anon`, `authenticated`, and `service_role`. Add a comment stating that it is an ADR-0029 P1 training-only source.

### Task 3: Wire normalized sessions into profile training only

**Files:**
- Modify: `supabase/migrations/20260729171000_adr0029_p1_sessionized_v1_training.sql`
- Test: `supabase/tests/adr0029_p1_normalized_training_evidence.sql`

**Interfaces:**
- Consumes: `private.normalized_behavior_training_sessions(...)`.
- Produces: A replacement `private.rebuild_alert_gap_profiles(uuid,date)` with the same signature, owner, ACL, return contract, idempotency, and canonical-v2 behavior.

- [ ] **Step 1: Enumerate opt-in historical users**

Retain coverage-backed users and union historical v1 users only when the model config policy is enabled:

```sql
WITH users AS (
  SELECT DISTINCT c.user_id
  FROM public.alert_observation_coverage_intervals AS c
  WHERE c.version_id = _version_id
    AND c.starts_at < _cutoff
    AND c.ends_at > _from
  UNION
  SELECT DISTINCT p.user_id
  FROM public.behavior_pings AS p
  WHERE _historical_v1_policy = 'sessionized_training_only_v1'
    AND p.ingest_version = 1
    AND p.at >= _from
    AND p.at < _cutoff
)
```

- [ ] **Step 2: Prevent cross-provenance gaps**

Pair sessions using:

```sql
lead(session_start) OVER (
  PARTITION BY user_id, source_ingest_version, training_provenance
  ORDER BY session_start
)
```

Carry current and next session provenance hashes. A v1 session can pair only with another v1 session; a v2 session can pair only with another v2 session.

- [ ] **Step 3: Preserve strict canonical gaps and add historical gaps**

Keep the existing coverage/intervention validation for canonical-v2. Add a historical branch that admits only paired, valid `historical_v1_training_only` sessions. Assign `timezone='UTC'`, `utc_offset_minutes=0`, no coverage ID, no sleep subtraction, and a deterministic training-gap provenance hash over both session hashes and bounds. Do not infer historical timezone, coverage, intervention, sleep, or P2 observability state.

- [ ] **Step 4: Restrict v1 to global profiles and bind provenance**

Every selected gap contributes to `personal_global`. Only canonical-v2 gaps may create context-key profiles:

```sql
SELECT ... FROM selected
UNION ALL
SELECT ... FROM selected
WHERE source_ingest_version = 2
  AND training_provenance = 'canonical_v2'
```

Include source version, training provenance, both session hashes, and training-gap hash in `gap_inputs`; therefore `input_sha256` and `profile_sha256` change whenever admitted v1 evidence changes.

- [ ] **Step 5: Preserve the public behavior of rebuild**

Keep the existing advisory lock, temp-table lifecycle, daily cap, p95 calculation, support/freshness quality, idempotent upsert/delete, return keys, volatility, owner, and revoked ACL. Do not alter `private.qualified_behavior_sessions`, `private.resolve_alert_candidate`, `private.run_adaptive_alert_replay`, or any live function.

### Task 4: Verify GREEN, regressions, and scope

**Files:**
- Modify: `docs/superpowers/plans/2026-07-29-adr0029-p1-sessionized-v1-training.md`
- Verify: `supabase/migrations/20260729171000_adr0029_p1_sessionized_v1_training.sql`
- Verify: `supabase/tests/adr0029_p1_normalized_training_evidence.sql`

**Interfaces:**
- Consumes: final migration and pgTAP suite.
- Produces: Local-only evidence sufficient for Brain write-back and human review.

- [ ] **Step 1: Run focused GREEN**

```powershell
npm run db:replay:compat -- --test supabase/tests/adr0029_p1_normalized_training_evidence.sql
```

Expected: the focused P1 pgTAP file passes.

- [ ] **Step 2: Run complete database replay**

```powershell
npm run db:replay:compat
```

Expected: all migration replay and pgTAP files pass, including P3.

- [ ] **Step 3: Run application gates**

```powershell
npm test
npm run typecheck
npm run local:gate:static
```

Expected: 56+ Vitest files pass, typecheck exits 0, and the static gate passes with only the existing missing Tauri signing-key warning.

- [ ] **Step 4: Run database lint and security inspection**

```powershell
npx supabase db lint --local --level error
git diff --check
git diff --stat
git status --short
```

Classify only pre-existing lint findings as baseline; do not expand scope to fix them. Inspect function ownership, `prosecdef`, `provolatile`, `proconfig`, ACL, and absence of triggers/publications/Cron.

- [ ] **Step 5: Self-review scope**

Confirm the final diff contains only:

```text
docs/superpowers/plans/2026-07-29-adr0029-p1-sessionized-v1-training.md
supabase/migrations/20260729171000_adr0029_p1_sessionized_v1_training.sql
supabase/tests/adr0029_p1_normalized_training_evidence.sql
```

Confirm no production migration, deploy, scheduler, version activation, or release occurred.

- [ ] **Step 6: Commit**

```powershell
git add -- docs/superpowers/plans/2026-07-29-adr0029-p1-sessionized-v1-training.md supabase/migrations/20260729171000_adr0029_p1_sessionized_v1_training.sql supabase/tests/adr0029_p1_normalized_training_evidence.sql
git commit -m "feat(db): admit sessionized v1 training evidence"
```

Then update the authorized Brain project truth and Dev Log, record verification plus `learning_review`, run `brain-task check`, and finish `KC-ADR29-P1-001`.
