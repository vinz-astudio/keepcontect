import { useCallback, useEffect, useRef, useState } from 'react'
import {
  getAllSignals,
  pruneBefore,
  recordSignal,
} from '@/features/signals/store'
import { startSignalSources } from '@/features/signals/sources'
import { evaluate } from '@/features/baseline/engine'
import {
  getConfig,
  getInstalledAt,
} from '@/features/baseline/configStore'
import type {
  BaselineConfig,
  Evaluation,
  SignalEvent,
} from '@/features/baseline/types'

const RETENTION_DAYS = 35
const REEVAL_MS = 60_000

interface LivenessState {
  evaluation: Evaluation | null
  config: BaselineConfig
  loading: boolean
  /** 手动"我没事"打卡，记一次 manual_checkin 并立即重算 */
  checkIn: () => Promise<void>
  /** 配置变更后重新加载（灵敏度/安静窗） */
  reload: () => Promise<void>
}

export function useLiveness(): LivenessState {
  const [evaluation, setEvaluation] = useState<Evaluation | null>(null)
  const [config, setConfig] = useState<BaselineConfig>(getConfig())
  const [loading, setLoading] = useState(true)
  const eventsRef = useRef<SignalEvent[]>([])
  const installedAtRef = useRef<number>(getInstalledAt())

  const recompute = useCallback(() => {
    const cfg = getConfig()
    setConfig(cfg)
    setEvaluation(
      evaluate(eventsRef.current, Date.now(), cfg, installedAtRef.current),
    )
  }, [])

  const reload = useCallback(async () => {
    eventsRef.current = await getAllSignals()
    recompute()
    setLoading(false)
  }, [recompute])

  const checkIn = useCallback(async () => {
    await recordSignal('manual_checkin')
    await reload()
  }, [reload])

  useEffect(() => {
    let cancelled = false

    // 启动信号源：新事件写入本地存储后触发重载
    const stop = startSignalSources((kind) => {
      void recordSignal(kind).then(() => {
        if (!cancelled) void reload()
      })
    })

    // 清理过期时序 + 首次加载
    void pruneBefore(Date.now() - RETENTION_DAYS * 86_400_000)
      .catch(() => {})
      .finally(() => {
        if (!cancelled) void reload()
      })

    // 定时重算（即使无新事件，静默时长也在增长）
    const timer = window.setInterval(recompute, REEVAL_MS)

    return () => {
      cancelled = true
      stop()
      window.clearInterval(timer)
    }
  }, [reload, recompute])

  return { evaluation, config, loading, checkIn, reload }
}
