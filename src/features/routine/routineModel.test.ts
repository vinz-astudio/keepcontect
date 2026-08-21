import { describe, expect, it } from 'vitest'
import {
  CHECKIN_MAX_MINUTES,
  CHECKIN_MIN_MINUTES,
  GRACE_MAX_MINUTES,
  GRACE_MIN_MINUTES,
  MIN_CONSECUTIVE_MISSES,
  clampCheckin,
  clampGrace,
  consecutiveMissesFor,
  formatAwakeHours,
  formatGrace,
  PLATFORM_RECOMMENDED_MINUTES,
  isSensitiveOutreach,
  outreachLadder,
  recommendationFor,
  snapOutreach,
} from './routineModel'
import { formatRemaining, nextCheckinRemainingMinutes } from './NextCheckin'

describe('check-in interval', () => {
  // 90 分钟是 iOS 采集面自己声明的到达宽限。低于它,健康的采集器也会被判失联。
  it('will not go below the iOS arrival allowance', () => {
    expect(clampCheckin(30)).toBe(CHECKIN_MIN_MINUTES)
    expect(CHECKIN_MIN_MINUTES).toBe(90)
  })

  it('caps at six hours so the lowest outreach rung still holds two checks', () => {
    expect(clampCheckin(24 * 60)).toBe(CHECKIN_MAX_MINUTES)
  })

  it('clamps the grace window at both ends', () => {
    expect(clampGrace(5)).toBe(GRACE_MIN_MINUTES)
    expect(clampGrace(600)).toBe(GRACE_MAX_MINUTES)
  })
})

describe('outreach ladder', () => {
  // 问3 = N × 问1 + 问2。界面上显示的「连续 N 次」必须和引擎实际做的一致,
  // 所以滑条只能停在这些档位上。
  it('starts at two consecutive misses, never one', () => {
    const rungs = outreachLadder(120, 45)
    expect(rungs[0]).toBe(2 * 120 + 45)
    expect(consecutiveMissesFor(rungs[0], 120, 45)).toBe(MIN_CONSECUTIVE_MISSES)
  })

  it('steps by one whole check-in interval', () => {
    const rungs = outreachLadder(120, 45)
    expect(rungs[1] - rungs[0]).toBe(120)
    expect(consecutiveMissesFor(rungs[2], 120, 45)).toBe(4)
  })

  it('snaps a dragged value onto a legal rung', () => {
    expect(snapOutreach(300, 120, 45)).toBe(285)
    expect(snapOutreach(400, 120, 45)).toBe(405)
  })

  it('never offers a rung past the outreach ceiling', () => {
    expect(Math.max(...outreachLadder(90, 15))).toBeLessThanOrEqual(48 * 60)
  })

  // 低于建议值要提示,但仍然允许设置 —— 建议不是禁止。
  it('warns below the recommendation, without blocking it', () => {
    expect(isSensitiveOutreach(285, PLATFORM_RECOMMENDED_MINUTES)).toBe(true)
    expect(isSensitiveOutreach(720, PLATFORM_RECOMMENDED_MINUTES)).toBe(false)
  })

  // 攒够这个账号自己的证据之前,说「根据您的数据」是不诚实的。
  it('says platform data until the account has its own', () => {
    expect(recommendationFor(null)).toEqual({
      minutes: PLATFORM_RECOMMENDED_MINUTES,
      source: 'platform',
    })
    expect(
      recommendationFor({ referenceMinutes: 9 * 60, evidenceDays: 30, confidence: 'medium' }),
    ).toEqual({ minutes: 540, source: 'account' })
  })

  // 三十天以内那个数字算得出来,但它描述的生活比它自称的短。照着它调时长的人
  // 会把一段假期当成自己的常态。
  it('will not call it your data until thirty days of it exist', () => {
    expect(
      recommendationFor({ referenceMinutes: 9 * 60, evidenceDays: 29, confidence: 'high' }),
    ).toEqual({ minutes: PLATFORM_RECOMMENDED_MINUTES, source: 'platform' })
  })

  it('will not use an estimate the estimator itself calls insufficient', () => {
    expect(
      recommendationFor({ referenceMinutes: 9 * 60, evidenceDays: 90, confidence: 'insufficient' }),
    ).toEqual({ minutes: PLATFORM_RECOMMENDED_MINUTES, source: 'platform' })
  })
})

describe('labels', () => {
  it('says awake time, so nobody reads it as clock time', () => {
    expect(formatAwakeHours(720, true)).toBe('12 小时清醒')
    expect(formatAwakeHours(285, true)).toBe('4.8 小时清醒')
  })

  it('says minutes below an hour and hours above it', () => {
    expect(formatGrace(45, true)).toBe('45 分钟')
    expect(formatGrace(90, true)).toBe('1.5 小时')
  })
})

describe('rolling deadline', () => {
  const now = new Date('2026-08-20T12:00:00Z')

  // 截止点锚在证据发生的时间,不是上报的时间。敲门在 20:00 取回「14:32 有步数」,
  // 就该从 14:32 起算。
  it('counts from when the evidence happened', () => {
    expect(nextCheckinRemainingMinutes('2026-08-20T06:00:00Z', 12 * 60, now)).toBe(360)
  })

  it('resets to full when fresh evidence arrives', () => {
    expect(nextCheckinRemainingMinutes('2026-08-20T12:00:00Z', 12 * 60, now)).toBe(720)
  })

  it('reports nothing when the account has no liveness yet', () => {
    expect(nextCheckinRemainingMinutes(null, 12 * 60, now)).toBeNull()
  })

  // 本地这份不知道睡眠时段,引擎知道。两边不一致时显示引擎会照着做的那个,
  // 否则界面在凌晨三点写着「现在」,而引擎其实要等到天亮以后才判。
  it('prefers the deadline the engine will actually judge against', () => {
    expect(
      nextCheckinRemainingMinutes('2026-08-20T06:00:00Z', 12 * 60, now, '2026-08-20T20:00:00Z'),
    ).toBe(480)
  })

  it('falls back to clock time when the server sent no deadline', () => {
    expect(nextCheckinRemainingMinutes('2026-08-20T06:00:00Z', 12 * 60, now, null)).toBe(360)
  })

  it('still reports a deadline when liveness is unknown but the server sent one', () => {
    expect(nextCheckinRemainingMinutes(null, 12 * 60, now, '2026-08-20T15:00:00Z')).toBe(180)
  })

  it('never shows seconds', () => {
    expect(formatRemaining(540, true)).toBe('约 9 小时')
    expect(formatRemaining(0, true)).toBe('现在')
  })
})
