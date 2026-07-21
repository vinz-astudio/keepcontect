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

describe('auto_resolved notification copy', () => {
  it('renders the watcher template instead of the raw server body', () => {
    const copy = renderNotificationCopy(
      {
        kind: 'auto_resolved',
        body: '阿明 的告警已自动解除（检测到活动恢复）。',
        params: { target: 'Ming' },
      },
      { userId: 'u1', displayName: 'Chunwei' },
    )

    expect(copy).toContain('Ming')
    expect(copy.toLowerCase()).toContain('automatically')
    expect(copy).not.toBe('阿明 的告警已自动解除（检测到活动恢复）。')
  })

  it('uses second person when the auto-resolved alert is about the current user', () => {
    const copy = renderNotificationCopy(
      {
        kind: 'auto_resolved',
        body: '原文',
        params: { target: 'Demo User', target_is_recipient: 'true' },
      },
      { userId: 'u1', displayName: 'Demo User' },
    )

    expect(copy.toLowerCase()).toContain('your alert')
  })

  it('keeps the raw-body fallback for unknown kinds', () => {
    const copy = renderNotificationCopy({
      kind: 'kind_from_the_future',
      body: 'raw body',
      params: {},
    })

    expect(copy).toBe('raw body')
  })
})
