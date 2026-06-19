import { useEffect, useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import {
  addQuietWindow,
  removeQuietWindow,
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
import './LivenessCard.css'

/** 作息/守望规则配置页：灵敏度、安全但不在、睡眠时间、解锁手势 */
export function RoutineSettings() {
  const { t } = useI18n()
  const { config, reload, startPractice, startSetup } = useLivenessContext()
  const [customH, setCustomH] = useState(1)
  const [customM, setCustomM] = useState(0)
  const [sleepStart, setSleepStart] = useState('23:00')
  const [sleepEnd, setSleepEnd] = useState('07:00')
  const [sleepOn, setSleepOn] = useState(false)
  const [sleepBusy, setSleepBusy] = useState(false)

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

  const oneoffs = config.quietWindows
    .map((w, i) => ({ w, i }))
    .filter(({ w }) => w.kind === 'oneoff')

  function durationLabel(totalMin: number): string {
    const h = Math.floor(totalMin / 60)
    const m = totalMin % 60
    const dur = m
      ? h
        ? t('live.dur.hm', { h, m })
        : t('live.dur.m', { m })
      : t('live.dur.h', { h })
    return `${t('live.safeaway')} ${dur}`
  }

  async function addSafeWindow(totalMin: number) {
    if (totalMin <= 0) return
    const now = Date.now()
    addQuietWindow({
      kind: 'oneoff',
      start: now,
      end: now + totalMin * 60_000,
      label: durationLabel(totalMin),
    })
    await reload()
  }

  return (
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

      <div className="liveness__row">
        <span className="liveness__rowlabel">{t('live.safeaway.custom')}</span>
        <div className="liveness__custom">
          <input
            type="number"
            min={0}
            max={23}
            value={customH}
            onChange={(e) => setCustomH(Math.max(0, Math.min(23, +e.target.value)))}
            aria-label={t('live.dur.h', { h: '' })}
          />
          <span>{t('live.hourUnit')}</span>
          <input
            type="number"
            min={0}
            max={59}
            step={5}
            value={customM}
            onChange={(e) => setCustomM(Math.max(0, Math.min(59, +e.target.value)))}
            aria-label={t('live.dur.m', { m: '' })}
          />
          <span>{t('live.minUnit')}</span>
          <button
            disabled={customH * 60 + customM <= 0}
            onClick={() => void addSafeWindow(customH * 60 + customM)}
          >
            {t('live.safeaway.add')}
          </button>
        </div>
      </div>

      {oneoffs.length > 0 && (
        <ul className="liveness__windows">
          {oneoffs.map(({ w, i }) => (
            <li key={i}>
              <span>
                {w.label} · {t('live.until')}{' '}
                {new Date(w.end!).toLocaleTimeString([], {
                  hour: '2-digit',
                  minute: '2-digit',
                })}
              </span>
              <button
                onClick={async () => {
                  removeQuietWindow(i)
                  await reload()
                }}
              >
                {t('live.cancel')}
              </button>
            </li>
          ))}
        </ul>
      )}

      <div className="liveness__row">
        <span className="liveness__rowlabel">{t('live.pattern')}</span>
        <div className="liveness__seg">
          <button onClick={startSetup}>{t('live.setPattern')}</button>
          <button onClick={startPractice}>{t('live.practice')}</button>
        </div>
      </div>
    </section>
  )
}
