# S3-C — Coverage-valid learning and authoritative protection health

Author: Claude · Date: 2026-08-09 · Status: C1 executed; C2–C6 pending
Branch: `codex/kc-s2-db-diagnosis` · Base: `7d6b6d4`

Binding decisions: ADR-0035, ADR-0037, ADR-0038, ADR-0039

> **Correction, 2026-08-09 22:30 (C1).** This plan assumed the coverage-interval
> schema had to be built. It already exists. See §3.1 and §4 for what changed.

Closes the last seven S1 REDs, all in
`supabase/tests/s1_coverage_learning_health_contract.sql`, plus the two items
S3-B deliberately handed over.

---

## 1. What this package is really for

Two ideas, and they are the same idea seen from two sides.

**Learning.** The silence threshold is supposed to be *this person's own normal*.
That only means something if the evidence behind it was actually observable. If
the phone was asleep, the permission was revoked, the network was down, or the
signal came from someone else's hand, then a long quiet stretch proves nothing —
and folding it into "normal" silently widens the very threshold that is supposed
to protect them. A person can be trained into never being missed.

**Health.** The other side: when coverage breaks, the app must say so. Staying
quiet while blind is the most expensive failure in the product, because quiet is
exactly what the app looks like when everything is fine. `healthy = quiet`,
`known failure = visible`, `unknown ≠ safe`.

Both reduce to one rule: **the system must know whether it was watching, and it
must never spend evidence it did not have.**

---

## 2. Current state

| Fact | Evidence |
|---|---|
| ~~No coverage-interval concept exists~~ | **Wrong.** `public.alert_observation_coverage_intervals` already exists with all three state axes, RLS on, zero policies, no client grants, written by `private.finalize_alert_shadow_coverage` |
| `rebuild_account_normal_bounds` learns from raw gaps | its source mentions none of coverage, exclusions or repeat-evidence |
| No protection-health surface exists | `public.my_protection_health` is absent |
| Replay failing set | exactly `s1_coverage_learning_health_contract.sql`, 7 of 8 assertions |
| Special Attention notice | subscription exists (S3-B); emission not built |
| `database.types.ts` | stale for `set_special_attention`, `my_special_attention` |

---

## 3. Design

### 3.1 Coverage intervals

**This table already exists** and was verified in C1 rather than built. One row
per continuous stretch during which the shadow line recorded observation for a
person, with the three state axes the contract names. The real columns are:

| Column | Meaning |
|---|---|
| `user_id` | subject |
| `version_id` | the shadow model version the interval was produced under |
| `starts_at`, `ends_at` | bounded; `ends_at > starts_at` enforced |
| `timezone`, `utc_offset_minutes` | the subject's own clock context |
| `activity_coverage_state` | `valid` / `outage` / `unknown` — was activity actually observable |
| `intervention_coverage_state` | `valid` / `incomplete` / `unknown` — could the app have reached the person |
| `sleep_context_state` | `valid` / `incomplete` / `unknown` — was sleep context trustworthy |
| `captured_at`, `finalized_at` | when the claim was made and sealed |
| `evidence_version`, `provenance_sha256` | provenance; the hash shape is constraint-enforced |

Collector identity lives upstream, on `private.alert_shadow_coverage_leases`
(`client_id`, `channel`, `collector_contract`, `collector_state`,
`capability_sha256`). Intervals are the finalized, per-user summary of those
leases.

Three axes rather than one boolean, because they fail independently and mean
different things. A phone can be collecting activity fine while notifications are
blocked: activity is `valid`, intervention is not. Collapsing them would let one
kind of blindness hide behind another kind of sight.

**Never inferred.** An interval is written by a collector reporting for itself.
Absence of an interval is `unknown`, not `valid` — the default is "we do not
know", which is the whole point.

Grants: RLS on, **zero policies, no grant to any client role** — there is no
Data API path at all. Clients report coverage through the existing lease surface;
`private.finalize_alert_shadow_coverage` writes the intervals.

**Consequence C2 must respect.** Interval production is gated on the adaptive
shadow runtime being enabled and accepting leases, which is default-off per
ADR-0038. So on a fresh or unactivated environment there are no intervals, and
coverage-valid learning correctly produces *nothing* rather than a bound. That is
ADR-0039's stated outcome — "无健康覆盖时结果为 Unknown/证据不足，不训练" — not a
gap to engineer around. It does mean **turning on coverage collection is a
prerequisite for learning ever resuming**, and protection health must say
`unknown` loudly in the meantime.

### 3.2 Learning gates — rewriting `rebuild_account_normal_bounds`

Four gates, in order. Each is a separate, named reason for exclusion so a skipped
sample can always be explained.

1. **Coverage gate.** A candidate gap counts only if it is fully contained in
   intervals whose `activity_coverage_state`, `intervention_coverage_state` and
   `sleep_context_state` are all `'valid'`, from a single continuous trusted
   source. Partial overlap does not partially count; it is excluded.
2. **Source-exclusion gate.** Evidence originating from `manual_checkin`,
   `guardian`, `shortcut` or `replay` is excluded from training. These prove
   somebody else acted, or that history was re-imported — never that this person
   was observably living their normal day.
3. **Repeat-evidence gate.** An *exceptional long* gap may only raise the upper
   bound when at least **two independent comparable dates** carry a similar
   coverage-valid gap: `count(distinct observation_date) >= 2`. A single extreme
   never rewrites normal. Independence is by calendar date in the subject's own
   timezone, so one long night cannot be split into two samples.
