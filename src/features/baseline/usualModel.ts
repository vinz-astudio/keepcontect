import type { Sensitivity, SignalEvent } from '@/features/baseline/types'
import { SENSITIVITY_PRESETS } from '@/features/baseline/types'

const HOUR = 3_600_000
const DAY = 86_400_000

export interface HourGapStats {
  samples: number
  p50Hours: number
  p75Hours: number
  p90Hours: number
  p95Hours: number
}

export interface UsualBehaviorModel {
  hourlyThresholds: number[]
  hourlyConfidence: number[]
  gapStatsByHour: Array<HourGapStats | null>
  sampleCount: number
  modelConfidence: number
  explanation: string
}

export interface UsualBehaviorOptions {
  timeZone?: string
  maxModeledGapHours?: number
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value))
}

function percentile(sortedAsc: number[], p: number): number {
  if (sortedAsc.length === 0) return 0
  const index = Math.min(sortedAsc.length - 1, Math.floor(p * sortedAsc.length))
  return sortedAsc[index]
}

function localHour(atMs: number, timeZone?: string): number {
  if (!timeZone) return new Date(atMs).getHours()
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hour: 'numeric',
      hour12: false,
    }).formatToParts(new Date(atMs))
    const hour = Number(parts.find((part) => part.type === 'hour')?.value)
    return Number.isFinite(hour) ? hour % 24 : new Date(atMs).getUTCHours()
  } catch {
    return new Date(atMs).getHours()
  }
}

export function applySensitivityToThreshold(
  baseHours: number,
  sensitivity: Sensitivity,
): number {
  const preset = SENSITIVITY_PRESETS[sensitivity]
  return clamp(
    Math.max(baseHours * preset.multiplier + preset.bufferHours, preset.floorHours),
    1,
    12,
  )
}

export function buildUsualBehaviorModel(
  events: SignalEvent[],
  options: UsualBehaviorOptions = {},
): UsualBehaviorModel {
  const maxModeledGapHours = options.maxModeledGapHours ?? 12
  const timestamps = events
    .map((event) => event.t)
    .filter((t) => Number.isFinite(t))
    .sort((a, b) => a - b)
  const buckets = Array.from({ length: 24 }, () => [] as number[])

  for (let i = 1; i < timestamps.length; i++) {
    const prev = timestamps[i - 1]
    const curr = timestamps[i]
    const gapHours = (curr - prev) / HOUR
    if (gapHours <= 0 || gapHours > maxModeledGapHours) continue
    buckets[localHour(prev, options.timeZone)].push(gapHours)
  }

  const allGaps = buckets.flat().sort((a, b) => a - b)
  const globalP90 = allGaps.length > 0 ? percentile(allGaps, 0.9) : 6
  const gapStatsByHour = buckets.map((bucket): HourGapStats | null => {
    if (bucket.length === 0) return null
    const sorted = [...bucket].sort((a, b) => a - b)
    return {
      samples: sorted.length,
      p50Hours: percentile(sorted, 0.5),
      p75Hours: percentile(sorted, 0.75),
      p90Hours: percentile(sorted, 0.9),
      p95Hours: percentile(sorted, 0.95),
    }
  })

  const hourlyThresholds = gapStatsByHour.map((stats) => {
    const p90 = stats?.p90Hours ?? globalP90
    return clamp(Math.max(1, p90 * 1.8), 1, 12)
  })
  const hourlyConfidence = gapStatsByHour.map((stats) =>
    stats ? clamp(stats.samples / 30, 0.05, 1) : 0,
  )
  const sampleCount = allGaps.length
  const modelConfidence = clamp(sampleCount / 1_000, 0, 1)
  const spanDays =
    timestamps.length >= 2
      ? Math.max(1, Math.round((timestamps[timestamps.length - 1] - timestamps[0]) / DAY))
      : 0

  return {
    hourlyThresholds,
    hourlyConfidence,
    gapStatsByHour,
    sampleCount,
    modelConfidence,
    explanation:
      sampleCount > 0
        ? `${spanDays}d behavior model from ${sampleCount} sub-${maxModeledGapHours}h gaps`
        : 'No behavior gaps available yet',
  }
}
