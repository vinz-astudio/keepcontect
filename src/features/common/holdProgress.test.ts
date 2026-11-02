import { describe, expect, it } from 'vitest'
import { SAFE_HOLD_MS, holdProgress } from './holdProgress'

describe('hold progress', () => {
  it('runs from 0 to 100 over the hold duration', () => {
    expect(holdProgress(1000, 1000, 3000)).toBe(0)
    expect(holdProgress(1000, 2500, 3000)).toBe(50)
    expect(holdProgress(1000, 4000, 3000)).toBe(100)
  })
  it('clamps and treats a missing start as no progress', () => {
    expect(holdProgress(null, 4000, 3000)).toBe(0)
    expect(holdProgress(5000, 4000, 3000)).toBe(0)
    expect(holdProgress(1000, 9000, 3000)).toBe(100)
    expect(holdProgress(1000, 2000, 0)).toBe(0)
  })
  it('asks for a three-second hold on "一切安好" (human decision 2026-11-02)', () => {
    expect(SAFE_HOLD_MS).toBe(3000)
  })
})
