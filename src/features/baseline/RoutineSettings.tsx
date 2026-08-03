import { useEffect, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { useRoutineInsights } from '@/features/baseline/RoutineInsights'
import { ActiveStatusBox } from '@/features/passive/ActiveStatusBox'
import { setSensitivity } from '@/features/baseline/configStore'
import {
  getSleepWindow,
  getServerSensitivity,
  saveSensitivitySafe,
  saveSleepWindowSafe,
  clearSleepWindowSafe,
  updateRoutineProfileSafe,
  detectTimezone,
  getServerTimezone,
  setServerTimezone,
} from '@/features/baseline/settingsApi'
import { useI18n } from '@/lib/i18n'
import type { Sensitivity } from '@/features/baseline/types'
import { getRoutineProfile } from '@/features/profile/profileApi'
import { getRoutineModeOptions, getRoutineModeSummary } from '@/features/baseline/routineModeCopy'
import { normalizeRoutineMode, type RoutineMode } from '@/features/baseline/routineMode'
import { toast } from '@/lib/toast'
import {
  PrototypeCard,
  PrototypeIcon,
  PrototypeRow,
  PrototypeSection,
} from '@/features/prototype/PrototypeUI'
import './LivenessCard.css'

/**
 * 兜底时区列表:只在引擎没有 `Intl.supportedValuesOf` 时才用。
 *
 * 这里曾经是**唯一**的列表,只有 8 项,不含 Asia/Thimphu —— 于是不丹用户的
 * `value` 匹配不到任何 option,浏览器退回显示第一项,界面上写着
 * "Asia/Shanghai" 而实际时区是 Asia/Thimphu,而且列表里根本没有正确选项可选。
 */
const FALLBACK_TIMEZONES = [
  'Asia/Thimphu',
  'Asia/Shanghai',
  'Asia/Kuala_Lumpur',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Europe/London',
  'America/New_York',
  'America/Los_Angeles',
  'UTC',
]

/** 当前时区相对 UTC 的偏移,给选项加一个人看得懂的后缀。 */
function timezoneOffsetLabel(tz: string): string {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      timeZoneName: 'shortOffset',
    }).formatToParts(new Date())
    const name = parts.find((p) => p.type === 'timeZoneName')?.value
    return name ? ` (${name})` : ''
  } catch {
    return ''
  }
}

function listTimezones(detected: string): string[] {
  let zones: string[] = []
  try {
    const supported = (Intl as unknown as { supportedValuesOf?: (k: string) => string[] })
      .supportedValuesOf
    if (typeof supported === 'function') zones = supported('timeZone')
  } catch {
    /* 老引擎:走兜底 */
  }
  if (zones.length === 0) zones = FALLBACK_TIMEZONES
  // 检测到的时区必须在列表里,否则 select 会显示成完全不相干的第一项。
  return zones.includes(detected) ? zones : [detected, ...zones]
}

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

  // Timezone. Auto-detection is the source of truth and is what the alert
  // engine actually uses; this control only exists to override it.
  const detectedTimezone = detectTimezone()
  const [timezoneOptions] = useState<string[]>(() => listTimezones(detectedTimezone))
  const [selectedTimezone, setSelectedTimezone] = useState<string>(detectedTimezone)
  const [isSavingTimezone, setIsSavingTimezone] = useState(false)

  /**
   * Writes the choice to `user_settings.timezone`. The previous version only
   * moved local state and then claimed success in a toast, so the sleep window
   * kept being evaluated against the detected zone no matter what was picked.
   */
  const chooseTimezone = async (tz: string) => {
    const previous = selectedTimezone
    setSelectedTimezone(tz)
    setIsSavingTimezone(true)
    try {
      await setServerTimezone(tz)
      toast(lang === 'zh' ? `时区已保存为 ${tz}` : `Timezone saved as ${tz}`, 'ok')
    } catch (err) {
      setSelectedTimezone(previous)
      toast(
        lang === 'zh'
          ? `时区保存失败:${err instanceof Error ? err.message : String(err)}`
          : `Could not save timezone: ${err instanceof Error ? err.message : String(err)}`,
        'danger',
      )
    } finally {
      setIsSavingTimezone(false)
    }
  }

  // The value binding is elided because nothing renders it — the setter is
  // still called on load and on save, so the state is written and never read.
  // Left in place rather than removed: that looks like a display that moved
  // during the prototype refactor, and deleting the writes would quietly change
  // whatever is meant to come back.
  const [, setServerSensitivity] = useState<Sensitivity | null>(null)
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
        if (s) setServerSensitivity(s)
      })
      .catch(() => {})

    // Show what the server actually stores, not what this device detects: if a
    // previous override is in effect the two differ, and displaying the
    // detected value would misreport which zone the alert maths is using.
    void getServerTimezone()
      .then((tz) => {
        if (tz) setSelectedTimezone(tz)
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
      toast(lang === 'zh' ? '已更新灵敏度' : 'Sensitivity updated', 'ok')
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
          />
          <div className="routine-prototype-settings__time-row" style={{ marginTop: 10 }}>
            <label>
              <span>{t('live.sleep.start')}</span>
              <input type="time" value={sleepStart} onChange={(event) => setSleepStart(event.target.value)} />
            </label>
            <label>
              <span>{t('live.sleep.end')}</span>
              <input type="time" value={sleepEnd} onChange={(event) => setSleepEnd(event.target.value)} />
            </label>
          </div>
          <div className="routine-prototype-settings__actions" style={{ marginTop: 12 }}>
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
        </PrototypeCard>
      </PrototypeSection>

      <PrototypeSection
        title={lang === 'zh' ? '提醒灵敏度' : 'Alert Sensitivity'}
        subtitle={lang === 'zh' ? '调节提醒提前或延后的缓冲，不会改变已学到的真实作息。' : 'Adjust the reminder buffer without replacing the routine evidence already learned.'}
      >
        <PrototypeCard>
          <ActiveStatusBox statusLine={statusLine} serverLastAt={serverLastBehaviorAt} serverTruthRequired />
          {basisInner}
          <div className="routine-prototype-settings__sensitivity" role="radiogroup" aria-label={t('live.sensitivity')} style={{ marginTop: 12 }}>
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
        </PrototypeCard>
      </PrototypeSection>

      <PrototypeSection
        title={lang === 'zh' ? '时区与隐私' : 'Timezone & Privacy'}
        subtitle={lang === 'zh' ? '可手动切换时区；共享选择与当前提醒估算分开处理。' : 'Select timezone manually; sharing choices stay separate from alert estimates.'}
      >
        <PrototypeCard>
          <div className="home-prototype__select-row" style={{ marginTop: 0, marginBottom: 12 }}>
            <span style={{ fontWeight: 600, color: 'var(--ink)' }}>{lang === 'zh' ? '设置时区' : 'Timezone'}</span>
            <select
              value={selectedTimezone}
              disabled={isSavingTimezone}
              onChange={(e) => void chooseTimezone(e.target.value)}
            >
              {timezoneOptions.map((tz) => (
                <option key={tz} value={tz}>
                  {tz}
                  {timezoneOffsetLabel(tz)}
                  {tz === detectedTimezone ? (lang === 'zh' ? ' · 自动检测' : ' · detected') : ''}
                </option>
              ))}
            </select>
          </div>

          <label className="routine-prototype-settings__check" style={{ borderTop: '1px solid var(--line)', paddingTop: 10 }}>
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
        </PrototypeCard>
      </PrototypeSection>
    </div>
  )
}
