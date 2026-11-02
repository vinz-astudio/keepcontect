import { Capacitor } from '@capacitor/core'
import {
  getNativeNotificationPermissionStatus, getNativePermissionState, getNativeTimeSensitiveSetting,
  openNativeNotificationSettings, openNativeAppSettings, openUsageStatsSettings,
  requestActivityRecognitionPermission, requestBatteryExemption, requestNativeNotificationPermission,
} from './native'
import { isTauri } from '@/lib/platform'
import { enablePush, pushSupported } from '@/features/push/pushApi'
import { FOCUS_TIME_SENSITIVE_HINT, timeSensitiveLimitation } from './timeSensitiveNotice'

export type PermissionState = 'granted' | 'denied' | 'unavailable' | 'checking' | 'prompt' | 'limited' | 'restricted'

export interface GuardianPermission {
  id: string
  labelZh: string
  labelEn: string
  costZh: string
  costEn: string
  supported: boolean
  check: () => Promise<PermissionState>
  fix: () => Promise<void>
  fixIsSettings: boolean
  /** Shown instead of the cost line when the state is 'limited'. */
  limitedZh?: string
  limitedEn?: string
}

/** OS permission checks only. Live OS state query. */
export function getGuardianPermissions(): GuardianPermission[] {
  const platform = Capacitor.getPlatform()
  const android = platform === 'android'
  const ios = platform === 'ios'
  const native = android || ios
  const desktop = isTauri()
  const web = !native && !desktop
  return [
    {
      id: 'notifications',
      labelZh: '通知权限', labelEn: 'Notifications',
      // IOS-FOCUS-01: KC cannot read the Focus switch, so iPhone users are told where it is.
      costZh: ios ? `用于发送关怀通知与紧急安全提醒。${FOCUS_TIME_SENSITIVE_HINT.zh}` : '用于发送关怀通知与紧急安全提醒。',
      costEn: ios ? `Used for care notifications and emergency alerts. ${FOCUS_TIME_SENSITIVE_HINT.en}` : 'Used for care notifications and emergency alerts.',
      supported: native || web,
      check: async (): Promise<PermissionState> => {
        if (native) {
          const state = await getNativePermissionState('notifications')
          // D2 (2026-11-02): allowed, but the safety ask cannot get through Focus.
          if (ios && timeSensitiveLimitation(await getNativeTimeSensitiveSetting(), state === 'granted')) {
            return 'limited'
          }
          return state
        }
        if (!pushSupported()) return 'unavailable'
        return Notification.permission === 'default' ? 'prompt' : Notification.permission
      },
      fix: async () => {
        if (web) { await enablePush(); return }
        const before = await getNativeNotificationPermissionStatus()
        if (before.canRequest) await requestNativeNotificationPermission()
        const after = await getNativeNotificationPermissionStatus()
        // Time Sensitive is switched on in the same settings page.
        const timeSensitiveOff = ios && (await getNativeTimeSensitiveSetting()) === 'disabled'
        if (!after.granted || timeSensitiveOff) await openNativeNotificationSettings()
      },
      fixIsSettings: false,
      limitedZh: timeSensitiveLimitation('disabled', true)?.zh,
      limitedEn: timeSensitiveLimitation('disabled', true)?.en,
    },
    {
      id: 'battery',
      labelZh: '电池优化豁免', labelEn: 'Battery optimization exemption',
      costZh: '减少系统对后台运行的限制，降低后台任务被延迟的可能。',
      costEn: 'Reduces system restrictions that may delay background work.',
      supported: android,
      check: () => getNativePermissionState('battery'),
      fix: async () => { await requestBatteryExemption() },
      fixIsSettings: false,
    },
    {
      id: 'motion',
      labelZh: ios ? '运动与健身' : '身体活动', labelEn: ios ? 'Motion & Fitness' : 'Physical activity',
      costZh: ios ? '用于记录步数与活动迹象，作为活跃证据。' : '用于记录日常活动与走动迹象，作为活跃证据。',
      costEn: ios ? 'Records steps and movement as activity evidence.' : 'Records physical activity and movement as activity evidence.',
      supported: native,
      check: () => getNativePermissionState('motion'),
      fix: ios ? openNativeAppSettings : requestActivityRecognitionPermission,
      fixIsSettings: ios,
    },
    {
      id: 'usage',
      labelZh: '使用情况访问', labelEn: 'Usage access',
      costZh: '在后台收集并上传您最后使用手机的时间戳到 Keep Contact 后端，用于检测不活跃；不会收集应用内容。',
      costEn: 'Collects and uploads your last phone-use timestamp to the Keep Contact backend in the background to detect inactivity; app content is not collected.',
      supported: android,
      check: () => getNativePermissionState('usage'),
      fix: openUsageStatsSettings,
      fixIsSettings: true,
    },
    {
      id: 'background-refresh',
      labelZh: '后台 App 刷新', labelEn: 'Background App Refresh',
      costZh: '允许系统在后台同步状态与更新活跃记录。',
      costEn: 'Allows the system to sync status in the background.',
      supported: ios,
      check: () => getNativePermissionState('background-refresh'),
      fix: openNativeAppSettings,
      fixIsSettings: true,
    },
    {
      id: 'autostart',
      labelZh: '开机自启', labelEn: 'Launch at startup',
      costZh: '电脑开机时自动在后台启动守护。',
      costEn: 'Starts automatically in background when computer boots.',
      supported: desktop,
      check: async (): Promise<PermissionState> => {
        try {
          const internals = (window as unknown as {
            __TAURI_INTERNALS__?: { invoke?: (cmd: string) => Promise<boolean> }
          }).__TAURI_INTERNALS__
          if (internals && typeof internals.invoke === 'function') {
            const enabled = await internals.invoke('plugin:autostart|is_enabled')
            return enabled ? 'granted' : 'prompt'
          }
        } catch {}
        return 'unavailable'
      },
      fix: async () => {
        try {
          const internals = (window as unknown as {
            __TAURI_INTERNALS__?: { invoke?: (cmd: string) => Promise<unknown> }
          }).__TAURI_INTERNALS__
          if (internals && typeof internals.invoke === 'function') {
            const enabled = (await internals.invoke('plugin:autostart|is_enabled')) as boolean
            if (enabled) {
              await internals.invoke('plugin:autostart|disable')
            } else {
              await internals.invoke('plugin:autostart|enable')
            }
          }
        } catch {}
      },
      fixIsSettings: false,
    },
  ].filter((permission) => permission.supported)
}

export function sortByUrgency(permissions: GuardianPermission[], states: Record<string, PermissionState>): GuardianPermission[] {
  const rank = (id: string) => states[id] === 'granted' ? 1 : 0
  return [...permissions].sort((a, b) => rank(a.id) - rank(b.id))
}

export function summarizeDevicePermissions(
  permissions: GuardianPermission[],
  states: Record<string, PermissionState>,
  checking: boolean,
): PermissionState {
  if (checking) return 'checking'
  if (permissions.length === 0) return 'granted'
  const values = permissions.map((p) => states[p.id] ?? 'checking')
  if (values.includes('checking')) return 'checking'
  if (values.includes('unavailable')) return 'unavailable'
  if (values.includes('restricted')) return 'restricted'
  if (values.some((v) => v === 'denied' || v === 'prompt')) return 'denied'
  if (values.every((v) => v === 'granted')) return 'granted'
  return 'denied'
}
