# Keep Contact Passive Check-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan package by package. Do not delegate; this session is Manager-direct.

**Goal:** Implement accepted ADR-0042 as an additive, shadow-first account-level passive check-in engine, produce locally verified release-candidate artifacts, and stop before any production, Store, publication, rollout, or release action.

**Architecture:** Platform collectors emit positive, privacy-limited evidence into one authenticated ingest contract. The server owns immutable contract versions, monitoring epochs, UTC windows, account-level OR aggregation, consecutive-miss chains, sleep-gated alert creation, causal snapshots, advisory recommendations, and shadow comparison. Collector health remains an independent display/training-exclusion axis and never controls window or alert authority. Existing `legacy` behavior remains the default until an account explicitly migrates.

**Tech Stack:** React 19 + Vite + TypeScript + Vitest; Supabase Postgres/RLS/pgTAP/Edge Functions; Capacitor 7 Android Java and iOS Swift plugin; Tauri 2 Rust; PowerShell/Windows local verification.

**Binding inputs:** ADR-0042; `docs/superpowers/specs/2026-08-13-kc-passive-checkin-system-design.md` revision 10; ADR-0039 and amendment one; ADR-0040; `android/PLAY-CONSTRAINTS.md`.

## Global Constraints

- Work only in an isolated `codex/passive-checkin-impl` worktree created from the accepted revision-10 design commit.
- Start and finish a separate guarded Brain task with an exact write set for every numbered package below.
- Add new migrations only. Never edit `20260808160000_baseline_from_production.sql` or any existing migration.
- Run each named test once in RED before implementation, then make the smallest package change that turns it GREEN.
- Do not call a remote Supabase project, change production data, enable remote cron, deploy an Edge Function, publish artifacts, submit to TestFlight/Play/Store, create a GitHub Release, or roll out an account.
- Existing accounts remain `legacy`; no migration may silently activate `passive_checkin`.
- Passive evidence never resolves, retracts, or relabels an open alert. Existing explicit-resolution paths stay authoritative.
- Collector health may affect display, recommendations, and training eligibility only. It may not create `unknown` windows, pause miss chains, or prevent an eligible self alert.
- Heartbeats, wakes, notification acknowledgement, reachability, location changes, automotive-only motion, and zero-step samples are not check-ins.
- Raw package names, URLs, typed content, routes, coordinates, raw motion, and Health records must not leave the collector.
- Preserve old-client acceptance during the compatibility window. New passive APIs are additive.
- The Windows host cannot compile iOS or build macOS artifacts. Static Swift contracts may pass locally, but iOS/macOS real-device and signed-build gates must remain explicitly open in launch readiness.

## Package 0 — Accepted Baseline and Isolated Workspace

**Files:**

- Modify: `docs/superpowers/specs/2026-08-13-kc-passive-checkin-system-design.md`
- Create: `docs/superpowers/plans/2026-08-14-kc-passive-checkin-implementation.md`

**Steps:**

- [ ] Verify `git diff --check` and that revision 10 says local implementation/release-candidate preparation is authorized while production and Store actions remain checkpoints.
- [ ] Commit the accepted design and this plan on `codex/passive-checkin-design`.
- [ ] Confirm `.worktrees/` is ignored with `git check-ignore -q .worktrees`.
- [ ] Create `.worktrees/passive-checkin-impl` on branch `codex/passive-checkin-impl` from the accepted design commit.
- [ ] Run `npm ci`, `npm test`, `npm run typecheck`, `npm run build`, `cargo test --manifest-path src-tauri/Cargo.toml`, and `android\\gradlew.bat -p android testDebugUnitTest` as the isolated baseline.
- [ ] If a baseline command fails, distinguish a pre-existing failure from worktree/setup drift before touching implementation.

## Package 1 — Database Contract and Read Surface

**Files:**

- Create: `supabase/migrations/20260814183000_passive_checkin_contract.sql`
- Create: `supabase/tests/passive_checkin_contract.sql`
- Modify: `src/lib/database.types.ts`
- Create: `src/features/passive/checkinContract.test.ts`
- Create: `src/features/passive/checkinContract.ts`

