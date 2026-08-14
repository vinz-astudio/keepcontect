import { supabase } from '@/lib/supabase'
import type { PassiveEngineMode } from './checkinContract'

export type PassiveWindowOutcome = 'pending' | 'checked_in' | 'missed' | 'superseded'
export type PassiveAlertStage = 'self' | 'group' | 'community' | 'terminal'

export interface PassiveWindowState {
  engineMode: PassiveEngineMode
  consecutiveMisses: number
  currentWindow: null | {
    id: string
    ordinal: number
    windowStart: string
    windowEnd: string
    arrivalDeadline: string
    outcome: PassiveWindowOutcome
  }
  openAlert: null | { id: string; stage: PassiveAlertStage; openedAt: string }
  sleepDeferred: boolean
}

const MODES = new Set(['legacy', 'shadow', 'passive_checkin'])
const OUTCOMES = new Set(['pending', 'checked_in', 'missed', 'superseded'])
const STAGES = new Set(['self', 'group', 'community', 'terminal'])

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : null
}

function iso(value: unknown): string | null {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) return null
  return new Date(value).toISOString()
}

export function parsePassiveWindowState(value: unknown): PassiveWindowState {
  const raw = object(value)
  if (!raw || typeof raw.engine_mode !== 'string' || !MODES.has(raw.engine_mode)
    || !Number.isSafeInteger(raw.consecutive_misses) || (raw.consecutive_misses as number) < 0
    || typeof raw.sleep_deferred !== 'boolean') throw new Error('Invalid passive window state')

  const current = raw.current_window === null ? null : object(raw.current_window)
  const alert = raw.open_alert === null ? null : object(raw.open_alert)
  if ((raw.current_window !== null && !current) || (raw.open_alert !== null && !alert)) {
    throw new Error('Invalid passive window state')
  }
  const windowStart = current ? iso(current.window_start) : null
  const windowEnd = current ? iso(current.window_end) : null
  const arrivalDeadline = current ? iso(current.arrival_deadline) : null
  if (current && (typeof current.id !== 'string' || !Number.isSafeInteger(current.ordinal)
    || (current.ordinal as number) < 0 || typeof current.outcome !== 'string'
    || !OUTCOMES.has(current.outcome) || !windowStart || !windowEnd || !arrivalDeadline
    || Date.parse(windowStart) >= Date.parse(windowEnd)
    || Date.parse(arrivalDeadline) < Date.parse(windowEnd))) {
    throw new Error('Invalid passive window state')
  }
  const openedAt = alert ? iso(alert.opened_at) : null
  if (alert && (typeof alert.id !== 'string' || typeof alert.stage !== 'string'
    || !STAGES.has(alert.stage) || !openedAt)) throw new Error('Invalid passive window state')

  return {
    engineMode: raw.engine_mode as PassiveEngineMode,
    consecutiveMisses: raw.consecutive_misses as number,
    currentWindow: current ? {
      id: current.id as string,
      ordinal: current.ordinal as number,
      windowStart: windowStart!,
      windowEnd: windowEnd!,
      arrivalDeadline: arrivalDeadline!,
      outcome: current.outcome as PassiveWindowOutcome,
    } : null,
    openAlert: alert ? {
      id: alert.id as string,
      stage: alert.stage as PassiveAlertStage,
      openedAt: openedAt!,
    } : null,
    sleepDeferred: raw.sleep_deferred,
  }
}

export async function getPassiveWindowState(): Promise<PassiveWindowState> {
  const { data, error } = await supabase.rpc('my_passive_window_state' as never)
  if (error) throw error
  return parsePassiveWindowState(data)
}
