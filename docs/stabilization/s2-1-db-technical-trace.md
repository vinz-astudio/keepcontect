# S2.1 Database Technical Trace

Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis`
Starting head: `64c87c2`
Scope: local read-only diagnosis; no source, migration, test, production, release, or native-project mutation

## Outcome

All five previously unpinned S2 clusters now have an earliest failing guard.

| Cluster | Earliest failing guard | Classification | Repair owner |
| --- | --- | --- | --- |
| Routine-mode invalidation | `UPDATE public.profiles` matches zero rows because the test inserts only `auth.users` | Test fixture defect | `adaptive_alert_routine_modes.sql` |
| Cohort prior `published=0` | No `public.profiles` rows survive the builder join | Test fixture defect | `routine_mode_cohort_priors.sql` |
| Shadow context / dirty queue | Missing `profiles` and `user_settings` rows make every fixture update a no-op | Test fixture defect | `adaptive_alert_shadow_operational_schema.sql` |
| `task_missed` notification | Missing ward profile leaves `_wname=NULL`; notification `body NOT NULL` rejects the row and per-subject isolation records the failure | Test fixture defect; the other six failures in the file are accepted-contract drift | `routine_safety.sql` |
| Account threshold shadow | ADR-0037 permits the live comparator to be NULL, but `account_threshold_shadow.live_threshold_minutes` is `NOT NULL` | Real shadow-runtime/schema defect | New append-only migration plus `account_threshold_shadow.sql` |

No new product decision is required. ADR-0037 and ADR-0039 already decide the missing-evidence and passive-activity semantics.

## Shared fixture root cause

The local catalog has no non-internal trigger on `auth.users`. The baseline defines `public.handle_new_user()`, but does not attach it to `auth.users`. Therefore this pattern does not create application fixtures:

```sql
INSERT INTO auth.users (...);
UPDATE public.profiles ...;
UPDATE public.user_settings ...;
```

The updates affect zero rows unless the test explicitly inserts `public.profiles` and `public.user_settings` first. This single fact explains clusters 1-4 without implicating their production triggers or builders.

## Cluster evidence

### 1. Routine-mode invalidation

`adaptive_alert_routine_modes.sql` inserts `auth.users`, never inserts `public.profiles`, then updates `public.profiles`. The profile invalidation trigger is present, but no row reaches it.

Targeted result: 15 assertions, failures only at 14-15. Both expected invalidation rows are absent.

Repair route: add an explicit profile fixture before the updates. Retain both invalidation assertions unchanged. If the file remains red after that fixture correction, stop and trace the next guard rather than changing the trigger contract.

### 2. Routine-mode cohort priors

`routine_mode_cohort_priors.sql` has the same missing-profile fixture. The cohort builder joins candidate personal rows to profiles for routine mode and consent. With zero profiles, contributor count is zero and `published=0`; later profile updates also cannot increment invalidation generations.

Targeted result: 42 assertions, failures 9-11, 17-18, 23, 25-27, 29, 31-35. The pattern is internally consistent with zero profile rows: aggregate publication, contributor count, invalidation, and republish assertions fail together.

Repair route: insert all explicit profile fixtures, including consent and canonical routine modes, before personal/cohort rows. Preserve contributor, privacy, generation, idempotency, and live-snapshot assertions.

### 3. Shadow operational context and dirty queue

`adaptive_alert_shadow_operational_schema.sql` inserts `auth.users`, then only updates `profiles` and `user_settings`.

- Missing settings make capture use the intended fallback `balanced/UTC`, so assertion 34 receives `balanced`, not fixture-expected `low`.
- Invalid-timezone and future-source-timestamp updates match zero rows, so assertions 35-36 receive NULL instead of their expected reasons.
- The consent update matches zero profiles, so assertion 40 cannot exercise the dirty trigger.

Targeted result: 42 assertions, failures only at 34-36 and 40.

Repair route: insert explicit profile and settings rows before capture. Preserve the existing invalid-timezone, future-timestamp, and dirty-queue expectations.

### 4. Routine safety

`routine_safety.sql` also inserts only `auth.users`. A rolled-back local reproduction created the same overdue `due_notified` interval task and called the current `public.process_checkin_tasks()`.

Observed inside the transaction:

```text
profiles=0
notifications=0
failure sqlstate=23502
failure message=null value in column "body" of relation "notifications" violates not-null constraint
task cycle_state=due_notified
```

The function selects the ward display name into `_wname`. No profile row leaves `_wname` NULL; concatenating the notification body stays NULL; `notifications.body NOT NULL` rejects the insert. The 2026-08-08 per-subject isolation wrapper correctly records the failure in `private.job_failures` and leaves the task for retry instead of aborting all subjects. The diagnostic deliberately raised at the end, and follow-up counts confirmed zero residual users, tasks, or failures.

Repair route:

1. Add explicit ward/creator profiles and ward settings.
2. Keep the offline-upload `task_missed` assertion; it should then pass through the intended notification branch.
3. Replace the passive-ping auto-resolution expectation with the ADR-0039 invariant that the alert remains open.
4. Seed `account_normal_bounds` explicitly before sensitivity assertions. Prove no-evidence returns NULL, then prove an evidence-backed 90-minute normal bound becomes 90/135/180 minutes under high/balanced/low buffers.
5. Keep `user_activity_profiles` quarantined from live authority and keep `my_routine_status` aligned to the evidence-backed live value.

The missing notification is not a production function defect: production users are expected to have profiles, and the failure-isolation behavior is correct. A separate data-integrity audit may later check whether any real `auth.users` rows lack profiles, but that is not evidence in this local fixture failure and is outside S2.1.

### 5. NULL-intolerant account threshold shadow

`account_threshold_shadow.sql` does create profiles/settings. It builds the older ADR-0035 candidate profile, then calls `private.record_account_threshold_shadow`. The current live comparator is `private.silence_threshold`, which reads `account_normal_bounds` and correctly returns NULL when no usable account normal bound exists.

Current schema/function conflict:

- `account_threshold_shadow.live_threshold_minutes` is `NOT NULL` and checked `> 0`;
- the recorder inserts the nullable result directly;
- its live episode and divergence calculations also assume a live comparator exists;
- the targeted test aborts at the recorder with SQLSTATE 23502 before later assertions run.

This is a real defect in an offline shadow tool, not in the live alert path.

#### Accepted repair contract

ADR-0037 says a no-evidence account has no invented live threshold and must be marked honestly. ADR-0035 retains this table as a record-only candidate-versus-live tool. Those two accepted decisions leave one truth-preserving representation:

- keep the shadow row, because skipping it would erase the candidate audit record;
- keep candidate threshold/count fields defined;
- store NULL for the unavailable live comparator and every value whose meaning depends on comparing with live;
- never store 0 or a fallback threshold, because either would fabricate live behavior.

The append-only repair should therefore make these columns nullable:

- `live_threshold_minutes`
- `episodes_live`
- `episodes_candidate_only`
- `episodes_live_only`

The already-nullable divergence timestamp/gap fields remain NULL when the comparator is unavailable. `gaps_evaluated`, `episodes_candidate_floored`, and `episodes_candidate_unfloored` remain non-null because they are independently defined. The recorder must condition its tallies on comparator availability; ordinary SQL NULL filtering must not silently convert unknown live counts into zero.

The existing comparison test should explicitly seed `account_normal_bounds` for its three comparator subjects, preserving its arithmetic. A separate no-evidence subject should prove: recorder lives, row is retained, candidate values are present, live-dependent values are NULL, and no live table or alert state changes.

## Accepted-contract migrations outside the five traces

The earlier S2 report remains valid for the other inherited red files:

- old `silence_threshold` and `process_escalations` hashes must move to the current accepted definitions;
- fixed/history-seeded threshold expectations must move to explicit `account_normal_bounds` fixtures;
- passive activity must not resolve alerts;
- fresh baseline tests must own their enabled shadow/model fixtures instead of assuming environment activation;
- fresh baseline cron/model assertions must follow ADR-0028/0038 rather than fabricate production-specific state.

These are test/fixture migrations, not permission to restore superseded behavior. The three `s1_*_contract.sql` files remain deliberately red until S3 implements ADR-0039 coverage health and care-authority contracts.

## Independent challenge

DeepSeek V4 independently challenged all five causal claims in one no-tool/no-filesystem turn. It agreed at high confidence that clusters 1-3 are fixture defects, cluster 4 splits into one fixture defect plus six obsolete expectations, and cluster 5 is a real runtime/schema conflict. It correctly objected that NULL storage should not be chosen without accepted-contract evidence. The Manager resolved that objection from ADR-0035's retained record-only shadow and ADR-0037's explicit no-invented-threshold/honest-marking rules: retain the row and make only live-dependent outputs NULL.

V4 used 2,761 exact provider tokens, made zero write attempts, had no tools or subdelegation, and had no production authority.

## Safety and platform impact

This trace changed no running behavior. The planned repair adds no Android/iOS permission, background mode, entitlement, notification category, tracking disclosure, native API, or Store capability. Its platform relevance is honesty: internal shadow evidence must represent `Unknown` as unknown, and passive activity must not be presented as proof that a guardian path worked.

Online KC, production Supabase, local `main`, remotes, deployments, releases, APK/AAB, iOS PWA, iOS Native, and Tauri artifacts were untouched.
