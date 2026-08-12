# GM and Native Onboarding Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GM silence classification and Android/iOS onboarding reflect canonical coverage and real native permissions.

**Architecture:** Keep GM correction in one append-only SQL migration and derive all UI readiness through a small pure TypeScript classifier. Native bridges expose current notification authorization; the existing wizard consumes that status and presents required versus recommended capabilities. Remove the iOS background-location implementation that conflicts with the accepted product decision.

**Tech Stack:** PostgreSQL/pgTAP, React 19, TypeScript/Vitest, Capacitor 7, Java Android bridge, Swift iOS plugin.

## Global Constraints

- A valid coverage interval ending within 26 hours classifies non-recent behavior as `person_quiet`.
- Alert precedence and all alert/learning/protection-health behavior remain unchanged.
- Notifications are ready only with OS authorization and an FCM token.
- Android required items are notifications, Usage Access, and connected guard; motion, battery exemption, and OEM autostart are recommended.
- iOS HealthKit may be labelled `Set up`, never `Allowed`, and is requested only from an explicit onboarding action.
- Remove iOS background-location requests and monitoring; preserve foreground SOS location.
- Do not deploy, release, upload, or mutate production.

---

### Task 1: Coverage-aware GM silence classification

**Files:**
- Create: `supabase/migrations/20260812000000_gm_coverage_aware_silence_kind.sql`
- Create: `supabase/tests/gm_coverage_aware_silence_kind.sql`

**Interfaces:**
- Consumes: `public.alert_observation_coverage_intervals(user_id, ends_at, activity_coverage_state)` and the current `public.gm_list_clients()` contract.
- Produces: unchanged GM JSON schema with corrected `silence_kind`.

- [ ] **Step 1: Write the failing pgTAP fixture**

Create four GM-visible subjects: iOS and Android with stale heartbeats plus recent valid coverage, one with expired coverage, and one with no coverage plus a fresh heartbeat. Assert `person_quiet`, `person_quiet`, `device_dark`, and `person_quiet` respectively.

- [ ] **Step 2: Run the test to verify RED**

Run: `npm run db:replay:compat` followed by the repository's pgTAP runner for `gm_coverage_aware_silence_kind.sql`.

Expected: the iOS and Android recent-coverage assertions fail as `device_dark`.

- [ ] **Step 3: Add the append-only migration**

Copy the current function contract, add a lateral maximum valid coverage end, and check `coverage.last_at > now() - interval '26 hours'` before the heartbeat fallback.

- [ ] **Step 4: Run the pgTAP test to verify GREEN**

Expected: all four classification assertions pass and GM execute grants remain unchanged.

### Task 2: Native notification authorization status

**Files:**
- Modify: `src/features/passive/native.ts`
- Modify: `android/app/src/main/java/com/keepcontact/app/PassivePingPlugin.java`
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/KcPassivePingPlugin.swift`
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/PushRegistrar.swift`
- Create: `src/features/passive/nativePermissions.test.ts`

**Interfaces:**
- Produces: `getNativeNotificationPermissionStatus(): Promise<boolean>` and native `getNotificationPermissionStatus()` returning `{ granted: boolean }`.

- [ ] **Step 1: Write a failing Vitest bridge test**

Assert the TypeScript helper returns the native `granted` value and fails closed when the bridge rejects.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `npm test -- src/features/passive/nativePermissions.test.ts`.

Expected: import/method missing.

- [ ] **Step 3: Implement the bridge on all three layers**

Android uses `NotificationManagerCompat.from(context).areNotificationsEnabled()`. iOS uses `UNUserNotificationCenter.current().getNotificationSettings` and treats `.authorized` and `.provisional` as granted.

- [ ] **Step 4: Run focused tests and typecheck**

Run: `npm test -- src/features/passive/nativePermissions.test.ts && npm run typecheck`.

Expected: PASS.

### Task 3: Honest onboarding readiness and copy

