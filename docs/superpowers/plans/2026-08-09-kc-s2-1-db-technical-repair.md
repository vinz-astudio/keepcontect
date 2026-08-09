# KC S2.1 Database Technical Repair Plan

Date: 2026-08-09
Status: ready for a separate guarded implementation task
Scope: isolated local worktree only; no deploy, linked Supabase, release, push, or native-project change

## Goal

Repair the one proven shadow-runtime defect, correct four broken fixture families, and migrate inherited tests to ADR-0037/0039 and ADR-0028/0038 without restoring superseded behavior.

The completion target for S2.1 is:

1. every historical (non-`s1_*`) pgTAP file passes after a fresh safe local replay;
2. the only remaining full-suite failures are the three deliberately red S1 contracts reserved for S3;
3. no live alert, notification, cron, permission, native capability, production, or release behavior changes.

## Package 1 — Prove the NULL-comparator contract RED

Files:

- Modify `supabase/tests/account_threshold_shadow.sql`

Steps:

1. Preserve the existing three candidate-versus-live arithmetic subjects, but insert explicit `account_normal_bounds` fixtures with a 90-minute usable normal bound so the live comparator is evidence-backed.
2. Add a fourth subject with a valid candidate profile and no usable `account_normal_bounds` row.
3. Assert that the fourth row is retained, candidate fields remain populated, and these live-dependent fields are NULL: `live_threshold_minutes`, `episodes_live`, `episodes_candidate_only`, `episodes_live_only`, and divergence fields.
4. Assert the recorder has no effect on alerts, alert events, notifications, behavior pings, device state, or `private.silence_threshold`.
5. Run the single file against the current schema and record RED at the recorder's 23502 constraint failure.

Command:

```powershell
npx supabase test db supabase/tests/account_threshold_shadow.sql
```

Stop if RED occurs for a reason other than the proven NULL/NOT-NULL contract.

## Package 2 — Append-only shadow-runtime repair

Files:

- Add `supabase/migrations/<timestamp>_s2_account_threshold_shadow_nullable_live_comparator.sql`
- Keep the Package 1 test changes

Migration contract:

1. Drop `NOT NULL` from `live_threshold_minutes`, `episodes_live`, `episodes_candidate_only`, and `episodes_live_only`; retain their checks, which correctly permit NULL.
2. `CREATE OR REPLACE` `private.record_account_threshold_shadow` from the current catalog definition, changing only comparator-null handling.
3. Preserve candidate calculations and row retention.
4. When the live comparator is NULL, return NULL for all live-dependent counts and divergence values; do not let `FILTER`/`coalesce` turn unknown into zero.
5. When the comparator exists, preserve current arithmetic byte-for-byte in behavior.
6. Preserve SECURITY DEFINER, empty search path, UTC, ownership, execute revokes, RLS, ACL, scheduler state, and all live functions.

GREEN gates:

```powershell
npx supabase test db supabase/tests/account_threshold_shadow.sql
npx supabase test db supabase/tests/per_subject_failure_isolation.sql
npx supabase test db supabase/tests/s2_data_api_acl_repair.sql
```

Catalog assertions must confirm only the four intended columns became nullable and all four internal-table ACL tests remain closed.

## Package 3 — Repair explicit fixture ownership

Files:

- Modify `supabase/tests/adaptive_alert_routine_modes.sql`
- Modify `supabase/tests/routine_mode_cohort_priors.sql`
- Modify `supabase/tests/adaptive_alert_shadow_operational_schema.sql`
- Modify `supabase/tests/routine_safety.sql`

Rules:

- Every test user that needs application state inserts its own `public.profiles` row.
- Every test that updates sensitivity/timezone/sleep inserts its own `public.user_settings` row.
- Use explicit values for consent, canonical routine mode, sensitivity, timezone, and timestamps.
- Do not add an `auth.users` trigger or production seed to make tests pass.
- Preserve privacy, invalidation, dirty-queue, failure-isolation, and offline-safety assertions.

Run each file independently after its fixture edit. If a later guard fails, diagnose it before editing runtime code.