4. **Outcome gate.** With no qualifying evidence the row is written with
   `has_usable_signal = false` and a NULL bound — the honest state the schema
   already enforces — never a template and never a zero.

Learning is also suspended for any period overlapping a health incident
(§3.3): a blind stretch cannot teach.

### 3.3 Protection health

New table `public.protection_health_incidents`: `user_id`, `opened_at`,
`closed_at`, `cause` (`coverage_gap` / `permission_lost` / `collector_stopped` /
`unknown`), `prompted_at` (when the subject was told, once), `acknowledged_at`,
`recovered_at`, `recovery_evidence`.

New RPC `public.my_protection_health()` returning, for the caller:

* `state`: `'ready'` / `'limited'` / `'unknown'`
* `since`, `cause`, `prompted_at`, `acknowledged_at`
* `recovery_required`: what new evidence would clear it
* `last_valid_coverage_at`

Three rules the contract encodes and the product depends on:

* **`ready` requires positive evidence.** No recent valid interval means
  `unknown`, never `ready`. Silence is not health.
* **Acknowledgement is not recovery.** Dismissing the prompt sets
  `acknowledged_at` and stops re-prompting; it does **not** set `recovered_at`
  and does **not** return the state to `ready`. Only a fresh stretch of
  continuous valid coverage does, recorded in `recovery_evidence`.
* **An outage never becomes a personal alert.** `my_protection_health` performs
  no `insert into public.alerts`, and neither does the incident writer. A
  technical failure is a technical failure; manufacturing a personal alert from
  one is exactly the false-positive that costs the group its willingness to
  respond.

### 3.4 Special Attention notice (handed over from S3-B)

Emission order is fixed by ADR-0039 and must be enforced server-side:

1. incident opens →
2. the **subject** is prompted once (`prompted_at`) →
3. an **extra health grace** elapses with no recovery →
4. **then** `special_attention_recipients(subject)` each receive **one** notice,
   worded as coverage interruption, explicitly not danger (`special.notice`).

Idempotent per incident: one notice per subscriber per incident, enforced by a
uniqueness key, so a flapping collector cannot spam anybody.

### 3.5 Client surface

* Regenerate `src/lib/database.types.ts` for all new functions.
* `specialAttention.ts` regains its RPC wrappers; add the per-person toggle.
* Protection-health card: `Limited` shown persistently with cause and what would
  clear it; one-time prompt; dismissal changes the prompt, not the state.
* `unknown` renders as *unknown* — never styled as healthy.

---

## 4. Packages

Executed in order; each ends green and committed before the next starts.

| # | Scope | Done when |
|---|---|---|
| **C1** ✅ | Verify and lock the existing coverage-interval contract; correct this plan | `observation_coverage_interval_contract.sql` 14/14; no client path; absence reads as `unknown`; **no migration needed** |
| **C2** | Rewrite `rebuild_account_normal_bounds` with the four gates | `ADR0039-LEARN-01..04` green; behavioural test proves each exclusion reason separately |
| **C3** | Incident table + `my_protection_health()` | `ADR0039-HEALTH-01..03` green; acknowledgement-vs-recovery proven behaviourally |
| **C4** | Special Attention notice emission | ordering and one-notice-per-incident proven; no alert created |
| **C5** | Types regen + client surface + i18n wiring | typecheck/build/Vitest green; `Limited` and `unknown` visibly distinct |
| **C6** | Full replay, all gates, exact diff review, independent read-only audit | replay failing set **empty**; agy verdict recorded |

C2 is the risky one: it changes what the live threshold learns. It gets its own
RED-first behavioural test per gate before the function is touched.

---

## 5. Verification

Per package: single-file pgTAP RED → implement → GREEN, then the full safe
replay. Final: `npm run typecheck`, `npm test`, `npm run build`,
`git diff --check`, exact write-set review, agy independent read-only audit.

Replay postconditions unchanged: local active cron 0, production-URL cron 0,
source baseline SHA unchanged.

**Acceptance for S3 as a whole:** the replay failing set is *empty*. S3 is the
package that removes the last deliberate RED, so "one file left" is no longer an
acceptable landing state.

The 15 inherited Vitest failures stay out of scope; they belong to the
`migrations-archive` normalisation decision, which is still open.

---

## 6. Risks

| Risk | Handling |
|---|---|
| Tightening learning strands users on `unknown` with no bound at all | Correct and intended — `unknown` is honest. Surface it in health rather than papering over it with a template. Watch how many real accounts land there before any production rollout. |
| Three-axis coverage is over-modelled | Each axis has a distinct failure mode and a distinct user-visible consequence; collapsing them hides one blindness behind another. Keep three. |
| Incident flapping produces prompt spam | One prompt per incident, extra grace before any subscriber notice, uniqueness key per (incident, subscriber). |
| Rewriting the learning worker changes production thresholds | Local only. No production apply is authorised by this plan; rollout needs its own human-authorised release gate. |
| Regenerating `database.types.ts` sweeps in unrelated drift | Review the generated diff explicitly; if it carries changes unrelated to S3, stop and report rather than absorbing them silently. |

---

## 7. Explicitly out of scope

Production apply, remote Supabase, push, merge, deploy, release, signing,
TestFlight, Store submission, and the S4 platform evidence. This plan authorises
local implementation and local verification only.
