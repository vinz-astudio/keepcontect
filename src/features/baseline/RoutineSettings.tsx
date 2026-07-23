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
import { toast } from '@/lib/toast'
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
  const [routinePattern, setRoutinePattern] = useState('regular_9to5')
  const [consentDataSharing, setConsentDataSharing] = useState(false)
  const [statusKey, setStatusKey] = useState(0)

  // States to track actual server values and saving/dirty status (KCA-18)
  const [serverSensitivity, setServerSensitivity] = useState<Sensitivity | null>(null)
  const [isSavingSensitivity, setIsSavingSensitivity] = useState(false)

  const [serverSleepWindow, setServerSleepWindow] = useState<{ start: string; end: string } | null>(null)

  const [serverRoutinePattern, setServerRoutinePattern] = useState<string>('regular_9to5')
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
        setRoutinePattern(p.routine_pattern)
        setConsentDataSharing(p.consent_data_sharing)
        setServerRoutinePattern(p.routine_pattern)
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

  // —— 短期:灵敏度 ——
  const sensitivityRow = (
    <div className="liveness__row">
      <span className="liveness__rowlabel">
        {t('live.sensitivity')}
        <span style={{ fontSize: '0.8rem', fontWeight: 'normal', marginLeft: '6px', color: isSensitivityDirty ? 'var(--danger)' : 'var(--fg-muted)' }}>
          {sensitivityStatus}
        </span>
      </span>
      <div className="liveness__seg liveness__seg--stacked">
        {(['high', 'balanced', 'low'] as Sensitivity[]).map((s) => (
          <button
            key={s}
            className={config.sensitivity === s ? 'active' : ''}
            disabled={isSavingSensitivity}
            onClick={async () => {
              if (isSavingSensitivity) return
              const previous = config.sensitivity
              setSensitivity(s)
              setIsSavingSensitivity(true)
              const res = await saveSensitivitySafe(s, previous)
              if (res.success) {
                setServerSensitivity(s)
                await reload()
                setStatusKey((k) => k + 1)
              } else {
                setSensitivity(previous)
                toast(t('err.save'), 'danger')
              }
              setIsSavingSensitivity(false)
            }}
          >
            <span className="liveness__seg-name">{t(`live.sens.${s}`)}</span>
            <span className="liveness__seg-delta">
              {s === 'high' ? '+0m' : s === 'balanced' ? '+45m' : '+90m'}
            </span>
          </button>
        ))}
      </div>
    </div>
  )

  // —— 长期:每周时间表 + 睡眠时间 + 作息模式 + 数据授权 ——
  const longConfigCard = (
    <section className="card">
      <h2 className="card__title">{t('tab.routine')}</h2>
      {scheduleInner}

      <div className="liveness__row">
        <span className="liveness__rowlabel">
          {t('live.sleep')}
          <span style={{ fontSize: '0.8rem', fontWeight: 'normal', marginLeft: '6px', color: isSleepDirty ? 'var(--danger)' : 'var(--fg-muted)' }}>
            {sleepStatus}
          </span>
        </span>
        <div className="liveness__custom">
          <input
            type="time"
            value={sleepStart}
            onChange={(e) => setSleepStart(e.target.value)}
            aria-label={t('live.sleep.start')}
          />
          <span>–</span>
          <input
            type="time"
            value={sleepEnd}
            onChange={(e) => setSleepEnd(e.target.value)}
            aria-label={t('live.sleep.end')}
          />
          <button disabled={sleepBusy} onClick={() => void saveSleep()}>
            {t('live.sleep.save')}
          </button>
          {sleepOn && (
            <button disabled={sleepBusy} onClick={() => void turnOffSleep()}>
              {t('live.sleep.off')}
            </button>
          )}
        </div>
      </div>
      <p className="muted liveness__sleephint">
        {sleepOn
          ? t('live.sleep.on', { start: sleepStart, end: sleepEnd })
          : t('live.sleep.disabled')}
      </p>

      {/* 作息模式选择 */}
      <div className="routine-mode">
        <div className="liveness__rowlabel routine-mode__label">
          {lang === 'zh' ? '作息模式' : 'Routine Mode'}
          <span style={{ fontSize: '0.8rem', fontWeight: 'normal', marginLeft: '6px', color: isRoutinePatternDirty ? 'var(--danger)' : 'var(--fg-muted)' }}>
            {routinePatternStatus}
          </span>
        </div>
        <p className="routine-mode__summary">{getRoutineModeSummary(lang)}</p>
        <div className="routine-mode__list">
          {getRoutineModeOptions(lang).map((item) => {
            const isActive = routinePattern === item.value
            return (
              <button
                key={item.value}
                className={`routine-mode__button${isActive ? ' is-active' : ''}`}
                disabled={isSavingRoutinePattern}
                onClick={async () => {
                  if (isSavingRoutinePattern) return
                  const previous = serverRoutinePattern
                  setRoutinePattern(item.value)
                  setIsSavingRoutinePattern(true)
                  const currentProfile = { routine_pattern: previous, consent_data_sharing: consentDataSharing }
                  const res = await updateRoutineProfileSafe({ routine_pattern: item.value }, currentProfile)
                  if (res.success) {
                    setServerRoutinePattern(item.value)
                    toast(lang === 'zh' ? '已更新作息模式' : 'Routine mode updated', 'ok')
                  } else {
                    setRoutinePattern(previous)
                    toast(t('err.save'), 'danger')
                  }
                  setIsSavingRoutinePattern(false)
                }}
              >
                <span className="routine-mode__copy">
                  <span>{item.label}</span>
                  <small>{item.description}</small>
                </span>
                {isActive && <span className="routine-mode__check">✓</span>}
              </button>
            )
          })}
        </div>
      </div>

      {/* 匿名数据共享授权 */}
      <div className="liveness__row" style={{ alignItems: 'flex-start' }}>
        <label className="toggle" style={{ gap: '10px', alignItems: 'flex-start', cursor: 'pointer' }}>
          <input
            type="checkbox"
            style={{ marginTop: '3px' }}
            checked={consentDataSharing}
            disabled={isSavingConsent}
            onChange={async (e) => {
              if (isSavingConsent) return
              const checked = e.target.checked
              const previous = serverConsentDataSharing
              setConsentDataSharing(checked)
              setIsSavingConsent(true)
              const currentProfile = { routine_pattern: routinePattern, consent_data_sharing: previous }
              const res = await updateRoutineProfileSafe({ consent_data_sharing: checked }, currentProfile)
              if (res.success) {
                setServerConsentDataSharing(checked)
                toast(lang === 'zh' ? '共享协议设置已更新' : 'Data sharing agreement updated', 'ok')
              } else {
                setConsentDataSharing(previous)
                toast(t('err.save'), 'danger')
              }
              setIsSavingConsent(false)
            }}
          />
          <span style={{ fontSize: '0.85rem', color: 'var(--fg-muted)', lineHeight: '1.4' }}>
            {lang === 'zh'
              ? '我同意授权匿名共享我的活跃频次数据,帮助改进作息分析模型且优化新用户的冷启动样板。'
              : 'I consent to anonymous sharing of my activity density data to help improve routine models and optimize patterns for new users.'}
            <span style={{ fontSize: '0.8rem', fontWeight: 'normal', marginLeft: '6px', color: isConsentDirty ? 'var(--danger)' : 'var(--fg-muted)' }}>
              {consentStatus}
            </span>
          </span>
        </label>
      </div>
    </section>
  )

  return (
    <div className="routine-grid">
      {/* 短期组:守护活跃度 + 判断依据 + 灵敏度,合成一个 block */}
      <div className="routine-grid__col1">
        <section className="card psig__short">
          <ActiveStatusBox
            statusLine={statusLine}
            serverLastAt={serverLastBehaviorAt}
            serverTruthRequired
          />
          {basisInner}
          {sensitivityRow}
        </section>
      </div>

      {/* 长期组:慢慢学习与长期设置 */}
      <div className="routine-grid__col2">
        {longConfigCard}
      </div>
    </div>
  )
}
