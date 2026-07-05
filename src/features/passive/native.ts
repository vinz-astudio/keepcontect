import { Capacitor, registerPlugin } from '@capacitor/core'
import { SUPABASE_URL } from '@/lib/config'
import { isSensorEnabled } from '@/features/signals/sensors'

interface PassivePingPlugin {
  configure(options: {
    supabaseUrl: string
    token: string
    allowCharging?: boolean
    allowAppActivity?: boolean
  }): Promise<void>
  clear(): Promise<void>
  pingApp(): Promise<void>
  openAccessibilitySettings(): Promise<void>
  openAutostartSettings(): Promise<void>
  requestNotificationPermission(): Promise<void>
  getFcmToken(): Promise<{ token: string }>
  isAccessibilityEnabled(): Promise<{ enabled: boolean }>
  getGuardStatus(): Promise<{
    enabled: boolean
    connectedAt: number
    lastEventAt: number
    lastPingAt: number
  }>
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
    const allowAppActivity =
      isSensorEnabled('app_activity') && (await readAccessibilityEnabled())
    await PassivePing.configure({
      supabaseUrl: SUPABASE_URL,
      token,
      allowCharging,
      allowAppActivity,
    })
    await PassivePing.pingApp()
  } catch {
    // Native bridge is best-effort; PWA ping URLs remain the fallback.
  }
}

/** Open the system Accessibility settings so the user can enable the background
 *  app-activity sensor (AppActivityService). Android-only, best-effort. */
export async function openAccessibilitySettings(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    await PassivePing.openAccessibilitySettings()
  } catch {
    /* ignore */
  }
}

/** Open the OEM autostart whitelist (MIUI/HyperOS) or the app-details page.
 *  Chinese ROMs kill background services unless the app is whitelisted. */
export async function openAutostartSettings(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    await PassivePing.openAutostartSettings()
  } catch {
    /* ignore */
  }
}

/** Whether the AppActivityService accessibility service is currently enabled. */
async function readAccessibilityEnabled(): Promise<boolean> {
  if (Capacitor.getPlatform() !== 'android') return false
  try {
    const res = await PassivePing.isAccessibilityEnabled()
    return !!res?.enabled
  } catch {
    return false
  }
}

export async function isAccessibilityEnabled(): Promise<boolean> {
  return readAccessibilityEnabled()
}

/** Android 13+ runtime POST_NOTIFICATIONS request. The WebView has no
 *  Notification.requestPermission, so the native poller's notifications need
 *  this explicit ask. Safe to call repeatedly — no-op once granted/denied. */
export async function requestNativeNotificationPermission(): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    await PassivePing.requestNotificationPermission()
  } catch {
    /* ignore */
  }
}

/** The device's FCM registration token, or null when unavailable (non-Android,
 *  GMS-less ROMs, Firebase unconfigured). Used for the ADR-0004 wake-tickle
 *  fast path — the token is an opaque routing handle, never content. */
export async function getNativeFcmToken(): Promise<string | null> {
  if (Capacitor.getPlatform() !== 'android') return null
  try {
    const res = await PassivePing.getFcmToken()
    return res?.token && res.token.length > 10 ? res.token : null
  } catch {
    return null
  }
}

export interface GuardStatus {
  enabled: boolean
  connectedAt: number
  lastEventAt: number
  lastPingAt: number
}

/** Guard liveness (settings toggle + real bind/event/ping timestamps). Null on
 *  non-Android or when the bridge fails. */
export async function getGuardStatus(): Promise<GuardStatus | null> {
  if (Capacitor.getPlatform() !== 'android') return null
  try {
    return await PassivePing.getGuardStatus()
  } catch {
    return null
  }
}
