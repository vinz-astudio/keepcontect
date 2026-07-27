# Keep Contact Adaptive Alert Production Shadow Design

## Metadata

| Field | Value |
|---|---|
| ID | SPEC-KC-ADAPTIVE-SHADOW-PROD-001 |
| Status | accepted under ADR-0028; local implementation planning/build/audit preparation authorized; production and publication remain separately gated |
| Date | 2026-07-27 |
| Change class | High-risk / M3 for implementation and release |
| Requirement | Collect production-quality adaptive candidate evidence without changing live alert behavior |
| Existing authority | ADR-0022 remains the only live alert authority; ADR-0023 authorizes replay/unscheduled shadow infrastructure only |
| Candidate source | `codex/adaptive-alert-shadow@e8b5d9270b968dd1edbf12c102c00ce47d35515f` |
| Current main | `cad6a664c085fcc8f1aeaf2d6b7198c3b9f63fa8` |
| Runtime task | `KC-ADAPTIVE-SHADOW-PROD-SPEC-001` |

## Executive Decision

Build a production shadow system that evaluates adaptive alert candidates every
5 minutes but has no authority to create, update, delay, pause, resolve, escalate,
or notify a live alert.

The implementation is a database-local pipeline driven by `pg_cron`, independent
of `process_escalations()`. It may read canonical safety evidence and existing
settings, and it may write only isolated shadow/coverage/aggregate objects.

The existing candidate cannot yet produce trustworthy production evidence by
itself. Its coverage tables have no operational producer. Treating
`device_state`, `clients.last_seen_at`, or a single behavior ping as continuous
observation coverage would confuse device/collector outage with user silence.
The production design therefore adds a source-identified **coverage lease**:

- a lease says a supported collector was operational;
- it is not activity and never refreshes live liveness;
- it never extends forward from absence;
- a valid interval is finalized only between two server-received leases from the
  same healthy collector;
- unsupported or missing coverage makes a candidate unreplayable/fail-closed.

This means the later implementation includes bounded Android and Tauri coverage
reporting and corresponding artifact builds. Ordinary browser, manual check-in,
Guardian confirmation, and Shortcut events cannot claim continuous coverage.

## Approved Product and Operational Boundaries

The human has approved these boundaries:

1. Production shadow is notification-free and cannot change live alerts.
2. Shadow judgment runs every 5 minutes.
3. Per-user shadow detail is retained for 35 days.
4. Long-term reports contain only deidentified aggregate metrics.
5. Population is every `device_state` user with at least one active
   `group_members.monitored=true` membership.
6. `consent_data_sharing=true` is required for cohort contribution.
7. A non-consenting user may still receive an internal personal-only candidate
   evaluation; they never contribute user-level data to a cohort.
8. Base schema/config/producer deploys with the scheduler absent/off.
9. One manual committed canary must pass before a separate activation migration
   adds the 5-minute schedule.
10. Unauthorized live writes, hash/ACL validation failure, abnormal growth, or
    timeout disables shadow execution. ADR-0022 continues unaffected.
11. At least 14 complete local days of accepted shadow evidence are required
    before a separate human live-promotion decision.
12. The scheduler is a private database function plus `pg_cron`, not an inline
    call from `process_escalations()` and not a network Edge scheduler.

## Root Requirement Trace

| Field | Evidence / decision |
|---|---|
| Work type | delivery after design acceptance |
| Trace status | validated |
| Source | Human approvals above; ADR-0022; ADR-0023; current candidate code and tests |
| Root requirement | Learn whether adaptive alert timing is safer and more useful from real production conditions without risking current users |
| Invariant | A shadow cycle can read live evidence but writes zero rows to `alerts`, `alert_events`, `notifications`, or any live authority/config path; no shadow output is consumed by live alert code |
| Observed gap | Candidate commit `e8b5d92` is explicitly `fixture_only_unscheduled` / `operational_shadow=false`; it has no coverage producer, scheduler, retention, kill switch, canary, or production run evidence |
| Causal chain | Production deployment was deliberately stopped at ADR-0023’s boundary; without operational coverage provenance, absence cannot be separated from collector outage |
| Cause-owning layer | multi-layer: platform coverage contract + database shadow operations |
| Root verification | pgTAP/catalog/source gates, current-transaction live-write proof, exact function hashes, scheduler-off/on migration separation, role/ACL checks |
| User/operational path | monitored user → supported collector leases → finalized coverage → private candidate evaluation → compact shadow record/aggregate; live ADR-0022 alert and notifications remain unchanged |
| Permanent follow-up | Any live promotion requires a separate accepted ADR and release task |

