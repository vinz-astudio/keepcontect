import { Fragment, useEffect, useMemo, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import { buildBaseline } from '@/features/baseline/engine'
import { getInstalledAt } from '@/features/baseline/configStore'
import { getAllSignals } from '@/features/signals/store'
import { SENSITIVITY_PRESETS, type SignalEvent } from '@/features/baseline/types'
import { translate, useI18n } from '@/lib/i18n'
import './LivenessCard.css'

const DAY = 86_400_000
const DAYS = 7

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
 * 作息可视化 + 异常沉默判断依据。
 * 全部在端上由本地行为时序(IndexedDB)计算,绝不上传——与"判断完全线下"一致。
 */
export function RoutineInsights() {
  const { t } = useI18n()
  const { evaluation, config } = useLivenessContext()
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
      // 找事件所属日列(midnight 升序,落在 [start, next) 内)
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

  // 基线模型(与判定引擎同一函数)+ 学习进度
  const model = useMemo(() => buildBaseline(events), [events])
  const installedAt = useMemo(() => getInstalledAt(), [])
  const learnedDays = Math.max(
    0,
    Math.floor((Date.now() - installedAt) / DAY),
  )
  const inLearning = learnedDays < config.learningDays

  // 此刻所在时段的常态间隔(样本不足时引擎已回退到全局)
  const nowHour = new Date().getHours()
  const baselineMs =
    model.sampleCount > 0 ? model.expectedGapByHour[nowHour] : null

  const preset = SENSITIVITY_PRESETS[config.sensitivity]

  return (
    <>
      <section className="card">
        <h2 className="card__title">{t('routine.insights.title')}</h2>
        <p className="muted">{t('routine.insights.desc')}</p>

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

            <div className="rhythm__legend" aria-hidden>
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

        <div className="rhythm__progress">
          <div className="rhythm__bar">
            <span
              style={{
                width: `${Math.min(100, (learnedDays / config.learningDays) * 100)}%`,
              }}
            />
          </div>
          <p className="muted">
            {inLearning
              ? t('routine.learn.progress', {
                  n: learnedDays,
                  total: config.learningDays,
                })
              : t('routine.learn.done', { total: config.learningDays })}
          </p>
        </div>
      </section>

      <section className="card">
        <h2 className="card__title">{t('routine.basis.title')}</h2>
        <p className="muted">{t('routine.basis.desc')}</p>

        <ul className="basis">
          <li className="basis__row">
            <span>{t('routine.basis.gap')}</span>
            <strong>{fmtDur(evaluation?.currentGapMs)}</strong>
          </li>
          <li className="basis__row">
            <span>{t('routine.basis.threshold')}</span>
            <strong>{fmtDur(evaluation?.thresholdMs)}</strong>
          </li>
          <li className="basis__row">
            <span>{t('routine.basis.baseline')}</span>
            <strong>
              {baselineMs != null ? fmtDur(baselineMs) : t('routine.basis.na')}
            </strong>
          </li>
          <li className="basis__row">
            <span>{t('routine.basis.sensitivity')}</span>
            <strong>
              {t(`live.sens.${config.sensitivity}`)}{' '}
              <em className="basis__sub">
                {t('routine.basis.sensFormula', {
                  mult: preset.multiplier,
                  floor: preset.floorHours,
                })}
              </em>
            </strong>
          </li>
          <li className="basis__row">
            <span>{t('routine.basis.samples')}</span>
            <strong>{t('routine.basis.sampleN', { n: events.length })}</strong>
          </li>
        </ul>

        <p className="basis__note">
          {t('routine.basis.thresholdHint')}
          {inLearning &&
            ` · ${t('routine.basis.learning', { h: config.coldStartGapHours })}`}
        </p>
        <p className="basis__tune">{t('routine.basis.tune')}</p>
      </section>
    </>
  )
}
