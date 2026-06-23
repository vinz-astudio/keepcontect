import { useEffect, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { PatternLock } from '@/features/pattern/PatternLock'
import {
  hasPattern,
  setPattern,
  verifyPattern,
} from '@/features/pattern/patternStore'
import { startAlarm, stopAlarm } from '@/features/baseline/alarm'
import { raiseSos } from '@/features/alerts/api'
import { triggerPushDispatch } from '@/features/push/pushApi'
import { getCurrentCoords } from '@/lib/geo'
import { useI18n } from '@/lib/i18n'
import { setServerPatternHash } from '@/features/baseline/settingsApi'
import './AlertOverlay.css'

export function AlertOverlay() {
  const { t } = useI18n()
  const { evaluation, serverAlert, mode, alertHint, confirmSafe, closeOverlay } =
    useLivenessContext()
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [sosSent, setSosSent] = useState(false)

  // 真告警：本地引擎判 alert，或 服务器已开告警（沉默/暗设备；SOS 本人主动发的不弹）
  const serverNeedsConfirm =
    serverAlert != null &&
    serverAlert.status === 'open' &&
    (serverAlert.cause === 'silence' || serverAlert.cause === 'dark_device')
  const realAlert = evaluation?.status === 'alert' || serverNeedsConfirm
  // 从通知点进来时先乐观顶出解锁界面（alertHint），待 getMyOpenAlert 确认
  const showAsAlert = realAlert || alertHint

  // 弹遮罩：告警(含乐观)，或 用户主动进入的演练/设置
  const show = showAsAlert || mode !== 'none'

  // 已确认的真告警且 App 在前台：应用内主动发声 + 震动（不依赖系统通知设置）
  useEffect(() => {
    if (realAlert) {
      startAlarm()
      return () => stopAlarm()
    }
    stopAlarm()
  }, [realAlert])

  if (!show) return null

  // setup 模式（非告警时）强制设置——首次或"修改手势"，覆盖旧手势
  const forceSetup = mode === 'setup' && !showAsAlert
  const needSetup = forceSetup || !hasPattern()
  // 告警不能"跳过"；演练/设置可以退出
  const exitable = !showAsAlert && mode !== 'none'

  const title = showAsAlert
    ? t('overlay.title')
    : mode === 'setup'
      ? t('overlay.setup.title')
      : t('overlay.practice.title')

  const sub = showAsAlert
    ? needSetup
      ? t('overlay.sub.setup')
      : t('overlay.sub.verify')
    : mode === 'setup'
      ? t('overlay.setup.sub')
      : needSetup
        ? t('overlay.practice.setup')
        : t('overlay.practice.verify')

  async function onComplete(seq: number[]) {
    setBusy(true)
    setError(null)
    try {
      if (needSetup) {
        await setPattern(seq)
        const localHash = localStorage.getItem('kc.patternHash')
        if (localHash) {
          await setServerPatternHash(localHash)
        }
        await confirmSafe()
      } else if (await verifyPattern(seq)) {
        await confirmSafe()
      } else {
        setError(t('overlay.error'))
      }
    } finally {
      setBusy(false)
    }
  }

  async function onSos() {
    if (sosSent) return
    setBusy(true)
    setError(null)
    try {
      const coords = await getCurrentCoords() // 附带实时位置
      await raiseSos(coords?.lat, coords?.lng)
      void triggerPushDispatch() // 不等 cron，立即推送到 Group
      setSosSent(true)
    } catch {
      setError(t('err.op'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="overlay" role="dialog" aria-modal="true">
      <div className="overlay__card">
        <h2 className="overlay__title">{title}</h2>
        <p className="overlay__sub">{sub}</p>
        <PatternLock
          onComplete={onComplete}
          hint={needSetup ? t('overlay.hint.setup') : t('overlay.hint.verify')}
        />
        {error && <p className="overlay__error">{error}</p>}
        {busy && <p className="overlay__busy">{t('overlay.busy')}</p>}

        {/* 求助：解不开/真有事时一键 SOS 通知 Group */}
        {sosSent ? (
          <p className="overlay__sosnote">{t('sos.sent')}</p>
        ) : (
          <button
            className="overlay__sos"
            aria-label={t('sos.aria')}
            disabled={busy}
            onClick={() => void onSos()}
          >
            {t('sos')}
          </button>
        )}

        {exitable ? (
          <button className="overlay__exit" onClick={() => closeOverlay()}>
            {mode === 'setup'
              ? t('overlay.setup.exit')
              : t('overlay.practice.exit')}
          </button>
        ) : (
          <p className="overlay__foot">{t('overlay.foot')}</p>
        )}
      </div>
    </div>
  )
}