## Goals

- Preserve the already audited candidate hierarchy and deterministic evaluator.
- Accumulate trustworthy, bounded production shadow evidence.
- Make missing coverage, missing context, low support, and consent withdrawal
  visible rather than silently filling gaps.
- Keep the shadow workload operationally bounded and immediately stoppable.
- Produce enough aggregate evidence for a later paired safety comparison.

## Non-Goals

- No learned threshold, cohort prior, sleep compensation, or candidate deadline
  controls a live alert.
- No change to `process_escalations()`, `private.notify_stage()`,
  `private.silence_threshold()`, `private.is_in_sleep_window()`,
  `private.apply_liveness_side_effects()`, or live notification dispatch.
- No new location, message, contact, browsing, or app-content collection.
- No external AI/model call.
- No long-term user-level event history beyond 35 days.
- No automatic live promotion.
- No production application of the separate ADR-0027 Data API ACL candidate as
  a side effect of adaptive deployment.

## Source Integration Boundary

The candidate and main branches diverge after
`add4c3ca2c167403956b14545e15cb96cb548d1c`.

Implementation must integrate onto current `main`, not deploy the old candidate
worktree directly:

1. bring in the replay compatibility harness commits needed for local testing;
2. bring in adaptive commits from routine-mode canonicalization through the
   unscheduled shadow recorder;
3. preserve the audited adaptive migration bytes unless a new RED test proves a
   required forward repair;
4. omit `20260726011500_explicit_data_api_acl_baseline.sql` from this rollout.
   Its production release is a separate authorization;
5. retain `20260727090000_scope_group_alerts_to_monitoring_direction.sql` and
   verify the group alert fix after integration;
6. add all operational work as new append-only migrations later than
   `20260727090000`.

Because the audited adaptive migrations have timestamps earlier than the already
applied group fix, production deployment requires an exact
`supabase db push --linked --include-all --dry-run`. The dry run must list only
the explicitly approved adaptive/base migration set. Any ACL migration or other
unexpected version is a hard stop.

## Architecture

### 1. Authority Separation

```text
canonical v2 behavior evidence ─┐
user settings / routine mode ───┼─ read only ─> adaptive shadow pipeline
coverage leases ────────────────┘                    │
                                                     ├─ shadow detail (35d)
ADR-0022 process_escalations ───────── live ─────────┼─ aggregate reports
                                                     │
alerts / alert_events / notifications <── never ─────┘
```

The production dispatcher does not call, wrap, or share a transaction entry
point with `process_escalations()`. The live scheduler continues on its existing
job and code.

### 2. Coverage Lease Contract

Add a narrow authenticated entry point:

```sql
public.record_alert_shadow_coverage_lease(
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
) returns text
```

Contract:

- `user_id` is always `auth.uid()` or, for the existing token/native Edge path,
  is supplied only to a separate service-only private wrapper.
- Server `clock_timestamp()` is the lease authority. `_observed_at` is accepted
  only within the existing five-minute drift bound and remains metadata.
- `_event_id` provides idempotency.
- The RPC writes only a private coverage-lease table.
- It does not call a behavior-ping validator, update `device_state`, write a
  behavior ping, resolve an alert, or dispatch a notification.
- `collector_state='operational'` is accepted only for a registered client,
  supported channel/collector contract, matching app version, and a capability
  hash with the required permissions/collector-health flags.
