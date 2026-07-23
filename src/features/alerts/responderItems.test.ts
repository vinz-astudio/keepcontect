import { describe, expect, it } from 'vitest'
import { buildResponderItems } from './responderItems'
import type { Alert, AppNotification } from './api'

describe('buildResponderItems', () => {
  it('yields a card item for an open alert even with zero notifications', () => {
    const alerts: Alert[] = [
      {
        id: 'alert-1',
        user_id: 'user-2',
        status: 'open',
        stage: 'group',
        cause: 'silence',
        created_at: '2026-07-21T00:00:00Z',
        resolved_at: null,
        paused_by: null,
        sos_lat: null,
        sos_lng: null,
      } as unknown as Alert
    ]
    const notifications: AppNotification[] = []

    const items = buildResponderItems(alerts, notifications)
    expect(items['alert-1']).toBeDefined()
    expect(items['alert-1'].alert.id).toBe('alert-1')
    expect(items['alert-1'].isUnread).toBe(false)
  })

  it('yields nothing for a resolved alert', () => {
    const alerts: Alert[] = [
      {
        id: 'alert-2',
        user_id: 'user-2',
        status: 'resolved',
        stage: 'group',
        cause: 'silence',
        created_at: '2026-07-21T00:00:00Z',
        resolved_at: '2026-07-21T01:00:00Z',
        paused_by: null,
        sos_lat: null,
        sos_lng: null,
      } as unknown as Alert
    ]
    const notifications: AppNotification[] = []

    const items = buildResponderItems(alerts, notifications)
    expect(items['alert-2']).toBeUndefined()
    expect(Object.keys(items)).toHaveLength(0)
  })

  it('correctly enriches the unread status from notifications', () => {
    const alerts: Alert[] = [
      {
        id: 'alert-3',
        user_id: 'user-2',
        status: 'open',
        stage: 'group',
        cause: 'silence',
        created_at: '2026-07-21T00:00:00Z',
        resolved_at: null,
        paused_by: null,
        sos_lat: null,
        sos_lng: null,
      } as unknown as Alert
    ]
    const notifications: AppNotification[] = [
      {
        id: 'notif-1',
        alert_id: 'alert-3',
        read_at: null,
        kind: 'group',
        created_at: '2026-07-21T00:00:05Z',
      } as unknown as AppNotification
    ]

    const items = buildResponderItems(alerts, notifications)
    expect(items['alert-3']).toBeDefined()
    expect(items['alert-3'].isUnread).toBe(true)

    // With read notifications, it should be false
    const readNotifications: AppNotification[] = [
      {
        id: 'notif-1',
        alert_id: 'alert-3',
        read_at: '2026-07-21T00:05:00Z',
        kind: 'group',
        created_at: '2026-07-21T00:00:05Z',
      } as unknown as AppNotification
    ]
    const itemsRead = buildResponderItems(alerts, readNotifications)
    expect(itemsRead['alert-3'].isUnread).toBe(false)
  })
})
