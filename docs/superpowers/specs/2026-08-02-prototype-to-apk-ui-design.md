# Keep Contact Prototype-to-APK UI Migration Design

Date: 2026-08-02
Status: approved by the human for implementation on 2026-08-02
Owner: Codex
Task: `KC-PROTOTYPE-TO-APK-UI-001`

## 1. Outcome

Make the Android APK use the visual language, layout, navigation, information hierarchy, and interaction patterns of `Prototype/interactive_prototype.html` as its only user-facing UI.

The existing 0.5.24 UI is not a second design source. It is only a functional inventory used to find production capabilities that the prototype omitted. An old capability returns only when removing it would prevent a real user or GM from completing a necessary task, and only after the human decides whether and where it belongs.

## 2. Approved source hierarchy

When sources disagree, use this order for the UI migration:

1. Human decisions in the 2026-08-02 conversation.
2. `Prototype/interactive_prototype.html` for visual design, layout, navigation, section order, information density, and interaction intent.
3. Accepted Keep Contact business and safety contracts for real data, authorization, privacy, alerts, SOS, and platform behavior.
4. Current React/Capacitor code as the reusable implementation and functional inventory.
5. The 0.5.24 visual structure has no design authority.

The prototype is a design contract, not runtime truth. Demo names, timings, statuses, server results, permissions, device evidence, acknowledgements, and addresses must be replaced by real state or an honest loading, empty, limited, unknown, or error state.

## 3. UX principles

This work implements accepted UX Framework principles P1–P8:

- P1 Calm technology: normal state is quiet; urgency appears only when action is needed.
- P2 Single truth: server state drives cross-device facts; local state drives only current-device facts.
- P3 Crisis zero-learning: SOS and alert actions remain large, immediate, and unambiguous.
- P4 Human language: Chinese is authored first, English is an equivalent translation, and internal terms stay hidden.
- P5 Perceptible privacy: every shared datum explains who may see it and when.
- P6 Role adaptation: care recipient, watcher, Guardian, and GM receive different density and authority.
- P7 Every touch responds: async actions expose pending, success, failure, and recovery.
- P8 Platform truth: Android permissions, safe areas, back behavior, and notification state remain native and honest.

## 4. Visual contract

The production UI must reproduce the prototype rather than the partial `spatial-v2` port already on `main`.

- Use the prototype's Warm Linen light theme and Warm Charcoal dark theme.
- Use the prototype's Plus Jakarta Sans typography, hierarchy, line height, card radii, dividers, badges, spacing, and raised center SOS navigation.
- Bundle production fonts and icon assets so the APK remains correct offline. Do not depend on a Google Fonts request at runtime.
- Use Material Symbols Rounded through a real bundled icon library. Remove new handwritten inline SVG icons, emoji-as-icons, and approximate CSS drawings.
- Preserve Android safe-area and edge-to-edge behavior.
- Minimum touch target is 44 by 44 CSS pixels.
- Support 360/375/412 px widths without clipped labels, compressed actions, or horizontal page scrolling.
- Light and dark themes must preserve WCAG AA text contrast.

The user-facing UI-style switch in Me is removed. The prototype UI is the only user option. A temporary internal rollback flag may render the classic UI during QA or emergency recovery, but it is not shown in the product UI and is removed after the new UI proves stable.

## 5. Information architecture

The four-tab structure is fixed:

1. Watch
2. Routine
3. Center SOS action
4. Circles
5. Me

No fifth ordinary tab is added. GM tools use a role-gated entry inside Watch.

## 6. Screen contracts

### 6.1 Watch

Follow the prototype's exact major order:

1. Status and action summary.
2. Current user's compact due check-in, only when a pending or due assignment exists.
3. GM-only Manager tools entry, only when the authenticated account is a GM.
4. Notifications and timeline filters.
5. Everyone's Status, grouped by Circle and Community.
6. Alert response card when a real alert requires action.

The Manager tools entry is a compact prototype-style card immediately above Notifications. Ordinary accounts do not render it. Selecting it opens the existing GM console as a separate full-screen surface; GM controls and diagnostics do not mix into ordinary Watch rows.

People rows use progressive disclosure. The collapsed row shows only information required to judge state. Device contribution, privacy, monitoring direction, reasoning, and authorized task management live in details.

Guardian-to-Ward task creation, editing, and removal live under that Ward's person details. A task assigned to the current user appears as the compact top check-in action, not as a permanent large Check-in Tasks section.

Normal same-group rows never show Concern. Limited and Unknown are evidence-quality states, not danger states, and do not become red. An active alert may offer Concern and immediate contact coordination only after the production eligibility contract is reconciled as described in Section 11.

