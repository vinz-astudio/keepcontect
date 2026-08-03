# ADR-0029 P3 Remove Behavior-Ping Coalescing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every distinct validated behavior event while preserving `event_id` idempotency, Gate 1 live-safety checks, and bounded client interaction emission.

**Architecture:** Add one append-only migration that replaces only `private.insert_behavior_ping`. Keep the per-event advisory lock and unique-index retry handling, but remove the user/source/five-minute bucket lock, coalescing lookup, skipped insert, and `coalesced` return path. Prove the database behavior with a standalone pgTAP suite and characterize the existing client-side five-minute emission limit with Vitest; do not change `private.silence_threshold`, live consumers, historical migrations, production state, or ADR-0029 P1/P2/P4/P5.

**Tech Stack:** PostgreSQL 15 / PL/pgSQL, Supabase CLI 2.109.1, pgTAP, React/Vite TypeScript, Vitest 3.2.6.

## Global Constraints

- Work only in `.worktrees/adr-0029-p3` on `codex/adr-0029-p3`.
- Add exactly one migration: `supabase/migrations/20260729170000_remove_behavior_ping_coalescing.sql`.
- Never edit a historical migration or access production Supabase.
- Preserve source/kind validation, five-minute future-drift rejection, `ingest_version=2`, event-scoped advisory locking, unique-index fallback, and `private.apply_liveness_side_effects`.
- A distinct `event_id` that passes validation returns `inserted` and creates one row even when another event for the same user/source is in the same five-minute observation bucket.
- Retrying an existing `event_id` returns `duplicate`, creates no row, and does not re-run side effects.
- Keep the existing client collector's explicit one-interaction-per-five-minutes bound; no database merge substitutes for client rate control.
- Do not deploy, push migrations, activate Cron, publish Web/APK/Tauri, or promote adaptive logic live.

---

### Task 1: Characterize the existing client emission boundary

**Files:**
- Create: `src/features/signals/sources.test.ts`
- Read: `src/features/signals/sources.ts`

**Interfaces:**
- Consumes: `startSignalSources(record: (kind: SignalKind) => void): () => void`
- Produces: a regression contract proving collector startup records once, repeated pointer/focus activity inside five minutes records nothing extra, and the first activity at the five-minute boundary records once.

- [x] **Step 1: Write the client contract test**

Use Vitest fake timers, mock `@capacitor/core`, `@/lib/platform`, and `@/features/signals/sensors`, set `document.visibilityState` to `visible`, call `startSignalSources`, dispatch repeated `pointerdown` and `focus`, then advance the system clock to the exact five-minute boundary.

The hand-derived assertions are:

```ts
expect(record).toHaveBeenCalledTimes(1)
expect(record).toHaveBeenLastCalledWith('interaction')
// repeated events before 300_000 ms
expect(record).toHaveBeenCalledTimes(1)
// first event at 300_000 ms
expect(record).toHaveBeenCalledTimes(2)
```

Call the returned stop function and prove later events no longer call `record`.

- [x] **Step 2: Run the focused test**

Run:

```powershell
npm test -- src/features/signals/sources.test.ts
```

Expected: PASS because P3 relies on the already-present client emission bound rather than changing it.

- [x] **Step 3: Mutation-check the contract**

Temporarily reason through these production mutations and confirm the assertions would fail: remove the throttle branch, change the interval below five minutes, or omit listener cleanup. Do not alter production source for this characterization-only task.

---

### Task 2: Prove the missing database behavior with RED pgTAP

**Files:**
- Create: `supabase/tests/behavior_ping_no_coalescing.sql`
- Read: `supabase/migrations/20260719015302_routine_ai_gate1_containment.sql`

**Interfaces:**
- Consumes: `public.record_behavior_ping(uuid, timestamptz, text, text) returns text`
- Produces: a standalone transactional pgTAP contract for same-bucket distinct-event persistence and retry idempotency.

- [x] **Step 1: Write the pgTAP test before production SQL**

Start a transaction, plan six assertions, insert one `auth.users` fixture and one `device_state` fixture, then call `record_behavior_ping` twice as that authenticated user with literal distinct UUIDs and observation times derived from one transaction-local `date_trunc('minute', now())` anchor plus one and two seconds.

Assert:

```sql
SELECT results_eq(
  $$ SELECT public.record_behavior_ping(
    '29000000-0000-4000-8000-000000000001'::uuid,
    date_trunc('minute', now()) + interval '1 second',
    'installed_pwa',
    'interaction'
  ) $$,
  $$ VALUES ('inserted'::text) $$,
  'first automatic event is inserted'
);
```

The second distinct UUID must also return `inserted`; a service-role count over the two UUIDs must equal `2`; retrying the first UUID must return `duplicate`; its per-event count must remain `1`; and both stored rows must have `ingest_version=2`, non-null `received_at`, and the literal observed timestamps. End with `finish()` and `ROLLBACK`.

