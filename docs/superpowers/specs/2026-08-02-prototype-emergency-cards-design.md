# Keep Contact Prototype Emergency Information Cards

**Date:** 2026-08-02  
**Status:** Human-selected design A  
**Scope:** `Prototype/interactive_prototype.html` only; no production data model or disclosure behavior

## Outcome

Replace the prototype's single emergency-contact row and single masked-address block with three visually and semantically separate card groups:

1. Emergency contacts that the user can add, edit, remove, and mark Primary.
2. Saved emergency addresses that the user can add, edit, and remove as static reference places.
3. One simple permission control on the current device that lets the crisis workflow request this device's GPS when emergency information needs to be disclosed.

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

### Current-device emergency GPS permission

- The Me page does not show a list of last device locations; location collection and comparison are background crisis responsibilities.
- The current device exposes one checkbox: allow Keep Contact to request this device's GPS when emergency information needs to be shared.
- Permission is per device because operating-system location authorization and device availability are device-local. A linked device must be configured on that device.
- The checkbox grants purpose-limited app consent; it does not imply the operating-system permission is currently granted or that a location is continuously collected.
- Supporting copy says the location is requested only for an active crisis disclosure, may be unavailable or inaccurate, and does not prove the person is beside the device.

## Crisis Disclosure Contract

- Routine Me-page viewing does not request or display device GPS; saved addresses remain protected.
- When the checkbox is enabled and an active crisis requires emergency-information disclosure, the background workflow may request this device's GPS.
- The crisis payload—not the routine Me page—must qualify each device result with device identity, interaction time, location time, freshness, accuracy, and unavailable/error state.
- Disclosure is limited to authorized Circle responders and verified emergency contacts, not an undefined public community.
- Responders may compare contact coverage, saved reference places, and qualified device results; the system does not automatically assert which device is beside the user.

Production implementation requires a separate privacy/data-model decision covering consent, retention, recipient authorization, revocation, audit logs, stale thresholds, location accuracy, and cross-device identity. This prototype does not authorize runtime collection or disclosure.

## Interaction Model

- A dedicated emergency-item dialog handles contact and address Add/Edit.
- Form title, fields, and confirmation label adapt to the selected item type and mode.
- Prototype contact and address data lives in small in-memory arrays and is re-rendered into semantic list containers.
- Add and edit update the relevant list and announce a Demo result through the existing toast/live-region pattern.
- Remove opens a confirmation dialog, updates only prototype state, and leaves at least one example recoverable on page reload.
- Primary selection is exclusive across contacts; selecting a new Primary demotes the previous one.
- The current-device GPS checkbox updates only Demo consent state and never fabricates a successful location lookup.

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

- Separate containers for emergency contacts and saved addresses, plus one current-device emergency GPS permission control.
- Add/Edit/Remove actions for contacts and addresses.
- Exclusive Primary contact semantics.
- No last-location list or GPS value in the routine Me page.
- Per-device, purpose-limited consent copy that does not claim operating-system permission or continuous tracking.
- Protected-by-default saved addresses and no routine device-position disclosure.
- Active-crisis disclosure limited to authorized responders; background device results remain qualified by time, accuracy, freshness, and uncertainty.
- Parseable inline JavaScript, unique IDs, and balanced dialogs.

## Acceptance Boundary

Acceptance for this task means the local prototype exposes the approved information hierarchy and interactions, backed by source contracts. Browser-rendered layout and touch behavior are accepted only if the selected in-app Browser can control the local file; otherwise the blocker remains explicit. Production React/native/backend/database/release behavior is out of scope.
