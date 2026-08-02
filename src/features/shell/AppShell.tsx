import {
  type PointerEvent,
  type ReactNode,
  useEffect,
  useRef,
  useState,
} from 'react'
import { PrototypeIcon } from '@/features/prototype/PrototypeUI'
import { toast } from '@/lib/toast'
import { useI18n } from '@/lib/i18n'
import {
  getSosHoldProgress,
  SOS_HOLD_MS,
  type PrimaryTab,
} from './appShellState'
import './AppShell.css'

const NAV_ITEMS: ReadonlyArray<{ tab: PrimaryTab; icon: string }> = [
  { tab: 'watch', icon: 'visibility' },
  { tab: 'routine', icon: 'schedule' },
  { tab: 'circles', icon: 'groups' },
  { tab: 'me', icon: 'person' },
]

export function AppShell({
  activeTab,
  onTabChange,
  onSos,
  displayName = '',
  unreadCount = 0,
  sosBusy = false,
  children,
}: {
  activeTab: PrimaryTab
  onTabChange: (tab: PrimaryTab) => void
  onSos: () => void | Promise<void>
  displayName?: string
  unreadCount?: number
  sosBusy?: boolean
  children?: ReactNode
}) {
  const { t, lang } = useI18n()
  const [holdProgress, setHoldProgress] = useState(0)
  const [holding, setHolding] = useState(false)
  const startedAtRef = useRef<number | null>(null)
  const frameRef = useRef<number | null>(null)
  const firedRef = useRef(false)

  const stopAnimation = () => {
    if (frameRef.current !== null) cancelAnimationFrame(frameRef.current)
    frameRef.current = null
  }

  const resetHold = () => {
    stopAnimation()
    startedAtRef.current = null
    setHolding(false)
    setHoldProgress(0)
  }

  useEffect(() => () => stopAnimation(), [])

  const tick = (now: number) => {
    const progress = getSosHoldProgress(startedAtRef.current, now)
    setHoldProgress(progress)
    if (progress >= 100) {
      firedRef.current = true
      resetHold()
      void onSos()
      return
    }
    frameRef.current = requestAnimationFrame(tick)
  }

  const startHold = (event: PointerEvent<HTMLButtonElement>) => {
    if (sosBusy || holding) return
    event.preventDefault()
    event.currentTarget.setPointerCapture?.(event.pointerId)
    firedRef.current = false
    startedAtRef.current = performance.now()
    setHolding(true)
    frameRef.current = requestAnimationFrame(tick)
  }

  const releaseHold = (showHint: boolean) => {
    const started = startedAtRef.current !== null
    const fired = firedRef.current
    resetHold()
    if (showHint && started && !fired) toast(t('sos.hold'), 'info')
  }

  const initials = displayName.trim().slice(0, 2).toUpperCase()
  const leftItems = NAV_ITEMS.slice(0, 2)
  const rightItems = NAV_ITEMS.slice(2)

  const tabLabels: Record<PrimaryTab, string> = {
    watch: t('tab.home'),
    routine: t('tab.routine'),
    circles: t('tab.circles'),
    me: t('tab.profile'),
  }

  const navButton = ({ tab, icon }: (typeof NAV_ITEMS)[number]) => (
    <button
      key={tab}
      type="button"
      className="app-shell__nav-button"
      data-tab={tab}
      aria-current={activeTab === tab ? 'page' : undefined}
      onClick={() => onTabChange(tab)}
    >
      <span className="app-shell__nav-icon">
        <PrototypeIcon name={icon} />
        {tab === 'watch' && unreadCount > 0 && (
          <span className="app-shell__unread">{unreadCount > 99 ? '99+' : unreadCount}</span>
        )}
      </span>
      <span>{tabLabels[tab]}</span>
    </button>
  )

  return (
    <div className={`app-shell app-shell--${activeTab}`}>
      <header className="app-shell__header">
        <span className="app-shell__brand">Keep Contact</span>
        {displayName && (
          <span className="app-shell__user" title={displayName}>
            <span className="app-shell__avatar" aria-hidden>{initials}</span>
            <span className="app-shell__user-name">{displayName}</span>
          </span>
        )}
      </header>

      <main className="app-shell__scroll" id="main-content">
        {children}
      </main>

      <nav className="app-shell__nav" aria-label={lang === 'zh' ? '主导航' : 'Primary navigation'}>
        {leftItems.map(navButton)}
        <button
          type="button"
          className={`app-shell__sos${holding ? ' is-holding' : ''}`}
          aria-label={t('sos.aria')}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={holdProgress}
          disabled={sosBusy}
          onPointerDown={startHold}
          onPointerUp={() => releaseHold(true)}
          onPointerCancel={() => releaseHold(false)}
          onLostPointerCapture={() => releaseHold(false)}
        >
          {sosBusy ? t('sos.sending') : t('sos')}
        </button>
        {rightItems.map(navButton)}
      </nav>

      {holding && (
        <div className="app-shell__sos-overlay" role="status" aria-live="polite">
          <PrototypeIcon name="emergency" className="app-shell__sos-overlay-icon" />
          <h2>{t('sos.hold')}</h2>
          <p>{Math.max(0, ((SOS_HOLD_MS * (100 - holdProgress)) / 100) / 1000).toFixed(1)}s</p>
          <progress max={100} value={holdProgress} aria-label={t('sos.hold')} />
          <span>{lang === 'zh' ? '松开即可取消' : 'Release to cancel'}</span>
        </div>
      )}
    </div>
  )
}
