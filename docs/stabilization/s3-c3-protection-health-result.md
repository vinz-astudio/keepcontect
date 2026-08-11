# S3-C3 — Authoritative protection health

Task: `KC-S3-HEALTH-005` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Base: `d081417`

Closes the last three S1 REDs `ADR0039-HEALTH-01` through `03`, and with them
the whole database suite.

## Why this had to follow C2 immediately

Quiet is exactly what this app looks like when everything is fine. After C2, an
account whose coverage broke learns no bound, and a NULL threshold produces no
silence alert. Without this package that account would have been **silently
unprotected** — nothing on screen, nothing in the data, while the person and
their circle went on believing somebody was watching.

`healthy = quiet` · `known bad = visible` · `unknown ≠ safe`.

## What was built

`supabase/migrations/20260810010000_s3_protection_health.sql`, append-only:

* `public.protection_health_incidents` — one row per period during which
  guardianship of an account was known to be degraded. RLS on, no policy, no
  client grant. A partial unique index enforces **one open incident per user**,
  so a flapping collector cannot produce a pile of incidents.
* `public.my_protection_health()` — owner-scoped, returns `ready` / `limited` /
  `unknown` plus `since`, `cause`, `prompted_at`, `acknowledged_at`,
  `recovery_required` and `last_valid_coverage_at`.
* `public.acknowledge_protection_health()` — the only thing a person can do to
  an incident, and all it does is stop the re-prompting.
* `private.evaluate_protection_health(uuid)` — opens an incident when coverage
  has gone stale and closes one only on genuinely fresh continuous valid
  coverage, recording what recovered it. Revoked from every client role.
* `private.mark_protection_health_prompted(uuid)` — records that the subject was
  told, once.

## The three rules, enforced rather than described

**Ready requires positive evidence.** No valid coverage inside the freshness
window (26 hours — one daily cycle plus room for a late finalizer) yields
`unknown`, never `ready`. The absence of bad news is not good news.

**Acknowledgement is not recovery.** Dismissing the prompt sets
`acknowledged_at` and nothing else. The state stays `limited`. Only fresh
continuous valid coverage closes the incident, and the schema refuses a recovery
that arrives without its evidence: `CHECK ((recovered_at IS NULL) = (recovery_evidence IS NULL))`.
A bare timestamp would let "it seems fine now" masquerade as proof.

**An outage never becomes a personal alert.** Nothing in the file writes an
alert row. Manufacturing a personal emergency out of a dead collector is the
false positive that costs a group its willingness to answer the next real one —
the same reasoning that drove S3-A.

## Evidence

`supabase/tests/protection_health_contract.sql`, new, **12/12**. Behavioural:
an account with no coverage reads `unknown`; fresh coverage makes it `ready`;
ageing that same coverage returns it to `unknown`; the evaluator opens an
incident and the state becomes `limited`; acknowledgement leaves it `limited`
with `recovered_at` still null; only new coverage recovers it, with evidence
attached; no alert row exists anywhere along the path; and `authenticated`
cannot execute the evaluator.

| Gate | Result |
|---|---|
| `protection_health_contract.sql` | 12/12 |
| `s1_coverage_learning_health_contract.sql` | **8/8** (was 1/8 before C2) |
| **Fresh safe replay** | **35 files / 829 tests — All tests successful, Result: PASS** |
| Replay postconditions | local active cron 0; production-URL cron 0; baseline SHA unchanged |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| `git diff --check` | PASS |

**The database suite failing set is now empty.** That was the acceptance line
this plan set for S3, and it is the first time it has been true since S0 opened
with 17 failing files.

## Where this leaves the release gate

The first of the two conditions recorded in C2 is now satisfied: an account
without coverage is visibly `limited` or `unknown` rather than quietly
unprotected. The second still stands — any production rollout must confirm
coverage collection is actually enabled and producing intervals for the
population, because otherwise the honest answer for everybody is `unknown`, and
`unknown` does not alert.

C5 still owes the client surface: until the health card exists, this truth is
correct in the database and invisible on screen.

## Boundary

One append-only migration, one new behavioural test, one report. No historical
migration, no product source, no cron, notification, native permission,
entitlement, secret, version or release artefact. No production, linked
Supabase, push, merge, deploy, release or store action. Online KC uninterrupted;
this branch is still not a release candidate.
