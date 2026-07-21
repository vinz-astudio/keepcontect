import { describe, expect, it } from 'vitest'
import {
  applySensitivityToThreshold,
  buildUsualBehaviorModel,
} from '@/features/baseline/usualModel'
import type { SignalEvent } from '@/features/baseline/types'

const HOUR = 3_600_000
const MIN = 60_000

function midnight(dayOffset: number): number {
  return new Date(2025, 0, 1 + dayOffset, 0, 0, 0, 0).getTime()
}

function activeHistory(days: number): SignalEvent[] {
  const events: SignalEvent[] = []
  for (let d = 0; d < days; d++) {
    const base = midnight(d)
    for (let m = 8 * 60; m <= 22 * 60; m += 30) {
      events.push({ t: base + m * MIN, kind: 'interaction' })
    }
  }
  return events
}

describe('buildUsualBehaviorModel', () => {
  it('builds neutral active-hour thresholds and confidence from long behavior history', () => {
    const model = buildUsualBehaviorModel(activeHistory(45), { timeZone: 'UTC' })

    expect(model.sampleCount).toBeGreaterThan(1_000)
    expect(model.modelConfidence).toBeGreaterThan(0.8)
    expect(model.gapStatsByHour[14]?.p90Hours).toBeCloseTo(0.5, 1)
    expect(model.hourlyThresholds[14]).toBeGreaterThanOrEqual(1)
    expect(model.hourlyThresholds[14]).toBeLessThanOrEqual(1.5)
    expect(model.hourlyConfidence[14]).toBeGreaterThan(0.8)
    expect(model.explanation).toContain('45d')
  })

  it('keeps sensitivity as a tool applied after the neutral model threshold', () => {
    const baseHours = 1.25

    const sensitive = applySensitivityToThreshold(baseHours, 'high')
    const balanced = applySensitivityToThreshold(baseHours, 'balanced')
    const relaxed = applySensitivityToThreshold(baseHours, 'low')

    expect(sensitive).toBeLessThanOrEqual(baseHours + 0.25)
    expect(balanced).toBeGreaterThan(sensitive)
    expect(relaxed).toBeGreaterThan(balanced)
    expect(relaxed).toBeLessThan(4)
    expect(relaxed).toBeGreaterThanOrEqual(3)
  })

  it('applies the displayed +0m/+45m/+90m contract to the 1.5h neutral Gate 1 base', () => {
    const baseHours = 1.5

    expect(applySensitivityToThreshold(baseHours, 'high')).toBe(1.5)
    expect(applySensitivityToThreshold(baseHours, 'balanced')).toBe(2.25)
    expect(applySensitivityToThreshold(baseHours, 'low')).toBe(3)
  })

  it('uses low confidence when there are too few behavior samples', () => {
    const model = buildUsualBehaviorModel([
      { t: midnight(0) + 8 * HOUR, kind: 'interaction' },
      { t: midnight(0) + 9 * HOUR, kind: 'interaction' },
    ])

    expect(model.sampleCount).toBe(1)
    expect(model.modelConfidence).toBeLessThan(0.2)
    expect(model.hourlyThresholds).toHaveLength(24)
  })
})
