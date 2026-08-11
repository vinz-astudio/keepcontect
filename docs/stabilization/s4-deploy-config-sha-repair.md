# Deploy repair — a model version disagreeing with its own digest

Task: `KC-DEPLOY-SHA-011` · Owner: Claude · Date: 2026-08-10

## What I broke

`20260809210000_s2_reauthorize_live_threshold_pin`, which I deployed to
production at the human's request, re-pinned
`emergency.expected_live_definition_sha256` inside `config` **and did not
recompute `config_sha256`**. Both production model versions immediately stopped
matching their own integrity digest.

`private.run_adaptive_alert_shadow_cycle` validates that digest before doing
anything, so the first cycle after re-enabling raised
`shadow_version_validation_failed` and began burning the runtime's failure
budget — three of those and the subsystem disables itself again, which is
exactly how coverage collection died on 2026-08-04 for a different reason.

Caught within minutes because the deployment was verified rather than assumed:
enabling the runtime, running one cycle deliberately, and reading the failure
code is what surfaced it.

## Why local tests did not catch it

`public.alert_model_versions` is empty on a fresh local base — ADR-0038 leaves
activation to the environment. The migration's `UPDATE ... WHERE pin = retired`
therefore matched **zero rows** locally, and that branch was never executed by
any test. It could only fail where real rows exist.

That is the sharpest lesson of this deployment: a migration branch that touches
data can be fully green locally and still be untested, if the local database has
no data for it to touch.

## The fix

Production was repaired immediately by recomputing the digest for the two
mismatched rows; the next cycle returned `completed`, evaluating 8 of 8
subjects.

The repository fix is append-only — the deployed migration is not edited:

* `20260810030000_s3_repair_model_version_config_sha.sql` — idempotent,
  recomputes the digest only for rows that disagree with their own config.
  Changes no config, no pin, no runtime state.
* `supabase/tests/model_version_config_integrity.sql` — the assertion that would
  have caught this. It checks the invariant holds, then deliberately inserts a
  row with a wrong digest to prove the check actually bites, then proves the
  repair expression restores consistency.

## Evidence

| Gate | Result |
|---|---|
| `model_version_config_integrity.sql` (new) | 3/3 |
| Fresh safe replay | **37 files / 842 tests — All tests successful, PASS** |
| `git diff --check` | PASS |
| Production after repair | `enabled=true`, `consecutive_failures=0`, `last_failure_code=null`, cycle `completed` 8/8, **0 open alerts** |

## Production state after this session

* Coverage collection is **running again** — first successful cycle since
  2026-08-04.
* Deployed to production so far: **only** the pin re-authorization and this
  repair. The five S3 migrations are still local.
* No alert, notification or user-visible behaviour changed. The shadow subsystem
  is record-only.
