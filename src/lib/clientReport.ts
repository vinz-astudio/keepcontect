import { Capacitor } from '@capacitor/core'
import { supabase } from '@/lib/supabase'
import { getPlatform, isStandalone } from '@/lib/platform'
import { APP_VERSION } from '@/lib/version'

const CLIENT_ID_KEY = 'kc.clientId'
const SIG_KEY = 'kc.client.sig'
const AT_KEY = 'kc.client.reportedAt'
const THROTTLE_MS = 6 * 3_600_000

/** 每个浏览器/安装一个稳定 id(localStorage) */
function clientId(): string {
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

/** 精确客户端渠道:android-apk / ios-app / {plat}-pwa / {plat}-web */
export function clientChannel(): string {
  const p = getPlatform()
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
      _client_id: clientId(),
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
