# Keep Contact Prototype Emergency Information Cards

**Date:** 2026-08-02  
**Status:** Human-selected design A  
**Scope:** `Prototype/interactive_prototype.html` only; no production data model or disclosure behavior

## Outcome

Replace the prototype's single emergency-contact row and single masked-address block with three visually and semantically separate card groups:

1. Emergency contacts that the user can add, edit, remove, and mark Primary.
2. Saved emergency addresses that the user can add, edit, and remove as static reference places.
3. Per-device last locations that are read-only evidence, qualified by time, freshness, accuracy, and uncertainty.

The design must never present a saved address as the user's current location or imply that a device location proves the user is beside that device.

## Information Architecture

### Emergency contacts

- Section header has `Add contact`.
- Each contact is a compact item card with name, relationship, verified channel, crisis-notification status, and Primary/Backup badge.
- Each item exposes `Edit` and `Remove`.
- Editing permits changing name, relationship, phone, crisis-notification opt-in, and Primary status.
- Removing the Primary contact requires a destructive confirmation and explains that another contact should be promoted.
- The prototype starts with two realistic contacts so multiple-contact behavior is visible.

### Saved emergency addresses

- Section header has `Add address`.
- Each item is a card with a user label such as Home or Office, a masked address summary, optional access note, and `Edit` / `Remove`.
- Saved addresses do not have Primary status and never receive Fresh/Stale badges.
- Address details remain masked until the user explicitly reveals them in the prototype.
- Add/edit fields are label, street address, and access note. Remove uses a destructive confirmation.

### Device last locations

- This is a separate read-only section; it has no Add, Edit, or Remove actions.
- Cards are sorted by most recent credible interaction.
- Each card shows device name, platform, last interaction time, last location time, accuracy, and Fresh/Stale/Unavailable.
- Coordinates or street-level detail remain masked outside an active crisis demo.
- Copy explicitly says: this is the device's last reported position, not proof of the person's location.

## Crisis Disclosure Contract

- Routine Me-page viewing keeps device locations and saved addresses protected.
- Prototype disclosure is labelled Demo and framed as an active-crisis view.
- Disclosure copy names the audience as authorized Circle responders and verified emergency contacts, not an undefined public community.
- Responders compare contact coverage, saved reference places, device freshness, and accuracy before choosing where to send help.
- The UI does not automatically recommend a device or claim the user is at a location.

Production implementation requires a separate privacy/data-model decision covering consent, retention, recipient authorization, revocation, audit logs, stale thresholds, location accuracy, and cross-device identity. This prototype does not authorize runtime collection or disclosure.

## Interaction Model

- A dedicated emergency-item dialog handles contact and address Add/Edit.
- Form title, fields, and confirmation label adapt to the selected item type and mode.
- Prototype data lives in small in-memory arrays and is re-rendered into semantic list containers.
- Add and edit update the relevant list and announce a Demo result through the existing toast/live-region pattern.
- Remove opens a confirmation dialog, updates only prototype state, and leaves at least one example recoverable on page reload.
- Primary selection is exclusive across contacts; selecting a new Primary demotes the previous one.
- Device-location cards are rendered from a fixed prototype scenario model and cannot be mutated by user controls.

## Visual System

- Preserve the current warm frosted-glass, DM Sans/Nunito system.
- Use nested item cards with existing line, surface, radius, button, badge, and spacing tokens.
- Keep Add at section-header level; place Edit/Remove at the bottom of each item card so ownership is unambiguous.
- Destructive red emphasis is reserved for the confirmation action, not the ordinary card surface.

## Accessibility and Privacy

- Lists use labelled sections and semantic buttons.
- Dialog fields have visible labels; status changes use the existing live-region/toast feedback.
- Remove confirmations name the exact item.
- Masked values remain text, not inaccessible visual placeholders.
- Freshness and accuracy are written in text and never encoded by color alone.

## Contract Tests

The dependency-free prototype test must fail before implementation and then require:

- Separate containers for emergency contacts, saved addresses, and device last locations.
- Add/Edit/Remove actions for contacts and addresses.
- Exclusive Primary contact semantics.
- No mutation actions on device-location cards.
- Device name, interaction time, location time, accuracy, freshness, and uncertainty copy.
- Protected-by-default saved addresses and device positions.
- Active-crisis disclosure limited to authorized responders and labelled Demo.
- Parseable inline JavaScript, unique IDs, and balanced dialogs.

## Acceptance Boundary

Acceptance for this task means the local prototype exposes the approved information hierarchy and interactions, backed by source contracts. Browser-rendered layout and touch behavior are accepted only if the selected in-app Browser can control the local file; otherwise the blocker remains explicit. Production React/native/backend/database/release behavior is out of scope.
