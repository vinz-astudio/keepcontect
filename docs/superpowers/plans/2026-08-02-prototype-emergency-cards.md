# Prototype Emergency Information Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype's single emergency contact/address values with manageable contact and saved-address cards, plus one purpose-limited GPS consent checkbox for the current device.

**Architecture:** Keep the existing single HTML/CSS/JavaScript prototype. Store Demo contacts and addresses in two in-memory arrays, render them into semantic list containers, and use one adaptive dialog for Add/Edit plus the existing confirmation dialog for Remove. GPS remains a per-current-device consent flag only; no routine last-location list or fabricated GPS result is rendered.

**Tech Stack:** HTML5, CSS custom properties, vanilla JavaScript, Node.js built-in `assert`/`fs`, existing Material Symbols Rounded.

## Global Constraints

- Preserve the current warm frosted-glass, DM Sans/Nunito visual system.
- Emergency contacts support Add, Edit, Remove, and exactly one Primary when contacts exist.
- Saved emergency addresses support Add, Edit, Remove, and per-card Reveal/Hide; they never claim to be current GPS.
- The routine Me page shows no last-location list and no GPS value.
- GPS consent is per current device, purpose-limited to active-crisis emergency-information disclosure, and does not claim operating-system permission or continuous tracking.
- Simulated mutations and state feedback are labelled Demo.
- Production React, native, backend, database, migration, consent, retention, disclosure, and release behavior are out of scope.

---

### Task 1: Lock emergency information contracts

**Files:**
- Modify: `Prototype/prototype.test.mjs`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: `Prototype/interactive_prototype.html` as UTF-8.
- Produces: source contracts for section IDs, action names, controller names, privacy copy, and the absence of a routine last-location list.

- [x] **Step 1: Add a failing contact/address card contract**

Add this check to `checks`:

