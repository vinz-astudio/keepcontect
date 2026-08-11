import { Capacitor, registerPlugin } from '@capacitor/core'
import { SUPABASE_URL } from '@/lib/config'
import { isSensorEnabled } from '@/features/signals/sensors'
import { getClientId } from '@/lib/clientReport'
import { APP_VERSION } from '@/lib/version'

export interface HealthWakeStatus {
  /** Device has HealthKit at all (an iPad does not). */
  supported: boolean
  /** The authorization sheet has been shown once on this install. */
  asked: boolean
  /** An observer query is registered right now. */
  observing: boolean
}

export interface GuardStatus {
  enabled: boolean
  connectedAt: number
  lastEventAt: number
  lastPingAt: number
  usageGranted?: boolean
  activityGranted?: boolean
  /** iOS only, and absent on shells built before the HealthKit wake. */
  health?: HealthWakeStatus
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
  consumeLaunchNotificationKind(): Promise<{ kind: string }>
  isAccessibilityEnabled(): Promise<{ enabled: boolean }>
  getGuardStatus(): Promise<GuardStatus>

  // UsageStats & Activity Recognition API bridges
  isUsageStatsEnabled(): Promise<{ enabled: boolean }>
  openUsageStatsSettings(): Promise<void>
  isActivityRecognitionEnabled(): Promise<{ enabled: boolean }>
  requestActivityRecognitionPermission(): Promise<void>

  // Android only: lets the guard sleep instead of staying resident.
  isBatteryExempt(): Promise<{ exempt: boolean }>
  requestBatteryExemption(): Promise<{ exempt: boolean }>
  getGuardMode(): Promise<{ mode: string; demotionPending: boolean }>
  resolveGuardDemotion(options: { accepted: boolean }): Promise<{ mode: string }>

  // iOS only: HealthKit as a wake source (KC-IOS-HEALTHWAKE-SPIKE-001).
  enableHealthWake(): Promise<{ granted: boolean }>

  // Android only: hand a URL to the user's real browser, in its own task.
  openExternalUrl(options: { url: string }): Promise<void>
}

const PassivePing = registerPlugin<PassivePingPlugin>('PassivePing')

/**
 * Opens a URL in the browser the user actually uses, not in an in-app tab.
 *
 * Only meaningful on Android, where a Custom Tab download has no trusted owner
 * and so offers no way to install what it just fetched.
 */
export async function openInExternalBrowser(url: string): Promise<void> {
  await PassivePing.openExternalUrl({ url })
}

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
      // Every other iOS evidence source needs KC to already be running when the
      // user does something, so a force-quit app goes silent until it is opened
      // again. HealthKit is the one wake that can relaunch it. Asked for here
      // rather than behind a settings toggle because a guard the user has to go
      // find is a guard most users will never have.
      await enableHealthWake()
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

/**
 * Shows the Health authorization sheet once and registers the HealthKit wake.
 *
 * Never throws: a shell built before this method exists rejects the call, and a
 * user who refuses is a normal outcome. Either way KC carries on with the
 * evidence sources it already has, so this must not be able to break sign-in.
 */
export async function enableHealthWake(): Promise<boolean> {
  if (Capacitor.getPlatform() !== 'ios') return false
  try {
    const res = await PassivePing.enableHealthWake()
    return !!res?.granted
  } catch {
    return false
  }
}

// —— 电池优化白名单(Android) ——
//
// 这一条决定了守护能不能"睡着而不是常驻"。拿到豁免,15 分钟的回看在 Doze 下
// 照常运行,通知栏干干净净;拿不到,系统可能把唤醒推迟几个小时,KC 只好退回
// 常驻前台服务——那条划不掉的通知就是这么来的。

export async function isBatteryExempt(): Promise<boolean> {
  if (Capacitor.getPlatform() !== 'android') return true
  try {
    const res = await PassivePing.isBatteryExempt()
    return !!res?.exempt
  } catch {
    // 旧壳没有这个方法:当作没拿到,让守护走保守路径
    return false
  }
}

/**
 * 弹出系统原生的「允许后台一直运行」对话框。
 *
 * 必须先给用户看过解释再调用——一个没有上下文、要求永久后台运行的系统弹窗,
 * 多数人会直接拒绝。用户是在这个 Promise 返回**之后**才作答的,所以返回值只
 * 代表调用前的状态,真实结果要在页面恢复时重新读一次。
 */
export async function requestBatteryExemption(): Promise<boolean> {
  if (Capacitor.getPlatform() !== 'android') return true
  try {
    const res = await PassivePing.requestBatteryExemption()
    return !!res?.exempt
  } catch {
    return false
  }
}

export interface GuardMode {
  /** 'silent' = 后台无痕;'persistent' = 通知栏常驻(仅冻结 KC 的设备才需要) */
  mode: 'silent' | 'persistent'
  /** KC 判定这台设备在冻结自己,正等着问用户要不要转为可见守护 */
  demotionPending: boolean
}

export async function getGuardMode(): Promise<GuardMode | null> {
  if (Capacitor.getPlatform() !== 'android') return null
  try {
    const res = await PassivePing.getGuardMode()
    return {
      mode: res?.mode === 'persistent' ? 'persistent' : 'silent',
      demotionPending: !!res?.demotionPending,
    }
  } catch {
    // 旧壳没有这个方法:当作静默且无待决请求
    return null
  }
}

/** 用户对"转为可见守护"的答复。拒绝也是答复,问题就此清除,不再追问。 */
export async function resolveGuardDemotion(accepted: boolean): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    await PassivePing.resolveGuardDemotion({ accepted })
  } catch {
    /* 旧壳:忽略 */
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

/**
 * A native install with no token has no wake channel at all: push-dispatch can
 * only fall back to the 15-minute WorkManager poll, which Doze defers on a
 * locked idle phone. A silent `catch` hid exactly that for 26 days after the
 * Android plugin lost `getFcmToken`, so the two failure modes are now told
 * apart and both are logged loudly.
 */
export async function getNativeFcmToken(): Promise<string | null> {
  if (!isNativePushPlatform()) return null
  try {
    const res = await PassivePing.getFcmToken()
    const token = res?.token && res.token.length > 10 ? res.token : null
    if (!token) {
      // Bridge answered, device has no token: no Google services, or Firebase
      // has not finished registering yet. Heals on a later launch.
      console.warn('[push] native FCM token unavailable on this device')
    }
    return token
  } catch (e) {
    // The bridge itself failed — the method is missing from this build, or the
    // plugin is not loaded. This is a broken build, not a device limitation.
    console.error('[push] native FCM bridge call failed; this build cannot receive push', e)
    return null
  }
}

/**
 * Which notification kind opened the app, read once and cleared.
 *
 * The PWA gets this from the `?notifKind=` query the service worker adds when a
 * web notification is tapped. A tapped system notification hands the native
 * shell no such signal, so without this the app opened on the home screen and
 * only swapped to the unlock prompt once the network confirmed an open alert —
 * home screen, sync, flicker, prompt. Returns '' when the app was opened some
 * other way, and on platforms with no native shell.
 */
export async function consumeLaunchNotificationKind(): Promise<string> {
  const platform = Capacitor.getPlatform()
  if (platform !== 'android' && platform !== 'ios') return ''
  try {
    const res = await PassivePing.consumeLaunchNotificationKind()
    return res?.kind ?? ''
  } catch {
    // An older shell without the method: fall back to the network path.
    return ''
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
