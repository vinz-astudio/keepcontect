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

/** OS permission checks only. Collector binding and user preferences are separate. */
export function getGuardianPermissions(): GuardianPermission[] {
  const platform = Capacitor.getPlatform()
  const android = platform === 'android'
  const ios = platform === 'ios'
  const native = android || ios
  const web = !native && !isTauri()
  return [
    {
      id: 'notifications',
      labelZh: '通知权限', labelEn: 'Notification permission',
      costZh: '允许通知不代表一定送达；专注模式、通知渠道和推送连接仍会影响提醒。网页被拒绝后需在浏览器或系统设置中修改。',
      costEn: 'Permission does not verify delivery. Focus, notification channels and push connectivity still matter. Repair a denied web permission in browser or system settings.',
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
      costZh: '未豁免时，省电模式可能推迟后台采集。豁免也不保证持续后台运行。',
      costEn: 'Power saving may delay collection without this exemption. An exemption still does not guarantee background execution.',
      supported: android,
      check: () => getNativePermissionState('battery'),
      fix: async () => { await requestBatteryExemption() },
      fixIsSettings: false,
    },
    {
      id: 'motion',
      labelZh: ios ? '运动与健身' : '身体活动', labelEn: ios ? 'Motion & Fitness' : 'Physical activity',
      costZh: '用于读取走动迹象。当前版本无法读取状态时，请到系统设置核对；没有读到数据不能证明权限被拒绝。',
      costEn: 'Used for movement signals. Check system settings if this version cannot read the status; missing data does not prove permission was denied.',
      supported: native,
      check: () => getNativePermissionState('motion'),
      fix: ios ? openNativeAppSettings : requestActivityRecognitionPermission,
      fixIsSettings: ios,
    },
    {
      id: 'usage',
      labelZh: '使用情况访问', labelEn: 'Usage access',
      costZh: '允许从系统使用记录回看手机活动，不上传具体内容或应用名称。',
      costEn: 'Allows activity lookback from system usage records; no app names or content are uploaded.',
      supported: android,
      check: () => getNativePermissionState('usage'),
      fix: openUsageStatsSettings,
      fixIsSettings: true,
    },
    {
      id: 'background-refresh',
      labelZh: '后台 App 刷新', labelEn: 'Background App Refresh',
      costZh: '读取 iOS 当前设置。低电量模式会关闭此能力；系统限制状态无法在 App 内解除。开启也不保证持续运行。',
      costEn: 'Reads the current iOS setting. Low Power Mode disables refresh; system restrictions cannot be removed here. Enabling it does not guarantee continuous execution.',
      supported: ios,
      check: () => getNativePermissionState('background-refresh'),
      fix: openNativeAppSettings,
      fixIsSettings: true,
    },
    {
      id: 'health-read',
      labelZh: '健康数据读取', labelEn: 'Health data read access',
      costZh: 'Apple 不向 App 公开读取授权结果。请在「健康」App 的数据访问权限中核对 KC；已请求、已注册或查询成功都不等于已授权。',
      costEn: 'Apple does not disclose read authorization. Check KC in Health data access settings; a completed request, registration or query does not prove consent.',
      supported: ios,
      check: async (): Promise<PermissionState> => 'limited',
      fix: openNativeAppSettings,
      fixIsSettings: true,
    },
  ].filter((permission) => permission.supported)
}

export function sortByUrgency(permissions: GuardianPermission[], states: Record<string, PermissionState>): GuardianPermission[] {
  const rank = (id: string) => states[id] === 'granted' ? 1 : 0
  return [...permissions].sort((a, b) => rank(a.id) - rank(b.id))
}
