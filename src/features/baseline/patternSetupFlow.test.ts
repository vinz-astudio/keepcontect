import { describe, expect, it } from 'vitest'
import {
  getPatternSetupActiveIndex,
  getPatternSetupIntro,
  getPatternSetupSteps,
  getPatternSetupText,
  patternsMatch,
  shouldShowSosAction,
} from './patternSetupFlow'

describe('pattern setup flow', () => {
  it('shows verify, new pattern, and confirm steps when an old pattern exists', () => {
    expect(getPatternSetupSteps(true, 'en')).toEqual([
      { key: 'verify', label: 'Verify' },
      { key: 'draw', label: 'Create' },
      { key: 'confirm', label: 'Confirm' },
    ])
    expect(getPatternSetupActiveIndex(true, 'draw')).toBe(1)
  })

  it('starts directly at new pattern and confirm when no old pattern exists', () => {
    expect(getPatternSetupSteps(false, 'en')).toEqual([
      { key: 'draw', label: 'Create' },
      { key: 'confirm', label: 'Confirm' },
    ])
    expect(getPatternSetupActiveIndex(false, 'draw')).toBe(0)
  })

  it('gives explicit step text so users know what to draw now', () => {
    expect(getPatternSetupText('verify', 'en').body).toBe(
      'Draw your current pattern to continue.',
    )
    expect(getPatternSetupText('draw', 'en').body).toBe(
      'Connect at least 4 dots.',
    )
    expect(getPatternSetupText('confirm', 'en').body).toBe(
      'Draw it again to confirm.',
    )
  })

  it('uses a short general safety explanation for first-time setup', () => {
    expect(getPatternSetupIntro(false, 'en')).toBe(
      'Create an unlock pattern used to confirm you are safe.',
    )
    expect(getPatternSetupIntro(true, 'en')).toBe(
      'Change the unlock pattern used to confirm you are safe.',
    )
  })

  it('hides SOS actions on pattern setup screens', () => {
    expect(shouldShowSosAction({ isPatternSetup: true })).toBe(false)
    expect(shouldShowSosAction({ isPatternSetup: false })).toBe(true)
  })

  it('compares confirmation patterns by exact sequence', () => {
    expect(patternsMatch([0, 1, 2, 5], [0, 1, 2, 5])).toBe(true)
    expect(patternsMatch([0, 1, 2, 5], [0, 1, 5, 2])).toBe(false)
    expect(patternsMatch([0, 1, 2, 5], [0, 1, 2])).toBe(false)
  })
})
