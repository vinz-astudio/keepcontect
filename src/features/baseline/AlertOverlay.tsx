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
import { toast } from '@/lib/toast'
import { getAvailableSensors, isSensorEnabled, setSensorEnabled } from '@/features/signals/sensors'
import { getPlatform } from '@/lib/platform'
import {
  getPatternSavedMessage,
  getPatternSetupActiveIndex,
  getPatternSetupIntro,
  getPatternSetupNotice,
  getPatternSetupSteps,
  getPatternSetupText,
  patternsMatch,
  shouldShowSosAction,
  type PatternSetupStep,
} from '@/features/baseline/patternSetupFlow'
import './AlertOverlay.css'

export function AlertOverlay() {
  const { t, lang } = useI18n()
  const { serverAlert, mode, alertHint, confirmSafe, closeOverlay } =
    useLivenessContext()
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [sosSent, setSosSent] = useState(false)
  const [_, setRefresh] = useState(0)

  // 真告警：本地引擎判 alert，或 服务器已开告警（沉默/暗设备/被关心；SOS 本人主动发的不弹）
  const serverNeedsConfirm =
    serverAlert != null &&
    serverAlert.status === 'open' &&
    (serverAlert.cause === 'silence' ||
      serverAlert.cause === 'dark_device' ||
      serverAlert.cause === 'concern')
  const realAlert = serverNeedsConfirm
  // 从通知点进来时先乐观顶出解锁界面（alertHint），待 getMyOpenAlert 确认
  const showAsAlert = realAlert || alertHint

  // 弹遮罩：告警(含乐观)，或 用户主动进入的演练/设置
  const show = showAsAlert || mode !== 'none'

  // setup 模式（非告警时）：修改手势。已有手势必须先画当前手势验证身份,
  // 再画新手势并重复一次确认(防误触/防他人趁解锁状态偷改)。
  const forceSetup = mode === 'setup' && !showAsAlert
  const [setupStep, setSetupStep] = useState<PatternSetupStep>('draw')
  const [firstSeq, setFirstSeq] = useState<number[] | null>(null)
  // 修改手势有旧手势时是 3 步,否则 2 步;每步推进给一条绿色成功反馈
  const [hadOld, setHadOld] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [lockVersion, setLockVersion] = useState(0)
  useEffect(() => {
    if (forceSetup) {
      const has = hasPattern()
      setHadOld(has)
      setSetupStep(has ? 'verify' : 'draw')
      setFirstSeq(null)
      setNotice(null)
      setError(null)
      setLockVersion((version) => version + 1)
    }
  }, [forceSetup])

  // 已确认的真告警且 App 在前台：应用内主动发声 + 震动（不依赖系统通知设置）
  useEffect(() => {
    if (realAlert) {
      startAlarm()
      return () => stopAlarm()
    }
    stopAlarm()
  }, [realAlert])

  if (!show) return null

  // 告警路径:还没设过手势的用户在告警时现场设置(危机场景不加验证摩擦)
  const needSetup = !forceSetup && !hasPattern()
  // 告警不能"跳过"；演练/设置可以退出
  const exitable = !showAsAlert && mode !== 'none' && !(forceSetup && !hadOld)
  const showSosAction = shouldShowSosAction({ isPatternSetup: forceSetup })

  const title = showAsAlert
    ? serverAlert?.cause === 'concern'
      ? lang === 'zh'
        ? '有人在关心你'
        : 'Someone is checking on you'
      : t('overlay.title')
    : mode === 'setup'
      ? t('overlay.setup.title')
      : t('overlay.practice.title')

  const setupText = getPatternSetupText(setupStep, lang)

  const sub = showAsAlert
    ? serverAlert?.cause === 'concern'
      ? lang === 'zh'
        ? '画出手势，让关心你的人知道你安好。'
        : 'Draw your pattern so they know you are OK.'
      : needSetup
        ? t('overlay.sub.setup')
        : t('overlay.sub.verify')
    : mode === 'setup'
      ? getPatternSetupIntro(hadOld, lang)
      : needSetup
        ? t('overlay.practice.setup')
        : t('overlay.practice.verify')

  async function onComplete(seq: number[]) {
    setBusy(true)
    setError(null)
    try {
      if (forceSetup) {
        setNotice(null)
        // 修改手势三段式:验旧 → 画新 → 重画确认;每步清空格子+绿色反馈
        if (setupStep === 'verify') {
          if (await verifyPattern(seq)) {
            setNotice(getPatternSetupNotice('verified', lang))
            setSetupStep('draw')
          } else {
            setError(t('overlay.error'))
          }
        } else if (setupStep === 'draw') {
          setFirstSeq(seq)
          setNotice(getPatternSetupNotice('captured', lang))
          setSetupStep('confirm')
        } else if (patternsMatch(firstSeq, seq)) {
          await setPattern(seq)
          const localHash = localStorage.getItem('kc.patternHash')
          if (localHash) {
            await setServerPatternHash(localHash)
          }
          toast(`${getPatternSavedMessage(lang)} ✓`, 'ok')
          closeOverlay()
        } else {
          setError(getPatternSetupNotice('mismatch', lang))
          setFirstSeq(null)
          setSetupStep('draw')
        }
        return
      }
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
      setLockVersion((version) => version + 1)
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
      <div className={`overlay__card${forceSetup ? ' is-setup' : ''}`}>
        <h2 className="overlay__title">{title}</h2>
        <p className="overlay__sub">{sub}</p>
        
        {needSetup && (
          <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: '8px', margin: '8px 0 16px 0', padding: '10px', background: 'var(--bg-soft)', borderRadius: 'var(--r-md)', border: '1px solid var(--line)', textAlign: 'left' }}>
            <strong style={{ fontSize: '0.82rem', color: 'var(--fg)', display: 'block', marginBottom: '4px' }}>
              {lang === 'zh' ? '开启本设备自动感知触发源' : 'Enable Active Sensors'}
            </strong>
            {getAvailableSensors().filter(s => s.supported).map((sensor) => {
              const isEnabled = isSensorEnabled(sensor.key)
              return (
                <label key={sensor.key} style={{ display: 'flex', alignItems: 'flex-start', gap: '6px', fontSize: '0.78rem', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={isEnabled}
                    style={{ marginTop: '2px' }}
                    onChange={async (e) => {
                      await setSensorEnabled(sensor.key, e.target.checked)
                      setRefresh(r => r + 1)
                    }}
                  />
                  <div>
                    <span style={{ fontWeight: '600', display: 'block', color: 'var(--fg)' }}>{lang === 'zh' ? sensor.labelZh : sensor.labelEn}</span>
                    <span style={{ display: 'block', fontSize: '0.7rem', opacity: 0.7, lineHeight: '1.2' }}>{lang === 'zh' ? sensor.descZh : sensor.descEn}</span>
                  </div>
                </label>
              )
            })}

            {getPlatform() === 'ios' && (
              <div style={{ marginTop: '4px', borderTop: '1px dashed var(--line)', paddingTop: '6px', fontSize: '0.75rem', color: 'var(--accent)', lineHeight: '1.4' }}>
                <strong style={{ display: 'block', marginBottom: '2px' }}>
                  {lang === 'zh' ? '⚠️ iOS 自动守护提示：' : '⚠️ iOS Automated Watch Info:'}
                </strong>
                <span>
                  {lang === 'zh' 
                    ? 'iOS 系统限制了 Web 应用在后台的感知能力。如需在关闹钟、插拔充电器或打开常用 App 时自动报活，稍后可在【我】页面复制个人链接，并在【快捷指令】里手动创建自动化。'
                    : 'iOS limits background web apps. To automate check-ins from alarms, charging, or opening a frequent app, copy your personal link later in the Profile tab and create a Shortcuts automation manually.'}
                </span>
              </div>
            )}
          </div>
        )}

        {forceSetup && (
          <div className="overlay__steps" aria-label={lang === 'zh' ? '修改手势步骤' : 'Pattern change steps'}>
            {getPatternSetupSteps(hadOld, lang).map(({ key, label }, i) => {
              const activeIdx = getPatternSetupActiveIndex(hadOld, setupStep)
              return (
                <span
                  key={key}
                  className={`overlay__step${i === activeIdx ? ' is-active' : ''}${i < activeIdx ? ' is-done' : ''}`}
                >
                  {i < activeIdx ? '✓' : i + 1}. {label}
                </span>
              )
            })}
          </div>
        )}
        {notice && forceSetup && <p className="overlay__notice">{notice}</p>}

        <PatternLock
          key={forceSetup ? `setup-${setupStep}-${lockVersion}` : `main-${lockVersion}`}
          onComplete={onComplete}
          hint={
            forceSetup
              ? setupText.body
              : needSetup
                ? t('overlay.hint.setup')
                : t('overlay.hint.verify')
          }
        />
        {error && <p className="overlay__error">{error}</p>}
        {busy && <p className="overlay__busy">{t('overlay.busy')}</p>}

        {showSosAction && (
          sosSent ? (
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
          )
        )}

        {exitable ? (
          <button className="overlay__exit" onClick={() => closeOverlay()}>
            {mode === 'setup'
              ? t('overlay.setup.exit')
              : t('overlay.practice.exit')}
          </button>
        ) : showAsAlert ? (
          <p className="overlay__foot">{t('overlay.foot')}</p>
        ) : null}
      </div>
    </div>
  )
}
