# S2 Database Root-Cause Diagnosis

Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis`
Base: `57e74c79348218110d6898736e7153369f32518d`

## Outcome

S2 repaired one proven defect class only: unintended direct Data API table authority. The repair is one append-only migration and changes no function, policy, trigger, cron definition, runtime flag, model seed, alert lifecycle, native project, release state, or production state.

The database suite is still **not green**. After a clean local replay, 15 inherited S0 files remain red for semantic or fixture/runtime conflicts; three S1 contract files are deliberately red for later stages.

## Proven defect and repair

The canonical baseline restored `GRANT ALL` and later revoked only `REFERENCES`, `TRIGGER`, and `TRUNCATE` from internal operational tables. On PostgreSQL 17, `ALL` also includes `MAINTAIN`. Consequently:

- `anon`, `authenticated`, and `service_role` retained `MAINTAIN` on fourteen RPC-only operational tables;
- the same three roles retained every direct table action on `public.gm_mutes`;
- RLS existed, but object-level grants still contradicted the locked least-privilege/RPC-only contract.

Repair: `20260809123646_s2_internal_data_api_acl_repair.sql` revokes all table privileges from `PUBLIC`, `anon`, `authenticated`, and `service_role` on the exact fifteen-table set. It does not alter the authenticated `gm_mute_user` RPC execute grant.

Regression: `s2_data_api_acl_repair.sql` has six assertions covering all eight PostgreSQL 17 table actions, `PUBLIC`, RLS, and the retained RPC path.

Evidence:

- pre-migration RED twice: assertions 1 and 3 failed, with no harness abort;
- post-migration GREEN twice: `Files=1, Tests=6, Result: PASS` both runs;
- all inherited ACL assertions disappeared after repair;
- `adaptive_alert_gap_profiles.sql` and `adaptive_sleep_candidate.sql` now pass completely.

## Safe local replay boundary

The baseline contains five production Edge Function URL occurrences in cron definitions. The S2 wrapper:

1. verifies the source baseline SHA-256 is `4c6b12de4e20ad937aca5ac28b88a073ed39323f5f2e2ef5a756ace92fe6fa26`;
2. copies Supabase config, migrations, and tests under `supabase/.temp/s2-safe-replay/project`;
3. replaces exactly those five URL prefixes with `http://127.0.0.1:1/functions/v1/` only in the disposable copy;
4. adds a disposable final migration that deactivates every local cron job;
5. runs only `db reset --local` and `test db --local`;
6. fails closed on hash drift, replacement-count drift, path escape, symlink escape, or child-command failure.

Vitest: 7/7 PASS. After replay: `active_jobs=0`, `prod_url_jobs=0`. The source baseline remained byte-identical. No linked/remote Supabase command, deployment, release, push, or production database operation was run.

## Clean replay result

Command: `node scripts/s2-safe-db-replay.mjs`

- Files: 30
- Tests: 732
- Result: FAIL
- Historical S0 failing files after ACL repair: 15
- Fully fixed historical files: 2
- Deliberately red S1 contract files: 3
- Harness/parser failure: `adaptive_alert_shadow_operational_cycle.sql` aborts after 21/46 on `shadow_live_hash_mismatch`

The totals decompose as 696 historical tests + 30 S1 contract tests + 6 S2 ACL tests.

## Inherited file classification

