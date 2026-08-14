import { supabase } from '@/lib/supabase'

export type PassiveRecommendationConfidence = 'insufficient' | 'low' | 'medium' | 'high'

export interface PassiveRecommendation {
  id: string
  revisionNumber: number
  estimatorVersion: string
  configVersion: string
  eligibleEpisodeCount: number
  evidenceDays: number
  excludedCounts: Record<string, number>
  sourceConfidence: PassiveRecommendationConfidence
  referenceMinutes: number
  proposedIntervalMinutes: number
  proposedConsecutiveMisses: number
  proposedHorizonMinutes: number
  platformDFloorMinutes: number
  platformHFloorMinutes: number
  platformFloorBasis: string[]
  expectedInterruptionsPerDay: number
  generatedAt: string
}

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function positiveInteger(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? value : null
}

function nonNegativeInteger(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : null
}

export function parsePassiveRecommendation(value: unknown): PassiveRecommendation | null {
  if (value === null) return null
  const raw = object(value)
  if (!raw) throw new Error('Invalid passive check-in recommendation')
  const confidence = raw.source_confidence
  const excluded = object(raw.excluded_counts)
  const basis = raw.platform_floor_basis
  const expected = raw.expected_interruptions_per_day
  const generatedAt = raw.generated_at
  const parsed: PassiveRecommendation = {
    id: typeof raw.id === 'string' ? raw.id : '',
    revisionNumber: positiveInteger(raw.revision_number) ?? 0,
    estimatorVersion: typeof raw.estimator_version === 'string' ? raw.estimator_version : '',
    configVersion: typeof raw.config_version === 'string' ? raw.config_version : '',
    eligibleEpisodeCount: nonNegativeInteger(raw.eligible_episode_count) ?? -1,
    evidenceDays: nonNegativeInteger(raw.evidence_days) ?? -1,
    excludedCounts: {},
    sourceConfidence: confidence as PassiveRecommendationConfidence,
    referenceMinutes: positiveInteger(raw.reference_minutes) ?? 0,
    proposedIntervalMinutes: positiveInteger(raw.proposed_interval_minutes) ?? 0,
    proposedConsecutiveMisses: positiveInteger(raw.proposed_consecutive_misses) ?? 0,
    proposedHorizonMinutes: positiveInteger(raw.proposed_horizon_minutes) ?? 0,
    platformDFloorMinutes: positiveInteger(raw.platform_d_floor_minutes) ?? 0,
    platformHFloorMinutes: positiveInteger(raw.platform_h_floor_minutes) ?? 0,
    platformFloorBasis: Array.isArray(basis) && basis.every((item) => typeof item === 'string') ? basis : [],
    expectedInterruptionsPerDay: typeof expected === 'number' && Number.isFinite(expected) && expected >= 0 ? expected : -1,
    generatedAt: typeof generatedAt === 'string' ? generatedAt : '',
  }
  if (excluded) {
    for (const [key, count] of Object.entries(excluded)) {
      if (!Number.isSafeInteger(count) || (count as number) < 0) throw new Error('Invalid passive check-in recommendation')
      parsed.excludedCounts[key] = count as number
    }
  }
  if (
    !parsed.id || !parsed.estimatorVersion || !parsed.configVersion
    || !['insufficient', 'low', 'medium', 'high'].includes(String(confidence))
    || parsed.revisionNumber < 1 || parsed.eligibleEpisodeCount < 0 || parsed.evidenceDays < 0
    || parsed.referenceMinutes < 1
    || parsed.proposedIntervalMinutes < 20 || parsed.proposedIntervalMinutes > 360
    || parsed.proposedConsecutiveMisses < 1 || parsed.proposedConsecutiveMisses > 1_000_000
    || parsed.proposedHorizonMinutes !== parsed.proposedIntervalMinutes * parsed.proposedConsecutiveMisses
    || parsed.platformDFloorMinutes < 1 || parsed.platformHFloorMinutes < 1
    || parsed.platformFloorBasis.length === 0 || parsed.expectedInterruptionsPerDay < 0
    || !parsed.generatedAt || Number.isNaN(Date.parse(parsed.generatedAt))
  ) throw new Error('Invalid passive check-in recommendation')
  return parsed
}

export function explainPassiveRecommendation(recommendation: PassiveRecommendation, lang: 'zh' | 'en' = 'zh'): string[] {
  const messages = recommendation.sourceConfidence === 'insufficient'
    ? [lang === 'zh' ? '活动历史不足，当前建议使用保守默认值。' : 'Activity history is insufficient, so this uses a conservative default.']
    : [lang === 'zh'
        ? `根据 ${recommendation.evidenceDays} 天、${recommendation.eligibleEpisodeCount} 段有效活动间隔生成。`
        : `Based on ${recommendation.evidenceDays} days and ${recommendation.eligibleEpisodeCount} eligible activity gaps.`]
  if (
    recommendation.proposedIntervalMinutes > recommendation.referenceMinutes
    || recommendation.proposedHorizonMinutes > recommendation.referenceMinutes
  ) messages.push(lang === 'zh'
    ? '已按当前设备能力下限放宽，避免把平台限制误判为失联。'
    : 'Raised to the current device floor so platform limits are not mistaken for lost contact.')
  messages.push(lang === 'zh'
    ? `预计每天最多约 ${recommendation.expectedInterruptionsPerDay.toFixed(1)} 个检查窗口。`
    : `About ${recommendation.expectedInterruptionsPerDay.toFixed(1)} check-in windows per day.`)
  return messages
}

export async function getPassiveCheckinRecommendation(): Promise<PassiveRecommendation | null> {
  const { data, error } = await supabase.rpc('my_passive_checkin_recommendation')
  if (error) throw error
  return parsePassiveRecommendation(data)
}
