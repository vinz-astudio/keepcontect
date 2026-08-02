# Keep Contact Prototype-to-APK UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Android APK's mixed classic/spatial UI with one production-connected React UI that matches `Prototype/interactive_prototype.html` across Watch, Routine, Circles, Me, Onboarding, and SOS.

**Architecture:** Keep existing Supabase, Capacitor, auth, liveness, alert, invite, push, and profile APIs as runtime truth. Replace the monolithic `HomeScreen` composition with a thin `AppShell`, five focused screen components, and reusable Prototype primitives; use pure presentation-model functions for role/state visibility so Vitest can verify safety rules without a browser DOM.

**Tech Stack:** React 19, TypeScript 5.8, Vite 6, Vitest 3, Capacitor 7, Supabase JS, `@fontsource-variable/plus-jakarta-sans@^5.3.0`, `@material-symbols/font-400@^0.45.10`.

## Global Constraints

- `Prototype/interactive_prototype.html` is the only authority for visual design, layout, navigation, section order, information density, and interaction intent.
- Production APIs and accepted Brain contracts remain authoritative for data, permissions, roles, alerts, SOS, and privacy.
- The only approved old-only additions are Routine type after Sleep & Morning Grace and GM Manager tools immediately above Notifications.
- Do not expose a classic/new UI selector; do not add a fifth ordinary tab.
- Do not change Concern server eligibility, liveness GPS persistence, or emergency multi-card database storage in this plan.
- No demo name, address, status, acknowledgement, delivery result, or permission result may appear as production truth.
- Bundle Plus Jakarta Sans and Material Symbols locally; add no handwritten inline SVG, emoji icon, CSS drawing, or runtime Google Fonts request.
- Minimum touch target is 44×44 CSS px; support 360/375/412 px widths; preserve Android safe areas, reduced motion, focus order, and WCAG AA contrast.
- Do not release a mixed visual state. Intermediate commits are development checkpoints only; build the APK after every ordinary tab and onboarding use the new system.

## File Structure

### Shared shell and visual system

- Modify `package.json` and `package-lock.json`: add the two local font/icon packages.
- Modify `src/main.tsx`: import the bundled font assets before application CSS.
- Modify `src/index.css`: replace the partial spatial tokens with the Prototype Warm Linen/Warm Charcoal token contract.
- Create `src/features/prototype/PrototypeUI.tsx`: icon, section header, card, row, badge, disclosure, segmented control, feedback, and state-panel primitives.
- Create `src/features/prototype/PrototypeUI.css`: exact reusable Prototype component styling.
- Create `src/features/prototype/prototypeUi.contract.test.ts`: static-render contracts for semantics and icon use.
- Create `src/features/shell/AppShell.tsx`: tab composition, header, scroll surface, floating navigation, SOS overlay, toasts, and global overlays.
- Create `src/features/shell/AppShell.css`: shell, safe-area, bottom-navigation, and SOS styling.
- Create `src/features/shell/appShellState.ts`: pure tab and SOS state helpers.
- Create `src/features/shell/appShellState.test.ts`: navigation/SOS state tests.
- Modify `src/features/nav/TabBar.tsx` and `src/features/nav/TabBar.css`: reduce the legacy component to the Prototype four-tab plus center-SOS contract.

### Screen composition

- Create `src/features/watch/watchPresentation.ts` and `.test.ts`: pure Watch ordering, role, task, evidence-quality, and action eligibility.
- Create `src/features/watch/WatchScreen.tsx` and `.css`: Watch layout connected to existing Notifications, group status, task, and GM surfaces.
- Create `src/features/routine/RoutineScreen.tsx` and `.css`: Prototype Routine composition around existing liveness/settings data.
- Create `src/features/routine/routinePresentation.ts` and `.test.ts`: labels and save-state rollback contract for the three routine types.
- Create `src/features/circles/CirclesScreen.tsx` and `.css`: Circles, Community, and Responsibilities composition.
- Create `src/features/circles/circlesPresentation.ts` and `.test.ts`: section order and role/action visibility.
- Create `src/features/me/MeScreen.tsx` and `.css`: Account, Safety Check-in, device, emergency, and preferences sections.
- Create `src/features/me/mePresentation.ts` and `.test.ts`: section order, platform truth, and emergency-feature limits.
- Create `src/features/onboarding/OnboardingFlow.tsx` and `.css`: two-task first-run flow and Ready/Limited result.
- Create `src/features/onboarding/onboardingPresentation.ts` and `.test.ts`: platform-auto-detection and result gating.

