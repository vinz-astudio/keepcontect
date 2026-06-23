import { useRef, useState, type PointerEvent, type ReactNode } from 'react'
import { toast } from '@/lib/toast'
import { useI18n } from '@/lib/i18n'
import './TabBar.css'

export type Tab = 'home' | 'routine' | 'circles' | 'profile' | 'gm'

const ICONS: Record<Tab, ReactNode> = {
  gm: (
    <>
      <path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z" />
      <path d="M9 12l2 2 4-4" />
    </>
  ),
  home: (
    <>
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <path d="M9 22V12h6v10" />
    </>
  ),
  routine: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3 2" />
    </>
  ),
  circles: (
    <>
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.9" />
      <path d="M16 3.1a4 4 0 0 1 0 7.8" />
    </>
  ),
  profile: (
    <>
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </>
  ),
}

const BASE_TABS: Tab[] = ['home', 'routine', 'circles', 'profile']
const HOLD_MS = 1400

interface Props {
  active: Tab
  onChange: (t: Tab) => void
  onSos: () => void
  sosBusy?: boolean
  alerts?: number
  isGm?: boolean
}

export function TabBar({
  active,
  onChange,
  onSos,
  sosBusy = false,
  alerts = 0,
  isGm = false,
}: Props) {
  const { t } = useI18n()
  const [hold, setHold] = useState(0)
  const rafRef = useRef<number | null>(null)
  const firedRef = useRef(false)
  const startedRef = useRef(false)
  const tabs: Tab[] = isGm ? [...BASE_TABS, 'gm'] : BASE_TABS
  const left = tabs.slice(0, 2)
  const right = tabs.slice(2)

  function stopRaf() {
    if (rafRef.current) cancelAnimationFrame(rafRef.current)
    rafRef.current = null
    setHold(0)
  }

  function startHold(e: PointerEvent) {
    if (sosBusy) return
    e.preventDefault()
    firedRef.current = false
    startedRef.current = true
    const t0 = performance.now()
    const tick = () => {
      const p = Math.min(1, (performance.now() - t0) / HOLD_MS)
      setHold(p)
      if (p >= 1) {
        firedRef.current = true
        stopRaf()
        onSos() // 长按满 → 真正发出求助
        return
      }
      rafRef.current = requestAnimationFrame(tick)
    }
    rafRef.current = requestAnimationFrame(tick)
  }

  function endHold() {
    if (startedRef.current && !firedRef.current) {
      toast(t('sos.hold'), 'info') // 只是点了一下 → 提示需长按，防误触
    }
    startedRef.current = false
    stopRaf()
  }

  function cancelHold() {
    startedRef.current = false
    stopRaf()
  }

  const btn = (tab: Tab) => (
    <button
      key={tab}
      className={`tabbar__btn${active === tab ? ' is-active' : ''}`}
      onClick={() => onChange(tab)}
      aria-current={active === tab ? 'page' : undefined}
    >
      <span className="tabbar__icon">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {ICONS[tab]}
        </svg>
        {tab === 'home' && alerts > 0 && (
          <span className="tabbar__badge">{alerts > 99 ? '99+' : alerts}</span>
        )}
      </span>
      <span className="tabbar__label">{t(`tab.${tab}`)}</span>
    </button>
  )

  return (
    <nav className="tabbar" aria-label="主导航">
      {left.map(btn)}
      <button
        className={`tabbar__sos${hold > 0 ? ' is-holding' : ''}`}
        aria-label={t('sos.aria')}
        title={t('sos.hold')}
        disabled={sosBusy}
        onPointerDown={startHold}
        onPointerUp={endHold}
        onPointerLeave={cancelHold}
        onPointerCancel={cancelHold}
      >
        <svg className="tabbar__sosring" viewBox="0 0 44 44" aria-hidden="true">
          <circle
            cx="22"
            cy="22"
            r="20"
            pathLength={1}
            style={{ strokeDasharray: 1, strokeDashoffset: 1 - hold }}
          />
        </svg>
        <span className="tabbar__soslabel">{sosBusy ? '…' : t('sos')}</span>
      </button>
      {right.map(btn)}
    </nav>
  )
}
