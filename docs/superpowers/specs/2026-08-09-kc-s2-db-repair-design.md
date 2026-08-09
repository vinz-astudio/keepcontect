# KC S2 Database Repair Design

## Goal

Repair only proven Data API ACL drift, make local database replay unable to contact production Edge Functions, and classify every remaining S0 database failure without changing disputed alert/shadow semantics.

## Root causes

1. `20260808160000_baseline_from_production.sql` restores `GRANT ALL` and later revokes `REFERENCES`, `TRIGGER`, and `TRUNCATE` from fourteen internal tables. On PostgreSQL 17, `ALL` includes `MAINTAIN`; the recovery block does not revoke it. Local pgTAP and direct catalog queries reproduce `MAINTAIN` for `anon`, `authenticated`, and `service_role`.
2. `public.gm_mutes` has `GRANT ALL` for all three Data API roles even though KC uses the GM-gated RPC and defines no direct table policy. Direct table reachability is broader than the accepted narrow mute authority.
3. The production baseline embeds five production Edge Function URLs. A local reset can schedule or execute those URLs. Local test replay therefore needs a hash-pinned disposable copy that rewrites only those five URLs to `127.0.0.1:1` and adds a local-only final migration that deactivates cron jobs.
4. Threshold body/hash, shadow activation/seeding, historical cohort semantics, and passive-activity auto-resolution are accepted-source conflicts. This package records them; it does not choose a side.

## Scope

- Add one S2 pgTAP ACL regression file.
- Add one append-only ACL migration. No old migration edit.
- Add a local-only replay wrapper and unit tests.
- Re-run inherited pgTAP files and write one diagnosis report.
- Preserve current `private.silence_threshold`, `public.process_escalations`, shadow runtime config, alert behavior, cron definitions in repository migrations, and all production state.

## ACL contract

These fourteen internal tables must expose zero table action to `PUBLIC`, `anon`, `authenticated`, and `service_role`:

- `account_gap_profiles`
- `account_normal_bounds`
- `account_threshold_shadow`
- `alert_gap_profiles`
- `alert_intervention_events`
- `alert_judgment_evaluations`
- `alert_judgment_shadow_decisions`
- `alert_judgment_subject_contexts`
- `alert_model_versions`
- `alert_observation_coverage_intervals`
- `alert_sleep_night_contexts`
- `routine_mode_cohort_generations`
- `routine_mode_cohort_invalidations`
- `routine_mode_cohort_priors`

`public.gm_mutes` also exposes zero direct table action to those roles. `authenticated` retains `EXECUTE` on `public.gm_mute_user(uuid,timestamptz,text)`; all application access remains RPC-only.

## Local replay contract

- Source baseline hash must equal `4c6b12de4e20ad937aca5ac28b88a073ed39323f5f2e2ef5a756ace92fe6fa26` before copying.
- Output stays under `supabase/.temp/s2-safe-replay/project` after real-path containment checks.
- Copy only `supabase/config.toml`, `supabase/migrations/**`, and `supabase/tests/**`.
- Replace exactly five occurrences of `https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/` in the disposable baseline with `http://127.0.0.1:1/functions/v1/`.
- Add only `20991231235959_local_test_disable_cron.sql` to the disposable copy; it deactivates every local `cron.job` through `cron.alter_job`.
- Commands contain `--local`, never `--linked`, `db push`, `migration repair`, or a remote DB URL.
- Source migrations remain byte-for-byte unchanged.

## Non-scope

- No production Supabase query, migration apply, deploy, push, release, or remote branch change.
- No threshold/hash/activation/cohort/Concern/Special Attention/native implementation.
- No expectation edits in inherited tests.
- No claim that the full DB suite is green if semantic conflicts remain.

## Acceptance

- New ACL test fails on the inherited baseline for the reproduced grants.
- After the new migration, all new ACL assertions pass and the ACL-only assertions in inherited files pass.
- Safe replay wrapper tests pass and a fresh local replay cannot address a production hostname.
- Full pgTAP report gives exact remaining failures and routes each to fixed, human decision, or separate diagnosed repair.
- Typecheck/build pass; diff is limited to S2 test infrastructure, one append-only migration, spec/plan/report.
