import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { useLiveness } from '@/features/baseline/useLiveness'
import {
  getMyOpenAlert,
  resolveMyAlert,
  sendHeartbeat,
  type Alert,
} from '@/features/alerts/api'
import { subscribeAlertSignals } from '@/features/alerts/realtime'
import {
  getServerSensitivity,
  getSleepWindow,
  setSleepWindow,
  getServerPatternHash,
  setServerPatternHash,
  syncServerTimezone,
} from '@/features/baseline/settingsApi'
import { getConfig, setConfig } from '@/features/baseline/configStore'
import { hasPattern } from '@/features/pattern/patternStore'
import { primeAlarm } from '@/features/baseline/alarm'
import type { BaselineConfig, Evaluation } from '@/features/baseline/types'
import { shouldShowSelfCheckForNotificationKind } from '@/features/alerts/notificationRouting'
import { recordViewportTrace } from '@/lib/viewportDiagnostics'

/** 解锁遮罩的非告警模式：演练（验证已设手势）/ 设置（首次或修改手势） */
export type OverlayMode = 'none' | 'practice' | 'setup'

interface LivenessContextValue {
  evaluation: Evaluation | null
  config: BaselineConfig
  loading: boolean
  /** 服务器侧当前 open 的告警（心跳/暗设备侦测到的，本地引擎看不到） */
  serverAlert: Alert | null
  /** 当前解锁遮罩模式（none = 仅在真告警时才弹） */
  mode: OverlayMode
  /** 从通知点进来时立刻置位：在 getMyOpenAlert 返回前就先把解锁界面顶上来 */
  alertHint: boolean
  /** 演练：练习已设手势 */
  startPractice: () => void
  /** 设置/修改手势（首次自动触发，也可手动进入；覆盖旧手势） */
  startSetup: () => void
  /** 关闭演练/设置遮罩（真告警无法用此跳过） */
  closeOverlay: () => void
  checkIn: () => Promise<void>
  reload: () => Promise<void>
  /** 本人 pattern 解锁成功：记一次活动 + 通知服务器自解除（演练/设置时仅关闭遮罩） */
  confirmSafe: () => Promise<void>
}

const Ctx = createContext<LivenessContextValue | undefined>(undefined)

// 保活心跳：服务器超时阈值是小时级，无需每分钟刷；状态变化即时发、其余低频保活。
const HEARTBEAT_MS = 300_000 // 5 分钟
const ALERT_POLL_MS = 30_000