- Plain browser, installed-PWA-only, Shortcut, manual check-in, and Guardian
  confirmation may still supply real activity events through their existing
  paths, but they cannot claim continuous coverage in v1.
- Client roles receive execute on this RPC only; they receive no table access.

Initial continuous-capable collectors:

| Channel | Lease cadence | Maximum consecutive server gap | Validity condition |
|---|---:|---:|---|
| Tauri native idle collector | 5 minutes while healthy | 12 minutes | Tauri runtime alive, idle collector healthy, stable client/capability hash |
| Android native passive collector | 15–30 minutes | 35 minutes | UsageStats/native collector permissions and worker health confirmed |

Android cadence respects the existing battery rule against high-frequency native
polling. A lease may piggyback on an already scheduled health path; it must not
create a new 5-minute Android polling loop.

Coverage finalization:

1. partition leases by user, client, channel, and capability hash;
2. require two consecutive server-received operational leases;
3. require the gap to be positive and within the channel limit;
4. create coverage only for `[previous_received_at, current_received_at)`;
5. never project beyond the current lease;
6. split on permission, timezone, UTC-offset, app-version, client, collector, or
   capability change;
7. do not merge an unsupported or unknown interval into a valid one;
8. for user-level `activity_coverage_state='valid'`, every active
   continuous-capable client in the bounded expected-device set must have
   overlapping valid coverage. Any unsupported active surface or missing lease
   yields `unknown`, not `valid`;
9. finalize intervals only after their end and write immutable provenance hash.

The expected-device set is based on registered clients seen within the 35-day
detail window. The policy is deliberately conservative: low coverage reduces
evidence volume; it never creates false silence evidence.

### 3. Subject Context Producer

For every population member, capture a single as-of context:

- canonical sensitivity (`high|balanced|low`);
- canonical routine mode;
- timezone and computed UTC offset;
- source setting timestamps;
- model config/evidence version;
- provenance hash.

If any context input changes, close the previous interval at capture time and
open a new one. Never project today’s setting backward. Missing/malformed
timezone, ambiguous intervals, future timestamps, or hash mismatch produces a
stable unreplayable reason.

### 4. Intervention Producer

Copy only minimal, version-bound intervention metadata needed to exclude
prompt-induced responses from training:

- the user’s own self-notification;
- later alert-stage notifications that could cause a response;
- explicit concern/nudge/check-in prompts;
- Guardian confirmation as an intervention marker only.

Guardian confirmation remains permanently forbidden as personal activity,
coverage, sleep evidence, or a silence-clock reset in the candidate model.
Intervention rows are idempotent and provenance-bound to existing live row IDs,
but the shadow pipeline never updates the live source rows.

### 5. Profile and Cohort Maintenance

`private.rebuild_alert_gap_profiles()` and
`private.rebuild_routine_mode_cohort_priors()` remain the authoritative candidate
builders.

- The 5-minute cycle processes a bounded dirty queue; it does not rescan every
  user’s complete history.
- A daily maintenance job completes remaining 35-day profile/cohort rebuilds and
  retention cleanup.
- Personal profiles may use a user’s own qualified data regardless of cohort
  consent.
- Cohort queries require `profiles.consent_data_sharing=true` at rebuild time.
- Consent withdrawal enqueues every affected mode/context prior for rebuild.
  Until rebuild completes, that prior is ineligible.
- Cohort output contains no contributor identity.
- Small cells below `min_contributors=10` remain audit-only/low-support and are
  excluded from long-term segmented reports.

Initial shadow config:

