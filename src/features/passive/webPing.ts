import { pingUrl, shouldSendPassiveWebPing } from '@/features/passive/api'

export type PassiveWebPingResult = 'sent' | 'throttled' | 'failed'

interface SendPassiveWebPingOptions {
  token: string
  nowMs?: number
  lastPingAtMs: number | null
  fetcher: typeof fetch
  storeLastPingAt: (value: number) => void
}

export async function sendPassiveWebPing({
  token,
  nowMs = Date.now(),
  lastPingAtMs,
  fetcher,
  storeLastPingAt,
}: SendPassiveWebPingOptions): Promise<PassiveWebPingResult> {
  if (!shouldSendPassiveWebPing(lastPingAtMs, nowMs)) return 'throttled'

  try {
    const response = await fetcher(pingUrl(token), {
      method: 'GET',
      cache: 'no-store',
      keepalive: true,
    })
    if (!response.ok) return 'failed'
    storeLastPingAt(nowMs)
    return 'sent'
  } catch {
    return 'failed'
  }
}