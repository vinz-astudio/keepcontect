import { useCallback, useEffect, useState } from 'react'
import { useI18n } from '@/lib/i18n'
import {
  acknowledgeProtectionHealth,
  fetchProtectionHealth,
  protectionCopyKeys,
  protectionState,
  shouldPromptOnce,
  shouldSurfaceProtection,
  type ProtectionHealth,
} from '@/features/baseline/protectionHealth'
import './ProtectionHealthCard.css'

/**
 * ADR-0039: healthy is quiet, a known failure is visible, and unknown is
 * neither. This card renders nothing at all while protection is proven ready —
 * that silence is the reward for everything working. The moment it is not
 * proven, it stays on screen until real coverage returns.
 *
 * Dismissing the prompt changes the prompt. It never changes the state.
 */
export function ProtectionHealthCard() {
  const { t } = useI18n()
  const [health, setHealth] = useState<ProtectionHealth | null>(null)
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      setHealth(await fetchProtectionHealth())
    } catch {
      // A failed read tells us nothing about whether anyone is watching, so it
      // must not be allowed to look reassuring. Null reads as unknown.
      setHealth(null)
    } finally {
      setLoaded(true)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  if (!loaded || !shouldSurfaceProtection(health)) return null

  const state = protectionState(health)
  const copy = protectionCopyKeys(state)

  async function dismiss() {
    setBusy(true)
    try {
      await acknowledgeProtectionHealth()
      await load()
    } finally {
      setBusy(false)
    }
  }

  return (
    <section
      className={`health health--${state}`}
      role="status"
      aria-live="polite"
      data-testid="protection-health"
    >
      <h3 className="health__title">{t('health.title')}</h3>
      <p className="health__state">{t(copy.label)}</p>
      <p className="health__detail">{t(copy.detail)}</p>
      {shouldPromptOnce(health) && (
        <button className="health__ack" disabled={busy} onClick={() => void dismiss()}>
          {t('health.ack')}
        </button>
      )}
    </section>
  )
}
