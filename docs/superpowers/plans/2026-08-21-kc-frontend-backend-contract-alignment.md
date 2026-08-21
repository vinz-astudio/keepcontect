# KC Frontend–Backend Contract Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current Keep Contact UX/UI behavior real end to end, with one authoritative frontend contract, matching Supabase migrations/RPC/RLS, safe notification delivery, and verifiable account/data operations.

**Architecture:** Keep the current product shell and converge it on the `daily-checkin-v1` contract already implemented in Supabase. Use append-only migrations for server behavior, owner-scoped Edge Functions for irreversible account operations, and normalized emergency-card tables with the same existing client-side encryption and responder visibility rules. Each stage ends with targeted tests and a human checkpoint before the next stage or any external deployment.

**Tech Stack:** React + Vite + TypeScript, Vitest, Supabase Postgres/RLS/RPC, Supabase Edge Functions, Web Push/FCM, Capacitor Android/iOS, Tauri desktop.

**Spec:** `C:/Users/vizen/Desktop/Obsidian Brain/2nd Brain/Projects/Keep Contact/Product Requirement.md`, `C:/Users/vizen/Desktop/Obsidian Brain/2nd Brain/Projects/Keep Contact/Decisions.md`, `C:/Users/vizen/Desktop/Obsidian Brain/2nd Brain/Projects/Keep Contact/Architecture/Database Schema.md`, `C:/Users/vizen/Desktop/Obsidian Brain/2nd Brain/Projects/Keep Contact/Business Logic/Alert System.md`, `C:/Users/vizen/Desktop/Obsidian Brain/2nd Brain/Projects/Keep Contact/Business Logic/Notification Flow.md`.

## Global Constraints

- Preserve all existing Claude work; never use `git reset --hard`, `git checkout --`, or overwrite unrelated dirty files.
- Current local changes are the implementation base; do not silently revert them to `origin/main`.
- Supabase schema changes are append-only new migrations under `supabase/migrations/`; never edit an applied migration.
- The daily check-in contract is exact: ask time `0..1439`, quiet period `240..2880` minutes, response grace `15..720` minutes, valid IANA timezone, client contract `daily-checkin-v1`, and server-owned `consecutive_misses = 1` with no independent sleep policy.
- A notification to the subject is required for every non-SOS self stage; the foreground overlay remains an additional path, not the only path.
- Account deletion must fail closed: no email-only deletion, no success message before a verified server-side deletion response, and no swallowed Supabase errors.
- Emergency data remains encrypted client-side and responder visibility remains limited to the existing owner/guardian/open-terminal-or-SOS rules.
- Any irreversible deletion, production migration, function deployment, or release action pauses for human confirmation.
- Android notification/background changes must be checked against `android/PLAY-CONSTRAINTS.md`.

## Execution Order and Checkpoints

Stages are intentionally sequential because Stage 1 changes the live frontend contract, Stage 2 changes notification delivery, Stage 3 handles irreversible deletion, and Stage 4 changes the emergency-data model. After each stage, report changed files, tests, remaining risk, and wait for confirmation before proceeding.

### Stage 0: Protect the current local baseline

**Files:**
- Read-only: repository status, current diff, current migration list, Brain Active Work and Decisions.
- No application file changes.

**Deliverable:** A safe implementation branch/baseline containing the current Claude work, with no lost untracked migrations or iOS diagnostic artifact.

- [ ] Record `git status --short`, `git diff --stat`, `git diff --check`, `git rev-parse HEAD`, and `git ls-files supabase/migrations/20260817*`.
- [ ] Confirm the two daily-checkin migrations are tracked and the self-stage/health migrations are still local-only.
- [ ] Run the existing baseline checks before edits: `npm run typecheck`, `npm test -- --reporter=dot`, `npm run build`, `npm run local:gate:static`.
- [ ] At execution time, create `codex/kc-contract-alignment` from the current `HEAD` while keeping the current dirty files in place; if that branch already exists, stop and report instead of switching or resetting.
- [ ] Stop and report the baseline before Stage 1.

