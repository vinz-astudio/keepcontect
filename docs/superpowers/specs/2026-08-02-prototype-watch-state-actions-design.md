# Prototype Watch State-Conditioned Actions

Date: 2026-08-02  
Task: `KC-PROTOTYPE-WATCH-ACTIONS-001`

## Problem

`Send concern` currently appears as a routine action on every `People I watch` card. That presentation is false to the product contract: `send_concern` starts or strengthens a real safety alert, requires the subject to unlock and check in, and may lead into the human escalation chain. In the alert scenario only Min changes to `View alert`; the other cards still expose `Send concern`.

## Considered approaches

1. Remove manual concern entirely. This is calm and safe, but removes the intended ability to deliberately ask someone to prove they are okay before automation raises an alert.
2. Keep concern as a secondary, consequence-confirmed action inside a person's expanded details. This preserves manual care without turning a safety trigger into a casual repeated button. **Selected.**
3. Keep concern visible on every card but restyle it. This does not solve the semantic problem and is rejected.

## State and action contract

| Person state | Collapsed card | Expanded details | Primary flow |
|---|---|---|---|
| Current | Status, evidence, `View details` | `Ask Min to check in` as a secondary action | Confirmation explains that a real safety check starts and may escalate after non-response |
| Limited / Unknown | Coverage limitation, evidence, `View details` | Same secondary manual action; limitation is explicitly not proof of danger | No automatic danger styling |
| Alert unclaimed | `Needs action`, `View alert` | Alert context | `I'll contact them` |
| Alert claimed by someone else | `Being contacted`, `View alert` | Claimer and timing | Read-only coordination state |
| Alert claimed by current user | `You're contacting`, `View alert` | Claimer and timing | `Confirm safe` |
| Resolved | `Resolved`, `View details` | Resolution note | No crisis action |

The prototype scenario controls will demonstrate `normal`, `limited`, `alert`, `claimed`, and `resolved` states. Routine cards never contain a persistent concern button.

## Copy

- Replace `Send concern` with `Ask <name> to check in`.
- Confirmation title: `Ask <name> to check in?`
- Confirmation body: `This starts a safety check and sends <name> an urgent notification. If they do not respond, Keep Contact may alert people in their Circle.`
- Confirmation action: `Start safety check`.
- Alert response actions: `View alert`, `I'll contact them`, `Confirm safe`.

The demo must not claim delivery. After the manual request it may say only that the server accepted the request and delivery is not yet confirmed.

## Interaction design

- The manual check-in action lives only inside the expanded person details.
- It opens a confirmation dialog before changing demo state.
- An alert opens a dedicated in-page response card rather than replacing the person's routine information.
- Claiming changes the response card to show the current user as the contact person and exposes `Confirm safe`.
- Confirming safe changes the scenario to resolved and removes crisis actions.

## Accessibility and safety

- Buttons retain visible labels, keyboard access, and at least the existing touch target size.
- State changes announce through the existing polite live region.
- Red/action emphasis appears only for an actual alert requiring response.
- Limited coverage remains neutral and explicitly does not imply danger.
- Destructive styling is not used because none of these actions deletes data.

## Testing

The prototype contract must fail before implementation and then prove:

- routine cards contain no persistent `send-concern` action;
- `Ask <name> to check in` exists only in expanded details;
- consequence confirmation names urgent notification and possible Circle escalation;
- alert flow exposes `View alert`, `I'll contact them`, and `Confirm safe`;
- claimed and resolved states are represented;
- the old casual `Send concern` copy is absent from the Watch surface;
- inline JavaScript parses and element IDs stay unique.

## Scope boundary

This task changes only the local interactive prototype, its static contract, and supporting design notes. It does not change production React, native code, Supabase RPCs, migrations, push delivery, or releases. Production UI and server-side stage enforcement require a separate High-risk task after prototype validation.
