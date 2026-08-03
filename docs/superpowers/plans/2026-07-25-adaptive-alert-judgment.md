# Adaptive Alert Judgment Replay and Shadow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a privacy-qualified three-Routine-mode cohort prior, personal p95 hierarchy, dynamic-sleep candidate accounting, deterministic historical replay, and a non-notifying shadow recorder without changing live alert behavior.

**Architecture:** Append-only PostgreSQL migrations create a versioned candidate-model boundary. Canonical-v2 evidence is sessionized, accepted sleep/quiet intervals are subtracted, personal/context p95 profiles and robust per-mode cohort priors are built, and one deterministic evaluator serves both replay and shadow. The existing ADR-0022 threshold and alert state machine remain the only live authority; no migration in this plan schedules the shadow writer or allows it to mutate alerts.

**Tech Stack:** Supabase PostgreSQL 17, PL/pgSQL, pgTAP, React 19, TypeScript 5.8, Vitest 3, Vite 6.

## Global Constraints

- Binding decision: Keep Contact ADR-0023.
- Canonical Routine modes: `regular_9to5`, `semester_break`, `shift_irregular`.
- Legacy mapping: `student → semester_break`; `shift_worker|flexible → shift_irregular`.
- Candidate hierarchy: comparable-context personal p95 → personal-global p95 → Routine-mode cohort prior → deterministic emergency failsafe.
- Cohort contributors require `consent_data_sharing=true` and qualified canonical evidence; aggregate consumers need not contribute.
- Aggregate per-user neutral p95 values; never pool or average raw heartbeat frequency.
- Sensitivity remains a separate additive tool: `high +0m`, `balanced +45m`, `low +90m`.
- Guardian confirmation is not protected-user activity, does not train, and does not reset effective silence; retain the existing 30-minute re-alert state machine.
- Configured sleep is an anchor. Absence, outage, missing evidence, and Guardian confirmation cannot extend sleep.
- Replay and shadow may write only candidate/evaluation metadata. They cannot create, delay, pause, upgrade, resolve, or notify an alert.
- No location, contact content, message content, window content, or new external AI dependency.
- New database changes are append-only migrations. Never edit an existing migration.
- All tables remain in `public`; business-logic functions remain in `private`. Internal tables use RLS plus explicit privilege revocation.
- Automated tests assert observable database/frontend behavior. Source regex scans are mechanical defense-in-depth checks only, not unit tests.
- No production migration, cron enablement, deploy, release, or live promotion in this implementation plan.
- Incremental external spend remains `US$0`.
- Every implementation task uses RED → GREEN → regression verification and ends in a scoped local commit.

---

## File and Interface Map

| File | Responsibility |
|---|---|
| `src/features/baseline/routineMode.ts` | Canonical frontend Routine-mode type and legacy normalization |
| `src/features/baseline/routineMode.test.ts` | Frontend taxonomy/normalization contract |
| `src/features/baseline/routineModeCopy.ts` | Copy keyed only by canonical mode |
| `src/features/profile/profileApi.ts` | Normalize server values before returning `RoutineProfile` |
| `supabase/migrations/20260725160000_canonicalize_routine_modes.sql` | DB normalization, preflight, constraint, invalidation trigger |
| `supabase/migrations/20260725161000_adaptive_alert_shadow_schema.sql` | Version, profile, cohort, shadow, replay/evaluation tables and RLS |
| `supabase/migrations/20260725162000_adaptive_sleep_candidate.sql` | Persisted nightly sleep-anchor context and positive-evidence candidate intervals |
| `supabase/migrations/20260725163000_adaptive_alert_gap_profiles.sql` | Coverage/intervention provenance, qualified sessions, effective gaps, personal/context p95 profiles |
| `supabase/migrations/20260725164000_routine_mode_cohort_priors.sql` | Consent-qualified robust cohort builder |
| `supabase/migrations/20260725165000_adaptive_alert_candidate_evaluator.sql` | Exact fallback hierarchy and decision snapshot |
| `supabase/migrations/20260725170000_adaptive_alert_replay.sql` | Historical replay and aggregate report |
| `supabase/migrations/20260725171000_adaptive_alert_shadow_recorder.sql` | Unscheduled non-notifying current-time recorder |
| `supabase/tests/adaptive_alert_routine_modes.sql` | DB taxonomy and consent invalidation tests |
| `supabase/tests/adaptive_alert_shadow_schema.sql` | RLS, grants, constraints, and no-live-FK schema tests |
| `supabase/tests/adaptive_sleep_candidate.sql` | Positive-evidence/absence-safe sleep tests |
| `supabase/tests/adaptive_alert_gap_profiles.sql` | Sessionization, sleep exclusion, censoring, quality, p95 tests |
| `supabase/tests/routine_mode_cohort_priors.sql` | Robust per-user aggregation and privacy/support tests |
| `supabase/tests/adaptive_alert_candidate_evaluator.sql` | Hierarchy, sensitivity, fallback, Guardian separation tests |
| `supabase/tests/adaptive_alert_replay.sql` | Deterministic historical comparison tests |
| `supabase/tests/adaptive_alert_shadow_recorder.sql` | Zero live-side-effect and idempotency tests |

### Database interfaces locked by this plan

```sql
private.canonical_routine_mode(_value text) returns text

private.candidate_sleep_intervals(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
) returns table (
  starts_at timestamptz,
  ends_at timestamptz,
  basis text,
  confidence double precision,
  provenance jsonb
)

private.qualified_behavior_sessions(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
) returns table (
  session_start timestamptz,
  session_end timestamptz,
  context_key text,
  evidence_count integer,
  quality_state text
)

private.rebuild_alert_gap_profiles(
  _version_id uuid,
  _through_date date
) returns jsonb

private.rebuild_routine_mode_cohort_priors(
  _version_id uuid,
  _through_date date
) returns jsonb

private.resolve_alert_candidate(
  _user_id uuid,
  _evaluated_at timestamptz,
  _version_id uuid
) returns jsonb

private.run_alert_judgment_replay(
  _version_id uuid,
  _from timestamptz,
  _to timestamptz
) returns jsonb

private.record_alert_judgment_shadow(
  _version_id uuid,
  _evaluated_at timestamptz
) returns jsonb
```

`resolve_alert_candidate` returns this stable JSON contract:

```json
{
  "version_id": "uuid",
  "evaluator_version": "adaptive_candidate_v1",
  "evaluated_at": "timestamptz",
  "evidence_cutoff": "timestamptz",
  "replayable": true,
  "unreplayable_reason": null,
  "basis": "personal_context|personal_global|routine_cohort|deterministic_emergency",
  "context_key": "versioned string",
  "neutral_threshold_minutes": 0,
  "sensitivity_buffer_minutes": 0,
  "unclamped_candidate_threshold_minutes": 0,
  "candidate_floor_minutes": 0,
  "candidate_ceiling_minutes": 0,
  "candidate_cap_reason": "none|floor|ceiling|emergency_exempt",
  "candidate_threshold_minutes": 0,
  "effective_silence_minutes": 0,
  "candidate_deadline": "timestamptz",
  "deadline_basis": "known_interval_inversion|no_future_exclusion",
  "would_alert": false,
  "confidence": 0,
  "quality_state": "valid|low_support|stale|drift_invalid|coverage_invalid",
  "fallback_path": ["personal_context", "personal_global", "routine_cohort"],
  "sleep_interval_provenance": [],
  "selected_source_sha256": "sha256|null",
  "subject_context_sha256": "sha256",
  "decision_provenance": {},
  "provenance_sha256": "sha256",
  "guardian_used_as_activity": false
}
```

When `replayable=false`, the exact shape is the same 28-key object above, with:

- `version_id`, `evaluator_version`, `evaluated_at`, and `evidence_cutoff` present;
- `replayable=false` and one stable `unreplayable_reason`;
- `basis`, `context_key`, all neutral/buffer/unclamped/floor/ceiling/cap/final
  threshold fields, `effective_silence_minutes`, `candidate_deadline`,
  `deadline_basis`, `would_alert`, `confidence`, `selected_source_sha256`, and
  `subject_context_sha256` all JSON `null`;