| Key | Value |
|---|---:|
| evidence version | `canonical-v2` |
| session gap | 30 minutes |
| training horizon | 35 days |
| personal minimum samples | 8 |
| personal minimum support dates | 7 |
| personal minimum span | 14 days |
| personal minimum confidence | 0.80 |
| cohort minimum contributors | 10 |
| cohort minimum support dates | 7 |
| cohort minimum span | 14 days |
| cohort minimum confidence | 0.70 |
| cohort aggregate | weighted median |
| candidate neutral floor | 90 minutes |
| candidate neutral ceiling | 360 minutes |
| sensitivity buffers | 0 / 45 / 90 minutes |
| emergency neutral | 90 minutes, bound to the reviewed ADR-0022 function hash |

The complete canonical JSON and SHA-256 are review artifacts. The implementation
must calculate and pin the current live deterministic-definition hash before
creating the version. A mismatch with the candidate’s expected hash is a hard
stop, not an automatic rewrite.

### 6. Operational Recorder

Keep `private.record_alert_judgment_shadow(uuid,timestamptz)` unchanged as the
fixture-only unscheduled recorder.

Add:

```sql
private.record_alert_judgment_shadow_operational(
  _version_id uuid,
  _evaluated_at timestamptz,
  _max_population integer
) returns jsonb
```

It uses the same population and `private.resolve_alert_candidate()` contract,
validates the complete result shape/hash, and writes only shadow objects.

To prevent unbounded 5-minute detail growth:

- evaluate every population member every 5 minutes;
- persist a full per-user detail row only on first result, `would_alert`
  transition, basis/threshold/quality/reason change, or hourly checkpoint;
- keep a private current-state row for idempotent comparison;
- cap detailed persistence at 36 rows per user per UTC day. Exceeding the cap
  indicates oscillation and disables execution;
- persist one aggregate run row every cycle;
- never omit evaluation counts or unreplayable reason counts from aggregate
  evidence.

### 7. Cycle and Dispatcher

```sql
private.run_adaptive_alert_shadow_cycle(
  _version_id uuid,
  _evaluated_at timestamptz
) returns jsonb

private.dispatch_adaptive_alert_shadow_cycle() returns void
```

Cycle order:

1. acquire a non-blocking advisory transaction lock;
2. validate version/config/evidence/live-function hashes/ACLs/publication state;
3. validate population and storage budgets;
4. finalize eligible coverage leases;
5. capture subject context and interventions;
6. process bounded profile/cohort invalidations;
7. run the operational recorder;
8. compare current-transaction stats for live tables to the start snapshot;
9. append a deidentified run summary;
10. return aggregate metrics.

The cycle snapshots `pg_stat_xact_user_tables` for:

- `public.alerts`;
- `public.alert_events`;
- `public.notifications`.

Any current-transaction INSERT/UPDATE/DELETE delta raises a security exception,
causing the cycle subtransaction to roll back. Concurrent legitimate live cron
writes occur in other transactions and do not appear in this proof.

The dispatcher:

- reads a private singleton runtime config;
- no-ops when disabled;
- sets `statement_timeout=120s`, `lock_timeout=2s`, UTC timezone, and an empty
  search path;
- runs the cycle in a catchable subtransaction;
- stores only a mapped failure code, never raw PII/error payload;
- immediately disables execution on timeout, live-write detection, hash/ACL/
  publication validation failure, malformed evaluator output, or row-budget
  breach;
- disables after three consecutive ordinary failures;
- resets consecutive failures only after a complete successful cycle.

The runtime config defaults:

```text
enabled=false
accept_coverage_leases=false
max_population=10000
detail_retention_days=35
cycle_timeout_seconds=120
max_consecutive_failures=3
```

### 8. Scheduling

Use two named `pg_cron` jobs:

- `adaptive-alert-shadow-cycle-v1`: `*/5 * * * *`;
- `adaptive-alert-shadow-maintenance-v1`: daily UTC maintenance/retention.

Official Supabase guidance recommends no more than eight concurrent Cron jobs and
jobs under ten minutes. This design uses advisory locking and a two-minute timeout.
Activation must verify that adding these jobs does not exceed the concurrency
budget.

The base deployment contains **no `cron.schedule` call**. The activation job is
introduced only by a later append-only migration after canary approval.

