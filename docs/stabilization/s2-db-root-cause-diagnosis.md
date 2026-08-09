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
| `gm_mute_user.sql` | CONFLICT | Direct table authority fixed; test 13 still pins a different `silence_threshold` definition hash. |
| `adaptive_alert_routine_modes.sql` | DIAGNOSED-UNFIXED | ACL fixed; tests 14-15 still see no expected routine/consent invalidation rows although trigger and generation seeds exist. No semantic edit made. |
| `adaptive_alert_candidate_evaluator.sql` | CONFLICT | ACL fixed; tests 68-70/74 disagree with current candidate source, emergency threshold, and live function hashes. |
| `adaptive_alert_shadow_schema.sql` | CONFLICT | ACL fixed; tests 59-60 expect a different cron set and one seeded model while the baseline deliberately omits the model seed. |
| `account_threshold_shadow.sql` | CONFLICT | `private.silence_threshold` returns NULL without a usable `account_normal_bounds` row; recorder writes that into a NOT NULL column; historical hash pin also differs. |
| `history_seeded_live_threshold_and_sleep.sql` | CONFLICT | Tests seed history/shadow state, but current live threshold reads `account_normal_bounds`, not the history model. |
| `routine_safety.sql` | MIXED | Five failures share the NULL threshold conflict; live batch does not auto-resolve an alert; the missing `task_missed` path still needs isolated diagnosis. |
| `routine_mode_cohort_priors.sql` | DIAGNOSED-UNFIXED | Builder publishes zero and invalidation generations/rows do not move as expected; earliest rejecting guard still needs a focused trace. |
| `adaptive_alert_shadow_coverage_contract.sql` | CONFLICT | Test expects runtime `enabled=true` and `accept_coverage_leases=true`; baseline intentionally starts `false/false` with no version. |
| `adaptive_alert_shadow_operational_cycle.sql` | CONFLICT | Cycle aborts on live-definition hash mismatch before completing its plan. |
| `adaptive_alert_shadow_operational_schema.sql` | DIAGNOSED-UNFIXED | Context capture values and cohort dirty queue differ from fixture expectations; exact branch still needs focused trace. |
| `adaptive_alert_shadow_recorder.sql` | CONFLICT | Historical `process_escalations`/`silence_threshold` hash pins differ from current live definitions. |
| `adaptive_shadow_history_seeded_activation.sql` | CONFLICT | Downstream of deliberately absent model seed/runtime version plus live hash disagreement. |
| `adaptive_shadow_live_hash_canonicalization.sql` | CONFLICT | LF/normalized representation is rejected because the semantic function body hash differs, not because of line endings alone. |
| `adaptive_shadow_subject_context_provenance.sql` | CONFLICT | Capture requires a valid enabled shadow version; baseline deliberately supplies none. |

## Shared causal clusters

1. **Live threshold contract split.** Current code uses `account_normal_bounds` and may return NULL; older tests expect history-seeded 90/135/180-style thresholds and pin a different function body.
2. **Live escalation contract split.** Tests pin another `process_escalations` body and some expect live activity to resolve an alert, while ADR-0039 says passive/technical activity cannot answer an alert.
3. **Shadow bootstrap contract split.** Baseline deliberately starts disabled and unversioned; older tests expect seeded/enabled shadow state, validation runs, and a different cron/model inventory.
4. **Technical paths still unpinned.** Routine-mode invalidation, cohort rebuild guards, context capture, dirty-queue creation, and `task_missed` need focused traces before they can be called defects or obsolete tests.

DeepSeek V4 independently classified clusters 1-3 as high-confidence contract conflicts and cluster 4 as evidence-insufficient/diagnosed-unfixed. Manager verified those conclusions against the repository; V4 had no filesystem, write, network, subdelegation, or production authority.

Google/agy then completed a separate read-only integrated audit with verdict **PASS** and no findings. Its sandbox attested one turn, zero write attempts, zero subdelegations, and no tools outside the allowlist.

## Human decisions required before semantic repair

No decision is needed for the ACL repair. Before changing the remaining semantic paths, the next checkpoint must settle:

1. Which live threshold definition is authoritative: current `account_normal_bounds`/NULL-on-insufficient-signal behavior, or the older history-seeded threshold contract and pinned hash.
2. Whether any genuinely live user event may resolve an alert automatically, versus the accepted rule that only explicit alert-bound resolution/confirmation can do so.
3. Whether a fresh environment must start shadow processing disabled and unseeded, or ship a seeded/enabled model and scheduled cycle.

Routine invalidation, cohort, context capture, and `task_missed` should be technically traced first; they are not yet appropriate human product choices.

## Store/native relevance

The ACL repair improves least privilege without adding review-sensitive permissions or background capabilities. The unresolved protection-health and shadow-bootstrap conflicts matter to AAB/iOS/Tauri honesty: an unavailable or unverified guard path must be reported as Limited/Unknown, never presented as Ready. APK/PWA behavior is not being used as proof that the final native apps will pass store review or sustain background protection.