- `quality_state='coverage_invalid'`;
- `fallback_path=[]`, `sleep_interval_provenance=[]`;
- `decision_provenance` a non-null canonical object containing only
  `version_id`, `evaluator_version`, UTC `evaluated_at`, UTC `evidence_cutoff`,
  `replayable=false`, and `unreplayable_reason`;
- `provenance_sha256` the lowercase SHA-256 of canonical
  `decision_provenance::text`;
- `guardian_used_as_activity=false`.

No failure result may carry an emergency substitute or partial decision.
Replay counts that result; the shadow recorder does not insert it into the
non-null decision table.

The exact unreplayable enum is:
`invalid_version_status`, `config_hash_mismatch`,
`unsupported_evidence_version`, `missing_subject_context`,
`ambiguous_subject_context`, `subject_context_provenance_invalid`, and
`missing_qualified_session`. Invalid personal/cohort tiers are not unreplayable:
they follow the fallback ladder; corrupt version/context/session truth is.

---

### Task 1: Canonicalize the three Routine modes

**Files:**
- Create: `src/features/baseline/routineMode.ts`
- Create: `src/features/baseline/routineMode.test.ts`
- Modify: `src/features/baseline/routineModeCopy.ts`
- Modify: `src/features/baseline/RoutineSettings.tsx`
- Modify: `src/features/profile/profileApi.ts`
- Create: `supabase/migrations/20260725160000_canonicalize_routine_modes.sql`
- Create: `supabase/tests/adaptive_alert_routine_modes.sql`

**Interfaces:**
- Produces: `RoutineMode`, `ROUTINE_MODES`, `normalizeRoutineMode(value)`.
- Produces: `private.canonical_routine_mode(text)`.
- Produces: per-mode cohort invalidation timestamps used by Task 5.

- [x] **Step 1: Write the failing frontend taxonomy test**

```ts
import { describe, expect, it } from 'vitest'
import {
  ROUTINE_MODES,
  normalizeRoutineMode,
} from '@/features/baseline/routineMode'

describe('Routine mode taxonomy', () => {
  it('uses the three human-accepted canonical values', () => {
    expect(ROUTINE_MODES).toEqual([
      'regular_9to5',
      'semester_break',
      'shift_irregular',
    ])
  })

  it.each([
    ['regular_9to5', 'regular_9to5'],
    ['semester_break', 'semester_break'],
    ['student', 'semester_break'],
    ['shift_irregular', 'shift_irregular'],
    ['shift_worker', 'shift_irregular'],
    ['flexible', 'shift_irregular'],
    ['unknown', 'regular_9to5'],
  ] as const)('normalizes %s to %s', (input, expected) => {
    expect(normalizeRoutineMode(input)).toBe(expected)
  })
})
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```powershell
npm test -- src/features/baseline/routineMode.test.ts
```

Expected: FAIL because `routineMode.ts` does not exist.

- [x] **Step 3: Implement the frontend contract**

```ts
export const ROUTINE_MODES = [
  'regular_9to5',
  'semester_break',
  'shift_irregular',
] as const

export type RoutineMode = (typeof ROUTINE_MODES)[number]

export function normalizeRoutineMode(value: unknown): RoutineMode {
  if (value === 'semester_break' || value === 'student') return 'semester_break'
  if (
    value === 'shift_irregular' ||
    value === 'shift_worker' ||
    value === 'flexible'
  ) return 'shift_irregular'
  return 'regular_9to5'
}
```

Replace the duplicate union in `routineModeCopy.ts`, type the settings state as `RoutineMode`, and normalize the value returned by `getRoutineProfile()`. Do not change visible labels or descriptions.

- [x] **Step 4: Write the failing pgTAP taxonomy test**

```sql
begin;
select plan(9);

select is(private.canonical_routine_mode('regular_9to5'), 'regular_9to5');
select is(private.canonical_routine_mode('semester_break'), 'semester_break');
select is(private.canonical_routine_mode('student'), 'semester_break');
select is(private.canonical_routine_mode('shift_irregular'), 'shift_irregular');
select is(private.canonical_routine_mode('shift_worker'), 'shift_irregular');
select is(private.canonical_routine_mode('flexible'), 'shift_irregular');
select is(private.canonical_routine_mode('bad-value'), 'regular_9to5');
select has_check('public', 'profiles', 'profiles_routine_pattern_canonical');
select function_privs_are(
  'private', 'canonical_routine_mode', array['text'],
  'authenticated', array[]::text[]
);

select * from finish();
rollback;
```

- [x] **Step 5: Implement the append-only taxonomy migration**

The migration must:

1. abort if any existing non-null value is outside the six known canonical/legacy values;
2. map the three legacy values;
3. add `profiles_routine_pattern_canonical`;
4. create an immutable normalizer;
5. create `public.routine_mode_cohort_invalidations(routine_mode text primary key, invalidated_at timestamptz)`, enable RLS, and create a trigger that invalidates the old and new normalized modes when `routine_pattern` or `consent_data_sharing` changes;
6. revoke all function/table access from `PUBLIC`, `anon`, and `authenticated`.

Core preflight:

```sql
do $$
begin
  if exists (
    select 1
    from public.profiles
    where routine_pattern not in (
      'regular_9to5', 'semester_break', 'shift_irregular',
      'student', 'shift_worker', 'flexible'
    )
  ) then
    raise exception 'unknown routine_pattern blocks canonical migration';
  end if;
end;
$$;
```

- [x] **Step 6: Run frontend and database tests**

```powershell
npm test -- src/features/baseline/routineMode.test.ts src/features/baseline/routineModeCopy.test.ts
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: all taxonomy tests PASS.

- [x] **Step 7: Commit**

```powershell
git add src/features/baseline/routineMode.ts src/features/baseline/routineMode.test.ts src/features/baseline/routineModeCopy.ts src/features/baseline/RoutineSettings.tsx src/features/profile/profileApi.ts supabase/migrations/20260725160000_canonicalize_routine_modes.sql supabase/tests/adaptive_alert_routine_modes.sql
git commit -m "feat(routine): canonicalize three routine modes"
```

---

### Task 2: Create the versioned shadow-only data boundary

**Files:**
- Create: `supabase/migrations/20260725161000_adaptive_alert_shadow_schema.sql`
- Create: `supabase/tests/adaptive_alert_shadow_schema.sql`

**Interfaces:**
- Produces: `alert_model_versions`, `alert_gap_profiles`, `routine_mode_cohort_priors`, `alert_judgment_shadow_decisions`, and `alert_judgment_evaluations`.
- Consumed by: Tasks 3–8.

- [x] **Step 1: Write failing pgTAP schema and privilege tests**

Assert all five tables exist, have RLS enabled, and expose no privileges to `anon` or `authenticated`. Assert:

```sql
select col_is_pk('public', 'alert_model_versions', 'id');
select has_column('public', 'alert_gap_profiles', 'context_key');
select has_column('public', 'routine_mode_cohort_priors', 'contributor_count');
select has_column('public', 'alert_judgment_shadow_decisions', 'fallback_path');
select hasnt_column('public', 'routine_mode_cohort_priors', 'user_id');
select hasnt_column('public', 'alert_judgment_evaluations', 'user_id');
```

Also assert no shadow table has a trigger calling alert/push functions and no foreign key points to `alerts`, `alert_events`, or `notifications`.

- [x] **Step 2: Extend the failing behavior-based boundary test**

In pgTAP, inspect the applied database catalogs and assert:

- no trigger owned by any new shadow table calls an alert, notification, push, or escalation function;
- no foreign key from a shadow table targets `alerts`, `alert_events`, or `notifications`;
- no `cron.job` row schedules an adaptive candidate rebuild, replay, evaluator, or shadow recorder;
- representative owner-only inserts into each shadow table in a transaction leave
  live-table counts and stable hashes unchanged. Task 2 has no callable rebuild
  boundary yet; behavior-based function assertions begin with Tasks 4–8.

Keep source-regex checks out of Vitest; Task 9 runs them as a separate mechanical defense-in-depth command.

- [x] **Step 3: Run focused tests and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: FAIL because schema migration and tables do not exist.

