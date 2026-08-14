import { describe, expect, it } from 'vitest'
import { explainPassiveRecommendation, parsePassiveRecommendation } from './recommendation'

const fixture = {
  id: 'recommendation-1', revision_number: 2, estimator_version: 'passive-gap-b1-v1',
  config_version: 'passive-recommendation-v1', eligible_episode_count: 3, evidence_days: 3,
  excluded_counts: { surface_health: 2 }, source_confidence: 'low', reference_minutes: 240,
  proposed_interval_minutes: 60, proposed_consecutive_misses: 4, proposed_horizon_minutes: 240,
  platform_d_floor_minutes: 35, platform_h_floor_minutes: 120,
  platform_floor_basis: ['android_native'], expected_interruptions_per_day: 6,
  generated_at: '2026-08-15T12:00:00Z',
}

describe('passive recommendation', () => {
  it('parses an advisory response', () => {
    expect(parsePassiveRecommendation(fixture)).toMatchObject({
      sourceConfidence: 'low', referenceMinutes: 240, excludedCounts: { surface_health: 2 },
    })
  })

  it('explains evidence and interruption cost', () => {
    expect(explainPassiveRecommendation(parsePassiveRecommendation(fixture)!)).toEqual([
      '根据 3 天、3 段有效活动间隔生成。', '预计每天最多约 6.0 个检查窗口。',
    ])
  })

  it('labels insufficient, floor-raised advice', () => {
    const parsed = parsePassiveRecommendation({
      ...fixture, source_confidence: 'insufficient', eligible_episode_count: 0, evidence_days: 0,
      reference_minutes: 360, proposed_interval_minutes: 360, proposed_consecutive_misses: 2,
      proposed_horizon_minutes: 720, platform_d_floor_minutes: 360, platform_h_floor_minutes: 720,
      platform_floor_basis: ['pwa_browser'], expected_interruptions_per_day: 2,
    })!
    expect(explainPassiveRecommendation(parsed)).toContain('已按当前设备能力下限放宽，避免把平台限制误判为失联。')
  })

  it('rejects authoritative-shape and arithmetic drift', () => {
    expect(() => parsePassiveRecommendation({ ...fixture, proposed_horizon_minutes: 241 })).toThrow()
    expect(() => parsePassiveRecommendation({ ...fixture, platform_floor_basis: [] })).toThrow()
  })
})
