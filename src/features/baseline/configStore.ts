// 本地配置存储（localStorage）：灵敏度、安静窗、安装时间（学习期起点）。

import {
  DEFAULT_CONFIG,
  type BaselineConfig,
  type QuietWindow,
  type Sensitivity,
} from '@/features/baseline/types'

const KEY_CONFIG = 'kc.baselineConfig'
const KEY_INSTALLED = 'kc.installedAt'

export function getInstalledAt(): number {
  const raw = localStorage.getItem(KEY_INSTALLED)
  if (raw) return Number(raw)
  const now = Date.now()
  localStorage.setItem(KEY_INSTALLED, String(now))
  return now
}

export function getConfig(): BaselineConfig {
  const raw = localStorage.getItem(KEY_CONFIG)
  if (!raw) return { ...DEFAULT_CONFIG }
  try {
    return { ...DEFAULT_CONFIG, ...(JSON.parse(raw) as Partial<BaselineConfig>) }
  } catch {
    return { ...DEFAULT_CONFIG }
  }
}

export function setConfig(cfg: BaselineConfig): void {
  localStorage.setItem(KEY_CONFIG, JSON.stringify(cfg))
}

export function setSensitivity(s: Sensitivity): BaselineConfig {
  const cfg = { ...getConfig(), sensitivity: s }
  setConfig(cfg)
  return cfg
}

export function addQuietWindow(w: QuietWindow): BaselineConfig {
  const cfg = getConfig()
  const next = { ...cfg, quietWindows: [...cfg.quietWindows, w] }
  setConfig(next)
  return next
}

export function removeQuietWindow(index: number): BaselineConfig {
  const cfg = getConfig()
  const next = {
    ...cfg,
    quietWindows: cfg.quietWindows.filter((_, i) => i !== index),
  }
  setConfig(next)
  return next
}
