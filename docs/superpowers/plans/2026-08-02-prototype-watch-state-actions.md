# Prototype Watch Responsibilities and Concern Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Watch distinguish ordinary Circle membership, Guardian-to-Ward check-in arrangements, the current user's own due task, and alert-only concern.

**Architecture:** Keep the existing single-file prototype and its current visual system. Replace the detached task card with one conditional top action, place scheduled-task management under the one demonstrated Ward, and extend the pure Watch state mapper to drive alert, concern-sent, claimed, resolved, and personal-task states. Use the existing delegated click handler and simple dialog instead of adding routes or dependencies.

**Tech Stack:** HTML, CSS, vanilla JavaScript, Node.js static/behavior contract.

## Global Constraints

- Modify the exact shared file `Prototype/interactive_prototype.html`; the user tests this path directly.
- Ordinary Circle membership exposes no scheduled-task action and no concern action before an alert.
- Only a Guardian-to-Ward responsibility exposes `Check-in arrangement` with add, edit, and remove destinations.
- The current user's due task appears as a compact top-level `Check in` action; no full-width `Check-in tasks` section remains.
- `Send concern` appears only inside an active alert and asks the protected person to disprove a possible false alarm.
- After concern is sent, `I'll contact them` remains available so the concern wait cannot delay urgent human action.
- Limited coverage never implies danger.
- Demo feedback distinguishes server acceptance, notification delivery, self-confirmation, contact claiming, and external confirmation.
- Do not change production React, native code, Supabase, migrations, push delivery, or releases.
- Preserve the existing Warm Linen / Warm Charcoal visual system and accessible control patterns.

---

### Task 1: Lock role ownership and alert-scoped concern with a failing contract

**Files:**
- Modify: `Prototype/prototype.test.mjs`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: the existing HTML string, the Watch screen slice, and the inline-script parser.
- Produces: executable expectations for `getWatchActionState(scenario)` and structural expectations for task ownership.

- [ ] **Step 1: Replace the old Watch ordering test**

Assert the order `watch-action-summary → watch-own-checkin → watch-people-list → activity-history`, while allowing the conditional top action to be hidden. Assert `id="checkin-tasks"` is absent.

- [ ] **Step 2: Replace the old routine action contract**

Extract ordinary members and the Ward separately. Assert ordinary person details lack `ask-checkin`, `send-concern`, `add-checkin-task`, `edit-checkin-task`, and `remove-checkin-task`. Assert only `person-mei` has `data-responsibility="ward"`, `Check-in arrangement`, and the three scheduled-task action destinations.

- [ ] **Step 3: Add scenario and state assertions**

Execute the real pure function and require these exact results:

```js
assert.deepEqual(getWatchActionState('normal'), {
  alertVisible: false, concernVisible: false, claimVisible: false,
  confirmVisible: false, ownTaskVisible: false
});
assert.deepEqual(getWatchActionState('task'), {
  alertVisible: false, concernVisible: false, claimVisible: false,
  confirmVisible: false, ownTaskVisible: true
});
assert.deepEqual(getWatchActionState('alert'), {
  alertVisible: true, concernVisible: true, claimVisible: true,
  confirmVisible: false, ownTaskVisible: false
});
assert.deepEqual(getWatchActionState('concern-sent'), {
  alertVisible: true, concernVisible: false, claimVisible: true,
  confirmVisible: false, ownTaskVisible: false
});
assert.deepEqual(getWatchActionState('claimed'), {
  alertVisible: true, concernVisible: false, claimVisible: false,
  confirmVisible: true, ownTaskVisible: false
});
```

Assert the external toolbar contains `task` and `concern-sent`; the alert response contains `send-concern`, `claim-alert`, and `confirm-safe`; and the routine person cards contain no concern action.

- [ ] **Step 4: Run the contract and verify RED**

Run: `node Prototype/prototype.test.mjs`

Expected: FAIL because `checkin-tasks` still exists, every expanded person still has `ask-checkin`, no Ward arrangement exists, the top Check in action is missing, and alert concern states are absent.

---

### Task 2: Rebuild Watch task placement and responsibility controls

**Files:**
- Modify: `Prototype/interactive_prototype.html`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: existing `button`, `card`, `row`, `person-detail`, `state-feedback`, and delegated `data-action` patterns.
- Produces: `#watch-own-checkin`, `data-responsibility="ward"`, and `add-checkin-task` / `edit-checkin-task` / `remove-checkin-task` destinations.

- [ ] **Step 1: Add the conditional top Check in action**

Insert a compact hidden container after `#watch-action-summary`:

```html
<section class="watch-own-checkin" id="watch-own-checkin" hidden>
  <div>
    <strong class="text-body">Your check-in is due</strong>
    <span class="text-sub">Due now · arranged by Min</span>
  </div>
  <button class="button primary text-body" type="button" data-action="complete-own-checkin">Check in</button>
</section>
```

Remove the complete `#checkin-tasks` card and its empty state, task list, and feedback region.

