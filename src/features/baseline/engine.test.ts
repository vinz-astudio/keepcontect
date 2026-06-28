import { describe, expect, it } from 'vitest'
import {
  buildBaseline,
  evaluate,
  hourOf,
  isInQuietWindow,
  percentile,
} from '@/features/baseline/engine'
import {
  DEFAULT_CONFIG,
  type BaselineConfig,
  type SignalEvent,
} from '@/features/baseline/types'

const HOUR = 3_600_000
const MIN = 60_000

// 用本地时间构造，保证引擎(本地 getHours/getDay)与测试一致、不依赖时区
function midnight(dayOffset: number): number {
  return new Date(2025, 0, 1 + dayOffset, 0, 0, 0, 0).getTime()
}

// 典型作息：每天 08:00–22:00 每 30 分钟一次活动；夜间无活动（睡眠）
function genDay(dayOffset: number): SignalEvent[] {
  const base = midnight(dayOffset)
  const out: SignalEvent[] = []
  for (let m = 8 * 60; m <= 22 * 60; m += 30) {
    out.push({ t: base + m * MIN, kind: 'interaction' })
  }
  return out
}

function genHistory(days: number): SignalEvent[] {
  const out: SignalEvent[] = []
  for (let d = 0; d < days; d++) out.push(...genDay(d))
  return out
}

describe('工具函数', () => {
  it('percentile 取分位', () => {
    expect(percentile([1, 2, 3, 4, 5], 0.9)).toBe(5)
    expect(percentile([], 0.5)).toBeNaN()
  })
  it('hourOf 返回本地小时', () => {
    expect(hourOf(new Date(2025, 0, 1, 14, 30).getTime())).toBe(14)
  })
})

describe('安静窗', () => {
  it('一次性区间命中', () => {
    const now = new Date(2025, 0, 1, 20, 0).getTime()
    const w = isInQuietWindow(now, [
      { kind: 'oneoff', start: now - HOUR, end: now + HOUR, label: '看电影' },
    ])
    expect(w?.label).toBe('看电影')
  })
  it('每周重复且跨午夜（睡眠 23:00–07:00）', () => {
    const night = new Date(2025, 0, 1, 2, 0) // 周三 02:00
    const w = isInQuietWindow(night.getTime(), [
      { kind: 'recurring', dow: night.getDay(), startMin: 23 * 60, endMin: 7 * 60 },
    ])
    expect(w).not.toBeNull()
  })
  it('窗外不命中', () => {
    const noon = new Date(2025, 0, 1, 12, 0).getTime()
    expect(
      isInQuietWindow(noon, [
        { kind: 'recurring', dow: 3, startMin: 23 * 60, endMin: 7 * 60 },
      ]),
    ).toBeNull()
  })
})

describe('学习期', () => {
  const cfg: BaselineConfig = { ...DEFAULT_CONFIG }
  it('学习期内、静默在冷启动阈值内 → learning', () => {
    const installedAt = midnight(0)
    const now = new Date(2025, 0, 6, 12, 0).getTime() // 第 5 天
    const events: SignalEvent[] = [{ t: now - 1 * HOUR, kind: 'interaction' }]
    expect(evaluate(events, now, cfg, installedAt).status).toBe('learning')
  })
  it('学习期内、静默超过冷启动阈值 → alert（防裸奔）', () => {
    const installedAt = midnight(0)
    const now = new Date(2025, 0, 6, 12, 0).getTime()
    const events: SignalEvent[] = [{ t: now - 13 * HOUR, kind: 'interaction' }]
    const e = evaluate(events, now, cfg, installedAt)
    expect(e.status).toBe('alert')
    expect(e.reason).toContain('冷启动')
  })
})

