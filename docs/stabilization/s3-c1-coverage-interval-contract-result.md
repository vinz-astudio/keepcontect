# S3-C1 — The coverage-interval contract, verified rather than built

Task: `KC-S3-COVERAGE-003` · Owner: Claude · Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis` · Base: `5653685`

## The finding

The S3-C plan opened with "new table `public.alert_observation_coverage_intervals`".
Catalog inspection before writing any SQL showed **the table already exists**,
with exactly the three state axes the S1 contract names, RLS enabled, zero
policies, and table grants only to `postgres`. It is written by
`private.finalize_alert_shadow_coverage` and already read by the shadow learning
line (`qualified_behavior_sessions`, `rebuild_alert_gap_profiles`,
`resolve_alert_candidate`).

Building a second one would have split the answer to "were we watching?" across
two tables that could disagree. So C1 became verification, and the plan was
corrected instead.

**No migration was needed or added.**

## What the real schema says

State vocabularies differ from what the plan guessed, and the real ones are
better:

| Axis | Values |
|---|---|
| `activity_coverage_state` | `valid` / `outage` / `unknown` |
| `intervention_coverage_state` | `valid` / `incomplete` / `unknown` |
| `sleep_context_state` | `valid` / `incomplete` / `unknown` |

`outage` and `incomplete` are distinct failures — the collector stopped, versus
it ran but could not see everything — and each axis keeps its own explicit
`unknown`. Collector identity lives upstream on
`private.alert_shadow_coverage_leases`; intervals are the finalized per-user
summary.

## The consequence C2 has to respect

Interval production is gated on the adaptive shadow runtime being **enabled and
accepting leases**, which ADR-0038 leaves default-off. On an unactivated
environment there are therefore no intervals at all, and coverage-valid learning
will correctly produce *nothing* rather than a bound.

That is ADR-0039's stated outcome, not a gap to engineer around: no healthy
coverage means Unknown, and Unknown does not train. But it has a real
operational edge — **turning coverage collection on is a prerequisite for
learning ever resuming**, and until then protection health must say `unknown`
loudly rather than letting the quiet read as fine. Recorded here so C2 and C3 do
not discover it late.

## Evidence

`supabase/tests/observation_coverage_interval_contract.sql`, new, 14/14:

* the three axes exist and are separately answerable;
* each axis is constrained to a vocabulary that includes an explicit `unknown`;
* RLS is on, there are zero policies, and neither `authenticated` nor `anon`
  holds `SELECT` or `INSERT`;
* an interval cannot end before it starts, cannot carry an invented state, and
  cannot carry placeholder provenance;
* **a person with no recorded interval has no valid coverage** — absence reads as
  unknown, never as yes.

That last assertion is the one the whole package exists to protect.

| Gate | Result |
|---|---|
| `observation_coverage_interval_contract.sql` | 14/14 |
| Fresh safe replay | see commit message; failing set unchanged at the single S3-C contract |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| `git diff --check` | PASS |

## Boundary

One new test file, one plan correction, one report. No migration, no schema
change, no product source change. No production, linked Supabase, push, merge,
deploy, release, signing or store action. Online KC uninterrupted.

## Next

C2 rewrites `rebuild_account_normal_bounds` to consume these intervals under the
four gates. It is the risky package: it changes what the live threshold learns,
so each gate gets its own RED-first behavioural test before the function is
touched.
