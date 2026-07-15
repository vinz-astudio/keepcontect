import { describe, expect, it, vi } from 'vitest'
import { PASSIVE_WEB_PING_THROTTLE_MS } from '@/features/passive/api'
import { sendPassiveWebPing } from '@/features/passive/webPing'

vi.mock('@/features/passive/api', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/features/passive/api')>()
  return {
    ...actual,
    calculateWebHmac: vi.fn().mockResolvedValue('mocked-signature'),
  }
})

describe('sendPassiveWebPing', () => {
  it('skips the request inside the throttle window', async () => {
    const fetcher = vi.fn()
    const storeLastPingAt = vi.fn()
    const nowMs = new Date('2026-06-19T12:00:00Z').getTime()

    const result = await sendPassiveWebPing({
      token: 'token123',
      source: 'installed_pwa',
      nowMs,
      lastPingAtMs: nowMs - 60_000,
      fetcher,
      storeLastPingAt,
    })

    expect(result).toBe('throttled')
    expect(fetcher).not.toHaveBeenCalled()
    expect(storeLastPingAt).not.toHaveBeenCalled()
  })

  it('sends one generic ping and stores the successful timestamp', async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
    const storeLastPingAt = vi.fn()
    const nowMs = new Date('2026-06-19T12:00:00Z').getTime()

    const result = await sendPassiveWebPing({
      token: 'token123',
      source: 'installed_pwa',
      nowMs,
      lastPingAtMs: nowMs - PASSIVE_WEB_PING_THROTTLE_MS,
      fetcher,
      storeLastPingAt,
    })

    expect(result).toBe('sent')
    expect(fetcher).toHaveBeenCalledWith(
      'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/ping?token=token123&source=installed_pwa&t=1781870400&sig=mocked-signature',
      { method: 'GET', cache: 'no-store', keepalive: true },
    )
    expect(storeLastPingAt).toHaveBeenCalledWith(nowMs)
  })

  it('does not store a timestamp when the ping fails', async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response('{}', { status: 500 }))
    const storeLastPingAt = vi.fn()

    const result = await sendPassiveWebPing({
      token: 'token123',
      source: 'installed_pwa',
      nowMs: 1000,
      lastPingAtMs: null,
      fetcher,
      storeLastPingAt,
    })

    expect(result).toBe('failed')
    expect(storeLastPingAt).not.toHaveBeenCalled()
  })
})