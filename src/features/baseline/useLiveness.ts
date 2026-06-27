import { useCallback, useEffect, useRef, useState } from 'react'
import {
  getAllSignals,
  pruneBefore,
  recordSignal,
  syncSignalsWithServer,
} from '@/features/signals/store'
import { startSignalSources } from '@/features/signals/sources'
import { evaluate } from '@/features/baseline/engine'
import {
  getConfig,
  getInstalledAt,
} from '@/features/baseline/configStore'
import { useAuth } from '@/features/auth/AuthProvider'
import { getSleepWindow } from '@/features/baseline/settingsApi'
import type {
  BaselineConfig,
  Evaluation,
  SignalEvent,
} from '@/features/baseline/types'

const RETENTION_DAYS = 35

interface LivenessState {
  evaluation: Evaluation | null
  config: BaselineConfig
  loading: boolean
  /** 手动"我没事"打卡，记一次 manual_checkin 并立即重算 */
  checkIn: () => Promise<void>
  /** 配置变更后重新加载（灵敏度/安静窗） */
  reload: (forceSync?: boolean) => Promise<void>
}

export function useLiveness(): LivenessState {
  const [evaluation, setEvaluation] = useState<Evaluation | null>(null)
  const [config, setConfig] = useState<BaselineConfig>(getConfig())
  const [loading, setLoading] = useState(true)
  const [_, setSleepWindow] = useState<{ start: string; end: string } | null>(null)
  const sleepWindowRef = useRef<{ start: string; end: string } | null>(null)
  const lastSleepFetchRef = useRef<number>(0)
  const eventsRef = useRef<SignalEvent[]>([])
  const lastSyncRef = useRef<number>(0)
  const timerRef = useRef<number | null>(null)

  const auth = useAuth()
  const user = auth?.user
  const installedAt = user?.created_at
    ? new Date(user.created_at).getTime()
    : getInstalledAt()

  const updateSleepWindow = useCallback((sw: { start: string; end: string } | null) => {
    setSleepWindow(sw)
    sleepWindowRef.current = sw
  }, [])

  const getExtendedConfig = useCallback((sleep: { start: string; end: string } | null) => {
    const baseCfg = getConfig()
    if (!sleep) return baseCfg

    const quietWindows = [...baseCfg.quietWindows]
    const parseHHMM = (hhmm: string) => {
      const [h, m] = hhmm.split(':').map(Number)
      return h * 60 + m
    }
    const startMin = parseHHMM(sleep.start)
    const endMin = parseHHMM(sleep.end)
    for (let dow = 0; dow < 7; dow++) {
      quietWindows.push({
        kind: 'recurring',
        label: 'sleep',
        dow,
        startMin,
        endMin,
      })
    }
    return { ...baseCfg, quietWindows }
  }, [])

  const recompute = useCallback(() => {
    const nextCfg = getExtendedConfig(sleepWindowRef.current)
    setConfig(nextCfg)
    const effectiveInstalledAt = eventsRef.current.length > 0
      ? Math.max(installedAt, Math.min(...eventsRef.current.map((e) => e.t)))
      : installedAt
    setEvaluation(
      evaluate(eventsRef.current, Date.now(), nextCfg, effectiveInstalledAt),
    )
  }, [installedAt, getExtendedConfig])

  const reload = useCallback(async (forceSync = false) => {
    const isVisible = document.visibilityState === 'visible'
    if (user?.id && (forceSync || (isVisible && Date.now() - lastSyncRef.current > 60_000))) {
      lastSyncRef.current = Date.now()
      await syncSignalsWithServer(user.id)
    }
    if (user?.id && (forceSync || !sleepWindowRef.current || (isVisible && Date.now() - lastSleepFetchRef.current > 300_000))) {
      lastSleepFetchRef.current = Date.now()
      const sw = await getSleepWindow().catch(() => null)
      updateSleepWindow(sw)
    }
    eventsRef.current = await getAllSignals()
    recompute()
    setLoading(false)
  }, [user?.id, recompute, updateSleepWindow])

  const checkIn = useCallback(async () => {
    await recordSignal('manual_checkin')
    await reload()
  }, [reload])

  useEffect(() => {
    if (!user?.id) {
      updateSleepWindow(null)
      lastSleepFetchRef.current = 0
    }
  }, [user?.id, updateSleepWindow])

  const reloadRef = useRef(reload)
  useEffect(() => {
    reloadRef.current = reload
  }, [reload])

  // Adaptive scheduler: recalculate next sync delay and reschedule timer
  useEffect(() => {
    if (loading) return
    if (timerRef.current) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }

    // Only sync / recompute periodically when the page is active
    if (document.visibilityState !== 'visible') return

    let delay = 60_000 // 1 minute default fallback
    if (evaluation) {
      if (evaluation.status === 'safe_window') {
        delay = 30 * 60 * 1000 // 30 minutes in sleep
      } else {
        const currentGapMs = evaluation.currentGapMs
        const thresholdMs = evaluation.thresholdMs ?? (12 * 3600 * 1000)
        const remainingMs = thresholdMs - currentGapMs

        if (remainingMs <= 0) {
          delay = 30_000 // 30 seconds
        } else if (remainingMs > 30 * 60 * 1000) {
          // Safe: wait until 30 minutes before threshold, up to max 1 hour
          delay = Math.min(remainingMs - 30 * 60 * 1000, 60 * 60 * 1000)
        } else {
          // Near threshold: check every 5 minutes
          delay = 5 * 60 * 1000
        }
      }
    }

    timerRef.current = window.setTimeout(() => {
      void reloadRef.current()
    }, delay)

    return () => {
      if (timerRef.current) {
        window.clearTimeout(timerRef.current)
        timerRef.current = null
      }
    }
  }, [evaluation, loading])

  // Listen to visibilitychange to instantly reschedule when foregrounded
  useEffect(() => {
    const handleVis = () => {
      if (document.visibilityState === 'visible') {
        void reloadRef.current(true)
      }
    }
    document.addEventListener('visibilitychange', handleVis)
    return () => document.removeEventListener('visibilitychange', handleVis)
  }, [])

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

    return () => {
      cancelled = true
      stop()
    }
  }, [reload])

  return { evaluation, config, loading, checkIn, reload }
}
