// 判定层（实时、纯统计、可解释）——纯函数，无 IO，便于确定性单测。
// 思路：对比用户自身的"时段感知"作息基线；当前静默时长超过该时段的常态阈值即告警。

import {
  type BaselineConfig,
  type Evaluation,
  type QuietWindow,
  type SignalEvent,
} from '@/features/baseline/types'
import { applySensitivityToThreshold } from '@/features/baseline/usualModel'

const HOUR = 3_600_000
const DAY = 86_400_000

export interface BaselineModel {
  /** 24 项：以"上一次活动所在小时"为索引的常态最大间隔（ms，取该时段间隔的 90 分位） */
  expectedGapByHour: number[]
  /** 样本不足时的全局回退（90 分位间隔） */
  globalExpectedGap: number
  sampleCount: number
}

export function hourOf(t: number): number {
  return new Date(t).getHours()
}

/** 已排序数组的分位数（p ∈ [0,1]） */
export function percentile(sortedAsc: number[], p: number): number {
  if (sortedAsc.length === 0) return NaN
  const idx = Math.min(sortedAsc.length - 1, Math.floor(p * sortedAsc.length))
  return sortedAsc[idx]
}

/** 由学习期时序构建基线模型 */
export function buildBaseline(events: SignalEvent[]): BaselineModel {
  const ts = events.map((e) => e.t).sort((a, b) => a - b)
  const gapsByHour: number[][] = Array.from({ length: 24 }, () => [])
  const allGaps: number[] = []
  for (let i = 1; i < ts.length; i++) {
    const gap = ts[i] - ts[i - 1]
    if (gap <= 0) continue
    gapsByHour[hourOf(ts[i - 1])].push(gap)
    allGaps.push(gap)
  }
  allGaps.sort((a, b) => a - b)
  const globalExpectedGap = allGaps.length ? percentile(allGaps, 0.9) : 6 * HOUR

  const expectedGapByHour = gapsByHour.map((arr) => {
    if (arr.length < 3) return globalExpectedGap // 该时段样本不足 → 用全局回退
    return percentile(
      [...arr].sort((a, b) => a - b),
      0.9,
    )
  })

  return { expectedGapByHour, globalExpectedGap, sampleCount: allGaps.length }
}

/** 当前时刻是否落在某安静窗内 */
export function isInQuietWindow(
  now: number,
  windows: QuietWindow[],
): QuietWindow | null {
  const d = new Date(now)
  const dow = d.getDay()
  const min = d.getHours() * 60 + d.getMinutes()
  for (const w of windows) {
    if (w.kind === 'oneoff' && w.start != null && w.end != null) {
      if (now >= w.start && now <= w.end) return w
    } else if (
      w.kind === 'recurring' &&
      w.dow != null &&
      w.startMin != null &&
      w.endMin != null
    ) {
      if (dow !== w.dow) continue
      if (w.startMin <= w.endMin) {
        if (min >= w.startMin && min < w.endMin) return w
      } else {
        // 跨午夜
        if (min >= w.startMin || min < w.endMin) return w
      }
    }
  }
  return null
}

/** 最近一次活动时间（无事件则回退到安装时间） */
export function lastActivityAt(events: SignalEvent[], installedAt: number): number {
  let last = installedAt
  for (const e of events) if (e.t > last) last = e.t
  return last
}

/**
 * 核心判定：返回当前生命迹象状态。
 * - 安静窗内 → safe_window（不告警）
 * - 学习期内 → learning，但超过冷启动绝对阈值仍 alert（防裸奔）
 * - 学习期后 → 按时段基线阈值判定 normal / alert
 */
export function evaluate(
  events: SignalEvent[],
  now: number,
  config: BaselineConfig,
  installedAt: number,
  model?: BaselineModel,
): Evaluation {
  const qw = isInQuietWindow(now, config.quietWindows)
  if (qw) {
    return {
      status: 'safe_window',
      reason: qw.label ?? '安全但不在时段',
      currentGapMs: 0,
      thresholdMs: null,
    }
  }

  const lastT = lastActivityAt(events, installedAt)
  const currentGapMs = now - lastT
  const coldStartMs = config.coldStartGapHours * HOUR
  const inLearning = now - installedAt < config.learningDays * DAY

  if (inLearning) {
    if (currentGapMs > coldStartMs) {
      return {
        status: 'alert',
        reason: `学习期内静默超过 ${config.coldStartGapHours} 小时（冷启动保底）`,
        currentGapMs,
        thresholdMs: coldStartMs,
      }
    }
    return {
      status: 'learning',
      reason: '正在学习你的作息',
      currentGapMs,
      thresholdMs: coldStartMs,
    }
  }

  const m = model ?? buildBaseline(events)
  const expected = m.expectedGapByHour[hourOf(lastT)] || m.globalExpectedGap
  const thresholdMs = applySensitivityToThreshold(expected / HOUR, config.sensitivity) * HOUR

  if (currentGapMs > thresholdMs) {
    return {
      status: 'alert',
      reason: '与日常作息不符的异常沉默',
      currentGapMs,
      thresholdMs,
    }
  }
  return { status: 'normal', reason: '一切正常', currentGapMs, thresholdMs }
}
