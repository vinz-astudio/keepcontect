# S3-C4 — The Special Attention coverage-interruption notice

Task: `KC-S3-NOTICE-006` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Base: `e5c57b9`

Connects the two halves built in S3-B and S3-C3: a private subscription, and a
protection-health incident.

## The ordering is the product

Somebody quietly agreed to look out for one particular person. When that
person's protection breaks, they are the only ones positioned to check. But
telling them badly is worse than not telling them at all, so ADR-0039 fixes the
order and this package enforces it server-side:

1. **The subject hears first.** Nobody learns that someone's phone stopped
   reporting before that person has been told themselves.
2. **A health grace passes** after that prompt. A collector that blinks for two
   minutes is not news; sending it anyway teaches people to ignore the next one,
   which is the only one that would have mattered.
3. **Exactly one notice per subscriber per incident**, enforced by the primary
   key of `public.special_attention_notices` rather than a hopeful `WHERE`. A
   flapping collector cannot spam anybody.
4. **The words say what happened**: coverage was interrupted, and that is not
   the same as the person being in danger.

## What was built

`supabase/migrations/20260810020000_s3_special_attention_notice.sql`:

* `public.special_attention_notices (incident_id, subscriber_id, notified_at)` —
  RLS on, no policy, no client grant. The primary key *is* the anti-spam
  guarantee.
* `private.dispatch_special_attention_notices(interval)` — revoked from every
  client role. Selects open, unrecovered, already-prompted incidents past the
  grace, joins `special_attention_recipients` so **eligibility is evaluated at
  send time**, and inserts one dedupe row plus one notification per subscriber.
  A concurrent cycle losing the race is swallowed as `unique_violation`.

The notification carries `kind = 'coverage_interrupted'`, a body naming the
interruption and denying danger, and `params.means_danger = false` so the denial
is machine-readable and no client can render it as an emergency.

## Evidence

`supabase/tests/special_attention_notice_contract.sql`, new, **10/10**: nothing
before the subject is prompted; nothing during the grace; both watchers notified
once the grace passes; a second dispatch sends nothing; exactly one notice row;
the wording and the machine-readable denial; no alert created; a watcher whose
membership lapsed is silently dropped at send time; and `authenticated` cannot
call the dispatcher.

| Gate | Result |
|---|---|
| `special_attention_notice_contract.sql` | 10/10 |
| Fresh safe replay | **36 files / 839 tests — All tests successful, PASS** |
| `npm run typecheck` / `npm run build` / `git diff --check` | PASS |

One fixture correction worth recording: the first draft opened a second incident
for the same person while the first was still open, and C3's
`protection_health_one_open_per_user` index refused it. The guard was right and
the fixture was wrong — the test now recovers the first incident before the
second break, which is what actually happens.

## Owed to C5

`coverage_interrupted` is a new notification kind. The client must render it,
and must honour `means_danger = false`. Until then the notice is correct in the
database and unstyled on screen.

## Boundary

One append-only migration, one new behavioural test, one report. No historical
migration, no product source. No production, linked Supabase, push, merge,
deploy, release or store action. Online KC uninterrupted.