**Contract to add:**

- `public.passive_checkin_accounts`: one row per account, `engine_mode` constrained to `legacy|shadow|passive_checkin`, active epoch/contract references, kill-switch state, timestamps.
- `public.passive_checkin_contract_versions`: immutable `D`, `N`, sleep-policy choice, timezone/sleep snapshot, platform-floor/provenance fields, server `effective_at`, actor and version.
- `public.passive_monitoring_epochs`: immutable epoch boundary and start reason; exactly one active epoch per account.
- `public.passive_checkin_windows`: half-open UTC bounds, arrival deadline, outcome constrained to `pending|checked_in|missed|superseded`, causal evidence ID, finalization timestamp.
- `private.passive_alert_causal_windows`: immutable ordered window IDs for the alert that a miss chain earned.
- `public.my_passive_checkin_status()` returns only the caller's settings, active epoch/window, current miss count, health summary and latest recommendation summary.
- `public.set_passive_checkin_contract(...)` validates `D=20..360`, `N=1..1,000,000`, a required sleep-policy choice, and an IANA timezone when sleep is enabled; creates a new contract/epoch at server time and supersedes the old partial window.

**TDD steps:**

- [ ] Write pgTAP assertions for table/constraint/index existence, immutable version rows, one active epoch, required sleep choice, D/N limits, server acknowledgement, half-open first window, RLS and least-privilege grants.
- [ ] Run `npm run db:replay:compat -- --test passive_checkin_contract` and capture the expected RED.
- [ ] Implement only the schema, RLS, grants, status RPC, settings RPC and first-window creation.
- [ ] Re-run the focused pgTAP file to GREEN, then run `npm run db:replay:compat`.
- [ ] Add TypeScript parsing/validation tests for the RPC result before adding `checkinContract.ts`.
- [ ] Regenerate or minimally update `database.types.ts`; review the diff so unrelated production drift is not absorbed.
- [ ] Commit package 1 after focused/full database tests, Vitest and typecheck pass.

## Package 2 — Trust, Binding and Evidence Ingest

**Files:**

- Create: `supabase/migrations/20260814190000_passive_evidence_ingest.sql`
- Create: `supabase/tests/passive_evidence_ingest.sql`
- Create: `supabase/functions/passive-evidence/contract.ts`
- Create: `supabase/functions/passive-evidence/contract.test.ts`
- Create: `supabase/functions/passive-evidence/index.ts`
- Modify: `src/lib/database.types.ts`
- Create: `src/features/passive/evidenceContract.test.ts`
- Create: `src/features/passive/evidenceContract.ts`

**Contract to add:**

- Closed surface registry for `android_native`, `ios_native`, `tauri_native`, `installed_pwa`, and `shortcut`, with arrival allowance and correction horizon from revision 10; absent types cannot bind.
- `private.passive_collector_bindings`: stable collector instance, exactly one active protected account, surface type, client ID, credential hash/version, sequence cursor, revoked timestamp.
- `private.passive_evidence_events`: immutable canonical payload hash, event ID, collector sequence, observed/received timestamps, evidence class/kind, correlation group and assigned epoch/window.
- `private.passive_surface_health_intervals`: collector health and repair reason, separate from evidence/window authority.
- Authenticated foreground/PWA path and token-authenticated native/Tauri path both call one private validator.
- Retry with identical event ID/payload returns `duplicate`; same ID with changed payload returns `conflict` and audits it; sequence rollback, revoked binding, cross-account binding, >5-minute future timestamp and >7-day evidence are rejected.
- Positive history inside seven days may change only `pending|missed` to `checked_in`; absence never arrives as evidence and cannot create a miss.
- Retention removes raw ingest after 35 days and derived windows/recommendations after 90 days; raw/private tables receive no `anon`/`authenticated` grants and are not added to Realtime.

**TDD steps:**