### Stage 1: Make the live Routine screen use the real daily-check-in contract

**Files:**
- Modify: `src/features/relationships/HomeScreen.tsx:604-605`
- Modify: `src/features/baseline/RoutineSettings.tsx`
- Modify: `src/features/passive/PassiveCheckinSettings.tsx`
- Modify: `src/features/passive/dailyCheckin.ts`
- Modify: `src/features/passive/dailyCheckinApi.ts`
- Modify: `src/features/routine/NextCheckin.tsx`
- Modify: `src/features/baseline/RoutineInsights.tsx`, `src/features/baseline/LivenessProvider.tsx` if their live daily-mode wording or legacy sleep writes contradict the authoritative daily contract.
- Test: existing `src/features/passive/dailyCheckin.test.ts` and the current source/viewport contract tests; add a focused routine contract test beside them.

**Interfaces:**
- Consumes: `getDailyCheckin()`, `saveDailyCheckin()`, `DailyCheckinDraft`, `DailyCheckinStatus`, `next_question_at`, `ask_at_local_minute`.
- Produces: one live routine screen that edits only ask time, quiet period, response grace, and timezone; it must submit the exact parameters already accepted by `set_daily_checkin_contract`.

- [ ] Write failing tests that prove the live route exposes the daily vocabulary and no longer exposes the incompatible “times before KC asks” control or independent sleep control in `passive_checkin` mode.
- [ ] Write failing model tests for the accepted boundary values: `240` and `2880` quiet minutes, `15` and `720` grace minutes, a valid local ask time, and rejection of `239`/`2881` quiet minutes.
- [ ] Write a failing countdown test that uses `nextQuestionAt` as the server anchor; it must not recompute the next question only from `lastActivityAt`.
- [ ] Promote the newer daily-checkin UI already present in `PassiveCheckinSettings` into the active Routine route, or move its exact controls into the current visual shell; leave only one authoritative implementation.
- [ ] Remove the active daily-mode controls for consecutive misses and sleep hours. If a legacy silence-only mode still exists, show its status separately and do not let it write the daily contract.
- [ ] Bind the three controls to the existing RPC parameters:

```ts
await saveDailyCheckin(
  {
    ...draft,
    askAtLocalMinute,
    waiverLookbackMinutes,
    responseGraceMinutes,
    timezone,
  },
  targetMode,
)
```

- [ ] Render the server-returned `nextQuestionAt`, `effectiveAt`, and engine mode so the UI explains the backend’s actual schedule rather than a local approximation.
- [ ] Run the focused Vitest tests and `npm run typecheck`.
- [ ] Run the full web checks and stop for human review of the local Routine flow.

### Stage 2: Close the self-notification and notification-health backend gaps

**Files:**
- Add/track: `supabase/migrations/20260820230000_self_stage_reaches_the_subject.sql`
- Modify/add: `supabase/migrations/20260820231000_undeliverable_notice_is_a_health_incident.sql`
- Test: add pgTAP coverage under `supabase/tests/` for self notification and the open-health-incident uniqueness behavior.
- Verify only: `supabase/functions/push-dispatch/index.ts`, `supabase/migrations/20260814193000_passive_window_engine.sql`.

**Interfaces:**
- Consumes: `private.notify_stage(alert_id, user_id, stage)`, `public.notifications`, `public.protection_health_incidents`, `finalize_notification_delivery`.
- Produces: one non-SOS `kind = 'self'` notification addressed to the subject, and at most one open protection-health incident per user without trigger-induced delivery failure.

- [ ] Add the self-stage migration as a tracked append-only migration; retain the foreground `AlertOverlay` path while inserting the subject notification for non-SOS self stages.
- [ ] Add a failing database test for a non-SOS self stage that asserts exactly one subject notification row with `recipient_id = alert.user_id`, `alert_id`, and `kind = 'self'`.
- [ ] Add a failing database test for an SOS self stage that asserts no duplicate self prompt is inserted.
- [ ] Change the undeliverable trigger guard to check for any open incident for the recipient, not only an open `permission_lost` incident; this must respect the existing partial unique index on `user_id`.

