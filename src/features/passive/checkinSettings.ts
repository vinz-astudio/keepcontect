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

export function canActivatePassive(status: PassiveCheckinStatus, hasBoundCollector: boolean, now = Date.now()): boolean {
  return status.engineMode === 'shadow' && !status.killSwitchActive && hasBoundCollector
    && shadowDays(status, now) >= SHADOW_DAYS_REQUIRED
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
