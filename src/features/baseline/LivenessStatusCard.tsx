import { useLivenessContext } from '@/features/baseline/LivenessProvider'
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

/** 守望状态(含「learning your routine」)。已从首页移到「作息」页顶部。 */
export function LivenessStatusCard() {
  const { t } = useI18n()
  const { evaluation, loading } = useLivenessContext()
  const status = evaluation?.status ?? 'learning'

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
    </section>
  )
}
