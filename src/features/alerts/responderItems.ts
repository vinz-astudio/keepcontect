import type { Alert, AppNotification } from './api'

export interface ResponderItemInfo {
  alert: Alert
  isUnread: boolean
}

/**
 * Derives responder items from open alerts and notifications.
 * Alerts are the source of truth; notifications only enrich (e.g. unread status).
 */
export function buildResponderItems(
  alerts: Alert[],
  notifications: AppNotification[]
): Record<string, ResponderItemInfo> {
  const result: Record<string, ResponderItemInfo> = {}

  for (const alert of alerts) {
    if (alert.status !== 'open') continue

    // A responder item is unread if there are any unread notifications associated with this alert
    const hasUnread = notifications.some(
      (n) => n.alert_id === alert.id && !n.read_at
    )

    result[alert.id] = {
      alert,
      isUnread: hasUnread,
    }
  }

  return result
}
