import { useState } from 'react'
import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import {
  addQuietWindow,
  removeQuietWindow,
} from '@/features/baseline/configStore'
import { useI18n } from '@/lib/i18n'
import './LivenessCard.css'

/** 首页最顶部:一行「安全但不在」快捷(+2 / +4 小时 / 自定义)。
 *  有进行中的安全窗口时列出并可随时取消。详细配置在「作息」页。 */
export function SafeAwayBar() {
  const { t, lang } = useI18n()
  const { config, reload } = useLivenessContext()
  const [showCustom, setShowCustom] = useState(false)
  const [customD, setCustomD] = useState(0)
  const [customH, setCustomH] = useState(1)
  const [customM, setCustomM] = useState(0)

  const oneoffs = config.quietWindows
    .map((w, i) => ({ w, i }))
    .filter(({ w }) => w.kind === 'oneoff')

  function durationLabel(totalMin: number): string {
    const d = Math.floor(totalMin / 1440)
    const h = Math.floor((totalMin % 1440) / 60)
    const m = totalMin % 60
    const parts: string[] = []
    if (d) parts.push(t('live.dur.d', { d }))
    if (h) parts.push(t('live.dur.h', { h }))
    if (m) parts.push(t('live.dur.m', { m }))
    const dur = parts.length ? parts.join(' ') : t('live.dur.m', { m: 0 })
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
      <div className="liveness__row liveness__quick">
        <span className="liveness__rowlabel">{t('live.safeaway')}</span>
        <div className="liveness__seg">
          <button onClick={() => void addSafeWindow(120)}>+2h</button>
          <button onClick={() => void addSafeWindow(240)}>+4h</button>
          <button
            onClick={() => setShowCustom(!showCustom)}
            className={showCustom ? 'active' : ''}
          >
            {lang === 'zh' ? '自定义' : 'Custom'}
          </button>
        </div>
      </div>

      {showCustom && (
        <div className="liveness__row" style={{ marginTop: '0.5rem', animation: 'kc-rise 0.2s ease both' }}>
          <span className="liveness__rowlabel">{t('live.safeaway.custom')}</span>
          <div className="liveness__custom">
            <input
              type="number"
              min={0}
              max={30}
              value={customD}
              onChange={(e) => setCustomD(Math.max(0, Math.min(30, +e.target.value)))}
              aria-label={t('live.dur.d', { d: '' })}
            />
            <span>{t('live.dayUnit')}</span>
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
              disabled={customD * 1440 + customH * 60 + customM <= 0}
              onClick={async () => {
                await addSafeWindow(customD * 1440 + customH * 60 + customM)
                setShowCustom(false)
              }}
            >
              {t('live.safeaway.add')}
            </button>
          </div>
        </div>
      )}

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
    </section>
  )
}

