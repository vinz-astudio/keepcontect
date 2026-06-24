import { Fragment, useEffect, useMemo, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { buildBaseline } from '@/features/baseline/engine'
import { getInstalledAt } from '@/features/baseline/configStore'
import { getAllSignals } from '@/features/signals/store'
import {
  SENSITIVITY_PRESETS,
  type LivenessStatus,
  type SignalEvent,
} from '@/features/baseline/types'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import { useAuth } from '@/features/auth/AuthProvider'
import './LivenessCard.css'

const HOUR = 3_600_000
const DAY = 86_400_000
const DAYS = 7

const STATUS_CLS: Record<LivenessStatus, string> = {
  normal: 'status--normal',
  learning: 'status--learning',
  alert: 'status--alert',
  safe_window: 'status--normal',
}
const STATUS_KEY: Record<LivenessStatus, I18nKey> = {
  normal: 'live.normal',
  learning: 'live.learning',
  alert: 'live.alert',
  safe_window: 'live.safe',
}
const HINT_KEY: Record<LivenessStatus, I18nKey> = {
  normal: 'live.hint.normal',
  learning: 'live.hint.learning',
  alert: 'live.hint.alert',
  safe_window: 'live.safe',
}

/** 时长(ms)→本地化人话,复用 live.* 文案 */
function fmtDur(ms: number | null | undefined): string {
  if (ms == null || !Number.isFinite(ms)) return '—'
  const min = Math.max(0, Math.round(ms / 60000))
  if (min < 60) return translate('live.min', { n: min })
  const h = Math.floor(min / 60)
  const m = min % 60
  return m ? translate('live.hourmin', { h, m }) : translate('live.hour', { h })
}

/** 单元格活跃强度分级(0=无,1~4 由该格活动数相对峰值决定) */
function level(count: number, max: number): number {
  if (count <= 0) return 0
  if (max <= 1) return 4
  const r = count / max
  if (r > 0.75) return 4
  if (r > 0.5) return 3
  if (r > 0.25) return 2
  return 1
}

/**
 * 守望状态 + 作息可视化 + 异常沉默判断依据。
 * 状态(原"learning your routine")与活跃节律图合并为一张卡,桌面端横跨两列。
 * 全部在端上由本地行为时序(IndexedDB)计算,绝不上传——与"判断完全线下"一致。
 */
export function RoutineInsights() {
  const { t, lang } = useI18n()
  const { evaluation, config, loading } = useLivenessContext()
  const [events, setEvents] = useState<SignalEvent[]>([])

  useEffect(() => {
    let on = true
    void getAllSignals()
      .then((e) => {
        if (on) setEvents(e)
      })
      .catch(() => {})
    return () => {
      on = false
    }
  }, [])

  // 近 7 天的每日 0 点(本地)——用来把事件落进 [天 × 24 小时] 网格
  const dayStarts = useMemo(() => {
    const out: number[] = []
    for (let i = DAYS - 1; i >= 0; i--) {
      const d = new Date()
      d.setHours(0, 0, 0, 0)
      d.setDate(d.getDate() - i)
      out.push(d.getTime())
    }
    return out
  }, [])

  const grid = useMemo(() => {
    const g = Array.from({ length: DAYS }, () => new Array<number>(24).fill(0))
    const from = dayStarts[0]
    for (const e of events) {
      if (e.t < from) continue
      const dt = new Date(e.t)
      let day = -1
      for (let k = 0; k < DAYS; k++) {
        const end = k < DAYS - 1 ? dayStarts[k + 1] : from + DAYS * DAY
        if (e.t >= dayStarts[k] && e.t < end) {
          day = k
          break
        }
      }
      if (day >= 0) g[day][dt.getHours()] += 1
    }
    return g
  }, [events, dayStarts])

  const maxCell = useMemo(
    () => grid.reduce((m, row) => Math.max(m, ...row), 0),
    [grid],
  )
  const hasData = maxCell > 0

  const model = useMemo(() => buildBaseline(events), [events])
  const auth = useAuth()
  const user = auth?.user
  const installedAt = useMemo(() => {
    return user?.created_at
      ? new Date(user.created_at).getTime()
      : getInstalledAt()
  }, [user?.created_at])
  const effectiveInstalledAt = useMemo(() => {
    return events.length > 0
      ? Math.max(installedAt, Math.min(...events.map((e) => e.t)))
      : installedAt
  }, [installedAt, events])
  const learnedDays = Math.max(0, Math.floor((Date.now() - effectiveInstalledAt) / DAY))
  const inLearning = learnedDays < config.learningDays

  const nowHour = new Date().getHours()
  const baselineMs =
    model.sampleCount > 0 ? model.expectedGapByHour[nowHour] : null

  const preset = SENSITIVITY_PRESETS[config.sensitivity]
  
  // Calculate dynamic threshold based on sensitivity
  const activeExpected = baselineMs ?? model.globalExpectedGap
  const calculatedThresholdMs = Math.max(activeExpected * preset.multiplier, preset.floorHours * HOUR)

  const status: LivenessStatus = evaluation?.status ?? 'learning'
  const statusHint = loading
    ? t('live.hint.loading')
    : status === 'safe_window'
      ? (evaluation?.reason ?? t(HINT_KEY[status]))
      : t(HINT_KEY[status])

  // Compute concrete duration result for each preset without showing the abstract formulas
  const sensitivityDesc = useMemo(() => {
    if (!activeExpected) return '—'
    const preset = SENSITIVITY_PRESETS[config.sensitivity]
    const calculated = activeExpected * preset.multiplier
    const floor = preset.floorHours * HOUR
    const resultMs = Math.max(calculated, floor)
    const formatted = fmtDur(resultMs)
    
    if (config.sensitivity === 'high') {
      return lang === 'zh'
        ? `敏感 (静默超过 ${formatted} 即告警)`
        : `Sensitive (Alerts if silence > ${formatted})`
    } else if (config.sensitivity === 'balanced') {
      return lang === 'zh'
        ? `平衡 (静默超过 ${formatted} 即告警)`
        : `Balanced (Alerts if silence > ${formatted})`
    } else {
      return lang === 'zh'
        ? `保守 (静默超过 ${formatted} 即告警)`
        : `Relaxed (Alerts if silence > ${formatted})`
    }
  }, [config.sensitivity, activeExpected, lang])

  const heroThresholdVal = inLearning
    ? fmtDur(evaluation?.thresholdMs)
    : fmtDur(calculatedThresholdMs)

  const thresholdSubtext = inLearning
    ? lang === 'zh'
      ? `学习期保底保护中。学习结束后预计为 ${fmtDur(calculatedThresholdMs)}。`
      : `Learning phase fallback active. Expected to be ${fmtDur(calculatedThresholdMs)} after learning.`
    : lang === 'zh'
      ? '系统基于此限度监控异常，超出即会发送通知。'
      : 'Silence exceeding this limit will trigger alert notifications.'

  return (
    <>
      <section className="card routine-hero">
        <div className="routine-hero__left" style={{ display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
          <div className={`routine-hero__status ${STATUS_CLS[status]}`}>
            <span className="status__dot" aria-hidden />
            <div className="routine-hero__statustext">
              <p className="routine-hero__label">{t(STATUS_KEY[status])}</p>
              <p className="routine-hero__hint">
                {statusHint}
                {evaluation && status !== 'safe_window' && (
                  <span className="liveness__gap">
                    {' '}
                    · {t('live.gap', { gap: fmtDur(evaluation.currentGapMs) })}
                  </span>
                )}
              </p>
            </div>
          </div>

          <p className="muted routine-hero__desc" style={{ margin: '0.5rem 0' }}>
            {t('routine.insights.desc')}
          </p>

          <div className="rhythm__progress" style={{ marginTop: '0.5rem' }}>
            <div className="rhythm__bar">
              <span
                style={{
                  width: `${Math.min(100, (learnedDays / config.learningDays) * 100)}%`,
                }}
              />
            </div>
            <p className="muted" style={{ margin: '0.25rem 0 0' }}>
              {inLearning
                ? t('routine.learn.progress', {
                    n: learnedDays,
                    total: config.learningDays,
                  })
                : t('routine.learn.done', { total: config.learningDays })}
            </p>
          </div>
        </div>

        <div className="routine-hero__right" style={{ display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
          {hasData ? (
            <>
              <div className="rhythm">
                <div
                  className="rhythm__grid"
                  role="img"
                  aria-label={t('routine.insights.title')}
                >
                  {grid.map((row, ri) => {
                    const date = new Date(dayStarts[ri])
                    const isToday = ri === DAYS - 1
                    return (
                      <Fragment key={ri}>
                        <span
                          className={`rhythm__daylabel${isToday ? ' is-today' : ''}`}
                          title={date.toLocaleDateString()}
                        >
                          {date.toLocaleDateString(undefined, {
                            weekday: 'short',
                          })}
                        </span>
                        {row.map((c, hi) => {
                          const lvl = level(c, maxCell)
                          return (
                            <span
                              key={hi}
                              className={`rhythm__cell${lvl ? ` is-on l${lvl}` : ''}`}
                              title={`${date.toLocaleDateString()} ${String(
                                hi,
                              ).padStart(2, '0')}:00 · ${c}`}
                            />
                          )
                        })}
                      </Fragment>
                    )
                  })}
                </div>
                <div className="rhythm__hours" aria-hidden>
                  <span />
                  {Array.from({ length: 24 }, (_, h) => (
                    <span key={h}>{h % 6 === 0 ? h : ''}</span>
                  ))}
                </div>
              </div>

              <div className="rhythm__legend" aria-hidden style={{ marginTop: '0.25rem' }}>
                <span>{t('routine.insights.legend.less')}</span>
                <i className="rhythm__cell" />
                <i className="rhythm__cell is-on l1" />
                <i className="rhythm__cell is-on l2" />
                <i className="rhythm__cell is-on l3" />
                <i className="rhythm__cell is-on l4" />
                <span>{t('routine.insights.legend.more')}</span>
              </div>
            </>
          ) : (
            <p className="muted">{t('routine.insights.empty')}</p>
          )}
        </div>
      </section>

      <section className="card">
        <h2 className="card__title">{t('routine.basis.title')}</h2>
        <p className="muted">{t('routine.basis.desc')}</p>

        {/* Highlighted Side-by-Side Comparison Blocks */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
          gap: '12px',
          marginBottom: '1rem',
          marginTop: '1rem'
        }}>
          {/* Left Block: Current Silence */}
          <div style={{
            background: 'var(--bg-soft)',
            border: '1px solid var(--line)',
            borderRadius: 'var(--r-md)',
            padding: '1rem',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            textAlign: 'center',
            gap: '4px'
          }}>
            <span style={{ fontSize: '0.8rem', color: 'var(--fg-muted)', fontWeight: '500' }}>
              {lang === 'zh' ? '当前已静默时间' : 'Current Silence'}
            </span>
            <span style={{ fontSize: '1.5rem', fontWeight: '700', color: 'var(--fg)' }}>
              {fmtDur(evaluation?.currentGapMs)}
            </span>
          </div>

          {/* Right Block: Alert Threshold (Hero Highlighted) */}
          <div style={{
            background: 'var(--accent-soft)',
            border: '1px solid var(--accent-line)',
            borderRadius: 'var(--r-md)',
            padding: '1rem',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            textAlign: 'center',
            gap: '4px'
          }}>
            <span style={{ fontSize: '0.8rem', color: 'var(--accent)', fontWeight: '600' }}>
              {lang === 'zh' ? '告警触发阈值' : 'Alert Threshold'}
            </span>
            <span style={{ fontSize: '1.5rem', fontWeight: '800', color: 'var(--accent)' }}>
              {heroThresholdVal}
            </span>
          </div>
        </div>

        <p className="muted" style={{ fontSize: '0.8rem', textAlign: 'center', margin: '0 0 1.25rem 0' }}>
          {thresholdSubtext}
        </p>

        <ul className="basis">
          <li className="basis__row">
            <span>{t('routine.basis.sensitivity')}</span>
            <strong>{sensitivityDesc}</strong>
          </li>
        </ul>

        <p className="basis__tune">{t('routine.basis.tune')}</p>
      </section>
    </>
  )
}
