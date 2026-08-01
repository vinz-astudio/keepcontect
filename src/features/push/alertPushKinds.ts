// Which notification kinds travel as a system-displayed alert push, and which
// stay a content-free wake tickle.
//
// Native pushes (FCM/APNs) are not end-to-end encrypted the way Web Push is, so
// anything written into the payload is readable by Google and Apple. ADR-0004
// answered that by sending an empty tickle for everything and letting the device
// pull the text from notify-feed.
//
// That is right for the escalation kinds, whose text exposes a third party's
// jeopardy — "紧急：X 持续无响应。已为你解锁其地址与紧急联系人" must never sit in
// a payload Apple can read. It is wrong for the two kinds addressed to the
// subject themselves: a `concern` or a `self` alert is the target's own chance to
// unlock and stop the escalation, and an empty envelope cannot display anything
// unless the app happens to be alive to render it — which on iOS it is not once
// the user has swiped the app away.
//
// So the rule is scoped per kind rather than applied uniformly.

/** Addressed to the subject; the payload names at most who is checking on them. */
const SELF_ADDRESSED_KINDS = new Set(['concern', 'self']);

export function usesAlertPush(kind: string): boolean {
  return SELF_ADDRESSED_KINDS.has(kind);
}
