import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { HOLD_RING_CIRCUMFERENCE, holdRingDashOffset } from './holdRingGeometry'
import { HoldRing } from './HoldRing'

describe('hold ring', () => {
  it('hides the whole stroke at 0 and none of it at 100', () => {
    expect(holdRingDashOffset(0)).toBeCloseTo(HOLD_RING_CIRCUMFERENCE)
    expect(holdRingDashOffset(50)).toBeCloseTo(HOLD_RING_CIRCUMFERENCE / 2)
    expect(holdRingDashOffset(100)).toBe(0)
  })

  it('clamps out-of-range and missing progress', () => {
    expect(holdRingDashOffset(-20)).toBeCloseTo(HOLD_RING_CIRCUMFERENCE)
    expect(holdRingDashOffset(140)).toBe(0)
    expect(holdRingDashOffset(Number.NaN)).toBeCloseTo(HOLD_RING_CIRCUMFERENCE)
  })

  it('starts at 12 o’clock and reports progress to assistive tech', () => {
    const html = renderToStaticMarkup(createElement(HoldRing, { progress: 25, label: 'Hold' }))
    expect(html).toContain('role="progressbar"')
    expect(html).toContain('aria-valuenow="25"')
    // rotate(-90) moves the stroke start from 3 o'clock to 12 o'clock.
    expect(html).toMatch(/transform="rotate\(-90 70 70\)"/)
  })
})