```powershell
npx supabase test db supabase/tests/adaptive_alert_routine_modes.sql
npx supabase test db supabase/tests/routine_mode_cohort_priors.sql
npx supabase test db supabase/tests/adaptive_alert_shadow_operational_schema.sql
npx supabase test db supabase/tests/routine_safety.sql
```

`routine_safety.sql` additionally must:

- expect a passive live ping to leave an alert open;
- prove no-evidence `silence_threshold` is NULL;
- seed a usable 90-minute `account_normal_bounds` row before checking 90/135/180-minute sensitivity results;
- prove `user_activity_profiles` cannot widen or replace that live bound;
- keep the evidence-backed `my_routine_status` server-truth assertion.

## Package 4 — Migrate inherited accepted-contract fixtures

Files, handled one at a time:

- `supabase/tests/gm_mute_user.sql`
- `supabase/tests/adaptive_alert_candidate_evaluator.sql`
- `supabase/tests/adaptive_alert_shadow_schema.sql`
- `supabase/tests/history_seeded_live_threshold_and_sleep.sql`
- `supabase/tests/adaptive_alert_shadow_coverage_contract.sql`
- `supabase/tests/adaptive_alert_shadow_operational_cycle.sql`
- `supabase/tests/adaptive_alert_shadow_recorder.sql`
- `supabase/tests/adaptive_shadow_history_seeded_activation.sql`
- `supabase/tests/adaptive_shadow_live_hash_canonicalization.sql`
- `supabase/tests/adaptive_shadow_subject_context_provenance.sql`

Migration rules:

1. Replace superseded hard-coded live hashes with the current canonical helper/hash contract; do not weaken fail-closed hash validation.
2. Replace history-seeded/fixed threshold authority with explicit `account_normal_bounds` fixtures and NULL/no-evidence assertions.
3. Keep passive activity unable to answer alerts.
4. Make every test that needs an enabled/versioned shadow model create that fixture itself.
5. Make fresh-baseline tests expect disabled/unseeded bootstrap and the ADR-0038 canonical cron structure.
6. Do not seed environment-specific model IDs or activation rows in migrations.
7. Keep all privacy, RLS, ACL, no-live-side-effect, Guardian exclusion, idempotency, provenance, and atomic-failure assertions.

After each edit, run only that file first. `adaptive_alert_shadow_operational_cycle.sql` currently aborts early; after correcting its live hash, treat any newly exposed failure as a new diagnostic stop, not permission to relax the remaining plan.

## Package 5 — Historical-suite convergence

Run the safe replay preparation/reset, then execute every historical test plus S2 tests while excluding only:

- `s1_alert_activity_concern_contract.sql`
- `s1_care_authority_contract.sql`
- `s1_coverage_learning_health_contract.sql`

Acceptance: every selected file passes, with no parser abort, no skipped file, and exact totals recorded. Then run the full suite and confirm its failure set is exactly those three S1 files and no others.

The safe replay postconditions remain:

```text
active local cron jobs = 0
local cron commands containing production Edge URL = 0
source baseline SHA-256 unchanged
```

## Package 6 — Repository and product gates

Run:

```powershell
npm run typecheck
npm test
npm run build
git diff --check
git status --short
```

Inspect the exact diff and verify:

- one new append-only migration only;
- no historical migration edits;
- only the declared pgTAP files changed;
- no alert lifecycle, notification dispatch, cron, native permission, entitlement, background mode, API key, release, or production change;
- S1 RED contracts remain intact for S3 rather than being deleted, skipped, or marked passed.

Request one fresh independent read-only integrated audit after all deterministic gates pass. Correct findings locally before any commit. Commit locally only; production application, push, merge, deploy, release, AAB signing, TestFlight, or Store submission requires a separate human checkpoint.

## Rollback

Before production there is no runtime rollback: discard the isolated branch/worktree changes.

If a future separately authorized production migration must be rolled back, use a new forward migration that restores the prior shadow recorder/schema contract. Never edit or remove an applied migration. The repair touches an internal offline shadow table only; it must not be used as a reason to alter the live threshold or alert lifecycle.