### Integration and retirement

- Modify `src/features/relationships/HomeScreen.tsx` and `HomeScreen.css`: retain orchestration/data mutations, delegate rendering to the focused screens, and remove partial spatial/classic branches.
- Modify `src/features/relationships/GroupBoard.tsx` and `GroupBoard.css`: remove `useUiMode` and expose Prototype-compatible status rows.
- Modify `src/features/passive/OnboardingWizard.tsx` and `OnboardingWizard.css`: become a compatibility wrapper around `OnboardingFlow` until callers are fully migrated.
- Modify `src/features/profile/EmergencyInfoCard.tsx`: expose real single-contact/single-address editing inside Prototype cards without faking multi-card persistence.
- Modify `src/lib/i18n.tsx`: add equivalent zh/en copy for new visible labels and states.
- Delete `src/lib/uiMode.ts`: retire the user-facing classic/V2 channel.
- Modify `src/App.viewport.test.ts`, `src/features/relationships/homeContainment.test.ts`, and `src/features/relationships/headerLayout.test.ts`: enforce the new composition and retired selector.

---

### Task 1: Install the Prototype visual foundation

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Modify: `src/main.tsx`
- Modify: `src/index.css`
- Create: `src/features/prototype/PrototypeUI.tsx`
- Create: `src/features/prototype/PrototypeUI.css`
- Test: `src/features/prototype/prototypeUi.contract.test.ts`

**Interfaces:**
- Produces: `PrototypeIcon`, `PrototypeSection`, `PrototypeCard`, `PrototypeRow`, `PrototypeBadge`, `PrototypeDisclosure`, `PrototypeSegmented`, and `PrototypeStatePanel`.
- `PrototypeBadge` consumes `tone: 'ready' | 'limited' | 'unknown' | 'action' | 'danger'`.
- `PrototypeStatePanel` consumes `state: 'loading' | 'empty' | 'limited' | 'unknown' | 'error'` plus an optional retry callback.

- [ ] **Step 1: Write the failing static-render contract**

```tsx
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { PrototypeBadge, PrototypeIcon, PrototypeSection } from './PrototypeUI'

describe('Prototype UI primitives', () => {
  it('renders semantic sections and Material Symbols without inline SVG', () => {
    const html = renderToStaticMarkup(
      <PrototypeSection title="Notifications" subtitle="Recent activity">
        <PrototypeIcon name="notifications" />
        <PrototypeBadge tone="ready">Ready</PrototypeBadge>
      </PrototypeSection>,
    )
    expect(html).toContain('<section')
    expect(html).toContain('material-symbols-rounded')
    expect(html).toContain('prototype-badge--ready')
    expect(html).not.toContain('<svg')
  })
})
```

- [ ] **Step 2: Run the new test and confirm the missing module failure**

Run: `npm test -- src/features/prototype/prototypeUi.contract.test.ts`

Expected: FAIL because `./PrototypeUI` does not exist.

- [ ] **Step 3: Install bundled typography and icon assets**

Run: `npm install @fontsource-variable/plus-jakarta-sans@^5.3.0 @material-symbols/font-400@^0.45.10`

Add to `src/main.tsx` before `./index.css`:

```ts
import '@fontsource-variable/plus-jakarta-sans'
import '@material-symbols/font-400/rounded.css'
```

