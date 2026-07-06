export interface NotificationForFeed {
  id: string
  kind: string
  alert_id: string | null
  created_at: string
}

export interface NotificationFeedItem<T extends NotificationForFeed> {
  notification: T
  count: number
  ids: string[]
}

export interface NotificationFeedOptions {
  expanded: boolean
  feedCap: number
}

const SELF_KINDS = new Set([
  'self',
  'task_invite',
  'task_due',
  'task_updated',
  'test',
  'concern',
])

function groupKey(notification: NotificationForFeed): string {
  if (!notification.alert_id) return `notification:${notification.id}`
  return `alert:${notification.alert_id}:${notification.kind}`
}

export function buildNotificationFeed<T extends NotificationForFeed>(
  notifications: T[],
  options: NotificationFeedOptions,
): { items: NotificationFeedItem<T>[]; hasMore: boolean } {
  const sorted = [...notifications].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
  )
  const grouped = new Map<string, NotificationFeedItem<T>>()

  for (const notification of sorted) {
    const key = groupKey(notification)
    const item = grouped.get(key)
    if (item) {
      item.count += 1
      item.ids.push(notification.id)
      continue
    }
    grouped.set(key, { notification, count: 1, ids: [notification.id] })
  }

  const allItems = [...grouped.values()]
  const memberItems = allItems.filter((item) => !SELF_KINDS.has(item.notification.kind))
  const items = options.expanded ? allItems : memberItems.slice(0, options.feedCap)
  const hasMore =
    !options.expanded &&
    (memberItems.length > options.feedCap || allItems.length > memberItems.length)

  return { items, hasMore }
}
