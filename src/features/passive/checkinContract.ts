import { supabase } from '@/lib/supabase'

export const PASSIVE_CHECKIN_CLIENT_CONTRACT = 'passive-checkin-v1' as const

export type PassiveEngineMode = 'legacy' | 'shadow' | 'passive_checkin'
export type PassiveSleepChoice =
  | {
      policy: 'configured'
      start: string
      end: string
      timezone: string
    }
  | {
      policy: 'none'
      acknowledged: boolean
    }

export interface PassiveContractDraft {
  intervalMinutes: number
  consecutiveMisses: number
  sleep: PassiveSleepChoice
}

export interface PassiveContractSummary {
  id: string
  versionNumber: number
  intervalMinutes: number
  consecutiveMisses: number
  nominalHMinutes: number
  sleepPolicy: 'configured' | 'none'
  sleepStartLocal: string | null
  sleepEndLocal: string | null
  timezone: string | null
  clientContractVersion: string
  effectiveAt: string
}

export interface PassiveEpochSummary {
  id: string
  startedAt: string
  startReason: 'contract_saved' | 'explicit_resolution' | 'manual_reset' | 'rollback'
}

export interface PassiveWindowSummary {
  id: string
  ordinal: number
  windowStart: string
  windowEnd: string
  arrivalDeadline: string
  outcome: 'pending' | 'checked_in' | 'missed' | 'superseded'
}

export interface PassiveCheckinStatus {
  engineMode: PassiveEngineMode
  killSwitchActive: boolean
  contract: PassiveContractSummary | null
  epoch: PassiveEpochSummary | null
  currentWindow: PassiveWindowSummary | null
  collectorHealth: unknown | null
  recommendation: unknown | null
}

export interface SetPassiveContractArgs {
  _interval_minutes: number
  _consecutive_misses: number
  _sleep_policy: 'configured' | 'none'
  _sleep_start_local: string | null
  _sleep_end_local: string | null
  _timezone: string | null
  _target_mode: 'shadow'
  _client_contract_version: typeof PASSIVE_CHECKIN_CLIENT_CONTRACT
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function requiredString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null
}

function finiteInteger(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) ? value : null
}

function nullableString(value: unknown): string | null | undefined {
  if (value === null) return null
  return requiredString(value) ?? undefined
}

function parseContract(value: unknown): PassiveContractSummary | null | undefined {
  if (value === null) return null
  const raw = record(value)
  if (!raw) return undefined
  const sleepPolicy = raw.sleep_policy
  const parsed: PassiveContractSummary = {
    id: requiredString(raw.id) ?? '',
    versionNumber: finiteInteger(raw.version_number) ?? Number.NaN,
    intervalMinutes: finiteInteger(raw.interval_minutes) ?? Number.NaN,
    consecutiveMisses: finiteInteger(raw.consecutive_misses) ?? Number.NaN,
    nominalHMinutes: finiteInteger(raw.nominal_h_minutes) ?? Number.NaN,
    sleepPolicy: sleepPolicy === 'configured' || sleepPolicy === 'none'
      ? sleepPolicy
      : 'none',
    sleepStartLocal: nullableString(raw.sleep_start_local) ?? null,
    sleepEndLocal: nullableString(raw.sleep_end_local) ?? null,
    timezone: nullableString(raw.timezone) ?? null,
    clientContractVersion: requiredString(raw.client_contract_version) ?? '',
    effectiveAt: requiredString(raw.effective_at) ?? '',
  }
  if (
    !parsed.id
    || !Number.isSafeInteger(parsed.versionNumber)
    || parsed.versionNumber < 1
    || !Number.isSafeInteger(parsed.intervalMinutes)
    || parsed.intervalMinutes < 20
    || parsed.intervalMinutes > 360
    || !Number.isSafeInteger(parsed.consecutiveMisses)
    || parsed.consecutiveMisses < 1
    || parsed.consecutiveMisses > 1_000_000
    || parsed.nominalHMinutes !== parsed.intervalMinutes * parsed.consecutiveMisses
    || !parsed.clientContractVersion
    || Number.isNaN(Date.parse(parsed.effectiveAt))
    || (sleepPolicy !== 'configured' && sleepPolicy !== 'none')
    || (
      parsed.sleepPolicy === 'configured'
      && (!parsed.sleepStartLocal || !parsed.sleepEndLocal || !parsed.timezone)
    )
  ) return undefined
  return parsed
}

function parseEpoch(value: unknown): PassiveEpochSummary | null | undefined {
  if (value === null) return null
  const raw = record(value)
  if (!raw) return undefined
  const startReason = raw.start_reason
  if (!['contract_saved', 'explicit_resolution', 'manual_reset', 'rollback'].includes(String(startReason))) {
    return undefined
  }
  const id = requiredString(raw.id)
  const startedAt = requiredString(raw.started_at)
  if (!id || !startedAt || Number.isNaN(Date.parse(startedAt))) return undefined
  return {
    id,
    startedAt,
    startReason: startReason as PassiveEpochSummary['startReason'],
  }
}