The runtime kill switch is authoritative: `enabled=false` makes the dispatcher
do no work. An operator then deactivates or unschedules the Cron job using the
supported `cron.alter_job` / `cron.unschedule` functions. A final additive
deactivation migration is the rollback artifact.

## Database Objects

New private operational objects:

- `private.adaptive_alert_shadow_runtime_config`;
- `private.adaptive_alert_shadow_coverage_leases`;
- `private.adaptive_alert_shadow_user_state`;
- `private.adaptive_alert_shadow_cycle_runs`;
- `private.adaptive_alert_shadow_daily_reports`;
- bounded dirty/invalidation queues where required;
- coverage/context/intervention producer functions;
- operational recorder, cycle, dispatcher, cleanup, disable functions.

Existing candidate user-level tables remain RLS-enabled, have no client policies,
are absent from Realtime, and have all privileges revoked from
`PUBLIC`, `anon`, `authenticated`, and `service_role`.

Every `SECURITY DEFINER` function:

- sets `search_path=''`;
- schema-qualifies every object;
- pins UTC and deterministic formatting where hashes depend on it;
- revokes default execute from `PUBLIC`;
- grants only the narrow coverage-lease RPC to authenticated callers;
- keeps operational workers owner/cron-only.

## Retention and Privacy

Delete after 35 days:

- source-identifiable coverage leases;
- materialized per-user coverage intervals;
- per-user subject contexts and interventions;
- per-user shadow decision details;
- obsolete per-user current-state/history rows;
- obsolete per-user gap-profile generations.

Keep long-term:

- cycle status/duration and total counts;
- basis/quality/unreplayable distributions;
- paired candidate-versus-ADR-0022 aggregate metrics;
- k-anonymous routine/sensitivity/channel segment summaries.

Long-term rows contain no user ID, client ID, raw event ID, raw alert ID, exact
individual timestamp, location, content, or reversible contributor list.
Segments with fewer than 10 eligible people are suppressed into `other`.

No external AI receives any shadow data. Enabling one would require a separate
consent/privacy/spend decision.

## Two-Stage Production Activation

### Phase A — Base and Coverage Warm-Up

1. accepted High-risk ADR and implementation task;
2. integrate candidate source onto current main, excluding the unrelated ACL
   migration;
3. fresh compatibility replay, full pgTAP, typecheck, tests, build, static gate;
4. independent non-author Claude or Codex audit;
5. exact production account/project verification;
6. `--include-all --dry-run` lists exactly the approved adaptive/base migrations;
7. deploy base migration with:
   - runtime disabled;
   - lease acceptance initially disabled;
   - no shadow Cron jobs;
8. enable lease acceptance only after ACL/RPC smoke;
9. release matching web, Android APK, and Tauri coverage producers from the
   audited source/version set;
10. collect enough leases to make a manual cycle meaningful.

Android and Tauri artifacts are therefore part of the later implementation
release. They were unrelated to the earlier per-group alert fix, but they are
required for trustworthy continuous coverage in this production shadow design.

### Phase B — Manual Canary

Run one committed cycle in an explicit transaction:

1. capture canonical SHA-256 for live functions before the cycle;
2. capture current-transaction live-table counters;
3. call exactly one cycle for the pinned version/minute;
4. assert zero current-transaction live-table DML delta;
5. assert live function hashes unchanged;
6. assert candidate-only write-set and aggregate invariants;
7. assert no notification/push/network call;
8. assert scheduler jobs still absent;
9. commit only if every assertion passes; otherwise rollback and disable.

Global table counts/max timestamps are also recorded as coarse smoke evidence,
but are not used to blame concurrent legitimate live jobs. The transaction-local
stats are the authoritative canary-write proof.

### Phase C — Schedule Activation

Only after Phase B passes:

1. add a separate activation migration;
2. create the two named jobs;
3. set the pinned runtime version and `enabled=true`;
4. verify one scheduled cycle and Cron history;
5. verify live hashes/ACLs/current-transaction guard again;
6. begin the 14-day evidence clock only after the first complete local day.