```js
['manages emergency contacts and saved addresses as separate cards', () => {
  for (const id of ['emergency-contacts-list', 'emergency-addresses-list', 'emergency-item-dialog']) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
  for (const action of [
    'add-emergency-contact', 'edit-emergency-contact', 'remove-emergency-contact',
    'add-emergency-address', 'edit-emergency-address', 'remove-emergency-address',
    'toggle-emergency-address'
  ]) assert.match(html, new RegExp(`data-action="${action}"`));
  for (const name of ['renderEmergencyContacts', 'renderEmergencyAddresses', 'openEmergencyItemDialog', 'saveEmergencyItem', 'requestEmergencyRemoval']) {
    assert.match(html, new RegExp(`function\\s+${name}\\s*\\(`));
  }
  assert.match(html, /Primary/);
  assert.match(html, /Static reference address/);
}],
```

- [x] **Step 2: Add a failing GPS-consent boundary contract**

```js
['keeps device GPS behind one purpose-limited current-device consent', () => {
  assert.match(html, /id="allow-emergency-gps"/);
  assert.match(html, /current device/i);
  assert.match(html, /active crisis/i);
  assert.match(html, /does not grant (?:the )?phone location permission/i);
  assert.doesNotMatch(html, /id="device-last-locations"|Last GPS|last device locations/i);
}],
```

- [x] **Step 3: Run the prototype test and verify RED**

Run: `node Prototype/prototype.test.mjs`

Expected: the two new checks fail because the current prototype has one contact row, one address block, no adaptive item dialog, and the old location-sharing checkbox.

- [x] **Step 4: Record the two failing check names in Brain task evidence**

Use `brain-task update`; do not edit generated Task Context or Active Work files.

---

### Task 2: Implement card collections and Add/Edit/Remove

**Files:**
- Modify: `Prototype/interactive_prototype.html`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: existing `.card`, `.row`, `.button`, `.badge`, `.field`, dialog, toast, and delegated `data-action` patterns.
- Produces: `emergencyContacts`, `emergencyAddresses`, `renderEmergencyContacts()`, `renderEmergencyAddresses()`, `openEmergencyItemDialog(kind, mode, id, opener)`, `saveEmergencyItem()`, and `requestEmergencyRemoval(kind, id, opener)`.

- [x] **Step 1: Add nested item-card styling**

Add narrowly scoped styles:

```css
.emergency-list { display: grid; gap: 10px; }
.emergency-item { padding: 12px; border: 1px solid var(--line); border-radius: 16px; background: var(--surface-2); }
.emergency-item-head, .emergency-item-actions { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.emergency-item-actions { justify-content: flex-end; margin-top: 10px; }
.emergency-item p { margin: 4px 0 0; }
```

- [x] **Step 2: Replace the current emergency contact/address markup**

Use two parent cards:

```html
<section class="card" aria-labelledby="contacts-title">
  <div class="card-header"><h2 class="card-title text-caption" id="contacts-title">Emergency contacts</h2><button class="button ghost text-body" type="button" data-action="add-emergency-contact">Add contact</button></div>
  <div class="emergency-list" id="emergency-contacts-list" aria-live="polite"></div>
</section>
<section class="card" aria-labelledby="addresses-title">
  <div class="card-header"><h2 class="card-title text-caption" id="addresses-title">Saved emergency addresses</h2><button class="button ghost text-body" type="button" data-action="add-emergency-address">Add address</button></div>
  <p class="supporting text-sub">Static reference addresses — not your current GPS.</p>
  <div class="emergency-list" id="emergency-addresses-list" aria-live="polite"></div>
</section>
```

- [x] **Step 3: Add the adaptive Add/Edit dialog**

Create `#emergency-item-dialog` with a form, shared label input, contact-only relationship/phone/Primary fields, address-only street/access-note fields, Cancel, and `#emergency-item-submit`. Every field has a visible `<label>`.

- [x] **Step 4: Add Demo collections and safe rendering**

Define:

```js
let emergencyContacts = [
  { id: 'min', name: 'Min', relationship: 'Daughter', phone: '+1 ••• ••• 0148', verified: true, receivesCrisis: true, primary: true },
  { id: 'john', name: 'John', relationship: 'Neighbour', phone: '+1 ••• ••• 8831', verified: true, receivesCrisis: true, primary: false }
];
let emergencyAddresses = [
  { id: 'home', label: 'Home', address: '1234 Warm Street', note: 'Gate code 2058', revealed: false },
  { id: 'office', label: 'Office', address: '8 Garden Square', note: 'Reception until 18:00', revealed: false }
];
let emergencyEditor = { kind: null, mode: null, id: null, opener: null };
```

Use an `escapeHtml(value)` helper before inserting user-edited values into `innerHTML`. Render each contact with Primary/Backup, verification, crisis-notification state, Edit, and Remove. Render each address with `Static reference address`, masked or revealed values, Reveal/Hide, Edit, and Remove.

- [x] **Step 5: Implement Add/Edit and exclusive Primary**

`openEmergencyItemDialog()` configures dialog title/fields and preloads edit values. `saveEmergencyItem()` validates required visible fields, adds or replaces one item, and when a saved contact is Primary runs:

```js
emergencyContacts.forEach((contact) => { contact.primary = contact.id === saved.id; });
```

If the first contact is added to an empty list, make it Primary automatically. Re-render, close the dialog, and announce `Demo contact saved.` or `Demo address saved.`.

- [x] **Step 6: Implement Remove confirmation and address reveal**

`requestEmergencyRemoval()` stores `{ kind, id }`, opens the existing confirmation dialog, names the exact item, and uses destructive styling. Confirmation removes only the selected Demo item; if the Primary contact is removed and contacts remain, promote the first remaining contact. `toggle-emergency-address` changes only `revealed` and re-renders.

- [x] **Step 7: Route delegated click and submit events**

Extend the existing click handler for all seven new action names. Add one form `submit` handler that calls `saveEmergencyItem()` and keeps native validation behavior.

- [x] **Step 8: Run the prototype test and verify the card contract GREEN**

Run: `node Prototype/prototype.test.mjs`

Expected: the contact/address contract passes; the GPS boundary remains RED until Task 3.

---

### Task 3: Replace routine location UI with current-device GPS consent

**Files:**
- Modify: `Prototype/interactive_prototype.html`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: existing `.check-row`, current-device wording, toast/live-region feedback.
- Produces: `#allow-emergency-gps` and `#emergency-gps-feedback`; no GPS value or last-location list.

- [x] **Step 1: Add the purpose-limited consent card**

Place after saved addresses:

```html
<section class="card" aria-labelledby="emergency-gps-title">
  <div class="card-header"><h2 class="card-title text-caption" id="emergency-gps-title">Emergency GPS · this device</h2><span class="badge unknown text-caption">Device setting</span></div>
  <div class="check-row"><input id="allow-emergency-gps" type="checkbox"><label for="allow-emergency-gps"><strong class="text-body">Allow this device's GPS when emergency information must be shared</strong><small class="text-sub">Only during an active crisis, for authorized Circle responders and verified emergency contacts. This does not grant the phone location permission or track you continuously.</small></label></div>
  <p class="state-feedback text-sub" id="emergency-gps-feedback" role="status" aria-live="polite">Off on this device.</p>
</section>
```

- [x] **Step 2: Remove the old reveal-location value and sharing checkbox**

Delete `#location-value`, `data-action="reveal-location"`, and `#crisis-location`; remove the `reveal-location` click branch. Do not add a GPS display or last-location card.

- [x] **Step 3: Add truthful checkbox feedback**

On change, set feedback to either:

```js
'Demo consent on for this device. The phone may still require location permission during a crisis.'
'Off on this device. Keep Contact will not request this device GPS for crisis disclosure.'
```

Do not claim a location was acquired or shared.

- [x] **Step 4: Run the complete prototype test and verify GREEN**

Run: `node Prototype/prototype.test.mjs`

Expected: all prior contracts and both new emergency-information contracts pass.

---

### Task 4: Verify, document, and close the prototype slice

**Files:**
- Modify: `Prototype/design-qa.md`
- Modify: `Projects/Keep Contact/UX Framework.md`
- Modify: `Experiences/Keep Contact/Dev Log.md`

**Interfaces:**
- Consumes: final HTML, RED/GREEN output, repository diff, and selected in-app Browser capability.
- Produces: honest QA evidence, project UX truth, and a prototype-only implementation record.

- [x] **Step 1: Run fresh mechanical verification**

Run:

```powershell
node Prototype/prototype.test.mjs
git diff --check
node "C:\Users\vizen\Desktop\Obsidian Brain\2nd Brain\Coordination\tools\brain-task.mjs" check
```

- [x] **Step 2: Inspect source boundaries**

Confirm strict UTF-8 decoding, no U+FFFD, one parseable inline script, unique IDs, balanced dialogs, no routine GPS value/list, and all simulated mutations labelled Demo.

- [x] **Step 3: Attempt selected Browser verification without workaround**

Reload and exercise Add/Edit/Remove, Primary transfer, address Reveal/Hide, and GPS checkbox only if the in-app Browser can control the local file. If its `file://` policy blocks control, record that exact boundary and do not use another browser or an HTTP workaround.

- [x] **Step 4: Write QA and Brain truth**

Append signed entries explaining the three-layer model now exposed to the user: contact cards, saved-address cards, and per-current-device GPS consent; record that last-location processing remains a production backend/privacy follow-up.

- [x] **Step 5: Record evidence and finish the Brain task**

Add RED/GREEN verification, write-back, first-principles verification, `learning_review`, and the Manager-direct ledger exemption through `brain-task update`; run `brain-task pending` and `brain-task check`; finish only if all non-visual requirements pass.

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 cover both manageable card collections, Primary semantics, masking, dialogs, validation, and Demo feedback. Task 3 covers the corrected current-device-only GPS consent and rejects a routine last-location UI. Task 4 covers privacy/source verification, browser evidence boundaries, and Brain write-back.
- **Placeholder scan:** No TBD, TODO, “implement later”, generic error-handling instruction, or undefined behavior remains.
- **Interface consistency:** IDs, action names, array names, render functions, editor state, and feedback strings are defined once and consumed with identical spelling.
- **Scope:** The plan changes only the approved prototype slice and documentation. Multi-device GPS collection, crisis payloads, authorization, retention, and production UI remain a separately governed follow-up.