function parseWindow(value: unknown): PassiveWindowSummary | null | undefined {
  if (value === null) return null
  const raw = record(value)
  if (!raw) return undefined
  const outcome = raw.outcome
  const id = requiredString(raw.id)
  const ordinal = finiteInteger(raw.ordinal)
  const windowStart = requiredString(raw.window_start)
  const windowEnd = requiredString(raw.window_end)
  const arrivalDeadline = requiredString(raw.arrival_deadline)
  if (
    !id
    || ordinal === null
    || ordinal < 0
    || !windowStart
    || !windowEnd
    || !arrivalDeadline
    || !['pending', 'checked_in', 'missed', 'superseded'].includes(String(outcome))
    || [windowStart, windowEnd, arrivalDeadline].some((item) => Number.isNaN(Date.parse(item)))
  ) return undefined
  return {
    id,
    ordinal,
    windowStart,
    windowEnd,
    arrivalDeadline,
    outcome: outcome as PassiveWindowSummary['outcome'],
  }
}

export function parsePassiveCheckinStatus(value: unknown): PassiveCheckinStatus {
  const raw = record(value)
  if (!raw) throw new Error('Invalid passive check-in status')
  const mode = raw.engine_mode
  if (mode !== 'legacy' && mode !== 'shadow' && mode !== 'passive_checkin') {
    throw new Error('Invalid passive check-in status')
  }

  const contract = parseContract(raw.contract ?? null)
  const epoch = parseEpoch(raw.epoch ?? null)
  const currentWindow = parseWindow(raw.current_window ?? null)
  const killSwitchActive = raw.kill_switch_active
  const activeShapeIsValid = mode === 'legacy'
    ? contract === null && epoch === null && currentWindow === null
    : contract !== null && contract !== undefined && epoch !== null && epoch !== undefined

  if (
    typeof killSwitchActive !== 'boolean'
    || contract === undefined
    || epoch === undefined
    || currentWindow === undefined
    || !activeShapeIsValid
  ) {
    throw new Error('Invalid passive check-in status')
  }

  return {
    engineMode: mode,
    killSwitchActive,
    contract,
    epoch,
    currentWindow,
    collectorHealth: raw.collector_health ?? null,
    recommendation: raw.recommendation ?? null,
  }
}

const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/

export function validatePassiveContractDraft(draft: PassiveContractDraft): string[] {
  const errors: string[] = []
  if (!Number.isSafeInteger(draft.intervalMinutes)
      || draft.intervalMinutes < 20
      || draft.intervalMinutes > 360) {
    errors.push('Collection interval must be between 20 and 360 minutes')
  }
  if (!Number.isSafeInteger(draft.consecutiveMisses)
      || draft.consecutiveMisses < 1
      || draft.consecutiveMisses > 1_000_000) {
    errors.push('Consecutive misses must be between 1 and 1000000')
  }
  if (draft.sleep.policy === 'none') {
    if (!draft.sleep.acknowledged) {
      errors.push('Confirm that overnight inactivity counts as missed check-ins')
    }
  } else {
    if (!TIME_PATTERN.test(draft.sleep.start) || !TIME_PATTERN.test(draft.sleep.end)) {
      errors.push('Sleep times must use HH:MM')
    }
    if (draft.sleep.start === draft.sleep.end) {
      errors.push('Sleep start and end must be different')
    }
    if (!draft.sleep.timezone.trim()) {
      errors.push('A timezone is required for configured sleep')
    }
  }
  return errors
}

function withSeconds(time: string): string {
  return `${time}:00`
}

export function buildPassiveContractArgs(draft: PassiveContractDraft): SetPassiveContractArgs {
  const errors = validatePassiveContractDraft(draft)
  if (errors.length) throw new Error(errors.join('; '))
  return {
    _interval_minutes: draft.intervalMinutes,
    _consecutive_misses: draft.consecutiveMisses,
    _sleep_policy: draft.sleep.policy,
    _sleep_start_local: draft.sleep.policy === 'configured' ? withSeconds(draft.sleep.start) : null,
    _sleep_end_local: draft.sleep.policy === 'configured' ? withSeconds(draft.sleep.end) : null,
    _timezone: draft.sleep.policy === 'configured' ? draft.sleep.timezone : null,
    _target_mode: 'shadow',
    _client_contract_version: PASSIVE_CHECKIN_CLIENT_CONTRACT,
  }
}

export async function getPassiveCheckinStatus(): Promise<PassiveCheckinStatus> {
  const { data, error } = await supabase.rpc('my_passive_checkin_status')
  if (error) throw error
  return parsePassiveCheckinStatus(data)
}

export async function savePassiveCheckinContract(
  draft: PassiveContractDraft,
): Promise<PassiveCheckinStatus> {
  const args = buildPassiveContractArgs(draft)
  const { data, error } = await supabase.rpc('set_passive_checkin_contract', args)
  if (error) throw error
  return parsePassiveCheckinStatus(data)
}
