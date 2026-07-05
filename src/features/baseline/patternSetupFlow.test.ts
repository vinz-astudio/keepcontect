import { describe, expect, it } from 'vitest'
import {
  getPatternSetupActiveIndex,
  getPatternSetupSteps,
  getPatternSetupText,
  patternsMatch,
} from './patternSetupFlow'

describe('pattern setup flow', () => {
  it('shows verify, new pattern, and confirm steps when an old pattern exists', () => {
    expect(getPatternSetupSteps(true, 'en')).toEqual([
      { key: 'verify', label: 'Verify current' },
      { key: 'draw', label: 'New pattern' },
      { key: 'confirm', label: 'Confirm' },
    ])
    expect(getPatternSetupActiveIndex(true, 'draw')).toBe(1)
  })

  it('starts directly at new pattern and confirm when no old pattern exists', () => {
    expect(getPatternSetupSteps(false, 'en')).toEqual([
      { key: 'draw', label: 'New pattern' },
      { key: 'confirm', label: 'Confirm' },
    ])
    expect(getPatternSetupActiveIndex(false, 'draw')).toBe(0)
  })

  it('gives explicit step text so users know what to draw now', () => {
    expect(getPatternSetupText('verify', 'en').body).toBe(
      'First draw your current pattern. This only verifies it is you; it will not change the saved pattern.',
    )
    expect(getPatternSetupText('draw', 'en').body).toBe(
      'Now draw the new pattern you want to use.',
    )
    expect(getPatternSetupText('confirm', 'en').body).toBe(
      'Draw the same new pattern once more to save it.',
    )
  })

  it('compares confirmation patterns by exact sequence', () => {
    expect(patternsMatch([0, 1, 2, 5], [0, 1, 2, 5])).toBe(true)
    expect(patternsMatch([0, 1, 2, 5], [0, 1, 5, 2])).toBe(false)
    expect(patternsMatch([0, 1, 2, 5], [0, 1, 2])).toBe(false)
  })
})
