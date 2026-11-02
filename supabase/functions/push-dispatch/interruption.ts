// Which visible pushes may break through Focus and Notification Summary on iOS
// (human decision D1, 2026-11-02). The subject's own safety ask and real
// emergencies do; lost-contact notices to the circle do not, so they do not
// spend other people's attention (plan A wording: "KC lost contact").
//
// Mirrors ios-passive-ping/ios/Sources/KcPassivePingPlugin/NotificationUrgency.swift.
// Without the app's time-sensitive entitlement, or on iOS 14, iOS treats the
// value as an ordinary notification, so the server can ship before the app.
const TIME_SENSITIVE_KINDS = new Set(['self', 'concern', 'sos', 'terminal'])

export function apnsInterruptionLevel(kind: string | undefined): 'time-sensitive' | 'active' {
  return kind && TIME_SENSITIVE_KINDS.has(kind) ? 'time-sensitive' : 'active'
}
