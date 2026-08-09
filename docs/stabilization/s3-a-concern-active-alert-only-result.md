# S3-A — Concern is active-alert-only

Task: `KC-S3-CONCERN-001` · Owner: Claude · Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis` (isolated worktree) · Base: `4e332cd`

Implements the two S1 REDs `ADR0039-CONCERN-01` and `ADR0039-CONCERN-02`.

## The defect

`public.send_concern` and `public.gm_send_concern` both took an
`insert into public.alerts ... cause='concern'` branch whenever the target had
no open alert. Any authorised group member, and any admin, could therefore
manufacture an alert on another person.

An alert is the only way the app says *this person is actually unaccounted for*.
Once concern can mint one, alerts stop correlating with real silence, and the
people who receive them learn to discount them. The cost lands later, on the
person whose genuine alert nobody answers.

The GM console compounded it: `src/features/gm/GMScreen.tsx` rendered the
Concern button with no active-alert condition at all, unlike
`watchPresentation.ts` and `StatusBoard.tsx`, which already gated on one.

## The repair

Append-only migration
`supabase/migrations/20260809220000_s3_concern_requires_active_alert.sql`
replaces both functions. With no open alert they now raise
`active alert required` (SQLSTATE `P0001`). With an open alert the previous
behaviour is unchanged: set `requires_explicit_unlock`, record a
`concern_on_open_alert` event against the existing alert, and notify the
subject.

Eligibility is enforced on the server. The UI gate added to the GM console is a
courtesy so an admin is not invited to attempt something that will be refused —
an old client, a replayed request or a direct RPC call are all refused
identically.

`src/features/gm/gmConcernEligibility.ts` holds the pure gate and the error
mapping; `GMScreen.tsx` consumes both. Authorisation, RLS and ACL are untouched.

## Evidence

| Gate | Result |
|---|---|
| `s1_alert_activity_concern_contract.sql` | 11/11 (was 7/11) |
| `concern_requires_active_alert.sql` (new, behavioural) | 12/12 |
| `gmConcernEligibility.test.ts` (new) | 6/6 |
| Fresh safe replay | 31 files / 780 tests; failing set now only the two remaining S1 contracts |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| `npm test` | 339 passed / 15 failed / 354 — the same inherited archive-path debt |

The behavioural test does not only assert that an error is raised. It pins the
ADR-0039 invariants: a refused Concern leaves **no** alert row and **no**
notification; an accepted Concern creates no second alert, does not resolve the
alert, and produces no `behavior_pings` evidence for the subject.

The replay failure set dropped from three S1 files to two.
`s1_alert_activity_concern_contract.sql` is now green and stays green.

## Known follow-up

The server's refusal message is shown in English only. Adding an i18n key
requires editing `src/lib/i18n.tsx`, which is outside this package's declared
write set, so it was not done here. The button gate makes this path reachable
only from a stale row. Tracked for the next S3 package that legitimately touches
i18n.

## Boundary

Changed: one append-only migration, one new pgTAP test, one new frontend module
with its test, and one edited screen. No historical migration, no alert
lifecycle beyond the Concern entry point, no cron, notification transport,
native permission, entitlement, secret, version or release artefact.

No push, merge, deploy, release, signing or store action. No production or
linked Supabase mutation. Online KC uninterrupted; this branch is still not a
release candidate.