- [x] **Step 4: Implement the schema migration**

Use explicit checks:

```sql
create table public.alert_model_versions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  status text not null check (status in ('draft', 'replay', 'shadow', 'retired')),
  config jsonb not null,
  config_sha256 text not null check (config_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_version text not null,
  created_at timestamptz not null default now(),
  shadow_enabled_at timestamptz,
  check (status <> 'shadow' or shadow_enabled_at is not null)
);
```

`config` must carry versioned values for sessionization, context definition, support/span gates, recency, cohort privacy support, sensitivity buffers, candidate threshold bounds, and sleep-compensation bounds. Lock the field names used by Tasks 3–6 (`sessionization.gap_minutes`, `sessionization.per_user_day_gap_cap`, `context.definition_version`, the personal/cohort support and freshness fields, `candidate_bounds.floor_minutes|ceiling_minutes`, and the six sleep-compensation bound/evidence fields). Do not seed any draft, replay, active, or shadow version in the migration.

`alert_judgment_shadow_decisions` must use a unique key `(version_id, user_id, evaluated_minute)` for idempotency and store `evaluated_minute` as `date_trunc('minute', evaluated_at)`.

- [x] **Step 5: Apply RLS and revocations**

Enable RLS on every table and create no policies in this phase. Revoke every
table privilege from `PUBLIC`, `anon`, `authenticated`, and `service_role`;
later candidate functions remain owner-only `SECURITY DEFINER SET search_path=''`
for local replay. Do not grant `service_role` private-schema access here: that
would require a separate audit and hardening of existing private functions.

- [x] **Step 6: Run schema tests**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: PASS, with no cron or live-side-effect path.

- [x] **Step 7: Commit**

```powershell
git add supabase/migrations/20260725161000_adaptive_alert_shadow_schema.sql supabase/tests/adaptive_alert_shadow_schema.sql
git commit -m "feat(alerts): add shadow-only adaptive model schema"
```

---

### Task 3: Derive absence-safe candidate sleep intervals

**Files:**
- Create: `supabase/migrations/20260725162000_adaptive_sleep_candidate.sql`
- Create: `supabase/tests/adaptive_sleep_candidate.sql`
- Modify: `supabase/tests/adaptive_alert_shadow_schema.sql`

**Interfaces:**
- Consumes: `alert_model_versions.config`.
- Produces: owner-only `alert_sleep_night_contexts` qualification metadata for prospective replay/shadow.
- Produces: `private.candidate_sleep_intervals(...)`.
- Consumed by: Tasks 4, 6, and 7.

- [x] **Step 1: Write RED tests for configured-anchor behavior**

Create users plus persisted nightly-context fixtures covering:

1. configured `23:00–07:00`, no activity: interval stays exactly configured;
2. qualified activity at `23:40`: start may move later only within configured version bounds;
3. qualified activity at `06:20`: wake may move earlier;
4. no morning activity: wake cannot move later;
5. outage/coverage-invalid evidence: direct positive activity may only narrow the configured interval; it can never extend the wake boundary;
6. Guardian confirmation/manual external evidence: no movement;
7. timezone shift beyond configured tolerance: return anchor/no prospective extension;
8. repeated positive late-activity clusters: only future nights receive bounded later wake compensation.
9. no persisted nightly context for a historical date: return no exclusion rather than projecting the current setting backward.

Key assertion:

```sql
select results_eq(
  $$
  select starts_at, ends_at, basis
  from private.candidate_sleep_intervals(
    :'user_without_morning_activity',
    '2026-07-01 12:00+00',
    '2026-07-02 12:00+00',
    :'version_id'
  )
  order by starts_at
  $$,
  $$
  values
    ('2026-07-01 23:00+00'::timestamptz, '2026-07-02 07:00+00'::timestamptz, 'configured_anchor'::text)
  $$,
  'absence never extends the configured wake boundary'
);
```

- [x] **Step 2: Run database tests and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: function missing.

- [x] **Step 3: Implement the candidate interval function**

The function must:

- read only persisted nightly context (`timezone`, local start/end, UTC anchor and offset) captured no later than that night's anchor; current settings must not be projected backward into historical replay;
- create `public.alert_sleep_night_contexts` in this append-only migration with RLS, no policy, and zero privileges for `PUBLIC`, `anon`, `authenticated`, and `service_role`;
- add `sleep_compensation.lookback_nights` and `sleep_compensation.min_late_events_per_night` as required positive version fields; the migration seeds no candidate values;
- admit only protected-user canonical-v2 activity as positive evidence;
- reject v1, replay, synthetic, future-drift, and Guardian-only evidence;
- allow direct positive activity to delay sleep start or advance wake even when coverage is unknown because both changes narrow, never widen, the exclusion;
- allow a later wake proposal only prospectively from prior, timezone-compatible, coverage-valid nights inside the fixed version lookback, with per-night contribution and update-rate caps;
- return every full half-open nightly interval that intersects `[_from,_to)`; callers calculate overlap/clipping;
- return no interval when the historical nightly context is missing or invalid;
- emit provenance JSON containing anchor, positive evidence counts, timezone, compensation, confidence, cap reason, and quality reason.

The function is `STABLE SECURITY DEFINER SET search_path=''` and executable by none of `PUBLIC`, `anon`, `authenticated`, or `service_role`. It does not modify `private.is_in_sleep_window`, `sleep_relaxed`, live alerts, or Guardian state.

- [x] **Step 4: Prove failure behavior**

Add tests showing malformed/missing config, missing/invalid historical context, timezone drift, unknown/outage coverage, and invalid sleep windows return the persisted anchor or no exclusion, never a wider inferred interval. Include same-day and overnight windows plus fixed DST gap/fold fixtures.

- [x] **Step 5: Run database regression**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: all sleep candidate and existing sleep-window tests PASS.

- [x] **Step 6: Commit**

```powershell
git add supabase/migrations/20260725162000_adaptive_sleep_candidate.sql supabase/tests/adaptive_sleep_candidate.sql
git commit -m "feat(sleep): derive absence-safe candidate intervals"
```

---

### Task 4: Build qualified sessions and personal p95 profiles

**Files:**
- Create: `supabase/migrations/20260725163000_adaptive_alert_gap_profiles.sql`
- Create: `supabase/tests/adaptive_alert_gap_profiles.sql`
- Modify: `supabase/tests/adaptive_alert_shadow_schema.sql`
- Modify: `supabase/tests/adaptive_sleep_candidate.sql`

**Interfaces:**
- Consumes: `candidate_sleep_intervals`, version config, canonical-v2 behavior evidence.
- Produces: owner-only `alert_observation_coverage_intervals` and
  `alert_intervention_events` qualification metadata for prospective shadow data.
- Produces: `qualified_behavior_sessions`, `rebuild_alert_gap_profiles`.
- Produces rows for `alert_gap_profiles`.

- [x] **Step 1: Write RED sessionization tests**

Fixture cases:

- multiple heartbeats inside the configured session gap become one session;
- the gap between session end and next session start is one training gap;
- raw within-session heartbeat gaps never become samples;
- ongoing/right-censored absence never trains as a completed normal gap;
- sleep-overlap minutes are subtracted with interval provenance;
- a prompt-induced response inside the configured intervention window is tagged/excluded;
- a completed wall-clock gap without one persisted coverage interval proving both
  activity and intervention provenance is excluded rather than learned;
- browser-local `quietWindows`, responder pause, and missing server history are
  not silently treated as accepted quiet intervals;
- no user/date contributes more than the version-configured cap;
- local timezone and context key are deterministic across replay.

Assert a five-heartbeat burst followed by a four-hour quiet period produces one completed gap, not four short gaps.

- [x] **Step 2: Write RED profile tests**

Insert completed effective gaps with known values and assert deterministic nearest-rank p95, support count, distinct support dates, span, freshness, confidence, and quality state. Include separate `personal_global` and comparable context rows.

- [x] **Step 3: Run pgTAP and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 4: Implement `qualified_behavior_sessions`**

Use `received_at` as the safety clock and require:

```sql
ingest_version = 2
and abs(extract(epoch from (received_at - at))) <= 300
```

