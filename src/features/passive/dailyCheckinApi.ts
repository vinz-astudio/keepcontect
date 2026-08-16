import { supabase } from '@/lib/supabase'
import type { DailyCheckinDraft } from './dailyCheckin'

export const DAILY_CHECKIN_CLIENT_CONTRACT = 'daily-checkin-v1' as const

export type DailyCheckinMode = 'legacy' | 'shadow' | 'passive_checkin'

export interface DailyCheckinStatus {
  engineMode: DailyCheckinMode
  killSwitchActive: boolean
  /** Null until the subject has saved a daily contract. */
  draft: DailyCheckinDraft | null
  versionNumber: number | null
  effectiveAt: string | null
  /** When the next question would be asked if nothing changes. */
  nextQuestionAt: string | null
  /** Most recent qualifying activity from any bound device. */
  lastActivityAt: string | null
  /** Completed days since the current settings took effect. */
  daysObserved: number
  /** Of those days, how many actually produced a question. */
  daysAsked: number
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function integer(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) ? value : null
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null
}

function mode(value: unknown): DailyCheckinMode {
  return value === 'passive_checkin' || value === 'shadow' ? value : 'legacy'
}

export function parseDailyCheckinStatus(payload: unknown): DailyCheckinStatus | null {
  const row = record(payload)
  if (!row) return null
  const askAt = integer(row.ask_at_local_minute)
  const quiet = integer(row.quiet_period_minutes)
  const grace = integer(row.response_grace_minutes)
  const timezone = text(row.timezone)
  // A contract missing any of the four is a legacy grid contract, not a daily
  // one. Reporting it as a half-filled daily contract would put numbers on the
  // settings screen that the engine is not actually using.
  const draft: DailyCheckinDraft | null =
    askAt !== null && quiet !== null && grace !== null && timezone !== null
      ? {
          askAtLocalMinute: askAt,
          waiverLookbackMinutes: quiet,
          responseGraceMinutes: grace,
          timezone,
        }
      : null
  return {
    engineMode: mode(row.engine_mode),
    killSwitchActive: row.kill_switch_active === true,
    draft,
    versionNumber: integer(row.version_number),
    effectiveAt: text(row.effective_at),
    nextQuestionAt: text(row.next_question_at),
    lastActivityAt: text(row.last_activity_at),
    daysObserved: integer(row.days_observed) ?? 0,
    daysAsked: integer(row.days_asked) ?? 0,
  }
}

export async function getDailyCheckin(): Promise<DailyCheckinStatus | null> {
  const { data, error } = await supabase.rpc('my_daily_checkin' as never)
  if (error) throw new Error(error.message)
  return parseDailyCheckinStatus(data)
}

export async function saveDailyCheckin(
  draft: DailyCheckinDraft,
  targetMode: 'shadow' | 'passive_checkin',
): Promise<void> {
  const { error } = await supabase.rpc('set_daily_checkin_contract' as never, {
    _ask_at_local_minute: draft.askAtLocalMinute,
    _quiet_period_minutes: draft.waiverLookbackMinutes,
    _response_grace_minutes: draft.responseGraceMinutes,
    _timezone: draft.timezone,
    _target_mode: targetMode,
    _client_contract_version: DAILY_CHECKIN_CLIENT_CONTRACT,
  } as never)
  if (error) throw new Error(error.message)
}

/**
 * The share of completed days that did NOT produce a question.
 *
 * This is the only honest source for "how often will KC actually ask you": it
 * is measured on this subject's own days, not modelled. Fewer than three
 * completed days is not a rate, so it returns null rather than a number the
 * subject would reasonably treat as a promise.
 */
export function observedActiveDaysRatio(status: DailyCheckinStatus): number | null {
  if (status.daysObserved < 3) return null
  const quiet = status.daysObserved - status.daysAsked
  return quiet / status.daysObserved
}
