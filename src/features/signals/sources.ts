// 信号源：优雅降级。
// - Web/通用保底：App 互动（可见/聚焦/触摸）——浏览器与双端均可用。
// - 原生加分（需真机，待接 Capacitor 插件）：运动/步数（Health）、Android 解锁事件。
//   这些通过同一 record 回调汇入本地时序；未接入的平台自动跳过。

import { Capacitor } from '@capacitor/core'
import type { SignalKind } from '@/features/baseline/types'

type Recorder = (kind: SignalKind) => void

const ACTIVITY_THROTTLE_MS = 5 * 60_000 // 同类互动信号最多 5 分钟记一次，避免刷量

/** App 互动信号（保底，双端通用） */
function startWebInteractionSource(record: Recorder): () => void {
  let last = 0
  const onActive = () => {
    if (document.visibilityState !== 'visible') return
    const now = Date.now()
    if (now - last < ACTIVITY_THROTTLE_MS) return
    last = now
    record('interaction')
  }
  const onVisible = () => {
    if (document.visibilityState === 'visible') onActive()
  }
  document.addEventListener('visibilitychange', onVisible)
  window.addEventListener('focus', onActive)
  window.addEventListener('pointerdown', onActive)
  onActive() // 启动即记一次（App 被打开本身就是生命迹象）

  return () => {
    document.removeEventListener('visibilitychange', onVisible)
    window.removeEventListener('focus', onActive)
    window.removeEventListener('pointerdown', onActive)
  }
}

/**
 * 原生加分信号占位：运动/步数、Android 解锁。
 * 需安装并接入对应 Capacitor 插件后实现；当前在原生平台先返回空清理函数。
 * TODO(P2-native): 接 @capacitor/health 或社区步数插件；Android 自定义解锁广播插件。
 */
function startNativeSources(_record: Recorder): () => void {
  // 占位：保持架构完整，真机接入后在此 record('steps') / record('unlock')
  return () => {}
}

/** 启动所有可用信号源，返回统一的停止函数 */
export function startSignalSources(record: Recorder): () => void {
  const stops: Array<() => void> = []
  stops.push(startWebInteractionSource(record))
  if (Capacitor.isNativePlatform()) {
    stops.push(startNativeSources(record))
  }
  return () => stops.forEach((s) => s())
}
