// P5 (ADR-0029): derive the user-facing learning state from REAL server evidence.
//
// Before P5 the UI derived "learning progress" from `(now - installedAt) / DAY`
// and, after 14 calendar days, told the user 「已建立作息基线」 — while no baseline
// existed anywhere and nothing influenced alerting. This module replaces that with
// the adaptive pipeline's own support counters, and it is deliberately the ONLY
// place allowed to conclude that a personal baseline exists.

/** `alert_gap_profiles.quality_state`, or null when the user has no profile row yet. */
export type EvidenceQualityState = 'valid' | 'low_support' | 'stale' | null

export interface LearningEvidence {
  /** A shadow model version is registered and enabled; without it nothing learns. */
  learningActive: boolean
  /** Qualified inter-session gaps observed for this user. */
  sampleCount: number | null
  /** Distinct local dates contributing evidence. */
  supportDays: number | null
  /** `personal.min_support_dates` from the active model config. */
  minSupportDays: number | null
  qualityState: EvidenceQualityState
  confidence: number | null
}

export type LearningStateKind =
  | 'inactive'
  | 'collecting'
  | 'low_support'
  | 'established'
  | 'stale'

export interface LearningState {
  kind: LearningStateKind
  supportDays: number
  sampleCount: number
  minSupportDays: number
  /** 0..1, for the progress bar. Never fabricated from elapsed calendar time. */
  progress: number
  confidence: number
}

/** Non-finite, negative, or missing values all mean "no evidence", not "unknown". */
function count(value: number | null | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return 0
  return value
}

function clamp01(value: number): number {
  if (!Number.isFinite(value) || value < 0) return 0
  return value > 1 ? 1 : value
}

export function deriveLearningState(evidence: LearningEvidence): LearningState {
  const supportDays = count(evidence.supportDays)
  const sampleCount = count(evidence.sampleCount)
  const minSupportDays = count(evidence.minSupportDays)
  const confidence = clamp01(count(evidence.confidence))

  const empty: LearningState = {
    kind: 'inactive',
    supportDays: 0,
    sampleCount: 0,
    minSupportDays,
    progress: 0,
    confidence: 0,
  }

  if (!evidence.learningActive) return empty

  // A baseline may be claimed only on the pipeline's own 'valid' verdict.
  if (evidence.qualityState === 'valid') {
    return {
      kind: 'established',
      supportDays,
      sampleCount,
      minSupportDays,
      progress: 1,
      confidence,
    }
  }

  const progress = minSupportDays > 0 ? clamp01(supportDays / minSupportDays) : 0

  if (evidence.qualityState === 'stale') {
    return { kind: 'stale', supportDays, sampleCount, minSupportDays, progress, confidence }
  }

  return {
    // No profile row yet vs. a row that exists but is under-supported.
    kind: evidence.qualityState === 'low_support' ? 'low_support' : 'collecting',
    supportDays,
    sampleCount,
    minSupportDays,
    progress,
    confidence,
  }
}