Partition by `user_id`, order by `(received_at, id)`, start a new session only
when the prior admitted event is farther than
`config.sessionization.gap_minutes`, and emit a versioned `context_key`.

Extend the version contract without seeding a production choice:

- `sessionization.training_horizon_days`;
- `sessionization.intervention_window_minutes`;
- `context.day_partition` (`all_days|weekday_weekend`);
- `context.hour_bucket_minutes` (a positive divisor of 1440);
- `personal.confidence_formula_version`.

Historical context/local dates come from persisted coverage metadata, never the
current mutable `user_settings.timezone`.

- [x] **Step 5: Implement effective completed gaps**

For consecutive sessions:

```text
effective_gap =
  next.session_start
  - current.session_end
  - overlap(accepted candidate sleep intervals)
  - overlap(accepted explicit quiet intervals)
```

Before admitting a gap, require one persisted coverage interval spanning it with
both activity and intervention provenance marked valid. Exclude intervals around
persisted candidate intervention events. Explicit quiet overlap is currently an
empty set because no server source exists; do not reinterpret localStorage,
`paused_until`, or mutable task deadlines as protected-user quiet time.

Persist only quantiles/support in `alert_gap_profiles`; do not create a permanent per-gap public table.

- [x] **Step 6: Implement profile rebuild**

`rebuild_alert_gap_profiles` is owner-only and idempotent per
`(version_id, user_id, context_key, through_date)`. It uses an exclusive UTC
cutoff, nearest-rank p95 rounded upward to whole minutes, deterministic
hash-based daily contribution caps, and a versioned confidence formula. Missing
coverage/timezone/intervention provenance produces no valid learned row and
falls through later. It writes only derived profile rows and never updates
current heartbeat, alerts, profiles, or cohort tables. Add a deterministic
`input_sha256` to `alert_gap_profiles`; input/profile hashes exclude
`computed_at`, and an identical rebuild must not change the row.

- [x] **Step 7: Run database tests**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: personal/global p95 tests PASS; existing routine safety tests remain unchanged.

- [x] **Step 8: Commit**

```powershell
git add supabase/migrations/20260725163000_adaptive_alert_gap_profiles.sql supabase/tests/adaptive_alert_gap_profiles.sql
git commit -m "feat(alerts): build qualified personal gap profiles"
```

---

### Task 5: Build the privacy-qualified Routine-mode cohort prior

**Files:**
- Create: `supabase/migrations/20260725164000_routine_mode_cohort_priors.sql`
- Create: `supabase/tests/routine_mode_cohort_priors.sql`
- Modify: `supabase/tests/adaptive_alert_shadow_schema.sql`
- Modify: `supabase/tests/adaptive_sleep_candidate.sql`
- Modify: `supabase/tests/adaptive_alert_gap_profiles.sql`

**Interfaces:**
- Consumes: canonical mode, current consent, the exact current
  `personal_global` profile row for the requested version/cutoff, invalidation
  generation, and version config.
- Produces: `rebuild_routine_mode_cohort_priors`.
- Produces aggregate-only rows for `routine_mode_cohort_priors`, extended with a
  conservative `valid_until` and source invalidation generation.
- This migration seeds no model version or calibration. Fixture values prove the
  mechanism only. With today's lack of historical coverage/consent/mode truth,
  real local historical cohort replay must return no valid prior; the path is
  prospective until qualified evidence accumulates.

- [x] **Step 1: Write RED privacy and aggregation tests**

Use three fixture modes. Prove:

- non-consenting users never contribute;
- consent withdrawal invalidates the mode until rebuild;
- low-quality/stale personal rows never contribute;
- one user with thousands of events still contributes one per-user p95 value;
- the robust aggregate is not the raw-event weighted mean;
- zero eligible users produce no row; 1..`min_contributors - 1` are stored as
  `low_support` and cannot be selected;
- output contains no user id or contributor list;
- cohort publication itself does not require every eventual consumer to be a contributor. The end-to-end non-contributor consumption assertion is deferred to Task 6, after the candidate evaluator exists.

Known robust fixture:

```text
per-user p95 values: [120, 180, 240, 1200]
raw-event counts:    [10, 10, 10, 10000]
```

Lock exact results for both supported methods:

- `weighted_median`: weight is the admitted personal profile confidence clamped
  to `[0,1]`; choose the smallest neutral value whose cumulative weight is at
  least half total weight. Ties are ordered by neutral value; contributor ids do
  not affect the result. With four confidence-1 fixture rows above the result is
  exactly `180`.
- `trimmed_mean`: clamp each user's neutral value to the cohort contribution
  floor/ceiling, sort values, remove
  `floor(contributor_count * trim_fraction)` from each tail, require at least one
  value to remain, average the remainder, and round upward to a whole minute.
  With `trim_fraction=0.25` the fixture result is exactly `210`.

Add version-config fields without choosing or seeding production values:
`cohort.contribution_floor_minutes`,
`cohort.contribution_ceiling_minutes`, `cohort.min_span_days`,
`cohort.min_confidence`, and `cohort.confidence_formula_version`. Candidate
floor/ceiling is not the contribution bound. The builder accepts the config only
when its stored SHA-256 equals a fresh SHA-256 of canonical `config::text`;
contributors/support dates/span/max ages and both contribution bounds are
positive integers, contribution ceiling is at least its floor,
`min_confidence` is `(0,1]`, and
`confidence_formula_version='cohort_support_min_v1'`. These are mechanism
domains, not selected production values.

- [x] **Step 2: Run pgTAP and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 3: Implement cohort rebuilding**

The builder must:

1. join current `profiles.consent_data_sharing=true`;
2. normalize Routine mode;
3. select exactly one `quality_state='valid'`,
   `context_key='personal_global'`, `through_date=<requested cutoff>` profile for
   the same version; independently recheck personal support, span, freshness,
   and configured minimum confidence;
4. publish only `context_key='personal_global'` and give each user at most one
   current value for that single context;
5. clamp each per-user neutral contribution with the dedicated cohort bounds,
   then apply the exact version-configured method above;
6. publish contributor count, the conservative minimum per-contributor support
   dates/span, `oldest_evidence_at = min(latest_evidence_at)` across admitted
   contributors, `valid_until`, quality, confidence,
   algorithm, config hash, evidence version, and source generation;
7. derive
   `valid_until = min(oldest_evidence_at + personal.max_age_days,
   oldest_evidence_at + cohort.max_age_days)`; `evaluated_at >= valid_until`
   rejects the prior;
8. refuse `valid` publication below configured contributor/support/span/
   confidence gates. For `cohort_support_min_v1`, compute
   `confidence = min(1, contributor_count/min_contributors,
   conservative_support_dates/min_support_dates,
   conservative_span_days/min_span_days,
   minimum_admitted_profile_confidence/min_confidence)` using double-precision
   division. Stale or zero-contributor output is deleted/no-row; non-stale
   under-support output is `low_support` with the same formula and cannot be
   selected;
9. initialize all three mode generations to `0`. Serialize invalidation and
   rebuild on the same per-mode advisory-lock key. Invalidate on
   `alert_gap_profiles` `personal_global` INSERT/UPDATE/DELETE and on `profiles`
   INSERT/DELETE plus routine/consent UPDATE. When old and new modes differ,
   acquire distinct mode locks in canonical lexical order and atomically
   increment each affected generation exactly once;
10. make the builder lock its mode before reading generation/contributors and
    publish in the same transaction. A zero-contributor rebuild deletes its
    target row; an under-supported rebuild overwrites any old `valid` row with
    `low_support`;
11. make the evaluator reject a prior when its source generation differs, when
    `evaluated_at >= valid_until`, when stored config/evidence version differs
    from the current model version, or when the model version's stored config
    SHA-256 differs from a fresh SHA-256 of canonical `config::text`.

Hashes are deterministic and membership-minimizing:

- `input_sha256` hashes version/config/evidence/through-date, mode, algorithm,
  source generation, ordered neutral-value/confidence multiset, and conservative
  aggregate support numbers plus aggregate `oldest_evidence_at` and
  `valid_until`;
