import { supabase } from '@/lib/supabase'
import { SUPABASE_URL } from '@/lib/config'
import type { Tables } from '@/lib/database.types'
import { isStandalone, isTauri } from '@/lib/platform'
import { Capacitor } from '@capacitor/core'

export type BehaviorPing = Tables<'behavior_pings'>
export type PingKind = 'app'

export const PASSIVE_WEB_PING_THROTTLE_MS = 5 * 60 * 1000

export const PING_SOURCES = {
  INSTALLED_PWA: 'installed_pwa',
  TAURI: 'tauri',
  CAPACITOR: 'capacitor',
  SHORTCUT: 'shortcut',
  MANUAL: 'manual',
} as const

export type PingSource = typeof PING_SOURCES[keyof typeof PING_SOURCES]

export function getAutomaticPingSource(): 'installed_pwa' | 'tauri' | 'capacitor' | null {
  if (isTauri()) {
    return PING_SOURCES.TAURI
  }
  if (isStandalone()) {
    return PING_SOURCES.INSTALLED_PWA
  }
  if (Capacitor.isNativePlatform()) {
    return PING_SOURCES.CAPACITOR
  }
  return null
}

export function shouldSendPassiveWebPing(
  lastPingAtMs: number | null,
  nowMs: number = Date.now(),
  throttleMs: number = PASSIVE_WEB_PING_THROTTLE_MS,
): boolean {
  return lastPingAtMs === null || nowMs - lastPingAtMs >= throttleMs
}

export async function getHeartbeatToken(): Promise<string | null> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return null
  const { data, error } = await supabase
    .from('heartbeat_tokens')
    .select('token')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  return data?.token ?? null
}

/** One tokenized URL is shared by every passive activity trigger. */
export function pingUrl(token: string, source?: string): string {
  const params = new URLSearchParams({ token })
  if (source) {
    params.set('source', source)
  }
  return `${SUPABASE_URL}/functions/v1/ping?${params.toString()}`
}

/** Recent pings used for the lightweight activity summary. */
export async function listRecentPings(): Promise<BehaviorPing[]> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return []
  const since = new Date(Date.now() - 48 * 3_600_000).toISOString()
  const { data, error } = await supabase
    .from('behavior_pings')
    .select('*')
    .eq('user_id', uid)
    .gte('at', since)
    .order('at', { ascending: false })
    .limit(200)
  if (error) throw error
  return data ?? []
}

export interface PingKindStats {
  todayCount: number
  lastAt: string | null
}

export function countTodayPings(
  pings: { at: string }[],
  now: number = Date.now(),
): number {
  const start = new Date(now)
  start.setHours(0, 0, 0, 0)
  const startMs = start.getTime()
  return pings.filter((ping) => new Date(ping.at).getTime() >= startMs).length
}

export function lastPingAt(pings: { at: string }[]): string | null {
  let last: string | null = null
  for (const ping of pings) {
    if (!last || new Date(ping.at).getTime() > new Date(last).getTime()) {
      last = ping.at
    }
  }
  return last
}

export async function calculateWebHmac(token: string, message: string): Promise<string> {
  const encoder = new TextEncoder()
  const keyBytes = encoder.encode(token)
  const messageBytes = encoder.encode(message)
  const cryptoObj = typeof window !== 'undefined' ? window.crypto : (globalThis as any).crypto
  const cryptoKey = await cryptoObj.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const sigBuffer = await cryptoObj.subtle.sign('HMAC', cryptoKey, messageBytes)
  const sigBytes = new Uint8Array(sigBuffer)
  return Array.from(sigBytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export interface EventLivenessContext {
  nowMs: number
  alertCreatedAtMs?: number | null
}

export function isEventLivenessQualifying(
  event: {
    observedAtMs: number
    receivedAtMs: number
    ingestVersion: number
    kind?: string
  },
  context: EventLivenessContext
): boolean {
  if (event.ingestVersion !== 2) return false
  if (!Number.isFinite(event.observedAtMs) || !Number.isFinite(event.receivedAtMs)) return false
  if (context.alertCreatedAtMs !== undefined && context.alertCreatedAtMs !== null) {
    if (event.observedAtMs < context.alertCreatedAtMs) return false
    if (event.receivedAtMs < context.alertCreatedAtMs) return false
  }
  if (event.observedAtMs > context.nowMs + 5 * 60 * 1000) return false
  if (Math.abs(event.receivedAtMs - event.observedAtMs) > 5 * 60 * 1000) return false
  return true
}
