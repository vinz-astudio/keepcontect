import { Capacitor } from '@capacitor/core'
import {
  getNativeNotificationPermissionStatus, getNativePermissionState,
  openNativeNotificationSettings, openNativeAppSettings, openUsageStatsSettings,
  requestActivityRecognitionPermission, requestBatteryExemption, requestNativeNotificationPermission,
} from './native'
import { isTauri } from '@/lib/platform'
import { enablePush, pushSupported } from '@/features/push/pushApi'

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
      costZh: '用于发送关怀通知与紧急安全提醒。',
      costEn: 'Used for care notifications and emergency alerts.',
      supported: native || web,
      check: async (): Promise<PermissionState> => {
        if (native) return getNativePermissionState('notifications')
        if (!pushSupported()) return 'unavailable'
        return Notification.permission === 'default' ? 'prompt' : Notification.permission
      },
      fix: async () => {
        if (web) { await enablePush(); return }
        const before = await getNativeNotificationPermissionStatus()
        if (before.canRequest) await requestNativeNotificationPermission()
        if (!(await getNativeNotificationPermissionStatus()).granted) await openNativeNotificationSettings()
      },
      fixIsSettings: false,
    },
    {
      id: 'battery',
      labelZh: '电池优化豁免', labelEn: 'Battery optimization exemption',
      costZh: '避免系统在后台清理或休眠应用。',
      costEn: 'Prevents the system from sleeping the app in the background.',
      supported: android,
      check: () => getNativePermissionState('battery'),
      fix: async () => { await requestBatteryExemption() },
      fixIsSettings: false,
    },
    {
      id: 'motion',
      labelZh: ios ? '运动与健身' : '身体活动', labelEn: ios ? 'Motion & Fitness' : 'Physical activity',
      costZh: ios ? '用于读取步数与走动迹象以确认安全。' : '用于检测日常活动与走动迹象。',
      costEn: ios ? 'Detects steps and movement to confirm safety.' : 'Detects physical activity and movement.',
      supported: native,
      check: () => getNativePermissionState('motion'),
      fix: ios ? openNativeAppSettings : requestActivityRecognitionPermission,
      fixIsSettings: ios,
    },
    {
      id: 'usage',
      labelZh: '使用情况访问', labelEn: 'Usage access',
      costZh: '通过系统记录感知设备活跃，不上传任何隐私内容。',
      costEn: 'Detects device activity from system records; no content is uploaded.',
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