## Automatic Stop Conditions

Immediate stop:

- any current-transaction live-table write;
- any live function hash drift;
- shadow table/RPC/publication privilege drift;
- malformed evaluator output or same-minute hash mismatch;
- `statement_timeout` or lock anomaly;
- population above 10,000 without a new accepted capacity review;
- per-user detail above 36 rows/day;
- decision, lease, or run counts violate declared invariants;
- a non-consenting user is observed in cohort input;
- Guardian/absence/outage is used as activity or sleep extension;
- raw PII/user identifiers enter aggregate reports.

Stop after three consecutive failures:

- transient internal database errors;
- bounded dirty-queue processing failure;
- temporary aggregate/report generation failure.

Stopping sets `enabled=false` in the same recovery transaction when possible.
The live ADR-0022 job continues. Operators then deactivate/unschedule only the
shadow jobs.

## Verification Plan

| Level | Contract/path | Evidence |
|---|---|---|
| Root | Shadow cannot mutate live authority | pgTAP + `pg_stat_xact_user_tables` delta + static DML/function-reference scan |
| User path | Monitored user gets candidate-only record; alert/notifications unchanged | local full-stack DB scenario and production canary |
| Coverage | No single/late/unsupported lease becomes valid coverage | pgTAP boundary matrix and platform tests |
| Privacy | Consent withdrawal removes future cohort contribution; user-level data expires | pgTAP time travel/cleanup and aggregate k-suppression tests |
| Security | No client table access; narrow lease RPC only; private workers owner-only | catalog ACL, RLS, Realtime, role-behavior tests, Security Advisor |
| Reliability | 5-minute overlap, timeout, failure counters, kill switch | concurrent session tests, advisory-lock tests, Cron smoke |
| Compatibility | Candidate + current main + group opt-out remain correct | ADR-0024 replay, all pgTAP, typecheck, Vitest, build, static gate |
| Release | Web/APK/Tauri coverage artifacts match source/version | artifact hashes, version alignment, download/smoke checks |
| Live | Scheduler-off base, committed canary, then separate activation | migration ledger, Cron catalog/history, live hashes, deidentified run summary |

Required negative tests:

- plain browser cannot claim continuous coverage;
- one lease cannot create an interval;
- stale/out-of-order/duplicate/drifted lease cannot extend coverage;
- client/capability/timezone change splits coverage;
- missing lease produces `unknown`, not activity;
- non-consent excludes cohort input immediately;
- current alert/Guardian/device status does not remove a user from population;
- shadow cycle cannot INSERT/UPDATE/DELETE live alert tables;
- client/service roles cannot execute operational workers;
- base migration creates no Cron job;
- activation migration creates only the two named jobs;
- disabling shadow does not alter the live alert Cron job.

## Evidence Gate After 14 Days

Fourteen days is necessary, not sufficient. A later live-promotion proposal may
be written only when all are true:

- 14 complete local days after scheduled activation;
- no P0/P1 shadow incident and no unauthorized write;
- at least 99% scheduled cycles complete successfully;
- cycle p95 under 60 seconds and maximum under 120 seconds;
- zero privacy/consent/ACL violation;
- deterministic config/evaluator/live hashes stable;
- adequate coverage and k-anonymous support for each segment being proposed;
- paired candidate-versus-ADR-0022 time-to-alert, earlier/later decision,
  fallback, and worst-segment metrics are available;
- independent non-author safety audit has no blocker.

Failure to meet evidence sufficiency keeps ADR-0022 live. It does not reset the
clock by hiding failed days or lowering support thresholds.

## Rollback / Recovery

- Set the private kill switch to disabled.
- Deactivate/unschedule only the two named shadow jobs.
- Keep live alert jobs and functions untouched.
- Do not drop candidate tables during an incident.
- Preserve deidentified run/failure evidence.
- Let 35-day cleanup remove per-user detail, or run the bounded cleanup manually.
- Use a new append-only deactivation/repair migration; never rewrite applied
  migration history.

