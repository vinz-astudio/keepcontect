# KC S2.2 Database Technical Repair Result

Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis`
Scope: isolated local worktree only

## Result

Packages 1-3 of the accepted S2.1 plan are implemented locally.

- One append-only migration repairs the internal, record-only account threshold shadow contract.
- A subject with no accepted live comparator now retains its candidate audit row.
- `live_threshold_minutes`, `episodes_live`, `episodes_candidate_only`, and `episodes_live_only` remain NULL when comparison is impossible; candidate evidence remains populated.
- Four pgTAP fixture families now create their own `profiles` and `user_settings` state.
- Passive activity remains unable to answer or resolve an open safety alert.
- No-evidence live threshold remains NULL; sensitivity arithmetic is tested only after an explicit usable 90-minute `account_normal_bounds` fixture.
- No `auth.users` provisioning trigger, production seed, alert lifecycle change, online change, native change, or release change was added.

## TDD evidence

Before the migration, the expanded `account_threshold_shadow.sql` failed at the intended contract boundary:

```text
SQLSTATE 23502
null value in column "live_threshold_minutes" of relation "account_threshold_shadow"
failing subject: 36000000-0000-4000-8000-000000000004
```

After the migration, the complete targeted database gate passed:

```text
Files=7, Tests=171
Result: PASS
```

Covered files:

- `account_threshold_shadow.sql` — 18
- `per_subject_failure_isolation.sql`
- `s2_data_api_acl_repair.sql`
- `adaptive_alert_routine_modes.sql`
- `routine_mode_cohort_priors.sql`
- `adaptive_alert_shadow_operational_schema.sql`
- `routine_safety.sql` — 36

The local schema dump confirms exactly the four intended live-dependent columns became nullable while candidate counts and `gaps_evaluated` remain NOT NULL. Existing checks, primary/foreign keys, RLS, SECURITY DEFINER, empty search path, UTC, ownership, and `PUBLIC` execute revocation remain present.

## Repository gates

- `npm run typecheck`: PASS
- `npm run build`: PASS, with the repository's existing chunk/import warnings
- `git diff --check`: PASS
- Fresh agy independent read-only audit: PASS, zero findings, zero write attempts, zero subdelegations
- `npm test`: 333 passed, 15 failed. The failures are inherited source-manifest/static-contract/iOS S1 gaps already outside this repair's write set; no failure targets the new migration or five changed pgTAP files.

## Remaining S2 work

Packages 4-6 remain: migrate the ten inherited pgTAP contract fixtures, converge the historical database suite, and confirm the only deliberate database RED set is the three S1 contracts reserved for S3.

No push, merge, deploy, linked-Supabase mutation, release, AAB signing, TestFlight action, or Store submission occurred.
