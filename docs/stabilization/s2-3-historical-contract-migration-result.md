# S2.3 — Historical contract migration and database suite convergence

Task: `KC-S2-MIGRATE-004` · Owner: Claude · Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis` (isolated worktree) · Base: `4a145d4`

This report closes Packages 4, 5 and 6 of
`docs/superpowers/plans/2026-08-09-kc-s2-1-db-technical-repair.md`.

## Result

The historical pgTAP suite now converges. A fresh safe replay produces:

```text
Files=30, Tests=768
Failing files: exactly 3
  s1_alert_activity_concern_contract.sql      (11 tests, 4 failed)
  s1_care_authority_contract.sql              (11 tests, 5 failed)
  s1_coverage_learning_health_contract.sql    ( 8 tests, 7 failed)
```

Those three are the deliberate S1 product REDs reserved for S3. No other file
fails, no file aborts at the parser, and no file is skipped. Replay
postconditions hold: `active local cron jobs = 0`, `local cron commands
containing a production Edge URL = 0`, and the source baseline SHA-256 is
unchanged (the replay refuses to start otherwise).

## The one real defect found, and its repair

ADR-0037 rewrote `private.silence_threshold(uuid)` on 2026-08-04 to read
`public.account_normal_bounds`
(`20260804135728_silence_threshold_reads_normal_bounds.sql`,
`20260804190000_account_normal_upper_bound.sql`). The adaptive-shadow subsystem
pins the live definition it was authorized against, in
`emergency.expected_live_definition_sha256`, and refuses to run on any mismatch.
The last migration to touch that pin was `20260729163120_canonicalize_shadow_live_hash.sql`.

Neither August migration, and no later migration, re-authorized the pin.

The guard was therefore firing correctly — the live definition really had
changed — but for an authorized reason nobody recorded. The practical effect is
that the adaptive-shadow evaluator has been hard-blocked with
`shadow_live_hash_mismatch` since 2026-08-04 and has recorded nothing. Because
the subsystem is record-only and default-off, the failure was silent and safe;
it was also total.

Repair: `supabase/migrations/20260809210000_s2_reauthorize_live_threshold_pin.sql`,
append-only. It

* refuses to run unless `private.silence_threshold(uuid)` hashes to exactly the
  authorized value, so environment drift fails loudly instead of being blessed;
* moves the pin inside `private.alert_candidate_config_is_valid` and the
  `alert_model_versions_candidate_evaluator_contract_check` constraint, after
  asserting the retired pin appears exactly once;
* re-pins only stored model versions that carried the retired pin, leaving any
  other pin failing closed on its own evidence;
* leaves `private.shadow_live_definition_matches` untouched, so retired pins
  still accept only the definitions they were issued against and tampered
  definitions are still rejected.

TDD: the new guard in `adaptive_shadow_live_hash_canonicalization.sql`,
`authorized config pin tracks the current live threshold definition`, was RED
before the migration and GREEN after. It makes this specific drift impossible to
repeat silently.

Cascade: re-authorizing the pin turned five previously failing or aborting files
green on its own, including `adaptive_alert_shadow_operational_schema.sql`,
whose four failures were recorded in Known Issues as suspected test isolation or
flakiness. They were not flaky; they were downstream of this defect.

## Contract migrations

**Superseded live-definition hashes.** Test-side assertion literals for
`private.silence_threshold` (`6be4ed54…` → `c3efc6cc…`) and
`public.process_escalations` (`fde0f2ec…` → `dae555ee…`) were repinned to the
current accepted definitions. Fail-closed validation was not weakened;
`gm_mute_user.sql` additionally gained a semantic guard that the live threshold
authority reads `account_normal_bounds` and never the retired
`user_activity_profiles`.

The retired config pin also appeared in six pgTAP files outside the original
ten-file declaration. Leaving them behind would have broken files that were
green, so the identical one-line repin was applied to all thirteen carriers and
nothing else in those six files was touched.

**Retired fixed-threshold authority (ADR-0037/ADR-0039).**
`history_seeded_live_threshold_and_sleep.sql` and
`adaptive_alert_candidate_evaluator.sql` asserted a fixed 90/135/180 template
derived from `alert_gap_profiles`. They now assert that no account evidence
means `NULL`, that a shadow gap profile alone never becomes live authority, that
an explicit usable `account_normal_bounds` row plus the accepted additive
buffers produces 90/135/180, that the most recent usable bound supersedes older
ones, and that losing usable signal returns to `NULL` rather than a fabricated
fallback. The uncapped `bound + buffer` result is recorded as the accepted
contract; the retired ten-hour cap was not reintroduced.

**Retired seeded/enabled bootstrap (ADR-0028/ADR-0038).**
`adaptive_alert_shadow_schema.sql`, `adaptive_alert_shadow_coverage_contract.sql`
and `adaptive_shadow_history_seeded_activation.sql` asserted that a migration
seeded a model version and enabled the runtime. They now assert that a fresh
base seeds no model version, leaves the runtime unactivated and pointed at no
version, and that each file builds its own activation fixture before asserting
activation semantics — including running the validation cycle it asserts on.
`adaptive_alert_shadow_schema.sql` also now pins the shadow-family cron set to
the three accepted jobs, adding `account-shadow-cycle-v1` (`37 2 * * *`,
`private.rebuild_account_normal_bounds()`), which the ADR-0037 nightly bounds
work legitimately introduced.

**Fixture ownership.** `adaptive_alert_candidate_evaluator.sql` and
`adaptive_shadow_subject_context_provenance.sql` relied on an
`auth.users → profiles/user_settings` provisioning trigger that does not exist
in this baseline, so their profile-dependent updates hit zero rows. Both now own
those rows explicitly. No auth trigger and no production seed was added.

**Re-locked golden.** `adaptive_alert_replay.sql`'s golden input/output digests
moved because `input_sha256` covers the model config and `output_sha256` is
`digest(metrics || input_sha256)`. The metrics themselves are the invariant and
remain asserted by the decision and metric checks above the tripwire.

## Gates

| Gate | Result |
|---|---|
| Fresh safe replay | 30 files / 768 tests; failures exactly the three S1 contracts |
| Replay postconditions | local active cron 0; production-URL cron 0; baseline SHA unchanged |
| `npm run typecheck` | PASS |
| `npm run build` | PASS; only the pre-existing dynamic-import/chunk warnings |
| `git diff --check` | PASS |
| `npm test` | 333 passed / 15 failed / 348 |

The 15 Vitest failures are the inherited debt recorded in the S2.2 handoff and
are unchanged by this work: S1 iOS platform contract 2, `adaptiveShadowSecurity`
missing archived migration path 3, `routineSafetyMigration` bound to an old
migration filename 1, `thresholdContractMigration` bound to the retired
ADR-0022 path 2, `local-supabase-replay` missing archived source files 6, and
`adaptive-shadow-source-manifest` 1. They are static-contract and manifest debt
pointing at `supabase/migrations-archive/**`, not database behaviour, and they
were deliberately not "fixed" by inventing archive paths or relaxing the current
product contract.

## Scope and boundary

Changed: 16 pgTAP test files and one new append-only migration
(338 insertions / 131 deletions). No product source, no historical migration, no
alert lifecycle, notification, cron schedule, native permission, entitlement,
secret, version or release change.

No push, merge, deploy, release, signing, TestFlight or Store action. No
production or linked Supabase mutation. The online app was not interrupted, and
this branch is still not a release candidate.

## Next

1. S3 implements the S1 product REDs: active-alert-only Concern, coverage-valid
   learning, authoritative protection health, private default-off Special
   Attention, and the Guardian/Ward care surface.
2. The 15 inherited Vitest failures need their own decision on the
   `migrations-archive` normalisation-or-exemption question already recorded in
   Known Issues, together with the 41,172-line whitespace diagnostic from S0.
3. S4 takes the AAB, iOS Native and Tauri store, signing and device evidence.
