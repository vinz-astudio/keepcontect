# Keep Contact Prototype Design QA

## Comparison target

- Source truth: the current warm glassmorphism prototype plus the approved 2026-08-02 correction that onboarding is for an ordinary user, not a tester.
- Implementation: `Prototype/interactive_prototype.html`.
- Intended viewport: mobile device frame, with prototype-only controls outside the frame.
- Focus of this iteration: production-function coverage, Watch progressive disclosure, first-run setup, relationship/account destinations, truthful failure/degraded states, and manageable emergency information.

## Evidence status

- Static source and interaction-contract evidence: available.
- Browser-rendered screenshot and computed-layout evidence: unavailable.
- Visual comparison and interactive focus verification: blocked.

The in-app Browser rejected the local `file://` URL under its URL security policy and prohibited bypassing that restriction through another browser surface or indirect route. No workaround was attempted.

## Static verification evidence

- `node Prototype/prototype.test.mjs`: PASS, 21/21 contract checks.
- Full `npm test`: 274/275 PASS; only `scripts/local-supabase-replay.test.mjs` exceeded the shared 5 s timeout. Its isolated rerun passed 13/13 in 3.89 s.
- The setup dialog contains no persona selector, device/platform selector, or safety-pattern controls.
- Android, iOS native, iOS web app, readiness, Watch, Routine, invitation, and SOS simulations exist only in the prototype toolbar outside the phone frame.
- The user flow is two tasks plus a result: value → phone settings → Ready/Limited.
- Permission labels use user language: Notifications, Phone activity, and Background protection.
- Watch follows Action summary → conditional top-level Check in → People I watch → Activity History, with three expandable people and decision context visible before expansion.
- Circles and Me retain creation, rename/move, invitation/link/QR, monitoring/sharing direction, responsibility, device, update, push-repair, sign-out, and pattern-management destinations.
- Routine save, readiness, invitations, and SOS include explicit success/degraded/failure or unknown states; no named acknowledgement is fabricated.
- Emergency contacts and saved addresses are separate card collections with Add/Edit/Remove; contacts have exclusive Primary semantics and addresses remain masked until revealed.
- Routine Me shows no last-location list or GPS value. A single current-device checkbox grants purpose-limited Demo consent for crisis-time GPS requests without claiming phone permission or continuous tracking.
- Inline JavaScript parses; element IDs are unique; dialogs are balanced; no inline event-handler attributes are present.

## UX findings addressed

- Removed the global “How do you use Keep Contact?” role choice. Care direction now belongs to each Circle rather than a global identity.
- Removed device choice from onboarding. The phone is described as automatically detected; platform switching is a prototype-only control.
- Removed safety-pattern practice from onboarding. Practice and change actions stay in Me and open their own task.
- Reframed progress from “3 steps” to “Step 1 of 2”, “Step 2 of 2”, then “Setup result”, so the result is not presented as another task.
- Replaced internal permission and verification language with outcomes a user can understand.
- Added honest completion branches: “This phone is ready” and “Protection is limited”, including Fix now and Finish later behavior.
- Restored Watch decision density through progressive disclosure: each collapsed row includes relationship/Circle, state, evidence source/age, coverage, and an applicable action.
- Added first-class alert/action summary, a compact current-user Check in action, and filterable history with loading, error, stale/limited, active-alert, and normal scenarios.
- Restored Circles/Me destinations that were visually absent from the newer concept, while keeping rare actions behind disclosure or dialogs.
- Added invitation handoff outcomes (accepted, invalid, already member, failed), Routine save rollback copy, capability-specific readiness, and evidence-based SOS delivery states.
- Marked simulated private data and state changes as Demo, and reserved destructive visual emphasis for destructive confirmations.
- Replaced the single emergency contact/address values with two manageable card lists. Kept saved addresses explicitly static and moved device location behind a per-current-device crisis consent checkbox; last-location processing remains a backend concern.
- Removed `Ask <name> to check in` from ordinary watched people. Scheduled check-ins now appear only under Mei's explicit Ward responsibility with Add/Edit/Remove controls; a task assigned to the current user becomes one compact Watch-top `Check in` action instead of a detached full-width section.
- Kept `Send concern` out of routine Group-member UI. An active alert now offers Send concern as the false-alarm check while keeping `I'll contact them` available; concern-sent, claimed, and resolved remain distinct states.
- Removed an orphaned duplicate Circles/Community/Responsibilities fragment introduced by a concurrent prototype edit after confirming that the retained redesigned section contained the same destinations. This restored unique IDs without reverting the newer layout.

## Remaining QA risk

- [P1] Browser-rendered layout and interaction evidence is unavailable.
  - Impact: clipping, font loading, contrast, focus order, modal behavior, and narrow-screen behavior cannot be certified from source checks alone.
  - Required follow-up: reload the local prototype manually or provide an allowed renderable URL/screenshots, then verify both themes, all platform and scenario controls, every expanded person, dialogs, keyboard focus, and touch behavior.

## Iteration history

- Baseline: current three-step dialog still asked for a global care role, exposed technical device language, and required pattern practice.
- Contract-first check: 6 onboarding-specific tests failed as expected.
- Implementation: replaced the flow, moved simulators out of the phone frame, and separated the pattern task.
- Final static check: 10/10 contract checks pass.
- Function-parity RED/GREEN cycles: Watch (3 failing checks → pass), Circles/Me (1 → pass), Routine/SOS (2 → pass), invitation handoff (1 → pass), final truth/styling details (2 → pass).
- Current final static check: 18/18 contract checks pass.
- Emergency-information RED/GREEN cycle: contact/address cards and GPS-consent boundary both failed before implementation, then passed after the UI and controller changes.
- Current final static check: 19/19 contract checks pass.
- Watch-action RED/GREEN cycles: persistent routine concern plus missing claimed/resolved states failed first; a second RED proved the alerted person's detail action still needed suppression. Both passed after state-conditioned rendering.
- Current final static check: 20/20 contract checks pass.
- Responsibility/concern correction RED/GREEN cycle: four checks failed for the detached task section, ordinary-member Ask actions, missing alert concern, and missing task/concern-sent states. The new ownership and alert state contract then passed. A later unique-ID failure exposed a concurrent orphaned Circles duplicate; removing only that duplicate restored the contract.
- Current final static check: 21/21 contract checks pass.

final result: static contract passed; browser-rendered visual QA blocked
