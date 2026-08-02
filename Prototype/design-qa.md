# Keep Contact Prototype Design QA

## Comparison target

- Source truth: the current warm glassmorphism prototype plus the approved 2026-08-02 correction that onboarding is for an ordinary user, not a tester.
- Implementation: `Prototype/interactive_prototype.html`.
- Intended viewport: mobile device frame, with prototype-only controls outside the frame.
- Focus of this iteration: first-run value explanation, auto-detected phone setup, Ready/Limited result, and separation of safety-pattern setup.

## Evidence status

- Static source and interaction-contract evidence: available.
- Browser-rendered screenshot and computed-layout evidence: unavailable.
- Visual comparison and interactive focus verification: blocked.

The in-app Browser rejected the local `file://` URL under its URL security policy and prohibited bypassing that restriction through another browser surface or indirect route. No workaround was attempted.

## Static verification evidence

- `node Prototype/prototype.test.mjs`: PASS, 10/10 contract checks.
- The setup dialog contains no persona selector, device/platform selector, or safety-pattern controls.
- Android, iOS native, iOS web app, Ready, and Limited simulations exist only in the prototype toolbar outside the phone frame.
- The user flow is two tasks plus a result: value → phone settings → Ready/Limited.
- Permission labels use user language: Notifications, Phone activity, and Background protection.
- Inline JavaScript parses; element IDs are unique; dialogs are balanced; no inline event-handler attributes are present.

## UX findings addressed

- Removed the global “How do you use Keep Contact?” role choice. Care direction now belongs to each Circle rather than a global identity.
- Removed device choice from onboarding. The phone is described as automatically detected; platform switching is a prototype-only control.
- Removed safety-pattern practice from onboarding. Practice and change actions stay in Me and open their own task.
- Reframed progress from “3 steps” to “Step 1 of 2”, “Step 2 of 2”, then “Setup result”, so the result is not presented as another task.
- Replaced internal permission and verification language with outcomes a user can understand.
- Added honest completion branches: “This phone is ready” and “Protection is limited”, including Fix now and Finish later behavior.

## Remaining QA risk

- [P1] Browser-rendered layout and interaction evidence is unavailable.
  - Impact: clipping, font loading, contrast, focus order, modal behavior, and narrow-screen behavior cannot be certified from source checks alone.
  - Required follow-up: reload the local prototype manually or provide an allowed renderable URL/screenshots, then verify both themes, all three platform scenarios, both result states, keyboard focus, and touch behavior.

## Iteration history

- Baseline: current three-step dialog still asked for a global care role, exposed technical device language, and required pattern practice.
- Contract-first check: 6 onboarding-specific tests failed as expected.
- Implementation: replaced the flow, moved simulators out of the phone frame, and separated the pattern task.
- Final static check: 10/10 contract checks pass.

final result: blocked