- it excludes user ids, contributor profile hashes, raw timestamps, and
  publication time; only the aggregate minimum freshness timestamps above are
  retained and hashed;
- `prior_sha256` additionally binds all published aggregate fields except
  `published_at`;
- identical inputs preserve hashes and `published_at`; a withdrawal/invalidation
  changes the generation even if the remaining numeric multiset is identical.

- [x] **Step 4: Prove withdrawal and rebuild behavior**

After consent changes:

- existing prior becomes unusable immediately through invalidation;
- rebuild omits the withdrawn contributor;
- no private membership list is exposed;
- current live ADR-0022 threshold is unchanged.

Also prove owner-only `SECURITY DEFINER SET search_path=''`, explicit execute
revocation from `PUBLIC`, `anon`, `authenticated`, and `service_role`, zero new
Data API/table grants, no cron/realtime/live trigger, and unchanged full-row
hashes for alerts, events, notifications, pings, profiles, and the deterministic
live threshold behavior.

- [x] **Step 5: Run database tests**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 6: Commit**

```powershell
git add supabase/migrations/20260725164000_routine_mode_cohort_priors.sql supabase/tests/routine_mode_cohort_priors.sql
git commit -m "feat(routine): derive privacy-qualified cohort priors"
```

---

### Task 6: Resolve one deterministic candidate decision

**Files:**
- Create: `supabase/migrations/20260725165000_adaptive_alert_candidate_evaluator.sql`
- Create: `supabase/tests/adaptive_alert_candidate_evaluator.sql`
- Modify: `supabase/tests/adaptive_alert_shadow_schema.sql`
- Modify: `supabase/tests/adaptive_sleep_candidate.sql`
- Modify: `supabase/tests/adaptive_alert_gap_profiles.sql`
- Modify: `supabase/tests/routine_mode_cohort_priors.sql`

**Interfaces:**
- Consumes: personal/context profile, cohort prior, sleep intervals, persisted
  as-of subject context, latest qualified session, and version config.
- Produces: `resolve_alert_candidate` JSON contract.
- Consumed by: replay and shadow.
- Produces owner-only, RLS/no-policy/zero-Data-API
  `alert_judgment_subject_contexts` for prospective Routine/sensitivity context
  capture. It stores effective range, canonical and raw sensitivity, canonical
  Routine mode, timezone/offset/settings provenance, capture time, evidence
  version, and provenance SHA-256. Task 6 seeds/backfills no row and supplies no
  scheduler/producer; pre-capture history is explicitly unreplayable. A
  separately authorized context/coverage/sleep producer is a prerequisite to
  any real prospective replay or shadow accumulation.
- Extends personal profile rows with config/evidence pins populated by an
  owner-only candidate-table trigger. Evaluator compares those pins and
  recomputes `profile_sha256`; config/evidence changes under the same version id
  make old rows unusable until rebuild.

- [x] **Step 1: Write RED hierarchy tests**

Prove exact selection:

1. valid context profile wins;
2. invalid context falls to valid personal-global;
3. invalid personal-global falls to valid same-mode cohort;
4. invalid cohort falls to the exact ADR-0022 deterministic emergency threshold
   without applying sensitivity twice;
5. low confidence falls a tier instead of inventing a threshold;
6. sensitivity adds exactly `0/45/90` minutes after neutral selection;
7. configured candidate floor/ceiling clamps learned candidates only and records
   `none|floor|ceiling`; deterministic emergency is `emergency_exempt` so it
   remains exactly ADR-0022;
8. p95 tail frequency is not returned as a risk probability;
9. atomic new activity changes `would_alert` to false;
10. Guardian confirmation never changes latest protected-user session or effective silence.
11. a user who does not contribute can still consume a valid published same-mode aggregate.
12. missing/ambiguous as-of subject context returns `replayable=false` with an
    explicit reason, not current mutable settings;
13. personal rows are selected only when
    `(through_date + 1 day at UTC) <= evaluated_at`, with no same-day future
    leakage;
14. config/evidence/profile/cohort hash or generation mismatch falls through or
    fails closed exactly as specified.

- [x] **Step 2: Write RED effective-silence tests**

For configured overnight sleep and a last session at `22:30`, evaluating at
`08:00` must count monitor-eligible silence after the accepted sleep interval,
not the entire wall-clock gap. Clip half-open candidate sleep ranges to
`[session_end,evaluated_at)`, merge them with `range_agg`, and subtract the union
once. The only accepted exclusions come from `candidate_sleep_intervals`;
browser quiet windows, `paused_until`, task deadlines, device absence/outage,
Guardian/alert confirmations, and `private.is_in_sleep_window` are forbidden.

- [x] **Step 3: Run pgTAP and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 4: Implement the evaluator**

The function:

- validates version status is `replay` or `shadow`;
- recomputes canonical config SHA-256 and validates evidence version; corrupt
  version/config returns unreplayable rather than emergency;
- reads exactly one persisted subject-context row whose half-open effective range
  covers `_evaluated_at`, whose `captured_at <= _evaluated_at`, and whose
  evidence/config provenance matches. It never projects current
  `profiles.routine_pattern`, current `user_settings.sensitivity`, or current
  timezone backward;
- resolves latest canonical protected-user session;
- integrates effective silence over accepted intervals;
- selects the exact fallback ladder;
- applies sensitivity and candidate-only bounds;
- returns the locked JSON keys;
- performs no `INSERT`, `UPDATE`, `DELETE`, notification, HTTP, or cron action.

Set:

```json
{
  "guardian_used_as_activity": false
}
```

unconditionally and prove this value derives from an evidence query that excludes external confirmation types.

Sensitivity/emergency normalization is pure, versioned, and exact:

```text
high|sensitive -> canonical high, buffer 0
low|relaxed    -> canonical low, buffer 90
everything else, including null/unknown -> canonical balanced, buffer 45

emergency.contract_version = adr0022_v1
emergency.neutral_minutes = 90
emergency_final_minutes = emergency.neutral_minutes + as-of version buffer
```

Require integral, non-negative values. With the locked version buffers
`0/45/90`, emergency final must reproduce ADR-0022 exactly:
`90/135/180`. Candidate floor/ceiling never clamps emergency; it clamps learned
personal/cohort output only. Add required version config
`emergency.contract_version='adr0022_v1'` and
`emergency.expected_live_definition_sha256` without seeding a production model.
Decision provenance binds both. The evaluator never calls mutable
`private.silence_threshold` to derive historical output; installation tests
prove the configured expected definition hash matches the current live helper
and that the pure contract produces identical high/default/balanced/low alias
results. A future live-helper redefinition therefore cannot silently rewrite
old replay output.

Profile selection and validity are as-of:

- choose the greatest `through_date` with its exclusive UTC cutoff
  `(through_date + 1 day at UTC) <= evaluated_at`;
- recheck `quality_state='valid'`, personal samples/support/span,
  `latest_evidence_at < evaluated_at`, freshness at evaluated time, configured
  personal minimum confidence, config/evidence pins, and a recomputed
  `profile_sha256`;
- cohort additionally requires `context_key='personal_global'`, the as-of
  canonical Routine mode, safe cutoff, all support/confidence gates,
  `evaluated_at < valid_until`, current config/evidence/digest, exact source
  generation, and recomputed prior hash;
- add `personal.min_confidence` as `(0,1]` version config, without seeding a
  production value;
- add `evaluator.contract_version='adaptive_candidate_v1'`; reject unsupported
  values and return it as `evaluator_version`.

`candidate_deadline` inverts the same effective-time clock across the ordered
union of sleep intervals known by the fixed evidence cutoff. If the threshold
crossing is inside the known range, use `known_interval_inversion`; if remaining
effective minutes extend beyond `_evaluated_at`, return the conservative earliest
deadline assuming no future exclusion and label `no_future_exclusion`. Never read
sleep context/activity finalized or received after the fixed evidence cutoff to
project a historical deadline.

