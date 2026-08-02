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
  getGuardStatus,
  getNativeFcmToken,
  isActivityRecognitionEnabled,
  isUsageStatsEnabled,
  openAutostartSettings,
  openUsageStatsSettings,
  requestActivityRecognitionPermission,
  requestNativeNotificationPermission,
} from './native'

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
    unavailable: isZh ? '此环境不支持完整的被动守护。安装手机 App 可获得完整保护。' : 'This environment cannot provide full passive protection. Install the phone app for full coverage.',
    enable: isZh ? '开启' : 'Enable',
    review: isZh ? '检查' : 'Review',
  }), [isZh])

  const refreshCapabilities = useCallback(async (moveToResult = true) => {
    setBusy(true)
    try {
      let next: SetupCapability[]
      let requiredReady = false
      let unavailable = false

      if (platform === 'android') {
        const [pushToken, motionReady, usageReady, guard] = await Promise.all([
          getNativeFcmToken(),
          isActivityRecognitionEnabled(),
          isUsageStatsEnabled(),
          getGuardStatus(),
        ])
        const notificationReady = Boolean(pushToken)
        requiredReady = notificationReady && motionReady && usageReady && Boolean(guard?.enabled)
        next = [
          {
            key: 'notifications', icon: 'notifications_active', title: copy.notifications,
            description: copy.notificationsDescription, state: notificationReady ? 'ready' : 'action',
            actionLabel: copy.enable,
            onAction: async () => { await requestNativeNotificationPermission(); await refreshCapabilities(false) },
          },
          {
            key: 'motion', icon: 'directions_walk', title: copy.motion,
            description: copy.motionDescription, state: motionReady ? 'ready' : 'action',
            actionLabel: copy.enable,
            onAction: async () => { await requestActivityRecognitionPermission(); await refreshCapabilities(false) },
          },
          {
            key: 'usage', icon: 'schedule', title: copy.usage,
            description: copy.usageDescription, state: usageReady ? 'ready' : 'action',
            actionLabel: copy.enable,
            onAction: async () => { await openUsageStatsSettings() },
          },
          {
            key: 'guard', icon: 'shield', title: copy.guard,
            description: copy.guardDescription, state: guard?.enabled ? 'ready' : 'unknown',
          },
          {
            key: 'autostart', icon: 'restart_alt', title: copy.autostart,
            description: copy.autostartDescription, state: autostartReviewed ? 'ready' : 'action',
            actionLabel: copy.review,
            onAction: async () => { await openAutostartSettings(); setAutostartReviewed(true) },
          },
        ]
      } else if (platform === 'ios') {
        const [pushToken, guard] = await Promise.all([getNativeFcmToken(), getGuardStatus()])
        const notificationReady = Boolean(pushToken)
        requiredReady = notificationReady && Boolean(guard?.enabled)
        next = [
          {
            key: 'notifications', icon: 'notifications_active', title: copy.notifications,
            description: copy.notificationsDescription, state: notificationReady ? 'ready' : 'action',
            actionLabel: copy.enable,
            onAction: async () => { await requestNativeNotificationPermission(); await refreshCapabilities(false) },
          },
          {
            key: 'guard', icon: 'shield', title: copy.guard,
            description: copy.guardDescription, state: guard?.enabled ? 'ready' : 'unknown',
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
