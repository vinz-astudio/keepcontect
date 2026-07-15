import { describe, expect, it } from 'vitest'
import {
  PASSIVE_WEB_PING_THROTTLE_MS,
  countTodayPings,
  lastPingAt,
  pingUrl,
  shouldSendPassiveWebPing,
  calculateWebHmac,
} from '@/features/passive/api'

describe('passive ping helpers', () => {
  it('builds one generic ping URL without behavior classification', () => {
    expect(pingUrl('abc123')).toBe(
      'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/ping?token=abc123',
    )
  })

  it('builds one generic ping URL with source parameter', () => {
    expect(pingUrl('abc123', 'shortcut')).toBe(
      'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/ping?token=abc123&source=shortcut',
    )
  })

  it('summarizes activity without caring which trigger fired', () => {
    const now = new Date()
    now.setHours(12, 0, 0, 0)
    const yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    const later = new Date(now)
    later.setHours(13, 0, 0, 0)

    const pings = [
      { at: now.toISOString() },
      { at: yesterday.toISOString() },
      { at: later.toISOString() },
    ]

    expect(countTodayPings(pings, now.getTime())).toBe(2)
    expect(lastPingAt(pings)).toBe(later.toISOString())
  })

  it('throttles generic web passive pings', () => {
    const now = new Date('2026-06-19T12:00:00Z').getTime()

    expect(shouldSendPassiveWebPing(null, now)).toBe(true)
    expect(shouldSendPassiveWebPing(now - 60_000, now)).toBe(false)
    expect(
      shouldSendPassiveWebPing(now - PASSIVE_WEB_PING_THROTTLE_MS, now),
    ).toBe(true)
  })

  it('calculates Web HMAC correctly', async () => {
    const key = 'secret-token'
    const message = '1781956800'
    const sig = await calculateWebHmac(key, message)
    expect(sig).toHaveLength(64)
    expect(/^[0-9a-f]+$/.test(sig)).toBe(true)
  })
})