## Task Inventory

| ID | Class | Route | Component/deps | Exact scope | Acceptance | Owner / reviewer | Isolation | Status |
|---|---|---|---|---|---|---|---|---|
| TASK-AS-01 | High-risk/M3 | S | source integration | Integrate audited candidate onto current main; omit ACL migration; preserve group fix | exact commit/migration manifest; replay passes | agy mechanical executor under Codex Manager; Claude audit at integrated gate | new worktree | blocked on ADR |
| TASK-AS-02 | High-risk/M3 | S | coverage contract | RED/Green DB lease schema/RPC/finalizer/retention tests | all negative coverage/ACL/privacy tests pass | same agy owner; Manager verifies | same branch | blocked on ADR |
| TASK-AS-03 | High-risk/M3 | S | client collectors after RPC lock | Tauri and Android healthy-collector lease emitters; no ordinary-browser lease | platform unit tests; no Android high-frequency polling | same agy owner | same branch | blocked on AS-02 |
| TASK-AS-04 | High-risk/M3 | S | operational DB pipeline | config/context/intervention/profile/cohort/recorder/cycle/dispatcher, scheduler absent | pgTAP/live-write guard/retention/growth/failure tests | same agy owner | same branch | blocked on AS-02 |
| TASK-AS-05 | High-risk/M3 | S | integration verification | replay, pgTAP, typecheck, tests, build, static/security gates | all deterministic checks pass | Codex Manager | integrated branch | blocked on AS-01..04 |
| TASK-AS-06 | High-risk/M3 | S | independent audit | Fresh integrated diff/spec/evidence review; `expected_verdict=null` | non-author Claude audit, zero blocker | Claude independent auditor | read-only locked order | blocked on AS-05 |
| TASK-AS-07 | Release/M3 | S | base deploy + platform artifacts | exact base migrations, web/APK/Tauri coverage release, no Cron | production account/dry-run/artifact/canary prerequisites pass | separate release task/human authorization | release branch | blocked on AS-06 |
| TASK-AS-08 | High-risk/M3 | S | manual canary | one committed transaction-local verified cycle | zero live DML/hash drift; scheduler absent | Codex Manager + human production authorization | production | blocked on AS-07 |
| TASK-AS-09 | High-risk/M3 | S | activation | separate activation migration, two named jobs, 14-day monitoring | scheduled smoke and stop controls pass | separate task + independent audit | production | blocked on AS-08 |
| TASK-AS-10 | High-risk/M3 or M4 if architecture changes | S | promotion decision | paired aggregate report and live proposal | separate accepted ADR; never automatic | human arbiter | none | blocked on 14-day evidence |

Delegation rule:

- The Manager writes one complete locked, hash-addressed order before each agy
  executor or Claude auditor call.
- agy receives no unresolved architecture or acceptance choice.
- `can_subdelegate=false`.
- Codex independently verifies workspace, diff, write set, hashes, and tests.
- Two rejected agy artifacts trigger Manager takeover and a
  `routing.agy-execution-fit` failure observation.

## Official Platform Constraints Used

- Supabase Cron runs inside Postgres using `pg_cron`, records history in
  `cron.job_run_details`, recommends no more than eight concurrent jobs, and
  recommends jobs finish within ten minutes.
- Supabase database function guidance requires explicit privileges; a
  `SECURITY DEFINER` function must pin `search_path`.
- Production schema changes remain version-controlled migrations; no Dashboard
  schema mutation is part of this design.
- RLS is defense-in-depth for candidate tables; table ACL and function execute
  rights are verified separately.

## Decision Requested

Approve or reject this complete design as one unit.

Approval authorizes writing a new accepted High-risk ADR and a detailed
implementation plan. It does **not** by itself authorize production deployment,
Cron activation, APK/Tauri publication, or live adaptive promotion; those remain
separate release/production gates.
