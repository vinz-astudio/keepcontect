import { useCallback, useEffect, useRef, useState } from 'react'
import { PrototypeBadge, PrototypeCard, PrototypeSection } from '@/features/prototype/PrototypeUI'
import { useI18n } from '@/lib/i18n'
import {
  DAILY_CHECKIN_LIMITS,
  defaultDailyCheckin,
  describeDailyCheckin,
  describeWorstCase,
  expectedQuestionsPerDay,
  formatLocalMinute,
  parseLocalMinute,
  validateDailyCheckin,
  type DailyCheckinDraft,
} from './dailyCheckin'
import {
  getDailyCheckin,
  observedActiveDaysRatio,
  saveDailyCheckin,
  type DailyCheckinStatus,
} from './dailyCheckinApi'
import { getPassiveCollectorHealth, passiveHealthCopy, type PassiveCollectorHealth } from './passiveCheckinPresentation'
import './PassiveCheckinSettings.css'

/**
 * Quiet-period choices, in the words people use about their own days.
 *
 * A free minute field was the old screen's mistake: it asked the subject to
 * pick a number they have no way to reason about. These four are the shapes a
 * person can actually hold an opinion on.
 */
const QUIET_CHOICES = [
  { minutes: 8 * 60, zh: '8 小时', en: '8 hours' },
  { minutes: 12 * 60, zh: '12 小时', en: '12 hours' },
  { minutes: 24 * 60, zh: '一天', en: 'A day' },
  { minutes: 48 * 60, zh: '两天', en: 'Two days' },
] as const

const GRACE_CHOICES = [
  { minutes: 30, zh: '30 分钟', en: '30 minutes' },
  { minutes: 2 * 60, zh: '2 小时', en: '2 hours' },
  { minutes: 4 * 60, zh: '4 小时', en: '4 hours' },
] as const

function deviceTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
  } catch {
    return 'UTC'
  }
}

