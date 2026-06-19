import { useLivenessContext } from '@/features/baseline/LivenessProvider'
import {
  addQuietWindow,
  removeQuietWindow,
} from '@/features/baseline/configStore'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import type { LivenessStatus } from '@/features/baseline/types'
import './LivenessCard.css'

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

function fmtGap(ms: number): string {
  const min = Math.floor(ms / 60000)
  if (min < 60) return translate('live.min', { n: min })
  const h = Math.floor(min / 60)
  const m = min % 60
  return m ? translate('live.hourmin', { h, m }) : translate('live.hour', { h })
}

/** 首页状态卡：当前守望状态 + 一个快捷「安全但不在」。详细配置在「作息」页。 */
export function LivenessCard() {
  const { t } = useI18n()
  const { evaluation, config, loading, reload } = useLivenessContext()
  const status = evaluation?.status ?? 'learning'

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
    <section className={`status ${STATUS_CLS[status]} liveness`}>
      <div className="status__dot" aria-hidden />
      <p className="status__label">{t(STATUS_KEY[status])}</p>
      <p className="status__hint">
        {loading
          ? t('live.hint.loading')
          : status === 'safe_window'
            ? (evaluation?.reason ?? t(HINT_KEY[status]))
            : t(HINT_KEY[status])}
        {evaluation && status !== 'safe_window' && (
          <span className="liveness__gap">
            {' '}
            · {t('live.gap', { gap: fmtGap(evaluation.currentGapMs) })}
          </span>
        )}
      </p>

      {oneoffs.length > 0 ? (
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
      ) : (
        <div className="liveness__row liveness__quick">
          <span className="liveness__rowlabel">{t('live.safeaway')}</span>
          <div className="liveness__seg">
            <button onClick={() => void addSafeWindow(120)}>+2h</button>
            <button onClick={() => void addSafeWindow(240)}>+4h</button>
          </div>
        </div>
      )}
    </section>
  )
}
