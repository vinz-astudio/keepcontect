import { useRef, useState, type PointerEvent, type ReactNode } from 'react'
import { toast } from '@/lib/toast'
import { useI18n, LangToggle } from '@/lib/i18n'
import { ThemeToggle } from '@/lib/theme'
import { useAuth } from '@/features/auth/AuthProvider'
import './TabBar.css'

export type Tab = 'home' | 'routine' | 'circles' | 'profile' | 'gm'

export const ICONS: Record<Tab, ReactNode> = {
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
  const { t, lang } = useI18n()
  const [hold, setHold] = useState(0)
  const rafRef = useRef<number | null>(null)
  const firedRef = useRef(false)
  const startedRef = useRef(false)
  const tabs = BASE_TABS
  const left = tabs.slice(0, 2)
  const right = tabs.slice(2)

  let authContext: any = null
  try {
    authContext = useAuth()
  } catch {
    /* 忽略可能没有 context 的测试/错误场景 */
  }
  const user = authContext?.user
  const signOut = authContext?.signOut ?? (async () => {})
  const username = (user?.user_metadata?.display_name as string | undefined) ?? user?.email ?? ''

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
    <>
      {/* 移动端底部 Tab Bar (在大屏下通过 CSS 隐藏) */}
      <nav className="tabbar tabbar--mobile" aria-label="主导航">
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

      {/* 桌面端侧边栏 Sidenav (在小屏下通过 CSS 隐藏) */}
      <aside className="sidenav" aria-label="侧边导航">
        <div className="sidenav__brand">
          <span className="sidenav__logo" aria-hidden>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ display: 'inline-block', verticalAlign: 'middle' }}>
              <circle cx="12" cy="12" r="10" />
              <circle cx="12" cy="12" r="4" fill="currentColor" />
            </svg>
          </span>
          <span className="sidenav__appname">Keep Contact</span>
        </div>

        {user && (
          <div className="sidenav__user">
            <span className="sidenav__avatar">{username.slice(0, 2).toUpperCase()}</span>
            <div className="sidenav__userinfo">
              <span className="sidenav__hello">{t('home.hello')}</span>
              <span className="sidenav__username" title={username} style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap', marginTop: '2px' }}>
                <span style={{ maxWidth: '100px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{username}</span>
                <span style={{ 
                  display: 'inline-flex', 
                  alignItems: 'center', 
                  padding: '1px 6px', 
                  fontSize: '0.68rem', 
                  fontWeight: '600', 
                  borderRadius: '9999px',
                  background: isGm ? 'var(--accent-soft)' : 'var(--bg-soft)',
                  color: isGm ? 'var(--accent)' : 'var(--fg-muted)',
                  border: isGm ? '1px solid var(--accent-line)' : '1px solid var(--line)'
                }}>
                  {isGm ? (lang === 'zh' ? '守护者' : 'Caregiver') : (lang === 'zh' ? '被守护者' : 'Recipient')}
                </span>
              </span>
            </div>
          </div>
        )}

        <nav className="sidenav__menu">
          {tabs.map((tabKey) => (
            <button
              key={tabKey}
              className={`sidenav__menuitem${active === tabKey ? ' is-active' : ''}`}
              onClick={() => onChange(tabKey)}
              aria-current={active === tabKey ? 'page' : undefined}
            >
              <svg className="sidenav__icon" viewBox="0 0 24 24" aria-hidden="true">
                {ICONS[tabKey]}
              </svg>
              <span className="sidenav__label">{t(`tab.${tabKey}`)}</span>
              {tabKey === 'home' && alerts > 0 && (
                <span className="sidenav__badge">{alerts > 99 ? '99+' : alerts}</span>
              )}
            </button>
          ))}
        </nav>

        <div className="sidenav__sos-box">
          <button
            className={`sidenav__sos${hold > 0 ? ' is-holding' : ''}`}
            disabled={sosBusy}
            onPointerDown={startHold}
            onPointerUp={endHold}
            onPointerLeave={cancelHold}
            onPointerCancel={cancelHold}
          >
            <svg className="sidenav__sosring" viewBox="0 0 44 44" aria-hidden="true">
              <circle
                cx="22"
                cy="22"
                r="20"
                pathLength={1}
                style={{ strokeDasharray: 1, strokeDashoffset: 1 - hold }}
              />
            </svg>
            <span className="sidenav__soslabel">{sosBusy ? '…' : t('sos')}</span>
          </button>
          <p className="sidenav__sos-hint">{t('sos.hold')}</p>
        </div>

        <div className="sidenav__footer" style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
          <ThemeToggle className="sidenav__footbtn" />
          <LangToggle className="sidenav__footbtn" />
          <button className="sidenav__footbtn" onClick={() => void signOut()}>
            {t('header.signout')}
          </button>
        </div>
      </aside>
    </>
  )
}
