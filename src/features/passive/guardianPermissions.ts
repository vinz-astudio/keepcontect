import { Capacitor } from '@capacitor/core'
import {
  getNativeNotificationPermissionStatus,
  isActivityRecognitionEnabled,
  isBatteryExempt,
  isUsageStatsEnabled,
  openNativeNotificationSettings,
  openUsageStatsSettings,
  requestActivityRecognitionPermission,
  requestBatteryExemption,
  requestNativeNotificationPermission,
} from '@/features/passive/native'

export type PermissionState = 'granted' | 'denied' | 'unavailable' | 'checking'

export interface GuardianPermission {
  id: string
  labelZh: string
  labelEn: string
  /** 少了它,KC 具体做不到哪件事。写后果,不写权限名。 */
  costZh: string
  costEn: string
  supported: boolean
  check: () => Promise<boolean>
  /** 有的能就地弹系统对话框,有的只能把用户送到设置页。 */
  fix: () => Promise<void>
  fixIsSettings: boolean
}

const android = () => Capacitor.getPlatform() === 'android'
const nativePhone = () => Capacitor.getPlatform() === 'android' || Capacitor.getPlatform() === 'ios'

/**
 * 权限清单按「少了它 KC 做不到什么」排序,不按系统的权限分类排。
 *
 * 通知排第一不是因为它最容易拿到,而是因为少了它,整条告警链的第一步就不成立 ——
 * KC 判断出你可能有事,却没有办法问你。后面所有的采集做得再好也白做。
 */
export function getGuardianPermissions(): GuardianPermission[] {
  return [
    {
      id: 'notifications',
      labelZh: '通知',
      labelEn: 'Notifications',
      costZh: 'KC 无法在判断您可能有事时问您。它会直接通知您的群组。',
      costEn: 'KC cannot ask you when it thinks something is wrong. It would go straight to your group.',
      supported: nativePhone(),
      check: async () => (await getNativeNotificationPermissionStatus()).granted,
      fix: async () => {
        const before = await getNativeNotificationPermissionStatus()
        // 系统只肯弹一次对话框。之前被拒过的账号再问也不会弹,只能送去设置页。
        if (before.canRequest) await requestNativeNotificationPermission()
        if (!(await getNativeNotificationPermissionStatus()).granted) {
          await openNativeNotificationSettings()
        }
      },
      fixIsSettings: false,
    },
    {
      id: 'battery',
      labelZh: '后台运行',
      labelEn: 'Background running',
      costZh: '系统会在省电时停掉 KC。它会漏掉您的活动,把您判成失联。',
      costEn: 'The system will stop KC to save power. It would miss your activity and read you as out of contact.',
      supported: android(),
      check: isBatteryExempt,
      fix: async () => { await requestBatteryExemption() },
      fixIsSettings: false,
    },
    {
      id: 'motion',
      labelZh: '身体活动',
      labelEn: 'Physical activity',
      costZh: 'KC 收不到走动的迹象,只能靠您解锁手机来证明您还在。',
      costEn: 'KC cannot see that you moved, and has to rely on you unlocking the phone.',
      supported: android(),
      check: isActivityRecognitionEnabled,
      fix: async () => { await requestActivityRecognitionPermission() },
      fixIsSettings: false,
    },
    {
      id: 'usage',
      labelZh: '使用情况访问',
      labelEn: 'Usage access',
      costZh: 'KC 看不到您解锁过手机,少了最可靠的一种活动迹象。',
      costEn: 'KC cannot see that you unlocked the phone, losing the most reliable sign of activity.',
      supported: android(),
      check: isUsageStatsEnabled,
      fix: openUsageStatsSettings,
      fixIsSettings: true,
    },
  ].filter((permission) => permission.supported)
}

/** 缺的比给的重要,所以没给的排前面。 */
export function sortByUrgency(
  permissions: GuardianPermission[],
  states: Record<string, PermissionState>,
): GuardianPermission[] {
  const rank = (id: string) => (states[id] === 'granted' ? 1 : 0)
  return [...permissions].sort((a, b) => rank(a.id) - rank(b.id))
}