| File | S2 status | Remaining root cause |
| --- | --- | --- |
| `adaptive_alert_gap_profiles.sql` | FIXED | Missing PostgreSQL 17 `MAINTAIN` revoke; now fully green. |
| `adaptive_sleep_candidate.sql` | FIXED | Missing PostgreSQL 17 `MAINTAIN` revoke; now fully green. |
| `gm_mute_user.sql` | OBSOLETE-EXPECTATION | Direct table authority fixed; test 13 still pins the pre-ADR-0037 `silence_threshold` definition hash. |
| `adaptive_alert_routine_modes.sql` | DIAGNOSED-UNFIXED | ACL fixed; tests 14-15 still see no expected routine/consent invalidation rows although trigger and generation seeds exist. No semantic edit made. |
| `adaptive_alert_candidate_evaluator.sql` | OBSOLETE-EXPECTATION | ACL fixed; tests 68-70/74 still require the pre-ADR-0037 candidate source, fixed emergency threshold, and old live hashes. |
| `adaptive_alert_shadow_schema.sql` | FIXTURE/EXPECTATION-DRIFT | ACL fixed; tests 59-60 expect a pre-baseline cron inventory and environment-specific seeded model that ADR-0038 deliberately does not encode as schema seed data. |
| `account_threshold_shadow.sql` | DIAGNOSED-UNFIXED | ADR-0037 intentionally allows no-evidence threshold NULL, but the shadow recorder still writes it into a NOT NULL column; old hash expectation is separately obsolete. |
| `history_seeded_live_threshold_and_sleep.sql` | OBSOLETE-EXPECTATION | ADR-0037 replaced the history-seeded live threshold with `account_normal_bounds`; these tests still assert the superseded authority. |
| `routine_safety.sql` | MIXED | Five threshold assertions and live-ping auto-resolution are obsolete under ADR-0037/0039; the missing `task_missed` path still needs isolated diagnosis. |
| `routine_mode_cohort_priors.sql` | DIAGNOSED-UNFIXED | Builder publishes zero and invalidation generations/rows do not move as expected; earliest rejecting guard still needs a focused trace. |
| `adaptive_alert_shadow_coverage_contract.sql` | FIXTURE/PHASE-DRIFT | ADR-0028 base objects intentionally start `false/false` and unversioned; activation is a separate environment phase. S1/ADR-0039 coverage-health work remains future S3 implementation. |
| `adaptive_alert_shadow_operational_cycle.sql` | DIAGNOSED-UNFIXED | Cycle aborts on a superseded live-definition hash before completing its plan; fixture/config must first align to ADR-0037. |
| `adaptive_alert_shadow_operational_schema.sql` | DIAGNOSED-UNFIXED | Context capture values and cohort dirty queue differ from fixture expectations; exact branch still needs focused trace. |
| `adaptive_alert_shadow_recorder.sql` | OBSOLETE-EXPECTATION | Historical `process_escalations`/`silence_threshold` hash pins predate the accepted live successors. |
| `adaptive_shadow_history_seeded_activation.sql` | FIXTURE/PHASE-DRIFT | It assumes environment activation data exists in a fresh baseline and also pins the superseded live threshold. |
| `adaptive_shadow_live_hash_canonicalization.sql` | OBSOLETE-EXPECTATION | LF normalization is not the issue; the expected semantic body predates ADR-0037. |
| `adaptive_shadow_subject_context_provenance.sql` | FIXTURE/PHASE-DRIFT | Capture correctly requires a valid enabled shadow version, but the fresh-baseline fixture supplies none. |

## Shared causal clusters

1. **Accepted live threshold vs obsolete tests.** ADR-0037 makes `account_normal_bounds` authoritative and permits NULL when evidence is insufficient; ADR-0039 further restricts training to healthy continuous coverage and repeated comparable long gaps. Older tests still expect history-seeded 90/135/180-style thresholds and old hashes.
2. **Accepted alert truth vs obsolete tests.** ADR-0039 says passive/technical activity cannot answer an alert. Tests that expect a live ping to auto-resolve or pin an older `process_escalations` body must migrate.
3. **Fresh baseline vs environment activation fixtures.** ADR-0028 base objects start disabled/unseeded and activation is separate; ADR-0038 preserves current cron structure but deliberately does not fabricate environment-specific model rows. Tests must establish their own activation fixture or test the safe bootstrap state.
4. **Technical paths still unpinned.** Routine-mode invalidation, cohort rebuild guards, context capture, dirty-queue creation, and `task_missed` need focused traces before they can be called defects or obsolete tests.

DeepSeek V4 independently grouped clusters 1-3 as high-confidence contract conflicts and cluster 4 as evidence-insufficient/diagnosed-unfixed. Manager then resolved the apparent conflicts against accepted ADR-0037, ADR-0039, ADR-0028, and ADR-0038: clusters 1-3 require test/fixture migration, not a new product decision. V4 had no filesystem, write, network, subdelegation, or production authority.

Google/agy then completed a separate read-only integrated audit with verdict **PASS** and no findings. Its sandbox attested one turn, zero write attempts, zero subdelegations, and no tools outside the allowlist.

## Decision state before semantic repair

No new human product decision is required for the three main historical conflicts:

1. ADR-0037/0039 already make the current personal normal-bound model authoritative, require healthy continuous coverage, and forbid invented fallback thresholds.
2. ADR-0039 already forbids passive/technical activity from answering an alert; only explicit alert-bound resolution/confirmation may do so.
3. ADR-0028/0038 already separate safe fresh bootstrap from environment activation and preserve cron structure without fabricating environment-specific model data.

Routine invalidation, cohort, context capture, `task_missed`, and the NULL-intolerant shadow recorder should be technically traced next. S1 coverage-health implementation remains S3 work under the already accepted ADR-0039 contract.

## Store/native relevance

The ACL repair improves least privilege without adding review-sensitive permissions or background capabilities. The unresolved protection-health and shadow-bootstrap conflicts matter to AAB/iOS/Tauri honesty: an unavailable or unverified guard path must be reported as Limited/Unknown, never presented as Ready. APK/PWA behavior is not being used as proof that the final native apps will pass store review or sustain background protection.
