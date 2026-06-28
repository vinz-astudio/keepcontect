import { useEffect, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { useRoutineInsights } from '@/features/baseline/RoutineInsights'
import { ActiveStatusBox } from '@/features/passive/ActiveStatusBox'
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

  const { statusLine, basisInner, scheduleInner } = useRoutineInsights(statusKey)

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

  // —— 短期:灵敏度(切换后即时刷新上方判断依据里的真实阈值)——
  const sensitivityRow = (
    <div className="liveness__row">
      <span className="liveness__rowlabel">{t('live.sensitivity')}</span>
      <div className="liveness__seg liveness__seg--stacked">
        {(['high', 'balanced', 'low'] as Sensitivity[]).map((s) => (
          <button
            key={s}
            className={config.sensitivity === s ? 'active' : ''}
            onClick={async () => {
              setSensitivity(s)
              await setServerSensitivity(s).catch(() => {})
              await reload()
              setStatusKey((k) => k + 1)
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
      <div className="routine-mode">
        <div className="liveness__rowlabel routine-mode__label">
          {lang === 'zh' ? '作息模式' : 'Routine Mode'}
        </div>
        <div className="routine-mode__list">
          {[
            { value: 'regular_9to5', label: lang === 'zh' ? '常规朝九晚五作息' : 'Regular 9-to-5' },
            { value: 'semester_break', label: lang === 'zh' ? '学期与假期交替作息' : 'Semester & Break' },
            { value: 'shift_irregular', label: lang === 'zh' ? '弹性/轮班不规律作息' : 'Flexible / Shift' },
          ].map((item) => {
            const isActive = routinePattern === item.value
            return (
              <button
                key={item.value}
                className={`routine-mode__button${isActive ? ' is-active' : ''}`}
                onClick={async () => {
                  setRoutinePattern(item.value)
                  try {
                    await updateRoutineProfile({ routine_pattern: item.value })
                    toast(lang === 'zh' ? '已更新作息模式' : 'Routine mode updated', 'ok')
                  } catch {
                    toast(lang === 'zh' ? '保存失败' : 'Failed to save', 'danger')
                  }
                }}
              >
                <span>{item.label}</span>
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
            onChange={async (e) => {
              const checked = e.target.checked
              setConsentDataSharing(checked)
              try {
                await updateRoutineProfile({ consent_data_sharing: checked })
                toast(lang === 'zh' ? '共享协议设置已更新' : 'Data sharing agreement updated', 'ok')
              } catch {
                toast(lang === 'zh' ? '保存失败' : 'Failed to save', 'danger')
              }
            }}
          />
          <span style={{ fontSize: '0.85rem', color: 'var(--fg-muted)', lineHeight: '1.4' }}>
            {lang === 'zh'
              ? '我同意授权匿名共享我的活跃频次数据,帮助改进作息分析模型且优化新用户的冷启动样板。'
              : 'I consent to anonymous sharing of my activity density data to help improve routine models and optimize patterns for new users.'}
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
          <ActiveStatusBox statusLine={statusLine} />
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