- [ ] **Step 2: Remove ordinary ad-hoc check-in controls**

Delete all three `ask-checkin` buttons. Min and John retain only monitoring, device, and evidence details.

- [ ] **Step 3: Mark Mei as the demonstrated Ward**

Set `data-responsibility="ward"` on `#person-mei`. Add a `Check-in arrangement` block inside Mei's details with one existing daily task (`Daily · 09:00 · Active`) plus visible `Edit` and `Remove` buttons, followed by `Add task`.

- [ ] **Step 4: Implement responsibility action feedback**

Use the existing simple dialog:

- `add-checkin-task`: explain that the arrangement is created for Mei as the user's Ward, then report Demo creation without claiming server persistence.
- `edit-checkin-task`: explain the daily/interval schedule destination, then report Demo update.
- `remove-checkin-task`: require confirmation before reporting Demo removal.
- `complete-own-checkin`: open the existing safety check-in flow language and report only that the user started their own explicit confirmation.

- [ ] **Step 5: Run the contract**

Run: `node Prototype/prototype.test.mjs`

Expected: responsibility-placement assertions pass; alert-state assertions remain RED until Task 3.

---

### Task 3: Implement alert-only concern and non-blocking escalation

**Files:**
- Modify: `Prototype/interactive_prototype.html`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: `renderWatchScenario(scenario)`, `simulateSimpleDialog()`, `#watch-alert-response`, and `#watch-feedback`.
- Produces: the exact `getWatchActionState(scenario)` return shape from Task 1, plus `send-concern`, `claim-alert`, and `confirm-safe` behavior.

- [ ] **Step 1: Add missing prototype controls and alert buttons**

Add toolbar scenarios `task` and `concern-sent`. Add `#watch-concern-action` before `#watch-claim-action` inside the alert response:

```html
<button class="button ghost text-sub" id="watch-concern-action"
  type="button" data-action="send-concern">Send concern</button>
```

- [ ] **Step 2: Replace the state mapper**

Implement the exact five-field state objects asserted in Task 1. All unlisted states, including `limited`, `resolved`, `loading`, and `error`, hide alert actions and the personal task unless explicitly mapped.

- [ ] **Step 3: Render each alert state truthfully**

- `alert`: copy says a possible false alarm has not been checked; show `Send concern` and `I'll contact them`.
- `concern-sent`: copy says `Concern sent · waiting for Min to confirm`; hide concern and retain `I'll contact them`.
- `claimed`: copy says the current user is contacting Min; show `Confirm safe` only.
- `resolved`: remove the response card and crisis actions.
- `task`: show `#watch-own-checkin`, leave the routine status neutral, and do not imply an alert.

- [ ] **Step 4: Implement concern confirmation**

`send-concern` opens a consequence dialog with:

```text
This asks Min to open Keep Contact and confirm they are safe. It is only available because an alert is active.
```

On confirmation, switch to `concern-sent` and announce only that the demo request was accepted; delivery and self-confirmation remain unknown. `claim-alert` must work from both `alert` and `concern-sent`.

- [ ] **Step 5: Remove obsolete handlers and copy**

Delete `ask-checkin`, `complete-task`, `task-feedback`, `task-list`, and `task-summary-badge` logic. Keep `Send concern` only in the alert response and its confirm-dialog mapping.

- [ ] **Step 6: Run the contract and verify GREEN**

Run: `node Prototype/prototype.test.mjs`

Expected: all checks pass, inline JavaScript parses, IDs remain unique, and every new scenario is present outside the phone frame.

---

### Task 4: Verify and write back the corrected product truth

**Files:**
- Modify: `Prototype/design-qa.md`
- Modify: `Projects/Keep Contact/UX Framework.md`
- Modify: `Experiences/Keep Contact/Dev Log.md`

**Interfaces:**
- Consumes: the completed prototype, targeted contract output, and source inspection.
- Produces: QA and Brain evidence that supersedes the earlier generic manual check-in rule.

- [ ] **Step 1: Run fresh verification**

Run:

```powershell
node Prototype/prototype.test.mjs
git diff --check
```

Strictly decode every changed text file as UTF-8, reject U+FFFD, verify unique IDs and parseable inline JavaScript, and scan the Watch surface to prove concern appears only inside `#watch-alert-response`.

- [ ] **Step 2: Record the corrected rule**

Update QA and Brain truth with:

- scheduled check-ins are Guardian-to-Ward responsibilities;
- the Ward owns task-management placement;
- the current user's assigned task is a compact Watch-top action;
- ordinary membership exposes neither concern nor task assignment;
- active alert exposes concern first without blocking direct contact claiming;
- production remains unchanged and needs a separate governed repair.

- [ ] **Step 3: Preserve the shared visible artifact**

Do not stage or commit the shared untracked `Prototype/` directory automatically. Record the exact changed HTML path and SHA-256, then hand it back for refresh and manual visual inspection because the selected local `file://` browser surface cannot be controlled.
