import { useCallback, useEffect, useMemo, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { useI18n } from '@/lib/i18n'
import { isTauri } from '@/lib/platform'
import { OnboardingFlow } from '@/features/onboarding/OnboardingFlow'
import {
  resolveSetupResult,
  type OnboardingStep,
  type SetupCapability,
  type SetupResult,
} from '@/features/onboarding/onboardingPresentation'
import { getPushStatus } from '@/features/push/pushApi'
import {
  enableHealthWake,
  getGuardStatus,
  getNativeFcmToken,
  getNativeNotificationPermissionStatus,
  isActivityRecognitionEnabled,
  isBatteryExempt,
  isUsageStatsEnabled,
  openAutostartSettings,
  openUsageStatsSettings,
  requestActivityRecognitionPermission,
  requestBatteryExemption,
  requestNativeNotificationPermission,
} from './native'
import {
  isAndroidRequiredSetupReady,
  isIosRequiredSetupReady,
  resolveNativeNotificationReadiness,
} from './onboardingReadiness'

interface OnboardingWizardProps {
  isGm: boolean
  onComplete: () => void
}

export function OnboardingWizard({ isGm, onComplete }: OnboardingWizardProps) {
  void isGm
  const { lang } = useI18n()
  const [step, setStep] = useState<OnboardingStep>('value')
  const [capabilities, setCapabilities] = useState<SetupCapability[]>([])
  const [result, setResult] = useState<SetupResult>('unknown')
  const [busy, setBusy] = useState(false)
  const [autostartReviewed, setAutostartReviewed] = useState(false)
  const platform = Capacitor.getPlatform()
  const nativePhone = platform === 'android' || platform === 'ios'
  const isZh = lang === 'zh'

  const copy = useMemo(() => ({
    notifications: isZh ? '紧急通知' : 'Emergency notifications',
    notificationsDescription: isZh ? '让告警和确认请求能够及时到达。' : 'Allows alerts and confirmation requests to reach you.',
    motion: isZh ? '活动识别' : 'Activity recognition',
    motionDescription: isZh ? '使用低功耗活动信号判断日常活跃，不读取路线。' : 'Uses low-power activity signals without reading your route.',
    usage: isZh ? '最近使用时间' : 'Recent phone use',
    usageDescription: isZh ? '只读取最后使用时间，不读取任何应用内容。' : 'Reads only the last-used time, never app contents.',
    autostart: isZh ? '后台启动' : 'Background start',
    autostartDescription: isZh ? '部分 Android 手机需要允许自动启动。' : 'Some Android phones require autostart to be allowed.',
    guard: isZh ? '后台守护' : 'Background guard',
    guardDescription: isZh ? '确认这台手机的后台守护已经连接。' : 'Confirms that this phone’s background guard is connected.',
    health: isZh ? '健康数据唤醒' : 'Health wake',
    healthDescription: isZh
      ? '允许读取步数，为 iOS 增加一次低功耗唤醒机会。Apple 不会向 App 显示你是否拒绝了读取权限。'
      : 'Allows step-count reads to add another low-power iOS wake opportunity. Apple does not reveal whether read access was declined.',
    unavailable: isZh ? '此环境不支持完整的被动守护。安装手机 App 可获得完整保护。' : 'This environment cannot provide full passive protection. Install the phone app for full coverage.',
    enable: isZh ? '开启' : 'Enable',
    setUp: isZh ? '设置' : 'Set up',
    setUpDone: isZh ? '已设置' : 'Set up',
    review: isZh ? '检查' : 'Review',
    reviewed: isZh ? '已检查' : 'Reviewed',
  }), [isZh])

  const refreshCapabilities = useCallback(async (moveToResult = true) => {
    setBusy(true)
    try {
      let next: SetupCapability[]
      let requiredReady = false
      let unavailable = false

      if (platform === 'android') {
        const [notificationPermission, pushToken, motionReady, usageReady, guard, batteryExempt] = await Promise.all([
          getNativeNotificationPermissionStatus(),
          getNativeFcmToken(),
          isActivityRecognitionEnabled(),
          isUsageStatsEnabled(),
          getGuardStatus(),
          isBatteryExempt(),
        ])
        const notification = resolveNativeNotificationReadiness({
          permissionGranted: notificationPermission,
          tokenAvailable: Boolean(pushToken),
        })
        // The battery exemption is not in `requiredReady`: without it the guard
        // still works, it just has to fall back to the visible resident mode.
        // Blocking setup on it would turn a preference for quiet into a wall.
        requiredReady = isAndroidRequiredSetupReady({
          notification,
          usageGranted: usageReady,
          guardEnabled: Boolean(guard?.enabled),
        })
        next = [
          {
            key: 'notifications', icon: 'notifications_active', title: copy.notifications,
            description: copy.notificationsDescription, state: notification,
            requirement: 'required',
            actionLabel: copy.enable,
            onAction: async () => { await requestNativeNotificationPermission(); await refreshCapabilities(false) },
          },
          {
            key: 'motion', icon: 'directions_walk', title: copy.motion,
            description: copy.motionDescription, state: motionReady ? 'ready' : 'action',
            requirement: 'recommended',
            actionLabel: copy.enable,
            onAction: async () => { await requestActivityRecognitionPermission(); await refreshCapabilities(false) },
          },
          {
            key: 'usage', icon: 'schedule', title: copy.usage,
            description: copy.usageDescription, state: usageReady ? 'ready' : 'action',
            requirement: 'required',
            actionLabel: copy.enable,
            onAction: async () => { await openUsageStatsSettings() },
          },
          {
            key: 'guard', icon: 'shield', title: copy.guard,
            description: copy.guardDescription, state: guard?.enabled ? 'ready' : 'unknown',
            requirement: 'required',
          },
          {
            // Asked before the autostart step because this one is a single tap
            // in a system dialog, and getting it is what lets the guard stay
            // out of the notification shade entirely. The OEM autostart screen
            // below is the messy fallback for the ROMs this does not cover.
            key: 'battery', icon: 'battery_saver',
            title: lang === 'zh' ? '允许后台运行' : 'Allow background running',
            description: lang === 'zh'
              ? '允许 Keep Contact 后台运行,让 App 能安静和稳定地守护您,以尽可能即时地反映您的状态给予关心您的人。'
              : 'Allow Keep Contact to run in the background, so it can watch over you quietly and reliably, and let the people who care about you know how you are.',
            state: batteryExempt ? 'ready' : 'action',
            requirement: 'recommended',
            actionLabel: copy.enable,
            onAction: async () => { await requestBatteryExemption(); await refreshCapabilities(false) },
          },
          {
            key: 'autostart', icon: 'restart_alt', title: copy.autostart,
            description: copy.autostartDescription, state: autostartReviewed ? 'ready' : 'action',
            requirement: 'recommended',
            stateLabel: autostartReviewed ? copy.reviewed : undefined,
            actionLabel: copy.review,
            onAction: async () => { await openAutostartSettings(); setAutostartReviewed(true) },
          },
        ]
      } else if (platform === 'ios') {
        const [notificationPermission, guard] = await Promise.all([
          getNativeNotificationPermissionStatus(),
          getGuardStatus(),
        ])
        // Before APNs authorization, Firebase cannot mint an iOS token and the
        // native bridge would spend its retry window waiting for the impossible.
        const pushToken = notificationPermission ? await getNativeFcmToken() : null
        const notification = resolveNativeNotificationReadiness({
          permissionGranted: notificationPermission,
          tokenAvailable: Boolean(pushToken),
        })
        requiredReady = isIosRequiredSetupReady({
          notification,
          guardEnabled: Boolean(guard?.enabled),
        })
        const healthState = guard?.health?.observing
          ? 'ready'
          : guard?.health?.supported === false
            ? 'limited'
            : guard?.health?.supported
              ? 'action'
              : 'unknown'
        next = [
          {
            key: 'notifications', icon: 'notifications_active', title: copy.notifications,
            description: copy.notificationsDescription, state: notification,
            requirement: 'required',
            actionLabel: copy.enable,
            onAction: async () => { await requestNativeNotificationPermission(); await refreshCapabilities(false) },
          },
          {
            key: 'guard', icon: 'shield', title: copy.guard,
            description: copy.guardDescription, state: guard?.enabled ? 'ready' : 'unknown',
            requirement: 'required',
          },
          {
            key: 'health', icon: 'health_and_safety', title: copy.health,
            description: copy.healthDescription, state: healthState,
            requirement: 'recommended',
            stateLabel: healthState === 'ready' ? copy.setUpDone : undefined,
            actionLabel: copy.setUp,
            onAction: async () => { await enableHealthWake(); await refreshCapabilities(false) },
          },
        ]
      } else if (isTauri()) {
        unavailable = true
        next = [{ key: 'desktop', icon: 'computer', title: isZh ? '桌面辅助' : 'Desktop companion', description: copy.unavailable, state: 'limited' }]
      } else {
        const pushStatus = await getPushStatus()
        unavailable = true
        next = [{
          key: 'web', icon: 'install_mobile', title: isZh ? '网页版保护' : 'Web protection',
          description: copy.unavailable, state: pushStatus === 'subscribed' ? 'limited' : 'action',
          actionLabel: isZh ? '允许通知' : 'Allow notifications',
          onAction: async () => { if ('Notification' in window) await Notification.requestPermission(); await refreshCapabilities(false) },
        }]
      }

      setCapabilities(next)
      setResult(resolveSetupResult({ currentRunVerified: true, requiredReady, unavailable }))
      if (moveToResult) setStep('result')
    } catch {
      setResult('unknown')
      if (moveToResult) setStep('result')
    } finally {
      setBusy(false)
    }
  }, [autostartReviewed, copy, isZh, platform])

  useEffect(() => {
    if (step !== 'phone-setup' || capabilities.length > 0) return
    void refreshCapabilities(false)
  }, [capabilities.length, refreshCapabilities, step])

  useEffect(() => {
    if (!nativePhone) return
    const handleResume = () => { if (step !== 'value') void refreshCapabilities(false) }
    window.addEventListener('focus', handleResume)
    window.addEventListener('pageshow', handleResume)
    return () => {
      window.removeEventListener('focus', handleResume)
      window.removeEventListener('pageshow', handleResume)
    }
  }, [nativePhone, refreshCapabilities, step])

  return (
    <OnboardingFlow
      step={step}
      result={result}
      capabilities={capabilities}
      onStepChange={setStep}
      onRefresh={() => refreshCapabilities(true)}
      onComplete={onComplete}
      lang={lang}
      busy={busy}
    />
  )
}
