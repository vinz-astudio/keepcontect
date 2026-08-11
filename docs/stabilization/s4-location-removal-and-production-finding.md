# S4-2 — Background location removed, and what production actually shows

Task: `KC-S4-IOS-LOCATION-010` · Owner: Claude · Date: 2026-08-10
Branch: `codex/kc-s2-db-diagnosis` · Base: `fda3265`

## 1. The background-location mode is gone

Human decision, 2026-08-10. `UIBackgroundModes` now contains only
`remote-notification`. `NSLocationAlwaysAndWhenInUseUsageDescription` is
removed.

`NSLocationWhenInUseUsageDescription` **stays**, because SOS genuinely uses
`navigator.geolocation` to attach a location to an emergency, and its wording now
describes that real purpose instead of a relaunch hack.

Declaring a location background mode the app never used for location made the
app look more protective than it was and is exactly the claim App Review pushes
back on. `s1-platform-contract` stays 12/12 with it gone.

## 2. Production was checked, and it is not healthy

Read-only inspection of the live project (`byekgmqyqlftgoveqnku`). No production
state was modified.

```
adaptive_alert_shadow_runtime_config:
  enabled                 = false
  accept_coverage_leases  = true
  last_failure_code       = 'shadow_live_hash_mismatch'
  updated_at              = 2026-08-04 14:00:00 UTC

last coverage interval ends_at   = 2026-08-04 13:42 UTC
last coverage lease received_at  = 2026-08-04 13:58 UTC
fresh intervals (26h)            = 0
fresh leases (26h)               = 0
users with fresh valid coverage  = 0
accounts with a usable bound     = 10 (latest rebuild 2026-08-09)
shadow cron jobs                 = all active=true
```

### What this means

**Production coverage collection has been dead since 2026-08-04 14:00 UTC.**

The cron jobs still run. The runtime disabled *itself*: the ADR-0037 rewrite of
`private.silence_threshold` on 2026-08-04 broke the live-definition pin, the
cycle raised `shadow_live_hash_mismatch`, and the fail-closed guard shut the
subsystem down. `last_failure_code` still says so, five days later.

That is the same defect S2.3 found and repaired locally. It is no longer an
inference from local tests — **it is the measured state of the live system**, and
the S2.3 pin re-authorization is the fix that would restart collection.

### What it means for the release

The ten accounts that currently hold a usable bound learned it **before**
2026-08-04, under the pre-C2 rules. Coverage evidence has not existed since.

So if C2 ships without restarting collection first, the next nightly rebuild
finds no coverage-valid evidence for anybody, every bound becomes NULL, and
`process_escalations` stops producing silence alerts **for the entire user
base**. The health card would honestly say `unknown` for everyone — which is
correct, and also means nobody is being alerted on.

**Order of operations for release, not optional:**

1. Deploy the S2.3 pin re-authorization migration to production.
2. Re-enable the shadow runtime and confirm intervals and leases start flowing
   again for real accounts.
3. Only then deploy C2's learning change.

Steps 1 and 2 are production actions and need explicit human authorization; this
package did not take them.

## 3. A new, real test-infrastructure defect

`scripts/s2-safe-db-replay.test.mjs` passes in isolation but fails
intermittently in the full run: two identical full-suite runs on the same tree
produced 14 and then 13 failures. It manipulates
`supabase/.temp/s2-safe-replay`, which the replay tooling also uses, so the
suite appears to race with itself over a shared temp directory.

This is **not** caused by the plist change — the failing assertion counts
migration files. It is recorded rather than dismissed, because "probably flaky"
is precisely how the coverage outage above stayed invisible for five days.

## Evidence

| Gate | Result |
|---|---|
| `s1-platform-contract` | 12/12 with the background mode removed |
| `npm run typecheck` / `npm run build` / `git diff --check` | PASS |
| `npm test` | 357–358 passed; 13 inherited failures plus the intermittent replay-harness one |

## Boundary

One iOS file and one report. Production was **read only**. No push, merge,
deploy, release, signing or submission.