export function LivenessProvider({ children }: { children: ReactNode }) {
  const live = useLiveness()
  const lastStatusRef = useRef<string | null>(null)
  const [serverAlert, setServerAlert] = useState<Alert | null>(null)
  const [mode, setMode] = useState<OverlayMode>('none')
  // 上次已知"有未解告警"则启动即乐观顶出解锁界面（不等网络/不靠脆弱的通知信号）
  const [alertHint, setAlertHint] = useState(
    () => localStorage.getItem('kc.openAlert') === '1',
  )

  const status = live.evaluation?.status ?? null
  const hbStatus: 'normal' | 'alert' = 'normal'

  const serverNeedsConfirm =
    serverAlert != null &&
    serverAlert.status === 'open' &&
    (serverAlert.cause === 'silence' ||
      serverAlert.cause === 'dark_device' ||
      // concern 是"别人点名要你报平安":被动 ping 不会解除,必须本人解锁
      serverAlert.cause === 'concern')
  const realAlert = serverNeedsConfirm

  // 首次进入且本机还没设过手势：自动同步服务器，若无则弹出"设置手势"引导
  const promptedRef = useRef(false)
  useEffect(() => {
    if (promptedRef.current) return
    promptedRef.current = true
    primeAlarm() // 解锁应用内告警声（iOS 需首个手势）
    
    // 冷启动从通知点开：只有 self/concern 通知可先乐观弹自证；group 通知只刷新列表
    const launchParams = new URLSearchParams(window.location.search)
    if (launchParams.get('from') === 'notif') {
      const notificationKind = launchParams.get('notifKind')
      recordViewportTrace('liveness-from-notification-query', { notificationKind })
      if (shouldShowSelfCheckForNotificationKind(notificationKind)) setAlertHint(true)
      window.history.replaceState(null, '', window.location.pathname) // 清掉参数，避免刷新再触发
    }

    const syncPattern = async () => {
      try {
        if (hasPattern()) {
          // 本地有，同步给服务器（如果服务器还没有）
          const localHash = localStorage.getItem('kc.patternHash')
          if (localHash) {
            const serverHash = await getServerPatternHash()
            if (!serverHash) {
              await setServerPatternHash(localHash)
            }
          }
        } else {
          // 本地没有，查服务器
          const serverHash = await getServerPatternHash()
          if (serverHash) {
            localStorage.setItem('kc.patternHash', serverHash)
          } else {
            // 服务器和本地都没有，说明是新用户首次登录，展示设置手势引导
            setMode('setup')
          }
        }
      } catch (err) {
        console.error('Failed to sync pattern with server:', err)
        if (!hasPattern()) {
          setMode('setup')
        }
      }
    }
    void syncPattern()
  }, [])

  const reloadRef = useRef(live.reload)
  const statusRef = useRef(status)
  const serverAlertRef = useRef(serverAlert)

  useEffect(() => {
    reloadRef.current = live.reload
  }, [live.reload])

  useEffect(() => {
    statusRef.current = status
  }, [status])

  useEffect(() => {
    serverAlertRef.current = serverAlert
  }, [serverAlert])

  const refreshAlert = useCallback(async () => {
    try {
      const a = await getMyOpenAlert()
      const prevAlert = serverAlertRef.current
      setServerAlert(a)
      // 记下权威状态供下次启动乐观显示；并收起本次乐观遮罩（有则 realAlert 接手）
      localStorage.setItem('kc.openAlert', a ? '1' : '0')
      setAlertHint(false)

      if (!a && (prevAlert || statusRef.current === 'alert')) {
        // 强制进行服务器信号同步，清除本地的“异常沉默”告警状态
        await reloadRef.current(true)
      }
    } catch {
      /* 离线/未登录时忽略；保留 alertHint 宁可多弹也不漏 */
    }
  }, [])

  // 心跳：状态变化即发 + 定时发（设备侧 G1；后台/iOS 需原生承载，见 sources.ts）
  useEffect(() => {
    if (live.loading) return
    if (lastStatusRef.current !== hbStatus) {
      lastStatusRef.current = hbStatus
      void sendHeartbeat(hbStatus).catch(() => {})
    }
  }, [hbStatus, live.loading])

  useEffect(() => {
    const beat = () =>
      void sendHeartbeat(
        lastStatusRef.current === 'alert' ? 'alert' : 'normal',
      ).catch(() => {})
    const t = window.setInterval(beat, HEARTBEAT_MS)
    // 网络恢复时立即补一次保活（平时没网就不徒劳发，省流量/耗电）
    window.addEventListener('online', beat)
    return () => {
      window.clearInterval(t)
      window.removeEventListener('online', beat)
    }
  }, [])

  // 首次进入：若服务器没有睡眠窗，写入默认（本地 23:00–07:00）作兜底；
  // 用本地标记避免覆盖用户之后主动关闭的选择。
  useEffect(() => {
    if (localStorage.getItem('kc.sleepInit')) return
    void getSleepWindow()
      .then((w) => (w ? undefined : setSleepWindow('23:00', '07:00')))
      .then(() => localStorage.setItem('kc.sleepInit', '1'))
      .catch(() => {})
  }, [])

  // 登录后从服务器拉灵敏度，回种本地（跨设备一致：换设备也保留你设过的档）
  useEffect(() => {
    void getServerSensitivity()
      .then((s) => {
        if (s && s !== getConfig().sensitivity) {
          setConfig({ ...getConfig(), sensitivity: s })
          void live.reload()
        }
      })
      .catch(() => {})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // 检测并自动同步浏览器本地时区到服务器
  useEffect(() => {
    void syncServerTimezone().catch((err) => {
      console.error('Failed to sync server timezone:', err)
    })
  }, [])


  // 轮询服务器 open 告警 + 回到前台时立刻查（这样打开 App 就能弹 pattern）
  useEffect(() => {
    void refreshAlert()
    const t = window.setInterval(() => void refreshAlert(), ALERT_POLL_MS)
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refreshAlert()
    }
    // 从通知点进来：Service Worker 发消息；仅 self/concern 可先弹自证，其余只刷新告警/通知
    const onSwMsg = (e: MessageEvent) => {
      const data = e.data as { type?: string; source?: string; notificationKind?: string | null } | null
      if (data?.type === 'kc-open-alert') {
        recordViewportTrace('liveness-service-worker-open-alert', {
          source: data.source ?? 'unknown',
          notificationKind: data.notificationKind ?? null,
        })
        if (shouldShowSelfCheckForNotificationKind(data.notificationKind)) setAlertHint(true)
        void refreshAlert()
      }
    }
    // iOS 主屏 PWA 回到页面常走 bfcache，focus/visibility 不一定触发 → 兜底
    const onPageShow = () => {
      recordViewportTrace('liveness-pageshow-refresh-alert')
      void refreshAlert()
    }
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('focus', refreshAlert)
    window.addEventListener('pageshow', onPageShow)
    navigator.serviceWorker?.addEventListener('message', onSwMsg)
    let unsubscribe: (() => void) | undefined
    void subscribeAlertSignals(refreshAlert).then((fn) => {
      unsubscribe = fn
    })
    return () => {
      window.clearInterval(t)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('focus', refreshAlert)
      window.removeEventListener('pageshow', onPageShow)
      navigator.serviceWorker?.removeEventListener('message', onSwMsg)
      unsubscribe?.()
    }
  }, [refreshAlert])

  const value: LivenessContextValue = {
    ...live,
    serverAlert,
    mode,
    alertHint,
    startPractice: () => setMode(hasPattern() ? 'practice' : 'setup'),
    startSetup: () => setMode('setup'),
    closeOverlay: () => setMode('none'),
    confirmSafe: async () => {
      if (!realAlert && !alertHint) {
        setMode('none') // 演练/设置：仅关闭遮罩，不动真告警
        return
      }
      setAlertHint(false)
      await live.checkIn() // 记一次本地活动
      await resolveMyAlert().catch(() => {}) // 通知服务器解除（若有 open 告警）
      await live.reload()
      await refreshAlert() // 清掉刚解除的服务器告警
      setMode('none')
    },
  }

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useLivenessContext(): LivenessContextValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useLivenessContext 必须在 <LivenessProvider> 内使用')
  return v
}