- [ ] **Step 4: Implement the primitive interfaces**

Use semantic HTML, `aria-labelledby`, native buttons/inputs, and this icon contract:

```tsx
export function PrototypeIcon({ name, label }: { name: string; label?: string }) {
  return (
    <span
      className="material-symbols-rounded prototype-icon"
      aria-hidden={label ? undefined : true}
      aria-label={label}
    >
      {name}
    </span>
  )
}
```

Port the Prototype variables for background, card, text, accent, ready, limited, unknown, action, danger, radii, dividers, and navigation glass into `src/index.css`. Remove duplicated `kc-rise`/`kc-breathe` definitions and the partial `.spatial-v2-*`/`.ui-mode-*` utilities.

- [ ] **Step 5: Run focused and baseline checks**

Run: `npm test -- src/features/prototype/prototypeUi.contract.test.ts && npm run typecheck`

Expected: the focused test and typecheck PASS.

- [ ] **Step 6: Commit the visual foundation**

```bash
git add package.json package-lock.json src/main.tsx src/index.css src/features/prototype
git commit -m "feat(ui): add prototype visual foundation"
```

### Task 2: Build AppShell navigation and SOS interaction

**Files:**
- Create: `src/features/shell/AppShell.tsx`
- Create: `src/features/shell/AppShell.css`
- Create: `src/features/shell/appShellState.ts`
- Test: `src/features/shell/appShellState.test.ts`
- Modify: `src/features/nav/TabBar.tsx`
- Modify: `src/features/nav/TabBar.css`

**Interfaces:**
- Produces `type PrimaryTab = 'watch' | 'routine' | 'circles' | 'me'`.
- Produces `getSosHoldProgress(startedAt: number | null, now: number, holdMs?: number): number`.
- Produces `<AppShell activeTab onTabChange unreadCount isGm sosBusy onSos children />`.
- Consumes the existing `dispatchSos()` callback through `onSos`; AppShell never calls Supabase directly.

- [ ] **Step 1: Write failing state tests**

```ts
import { describe, expect, it } from 'vitest'
import { getSosHoldProgress, isPrimaryTab } from './appShellState'

describe('AppShell state', () => {
  it('accepts only four ordinary tabs', () => {
    expect(isPrimaryTab('watch')).toBe(true)
    expect(isPrimaryTab('gm')).toBe(false)
  })

  it('uses the production 1.4 second SOS hold', () => {
    expect(getSosHoldProgress(1000, 1700)).toBe(50)
    expect(getSosHoldProgress(1000, 2400)).toBe(100)
  })
})
```

- [ ] **Step 2: Confirm the new tests fail**

Run: `npm test -- src/features/shell/appShellState.test.ts`

Expected: FAIL because `appShellState.ts` does not exist.

- [ ] **Step 3: Implement the pure state helpers and shell**

Implement `HOLD_MS = 1400`, clamp progress to `0..100`, reset on pointer release/cancel, and call `onSos` once only after 100%. Use Pointer Events and pointer capture so touch and mouse follow the same release-to-cancel path.

Render tabs in the fixed order Watch, Routine, center SOS, Circles, Me. Render GM only as screen content, never as a tab. Keep `env(safe-area-inset-top)` and `env(safe-area-inset-bottom)` in shell CSS.

- [ ] **Step 4: Run shell tests and existing hold tests**

Run: `npm test -- src/features/shell/appShellState.test.ts src/features/nav/sosHold.test.ts && npm run typecheck`

Expected: both test files and typecheck PASS.

- [ ] **Step 5: Commit shell and navigation**

```bash
git add src/features/shell src/features/nav/TabBar.tsx src/features/nav/TabBar.css
git commit -m "feat(ui): add prototype app shell"
```

### Task 3: Implement Watch with role- and alert-correct actions

