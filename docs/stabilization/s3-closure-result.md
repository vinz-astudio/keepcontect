# S3 — Closure

Task: `KC-S3-CLOSE-008` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Range: `4e332cd..2cdd885`

## What S3 was for

S1 froze what "correct" means and found sixteen places where the product did not
meet it. S3 built those sixteen. Every one of them reduces to the same thing:
**an alert must keep meaning that somebody is actually unaccounted for**, and
**the app must never look calm while it is blind**.

| Package | What it closed |
|---|---|
| A | Concern can no longer manufacture an alert — server-side, not by hiding a button |
| B | Special Attention: private, default-off, powerless; eligibility follows the relationship while the preference survives it |
| C1 | The coverage-interval contract locked; absence reads as unknown, never yes |
| C2 | Learning admits only coverage-valid, self-originated, repeat-supported evidence |
| C2b | The isolation fixture migrated to that meaning of evidence rather than the gate relaxed |
| C3 | Protection health: ready needs evidence, acknowledgement is not recovery, an outage is never a personal alert |
| C4 | The coverage notice: subject first, then a grace, then once per subscriber per incident, never claiming danger |
| C5 | The client surface, so the answer is visible rather than merely correct |

Fourteen of the sixteen S1 REDs are closed. The remaining two are iOS
store-honesty items routed to S4.

## Final gates

| Gate | Result |
|---|---|
| Fresh safe replay | **36 files / 839 tests — All tests successful, PASS** |
| Replay postconditions | local active cron 0; production-URL cron 0; baseline SHA unchanged |
| `npm run typecheck` | PASS |
| `npm test` | 356 passed / 15 failed / 371 — the unchanged inherited archive-path debt |
| `npm run build` | PASS |
| `git diff --check` | PASS |

## Scope integrity

The whole range: 9 commits, 32 files, **3413 insertions / 6 deletions**.

* **Modified historical migrations: 0.** All five migrations are additions.
* **Files touched under `android/`, `ios/`, `src-tauri/`, `public/`,
  `supabase/functions/`, `package.json`, `version.ts`: 0.**

Those six deleted lines are the alert-creating branch inside `send_concern` and
`gm_send_concern`. S3 is almost entirely new constraint rather than rewritten
behaviour.

## Independent audit

`KC-S3-CLOSE-008-AGY-A01`, independent-auditor, read-only, no shell, no network,
no subdelegation. Verdict **`zero-finding`**, findings `[]`, 0 write attempts.

It confirmed specifically that walking the ranked candidates after a failed
repeat-evidence check can only move to *smaller* durations — the property that
matters most, because the opposite would have silently widened people's
thresholds — and that no path creates a personal alert from a technical outage.

## What S3 did not do

**Nothing online.** No push, merge, deploy, release, signing, TestFlight or
Store action; no production or linked-Supabase mutation. Root `main` is still
`43636b1`. This branch is **not** a release candidate.

**No live product verification.** The client surface has unit-tested rules and
has never been seen rendered. The dev session points at production Supabase, and
this work has touched nothing online, so verifying it would have meant breaking
that boundary. Somebody has to look at it on a real device before release.

**No stylesheet** for the protection health card. It is semantic and readable,
not styled.

**The inherited Vitest debt is untouched** — 15 failures against
`supabase/migrations-archive/**`, still awaiting the archive
normalisation-or-exemption decision alongside the S0 whitespace diagnostic.

## The release gate condition that outlives S3

`private.silence_threshold` returns NULL without a usable bound, and a NULL
threshold produces no silence alert. After C2, only accounts with genuine
coverage intervals learn a bound, and intervals come from the adaptive shadow
line that ADR-0038 leaves default-off.

C3 satisfied the first half of the mitigation: such an account is now visibly
`limited` or `unknown` instead of quietly unprotected. **The second half still
stands and belongs to whoever runs the release**: confirm coverage collection is
actually enabled and producing intervals for the real population, or accept that
the honest answer for everyone is `unknown` — and `unknown` does not alert.

## Next

S4: the two iOS store-honesty REDs, then the AAB, iOS Native and Tauri review,
signing and real-device evidence. Much of that can only be obtained by the human
with their own accounts and devices.