`decision_provenance` deterministically binds evidence cutoff, context snapshot,
selected profile/prior hash and aggregate support/freshness, model
config/evidence hash, cohort generation, canonical sensitivity/Routine mode,
candidate bounds/reason, ordered merged sleep provenance, effective silence, and
deadline basis. Canonicalize timestamps in UTC, order arrays/ranges stably, set
function `TimeZone='UTC'`, and hash this object into `provenance_sha256`.

- [x] **Step 5: Add behavior-based forbidden-write assertions**

Snapshot live-table counts and stable hashes, invoke the evaluator for
representative hierarchy paths, and assert the snapshots remain unchanged. Also
assert `STABLE SECURITY DEFINER`, `search_path=''`, `TimeZone='UTC'`, owner
match, no trigger, and no execute privilege for `PUBLIC`, `anon`,
`authenticated`, or `service_role`. Assert live `silence_threshold` and
Guardian 30-minute `process_escalations` definitions/hashes are unchanged. The
atomic-activity assertion means one fixed top-level MVCC snapshot with an
exclusive evidence cutoff; it does not claim protection against commits after
that snapshot or perform a live alert action. Task 9 retains the separate
mechanical source scan.

- [x] **Step 6: Run focused and database tests**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 7: Commit**

```powershell
git add supabase/migrations/20260725165000_adaptive_alert_candidate_evaluator.sql supabase/tests/adaptive_alert_candidate_evaluator.sql
git commit -m "feat(alerts): resolve replayable adaptive candidates"
```

---

### Task 7: Run deterministic historical replay first

**Files:**
- Create: `supabase/migrations/20260725170000_adaptive_alert_replay.sql`
- Create: `supabase/tests/adaptive_alert_replay.sql`

**Interfaces:**
- Consumes: `resolve_alert_candidate`, canonical-v2 raw sessions, and persisted
  silence-alert rows.
- Uses an internal `MATERIALIZED candidate_replay_units` CTE inside
  `run_alert_judgment_replay`; no set-returning API, temp/permanent per-user
  table, or stored replay-unit row is created.
- Produces: `run_alert_judgment_replay`.
- Writes: aggregate-only `alert_judgment_evaluations`.
- Pre-subject-context/coverage/sleep-capture history is counted with the exact
  Task 6 unreplayable reason enum; it is never replayed from current mutable
  settings. On today's data this path is fixture-only. Real prospective replay or
  shadow requires a separately authorized producer for subject context, coverage,
  intervention, and sleep context.

One replay unit is exactly one canonical-v2 completed raw session gap:

- transient identity `(user_id, session_end, next_start)`;
- half-open interval `[session_end,next_start)`;
- `evaluated_at=next_start`, with evaluator evidence strictly `< next_start`;
- include the unit when `next_start ∈ [_from,_to)`;
- sessionize once, set-wise, using version `sessionization.gap_minutes`, canonical
  clock sanity, and the last eligible ping before `_from`;
- do not require coverage/subject/sleep context during enumeration. The evaluator
  classifies missing qualification/context as unreplayable rather than making
  pre-capture history disappear.

This is a completed-gap endpoint proxy, not a continuous scheduler simulation.
Historical scheduler ticks and within-gap setting changes were not persisted.

Add required version config without seeding production values:
`replay.contract_version='adaptive_replay_v1'`,
`replay.max_range_days`, and `replay.max_units`; both limits are positive
integers. Before enumeration or upsert require `_from < _to`, model
`status='replay'`, a fresh canonical config SHA-256, evidence
`canonical-v2`, evaluator contract `adaptive_candidate_v1`, replay contract
`adaptive_replay_v1`, and range within `max_range_days`. Exceeding
`max_units` or any invalid preflight raises/fails the run before writing.
Version/config/evidence preflight failures are run-level errors, not per-unit
unreplayable reasons, because untrusted sessionization config cannot enumerate a
safe unit universe.

- [x] **Step 1: Write RED deterministic replay tests**

Run the same fixture/version/range twice. Assert:

- the aggregate JSON and stored metrics are identical;
- no duplicate evaluation row is created;
- no alert/notification/event row count or status changes;
- exact half-open range and next-session cutoff behavior;
- pre-capture raw units are counted with exact Task 6 unreplayable reasons, not
  dropped;
- empty, all-unreplayable, mixed, and all-replayable report statuses;
- results separate `both_proxy`, `live_only_proxy`,
  `candidate_only_proxy`, `neither_proxy`, cap hits, fallback basis, and
  unadjudicated outcomes;
- multiple silence alert rows inside one gap count once in the proxy denominator;
  dark-device/SOS rows are excluded and unmatched silence alerts are separate;
- current profiles/settings/timezone/status/resolution/device-state mutations do
  not change a historical result;
- stored aggregate JSON/hashes contain no user UUID, alert id, or per-user array;
- the report never labels “no live alert row” as safety or false-alert proof.

- [x] **Step 2: Define aggregate output**

```json
{
  "version_id": "uuid",
  "replay_contract_version": "adaptive_replay_v1",
  "evaluator_version": "adaptive_candidate_v1",
  "from": "timestamptz",
  "to": "timestamptz",
  "report_status": "empty|all_unreplayable|partial|complete",
  "evaluated_count": 0,
  "replayable_count": 0,
  "unreplayable_count": 0,
  "unreplayable_reason_counts": {},
  "replayable_completed_gap_count": 0,
  "live_alert_rows_observed": 0,
  "unmatched_live_silence_alert_rows": 0,
  "candidate_would_alert_gaps": 0,
  "proxy_denominator_replayable_gaps": 0,
  "both_proxy": 0,
  "live_only_proxy": 0,
  "candidate_only_proxy": 0,
  "neither_proxy": 0,
  "threshold_delta_denominator_replayable_gaps": 0,
  "median_candidate_minus_adr0022_threshold_proxy_minutes": null,
  "p95_candidate_minus_adr0022_threshold_proxy_minutes": null,
  "basis_counts": {},
  "quality_counts": {},
  "cap_reason_counts": {},
  "adjudicated_risk_outcomes": 0,
  "unadjudicated_replayable_count": 0,
  "safety_claim": "not_evaluated",
  "promotion_eligible": false
}
```

`evaluated_count = replayable_count + unreplayable_count`. Candidate/live proxy,
threshold-proxy, cap, basis, quality, and proxy denominators use replayable rows
only. `proxy_denominator_replayable_gaps = both_proxy + live_only_proxy +
candidate_only_proxy + neither_proxy`. `unreplayable_reason_counts` sums to
`unreplayable_count`. Empty and all-unreplayable are distinct; both use zero
denominators, `{}` count maps where applicable, and `null` percentiles, never
zero/NaN. With no adjudication source, `adjudicated_risk_outcomes=0`,
`unadjudicated_replayable_count=replayable_count`, and no risk rate is emitted.
`replayable_completed_gap_count = replayable_count`.
`live_alert_rows_observed` is the sum of matched silence-alert row counts over
replayable units; `unmatched_live_silence_alert_rows` counts silence alerts with
`opened_at ∈ [_from,_to)` matching no raw unit. Report status is exact:
`empty` when evaluated is zero; `all_unreplayable` when evaluated is positive
and replayable is zero; `partial` when both replayable and unreplayable are
positive; `complete` when evaluated is positive and unreplayable is zero.

- [x] **Step 3: Run pgTAP and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 4: Implement replay**

Enumerate replay units once set-wise, then invoke the evaluator once per bounded
unit. For each replayable gap, count persisted `alerts` with the same transient
user, `cause='silence'`, and `opened_at ∈ [session_end,next_start)`; the boolean
proxy uses count `>0`. Exclude dark-device/SOS/status/resolution/escalation/
notification/current-state fields. Report silence alerts not matched to any unit
separately.

The 2×2 proxy is counterfactual only:

- `both_proxy`: live silence row observed and candidate would alert;
- `live_only_proxy`: live row observed and candidate would not alert;
- `candidate_only_proxy`: no live row observed and candidate would alert;
- `neither_proxy`: neither.

No-live-row can reflect already-open suppression, scheduler cadence, retention,
or missing historical state; it is not a safety outcome. Threshold delta is only
`candidate_threshold_minutes - (90 + as_of_sensitivity_buffer_minutes)`, named
the ADR-0022 threshold proxy rather than actual live timing.

