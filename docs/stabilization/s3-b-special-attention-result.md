# S3-B — Special Attention: private, default-off, powerless

Task: `KC-S3-SPECIAL-002` · Owner: Claude · Date: 2026-08-09
Branch: `codex/kc-s2-db-diagnosis` (isolated worktree) · Base: `f643d22`

Implements the five S1 REDs `ADR0039-SPECIAL-01` through `ADR0039-SPECIAL-05`.

## What the product rule actually demands

An ordinary group member sees a name and a status, and nothing more. ADR-0039
lets them quietly watch out for one particular person — but only through a
preference that is private, off by default, and carries no authority.

The alternatives it exists to avoid are both worse. Widening everyone's
notifications teaches people to ignore them, which costs the group its
willingness to respond. Escalating the relationship hands someone authority
over another person's care surface that they never needed.

## What was built

`supabase/migrations/20260809230000_s3_special_attention.sql`, append-only:

* `public.special_attention_subscriptions` — composite key on
  `(subscriber_id, subject_id)`, a `subscriber_id <> subject_id` check, and no
  seeded rows. **Absence of a row means off.**
* RLS enabled with **no policy and no grant**. There is deliberately no Data API
  path at all; every read and write goes through an owner-scoped
  `SECURITY DEFINER` function.
* `public.set_special_attention(uuid, boolean)` — enabling requires a currently
  active group membership or an active guardianship; disabling never does, so
  withdrawal is always available. It touches no alert, emergency-info, check-in
  task or guardianship row.
* `public.my_special_attention()` — a caller can only ever read their own
  subscriptions, which is what keeps the subject from learning who subscribed.
* `public.special_attention_recipients(uuid)` — server-side eligibility
  resolution, revoked from every client role.

One design decision worth recording: **eligibility follows the relationship, but
the preference survives it.** When a membership stops being active the person
stops receiving notices immediately, and their stored choice is left alone. If
the relationship comes back, so does their choice. Deleting it silently would
quietly discard a decision the person made about someone they care about.

## A trap this caught

`REVOKE ... FROM PUBLIC` was not enough. Supabase grants `EXECUTE` on new public
functions to `anon` and `authenticated` by default, so recipient resolution
stayed callable by any signed-in user — meaning anyone could have enumerated who
was watching out for a given person. The behavioural test caught it. The
migration now revokes from those roles by name.

## Evidence

| Gate | Result |
|---|---|
| `s1_care_authority_contract.sql` | 11/11 (was 6/11) |
| `special_attention_privacy_and_authority.sql` (new, behavioural) | 13/13 |
| `specialAttention.test.ts` (new) | 5/5 |
| Fresh safe replay | 32 files / 793 tests; failing set now a single file |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| `npm test` | 344 passed / 15 failed / 359 — the same inherited archive-path debt |
| `git diff --check` | PASS |

The replay failing set is now exactly
`s1_coverage_learning_health_contract.sql`, the last S3 package.

## Deliberate scope boundary

The RPC wrappers and the UI toggle are **not** in this package. They require
`src/lib/database.types.ts` to be regenerated for the new functions, which is
outside this package's declared write set. Rather than paper over that with a
type cast, they move to S3-C, which owns protection health and therefore the
same surface where the `Limited` state and this notice are shown.

So the rule and the data contract are now unbypassable; the interface is not yet
wired. The i18n copy for both is already in place, including the English-only
Concern refusal message left over from S3-A.

## Boundary

No historical migration rewrite. No production, linked Supabase, push, merge,
deploy, release, signing or store action. Online KC uninterrupted; this branch
is still not a release candidate.
