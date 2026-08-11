import { useCallback, useEffect, useState } from 'react'
import {
  isSpecialAttentionOn,
  listMySpecialAttention,
  setSpecialAttention,
  specialAttentionErrorKey,
  type SpecialAttentionSubscription,
} from '@/features/relationships/specialAttention'
import { useI18n } from '@/lib/i18n'
import './SpecialAttention.css'

/**
 * ADR-0039 Special Attention — the private, default-off preference.
 *
 * The subject is never told who subscribed, so this control shows only the
 * viewer's own state and says so in the hint. Every guarantee that matters
 * (eligibility, privacy, one notice per incident) is the server's; this is a
 * checkbox over `set_special_attention` and nothing more.
 */
export function SpecialAttentionToggle({ subject }: { subject: string }) {
  const { t } = useI18n()
  const [subs, setSubs] = useState<SpecialAttentionSubscription[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      setSubs(await listMySpecialAttention())
    } catch {
      // Unknown is not off. Leaving it null keeps the control out of the way
      // rather than drawing an unchecked box that claims nobody is watching.
      setSubs(null)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  if (subs === null) return null

  const on = isSpecialAttentionOn(subs, subject)

  async function toggle(next: boolean) {
    setBusy(true)
    setError(null)
    try {
      await setSpecialAttention(subject, next)
      await load()
    } catch (cause) {
      const key = specialAttentionErrorKey(cause)
      setError(key ? t(key) : (cause as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="special">
      <label className="special__row">
        <input
          type="checkbox"
          checked={on}
          disabled={busy}
          onChange={(event) => void toggle(event.target.checked)}
          data-testid={`special-attention-${subject}`}
        />
        <span className="special__label">{t('special.label')}</span>
      </label>
      {on && <p className="special__hint">{t('special.hint')}</p>}
      {error && <p className="special__error">{error}</p>}
    </div>
  )
}