**Files:**
- Create: `src/features/watch/watchPresentation.ts`
- Test: `src/features/watch/watchPresentation.test.ts`
- Create: `src/features/watch/WatchScreen.tsx`
- Create: `src/features/watch/WatchScreen.css`
- Modify: `src/features/relationships/GroupBoard.tsx`
- Modify: `src/features/relationships/GroupBoard.css`

**Interfaces:**
- Produces `buildWatchSections(input): WatchSectionKey[]`, where `WatchSectionKey = 'summary' | 'own-task' | 'gm-tools' | 'notifications' | 'people' | 'alert-response'`.
- Produces `getPersonActions({ hasActiveAlert, canManageWardTasks, evidenceQuality }): PersonAction[]`.
- `WatchScreen` consumes real `groups`, `communities`, `isGm`, `unread`, refresh callbacks, and existing domain components/APIs supplied by `HomeScreen`.

- [ ] **Step 1: Write failing Watch contract tests**

```ts
import { describe, expect, it } from 'vitest'
import { buildWatchSections, getPersonActions } from './watchPresentation'

describe('Watch presentation', () => {
  it('puts GM tools above notifications only for GM accounts', () => {
    expect(buildWatchSections({ hasOwnTask: false, isGm: true, hasActiveAlert: false }))
      .toEqual(['summary', 'gm-tools', 'notifications', 'people'])
    expect(buildWatchSections({ hasOwnTask: false, isGm: false, hasActiveAlert: false }))
      .toEqual(['summary', 'notifications', 'people'])
  })

  it('never offers concern in normal, limited, or unknown states', () => {
    for (const evidenceQuality of ['ready', 'limited', 'unknown'] as const) {
      expect(getPersonActions({ hasActiveAlert: false, canManageWardTasks: false, evidenceQuality }))
        .not.toContain('send-concern')
    }
  })

  it('keeps Ward task management separate from concern', () => {
    expect(getPersonActions({ hasActiveAlert: false, canManageWardTasks: true, evidenceQuality: 'ready' }))
      .toEqual(['manage-checkin-task'])
  })
})
```

- [ ] **Step 2: Confirm the Watch tests fail**

Run: `npm test -- src/features/watch/watchPresentation.test.ts`

Expected: FAIL because the presentation module does not exist.

- [ ] **Step 3: Implement Watch ordering and screen composition**

Render major sections strictly from `buildWatchSections`. The GM card calls the existing `GMScreen` destination. Notifications reuse `NotificationsCard`. People reuse real `getGroupActivity`/`GroupBoard` data in Prototype rows with collapsed judgement facts and a disclosure panel for device contribution, privacy, monitoring direction, and authorized Ward task controls.

Do not expose `send-concern` until both `hasActiveAlert` is true and the existing production action already reports eligibility. Do not change the server/RPC rule in this task.

- [ ] **Step 4: Run Watch, relationship, and alert regressions**

Run: `npm test -- src/features/watch/watchPresentation.test.ts src/features/relationships src/features/alerts && npm run typecheck`

Expected: all targeted suites and typecheck PASS.

- [ ] **Step 5: Commit Watch**

```bash
git add src/features/watch src/features/relationships/GroupBoard.tsx src/features/relationships/GroupBoard.css
git commit -m "feat(ui): migrate Watch to prototype layout"
```

### Task 4: Implement Routine including the retained Routine type

**Files:**
- Create: `src/features/routine/routinePresentation.ts`
- Test: `src/features/routine/routinePresentation.test.ts`
- Create: `src/features/routine/RoutineScreen.tsx`
- Create: `src/features/routine/RoutineScreen.css`
- Modify: `src/features/baseline/RoutineSettings.tsx`

**Interfaces:**
- Produces `ROUTINE_TYPE_OPTIONS` keyed by `regular_9to5 | semester_break | shift_irregular`.
- Produces `resolveRoutineSaveState(previous, requested, result): { value; status }` with status `saved | rolled-back`.
- `RoutineScreen` consumes the existing liveness context and `updateRoutineProfileSafe`; it does not duplicate a second client model.