```sql
WHERE NOT EXISTS (
  SELECT 1
  FROM public.protection_health_incidents AS open_incident
  WHERE open_incident.user_id = NEW.recipient_id
    AND open_incident.closed_at IS NULL
)
```

- [ ] Add tests for `no_target` with no open incident, repeated `no_target` with the same incident open, and `no_target` while a different-cause incident is already open.
- [ ] Replay the migrations and pgTAP tests with Docker/Supabase local running; do not treat static SQL inspection as deployment proof.
- [ ] Run a local push-dispatch smoke test for self and concern notification records, including no-target health creation.
- [ ] Stop before applying migrations to any shared/production Supabase project and request the human deployment checkpoint.

### Stage 3: Implement safe account deletion end to end

**Files:**
- Create: `supabase/functions/delete-account/index.ts`
- Add contract test: `supabase/functions/delete-account/index.test.ts`
- Modify: `src/features/profile/profileApi.ts:54-81`
- Modify: `src/features/legal/AccountDeletion.tsx:11-64`
- Modify: `src/App.tsx` auth guard for `/delete-account` so the public page cannot claim deletion from an unauthenticated email submission.

**Interfaces:**
- Consumes: the authenticated Supabase access token and the current user ID.
- Produces: `deleteMyAccount(): Promise<void>` that returns only after the server confirms deletion, and a public deletion page that never claims success from `signOut()` alone.

- [ ] Write failing source-contract tests requiring the Edge Function to reject missing/invalid authorization and requiring the client to check the function error before clearing local state.
- [ ] Implement the authenticated Edge Function: validate the bearer token with Supabase Auth, obtain the verified user ID, call the service-role `auth.admin.deleteUser(userId)`, and return a non-2xx response on any failure.
- [ ] Replace direct client-side table deletion with:

```ts
const { error } = await supabase.functions.invoke('delete-account', { body: {} })
if (error) throw error
localStorage.clear()
await supabase.auth.signOut()
```

- [ ] Change `/delete-account` so an unauthenticated visitor is sent through the existing authenticated sign-in path or a verified email-link path; an email string alone must never identify or delete an account.
- [ ] Show “request received/deleted” only after a successful server response; show the actual error and retain the session when deletion fails.
- [ ] Test successful deletion, missing session, function failure, and local-storage cleanup ordering.
- [ ] Pause for explicit human confirmation before deploying this irreversible function or testing it against a real account.

### Stage 4: Replace the emergency-card JSON shim with a real backend model

**Gate:** This stage changes the database model and emergency responder data contract. Before creating the migration, write the required proposal in Brain `Coordination/Active Work.md` and wait for the human to record an accepted ADR in `Projects/Keep Contact/Decisions.md`.

**Files:**
- Add after ADR acceptance: `supabase/migrations/20260822000000_emergency_info_cards.sql`
- Modify: `src/features/profile/emergencyApi.ts`
- Modify: `src/features/profile/EmergencyInfoCard.tsx`
- Modify: `src/features/alerts/api.ts`
- Modify: `src/features/alerts/NotificationsCard.tsx`
- Update generated types: `src/lib/database.types.ts`
- Test: `src/features/profile/emergencyApi.test.ts`, `src/features/profile/EmergencyInfoCard.test.tsx`, and a pgTAP/RLS test under `supabase/tests/`.

**Interfaces:**
- Consumes: the existing `ContactCardItem` and `AddressCardItem` shapes: `id`, `name`, `phone`, `relationship`, `isPrimary`, `label`, `address`, and `accessCode`.
- Produces: normalized owner-scoped contact/address rows, encrypted field values, primary-card constraints, and responder views that render all visible cards at terminal/SOS time.

