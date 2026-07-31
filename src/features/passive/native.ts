import { Capacitor, registerPlugin } from '@capacitor/core'
import { SUPABASE_URL } from '@/lib/config'
import { isSensorEnabled } from '@/features/signals/sensors'
import { getClientId } from '@/lib/clientReport'
import { APP_VERSION } from '@/lib/version'

export interface GuardStatus {
  enabled: boolean
  connectedAt: number
  lastEventAt: number
  lastPingAt: number
  usageGranted?: boolean
  activityGranted?: boolean
}

interface PassivePingPlugin {
  configure(options: {
    supabaseUrl: string
    token: string
    allowCharging?: boolean
    allowUsageStats?: boolean
    allowActivityRecognition?: boolean
    clientId: string
    appVersion: string
    collectorContract: 'android-passive-v1' | 'ios-passive-v1'
  }): Promise<void>
  clear(): Promise<void>
  pingApp(): Promise<void>
  openAccessibilitySettings(): Promise<void>
  openAutostartSettings(): Promise<void>
  requestNotificationPermission(): Promise<void>
  getFcmToken(): Promise<{ token: string }>
  isAccessibilityEnabled(): Promise<{ enabled: boolean }>
  getGuardStatus(): Promise<GuardStatus>

  // UsageStats & Activity Recognition API bridges
  isUsageStatsEnabled(): Promise<{ enabled: boolean }>
  openUsageStatsSettings(): Promise<void>
  isActivityRecognitionEnabled(): Promise<{ enabled: boolean }>
  requestActivityRecognitionPermission(): Promise<void>
}

const PassivePing = registerPlugin<PassivePingPlugin>('PassivePing')

export async function configureNativePassivePing(
  token: string | null,
): Promise<void> {
  const platform = Capacitor.getPlatform()
  if (platform !== 'android' && platform !== 'ios') return
  try {
    if (!token) {
      await PassivePing.clear()
      return
    }
    // iOS has no UsageStats/charger/activity equivalents; its guard is the
    // unlock watcher alone, so it only needs credentials. The extra Android
    // toggles are omitted rather than sent and ignored.
    if (platform === 'ios') {
      // The unlock watcher is the whole iOS guard, so the same toggle that
      // labels it has to be able to switch it off.
      if (!isSensorEnabled('app_activity')) {
        await PassivePing.clear()
        return
      }
      await PassivePing.configure({
        supabaseUrl: SUPABASE_URL,
        token,
        clientId: getClientId(),
        appVersion: APP_VERSION,
        collectorContract: 'ios-passive-v1',
      })
      await PassivePing.pingApp()
      return
    }

    const allowCharging = isSensorEnabled('phone_charger')
    const allowUsageStats = isSensorEnabled('app_activity')
    const allowActivityRecognition = isSensorEnabled('motion')

    await PassivePing.configure({
      supabaseUrl: SUPABASE_URL,
      token,
      allowCharging,
      allowUsageStats,
      allowActivityRecognition,
      clientId: getClientId(),
      appVersion: APP_VERSION,
      collectorContract: 'android-passive-v1',
    })
    await PassivePing.pingApp()
  } catch {
    // Native bridge is best-effort; PWA ping URLs remain the fallback.
  }
}

// —— UsageStats Helpers ——

export async function isUsageStatsEnabled(): Promise<boolean> {
  if (Capacitor.getPlatform() !== 'android') return false
  try {
    const res = await PassivePing.isUsageStatsEnabled()
    return !!res?.enabled
  } catch {
    return false
  }
}

export async function openUsageStatsSettings(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  const isZh = (navigator.language || '').startsWith('zh')
  const message = isZh
    ? '【使用情况访问权限 - 显著披露】\n\nKeep Contact 需要使用情况访问权限，仅用于在后台检测您最后使用手机的时间戳（以判定安全状态并防止误报紧急失联）。\n\n我们承诺：绝不会收集、读取、上传或分享您的任何应用内容、聊天记录、搜索历史或个人隐私信息。'
    : '【Usage Access Permission - Prominent Disclosure】\n\nKeep Contact requires Usage Access permission solely to detect your last active phone timestamp in background (to assess your safety and prevent false emergency alerts).\n\nWe promise: We NEVER read, collect, upload, or share your app contents, messages, search history, or personal privacy data.'
  
  if (window.confirm(message)) {
    try {
      await PassivePing.openUsageStatsSettings()
    } catch {
      /* ignore */
    }
  }
}

// —— Activity Recognition Helpers ——

export async function isActivityRecognitionEnabled(): Promise<boolean> {
  if (Capacitor.getPlatform() !== 'android') return false
  try {
    const res = await PassivePing.isActivityRecognitionEnabled()
    return !!res?.enabled
  } catch {
    return false
  }
}

export async function requestActivityRecognitionPermission(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  const isZh = (navigator.language || '').startsWith('zh')
  const message = isZh
    ? '【身体运动识别权限 - 显著披露】\n\nKeep Contact 需要身体运动识别权限，仅用于在您携手机行走或运动时通过硬件底层判定日常活跃，无需频繁点亮屏幕。\n\n我们承诺：绝不上传或追踪您的精确地理位置，运动状态仅用于本地与服务端的安全判定。'
    : '【Physical Activity Recognition - Prominent Disclosure】\n\nKeep Contact requires Physical Activity recognition permission to detect active status while walking or moving using low-power hardware, without turning on the screen.\n\nWe promise: We NEVER track or upload your location data.'
  
  if (window.confirm(message)) {
    try {
      await PassivePing.requestActivityRecognitionPermission()
    } catch {
      /* ignore */
    }
  }
}

// —— Autostart & Notifications Helpers ——

export async function openAutostartSettings(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    await PassivePing.openAutostartSettings()
  } catch {
    /* ignore */
  }
}

// Both platforms register through the same Firebase project, so an iOS device
// lands in `push_tokens` exactly like an Android one and push-dispatch needs no
// iOS branch. This is what gives an iOS user a chance to clear a `self` alert
// before it escalates to their group.
function isNativePushPlatform(): boolean {
  const platform = Capacitor.getPlatform()
  return platform === 'android' || platform === 'ios'
}

export async function requestNativeNotificationPermission(): Promise<void> {
  if (!isNativePushPlatform()) return
  try {
    await PassivePing.requestNotificationPermission()
  } catch {
    /* ignore */
  }
}

export async function getNativeFcmToken(): Promise<string | null> {
  if (!isNativePushPlatform()) return null
  try {
    const res = await PassivePing.getFcmToken()
    return res?.token && res.token.length > 10 ? res.token : null
  } catch {
    return null
  }
}

export async function getGuardStatus(): Promise<GuardStatus | null> {
  const platform = Capacitor.getPlatform()
  if (platform !== 'android' && platform !== 'ios') return null
  try {
    return await PassivePing.getGuardStatus()
  } catch {
    return null
  }
}

// —— Legacy Compatibility Helpers (No-ops) ——

export async function openAccessibilitySettings(): Promise<void> {
  // Legacy Accessibility settings: now a no-op
}

export async function isAccessibilityEnabled(): Promise<boolean> {
  return false
}