- [ ] **Step 1: Write failing Routine tests**

```ts
import { describe, expect, it } from 'vitest'
import { ROUTINE_TYPE_OPTIONS, resolveRoutineSaveState } from './routinePresentation'

describe('Routine presentation', () => {
  it('keeps exactly the three production routine values', () => {
    expect(ROUTINE_TYPE_OPTIONS.map((item) => item.value)).toEqual([
      'regular_9to5', 'semester_break', 'shift_irregular',
    ])
  })

  it('rolls a failed save back to the last server-confirmed value', () => {
    expect(resolveRoutineSaveState('regular_9to5', 'shift_irregular', false))
      .toEqual({ value: 'regular_9to5', status: 'rolled-back' })
  })
})
```

- [ ] **Step 2: Confirm the Routine tests fail**

Run: `npm test -- src/features/routine/routinePresentation.test.ts`

Expected: FAIL because the presentation module does not exist.

- [ ] **Step 3: Implement Prototype section order and save states**

Render Sleep & Morning Grace, Routine type, Alert Sensitivity, and Timezone & Privacy in that order. Map effective estimates to real `RoutineInsights`/server data. Every control must show dirty, saving, saved, or failed/rolled-back feedback; disable only the affected control while saving.

- [ ] **Step 4: Run Routine and liveness regressions**

Run: `npm test -- src/features/routine/routinePresentation.test.ts src/features/baseline && npm run typecheck`

Expected: all targeted suites and typecheck PASS.

- [ ] **Step 5: Commit Routine**

```bash
git add src/features/routine src/features/baseline/RoutineSettings.tsx
git commit -m "feat(ui): migrate Routine to prototype layout"
```

### Task 5: Implement Circles, Community, and Responsibilities

**Files:**
- Create: `src/features/circles/circlesPresentation.ts`
- Test: `src/features/circles/circlesPresentation.test.ts`
- Create: `src/features/circles/CirclesScreen.tsx`
- Create: `src/features/circles/CirclesScreen.css`

**Interfaces:**
- Produces fixed `CIRCLE_SECTIONS = ['circles', 'community', 'responsibilities']`.
- Produces `getCircleActions({ role, hasCommunity }): CircleAction[]` without conflating Circle membership and Guardian/Ward authority.
- `CirclesScreen` consumes existing create/join/rename/delete/leave/share/QR/scan/direction/community callbacks from `HomeScreen`.

- [ ] **Step 1: Write failing Circles tests**

```ts
import { describe, expect, it } from 'vitest'
import { CIRCLE_SECTIONS, getCircleActions } from './circlesPresentation'

describe('Circles presentation', () => {
  it('uses the approved section order', () => {
    expect(CIRCLE_SECTIONS).toEqual(['circles', 'community', 'responsibilities'])
  })

  it('does not grant Ward task management from membership alone', () => {
    expect(getCircleActions({ role: 'member', hasCommunity: true }))
      .not.toContain('manage-ward-task')
    expect(getCircleActions({ role: 'guardian', hasCommunity: true }))
      .toContain('manage-ward-task')
  })
})
```

- [ ] **Step 2: Confirm the Circles tests fail**

Run: `npm test -- src/features/circles/circlesPresentation.test.ts`

Expected: FAIL because the presentation module does not exist.

- [ ] **Step 3: Implement all real relationship destinations in Prototype cards**

Keep create, invite, share link, QR, scan, members, monitoring direction, sharing direction, leave, community assignment, Guardian/Ward management, rename, delete, and reassignment reachable through Prototype disclosure/dialog patterns. Keep destructive actions separated and confirmed.

- [ ] **Step 4: Run relationship and invite regressions**

Run: `npm test -- src/features/circles/circlesPresentation.test.ts src/features/relationships src/features/tasks src/features/guardians && npm run typecheck`

Expected: all targeted suites and typecheck PASS.

- [ ] **Step 5: Commit Circles**

