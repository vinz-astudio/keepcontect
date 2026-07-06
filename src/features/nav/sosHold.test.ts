import { describe, expect, it } from 'vitest'
import { shouldShowSosHoldHint } from '@/features/nav/sosHold'

describe('SOS hold feedback', () => {
  it('shows the hold hint when the user taps or releases before SOS fires', () => {
    expect(shouldShowSosHoldHint({ started: true, fired: false })).toBe(true)
  })

  it('does not show the hint after a completed SOS hold', () => {
    expect(shouldShowSosHoldHint({ started: true, fired: true })).toBe(false)
  })

  it('does not show the hint for a cancelled pointer that never started', () => {
    expect(shouldShowSosHoldHint({ started: false, fired: false })).toBe(false)
  })
})
