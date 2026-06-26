# Activity Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GM, group watch boards, actual behavior pings, and alert state use one account-level activity truth.

**Architecture:** `behavior_pings.max(at)` is the real behavior clock. `device_state.last_heartbeat_at` is only a derived/cache heartbeat. Server RPCs expose the same behavior clock and alert state to GM and group UI. Alert processing re-evaluates open silence/dark alerts against current threshold before escalating.

**Tech Stack:** Supabase Postgres functions/migrations, React/TypeScript, Vitest.

---

### Task 1: Frontend Activity Display Contract

**Files:**
- Modify: `src/features/relationships/groupActivity.ts`
- Modify: `src/features/relationships/GroupBoard.tsx`
- Test: `src/features/relationships/groupActivityDisplay.test.ts`

- [ ] Add a failing Vitest case proving an alerted member with 3 hours of silence renders as an alert/needs-attention status, not `1+ day(s)`.
- [ ] Extend `ActivityStatus` with `alert` and add optional `last_behavior_at`, `last_heartbeat_at`, and `threshold_hours` fields.
- [ ] Update `GroupBoard` to display `alert` separately and include actual elapsed behavior hours.
- [ ] Run the focused test and verify it passes.

### Task 2: Server Truth For Group Activity

**Files:**
- Create: new Supabase migration from `supabase migration new sync_activity_truth`

- [ ] Update `public.get_group_activity(_group uuid)` to use `behavior_pings.max(at)` for member status and hours.
- [ ] Return `last_behavior_at` and `last_heartbeat_at` in every visible member row.
- [ ] Return `status = 'alert'` when the member has an open group/community/terminal alert instead of forcing UI to infer it.
- [ ] Keep privacy behavior for `hidden` rows.

### Task 3: Re-Evaluate Open Alerts

**Files:**
- Same migration as Task 2

- [ ] Add helper logic to `public.process_escalations()` that resolves open `silence` alerts when the current behavior age is back within `private.silence_threshold()` or inside sleep window.
- [ ] Resolve open `dark_device` alerts when device heartbeat is no longer older than 18 hours.
- [ ] Insert an `alert_events` row with kind `auto_resolved` and note `condition_cleared` for these stale alerts.
- [ ] Continue escalation only after this stale-alert cleanup.

### Task 4: Stop Polluting Behavior Pings

**Files:**
- Same migration as Task 2
- Modify: `supabase/functions/ping/index.ts`

- [ ] Remove guardian `resolve_alert` inserting a `behavior_ping` for the target; guardian confirmation is not actual target behavior.
- [ ] Keep target self-notification so they are asked to use/unlock the device.
- [ ] Ensure `resolve_my_alert()` inserts a self `manual_checkin` behavior ping because that action is actual user behavior.
- [ ] Simplify Edge `ping` so database trigger remains the central side-effect owner after inserting behavior ping.

### Task 5: Verify And Publish

- [ ] Run focused tests.
- [ ] Run `npm test`.
- [ ] Run `npm run typecheck`.
- [ ] Run `npm run build`.
- [ ] Apply the migration to live Supabase and verify sanagu no longer has an open stale silence alert if current threshold says safe.
- [ ] Commit and push `iteration`.