describe('基线判定（学习期后）', () => {
  const installedAt = midnight(0)
  const history = genHistory(20)
  const cfg: BaselineConfig = { ...DEFAULT_CONFIG } // balanced

  it('白天近期有活动 → normal', () => {
    const events = [...history, { t: new Date(2025, 0, 21, 14, 0).getTime(), kind: 'interaction' as const }]
    const now = new Date(2025, 0, 21, 15, 0).getTime() // 距上次 1h
    expect(evaluate(events, now, cfg, installedAt).status).toBe('normal')
  })

  it('白天长时间静默 → alert', () => {
    const events = [...history, { t: new Date(2025, 0, 21, 14, 0).getTime(), kind: 'interaction' as const }]
    const now = new Date(2025, 0, 21, 19, 0).getTime() // 距上次 5h（白天反常）
    expect(evaluate(events, now, cfg, installedAt).status).toBe('alert')
  })

  it('时段感知：同样 5h 静默，夜间起算不告警', () => {
    // 上次活动在 22:00（入睡前），夜间常态间隔很大
    const events = [...history, { t: new Date(2025, 0, 21, 22, 0).getTime(), kind: 'interaction' as const }]
    const now = new Date(2025, 0, 22, 3, 0).getTime() // 距上次 5h，但起算于 22:00
    expect(evaluate(events, now, cfg, installedAt).status).toBe('normal')
  })
})

describe('灵敏度档影响阈值', () => {
  const installedAt = midnight(0)
  const history = genHistory(20)
  const events = [...history, { t: new Date(2025, 0, 21, 14, 0).getTime(), kind: 'interaction' as const }]
  const now = new Date(2025, 0, 21, 19, 0).getTime() // 白天 5h 静默

  it('high 档 → alert', () => {
    expect(
      evaluate(events, now, { ...DEFAULT_CONFIG, sensitivity: 'high' }, installedAt).status,
    ).toBe('alert')
  })
  it('low 档不再用 6h 硬下限 → 5h 明显静默仍可 alert', () => {
    expect(
      evaluate(events, now, { ...DEFAULT_CONFIG, sensitivity: 'low' }, installedAt).status,
    ).toBe('alert')
  })

  it('sensitive 档贴近模型阈值，balanced / relaxed 只作为更长等待工具', () => {
    const recentEvents = [
      ...history,
      { t: new Date(2025, 0, 21, 14, 0).getTime(), kind: 'interaction' as const },
    ]
    const checkAt = new Date(2025, 0, 21, 14, 10).getTime()
    const sensitive = evaluate(
      recentEvents,
      checkAt,
      { ...DEFAULT_CONFIG, sensitivity: 'high' },
      installedAt,
    )
    const balanced = evaluate(
      recentEvents,
      checkAt,
      { ...DEFAULT_CONFIG, sensitivity: 'balanced' },
      installedAt,
    )
    const relaxed = evaluate(
      recentEvents,
      checkAt,
      { ...DEFAULT_CONFIG, sensitivity: 'low' },
      installedAt,
    )

    expect(sensitive.thresholdMs).not.toBeNull()
    expect(sensitive.thresholdMs!).toBeLessThanOrEqual(60 * MIN)
    expect(balanced.thresholdMs!).toBeGreaterThan(sensitive.thresholdMs!)
    expect(relaxed.thresholdMs!).toBeGreaterThan(balanced.thresholdMs!)
  })
})

describe('安静窗抑制告警', () => {
  it('身处安静窗内即使长时间静默也不告警', () => {
    const installedAt = midnight(0)
    const history = genHistory(20)
    const now = new Date(2025, 0, 21, 19, 0).getTime()
    const events = [...history, { t: new Date(2025, 0, 21, 14, 0).getTime(), kind: 'interaction' as const }]
    const cfg: BaselineConfig = {
      ...DEFAULT_CONFIG,
      quietWindows: [{ kind: 'oneoff', start: now - HOUR, end: now + HOUR, label: '健身' }],
    }
    expect(evaluate(events, now, cfg, installedAt).status).toBe('safe_window')
  })
})

describe('buildBaseline', () => {
  it('白天时段常态间隔约 30 分钟、夜间起算时段间隔很大', () => {
    const m = buildBaseline(genHistory(20))
    expect(m.expectedGapByHour[14]).toBeLessThanOrEqual(31 * MIN)
    expect(m.expectedGapByHour[22]).toBeGreaterThan(8 * HOUR)
  })
})