- [ ] Write Edge contract tests for field allowlist, type/UUID/timestamp validation, credential stripping and fail-closed outcomes.
- [ ] Run `npx vitest run supabase/functions/passive-evidence/contract.test.ts` and capture RED.
- [ ] Write pgTAP trust/identity/privacy/retention tests and capture RED through local replay.
- [ ] Implement SQL validator and Edge transport without logging credentials or raw payloads.
- [ ] Make Edge tests and focused pgTAP GREEN; then run full replay, Vitest and typecheck.
- [ ] Commit package 2.

## Package 3 — Android Positive-Evidence Collector

**Files:**

- Create: `android/app/src/main/java/com/keepcontact/app/PassiveEvidenceContract.java`
- Create: `android/app/src/test/java/com/keepcontact/app/PassiveEvidenceContractTest.java`
- Modify: `android/app/src/main/java/com/keepcontact/app/PassivePing.java`
- Modify: `android/app/src/main/java/com/keepcontact/app/ActivityTransitionReceiver.java`
- Modify: `android/app/src/main/java/com/keepcontact/app/NotifyWorker.java`
- Modify: `android/app/src/main/java/com/keepcontact/app/PassivePingPlugin.java`
- Modify: `src/features/passive/native.ts`
- Modify: `src/features/passive/native.test.ts`

**Behavior:**

- Upload UsageStats `KEYGUARD_HIDDEN`, `USER_INTERACTION`, or qualifying foreground history at the true event timestamp; never replace it with collector wake time and never upload package names.
- Qualify keyguard-hidden/foreground interaction and pedestrian walking/running transitions; screen-on, stationary and automotive-only events do not check in.
- Initial/restored charging state is baseline. Emit `power_transition` only after both states are known and the new state stays stable for five seconds; collapse edges from one collector inside 60 seconds into one correlation group.
- Use the new collector binding/credential and monotonically increasing sequence. On account switch/sign-out, revoke/clear the old binding, credential and local queue before accepting the new account.
- WorkManager remains the default wake mechanism. No new manifest receiver, wake lock, accessibility requirement, exact-alarm requirement, unconditional foreground service or unapproved core permission.

**TDD steps:**

- [ ] Add Java unit tests for true timestamps, no package-name field, screen-on exclusion, automotive exclusion, stable charging edges, flap suppression, sequence persistence and account-switch clearing.
- [ ] Run `android\\gradlew.bat -p android testDebugUnitTest --tests com.keepcontact.app.PassiveEvidenceContractTest` and capture RED.
- [ ] Implement the smallest contract/collector changes, then make focused Android tests GREEN.
- [ ] Add/turn GREEN the TypeScript bridge tests for the exact native configuration/binding payload.
- [ ] Run Android unit suite, `compileDebugJavaWithJavac`, Vitest and typecheck.
- [ ] Commit package 3.

## Package 4 — iOS Positive Evidence and Wake Layering

**Files:**

- Create: `src/features/passive/iosEvidenceContract.test.ts`
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/HealthWake.swift`
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/DeviceSample.swift`
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/PassiveGuard.swift`
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/KcPassivePingPlugin.swift`
- Modify: `ios/App/App/Info.plist`
- Modify: `src/features/passive/native.ts`
- Modify: `src/features/passive/native.test.ts`

**Behavior:**

- HealthKit observer wakes the app, reports collector health, then queries positive step history; it emits evidence only for positive steps/floors at their real interval timestamp. A wake by itself and a zero-step result emit no check-in.
- Device samples promote positive pedestrian steps/floors only; automotive-only motion disqualifies movement evidence.
- Unlock and foreground remain positive evidence. Push wake, Health wake and significant-location change are wake/health events only.
- Significant-change location monitoring never reads `locations`, never starts continuous updates, never enables `UIBackgroundModes: location`, and never records a check-in. Correct comments to say Apple documents system-termination relaunch while user force-quit behavior remains unproven until the device gate.
- Charging edges follow the same known-state/stable-five-second/60-second-correlation contract as Android.
- Collector credential is stored in Keychain-backed storage and cleared on sign-out/account switch.