```bash
git add src/features/circles
git commit -m "feat(ui): migrate Circles to prototype layout"
```

### Task 6: Implement Me without faking unavailable storage

**Files:**
- Create: `src/features/me/mePresentation.ts`
- Test: `src/features/me/mePresentation.test.ts`
- Create: `src/features/me/MeScreen.tsx`
- Create: `src/features/me/MeScreen.css`
- Modify: `src/features/profile/EmergencyInfoCard.tsx`
- Modify: `src/features/update/UpdatesCard.tsx`

**Interfaces:**
- Produces fixed `ME_SECTIONS` for Account, Safety Check-in, This Device, Linked Devices, Emergency Contacts, Emergency Addresses, Emergency GPS, Preferences & Updates.
- Produces `getEmergencyCapabilities({ multiCardApiAvailable, gpsContractResolved })` so unavailable production behavior stays hidden or explicitly limited.
- `MeScreen` consumes user/account callbacks, liveness setup/practice/clear, push/device truth, emergency API, update controls, theme/language, scan sync, sign-out, and account deletion.

- [ ] **Step 1: Write failing Me tests**

```ts
import { describe, expect, it } from 'vitest'
import { getEmergencyCapabilities, ME_SECTIONS } from './mePresentation'

describe('Me presentation', () => {
  it('uses the approved eight-section order', () => {
    expect(ME_SECTIONS).toEqual([
      'account', 'safety-checkin', 'this-device', 'linked-devices',
      'emergency-contacts', 'emergency-addresses', 'emergency-gps', 'preferences-updates',
    ])
  })

  it('does not advertise multi-card or crisis GPS persistence before runtime support', () => {
    expect(getEmergencyCapabilities({ multiCardApiAvailable: false, gpsContractResolved: false }))
      .toEqual({ multiCardEditing: false, crisisGpsPersistence: false })
  })
})
```

- [ ] **Step 2: Confirm the Me tests fail**

Run: `npm test -- src/features/me/mePresentation.test.ts`

Expected: FAIL because the presentation module does not exist.

- [ ] **Step 3: Implement real Me sections and honest emergency limits**

Render current single contact/address records as Prototype cards with the operations the existing API truly supports. Do not display additional local-only cards. Render the Prototype Emergency GPS checkbox disabled with an explicit “Not available until the crisis-sharing privacy contract is approved” explanation while persistence is gated; do not save a fake consent and do not show last-location telemetry.

Remove the UI-style selector. Keep Pattern lifecycle, platform-specific permission repair, linked-device truth, language, theme, version/update, sign-out, and destructive account deletion.

- [ ] **Step 4: Run profile, push, update, and isolation regressions**

Run: `npm test -- src/features/me/mePresentation.test.ts src/features/profile src/features/push src/features/update src/features/pattern && npm run typecheck`

Expected: all targeted suites and typecheck PASS.

- [ ] **Step 5: Commit Me**

```bash
git add src/features/me src/features/profile/EmergencyInfoCard.tsx src/features/update/UpdatesCard.tsx
git commit -m "feat(ui): migrate Me to prototype layout"
```

### Task 7: Replace seven-step onboarding with two user tasks plus result

**Files:**
- Create: `src/features/onboarding/onboardingPresentation.ts`
- Test: `src/features/onboarding/onboardingPresentation.test.ts`
- Create: `src/features/onboarding/OnboardingFlow.tsx`
- Create: `src/features/onboarding/OnboardingFlow.css`
- Modify: `src/features/passive/OnboardingWizard.tsx`
- Modify: `src/features/passive/OnboardingWizard.css`

**Interfaces:**
- Produces `getOnboardingSteps(): ['value', 'phone-setup', 'result']` and `getProgressLabel(step): '1 of 2' | '2 of 2' | null`.
- Produces `resolveSetupResult(capabilities): 'ready' | 'limited' | 'unknown'`; Ready requires authoritative evidence from the current run.
- `OnboardingFlow` consumes real platform detection and native permission refresh functions already used by `OnboardingWizard`.

