import { useEffect, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { useRoutineInsights } from '@/features/baseline/RoutineInsights'
import { ActiveStatusBox } from '@/features/passive/ActiveStatusBox'
import {
  setSensitivity,
} from '@/features/baseline/configStore'
import {
  getSleepWindow,
  getServerSensitivity,
  saveSensitivitySafe,
  saveSleepWindowSafe,
  clearSleepWindowSafe,
  updateRoutineProfileSafe,
} from '@/features/baseline/settingsApi'
import { useI18n } from '@/lib/i18n'
import type { Sensitivity } from '@/features/baseline/types'
import { getRoutineProfile } from '@/features/profile/profileApi'
import { getRoutineModeOptions, getRoutineModeSummary } from '@/features/baseline/routineModeCopy'
import { normalizeRoutineMode, type RoutineMode } from '@/features/baseline/routineMode'
import { toast } from '@/lib/toast'
import {
  PrototypeBadge,
  PrototypeCard,
  PrototypeIcon,
  PrototypeRow,
  PrototypeSection,
} from '@/features/prototype/PrototypeUI'
import './LivenessCard.css'

/**
 * 作息/守望页。布局分两组(桌面左右两列、移动端上下堆叠):
 *  短期组:守护活跃度 + 当前守望状态 + 异常沉默判断依据 + 灵敏度。
 *  长期组:Routine block 内合并每周时间表 + 睡眠时间 + 作息模式 + 数据授权。
 */
export function RoutineSettings() {
  const { t, lang } = useI18n()
  const { config, reload } = useLivenessContext()
  const [sleepStart, setSleepStart] = useState('23:00')
  const [sleepEnd, setSleepEnd] = useState('07:00')
  const [sleepOn, setSleepOn] = useState(false)
  const [sleepBusy, setSleepBusy] = useState(false)
  const [routinePattern, setRoutinePattern] = useState<RoutineMode>('regular_9to5')
  const [consentDataSharing, setConsentDataSharing] = useState(false)
  const [statusKey, setStatusKey] = useState(0)

  // States to track actual server values and saving/dirty status (KCA-18)
  const [serverSensitivity, setServerSensitivity] = useState<Sensitivity | null>(null)
  const [isSavingSensitivity, setIsSavingSensitivity] = useState(false)

  const [serverSleepWindow, setServerSleepWindow] = useState<{ start: string; end: string } | null>(null)

  const [serverRoutinePattern, setServerRoutinePattern] = useState<RoutineMode>('regular_9to5')
  const [isSavingRoutinePattern, setIsSavingRoutinePattern] = useState(false)

  const [serverConsentDataSharing, setServerConsentDataSharing] = useState<boolean>(false)
  const [isSavingConsent, setIsSavingConsent] = useState(false)

  const { statusLine, basisInner, scheduleInner, serverLastBehaviorAt } = useRoutineInsights(statusKey)

  useEffect(() => {
    void getServerSensitivity()
      .then((s) => {
        if (s) {
          setServerSensitivity(s)
        }
      })
      .catch(() => {})

    void getSleepWindow()
      .then((w) => {
        if (w) {
          setSleepStart(w.start)
          setSleepEnd(w.end)
          setSleepOn(true)
          setServerSleepWindow(w)
        } else {
          setServerSleepWindow(null)
        }
      })
      .catch(() => {})

    void getRoutineProfile()
      .then((p) => {
        const normalizedPattern = normalizeRoutineMode(p.routine_pattern)
        setRoutinePattern(normalizedPattern)
        setConsentDataSharing(p.consent_data_sharing)
        setServerRoutinePattern(normalizedPattern)
        setServerConsentDataSharing(p.consent_data_sharing)
      })
      .catch(() => {})
  }, [])

  async function saveSleep() {
    setSleepBusy(true)
    const previous = serverSleepWindow
    const res = await saveSleepWindowSafe(sleepStart, sleepEnd, previous)
    if (res.success) {
      setSleepOn(true)
      setServerSleepWindow(res.value)
      toast(lang === 'zh' ? '已更新睡眠时间' : 'Sleep hours updated', 'ok')
    } else {
      if (previous) {
        setSleepStart(previous.start)
        setSleepEnd(previous.end)
        setSleepOn(true)
      } else {
        setSleepOn(false)
      }
      toast(t('err.save'), 'danger')
    }
    setSleepBusy(false)
  }

  async function turnOffSleep() {
    setSleepBusy(true)
    const previous = serverSleepWindow
    const res = await clearSleepWindowSafe(previous)
    if (res.success) {
      setSleepOn(false)
      setServerSleepWindow(null)
      toast(lang === 'zh' ? '已关闭睡眠时间' : 'Sleep hours disabled', 'ok')
    } else {
      if (previous) {
        setSleepStart(previous.start)
        setSleepEnd(previous.end)
        setSleepOn(true)
      }
      toast(t('err.save'), 'danger')
    }
    setSleepBusy(false)
  }

  // Dirty indicators and status texts (KCA-18)
  const isSensitivityDirty = serverSensitivity !== null && config.sensitivity !== serverSensitivity
  const sensitivityStatus = isSavingSensitivity
    ? (lang === 'zh' ? ' (保存中...)' : ' (Saving...)')
    : isSensitivityDirty
      ? (lang === 'zh' ? ' (未保存更改)' : ' (Unsaved Changes)')
      : (lang === 'zh' ? ' (已保存)' : ' (Saved)')

  const isSleepDirty = serverSleepWindow === null
    ? sleepOn
    : (!sleepOn || sleepStart !== serverSleepWindow.start || sleepEnd !== serverSleepWindow.end)
  const sleepStatus = sleepBusy
    ? (lang === 'zh' ? ' (保存中...)' : ' (Saving...)')
    : isSleepDirty
      ? (lang === 'zh' ? ' (未保存更改)' : ' (Unsaved Changes)')
      : (lang === 'zh' ? ' (已保存)' : ' (Saved)')

  const isRoutinePatternDirty = routinePattern !== serverRoutinePattern
  const routinePatternStatus = isSavingRoutinePattern
    ? (lang === 'zh' ? ' (保存中...)' : ' (Saving...)')
    : isRoutinePatternDirty
      ? (lang === 'zh' ? ' (未保存更改)' : ' (Unsaved Changes)')
      : (lang === 'zh' ? ' (已保存)' : ' (Saved)')

  const isConsentDirty = consentDataSharing !== serverConsentDataSharing
  const consentStatus = isSavingConsent
    ? (lang === 'zh' ? ' (保存中...)' : ' (Saving...)')
    : isConsentDirty
      ? (lang === 'zh' ? ' (未保存更改)' : ' (Unsaved Changes)')
      : (lang === 'zh' ? ' (已保存)' : ' (Saved)')

  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'

  async function chooseSensitivity(next: Sensitivity) {
    if (isSavingSensitivity) return
    const previous = config.sensitivity
    setSensitivity(next)
    setIsSavingSensitivity(true)
    const res = await saveSensitivitySafe(next, previous)
    if (res.success) {
      setServerSensitivity(next)
      await reload()
      setStatusKey((key) => key + 1)
    } else {
      setSensitivity(previous)
      toast(t('err.save'), 'danger')
    }
    setIsSavingSensitivity(false)
  }

  async function chooseRoutineType(next: RoutineMode) {
    if (isSavingRoutinePattern) return
    const previous = serverRoutinePattern
    setRoutinePattern(next)
    setIsSavingRoutinePattern(true)
    const currentProfile = { routine_pattern: previous, consent_data_sharing: consentDataSharing }
    const res = await updateRoutineProfileSafe({ routine_pattern: next }, currentProfile)
    if (res.success) {
      setServerRoutinePattern(next)
      toast(lang === 'zh' ? '已更新作息类型' : 'Routine type updated', 'ok')
    } else {
      setRoutinePattern(previous)
      toast(t('err.save'), 'danger')
    }
    setIsSavingRoutinePattern(false)
  }

  async function chooseConsent(checked: boolean) {
    if (isSavingConsent) return
    const previous = serverConsentDataSharing
    setConsentDataSharing(checked)
    setIsSavingConsent(true)
    const currentProfile = { routine_pattern: routinePattern, consent_data_sharing: previous }
    const res = await updateRoutineProfileSafe({ consent_data_sharing: checked }, currentProfile)
    if (res.success) {
      setServerConsentDataSharing(checked)
      toast(lang === 'zh' ? '共享设置已更新' : 'Sharing preference updated', 'ok')
    } else {
      setConsentDataSharing(previous)
      toast(t('err.save'), 'danger')
    }
    setIsSavingConsent(false)
  }

  return (
    <div className="routine-prototype-settings">
      <PrototypeSection
        title={lang === 'zh' ? '夜间休息与晨间缓冲' : 'Sleep & Morning Grace'}
        subtitle={lang === 'zh' ? '休息期间与起床后的短暂缓冲不会被误判为异常安静。' : 'Sleep and a short morning grace period are excluded from quiet-time judgement.'}
      >
        <PrototypeCard>
          {scheduleInner}
          <PrototypeRow
            icon="bedtime"
            title={t('live.sleep')}
            subtitle={sleepOn
              ? t('live.sleep.on', { start: sleepStart, end: sleepEnd })
              : t('live.sleep.disabled')}
            trailing={<PrototypeBadge tone={isSleepDirty ? 'limited' : 'ready'}>{sleepStatus.replace(/[()]/g, '')}</PrototypeBadge>}
          />
          <div className="routine-prototype-settings__time-row">
            <label>
              <span>{t('live.sleep.start')}</span>
              <input type="time" value={sleepStart} onChange={(event) => setSleepStart(event.target.value)} />
            </label>
            <label>
              <span>{t('live.sleep.end')}</span>
              <input type="time" value={sleepEnd} onChange={(event) => setSleepEnd(event.target.value)} />
            </label>
          </div>
          <div className="routine-prototype-settings__actions">
            <button className="prototype-button prototype-button--primary" disabled={sleepBusy} onClick={() => void saveSleep()}>
              {t('live.sleep.save')}
            </button>
            {sleepOn && (
              <button className="prototype-button prototype-button--ghost" disabled={sleepBusy} onClick={() => void turnOffSleep()}>
                {t('live.sleep.off')}
              </button>
            )}
          </div>
        </PrototypeCard>
      </PrototypeSection>

      <PrototypeSection
        title={lang === 'zh' ? '作息类型' : 'Routine type'}
        subtitle={getRoutineModeSummary(lang)}
      >
        <PrototypeCard compact>
          <div className="routine-prototype-settings__options">
            {getRoutineModeOptions(lang).map((item) => {
              const active = routinePattern === item.value
              return (
                <button
                  key={item.value}
                  type="button"
                  className="routine-prototype-settings__option"
                  aria-pressed={active}
                  disabled={isSavingRoutinePattern}
                  onClick={() => void chooseRoutineType(item.value)}
                >
                  <span>
                    <strong>{item.label}</strong>
                    <small>{item.description}</small>
                  </span>
                  {active && <PrototypeIcon name="check" />}
                </button>
              )
            })}
          </div>
          <p className="routine-prototype-settings__feedback" aria-live="polite">{routinePatternStatus}</p>
        </PrototypeCard>
      </PrototypeSection>

      <PrototypeSection
        title={lang === 'zh' ? '提醒灵敏度' : 'Alert Sensitivity'}
        subtitle={lang === 'zh' ? '调节提醒提前或延后的缓冲，不会改变已学到的真实作息。' : 'Adjust the reminder buffer without replacing the routine evidence already learned.'}
      >
        <PrototypeCard>
          <ActiveStatusBox statusLine={statusLine} serverLastAt={serverLastBehaviorAt} serverTruthRequired />
          {basisInner}
          <div className="routine-prototype-settings__sensitivity" role="radiogroup" aria-label={t('live.sensitivity')}>
            {(['high', 'balanced', 'low'] as Sensitivity[]).map((sensitivity) => (
              <button
                key={sensitivity}
                type="button"
                role="radio"
                aria-checked={config.sensitivity === sensitivity}
                disabled={isSavingSensitivity}
                onClick={() => void chooseSensitivity(sensitivity)}
              >
                <span>{t(`live.sens.${sensitivity}`)}</span>
                <small>{sensitivity === 'high' ? '+0m' : sensitivity === 'balanced' ? '+45m' : '+90m'}</small>
              </button>
            ))}
          </div>
          <p className="routine-prototype-settings__feedback" aria-live="polite">{sensitivityStatus}</p>
        </PrototypeCard>
      </PrototypeSection>

      <PrototypeSection
        title={lang === 'zh' ? '时区与隐私' : 'Timezone & Privacy'}
        subtitle={lang === 'zh' ? '时区来自本机；共享选择与当前提醒估算分开处理。' : 'Timezone comes from this phone; sharing choices stay separate from the current alert estimate.'}
      >
        <PrototypeCard>
          <PrototypeRow icon="globe" title={lang === 'zh' ? '本机时区' : 'This phone’s timezone'} subtitle={timezone} />
          <label className="routine-prototype-settings__check">
            <input
              type="checkbox"
              checked={consentDataSharing}
              disabled={isSavingConsent}
              onChange={(event) => void chooseConsent(event.target.checked)}
            />
            <span>
              <strong>{lang === 'zh' ? '允许匿名作息学习' : 'Allow anonymous routine learning'}</strong>
              <small>{lang === 'zh'
                ? '只共享用于改善冷启动模型的活跃频次，不共享手机内容。'
                : 'Shares activity frequency for cold-start improvement, never phone content.'}</small>
            </span>
          </label>
          <p className="routine-prototype-settings__feedback" aria-live="polite">{consentStatus}</p>
        </PrototypeCard>
      </PrototypeSection>
    </div>
  )
}
