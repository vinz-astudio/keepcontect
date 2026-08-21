import { describe, expect, it } from 'vitest'
import {
  DAILY_CHECKIN_LIMITS,
  defaultDailyCheckin,
  describeDailyCheckin,
  describeWorstCase,
  expectedQuestionsPerDay,
  formatLocalMinute,
  parseLocalMinute,
  validateDailyCheckin,
  type DailyCheckinDraft,
} from './dailyCheckin'

const base: DailyCheckinDraft = {
  askAtLocalMinute: 9 * 60,
  waiverLookbackMinutes: 24 * 60,
  responseGraceMinutes: 2 * 60,
  timezone: 'Asia/Thimphu',
}

describe('local minute conversion', () => {
  it('round-trips a time the user typed', () => {
    expect(parseLocalMinute('09:00')).toBe(540)
    expect(formatLocalMinute(540)).toBe('09:00')
    expect(formatLocalMinute(parseLocalMinute('23:45')!)).toBe('23:45')
  })

  it('rejects times that are not times', () => {
    expect(parseLocalMinute('24:00')).toBeNull()
    expect(parseLocalMinute('09:60')).toBeNull()
    expect(parseLocalMinute('morning')).toBeNull()
  })
})

describe('validation', () => {
  it('accepts the default', () => {
    expect(validateDailyCheckin(defaultDailyCheckin('Asia/Thimphu'), true)).toEqual([])
  })

  it('rejects a quiet period short enough to be a tripwire', () => {
    const draft = { ...base, waiverLookbackMinutes: DAILY_CHECKIN_LIMITS.minWaiverLookbackMinutes - 1 }
    expect(validateDailyCheckin(draft, false)).toHaveLength(1)
  })

  it('rejects a response window too short to answer', () => {
    const draft = { ...base, responseGraceMinutes: 5 }
    expect(validateDailyCheckin(draft, false)).toHaveLength(1)
  })

  it('rejects a missing timezone, because the ask time means nothing without it', () => {
    expect(validateDailyCheckin({ ...base, timezone: '  ' }, false)).toHaveLength(1)
  })
})

describe('plain-language contract', () => {
  it('states quiet, ask, answer and escalate in that order', () => {
    const lines = describeDailyCheckin(base, true)
    expect(lines).toHaveLength(4)
    expect(lines[0]).toContain('09:00')
    expect(lines[0]).toContain('1 天')
    expect(lines[1]).toContain('问您一次')
    expect(lines[2]).toContain('点一下')
    expect(lines[3]).toContain('2 小时')
  })

  it('renders odd durations without pretending they are round', () => {
    const lines = describeDailyCheckin({ ...base, responseGraceMinutes: 90 }, false)
    expect(lines[3]).toContain('1h 30m')
  })

  it('promises the market baseline as the worst case, not silence', () => {
    expect(describeWorstCase(true)).toContain('每天问您一次')
    expect(describeWorstCase(false)).toContain('once a day')
  })
})

describe('interruption budget', () => {
  it('a subject active every day is never asked', () => {
    expect(expectedQuestionsPerDay(1)).toBe(0)
  })

  it('a subject the collector never sees is asked daily', () => {
    expect(expectedQuestionsPerDay(0)).toBe(1)
  })

  it('reports no rate rather than inventing one when there is no history', () => {
    expect(expectedQuestionsPerDay(null)).toBeNull()
  })

  it('stays inside the product gate for a normally active subject', () => {
    // The accepted gate is median <= 0.2 questions per subject-day.
    expect(expectedQuestionsPerDay(0.9)!).toBeLessThanOrEqual(0.2)
  })
})
