import { supabase } from '@/lib/supabase'
import type { DailyCheckinDraft } from './dailyCheckin'

export const DAILY_CHECKIN_CLIENT_CONTRACT = 'daily-checkin-v1' as const

export type DailyCheckinMode = 'legacy' | 'shadow' | 'passive_checkin'

export type PassiveMissKind = 'silent' | 'device_unreachable' | 'collection_restricted'

export interface DailyCheckinStatus {
  engineMode: DailyCheckinMode
  killSwitchActive: boolean
  /** Null until the subject has saved a daily contract. */
  draft: DailyCheckinDraft | null
  versionNumber: number | null
  effectiveAt: string | null
  /** When the next question would be asked if nothing changes. */
  nextQuestionAt: string | null
  /**
   * 引擎当前实际在判断的截止点。它已经把两件事算进去了:锚在最新一次告活上,
   * 而且睡眠时段不消耗阈值。界面显示这个,不要自己再推一遍。
   */
  nextDeadlineAt: string | null
  /** 从最后一次告活起,已经过掉几个截止点。到达 `consecutiveMisses` 才通知。 */
  missedSoFar: number
  /**
   * 上一个截止点为什么过掉了。三种沉默不是同一回事:
   * `silent` 采集正常但确实没动静 · `device_unreachable` 设备根本没说话 ·
   * `collection_restricted` 采集被关掉了,这时的安静什么都不能证明。
   */
  lastMissKind: PassiveMissKind | null
  /** Most recent qualifying activity from any bound device. */
  lastActivityAt: string | null
  /** 服务端实际在用的连续漏签次数。界面显示这个,不自己假设。 */
  consecutiveMisses: number | null
  /**
   * Closed windows since the current settings took effect, NOT days.
   *
   * Since 20260821020000 the deadlines roll, so one closed window is one quiet
   * stretch and a single calendar day can hold several. Do not render this as
   * "your last N days" and do not divide by it to get a per-day rate.
   */
  daysObserved: number
  /** Of those closed windows, how many were missed. Again: windows, not days. */
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

function missKind(value: unknown): PassiveMissKind | null {
  return value === 'silent' || value === 'device_unreachable' || value === 'collection_restricted'
    ? value
    : null
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
    nextDeadlineAt: text(row.next_deadline_at),
    missedSoFar: integer(row.missed_so_far) ?? 0,
    lastMissKind: missKind(row.last_miss_kind),
    lastActivityAt: text(row.last_activity_at),
    consecutiveMisses: integer(row.consecutive_misses),
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
  consecutiveMisses = 2,
): Promise<void> {
  const { error } = await supabase.rpc('set_daily_checkin_contract' as never, {
    _ask_at_local_minute: draft.askAtLocalMinute,
    _quiet_period_minutes: draft.waiverLookbackMinutes,
    _response_grace_minutes: draft.responseGraceMinutes,
    _timezone: draft.timezone,
    _target_mode: targetMode,
    _client_contract_version: DAILY_CHECKIN_CLIENT_CONTRACT,
    _consecutive_misses: consecutiveMisses,
  } as never)
  if (error) throw new Error(error.message)
}