### 6.2 Routine

Use the prototype's screen heading, section headers, cards, controls, and final save feedback.

Keep the prototype sections:

1. Sleep & Morning Grace.
2. Alert Sensitivity, including the real current effective estimate.
3. Timezone & Privacy.

Add one human-approved old capability that the prototype omitted:

- A compact prototype-style `Routine type` card directly after Sleep & Morning Grace.
- Values map to the existing `regular_9to5`, `semester_break`, and `shift_irregular` production contract.
- User-facing labels describe ordinary routine, looser/holiday routine, and shift/irregular routine without exposing internal model vocabulary.

Do not restore the old Routine layout or duplicate insight cards. Existing production insight and model state supply the prototype's effective-estimate and supporting copy.

Save behavior must cover dirty, saving, saved, failed, and rollback states. A failed save restores the last server-confirmed value and explains the next action.

### 6.3 Circles

Use the prototype's three sections and order:

1. Circles.
2. Community.
3. Responsibilities.

The card and disclosure designs come from the prototype. Existing production functions are connected only where the prototype provides an appropriate destination: create, invite, share link, QR, scan, view members, monitoring direction, sharing direction, leave, community assignment, and Guardian/Ward management.

Low-frequency rename, delete, and reassignment actions may remain inside details or confirmation dialogs. They must not recreate the old dashboard layout.

Guardian/Ward responsibilities remain distinct from Circle membership and emergency contacts. Only Guardian authority permits Ward check-in task management.

### 6.4 Me

Use the prototype sections and order:

1. Account.
2. Safety Check-in.
3. This Device.
4. Linked Devices.
5. Emergency Contacts.
6. Emergency Addresses.
7. Emergency GPS.
8. Preferences & Updates.

Account actions include link device and sign out. Safety Check-in includes practice, change, and clear with the existing account-isolated Pattern lifecycle. This Device renders current-platform permission and readiness truth, including repair actions. Linked Devices uses real client records and never merges device readiness into one account-wide Ready badge.

Preferences & Updates owns language, theme, version, update check, and destructive account deletion. It does not contain a UI-style selector.

Emergency Contacts and Emergency Addresses use Add/Edit/Remove cards. Production currently has only one contact and one address row, so multi-card persistence is not implemented as fake local UI. It requires an authorized data migration phase.

Emergency GPS presents the prototype's current-device crisis consent checkbox. It does not show last-location telemetry and does not imply continuous tracking or OS permission.

### 6.5 Onboarding

Use the prototype flow:

1. Value explanation.
2. Automatically detected current-phone setup.
3. Honest Ready or Limited result.

The progress label counts two user tasks; the result is not another user task. Users never choose a platform, device type, or global care role. Android capabilities are requested and refreshed through real native calls. Verification mechanics stay internal. A result may be Ready only when the current run has authoritative evidence; otherwise use Limited or Unknown with a recovery action.

The setup can be resumed from This Device in Me without replaying the value introduction.

### 6.6 SOS

Keep the prototype's raised center button and full-screen hold feedback. Preserve the production 1.4-second hold contract, release-to-cancel behavior, and current dispatch API.

Show server receipt, notification delivery, responder acknowledgement, failure, and retry as separate facts. Never infer delivery or human acknowledgement from server acceptance.

## 7. Necessary old capabilities retained

Only two old-UI capabilities were approved for explicit return:

1. Routine type, as the compact Routine card described above.
2. GM Manager tools, as the role-only Watch entry above Notifications.

All other old sections are removed when their necessary function already has a prototype destination. The classic visual hierarchy, dual-column dashboard, permanent Check-in Tasks card, Profile mega-card, and user-facing UI channel selector do not return.

If later implementation finds another old-only capability whose removal blocks a real task, stop and ask the human whether to keep it and where it belongs. Do not insert it automatically.

## 8. Component architecture

Split the current monolithic `HomeScreen` into clear UI boundaries while reusing established APIs and providers:

- `AppShell`: header, tab state, bottom navigation, SOS, overlays, and global toasts.
- `WatchScreen`: Watch composition only.
- `RoutineScreen`: Routine composition only.
- `CirclesScreen`: Circle/Community/Responsibility composition only.
- `MeScreen`: account, device, emergency, and preferences composition only.
- `OnboardingFlow`: first-run setup only.
- Shared prototype primitives: section header, card, row, badge, segmented control, disclosure, feedback, dialog, and empty/error state.

