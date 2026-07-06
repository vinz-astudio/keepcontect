import { describe, expect, it } from 'vitest'
import { buildNotificationFeed } from '@/features/alerts/notificationFeed'

const base = {
  recipient_id: 'viewer',
  read_at: null,
  pushed_at: null,
  params: {},
}

function notif(
  id: string,
  kind: string,
  alertId: string | null,
  createdAt: string,
) {
  return {
    ...base,
    id,
    kind,
    alert_id: alertId,
    body: id,
    created_at: createdAt,
  }
}

describe('notification feed grouping', () => {
  it('collapses repeated visible notifications for the same alert', () => {
    const feed = buildNotificationFeed(
      [
        notif('newer', 'community', 'alert-1', '2026-07-06T12:03:00Z'),
        notif('older', 'community', 'alert-1', '2026-07-06T12:00:00Z'),
        notif('other', 'group', 'alert-2', '2026-07-06T11:59:00Z'),
      ],
      { expanded: false, feedCap: 3 },
    )

    expect(feed.items).toHaveLength(2)
    expect(feed.items[0].notification.id).toBe('newer')
    expect(feed.items[0].count).toBe(2)
    expect(feed.items[0].ids).toEqual(['newer', 'older'])
  })

  it('keeps account-only notifications hidden until expanded', () => {
    const feed = buildNotificationFeed(
      [
        notif('self', 'self', 'alert-self', '2026-07-06T12:04:00Z'),
        notif('member', 'group', 'alert-member', '2026-07-06T12:03:00Z'),
      ],
      { expanded: false, feedCap: 3 },
    )

    expect(feed.items.map((item) => item.notification.id)).toEqual(['member'])
    expect(feed.hasMore).toBe(true)
  })
})
