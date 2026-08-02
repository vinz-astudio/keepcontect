# Keep Contact Interactive Prototype UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a directly testable, safety-truthful revision of the existing Keep Contact single-file mobile prototype.

**Architecture:** Keep the prototype dependency-light and single-page: semantic HTML defines the five product screens and onboarding dialog, CSS preserves the approved warm design system, and one event-driven JavaScript controller manages theme, navigation, disclosures, modal focus, platform simulation, routine saving, and SOS state. A dependency-free Node test enforces the safety, privacy, semantics, and interaction contracts.

**Tech Stack:** HTML5, CSS custom properties, vanilla JavaScript, Node.js built-in test/assert APIs, Google Fonts, Material Symbols Rounded.

## Global Constraints

- Preserve Warm Linen / Warm Charcoal, Fraunces, Hanken Grotesk, rounded mobile framing, and five-tab structure.
- Do not change production application, native, backend, database, migration, or release files.
- Never equate no active alert with proven safety.
- Never display routine raw GPS or offer ordinary liveness GPS attachment.
- Keep preferences, system readiness, and evidence quality separate.
- Platform options are Android native, iOS native, and iOS PWA.
- Important touch targets are at least 44×44 CSS pixels and interactive controls are semantic.
- Browser-policy limitations must be recorded honestly.

---

### Task 1: Lock the prototype contract with a failing source test

**Files:**
- Create: `Prototype/prototype.test.mjs`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: `Prototype/interactive_prototype.html` as UTF-8 text.
- Produces: a dependency-free validation command, `node Prototype/prototype.test.mjs`, with one assertion group per UX contract.

- [ ] **Step 1: Write the failing test**

Use Node `readFileSync` and `node:assert/strict` to require the new navigation labels, onboarding dialog and steps, four readiness states, current-platform cards, evidence-safe headline, SOS progress semantics, accessible disclosure attributes, and reduced-motion CSS. Reject raw coordinate formats, ordinary GPS snapshot controls, inline event-handler attributes, and a `div` SOS control.

- [ ] **Step 2: Run test to verify it fails**

Run: `node Prototype/prototype.test.mjs`

Expected: FAIL because the existing prototype lacks onboarding/readiness contracts and still contains raw GPS and inline event attributes.

### Task 2: Rebuild the source hierarchy while preserving the visual system

**Files:**
- Modify: `Prototype/interactive_prototype.html`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: the existing theme tokens and the approved screen requirements.
- Produces: semantic sections with IDs `home`, `updates`, `routine`, `circles`, and `me`; dialog `setup-dialog`; controls addressable through `data-action` and `data-tab` attributes.

- [ ] **Step 1: Implement the five-screen semantic HTML**

Create conservative Home state layers, privacy-safe Updates, adaptive Routine, explicit Circle/Community hierarchy, and the restructured Me page.

- [ ] **Step 2: Implement responsive warm-theme CSS**

Preserve existing typography, palette, cards, radii, and device frame; raise operational text and touch targets; add focus-visible styling and reduced-motion overrides.

- [ ] **Step 3: Run the contract test**

Run: `node Prototype/prototype.test.mjs`

Expected: remaining failures are limited to interactive controller contracts not yet implemented.

### Task 3: Implement complete prototype interactions

**Files:**
- Modify: `Prototype/interactive_prototype.html`
- Test: `Prototype/prototype.test.mjs`

**Interfaces:**
- Consumes: semantic IDs and data attributes from Task 2.
- Produces: `switchTab`, `setTheme`, `toggleDisclosure`, `openDialog`, `closeDialog`, `renderSetupStep`, `refreshReadiness`, `startVerification`, `completeSetup`, and SOS hold-state behavior.

- [ ] **Step 1: Implement navigation, theme, disclosures, and save feedback**

Use delegated click/change listeners, update ARIA state, preserve the active screen, and display time-bounded success feedback for routine changes.

- [ ] **Step 2: Implement dialog focus and onboarding state machine**

Trap focus, close on Escape, return focus to the opener, allow platform selection and limited-state simulation, baseline the verification timestamp, and prevent a pre-existing event from passing the test.

- [ ] **Step 3: Implement SOS hold/cancel/delivery simulation**

Use pointer and keyboard events on a real button, continuously update `aria-valuenow`, cancel on early release, then show queued, server-accepted, notifying, and acknowledged states.

- [ ] **Step 4: Run the contract test**

Run: `node Prototype/prototype.test.mjs`

Expected: PASS with no warnings.

### Task 4: Verify and document the design artifact

**Files:**
- Create: `Prototype/design-qa.md`
- Modify: `Projects/Keep Contact/UX Framework.md`
- Modify: `Experiences/Keep Contact/Dev Log.md`

**Interfaces:**
- Consumes: final prototype, test output, allowed browser evidence, and current Brain task context.
- Produces: explicit verification evidence, visual QA status, prototype-only truth writeback, and learning review.

- [ ] **Step 1: Inspect scope and encoding**

Run `git diff --check`, inspect `git status --short`, and parse the HTML as UTF-8. Confirm no files outside the exact task write set were mutated.

- [ ] **Step 2: Attempt allowed browser verification**

Use only the in-app Browser surface. If the browser URL policy blocks the local prototype, do not route through another browser or HTTP workaround; record `final result: blocked` with static-test evidence and the named blocker.

- [ ] **Step 3: Write QA and Brain truth notes**

Record the preserved visual system, implemented information architecture, interaction coverage, remaining visual-verification gap, and the fact that the artifact is not production runtime truth.

- [ ] **Step 4: Run final checks and finish the Brain task**

Run `node Prototype/prototype.test.mjs`, `node Coordination/tools/brain-task.mjs check`, update the task evidence with `learning_review`, and finish only if all non-visual requirements pass.

## Plan self-review

- Spec coverage: all approved P0/P1 prototype requirements map to Tasks 1–3; verification and truth writeback map to Task 4.
- Placeholder scan: no TBD, TODO, or deferred implementation instruction remains.
- Interface consistency: HTML IDs/data attributes named in Task 2 are the selectors consumed by Task 3 and asserted by Task 1.
- Execution choice: inline execution is selected because the human explicitly requested direct modification of the named workspace file; no subordinate dispatch is authorized by the active task context.

