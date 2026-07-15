import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useRef } from 'react'
import { getHeartbeatToken, getAutomaticPingSource } from '@/features/passive/api'
import {
  configureNativePassivePing,
  getNativeFcmToken,
  requestNativeNotificationPermission,
} from '@/features/passive/native'
import { supabase } from '@/lib/supabase'
import { sendPassiveWebPing } from '@/features/passive/webPing'
import { resilientFetch } from '@/lib/resilientFetch'

const LAST_WEB_PING_KEY = 'kc.passive.lastWebPingAt'

function readLastWebPingAt(): number | null {
  try {
    const raw = window.localStorage.getItem(LAST_WEB_PING_KEY)
    if (!raw) return null
    const value = Number(raw)
    return Number.isFinite(value) ? value : null
  } catch {
    return null
  }
}

function storeLastWebPingAt(value: number): void {
  try {
    window.localStorage.setItem(LAST_WEB_PING_KEY, String(value))
  } catch {
    /* Storage can be unavailable in private or locked-down webviews. */
  }
}

export function PassivePingBoot() {
  const tokenRef = useRef<string | null>(null)
  const pingingRef = useRef(false)

  const pingWeb = useCallback(async () => {
    const token = tokenRef.current
    if (!token || pingingRef.current) return

    const source = getAutomaticPingSource()
    if (!source) return // Plain browser: do NOT send automatic passive pings

    pingingRef.current = true
    try {
      await sendPassiveWebPing({
        token,
        source,
        lastPingAtMs: readLastWebPingAt(),
        fetcher: resilientFetch,
        storeLastPingAt: storeLastWebPingAt,
      })
    } finally {
      pingingRef.current = false
    }
  }, [])

  useEffect(() => {
    let cancelled = false

    getHeartbeatToken()
      .then(async (token) => {
        if (cancelled) return
        tokenRef.current = token
        await configureNativePassivePing(token)
        // Android 13+:原生轮询通知需要 POST_NOTIFICATIONS,登录配置后请求一次
        //(系统自会记住授权/拒绝,重复调用无副作用)。
        if (token) {
          await requestNativeNotificationPermission()
          // FCM 快路径:注册本机 token(幂等 upsert;无 GMS 的机型拿不到,
          // 自动回退 15min 轮询)。token 只是路由句柄,通知内容不经 Google。
          const fcm = await getNativeFcmToken()
          if (fcm) {
            void supabase
              .rpc('register_fcm_token', { _token: fcm })
              .then(() => {})
          }
        }
        await pingWeb()
      })
      .catch(() => {})

    return () => {
      cancelled = true
      tokenRef.current = null
      void configureNativePassivePing(null)
    }
  }, [pingWeb])

  // Android:回到前台时重新同步原生配置。用户从「无障碍设置」授权返回后,
  // native.ts 里的 allowAppActivity 门控需要重算,否则 SharedPreferences 里的
  // allow_app_activity 停在 false,无障碍服务收到事件也不会上报。
  useEffect(() => {
    if (Capacitor.getPlatform() !== 'android') return
    const resync = () => {
      if (tokenRef.current) void configureNativePassivePing(tokenRef.current)
    }
    const onVisibility = () => {
      if (document.visibilityState === 'visible') resync()
    }
    document.addEventListener('visibilitychange', onVisibility)
    window.addEventListener('focus', resync)
    return () => {
      document.removeEventListener('visibilitychange', onVisibility)
      window.removeEventListener('focus', resync)
    }
  }, [])

  useEffect(() => {
    const source = getAutomaticPingSource()
    if (!source) return // Plain browser: do NOT schedule automatic passive pings

    const ping = () => void pingWeb()
    const onVisibility = () => {
      if (document.visibilityState === 'visible') ping()
    }

    window.addEventListener('focus', ping)
    window.addEventListener('pageshow', ping)
    window.addEventListener('online', ping)
    window.addEventListener('pointerdown', ping, { passive: true })
    document.addEventListener('visibilitychange', onVisibility)

    return () => {
      window.removeEventListener('focus', ping)
      window.removeEventListener('pageshow', ping)
      window.removeEventListener('online', ping)
      window.removeEventListener('pointerdown', ping)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [pingWeb])

  return null
}