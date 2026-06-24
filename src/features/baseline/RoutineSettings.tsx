import { useEffect, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { RoutineInsights } from '@/features/baseline/RoutineInsights'
import {
  setSensitivity,
} from '@/features/baseline/configStore'
import {
  clearSleepWindow,
  getSleepWindow,
  setServerSensitivity,
  setSleepWindow,
} from '@/features/baseline/settingsApi'
import { useI18n } from '@/lib/i18n'
import type { Sensitivity } from '@/features/baseline/types'
import { getRoutineProfile, updateRoutineProfile } from '@/features/profile/profileApi'
import { toast } from '@/lib/toast'
import './LivenessCard.css'

/** 作息/守望规则配置页：灵敏度、睡眠时间 */
export function RoutineSettings() {
  const { t, lang } = useI18n()
  const { config, reload } = useLivenessContext()
  const [sleepStart, setSleepStart] = useState('23:00')
  const [sleepEnd, setSleepEnd] = useState('07:00')
  const [sleepOn, setSleepOn] = useState(false)
  const [sleepBusy, setSleepBusy] = useState(false)
  const [routinePattern, setRoutinePattern] = useState('regular_9to5')
  const [consentDataSharing, setConsentDataSharing] = useState(false)

  useEffect(() => {
    void getSleepWindow()
      .then((w) => {
        if (w) {
          setSleepStart(w.start)
          setSleepEnd(w.end)
          setSleepOn(true)
        }
      })
      .catch(() => {})

    void getRoutineProfile()
      .then((p) => {
        setRoutinePattern(p.routine_pattern)
        setConsentDataSharing(p.consent_data_sharing)
      })
      .catch(() => {})
  }, [])

  async function saveSleep() {
    setSleepBusy(true)
    try {
      await setSleepWindow(sleepStart, sleepEnd)
      setSleepOn(true)
    } catch {
      /* 忽略 */
    } finally {
      setSleepBusy(false)
    }
  }

  async function turnOffSleep() {
    setSleepBusy(true)
    try {
      await clearSleepWindow()
      setSleepOn(false)
    } catch {
      /* 忽略 */
    } finally {
      setSleepBusy(false)
    }
  }

  return (
    <div className="routine-grid">
      <RoutineInsights />
      <section className="card">
        <h2 className="card__title">{t('tab.routine')}</h2>
        <p className="muted">{t('routine.desc')}</p>

        <div className="liveness__row">
          <span className="liveness__rowlabel">{t('live.sensitivity')}</span>
          <div className="liveness__seg">
            {(['high', 'balanced', 'low'] as Sensitivity[]).map((s) => (
              <button
                key={s}
                className={config.sensitivity === s ? 'active' : ''}
                onClick={async () => {
                  setSensitivity(s)
                  void setServerSensitivity(s).catch(() => {})
                  await reload()
                }}
              >
                {t(`live.sens.${s}`)}
              </button>
            ))}
          </div>
        </div>

        <div className="liveness__row">
          <span className="liveness__rowlabel">{t('live.sleep')}</span>
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
        <div className="liveness__row">
          <span className="liveness__rowlabel">{lang === 'zh' ? '作息模式' : 'Routine Mode'}</span>
          <select
            value={routinePattern}
            onChange={async (e) => {
              const val = e.target.value
              setRoutinePattern(val)
              try {
                await updateRoutineProfile({ routine_pattern: val })
                toast(lang === 'zh' ? '已更新作息模式' : 'Routine mode updated', 'ok')
              } catch (err) {
                toast(lang === 'zh' ? '保存失败' : 'Failed to save', 'danger')
              }
            }}
            style={{
              flex: 1,
              padding: '8px 12px',
              border: '1px solid var(--line)',
              borderRadius: 'var(--r-md)',
              background: 'var(--bg-soft)',
              color: 'var(--fg)',
              cursor: 'pointer'
            }}
          >
            <option value="regular_9to5">{lang === 'zh' ? '常规朝九晚五作息' : 'Regular 9-to-5'}</option>
            <option value="semester_break">{lang === 'zh' ? '学期与假期交替作息' : 'Semester & Break'}</option>
            <option value="shift_irregular">{lang === 'zh' ? '弹性/轮班不规律作息' : 'Flexible / Shift'}</option>
          </select>
        </div>

        {/* 匿名数据共享授权 */}
        <div className="liveness__row" style={{ alignItems: 'flex-start' }}>
          <label className="toggle" style={{ gap: '10px', alignItems: 'flex-start', cursor: 'pointer' }}>
            <input
              type="checkbox"
              style={{ marginTop: '3px' }}
              checked={consentDataSharing}
              onChange={async (e) => {
                const checked = e.target.checked
                setConsentDataSharing(checked)
                try {
                  await updateRoutineProfile({ consent_data_sharing: checked })
                  toast(lang === 'zh' ? '共享协议设置已更新' : 'Data sharing agreement updated', 'ok')
                } catch (err) {
                  toast(lang === 'zh' ? '保存失败' : 'Failed to save', 'danger')
                }
              }}
            />
            <span style={{ fontSize: '0.85rem', color: 'var(--fg-muted)', lineHeight: '1.4' }}>
              {lang === 'zh' 
                ? '我同意授权匿名共享我的活跃频次数据，帮助改进作息分析模型且优化新用户的冷启动样板。' 
                : 'I consent to anonymous sharing of my activity density data to help improve routine models and optimize patterns for new users.'}
            </span>
          </label>
        </div>
      </section>
    </div>
  )
}
