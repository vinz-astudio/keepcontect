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
import { supabase } from '@/lib/supabase'
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

  // 服务端真实状态:silence_threshold(当前时段真正触发告警的阈值)+ 最后行为时间
  const [serverStatus, setServerStatus] = useState<{
    threshold_seconds: number
    last_behavior_at: string | null
    sensitivity?: 'high' | 'balanced' | 'low'
    sleep_start?: string | null
    sleep_end?: string | null
    timezone?: string | null
    in_sleep_window?: boolean
  } | null>(null)
  useEffect(() => {
    let on = true
    void supabase.rpc('my_routine_status').then(({ data }) => {
      if (on && data) {
        setServerStatus(
          data as {
            threshold_seconds: number
            last_behavior_at: string | null
            sensitivity?: 'high' | 'balanced' | 'low'
            sleep_start?: string | null
            sleep_end?: string | null
            timezone?: string | null
            in_sleep_window?: boolean
          },
        )
      }
    })
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

  const orderedGridData = useMemo(() => {
    const data = dayStarts.map((start, ri) => {
      const date = new Date(start)
      const dayOfWeek = date.getDay() // 0 = Sun, 1 = Mon, ..., 6 = Sat
      const order = dayOfWeek === 0 ? 6 : dayOfWeek - 1 // Mon -> 0, Sun -> 6
      return {
        start,
        row: grid[ri],
        order,
        isToday: ri === DAYS - 1,
      }
    })
    data.sort((a, b) => a.order - b.order)
    return data
  }, [dayStarts, grid])

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

  const serverSensitivity = serverStatus?.sensitivity ?? config.sensitivity

  // Explain how the selected sensitivity changes the real server threshold.
  const sensitivityDesc = useMemo(() => {
    if (serverSensitivity === 'high') {
      return lang === 'zh'
        ? '敏感：缩短作息阈值，醒着时更快提醒。'
        : 'Sensitive: shortens the routine threshold for faster awake-hour alerts.'
    }
    if (serverSensitivity === 'balanced') {
      return lang === 'zh'
        ? '平衡：按作息画像使用当前阈值。'
        : 'Balanced: uses the current routine threshold as learned.'
    }
    return lang === 'zh'
      ? '保守：放宽作息阈值，减少误报但提醒更慢。'
      : 'Relaxed: lengthens the routine threshold to reduce false alerts.'
  }, [serverSensitivity, lang])

  // 优先用服务端真实阈值/gap;加载中回退本地估算,永不显示 '—'
  const serverThresholdMs =
    serverStatus != null ? serverStatus.threshold_seconds * 1000 : null
  const serverGapMs = serverStatus?.last_behavior_at
    ? Date.now() - new Date(serverStatus.last_behavior_at).getTime()
    : null
  const heroThresholdVal =
    serverThresholdMs != null
      ? fmtDur(serverThresholdMs)
      : fmtDur(calculatedThresholdMs)

  const sleepWindowLabel =
    serverStatus?.sleep_start && serverStatus.sleep_end
      ? `${serverStatus.sleep_start.slice(0, 5)}-${serverStatus.sleep_end.slice(0, 5)}`
      : null
  const thresholdSubtext = serverStatus?.in_sleep_window
    ? lang === 'zh'
      ? `当前在睡眠时间${sleepWindowLabel ? ` (${sleepWindowLabel})` : ''}内，静默告警会暂停；醒来后才按上方阈值判断。`
      : `Sleep hours${sleepWindowLabel ? ` (${sleepWindowLabel})` : ''} are active, so silence alerts are paused; after waking, the limit above applies.`
    : lang === 'zh'
      ? '这是当前时段真正会触发告警的静默上限，已综合作息画像、灵敏度和周末调整；睡眠时间内会暂停静默告警。'
      : 'This is the real server alert limit for this hour, combining routine profile, sensitivity, and weekend adjustment; sleep hours pause silence alerts.'

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
                  {orderedGridData.map(({ start, row, isToday }, idx) => {
                    const date = new Date(start)
                    return (
                      <Fragment key={idx}>
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
              {fmtDur(serverGapMs ?? evaluation?.currentGapMs)}
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
