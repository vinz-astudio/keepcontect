/**
 * Daily check-in with an activity waiver.
 *
 * This replaces the window-grid model the user never had a mental model for.
 * The market shape KC now follows is the one people already understand: KC asks
 * you once a day, and if you have already used your phone it does not ask.
 *
 * The old model asked the user for `D` (window length) and `N` (consecutive
 * misses) and showed them `H = D × N`. Nobody has an intuition about how often
 * they want to be silently sampled. Everybody has an intuition about "ask me in
 * the morning" and "don't ask if I'm obviously up and about".
 *
 * The decisive property is what happens when collection breaks. Under the grid
 * model a dead collector produced extra questions, because absence of evidence
 * accumulated into misses. Here a dead collector produces exactly one daily
 * question — the market baseline — and never more. KC can therefore never be
 * more annoying than the manual check-in app it exists to improve on, which is
 * the acceptance criterion the product is measured against.
 */

/** Minutes from local midnight. Stored rather than a string so arithmetic is total. */
export type LocalMinuteOfDay = number

export interface DailyCheckinDraft {
  /** When KC asks, in the subject's own local time. */
  askAtLocalMinute: LocalMinuteOfDay
  /**
   * How far back ordinary device use waives the question. Twenty-four hours
   * means "if you used your phone at any point since yesterday's check-in,
   * don't ask". Shorter values ask more often and are for people who want a
   * tighter contract with themselves.
   */
  waiverLookbackMinutes: number
  /** How long the subject has to answer before the existing funnel opens. */
  responseGraceMinutes: number
  /** IANA zone. The ask time is meaningless without it. */
  timezone: string
}

export const DAILY_CHECKIN_LIMITS = {
  /** Anything under four hours turns the waiver into a tripwire. */
  minWaiverLookbackMinutes: 4 * 60,
  /** Two days without a single unlock is not a contract anybody is keeping. */
  maxWaiverLookbackMinutes: 48 * 60,
  /** Below fifteen minutes the subject cannot realistically be reached. */
  minResponseGraceMinutes: 15,
  /** Beyond twelve hours the answer stops meaning anything on the day it was asked. */
  maxResponseGraceMinutes: 12 * 60,
} as const

export const DAILY_CHECKIN_DEFAULT: DailyCheckinDraft = {
  askAtLocalMinute: 9 * 60,
  waiverLookbackMinutes: 24 * 60,
  responseGraceMinutes: 2 * 60,
  timezone: 'UTC',
}

export function defaultDailyCheckin(timezone?: string): DailyCheckinDraft {
  return {
    ...DAILY_CHECKIN_DEFAULT,
    timezone: timezone && timezone.trim().length > 0 ? timezone : 'UTC',
  }
}

export function formatLocalMinute(minute: LocalMinuteOfDay): string {
  const safe = ((Math.trunc(minute) % 1440) + 1440) % 1440
  const hours = Math.floor(safe / 60)
  const minutes = safe % 60
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`
}

export function parseLocalMinute(value: string): LocalMinuteOfDay | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim())
  if (!match) return null
  const hours = Number(match[1])
  const minutes = Number(match[2])
  if (hours > 23 || minutes > 59) return null
  return hours * 60 + minutes
}

export function validateDailyCheckin(draft: DailyCheckinDraft, zh: boolean): string[] {
  const problems: string[] = []
  const minute = draft.askAtLocalMinute
  if (!Number.isSafeInteger(minute) || minute < 0 || minute > 1439) {
    problems.push(zh ? '请选择一个有效的提醒时间' : 'Choose a valid reminder time')
  }
  if (!Number.isSafeInteger(draft.waiverLookbackMinutes)
    || draft.waiverLookbackMinutes < DAILY_CHECKIN_LIMITS.minWaiverLookbackMinutes
    || draft.waiverLookbackMinutes > DAILY_CHECKIN_LIMITS.maxWaiverLookbackMinutes) {
    problems.push(zh
      ? '“多久没动静才问”必须在 4 小时到 48 小时之间'
      : 'The quiet period must be between 4 and 48 hours')
  }
  if (!Number.isSafeInteger(draft.responseGraceMinutes)
    || draft.responseGraceMinutes < DAILY_CHECKIN_LIMITS.minResponseGraceMinutes
    || draft.responseGraceMinutes > DAILY_CHECKIN_LIMITS.maxResponseGraceMinutes) {
    problems.push(zh
      ? '“没回应多久后通知”必须在 15 分钟到 12 小时之间'
      : 'The response window must be between 15 minutes and 12 hours')
  }
  if (draft.timezone.trim().length === 0) {
    problems.push(zh ? '缺少时区' : 'Timezone is missing')
  }
  return problems
}

function formatDuration(minutes: number, zh: boolean): string {
  if (minutes % 1440 === 0 && minutes >= 1440) {
    const days = minutes / 1440
    return zh ? `${days} 天` : days === 1 ? '1 day' : `${days} days`
  }
  if (minutes % 60 === 0) {
    const hours = minutes / 60
    return zh ? `${hours} 小时` : hours === 1 ? '1 hour' : `${hours} hours`
  }
  if (minutes < 60) return zh ? `${minutes} 分钟` : `${minutes} minutes`
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  return zh ? `${hours} 小时 ${rest} 分钟` : `${hours}h ${rest}m`
}

/**
 * The whole contract in sentences the subject can check against their own life.
 *
 * Deliberately four short statements in a fixed order — what happens normally,
 * what happens if not, what they must do, what happens if they do nothing. A
 * settings screen that cannot produce these four sentences is asking the user
 * to configure something they do not understand.
 */
export function describeDailyCheckin(draft: DailyCheckinDraft, zh: boolean): string[] {
  const at = formatLocalMinute(draft.askAtLocalMinute)
  const quiet = formatDuration(draft.waiverLookbackMinutes, zh)
  const grace = formatDuration(draft.responseGraceMinutes, zh)
  return zh
    ? [
        `每天 ${at}，如果你在过去 ${quiet} 内用过手机，KC 不打扰你。`,
        `如果这段时间完全没有动静，KC 会问你一次。`,
        `你点一下就结束了。`,
        `${grace} 内没有回应，KC 才会通知你信任的人。`,
      ]
    : [
        `Each day at ${at}, if you have used your phone in the past ${quiet}, KC stays quiet.`,
        `If there has been no activity at all, KC asks you once.`,
        `One tap ends it.`,
        `Only after ${grace} with no answer does KC tell the people you trust.`,
      ]
}

/**
 * The honest worst case, stated before the user commits.
 *
 * A subject who never grants Usage Access, or whose phone freezes the
 * collector, falls back to exactly one question per day. Saying so out loud is
 * what stops the passive layer from being sold as protection it cannot give.
 */
export function describeWorstCase(zh: boolean): string {
  return zh
    ? '如果采集失效或你没有授权，KC 每天问你一次 —— 和普通签到 App 一样，不会更多。'
    : 'If collection fails or you grant nothing, KC asks once a day — the same as an ordinary check-in app, never more.'
}

/**
 * Expected questions per day, for the interruption budget the product is gated on.
 *
 * `activeDaysRatio` is the share of days the subject produced any qualifying
 * evidence inside the look-back. It comes from observed history; with no
 * history the caller passes null and gets null rather than a fabricated rate.
 */
export function expectedQuestionsPerDay(activeDaysRatio: number | null): number | null {
  if (activeDaysRatio === null || !Number.isFinite(activeDaysRatio)) return null
  const clamped = Math.min(1, Math.max(0, activeDaysRatio))
  return Math.round((1 - clamped) * 100) / 100
}