- [ ] Add normalized `emergency_contacts` and `emergency_addresses` tables with UUID IDs, `user_id`, encrypted text fields, `is_primary`, `sort_order`, timestamps, foreign-key cascade, and one-primary-per-user partial indexes.
- [ ] Add RLS matching existing emergency-info semantics: owner read/write, guardian update where currently allowed, and responder read only when an open terminal/SOS alert and the existing guardian/watch/community predicate are true.
- [ ] Add a one-time migration from legacy `emergency_info` values into one primary contact/address row without deleting the legacy columns.
- [ ] Replace JSON serialization with typed CRUD functions that encrypt/decrypt each field using the existing key derivation path.
- [ ] Update `NotificationsCard` to fetch and render all visible contacts and addresses while retaining the legacy-row fallback until every client uses the new tables.
- [ ] Test add/edit/remove, primary switching, legacy migration, owner isolation, responder visibility, and encrypted round-trip behavior.
- [ ] Replay the migration and RLS tests locally before any shared database application.

### Stage 5: Make the passcode promise real

**Files:**
- Modify: `src/features/baseline/AlertOverlay.tsx`
- Modify or add: `src/features/pattern/PasscodeSetup.tsx`, `src/features/pattern/PatternLock.tsx`, and a passcode input component beside them.
- Modify: `src/features/pattern/patternStore.ts` only if the existing namespaced storage contract needs a shared verifier.
- Test: existing `src/features/pattern/passcodeStore.test.ts`, `src/features/pattern/patternStore.isolation.test.ts`, and a focused AlertOverlay interaction test.

**Interfaces:**
- Consumes: `verifyPattern(uid, sequence)`, `verifyPasscode(uid, digits)`, `resolveMyAlert()`.
- Produces: the same alert unlock flow accepting either configured local credential, with server resolution occurring only after local verification.

- [ ] Add a failing overlay test for a configured passcode that currently renders only `PatternLock`.
- [ ] Add a passcode input path to the overlay and route its completion through `verifyPasscode` with the same error, retry, setup, and busy-state behavior as pattern verification.
- [ ] Keep the credential device-local; do not add a false server-side passcode field. `resolve_my_alert()` remains protected by the authenticated Supabase session.
- [ ] Add tests for pattern-only, passcode-only, both configured, wrong credential, and no-credential setup states.
- [ ] Run the pattern/overlay tests and verify the copy no longer promises an unavailable unlock method.

### Stage 6: Full verification, device matrix, and release handoff

**Files:**
- Modify only test/contract documentation and Brain truth notes required by actual completed changes.
- No release/version bump unless the human separately approves release work.

- [ ] Run `npm run typecheck`.
- [ ] Run `npm test -- --reporter=dot`.
- [ ] Run `npm run build`.
- [ ] Run `npm run local:gate:static` and confirm no new warnings are introduced.
- [ ] Start Docker Desktop and run `npm run db:replay:compat`; run the full Supabase migration/pgTAP suite.
- [ ] Build Android debug with `android/gradlew.bat assembleDebug --no-daemon` and verify notification permission/background constraints against `android/PLAY-CONSTRAINTS.md`.
- [ ] Manually verify the critical flows on PWA, Android, iOS, and Tauri: daily check-in schedule, activity waiver, self notification while the app is closed, concern escalation, no-target health state, SOS responder cards, pattern/passcode unlock, and failed account deletion.
- [ ] Before generating any release artifact, verify that all four version files are synchronized; do not bump versions as part of this alignment work.
- [ ] Update Brain project truth only with facts actually established by code/tests/device verification, and append a signed Dev Log entry explaining the changes.
- [ ] Present the final changed-file list, test evidence, migration/deployment status, and remaining release risks for the final human checkpoint.

## Self-review

- Product behavior covered: daily check-in, activity waiver, escalation/self notification, protection health, account deletion, emergency cards, and unlock UX.
- Backend contracts covered: RPC arguments/returns, notification rows, health incident uniqueness, Edge Function authentication, emergency-table RLS, and generated frontend types.
- Known deployment boundary: local code/migrations are not considered live until replayed and explicitly applied; irreversible deletion and production deployment require confirmation.
- No step depends on editing an old migration or silently discarding the current Claude work.
