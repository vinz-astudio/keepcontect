import { describe, expect, it } from 'vitest'
import { deriveLearningState, type LearningEvidence } from './learningState'

const base: LearningEvidence = {
  learningActive: true,
  sampleCount: null,
  supportDays: null,
  minSupportDays: 7,
  qualityState: null,
  confidence: null,
}

describe('deriveLearningState', () => {
  it('reports inactive when no shadow model version is enabled', () => {
    const state = deriveLearningState({ ...base, learningActive: false })
    expect(state.kind).toBe('inactive')
    expect(state.progress).toBe(0)
  })

  it('reports collecting when no profile row exists yet', () => {
    const state = deriveLearningState(base)
    expect(state.kind).toBe('collecting')
    expect(state.supportDays).toBe(0)
    expect(state.sampleCount).toBe(0)
    expect(state.progress).toBe(0)
  })

  it('reports low_support and keeps partial progress', () => {
    const state = deriveLearningState({
      ...base,
      qualityState: 'low_support',
      supportDays: 3,
      sampleCount: 12,
      confidence: 0.42,
    })
    expect(state.kind).toBe('low_support')
    expect(state.supportDays).toBe(3)
    expect(state.progress).toBeCloseTo(3 / 7)
  })

  it('reports established only when quality_state is valid', () => {
    const state = deriveLearningState({
      ...base,
      qualityState: 'valid',
      supportDays: 9,
      sampleCount: 46,
      confidence: 0.88,
    })
    expect(state.kind).toBe('established')
    expect(state.progress).toBe(1)
    expect(state.confidence).toBeCloseTo(0.88)
  })

  it('reports stale when evidence aged out', () => {
    const state = deriveLearningState({
      ...base,
      qualityState: 'stale',
      supportDays: 11,
      sampleCount: 60,
      confidence: 0,
    })
    expect(state.kind).toBe('stale')
  })

  // Regression guard for the pre-P5 bug: the UI claimed "已建立作息基线" purely
  // because 14 calendar days had passed since signup, with no evidence at all.
  it('never claims an established baseline without valid evidence', () => {
    const notValid: Array<LearningEvidence['qualityState']> = [
      null,
      'low_support',
      'stale',
    ]
    for (const qualityState of notValid) {
      const state = deriveLearningState({
        ...base,
        qualityState,
        supportDays: 9999,
        sampleCount: 9999,
        confidence: 1,
      })
      expect(state.kind).not.toBe('established')
    }
  })

  it('clamps progress into [0,1] and tolerates a missing/zero threshold', () => {
    const over = deriveLearningState({
      ...base,
      qualityState: 'low_support',
      supportDays: 40,
      sampleCount: 5,
    })
    expect(over.progress).toBe(1)

    const noThreshold = deriveLearningState({
      ...base,
      minSupportDays: 0,
      qualityState: 'low_support',
      supportDays: 4,
      sampleCount: 5,
    })
    expect(noThreshold.progress).toBe(0)
  })

  it('treats negative or non-finite inputs as absent', () => {
    const state = deriveLearningState({
      ...base,
      qualityState: 'low_support',
      supportDays: -3,
      sampleCount: Number.NaN,
    })
    expect(state.supportDays).toBe(0)
    expect(state.sampleCount).toBe(0)
    expect(state.progress).toBe(0)
  })
})