Canonical hashing uses UTC timestamps with six fractional digits and `Z`,
half-open range semantics, integer seconds for durations, stable enum/array
ordering, canonical `jsonb::text`, UTF-8, and SHA-256. `input_sha256` binds replay
and evaluator contract versions, model/version config/evidence hashes, exact
range, and an ordered multiset of unit timestamps, Task 6 result/provenance
hashes, and ordered live-proxy timestamps/counts. It excludes user/alert ids,
runtime/transaction/query timing, `created_at`, and hash fields; duplicate tokens
remain duplicated so multiplicity is bound. `output_sha256` binds finalized
metrics plus `input_sha256`.

Upsert one aggregate row per
`(version_id, historical_replay, from, to)`. On conflict update metrics/hashes/
evaluator version only when distinct, always keep
`promotion_eligible=false`, and never update `created_at`. Store no user id,
alert id, per-user key, contributor list, or per-user array.

- [x] **Step 5: Add a hard non-promotion rule**

Every replay result must return `promotion_eligible=false`. Historical proxy metrics alone cannot authorize shadow scheduling or live promotion.

- [x] **Step 6: Run replay tests and inspect query plans**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Require configured hard unit/range limits. On realistic bounded fixtures, run
`ANALYZE` then `EXPLAIN (ANALYZE, BUFFERS)` for unit enumeration, evaluator
lateral calls, live-alert interval join, and aggregate/upsert. Add indexes only
for demonstrated scans; likely candidates are
`behavior_pings(user_id,received_at,id) WHERE ingest_version=2` and
`alerts(user_id,opened_at) WHERE cause='silence'`. Avoid quadratic re-sessionizing
inside every evaluator call.

Add golden input/output hash fixtures, timezone and insertion-order invariance,
relevant-input sensitivity, irrelevant current-state invariance, idempotent
`created_at` preservation, no identifiers in stored JSON, exact half-open alert
boundaries, multiple-alert de-duplication, dark/SOS exclusion, unmatched alerts,
promotion false, owner-only `VOLATILE SECURITY DEFINER` with UTC/search-path
pins and zero API execution, and live/candidate source table hashes showing only
one aggregate evaluation row may change.

- [x] **Step 7: Commit**

```powershell
git add supabase/migrations/20260725170000_adaptive_alert_replay.sql supabase/tests/adaptive_alert_replay.sql
git commit -m "feat(alerts): add aggregate-only historical replay"
```

---

### Task 8: Define the non-notifying shadow recorder

**Files:**
- Create: `supabase/migrations/20260725171000_adaptive_alert_shadow_recorder.sql`
- Create: `supabase/tests/adaptive_alert_shadow_recorder.sql`
- Modify: `supabase/tests/adaptive_alert_shadow_schema.sql`

**Interfaces:**
- Consumes: a version explicitly marked `shadow`, `resolve_alert_candidate`.
- Produces: idempotent `alert_judgment_shadow_decisions`.
- Callable only by the owner in fixture validation; does not schedule itself.
- Because this task does not create or authorize the missing subject-context,
  coverage/intervention, or sleep-evidence producer, its result always reports
  `execution_scope='fixture_only_unscheduled'` and `operational_shadow=false`.
  Production-like data may legitimately return `empty` or `all_unreplayable`;
  that is not operational shadow evidence. A producer, deployment, enablement, or
  schedule requires a separate authorized task/ADR.

- [x] **Step 1: Write RED no-side-effect tests**

Snapshot full counts and stable whole-row hashes for:

- `alerts`;
- `alert_events`;
- `notifications`;
- `behavior_pings`;
- `device_state`;
- `checkin_tasks`.

Also snapshot `net.http_request_queue` when it exists. Catalog/source assertions
must exclude alert writes, notification helpers, `net.http*`, `pg_notify` /
`NOTIFY`, dynamic SQL, cron scheduling, triggers, and publication changes.

Call the recorder twice for the same UTC minute, then assert:

- all live snapshots are unchanged;
- exactly one shadow row exists per user/version/minute;
- the second call preserves row ID, `created_at`, the full stored payload, and
  both provenance hashes;
- no push dispatch or network function ran;
- users with no valid version receive no shadow row;
- a version in `draft`, `replay`, or `retired` status cannot record;
- nonexistent versions and calls before `shadow_enabled_at` fail before user
  enumeration and leave zero rows;
- equivalent absolute instants represented with different offsets/DST forms
  canonicalize to the same UTC minute and the same decision;
- a replayable learned `ceiling` result whose final threshold is below its
  neutral p95 inserts successfully, while every cap-reason/value mismatch fails
  the replacement table constraints;
- null and infinite evaluation timestamps fail;
- duplicate active monitored memberships evaluate the user once;
- pending, inactive, unmonitored, guardianship-only, and no-`device_state` users
  are excluded;
- users are not prefiltered by device status, open alerts, Guardian state,
  subject context, coverage, sleep, profile, or session;
- the per-user reasons `missing_subject_context`, `ambiguous_subject_context`,
  `subject_context_provenance_invalid`, and `missing_qualified_session` are
  counted, never inserted, and never replaced by emergency values;
- an evaluator result containing a run-level reason
  (`invalid_version_status`, `config_hash_mismatch`, or
  `unsupported_evidence_version`) is a contract violation and aborts;
- missing or malformed evaluator result keys abort the call atomically;
- Guardian evidence cannot change the stored decision and
  `guardian_used_as_activity=false`;
- golden identity/owner/definition hashes for `process_escalations()` and
  `private.silence_threshold` remain unchanged.

Update `adaptive_alert_shadow_schema.sql`'s pgTAP plan count, column/constraint
assertions, representative owner insert, UTC-minute assertion, ACL/no-policy/
no-trigger/no-Realtime checks, and live snapshot assertion for every appended
non-null decision column.

- [x] **Step 2: Run pgTAP and verify RED**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 3: Implement the recorder**

Create
`private.record_alert_judgment_shadow(_version_id uuid, _evaluated_at timestamptz)`
as an owner-only `VOLATILE SECURITY DEFINER` function with `search_path=''` and
`TimeZone='UTC'`. Its owner must match the evaluator and target table. Revoke
execute from `PUBLIC`, `anon`, `authenticated`, and `service_role`; reassert
target-table RLS, zero policies, zero API privileges, no triggers, and no
Realtime publication membership.

The function first rejects null/infinite timestamps, then canonicalizes once:

```sql
_evaluated_minute :=
  date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
```

Use that exact instant for both `resolve_alert_candidate` and the insert. Lock
the exact version row `FOR SHARE` through completion; require an existing
non-null version, `status='shadow'`,
`_evaluated_minute >= shadow_enabled_at`, a freshly matching canonical config
SHA, the supported evidence version, and
`evaluator.contract_version='adaptive_candidate_v1'`. Null/nonexistent version,
non-shadow status, pre-enable minute, config-hash mismatch, and unsupported
evidence/evaluator contract are run-level errors before population enumeration.

The exact population mirrors the current live silence-scan population, without
copying its current alert eligibility filters:

```sql
SELECT DISTINCT ds.user_id
FROM public.device_state ds
WHERE EXISTS (
  SELECT 1
  FROM public.group_members gm
  WHERE gm.user_id = ds.user_id
    AND gm.status = 'active'
    AND gm.monitored
)
ORDER BY ds.user_id
```

Do not filter by device status, alert state, Guardian state, subject context,
coverage, sleep, profile, or qualified session. Missing/corrupt truth must reach
the evaluator and become its stable unreplayable result.

For every population member, call
`private.resolve_alert_candidate(user_id, _evaluated_minute, _version_id)`.
Validate the complete locked Task 6 JSON shape and evaluator version.
`replayable=false` produces no decision row and increments the exact stable
per-user reason count. If the evaluator unexpectedly returns a run-level reason,
or returns a malformed result, abort the whole statement. Any unexpected error
also aborts; partial writes are never retained to manufacture an error count.

Append-only alter `alert_judgment_shadow_decisions` to persist the complete
candidate result:

- `evidence_cutoff`;
- `unclamped_candidate_threshold_minutes`;
- `candidate_floor_minutes`;
- `candidate_ceiling_minutes`;
- `candidate_cap_reason`;
- `deadline_basis`;
- nullable `selected_source_sha256`;
- `subject_context_sha256`;
- `decision_provenance jsonb`;
- `decision_sha256`.

Replace the original autogenerated
`alert_judgment_shadow_decisions_candidate_threshold_minutes_check`
(`candidate_threshold_minutes >= neutral_threshold_minutes`). That relation is
invalid for a legitimate learned `ceiling` cap when the configured ceiling is
below the neutral p95. Preserve non-negativity with a named
`candidate_threshold_minutes >= 0` check and add cross-field constraints that
lock the evaluator contract:

- floor/ceiling/unclamped/final values are non-negative and
  `candidate_ceiling_minutes >= candidate_floor_minutes`;
- `none` means `final = unclamped`;
- `floor` means `unclamped < floor` and `final = floor`;
- `ceiling` means `unclamped > ceiling` and `final = ceiling`, including the
  regression case `final < neutral`;
- `emergency_exempt` requires `basis='deterministic_emergency'` and
  `final = unclamped`.

Validate `provenance_sha256` against the canonical `decision_provenance`.
`decision_sha256` binds version, user, canonical minute, and the complete
canonical evaluator JSON. Insert only replayable results, using
`ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING`; after a
conflict, compare the existing `decision_sha256` and raise on mismatch instead
of concealing same-minute nondeterminism.

The exact successful aggregate-only return contract is:

```json
{
  "recorder_contract_version": "adaptive_shadow_recorder_v1",
  "evaluator_version": "adaptive_candidate_v1",
  "execution_scope": "fixture_only_unscheduled",
  "operational_shadow": false,
  "result_status": "empty|all_unreplayable|partial|complete",
  "population_count": 0,
  "evaluated_count": 0,
  "replayable_count": 0,
  "inserted_count": 0,
  "duplicate_count": 0,
  "unreplayable_count": 0,
  "unreplayable_reason_counts": {},
  "skipped_count": 0,
  "error_count": 0
}
```

Status is `empty` for zero population, `all_unreplayable` for nonzero population
and zero replayable results, `partial` when replayable and unreplayable results
both exist, otherwise `complete`. Successful-call invariants:

- `population_count = evaluated_count`;
- `evaluated_count = replayable_count + unreplayable_count`;
- `replayable_count = inserted_count + duplicate_count`;
- `skipped_count = duplicate_count + unreplayable_count`;
- `error_count = 0`.

- [x] **Step 4: Prove no scheduling**

PgTAP catalog assertions must show that no cron command references the recorder or
evaluator, no live-evidence trigger function references candidate functions, and
the production `process_escalations` plus `private.silence_threshold` identities,
owners, signatures, and definition hashes are unchanged. Task 9 separately scans
the migration source for scheduling, live alert writes, notification/push/network
references, dynamic SQL, and publication changes.

- [x] **Step 5: Run all database and static tests**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

- [x] **Step 6: Commit**

```powershell
git add supabase/migrations/20260725171000_adaptive_alert_shadow_recorder.sql `
  supabase/tests/adaptive_alert_shadow_recorder.sql `
  supabase/tests/adaptive_alert_shadow_schema.sql
git commit -m "feat(alerts): add unscheduled shadow recorder"
```

---

### Task 9: Full verification and evidence checkpoint

**Files:**
- Modify only if verification exposes a scoped defect in Tasks 1–8.

**Interfaces:**
- Produces: implementation evidence for a separate deployment/shadow-enable decision.

- [x] **Step 1: Reset and replay migrations on PostgreSQL 17**

```powershell
npm exec --package=supabase@2.109.1 -- supabase db reset
```

Expected: every historical and new append-only migration applies cleanly.

Evidence note: the raw pinned CLI reset still stops at the pre-existing
`20260623090000_gm_admin_console.sql` fixed-admin FK fixture issue. The
ADR-0024 hash-pinned disposable compatibility replay is the accepted local
reset path; it applied every migration through `20260726011500` and passed
the complete database suite without editing historical migrations.

- [x] **Step 2: Run the full database suite**

```powershell
npm exec --package=supabase@2.109.1 -- supabase test db
```

Expected: all existing and new pgTAP assertions PASS.

- [x] **Step 3: Run frontend verification**

```powershell
npm run typecheck
npm test
npm run build
npm run local:gate:static
```

- [x] **Step 4: Run mechanical safety checks**

```powershell
git diff --check
rg -n -i 'insert\s+into\s+(public\.)?(alerts|alert_events|notifications)|update\s+(public\.)?alerts|trigger_push_dispatch|notify_stage|cron\.schedule|net\.(http|http_[a-z_]+)|http_(get|post|delete)\s*\(|pg_notify\s*\(|\bnotify\b|alter\s+publication' supabase/migrations -g "2026072516*.sql" -g "2026072517*.sql"
rg -n -P -i '^\s*execute\s+(?!function\b|procedure\b)' supabase/migrations -g "2026072516*.sql" -g "2026072517*.sql"
rg -n -i 'create\s+(constraint\s+)?trigger' supabase/migrations -g "20260725171000_adaptive_alert_shadow_recorder.sql"
```

Expected: matches occur only inside static-test strings, required candidate
profile invalidation triggers outside Task 8, or explicit negative assertions;
no candidate migration performs a live write, notification/network/dynamic-SQL/
publication mutation, and the Task 8 migration creates no trigger or schedule.

- [x] **Step 5: Produce a redacted replay evidence packet**

Run replay only in local/non-production or against an explicitly approved read-only/redacted copy. Record aggregate metrics, config hash, evaluator hash, input range, evidence version, row counts, quality/fallback counts, and query duration. Do not export user IDs, raw timestamps, or individual safety cases.

- [x] **Step 6: Independent integrated audit**

Use a fresh non-author Codex/OpenAI or Claude/Anthropic reviewer with:

- ADR-0023;
- exact diff;
- full test output;
- replay aggregate packet;
- proof that live table hashes/counts do not change;
- proof no cron is scheduled.

Google may implement bounded tasks but cannot sign the final ADR-0021/0022/0023 safety inspection gate.

- [x] **Step 7: Stop at the deployment boundary**

Do not apply migrations to production and do not enable shadow scheduling. Open a separate High-risk deployment task referencing ADR-0023 and the accepted audit. That task must decide:

- concrete version config and candidate grid;
- production migration/canary order;
- shadow sampling frequency and retention;
- monitoring and stop conditions;
- whether another human decision is required before production shadow enablement.

- [x] **Step 8: Commit verification-only fixes and evidence references**

```powershell
git status --short
git log --oneline --decorate -10
```

Commit only scoped verification fixes. Do not push, deploy, or release from this plan.

---

## Self-Review Record

### Spec coverage

- Three-mode canonical taxonomy and legacy mapping: Task 1.
- Consent-qualified robust cohort prior: Tasks 2 and 5.
- Personal context/global p95 hierarchy: Tasks 4 and 6.
- Deterministic emergency fallback and sensitivity separation: Task 6.
- Dynamic sleep with absence-safe boundaries: Task 3.
- Guardian separation and 30-minute state-machine preservation: Task 6 plus no live state-machine changes.
- Historical replay before shadow: Task 7 precedes Task 8.
- Non-notifying shadow and zero live side effects: Tasks 2, 6, and 8.
- Privacy, RLS, aggregate-only reports, consent withdrawal: Tasks 1, 2, 5, and 7.
- Replayability, observability, failure and rollback: Tasks 6–9.
- No live promotion: global constraints and Task 9 stop boundary.

### Type and signature consistency

- Frontend `RoutineMode` values match DB canonical normalizer.
- Tasks 3–8 consume the same `version_id`.
- Replay and shadow call the same `resolve_alert_candidate` contract.
- Profile/cohort/evaluator basis names match the locked JSON contract.
- No task creates an alternative live threshold function or modifies `process_escalations`.

### Placeholder scan

The plan contains no deferred implementation markers. Product-selected numeric values are intentionally stored in a version config and are not silently invented by the implementation task.
