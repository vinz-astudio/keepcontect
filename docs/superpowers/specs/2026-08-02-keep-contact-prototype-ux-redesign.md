# Keep Contact Interactive Prototype UX Redesign

## Status and approval

Approved by the human on 2026-08-02 through the instruction to apply the previously presented integrated UX recommendations directly to `Prototype/interactive_prototype.html`.

## Goal

Turn the existing Warm Linen / Warm Charcoal single-file mobile prototype into a directly testable product-flow prototype that represents safety status conservatively, distinguishes user preferences from real device readiness, and treats Android native, iOS native, and iOS PWA capabilities truthfully.

## Scope

Modify only the design prototype and its verification/supporting documents. Do not alter production React, native Android/iOS, backend, database, migration, or release code.

## Visual target

Preserve the existing visual system:

- Warm Linen light theme and Warm Charcoal dark theme.
- Fraunces display headings and Hanken Grotesk body copy.
- Rounded 390px mobile device frame, calm cards, restrained shadows, and warm semantic colors.
- Five-tab mobile information architecture.

Replace custom inline SVG icons with a freely available rounded icon library. Do not introduce new illustration art or change the established visual direction.

## Product-state model

The UI must keep three truths separate:

1. People state: active alerts and people requiring attention.
2. Device readiness: whether the current device can provide promised evidence.
3. Evidence quality: recency, source, and coverage limitations.

`No active alerts` must never be presented as proof that everybody is safe. Supported statuses are `Ready`, `Limited`, `Needs action`, and `Unknown`.

## Navigation and screens

Use five immediately understandable tabs: Home, Updates, Routine, Circles, and Me.

### Home

- Lead with `No active alerts`, the latest trusted evidence time, and coverage qualifier.
- Present separate `People I watch`, `Me`, and `This device` sections.
- Surface a device-readiness repair CTA.
- Keep progressive disclosure for evidence details.
- Provide an accessible SOS press-and-hold control with visible progress, release-to-cancel behavior, and truthful delivery states.

### Updates

- Use human-readable activity events rather than technical ping terminology.
- Distinguish routine evidence, limited coverage, warnings, and crisis actions.
- Do not display raw coordinates or attach routine GPS snapshots.
- Explain that exact location is available only during an authorized active crisis.

### Routine

- Keep sleep window, sensitivity, and timezone together.
- Describe sensitivity by consequence rather than hard-coded fixed thresholds.
- Show the current effective estimate as adaptive.
- Explain the post-wake grace period.
- Provide visible save confirmation.

### Circles

- Define Circle as a small reciprocal trusted group and Community as a broader escalation network.
- Expose monitoring direction and information visibility.
- Keep member import and invitation actions interactive.

### Me

Order sections as Account and care role; Safety check-in and pattern; This device readiness; What this device monitors; Emergency contacts; Crisis location and privacy consent; Other devices; Appearance and account actions.

Preferences must not appear as permission/readiness claims. Current-platform readiness must be authoritative and read-only, with repair actions. Home address and gate details remain masked until explicitly revealed.

## Onboarding

Add an interactive first-run setup experience accessible from the prototype toolbar and Me. It must cover:

1. Care role and low-interruption promise.
2. Platform selection for Android native, iOS native, or iOS PWA.
3. Permission explanation before simulated system action.
4. Authoritative readiness refresh after returning from settings.
5. A verification ping that only succeeds after the test starts.
6. Pattern setup/practice.
7. Honest completion as `Ready` or `Limited`.

The prototype must allow denied/limited states to be explored without falsely completing as fully ready.

## Interaction and accessibility

- Use semantic buttons for all actions and expanders.
- Maintain `aria-current`, `aria-selected`, `aria-expanded`, `aria-pressed`, and progress values where applicable.
- Dialogs need `role=dialog`, `aria-modal`, an accessible title, Escape close, focus containment, and focus return.
- All important touch targets must be at least 44×44 CSS pixels.
- Visible text must remain readable for older adults; avoid sub-12px operational labels.
- Respect `prefers-reduced-motion`.
- Every input/select must have an associated label.
- Theme, navigation, disclosure, modal, onboarding, routine save, platform simulation, and SOS states must be directly testable without backend dependencies.

## Verification

- Run the dependency-free Node source-contract test before and after implementation.
- Verify all required product language and state boundaries exist.
- Verify forbidden raw-GPS strings, inline event attributes, and non-semantic SOS/expand controls are absent.
- Run browser interaction and visual QA only on an allowed browser surface. If browser policy blocks the local source, record the exact limitation rather than claiming visual verification.

## Out of scope

- Authentication, persistence, APIs, push delivery, real operating-system permission changes, real GPS, production telemetry, and production UI integration.
- Changing accepted production information architecture or runtime behavior. Prototype findings require a later implementation task before reaching the app.

