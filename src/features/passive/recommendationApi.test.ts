import { describe, expect, it } from 'vitest'
import { parsePassiveRecommendation } from './recommendationApi'

describe('account reference parsing', () => {
  it('reads the three fields the gate depends on', () => {
    expect(
      parsePassiveRecommendation({
        evidence_days: 42,
        reference_minutes: 540,
        source_confidence: 'medium',
        // 服务端还返回十几个字段,这里只取门槛用得到的三个。
        proposed_interval_minutes: 120,
      }),
    ).toEqual({ evidenceDays: 42, confidence: 'medium', referenceMinutes: 540 })
  })

  it('returns nothing when the account has no reference yet', () => {
    expect(parsePassiveRecommendation(null)).toBeNull()
  })

  // 半个建议比没有建议更危险:缺了 evidence_days 就无从判断这是不是「您的数据」。
  it('refuses a half-filled row rather than guessing the missing half', () => {
    expect(parsePassiveRecommendation({ reference_minutes: 540, source_confidence: 'high' }))
      .toBeNull()
    expect(parsePassiveRecommendation({ evidence_days: 42, source_confidence: 'high' })).toBeNull()
    expect(parsePassiveRecommendation({ evidence_days: 42, reference_minutes: 540 })).toBeNull()
  })

  it('refuses a reference of zero minutes', () => {
    expect(
      parsePassiveRecommendation({
        evidence_days: 42,
        reference_minutes: 0,
        source_confidence: 'high',
      }),
    ).toBeNull()
  })
})