- [ ] **Step 1: Write failing onboarding tests**

```ts
import { describe, expect, it } from 'vitest'
import { getOnboardingSteps, getProgressLabel, resolveSetupResult } from './onboardingPresentation'

describe('Onboarding presentation', () => {
  it('counts two user tasks and not the result', () => {
    expect(getOnboardingSteps()).toEqual(['value', 'phone-setup', 'result'])
    expect(getProgressLabel('value')).toBe('1 of 2')
    expect(getProgressLabel('phone-setup')).toBe('2 of 2')
    expect(getProgressLabel('result')).toBeNull()
  })

  it('never calls stale or missing evidence Ready', () => {
    expect(resolveSetupResult({ currentRunVerified: false, requiredReady: true, unavailable: false }))
      .toBe('unknown')
    expect(resolveSetupResult({ currentRunVerified: true, requiredReady: false, unavailable: true }))
      .toBe('limited')
  })
})
```

- [ ] **Step 2: Confirm onboarding tests fail**

Run: `npm test -- src/features/onboarding/onboardingPresentation.test.ts`

Expected: FAIL because the presentation module does not exist.

- [ ] **Step 3: Implement the auto-detected two-task flow**

Do not render platform, device-type, global-role, GM, Guardian, or Ward questions. Explain each capability before invoking native permission code. On app resume, refresh authoritative state. Allow completion only to Ready or Limited; Unknown keeps a recovery action. Expose a `mode="repair"` entry for This Device that skips the value introduction.

- [ ] **Step 4: Run onboarding and passive-signal regressions**

Run: `npm test -- src/features/onboarding/onboardingPresentation.test.ts src/features/passive && npm run typecheck`

Expected: all targeted suites and typecheck PASS.

- [ ] **Step 5: Commit onboarding**

```bash
git add src/features/onboarding src/features/passive/OnboardingWizard.tsx src/features/passive/OnboardingWizard.css
git commit -m "feat(ui): simplify onboarding to two tasks"
```

### Task 8: Integrate all screens and retire the mixed UI

**Files:**
- Modify: `src/features/relationships/HomeScreen.tsx`
- Modify: `src/features/relationships/HomeScreen.css`
- Modify: `src/lib/i18n.tsx`
- Delete: `src/lib/uiMode.ts`
- Modify: `src/App.viewport.test.ts`
- Modify: `src/features/relationships/homeContainment.test.ts`
- Modify: `src/features/relationships/headerLayout.test.ts`

**Interfaces:**
- `HomeScreen` remains the production orchestration owner for auth, role resolution, groups/communities, unread notifications, realtime subscriptions, invite handoff, QR/scan, SOS dispatch, and onboarding completion.
- `AppShell` receives only rendered screens and callbacks; screen components receive only domain data/actions required by their visible contract.

- [ ] **Step 1: Replace old contract expectations with failing Prototype expectations**

Add assertions that source contains `AppShell`, `WatchScreen`, `RoutineScreen`, `CirclesScreen`, and `MeScreen`, while excluding `useUiMode`, `ui-mode-switcher`, `spatial-v2-mode`, and a `gm` tab.

```ts
expect(source).toContain('<AppShell')
expect(source).toContain('<WatchScreen')
expect(source).not.toContain('useUiMode')
expect(source).not.toContain('ui-mode-switcher')
```

- [ ] **Step 2: Run the integration contracts and confirm they fail**

Run: `npm test -- src/App.viewport.test.ts src/features/relationships/homeContainment.test.ts src/features/relationships/headerLayout.test.ts`

Expected: FAIL because `HomeScreen` still owns mixed classic/spatial rendering.

- [ ] **Step 3: Recompose HomeScreen and remove user-facing UI mode**

Keep existing effects and mutation callbacks, but replace the monolithic JSX with `AppShell` plus focused screens. Move no Supabase or native behavior into visual primitives. Delete `uiMode.ts` only after all imports are gone. Add exact zh/en strings for every new visible label and state.

