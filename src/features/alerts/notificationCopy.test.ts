import { describe, expect, it } from 'vitest'
import { renderNotificationCopy } from '@/features/alerts/notificationCopy'

describe('notification copy', () => {
  it('uses second person when a resolved notification is about the current user', () => {
    const copy = renderNotificationCopy(
      {
        kind: 'resolved',
        body: 'Demo User is confirmed safe.',
        params: { target: 'Demo User' },
      },
      { userId: 'u1', displayName: 'Demo User' },
    )

    expect(copy).toBe('You are confirmed safe. Alert resolved.')
  })

  it('uses second person when an on-it notification target is the current user', () => {
    const copy = renderNotificationCopy(
      {
        kind: 'on_it',
        body: 'Chunwei is following up on Demo User.',
        params: { actor: 'Chunwei', target_id: 'u1', target: 'Demo User' },
      },
      { userId: 'u1', displayName: 'Demo User' },
    )

    expect(copy).toBe('Chunwei is following up on you.')
  })

  it('keeps third person when the notification is about someone else', () => {
    const copy = renderNotificationCopy(
      {
        kind: 'resolved',
        body: 'Demo User is confirmed safe.',
        params: { target_id: 'u2', target: 'Demo User' },
      },
      { userId: 'u1', displayName: 'Chunwei' },
    )

    expect(copy).toBe('Demo User is confirmed safe. Alert resolved.')
  })
})
