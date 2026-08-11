# S3-C5 — The client surface

Task: `KC-S3-SURFACE-007` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Base: `740b556`

A truth that is correct in the database and invisible on screen protects nobody.
C2 and C3 made the server honest about whether anyone is watching; this package
puts that answer where a person can see it.

## What landed

* `src/lib/database.types.ts` — hand-added entries for `my_protection_health`,
  `acknowledge_protection_health`, `my_special_attention` and
  `set_special_attention`. **Not regenerated**: `supabase gen types` wanted to
  pull a `postgres-meta` image and, more importantly, a full regeneration risks
  sweeping in drift unrelated to S3, which the plan told me to refuse. Four
  precise additions are reviewable in a way a regenerated file is not.
* `src/features/baseline/protectionHealth.ts` — fetch, acknowledge, and the
  presentation rules. The load path deliberately maps a **failed read to
  `unknown`**: a fetch that failed tells us nothing about whether anyone is
  watching, so it must not be allowed to look reassuring.
* `src/features/baseline/ProtectionHealthCard.tsx` — renders **nothing** while
  protection is proven ready. That silence is the reward for everything working.
  The moment it is not proven, the card stays on screen with the state, what it
  means, and what would clear it. `role="status"` and `aria-live="polite"` so it
  is announced rather than merely drawn.
* `HomeScreen` mounts it above the notifications stack.
* `specialAttention.ts` regains its RPC wrappers, now that the types exist.
* `notificationCopy.ts` learns the `coverage_interrupted` kind and gains
  `notificationClaimsDanger()`, which honours the server's machine-readable
  `means_danger = false`.
* `i18n.tsx` — copy for all three states in both languages, plus the notice.

## The rule the copy enforces

`unknown` gets its own words: *there is not enough evidence that anyone is
watching; unknown is neither safe nor unsafe.* It is never dressed as ready, and
the state has a distinct class (`health--unknown`) rather than sharing a
"nothing to see" style with health.

Dismissing changes the prompt, never the state: the button only appears while
`limited` and unacknowledged, and after acknowledgement the card stays.

## Evidence

| Gate | Result |
|---|---|
| `protectionHealth.test.ts` (new) | 8/8 — including that null, undefined and an unrecognised state all read as `unknown` |
| `npm run typecheck` | PASS |
| `npm test` | 352 passed / 15 failed / 367 — the same inherited archive-path debt |
| `npm run build` | PASS |
| Fresh safe replay | 36 files / 839 tests, PASS |
| `git diff --check` | PASS |

## Honestly owed

**No live browser verification.** The card only renders for a signed-in session,
and this app's dev session points at **production** Supabase, not the local
stack these changes were built against. Exercising it would have meant touching
production, which is outside every boundary this work has held to. The
presentation rules are covered by unit tests; the rendered card has not been
seen in a browser.

**No stylesheet.** The card uses semantic markup and state classes but ships no
CSS, because adding one was outside this package's declared write set. It is
visible and readable, not styled.

**`notificationClaimsDanger` has no unit test yet.** I wrote one, then noticed
`notificationCopy.test.ts` was not in the declared write set, and reverted it
rather than writing outside the set. It needs a one-file successor package.

## Boundary

Six files changed, three added, one report. No migration, no production, linked
Supabase, push, merge, deploy, release or store action. Online KC uninterrupted.
