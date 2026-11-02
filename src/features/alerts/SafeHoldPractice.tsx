import { HoldRing } from '@/features/common/HoldRing'
import { SAFE_HOLD_MS } from '@/features/common/holdProgress'
import { useHoldToConfirm } from '@/features/common/useHoldToConfirm'
import { toast } from '@/lib/toast'
import './SafeHoldPractice.css'

/**
 * Practice for the "一切安好" hold (human decision 2026-11-02). Same ring and
 * timing as the alert screen, tied to no alert: it sends nothing and notifies
 * no one, so it can be tried at any time. A real safety ask clears itself as
 * soon as the person is active, so the real button is hard to reach on demand.
 */
export function SafeHoldPractice({ lang }: { lang: 'zh' | 'en' }) {
  const zh = lang === 'zh'
  const hold = useHoldToConfirm({
    durationMs: SAFE_HOLD_MS,
    onComplete: () => toast(zh ? '按住 3 秒有效 ✓（这是练习，没有发出任何确认）' : 'Held for 3 seconds ✓ (practice only, nothing was sent)', 'ok'),
    onEarlyRelease: () => toast(zh ? '请按住“一切安好”3 秒' : 'Hold “I am safe” for 3 seconds', 'info'),
  })
  return (
    <div className="safe-hold-practice">
      <button
        type="button"
        className={`safe-hold-practice__button${hold.holding ? ' is-holding' : ''}`}
        aria-describedby="safe-hold-practice-hint"
        {...hold.handlers}
      >
        <HoldRing progress={hold.progress} label={zh ? '练习：按住确认一切安好' : 'Practice: hold to confirm you are safe'}>
          <span className="safe-hold-practice__label">{zh ? '一切安好' : 'I am safe'}</span>
        </HoldRing>
      </button>
      <p id="safe-hold-practice-hint" className="muted safe-hold-practice__hint">
        {hold.holding
          ? (zh ? '继续按住…' : 'Keep holding…')
          : (zh ? '练习：按住 3 秒，不会发出任何确认' : 'Practice: hold for 3 seconds; nothing is sent')}
      </p>
    </div>
  )
}
