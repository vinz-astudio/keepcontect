import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import {
  addQuietWindow,
  removeQuietWindow,
} from '@/features/baseline/configStore'
import { useI18n } from '@/lib/i18n'
import './LivenessCard.css'

/** 首页最顶部:一行「安全但不在」快捷(+2 / +4 / +6 小时)。
 *  有进行中的安全窗口时列出并可随时取消。详细配置在「作息」页。 */
export function SafeAwayBar() {
  const { t } = useI18n()
  const { config, reload } = useLivenessContext()

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
      <div className="liveness__row liveness__quick">
        <span className="liveness__rowlabel">{t('live.safeaway')}</span>
        <div className="liveness__seg">
          <button onClick={() => void addSafeWindow(120)}>+2h</button>
          <button onClick={() => void addSafeWindow(240)}>+4h</button>
          <button onClick={() => void addSafeWindow(360)}>+6h</button>
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
    </section>
  )
}