- [ ] **Step 4: Run repository-wide mechanical verification**

Run: `npm run typecheck`

Run: `npm test -- --reporter=dot`

Run: `npm run build`

Run: `rg -n "useUiMode|ui-mode-switcher|spatial-v2|<svg|✨|🛡️" src/features/prototype src/features/shell src/features/watch src/features/routine src/features/circles src/features/me src/features/onboarding src/features/relationships/HomeScreen.tsx src/features/relationships/GroupBoard.tsx src/features/nav/TabBar.tsx`

Expected: typecheck, all tests, and build PASS; the final search returns no user-facing mixed-mode code, inline SVG, or emoji icons in the migrated UI.

- [ ] **Step 5: Verify responsive and accessibility contracts locally**

At 360, 375, and 412 px widths, verify Watch, Routine, Circles, Me, Onboarding, and SOS in zh/en and light/dark. Record visible outcomes for clipped labels, horizontal scrolling, 44 px targets, focus order, reduced motion, and safe-area padding. Mark pixel-level comparison blocked until approved Prototype screenshots are available; do not substitute source inspection for visual evidence.

- [ ] **Step 6: Commit integrated migration**

```bash
git add src/features/relationships/HomeScreen.tsx src/features/relationships/HomeScreen.css src/lib/i18n.tsx src/App.viewport.test.ts src/features/relationships/homeContainment.test.ts src/features/relationships/headerLayout.test.ts
git rm src/lib/uiMode.ts
git commit -m "feat(ui): make prototype the only app experience"
```

### Task 9: Build and exercise the Android APK

**Files:**
- Generated only: `dist/**`, `android/app/src/main/assets/public/**`, Android build outputs; do not commit generated artifacts unless the release workflow explicitly requires them.

**Interfaces:**
- Consumes the completed React build and existing Capacitor Android project.
- Produces an installable APK plus device evidence; it changes no production server contract.

- [ ] **Step 1: Build and sync web assets into Android**

Run: `npm run build && npx cap sync android`

Expected: Vite build and Capacitor sync PASS with bundled font/icon assets present in the Android web asset directory.

- [ ] **Step 2: Build a debug APK**

Run: `Push-Location android; .\gradlew.bat assembleDebug; Pop-Location`

Expected: Gradle reports `BUILD SUCCESSFUL` and produces `android/app/build/outputs/apk/debug/app-debug.apk`.

- [ ] **Step 3: Install and run the real user path**

Install on an authorized Android device/emulator, sign in with the shared AI GM account, and exercise: first-run setup, Settings resume, Watch normal/limited/alert states, GM entry above Notifications, Routine type save/rollback, Circles invite/QR/scan, Me Pattern/device/emergency/update actions, and SOS press/release/dispatch states.

- [ ] **Step 4: Capture blocking visual evidence**

For each screen, compare an approved Prototype reference screenshot and APK screenshot together at the same viewport and state. Fix visible differences in typography, spacing, radius, border, icon, color, crop, and safe-area behavior; repeat until no material mismatch remains. If reference screenshots are still unavailable, report the build as functionally verified but visually blocked.

- [ ] **Step 5: Run the final gate and record evidence**

Run: `npm run typecheck && npm test -- --reporter=dot && npm run build`

Expected: every command PASS. Record the APK path/hash, Android device/emulator identity, login account role, exercised scenarios, and visual-comparison status in Brain write-back.

- [ ] **Step 6: Commit only intentional source/test fixes from device verification**

```bash
git add src/index.css src/features/prototype src/features/shell src/features/watch src/features/routine src/features/circles src/features/me src/features/onboarding src/features/relationships src/features/passive src/features/profile src/features/nav src/lib/i18n.tsx
git commit -m "fix(ui): close Android prototype parity gaps"
```

Do not stage unrelated untracked plans, specs, migrations, tests, or generated APK assets.