Both calls must derive one shared `now()`-relative bucket anchor so they remain live-safety eligible on any replay date.

- [x] **Step 2: Run replay before adding the migration**

Run:

```powershell
npm run db:replay:compat
```

Expected: FAIL in `behavior_ping_no_coalescing.sql` because the second distinct event returns `coalesced` and only one row is stored. Save this RED output in task evidence.

---

### Task 3: Replace the shared validator without coalescing

**Files:**
- Create: `supabase/migrations/20260729170000_remove_behavior_ping_coalescing.sql`
- Test: `supabase/tests/behavior_ping_no_coalescing.sql`

**Interfaces:**
- Consumes: existing `public.behavior_pings`, `behavior_pings_event_id_uidx`, and `private.apply_liveness_side_effects(uuid,timestamptz,timestamptz)`
- Produces: the unchanged function signature `private.insert_behavior_ping(uuid,uuid,timestamptz,text,text) returns text`, now returning only `inserted`, `duplicate`, or `invalid`.

- [x] **Step 1: Write the minimal append-only migration**

Use `CREATE OR REPLACE FUNCTION private.insert_behavior_ping(...)` with the existing validation and event lock. The write path must be:

```sql
PERFORM pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(_user_id::text || ':event:' || _event_id::text, 0)
);

IF EXISTS (
  SELECT 1
  FROM public.behavior_pings
  WHERE user_id = _user_id
    AND event_id = _event_id
) THEN
  RETURN 'duplicate';
END IF;

BEGIN
  INSERT INTO public.behavior_pings
    (user_id, event_id, at, source, kind, received_at, ingest_version)
  VALUES
    (_user_id, _event_id, _observed_at, _source, _kind, _received_at, 2);
EXCEPTION WHEN unique_violation THEN
  IF EXISTS (
    SELECT 1
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND event_id = _event_id
  ) THEN
    RETURN 'duplicate';
  END IF;
  RAISE;
END;

IF _is_live_safety THEN
  PERFORM private.apply_liveness_side_effects(
    _user_id,
    _observed_at,
    _received_at
  );
END IF;

RETURN 'inserted';
```

Do not include `':bucket:'`, a five-minute bucket lookup, `_is_coalesced`, or a `coalesced` return.

- [x] **Step 2: Run the full disposable replay**

Run:

```powershell
npm run db:replay:compat
```

Expected: all migrations apply and all pgTAP files pass, including the new six-assertion P3 suite and the existing live-safety suite.

- [x] **Step 3: Inspect the effective function contract**

Use the disposable local database only and verify the migration did not modify `private.silence_threshold`, public RPC signatures, ACL statements, or any live/adaptive function. `git diff --check` must report no whitespace errors.

---

### Task 4: Verify the branch and write back runtime truth

**Files:**
- Verify: all four branch files above
- Modify through Brain task allowance: `Projects/Keep Contact/Business Logic/Behavior Pings.md`
- Modify through Brain task allowance: `Projects/Keep Contact/Architecture/Database Schema.md`
- Modify through Brain task allowance: `Projects/Keep Contact/QA/Scenario Matrix.md`
- Modify: `Experiences/Keep Contact/Dev Log.md`

**Interfaces:**
- Consumes: fresh verification output and the final diff
- Produces: aligned project truth, signed Dev Log evidence, and a finishable schema-v1 task record.

- [x] **Step 1: Run focused and static checks**

Run:

```powershell
npm test -- src/features/signals/sources.test.ts
npm run typecheck
npm run local:gate:static
git diff --check
git status --short
```

Expected: focused test and static gate pass. If the baseline `PrivacyPolicy.tsx` unused-React type error remains, report it as an unrelated pre-existing blocker and do not modify that out-of-scope file.

- [x] **Step 2: Re-run the full replay as completion evidence**

Run:

```powershell
npm run db:replay:compat
```

Expected: exit 0 with every migration and pgTAP suite passing.

- [x] **Step 3: Update Brain truth using verified behavior**

Replace the old server-coalescing contract with:

- distinct validated `event_id` values each persist once;
- duplicate `event_id` is the only ingestion deduplication rule;
- client interaction emission remains explicitly bounded to one event per five minutes per running collector;
- RPC current results are `inserted|duplicate|invalid`, while clients may continue accepting legacy `coalesced` during server rollout;
- SCN-016 now verifies same-bucket persistence plus duplicate retry idempotency.

Prepend a signed `[Codex · 2026-07-29 HH:mm +06:00]` Dev Log entry with RED/GREEN/replay evidence and the no-production boundary.

- [x] **Step 4: Update and finish the Brain task**

Record verification, writeback, first-principles evidence, and:

```json
{
  "learning_review": {
    "status": "none",
    "reason": "P3 produced task-specific behavior evidence; no reusable workflow rule met the promotion threshold."
  }
}
```

Run `brain-task update`, `brain-task check`, and `brain-task finish KC-ADR0029-P3-001` only when all required gates pass or the task truthfully records an unresolved blocker.