**Files:**
- Create: `src/features/passive/onboardingReadiness.ts`
- Create: `src/features/passive/onboardingReadiness.test.ts`
- Modify: `src/features/passive/OnboardingWizard.tsx`
- Modify: `src/features/onboarding/onboardingPresentation.ts`
- Modify: `src/features/onboarding/OnboardingFlow.tsx`
- Modify: `src/features/onboarding/onboardingPresentation.test.ts`

**Interfaces:**
- Produces: pure Android/iOS readiness classifiers and optional capability labels/requirement level consumed by the existing flow.

- [ ] **Step 1: Write failing classifier tests**

Assert Android Ready does not require motion/battery/autostart, does require OS notification authorization + token + Usage Access + guard, and iOS Ready requires OS notification authorization + token + guard while Health is recommended.

- [ ] **Step 2: Run the focused tests and confirm RED**

Run: `npm test -- src/features/passive/onboardingReadiness.test.ts src/features/onboarding/onboardingPresentation.test.ts`.

Expected: classifier missing and old Ready copy assertion fails.

- [ ] **Step 3: Implement minimal classifier and presentation contract**

Add `requirement` and `stateLabel` to capabilities, render them without changing the screen structure, and update result/welcome copy to the approved honest wording.

- [ ] **Step 4: Wire the wizard to real statuses**

Read notification authorization separately from the token. Remove automatic HealthKit authorization from passive configuration; add an explicit iOS Health row whose action calls `enableHealthWake()` and refreshes status.

- [ ] **Step 5: Run focused tests and typecheck**

Expected: PASS.

### Task 4: Remove iOS background-location collector residue

**Files:**
- Modify: `ios-passive-ping/ios/Sources/KcPassivePingPlugin/PassiveGuard.swift`
- Modify: `scripts/s1-platform-contract.test.mjs`

**Interfaces:**
- Preserves: silent push, HealthKit wake, unlock/foreground sampling, and foreground SOS location outside `PassiveGuard`.
- Removes: `CLLocationManager`, Always authorization, significant-change monitoring, and its delegate callbacks.

- [ ] **Step 1: Add failing source-contract assertions**

Assert the shipping iOS passive collector contains none of `requestAlwaysAuthorization`, `startMonitoringSignificantLocationChanges`, or `CLLocationManagerDelegate`.

- [ ] **Step 2: Run and confirm RED**

Run: `npm test -- scripts/s1-platform-contract.test.mjs`.

Expected: the new assertions fail against the residual Swift code.

- [ ] **Step 3: Remove only the residual background-location path**

Keep `NSObject` inheritance and all non-location collectors intact.

- [ ] **Step 4: Run the platform contract and typecheck**

Expected: PASS.

### Task 5: Integrated verification and project truth

**Files:**
- Modify: `Projects/Keep Contact/Known Issues.md` in the Brain through guarded writeback.
- Modify: `Experiences/Keep Contact/Dev Log.md` in the Brain through guarded writeback.

**Interfaces:**
- Produces: verified local change set and durable correction of the previously pending iOS/APK collection truth.

- [ ] **Step 1: Run full verification**

Run: `npm test`, `npm run typecheck`, `npm run build`, Android unit tests, `gradlew.bat assembleRelease bundleRelease`, and local Supabase replay/pgTAP.

- [ ] **Step 2: Render mobile onboarding at 390×844**

Capture Android setup, iOS setup, and Ready result; compare against the saved pre-change screenshots for overflow, labels, hierarchy, and truthful copy.

- [ ] **Step 3: Review the diff and requirements**

Confirm every changed file is inside the guarded write set and no deployment/release action occurred.

- [ ] **Step 4: Write back changed truth**

Record that APK/iOS collection is proven healthy at the collector layer, learning remains not coverage-qualified, GM local fix exists but is undeployed, and onboarding permission truth was corrected locally.

