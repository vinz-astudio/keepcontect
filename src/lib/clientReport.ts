import { Capacitor } from '@capacitor/core'
import { supabase } from '@/lib/supabase'
import { getPlatform, isStandalone, isTauri } from '@/lib/platform'
import { APP_VERSION } from '@/lib/version'

const CLIENT_ID_KEY = 'kc.clientId'
const SIG_KEY = 'kc.client.sig'
const AT_KEY = 'kc.client.reportedAt'
const THROTTLE_MS = 6 * 3_600_000

/** 每个浏览器/安装一个稳定 id(localStorage) */
export function getClientId(): string {
  try {
    let id = localStorage.getItem(CLIENT_ID_KEY)
    if (!id) {
      id =
        crypto.randomUUID?.() ??
        `c-${Date.now()}-${Math.random().toString(36).slice(2)}`
      localStorage.setItem(CLIENT_ID_KEY, id)
    }
    return id
  } catch {
    return 'unknown'
  }
}

/** 精确客户端渠道:tauri / android-apk / ios-app / {plat}-pwa / {plat}-web */
export function clientChannel(): string {
  const p = getPlatform()
  // 桌面原生壳必须先判:它是普通 WebView,不查 isTauri() 就会自称 desktop-web,
  // 与浏览器标签页无从区分。服务端 record_alert_shadow_coverage_lease 要求
  // clients.platform = 'tauri' 才收覆盖凭据,报错渠道名会被静默判为
  // capability_mismatch —— 守望者心跳因此永远落不了地。
  if (isTauri()) return 'tauri'
  if (Capacitor.isNativePlatform()) {
    return p === 'android' ? 'android-apk' : `${p}-app`
  }
  if (isStandalone()) return `${p}-pwa`
  return `${p}-web`
}

/**
 * 上报当前客户端的版本与平台(需已登录)。
 * 版本/平台变化立即上报,否则至多每 ~6h 一次(省写入)。
 */
export async function reportClient(): Promise<void> {
  try {
    const sig = `${clientChannel()}|${APP_VERSION}`
    const lastSig = localStorage.getItem(SIG_KEY)
    const lastAt = Number(localStorage.getItem(AT_KEY)) || 0
    if (sig === lastSig && Date.now() - lastAt < THROTTLE_MS) return
    const { error } = await supabase.rpc('report_client', {
      _client_id: getClientId(),
      _platform: clientChannel(),
      _version: APP_VERSION,
    })
    if (!error) {
      localStorage.setItem(SIG_KEY, sig)
      localStorage.setItem(AT_KEY, String(Date.now()))
    }
  } catch {
    /* 离线/未登录:忽略 */
  }
}