**TDD steps:**

- [ ] Write a RED static contract test asserting positive-query semantics, no unconditional `recordEvent(...steps)`, no coordinate reads, no continuous location mode, force-quit wording honesty, charging stability and credential clearing.
- [ ] Implement Swift changes and make the static contract GREEN.
- [ ] Run `npx cap sync ios`, the iOS contract test, full Vitest, typecheck and build.
- [ ] Record that Xcode compilation, TestFlight and three-device evidence remain open; do not claim them from Windows.
- [ ] Commit package 4.

## Package 5 — Tauri Reconstructed Input Evidence

**Files:**

- Modify: `src-tauri/src/lib.rs`
- Create: `src/features/passive/tauriEvidence.test.ts`
- Create: `src/features/passive/tauriEvidence.ts`
- Modify: `src/features/passive/PassivePingBoot.tsx`
- Modify: `src/features/passive/shadowCoverage.ts`
- Modify: `src/features/passive/shadowCoverage.test.ts`

**Behavior:**

- Add a Tauri command returning current sample time, idle duration and reconstructed `last_input_at`; send only the reconstructed timestamp and closed evidence kind, never key, app, URL or typed content.
- Five-minute sampling emits one idempotent evidence event only when `last_input_at` advances. Sleep/resume and clock change cannot fabricate a future event.
- Tauri reports channel `tauri`, collector contract/version and health separately; browser and desktop-native channels cannot be confused.
- Use the new binding/credential/sequence contract and clear the local queue on account switch/sign-out.

**TDD steps:**

- [ ] Add Rust unit tests for reconstruction, tick-count wrap, unavailable probes and clock guards; run `cargo test --manifest-path src-tauri/Cargo.toml` to RED.
- [ ] Add Vitest tests for de-duplication, true observed timestamp, channel identity, queue partitioning and no raw input fields; run focused test to RED.
- [ ] Implement Rust command and TypeScript scheduler, then turn both suites GREEN.
- [ ] Run Rust tests, full Vitest, typecheck and build.
- [ ] Commit package 5.

## Package 6 — Window Aggregation, Miss Chain and Alert Authority

**Files:**

- Create: `supabase/migrations/20260814193000_passive_window_engine.sql`
- Create: `supabase/tests/passive_window_engine.sql`
- Create: `src/features/passive/windowState.test.ts`
- Create: `src/features/passive/windowState.ts`
- Modify: `src/lib/database.types.ts`

**Behavior:**

- `private.process_passive_checkin_subject(user_id, now)` and `public.process_passive_checkins()` finalize due windows per subject with failure isolation.
- Window boundaries are server-owned UTC half-open intervals. Evidence at start belongs to the window; evidence at end belongs to the next. Arrival allowances come only from surfaces bound during the window.
- Any qualified evidence checks in the account; no evidence by the deadline misses regardless of collector health.
- Checked-in clears the consecutive-miss chain. Exactly `N` consecutive misses earns one alert eligibility; sleep allows counting but defers alert insertion until canonical sleep/post-wake grace ends.
- Create at most one existing `alerts` row at `self` using a compatible inactivity cause and one immutable causal snapshot. Further missed windows cannot duplicate it.
- Replace `process_escalations()` additively so legacy threshold/dark-device inactivity creation skips `passive_checkin` accounts, while SOS/non-inactivity and existing stage progression remain unchanged.
- Passive evidence after alert creation cannot call any resolution function. Explicit resolution creates a fresh epoch/window at `resolved_at`.
- Group/community notification copy says KC lost contact and never says the person is in danger.

**TDD steps:**

- [ ] Write all 16 specification contract cases plus per-subject failure isolation, dual-engine exclusion, alert uniqueness, causal immutability and no-passive-resolution pgTAP tests.
- [ ] Run focused local replay and capture RED.
- [ ] Implement pure subject evaluator first, then scheduler wrapper, then the legacy-authority guard and explicit-resolution epoch hook.
- [ ] Make focused pgTAP GREEN, run adjacent alert/sleep/failure-isolation tests, then full replay.
- [ ] Add TypeScript display-state parser tests, implement parser, run Vitest/typecheck.
- [ ] Commit package 6.

