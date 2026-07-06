import { Capacitor, registerPlugin } from '@capacitor/core'
import { SUPABASE_URL } from '@/lib/config'
import { isSensorEnabled } from '@/features/signals/sensors'

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
  if (Capacitor.getPlatform() !== 'android') return
  try {
    if (!token) {
      await PassivePing.clear()
      return
    }
    const allowCharging = isSensorEnabled('phone_charger')
    const hasAppActivitySensor = isSensorEnabled('app_activity')

    const allowUsageStats = hasAppActivitySensor && (await isUsageStatsEnabled())
    const allowActivityRecognition = hasAppActivitySensor && (await isActivityRecognitionEnabled())

    await PassivePing.configure({
      supabaseUrl: SUPABASE_URL,
      token,
      allowCharging,
      allowUsageStats,
      allowActivityRecognition,
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
  try {
    await PassivePing.openUsageStatsSettings()
  } catch {
    /* ignore */
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
  try {
    await PassivePing.requestActivityRecognitionPermission()
  } catch {
    /* ignore */
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

export async function requestNativeNotificationPermission(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    await PassivePing.requestNotificationPermission()
  } catch {
    /* ignore */
  }
}

export async function getNativeFcmToken(): Promise<string | null> {
  if (Capacitor.getPlatform() !== 'android') return null
  try {
    const res = await PassivePing.getFcmToken()
    return res?.token && res.token.length > 10 ? res.token : null
  } catch {
    return null
  }
}

export async function getGuardStatus(): Promise<GuardStatus | null> {
  if (Capacitor.getPlatform() !== 'android') return null
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
