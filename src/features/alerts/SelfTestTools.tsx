import { useEffect, useState } from 'react'
import { getPushStatus, sendTestNotification, sendTestUnlock, type PushStatus } from '@/features/push/pushApi'
import { requestDesktopNotifierCheck } from '@/features/desktop/notificationPicker'
import { getNativeNotificationPermissionStatus } from '@/features/passive/native'
import { SafeHoldPractice } from '@/features/alerts/SafeHoldPractice'
import { getPlatform, isTauri } from '@/lib/platform'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import './NotificationsCard.css'

/**
 * Self-test tools: send a test notification, practise the "一切安好" hold, and
 * (GM only) raise a test safety ask. Shown in the notifications card body and
 * in the GM console, never inside a card header: the Home screen hides card
 * headers inside its sections, which is how the old toggle stayed invisible.
 */
export function SelfTestTools({ showUnlockTest = false }: { showUnlockTest?: boolean }) {
  const { t, lang } = useI18n()
  const [pushStatus, setPushStatus] = useState<PushStatus>('unsupported')
  // The iOS and Android apps have no Web Push; their channel is FCM/APNs,
  // ready once the OS notification permission is granted.
  const [nativePushReady, setNativePushReady] = useState(false)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [showHoldPractice, setShowHoldPractice] = useState(false)

  useEffect(() => {
    void getPushStatus().then(setPushStatus)
    void getNativeNotificationPermissionStatus().then((s) => setNativePushReady(s.granted))
  }, [])

  const desktop = isTauri()
  const platform = getPlatform()
  // Every surface that can receive a notification: Web Push, the iOS/Android
  // apps and the desktop app (OS notifications, DESK-01).
  const canReceive = pushStatus === 'subscribed' || nativePushReady || desktop
  const hintKey: I18nKey = desktop ? 'push.test.hint.desktop' : platform === 'android' ? 'push.test.hint.android' : 'push.test.hint'

  async function run(send: () => Promise<void>, sentKey: I18nKey) {
    setBusy(true)
    setError(null)
    try {
      await send()
      if (desktop) requestDesktopNotifierCheck()
      setMsg(t(sentKey))
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.op'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="pushbar">
      <p className="muted">
        {msg ?? (canReceive
          ? t(hintKey)
          : (lang === 'zh' ? '这台设备还没开启通知，测试通知会收不到；"试按「一切安好」"仍可使用。' : 'Notifications are not on for this device, so a test notification will not arrive; "Try I am safe" still works.'))}
      </p>
      <div className="pushbar__btns">
        <button className="pushbar__btn" disabled={busy} onClick={() => void run(sendTestNotification, 'push.test.sent')}>
          {t('push.test')}
        </button>
        <button
          className="pushbar__btn"
          aria-expanded={showHoldPractice}
          onClick={() => setShowHoldPractice((v) => !v)}
        >
          {lang === 'zh' ? '试按「一切安好」' : 'Try “I am safe”'}
        </button>
        {showUnlockTest && (
          <button className="pushbar__btn" disabled={busy} onClick={() => void run(sendTestUnlock, 'push.testUnlock.sent')}>
            {t('push.testUnlock')}
          </button>
        )}
      </div>
      {showUnlockTest && (
        <p className="muted" style={{ fontSize: '0.78rem', margin: '0.4rem 0 0' }}>
          {lang === 'zh'
            ? '"测试解锁通知"会建一个真的测试告警；你一有活动它就自动解除，解除时你的圈子会收到"告警已解除"通知。'
            : '"Test the unlock notification" raises a real test alert; it clears as soon as you are active, and your circle is told it cleared.'}
        </p>
      )}
      {error && <p className="home__error">{error}</p>}
      {showHoldPractice && <SafeHoldPractice lang={lang === 'zh' ? 'zh' : 'en'} />}
    </div>
  )
}