export function PassiveCheckinSettings() {
  const { lang } = useI18n()
  const zh = lang === 'zh'
  const [status, setStatus] = useState<DailyCheckinStatus | null>(null)
  const [health, setHealth] = useState<PassiveCollectorHealth | null>(null)
  const [draft, setDraft] = useState<DailyCheckinDraft>(() => defaultDailyCheckin(deviceTimezone()))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  const errorRef = useRef<HTMLParagraphElement>(null)

  const load = useCallback(async () => {
    try {
      const [serverStatus, collectorHealth] = await Promise.all([
        getDailyCheckin(),
        getPassiveCollectorHealth(),
      ])
      setStatus(serverStatus)
      if (serverStatus?.draft) setDraft(serverStatus.draft)
      setHealth(collectorHealth)
      setError(null)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause))
    }
  }, [])

  useEffect(() => { void load() }, [load])
  useEffect(() => { if (error) errorRef.current?.focus() }, [error])

  if (!health) {
    return (
      <PrototypeSection title={zh ? '每日确认' : 'Daily check-in'}>
        <PrototypeCard>
          <p role={error ? 'alert' : 'status'}>
            {error ?? (zh ? '正在读取设置…' : 'Loading settings…')}
          </p>
        </PrototypeCard>
      </PrototypeSection>
    )
  }

  const problems = validateDailyCheckin(draft, zh)
  const sentences = describeDailyCheckin(draft, zh)
  const healthCopy = passiveHealthCopy(health, lang)
  const live = status?.engineMode === 'passive_checkin'
  const ratio = status ? observedActiveDaysRatio(status) : null
  const rate = expectedQuestionsPerDay(ratio)

  async function save(targetMode: 'shadow' | 'passive_checkin') {
    if (problems.length || busy) return
    setBusy(true)
    setError(null)
    setSaved(false)
    try {
      await saveDailyCheckin(draft, targetMode)
      await load()
      setSaved(true)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause))
    }
    setBusy(false)
  }

  return (
    <PrototypeSection
      title={zh ? '每日确认' : 'Daily check-in'}
      subtitle={zh
        ? 'KC 每天问你一次。如果你已经在用手机，它就不问。'
        : 'KC asks you once a day. If you have already been using your phone, it does not ask.'}
    >
      <PrototypeCard className="passive-checkin-settings">
        <div className="passive-checkin-settings__status">
          <PrototypeBadge tone={live ? 'ready' : status?.engineMode === 'shadow' ? 'limited' : 'unknown'}>
            {live ? (zh ? '已启用' : 'On') : status?.engineMode === 'shadow' ? (zh ? '观察中' : 'Observing') : (zh ? '未设置' : 'Not set')}
          </PrototypeBadge>
          {status?.effectiveAt && (
            <span>
              {zh ? `第 ${status.versionNumber} 版` : `Version ${status.versionNumber}`}
              {' · '}
              {new Date(status.effectiveAt).toLocaleString()}
            </span>
          )}
        </div>

        <label className="passive-checkin-settings__field">
          <span>{zh ? '每天什么时候问我' : 'When should KC ask'}</span>
          <input
            type="time"
            aria-label={zh ? '提醒时间' : 'Reminder time'}
            value={formatLocalMinute(draft.askAtLocalMinute)}
            onChange={(event) => {
              const minute = parseLocalMinute(event.target.value)
              if (minute !== null) setDraft({ ...draft, askAtLocalMinute: minute })
            }}
          />
        </label>

        <fieldset className="passive-checkin-settings__choices">
          <legend>{zh ? '多久完全没动静才需要问' : 'How long with no activity before asking'}</legend>
          {QUIET_CHOICES.map((choice) => (
            <label key={choice.minutes}>
              <input
                type="radio"
                name="daily-quiet"
                checked={draft.waiverLookbackMinutes === choice.minutes}
                onChange={() => setDraft({ ...draft, waiverLookbackMinutes: choice.minutes })}
              />
              {zh ? choice.zh : choice.en}
            </label>
          ))}
        </fieldset>

        <fieldset className="passive-checkin-settings__choices">
          <legend>{zh ? '没回应多久后通知信任的人' : 'How long before telling the people you trust'}</legend>
          {GRACE_CHOICES.map((choice) => (
            <label key={choice.minutes}>
              <input
                type="radio"
                name="daily-grace"
                checked={draft.responseGraceMinutes === choice.minutes}
                onChange={() => setDraft({ ...draft, responseGraceMinutes: choice.minutes })}
              />
              {zh ? choice.zh : choice.en}
            </label>
          ))}
        </fieldset>

        {/* The whole contract, restated in the subject's own settings. A screen
            that cannot say this plainly is asking someone to configure a thing
            they do not understand. */}
        <div className="passive-checkin-settings__contract">
          {sentences.map((line) => <p key={line}>{line}</p>)}
          <p className="passive-checkin-settings__worst">{describeWorstCase(zh)}</p>
        </div>

        {rate !== null && (
          <p className="passive-checkin-settings__rate">
            {zh
              ? `按你最近 ${status!.daysObserved} 天的实际情况，KC 平均每天问你 ${rate} 次。`
              : `Over your last ${status!.daysObserved} days, KC asked you ${rate} times a day on average.`}
          </p>
        )}

        <div className={`passive-checkin-settings__health is-${health.state}`}>
          <strong>{zh ? '采集状态' : 'Collector health'}: {healthCopy.label}</strong>
          <p>{healthCopy.detail}</p>
          {health.devices.filter((device) => device.state === 'limited').map((device) => (
            <p key={device.bindingId}><b>{device.device}</b> · {device.reason} · {device.repairAction}</p>
          ))}
        </div>

        {problems.length > 0 && (
          <ul className="passive-checkin-settings__errors">
            {problems.map((message) => <li key={message}>{message}</li>)}
          </ul>
        )}
        {error && (
          <p ref={errorRef} tabIndex={-1} role="alert" className="passive-checkin-settings__error">
            {zh ? '保存失败：' : 'Save failed: '}{error}
          </p>
        )}
        {saved && !error && (
          <p role="status" className="passive-checkin-settings__saved">
            {zh ? '已保存。' : 'Saved.'}
          </p>
        )}

        <div className="passive-checkin-settings__actions">
          <button
            type="button"
            className="prototype-button prototype-button--primary"
            disabled={busy || problems.length > 0}
            onClick={() => void save('passive_checkin')}
          >
            {busy ? (zh ? '正在保存…' : 'Saving…') : (zh ? '保存并启用' : 'Save and turn on')}
          </button>
          <button
            type="button"
            className="prototype-button"
            disabled={busy || problems.length > 0}
            onClick={() => void save('shadow')}
          >
            {zh ? '只观察，先不启用' : 'Observe only for now'}
          </button>
        </div>
        <p className="passive-checkin-settings__note">
          {zh
            ? `只观察：KC 照常记录，但是不会问你，也不会通知任何人。免签时长最短 ${DAILY_CHECKIN_LIMITS.minWaiverLookbackMinutes / 60} 小时。`
            : `Observe only: KC keeps recording but never asks and never notifies anyone. The shortest quiet period is ${DAILY_CHECKIN_LIMITS.minWaiverLookbackMinutes / 60} hours.`}
        </p>
      </PrototypeCard>
    </PrototypeSection>
  )
}
