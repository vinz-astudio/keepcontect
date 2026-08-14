import type { PassiveCheckinStatus, PassiveContractDraft } from './checkinContract'

export const SHADOW_DAYS_REQUIRED = 14

export function formatHorizonMinutes(intervalMinutes: number, consecutiveMisses: number): string {
  if (!Number.isSafeInteger(intervalMinutes) || !Number.isSafeInteger(consecutiveMisses)) return '—'
  const minutes = intervalMinutes * consecutiveMisses
  if (!Number.isSafeInteger(minutes) || minutes < 1) return '—'
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  const rest = minutes % 60
  return [days ? `${days}d` : '', hours ? `${hours}h` : '', rest || (!days && !hours) ? `${rest}m` : '']
    .filter(Boolean).join(' ')
}

export function shadowDays(status: PassiveCheckinStatus, now = Date.now()): number {
  if (status.engineMode !== 'shadow' || !status.epoch) return 0
  return Math.max(0, Math.floor((now - Date.parse(status.epoch.startedAt)) / 86_400_000))
}

export function canActivatePassive(_status: PassiveCheckinStatus, _hasBoundCollector: boolean, _now = Date.now()): boolean {
  // Live activation (20260814201500) is deferred out of Stage 1. The UI must
  // never offer activation while the server RPC does not exist in production.
  // Re-enable the shadow-days gate when the activation migration ships.
  return false
}

export interface SafeSaveResult {
  success: boolean
  status: PassiveCheckinStatus
  error: string | null
}

export async function savePassiveSettingsSafe(
  draft: PassiveContractDraft,
  target: 'shadow' | 'passive_checkin',
  previous: PassiveCheckinStatus,
  writer: (draft: PassiveContractDraft, target: 'shadow' | 'passive_checkin') => Promise<PassiveCheckinStatus>,
): Promise<SafeSaveResult> {
  try {
    return { success: true, status: await writer(draft, target), error: null }
  } catch (error) {
    return { success: false, status: previous, error: error instanceof Error ? error.message : String(error) }
  }
}