## Package 7 — Advisory Learner and Platform Floor

**Files:**

- Create: `supabase/migrations/20260814200000_passive_checkin_recommendations.sql`
- Create: `supabase/tests/passive_checkin_recommendations.sql`
- Create: `src/features/passive/recommendation.test.ts`
- Create: `src/features/passive/recommendation.ts`
- Modify: `src/lib/database.types.ts`

**Behavior:**

- Store recommendation revisions separately from active contract versions, with estimator/config version, eligible episode IDs/hash, excluded counts/reasons, source confidence, proposed D/N, platform floor, expected interruptions/day and generated time.
- Eligible episodes exclude superseded windows, sleep/post-wake, alert response, Guardian/Shortcut/replay, and every interval overlapping a non-reporting bound surface.
- Fewer than three eligible episodes yields the transparent six-hour default. Use the revision-10 `B=1` estimator over 30 evidence days; a single >150% outlier cannot change `R`, while two comparable different-date gaps may.
- Map through `ceil(R/D)`, then raise the recommendation—not the active setting—to the maximum bound-surface platform floor. Android and Tauri use measured constants; iOS remains provisional 12 hours until device evidence replaces it.
- Recommendation writes are mechanically unable to update active settings, windows, chains or alerts.

**TDD steps:**

- [ ] Write RED pgTAP cases for every exclusion, default, outlier rule, mapping/floor, provenance and no-live-mutation invariant.
- [ ] Implement recommendation storage and rebuild function; make focused/full database tests GREEN.
- [ ] Write RED TypeScript parsing/explanation tests, implement UI model, make Vitest/typecheck GREEN.
- [ ] Commit package 7.

## Package 8 — Settings, Health and Explicit Migration UX

**Files:**

- Create: `src/features/passive/checkinSettings.test.ts`
- Create: `src/features/passive/checkinSettings.ts`
- Create: `src/features/passive/PassiveCheckinSettings.tsx`
- Create: `src/features/passive/PassiveCheckinSettings.css`
- Create: `src/features/passive/passiveCheckinPresentation.test.ts`
- Create: `src/features/passive/passiveCheckinPresentation.ts`
- Modify: `src/features/baseline/RoutineSettings.tsx`
- Modify: `src/features/passive/PassiveSignalCard.tsx`
- Modify: `src/features/baseline/ProtectionHealthCard.tsx`
- Modify: `src/features/onboarding/OnboardingFlow.tsx`
- Modify: `src/lib/i18n.tsx`
- Modify: `src/App.viewport.test.ts`

**Behavior:**

- D and N accept the full ranges without presets; show `H=D×N`, active server version/effective time, recommendation with rationale, expected interruption rate and realistic platform-floor warning.
- Sleep choice is mandatory: configured sleep with timezone or explicit no-sleep acknowledgement. Missing choice blocks enablement.
- Save uses one RPC and changes UI only after server ack; failure reverts to last server truth and announces an accessible error.
- Existing users see an explicit migration explanation and remain legacy until they confirm. Shadow mode has no alert side effects. Old clients cannot edit passive settings.
- Health shows `Ready|Limited|Off`, exact affected device/reason and repair action, but never claims Limited pauses miss counting.
- Copy plainly states KC may lose contact and may ask the user; it does not promise accident detection.
- Keyboard, screen reader, focus, 320px viewport and bilingual copy tests pass.

**TDD steps:**

- [ ] Add RED pure-model tests for ranges, H overflow-safe formatting, sleep requirement, floor warning, migration eligibility, server-ack rollback and health copy.
- [ ] Implement API/model, then component wiring and i18n until focused tests pass.
- [ ] Run full Vitest, typecheck and build; verify viewport contract.
- [ ] Commit package 8.

## Package 9 — Shadow Comparison, Observability and Kill Switch

**Files:**

