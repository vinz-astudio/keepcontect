// 异常沉默判断引擎的类型与配置（完全线下，纯本地）

export type SignalKind = 'interaction' | 'steps' | 'unlock' | 'manual_checkin'

/** 一次"生命迹象"事件（设备本地时序，绝不上传） */
export interface SignalEvent {
  t: number // epoch ms
  kind: SignalKind
}

export type Sensitivity = 'high' | 'balanced' | 'low'

/**
 * 安静窗：
 * - recurring：每周重复（如每晚睡眠），dow 0-6（0=周日），startMin/endMin 为当日分钟数，可跨午夜
 * - oneoff：一次性"安全但不在"，绝对时间区间
 */
export interface QuietWindow {
  kind: 'recurring' | 'oneoff'
  label?: string
  dow?: number
  startMin?: number
  endMin?: number
  start?: number
  end?: number
}

export interface BaselineConfig {
  sensitivity: Sensitivity
  /** 学习期天数（期间不按基线告警，只用冷启动绝对阈值兜底） */
  learningDays: number
  /** 冷启动绝对阈值（小时）：学习期内静默超过即告警，避免裸奔 */
  coldStartGapHours: number
  quietWindows: QuietWindow[]
}

/**
 * Sensitivity is a user-facing adjustment tool, not part of the learned model.
 * The model should output a neutral usual threshold; this preset only decides
 * how much longer to wait before labeling silence as unusual.
 */
export const SENSITIVITY_PRESETS: Record<
  Sensitivity,
  { multiplier: number; bufferHours: number; floorHours: number }
> = {
  high: { multiplier: 1, bufferHours: 0.25, floorHours: 1 },
  balanced: { multiplier: 1, bufferHours: 0.5, floorHours: 2 },
  low: { multiplier: 1, bufferHours: 1.5, floorHours: 3 },
}

export const DEFAULT_CONFIG: BaselineConfig = {
  sensitivity: 'balanced',
  learningDays: 14,
  coldStartGapHours: 12,
  quietWindows: [],
}

export type LivenessStatus = 'normal' | 'learning' | 'alert' | 'safe_window'

export interface Evaluation {
  status: LivenessStatus
  reason: string
  currentGapMs: number
  thresholdMs: number | null
}
