# S4-1 — iOS store honesty

Task: `KC-S4-IOS-HONESTY-009` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Base: `1d8adcf`

Closes the last two S1 REDs, `ADR0039-IOS-01` and `ADR0039-IOS-03`. **All
sixteen S1 REDs are now implemented.**

## What was actually wrong

The permission strings said the capability exists

> "…to restart its guardian if the app gets closed, **so your circle can still
> tell you are fine**."

That is a coverage promise, made by a mechanism that cannot keep it.
Significant-change relaunch after a force-quit is best-effort and frequently
does not happen; the plist's own comment already admitted no coordinate is ever
read. And nothing anywhere said that a silent push may simply never arrive.

A person reading that string concludes somebody is watching. That belief is
exactly the thing the whole stabilisation exists to stop the app from creating.

## What changed — claims, not capability

* Both `NSLocation*UsageDescription` strings now say what the mechanism does:
  it *may* relaunch the app, it is best-effort and often does not happen, it is
  **not a guarantee that anyone is watching**, and no coordinate is read, stored
  or sent.
* The `UIBackgroundModes` comment records that a silent push is best-effort —
  iOS may delay, coalesce or drop it — so it cannot on its own prove coverage,
  and that background location is never treated as evidence the person is fine.
* `AppDelegate.swift` carries the same truth where the handler lives: absence of
  a silent push is `unknown`, not `fine`, and the server treats it that way.

**No capability, entitlement, background mode or behaviour was changed.** This
package changed what the app claims, not what it does.

## The decision I did not make for you

The honest reading of ADR-0039 arguably points further: drop the `location`
background mode altogether, since no coordinate is ever used and a
relaunch-only declaration is the kind of thing App Review pushes back on.

I did not do that, because removing it removes a real (if unreliable) recovery
path after force-quit, and that is a Store-and-product tradeoff, not a wording
fix. It is recorded in the plist comment and here so it is decided deliberately
before submission rather than discovered during review.

## Evidence

| Gate | Result |
|---|---|
| `scripts/s1-platform-contract.test.mjs` | **12/12** (was 10/12) |
| `npm test` | 358 passed / 13 failed / 371 — inherited debt drops from 15 to 13 |
| `npm run typecheck` / `npm run build` / `git diff --check` | PASS |

**Not verified, and cannot be here:** this is an Xcode project on a Windows
machine. Nothing was compiled, signed, run on a device, or submitted. The change
is text in two files; its effect on App Review can only be established by an
actual submission.

## Boundary

Two iOS files and one report. No production, signing, TestFlight, Store or
online action of any kind.