- Create: `supabase/migrations/20260814203000_passive_checkin_shadow_observability.sql`
- Create: `supabase/tests/passive_checkin_shadow_observability.sql`
- Create: `scripts/passive-checkin-shadow-report.mjs`
- Create: `scripts/passive-checkin-shadow-report.test.mjs`
- Modify: `package.json`
- Modify: `src/lib/database.types.ts`

**Behavior:**

- Shadow mode evaluates the same epoch/windows without inserting alerts or notifications and records causal IDs sufficient to replay every decision.
- Aggregate-only observability exposes pending/checked-in/missed/superseded counts, overdue pending windows, arrival-gap distributions, late positive corrections split by whether they intersect an alert causal snapshot, duplicate/replay/conflict/binding rejections, chain transitions, alert opens/duplicate suppressions, recommendation changes, cleanup/job health and interruptions/user/day segmented by platform mix/contract/client version.
- Hard-invariant alarms cover late absence creating a miss, passive resolution, Guardian-as-subject evidence, cross-account acceptance, dual-engine alerts and prohibited raw fields.
- Global kill switch stops new passive inactivity alerts and marks affected accounts Limited; it never substitutes a legacy threshold or rewrites completed state.
- Report command fails the rollout gate unless shadow duration is at least 14 days, each platform mix has at least 20 qualifying accounts, median interruptions `<=0.2/day`, p90 `<=1/day`, zero hard-invariant violation and no dual-engine alert.

**TDD steps:**

- [ ] Write RED pgTAP for zero side effects, causal replay, metrics privacy, kill switch and alarms.
- [ ] Write RED Node tests using fixture aggregates for every rollout threshold and failure message.
- [ ] Implement SQL and report command, make focused tests GREEN, then run full replay/Vitest/typecheck.
- [ ] Commit package 9.

## Package 10 — Integrated Verification and 0.7.0 Release Candidate

**Files:**

- Modify: `src/lib/version.ts`
- Modify: `android/app/build.gradle`
- Modify: `ios/App/App/Info.plist`
- Modify: `src-tauri/tauri.conf.json`
- Create: `docs/release/0.7.0-passive-checkin-readiness.md`
- Create: `docs/release/0.7.0-passive-checkin-rollback.md`

**Steps:**

- [ ] Start the package task with exact version/build/readiness write set; set all four product version files to `0.7.0` together without publication.
- [ ] Run `git diff --check` and exact write-set review.
- [ ] Run `npm test`, `npm run typecheck`, `npm run build`, `npm run local:gate`, and `npm run db:replay:compat` from clean state.
- [ ] Run `cargo test --manifest-path src-tauri/Cargo.toml` and `npm run tauri build` for Windows NSIS/MSI.
- [ ] Run `android\\gradlew.bat -p android clean testReleaseUnitTest assembleRelease bundleRelease`; verify APK/AAB version, package ID, signing certificate, APK v1/v2 signature, AAB contents, manifest permission disclosure and identical feature behavior.
- [ ] Run `npx cap sync ios`; verify plist/entitlement/static contracts. Record Xcode archive/TestFlight and three-device gate as open, not passed.
- [ ] Hash every local candidate artifact and record exact source commit, commands, results, open platform gates, database/Edge deployment order, forward-only rollback and global kill-switch procedure.
- [ ] Confirm no release script, remote Supabase command, Vercel deployment, GitHub publication or Store submission ran.
- [ ] Use `superpowers:verification-before-completion`, then `superpowers:finishing-a-development-branch` to present the locally complete branch and the production/Store checkpoint to the human.

## Completion Boundary

This plan is complete when packages 1–9 are locally green, the 0.7.0 Windows/Android candidate artifacts and hashes exist, the readiness/rollback documents distinguish passed local evidence from open real-device/shadow gates, and the branch is ready for human review. It is not complete—and must not be described as launched—until the separate 14-day shadow, qualifying cohort, Android/iOS/macOS device, signed iOS/macOS build, production deployment, Store and rollout checkpoints are actually passed and authorized.
