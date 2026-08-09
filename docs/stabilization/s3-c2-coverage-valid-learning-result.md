# S3-C2 — Coverage-valid learning

Task: `KC-S3-LEARN-004` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Base: `98e6052`

Closes the four learning REDs `ADR0039-LEARN-01` through `04`.

## The defect

`private.rebuild_account_normal_bounds` learned from every gap between pings. A
stretch where the phone was asleep, the permission was revoked, the network was
down, the collector had stopped, or the signal came from somebody else's hand
all counted as "normal quiet" — and each one widens the very threshold meant to
notice when this person goes missing.

Run long enough, that is a person being trained into never being missed.

## The four gates

**1. Coverage.** A gap counts only if it lies *entirely* inside an observation
interval whose `activity_coverage_state`, `intervention_coverage_state` and
`sleep_context_state` are all `valid`. Containment, not overlap: half a gap
inside coverage says nothing about the other half, and the other half is exactly
where someone could have been missed.

**2. Source.** `kind = 'manual_checkin'` and `source in ('shortcut','manual')`
are excluded, as is replayed history (the existing `received_at` skew guard,
now named for what it does). These prove somebody acted, or that history was
re-imported — never that this person was observably living an ordinary day.
Guardian action is excluded by the same rule and by the standing contract that
Guardian confirmation is never written as the ward's behaviour.

**3. Repeat.** A candidate is *exceptional* when it towers over the rest of this
account's own silences — measured against the median of the **other** gaps, so
an outlier cannot certify itself as typical. An exceptional candidate is only
adopted when at least two independent comparable dates (≥80% of its length,
counted by distinct calendar date **in the subject's own timezone**) support it.
Failing that, selection walks toward *smaller* candidates. A missing second date
can therefore only narrow a threshold, never widen one.

With no other gap to compare against there is no distribution and nothing can be
called exceptional: a lone observed silence is simply the only thing we have
seen, and is used as-is.

**4. Outcome.** Nothing qualifying yields `has_usable_signal = false` and a NULL
bound — a recorded absence, never a template and never a zero.

## Evidence

`supabase/tests/coverage_valid_learning.sql`, new, **10/10**. It is behavioural,
not textual — eight subjects differing only in whether we could see the silence,
who produced it, and how often it happened:

| Subject | Situation | Learned |
|---|---|---|
| 1 | silence with no coverage at all | nothing |
| 2 | same silence, fully covered | 200 min |
| 3 | coverage stops midway | nothing |
| 4 | covered, but app could not reach them | nothing |
| 5 | manual check-in | nothing |
| 6 | Shortcut | nothing |
| 7 | replayed history | nothing |
| 8 | no data at all | recorded absence |

Then subject 2 gets one 600-minute silence on a single date — the bound stays at
200. A second independent date carrying a comparable silence, and only then does
600 become part of their normal.

`s1_coverage_learning_health_contract.sql` moves 1/8 → 5/8; the remaining three
are the protection-health assertions owned by C3.

| Gate | Result |
|---|---|
| `coverage_valid_learning.sql` | 10/10 |
| S1 learning assertions 2–5 | pass |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| `git diff --check` | PASS |
| Fresh safe replay | 34 files / 817 tests; see the known regression below |

## Known regression, owned by the immediate follow-up

`per_subject_failure_isolation.sql` test 5 now fails. Its fixture builds raw
pings and no coverage intervals, then asserts "an account with evidence still
gets its own number". Under ADR-0039 raw pings are no longer evidence, so that
account correctly learns nothing.

The test's purpose is per-subject failure isolation, not learning admissibility,
so the fixture needs coverage added rather than the gate relaxed. That file was
outside this package's declared write set, so it is migrated in the immediate
successor package rather than edited here.

## The operational consequence that must reach the release gate

`private.silence_threshold` returns NULL when there is no usable bound, and
`process_escalations` compares elapsed silence with `> private.silence_threshold(...)`.
A NULL threshold therefore yields no silence alert for that account.

That behaviour already existed. What changes here is **how many accounts land in
it**: after this package, only accounts with genuine coverage intervals learn a
bound at all, and coverage intervals are produced by the adaptive shadow line,
which ADR-0038 leaves default-off.

So: **deploying this to an environment where coverage collection is not enabled
would leave silence alerting inert for every account in it.** That is the
accepted semantic — no healthy coverage means Unknown, and Unknown neither
trains nor proves danger — but it is not something to discover after a release.
Two conditions follow, and neither is optional:

1. C3 must land first, so an account with no coverage is visibly `Limited` or
   `unknown` rather than quietly unprotected.
2. Any production rollout must confirm coverage collection is actually enabled
   and producing intervals for the population, before or together with this
   change.

Recorded here, in the Dev Log and in Known Issues so the release gate cannot
miss it.

## Boundary

One append-only migration, one new behavioural test, one report. No historical
migration, no product source, no cron, notification, native permission,
entitlement, secret, version or release artefact. No production, linked
Supabase, push, merge, deploy, release or store action. Online KC uninterrupted;
this branch is still not a release candidate.
