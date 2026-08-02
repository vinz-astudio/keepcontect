# Prototype Watch Responsibilities, Check-ins, and Concern

Date: 2026-08-02
Task: `KC-PROTOTYPE-WATCH-ACTIONS-001`

## Problem

The prototype currently mixes three different responsibilities:

- Any watched person's details offer `Ask <name> to check in`, although scheduled check-in tasks belong only to a special Guardian-to-Ward responsibility.
- Tasks assigned to the current user occupy a separate full-width `Check-in tasks` section below the people list.
- The alert response starts with contact claiming, although `Send concern` is intended to ask the alerted person to disprove a possible false alarm before responders spend more human attention.

These mistakes make ordinary Circle membership look like permission to assign care work or repeatedly nudge another member.

## Considered approaches

1. **Person-owned responsibility, selected.** Keep a Ward's check-in arrangement inside that person's expanded details. Surface the current user's own due task through a compact `Check in` action at the top of Watch. Keep concern inside the active alert flow only. This preserves who owns each action and removes the large detached task section.
2. **Responsibilities-only management.** Put all scheduled-task controls in Circles → Responsibilities. This is structurally strict, but makes a guardian leave the person they are reviewing to manage that person's care.
3. **Top task drawer.** Put every assigned and received task in one Watch drawer. This is compact, but again separates tasks from the Ward they belong to and mixes tasks the user performs with tasks the user manages.

## Role and ownership contract

| Relationship or state | Allowed Watch action |
|---|---|
| Ordinary member in the same Circle | View status and details only before an alert |
| Current user is Guardian for a Ward | The Ward's expanded details show `Check-in arrangement`; the Guardian may add, edit, or remove scheduled tasks |
| Current user has a task assigned by a Guardian | A compact top-level `Check in` action appears with due/pending context; the detached full-width task section does not appear |
| No task is waiting for the current user | No top-level task action is shown |
| Active alert | The alert response, not the routine person card, may offer `Send concern` |

`Ask <name> to check in` is removed from ordinary people details. Creating a scheduled task is a care arrangement, not an ad-hoc request.

## Information architecture

Watch is ordered as follows:

1. compact action summary;
2. conditional top-level `Check in` action for the current user's own task;
3. `People I watch`;
4. active alert response when applicable;
5. activity history.

There is no separate `Check-in tasks` section. A Guardian's task-management controls remain under the corresponding Ward. Tasks assigned to the current user remain reachable without requiring the user to find the person who created them.

## Alert action state machine

| Alert state | Alert copy | Actions |
|---|---|---|
| No alert | Routine evidence only | No concern action |
| Alert opened | Possible false alarm has not been checked | `Send concern`; secondary `I'll contact them` |
| Concern sent | Waiting for the protected person to complete their explicit safety confirmation | `I'll contact them` remains available; do not block urgent human action |
| Claimed by current user | Current user is contacting the protected person | `Confirm safe` |
| Claimed by someone else | Named responder is contacting the protected person | Read-only coordination state |
| Subject self-confirms | Alert resolved by the protected person's explicit confirmation | No crisis action |
| Responder confirms safe | Alert resolved with external confirmation | No crisis action; do not present it as the subject's own activity evidence |

`Send concern` is alert-scoped. It is the first false-alarm check, not a general-purpose message and not a substitute for claiming or contacting the person. Concern delivery failure must leave `I'll contact them` available.

## Prototype scenarios

The external prototype controls demonstrate:

- `normal`: no task and no alert;
- `task`: the current user has one due check-in action at the top;
- `limited`: evidence is incomplete but no danger action is inferred;
- `alert`: concern is available only inside the active alert response;
- `concern-sent`: waiting for explicit self-confirmation while contact claiming stays available;
- `claimed`: the current user is contacting the person;
- `resolved`: crisis actions are removed;
- existing loading and error states.

One Ward card demonstrates an existing scheduled check-in arrangement with add, edit, and remove destinations. Ordinary member cards demonstrate that Circle membership alone exposes none of those controls.

## Copy

- Current-user task action: `Check in`.
- Ward details title: `Check-in arrangement`.
- Ward task actions: `Add task`, `Edit`, `Remove`.
- Alert action: `Send concern`.
- Concern confirmation body: `This asks <name> to open Keep Contact and confirm they are safe. It is only available because an alert is active.`
- Post-send state: `Concern sent · waiting for <name> to confirm`.
- Parallel escalation action: `I'll contact them`.
- Claimed action: `Confirm safe`.

The demo must distinguish server acceptance, notification delivery, self-confirmation, contact claiming, and external safety confirmation. None may be silently inferred from another.

## Accessibility and safety

- Every action retains a visible label, keyboard access, and the existing minimum touch target.
- State changes announce through the existing polite live region.
- Alert emphasis appears only while an alert requires response.
- Limited coverage remains neutral and explicitly does not imply danger.
- Removing a scheduled task requires confirmation; sending concern and confirming safe each require consequence copy.

## Testing

The prototype contract must fail before implementation and then prove:

- ordinary person cards and details contain neither concern nor task-assignment actions;
- only a Ward responsibility exposes add, edit, and remove check-in task destinations;
- the detached `checkin-tasks` section is absent;
- the current user's due task appears as a compact top-level `Check in` action;
- `Send concern` is absent without an alert and present inside the active alert response;
- after concern is sent, waiting copy and `I'll contact them` remain available;
- claimed and resolved states remain distinct;
- inline JavaScript parses and element IDs stay unique.

## Scope boundary

This task changes only the local interactive prototype, its static contract, and supporting design notes. It does not change production React, native code, Supabase RPCs, migrations, push delivery, or releases. The production UI, task placement, and server-side concern eligibility need a separate governed task after prototype validation.