Data-loading and mutation hooks remain near their domains. Shared visual primitives do not call Supabase or native plugins directly. Screen components compose domain state into the prototype layout.

Do not rewrite business APIs merely to fit the new DOM. Do not move unrelated alert, push, auth, or passive-signal logic during visual extraction.

## 9. State and error contract

Every networked or native-backed surface supports the states it can actually enter:

- loading
- loaded
- empty
- limited or unknown
- permission denied or unavailable
- saving or submitting
- success with an authoritative receipt
- recoverable failure with retry
- terminal failure with a clear next action

Optimistic updates are allowed only when failure restores the last confirmed state. Destructive actions require confirmation and expose progress and failure. Red appears only with an immediate required action.

## 10. Migration and rollout

Implementation order:

1. Shared visual tokens, bundled typography/icons, AppShell, navigation, and hidden rollback flag.
2. Watch.
3. Routine, including Routine type.
4. Circles.
5. Me.
6. Onboarding.
7. Cross-screen accessibility, localization, and state polish.
8. Android build, sync, install, login, permission, and device regression.

Each phase must be independently testable. Do not release a state in which only Watch uses the prototype while the other main tabs retain the old visual system.

The production release occurs only after all four ordinary tabs and onboarding share the new system. Internal development checkpoints may land earlier behind the hidden rollback flag.

## 11. Conflicts and governance gates

### 11.1 Concern eligibility

`Projects/Keep Contact/UX Framework.md` records the human decision that Concern appears only after an active alert and remains alongside immediate contact coordination. `Projects/Keep Contact/Keep Contact.md` still says Concern should close after the group stage.

`[CONFLICT]` The visual migration may build the alert response surface, but it must not change production Concern eligibility or server authorization until a separate High-risk task formally reconciles the contract and an accepted ADR records the result.

### 11.2 Emergency GPS scope

The approved prototype and the later UX Framework correction specify a single current-device consent for requesting GPS when emergency information must be shared during an active crisis. ADR-0036 also contains language about optionally attaching GPS to every liveness ping.

`[CONFLICT]` The screen design follows the approved prototype's crisis-only checkbox. Persistence and signal behavior must not be changed until the accepted ADR text and later human correction are reconciled in a separate governed task.

### 11.3 Emergency multi-card storage

ADR-0036 authorizes separate multi-card contacts and addresses, but current production storage exposes a single contact and a single home address. The frontend may be styled only after the production schema/API phase provides real add, edit, remove, ordering, and authorization semantics.

## 12. Verification contract

### Mechanical

- TDD for state visibility, action eligibility, and screen composition.
- Existing TypeScript, Vitest, build, security, and contract tests remain green.
- No missing i18n keys, duplicate IDs, inline SVG additions, or unresolved icon glyphs.
- Touch targets, contrast, focus order, reduced motion, and safe-area checks.

### Scenario

- Authenticated normal, limited, alert, loading, error, and empty Watch states.
- Current-user due check-in; Guardian Ward task add/edit/remove; ordinary member has no task authority.
- Concern/claim/confirm-safe states only after the production contract gate.
- Routine load, change, save, failure rollback, and all three Routine types.
- Circle create/join/share/QR/scan/leave, monitoring direction, Community, Guardian/Ward management.
- Me Pattern lifecycle, device repair, linked-device truth, emergency cards, updates, sign out, and delete.
- Android first-run permission flow, resume from Settings, Ready/Limited outcome, and setup repair.
- SOS press feedback, hold progress, cancellation, server receipt, degraded delivery, and failure.

### Visual and device

- Compare reference and implementation in the same viewport and state for 360, 375, and 412 px widths.
- Verify Chinese and English, light and dark themes, keyboard focus, large text pressure, Android status/navigation bars, and back behavior.
- Install an Android debug/release candidate, log in with the shared AI GM account where authorized, and exercise real data and permissions.

The in-app Browser cannot inspect the local `file://` reference under browser security policy. A screenshot of the approved prototype states is therefore required for blocking pixel-level design QA. Source inspection and automated tests cannot be reported as visual verification.

## 13. Success criteria

The migration is complete only when:

- APK users see one coherent prototype-derived design across Watch, Routine, Circles, Me, Onboarding, and SOS.
- The user-facing classic/new UI selector is gone.
- The only approved old-only additions are Routine type and the role-gated GM entry in their approved locations.
- Real production functions remain reachable through prototype-native layouts without restoring old sections.
- No Demo state is presented as runtime truth.
- All governance conflicts are resolved or the affected production action remains blocked.
- Automated, visual, and Android device evidence all pass.
