import { PrototypeIcon } from '@/features/prototype/PrototypeUI'
import { useI18n } from '@/lib/i18n'
import './TabBar.css'

/** @deprecated AppShell owns primary navigation. Kept for import compatibility. */
export type Tab = 'home' | 'routine' | 'circles' | 'profile' | 'gm'

const ICONS: Record<Tab, string> = {
  home: 'visibility',
  routine: 'schedule',
  circles: 'groups',
  profile: 'person',
  gm: 'admin_panel_settings',
}

export function TabBar({ active, onChange, onSos, sosBusy = false, alerts = 0 }: {
  active: Tab
  onChange: (tab: Tab) => void
  onSos: () => void
  sosBusy?: boolean
  alerts?: number
  isGm?: boolean
}) {
  const { t, lang } = useI18n()
  const tabs: Tab[] = ['home', 'routine', 'circles', 'profile']
  const renderTab = (tab: Tab) => (
    <button key={tab} type="button" className={`tabbar__btn${active === tab ? ' is-active' : ''}`} onClick={() => onChange(tab)}>
      <span className="tabbar__icon"><PrototypeIcon name={ICONS[tab]} />{tab === 'home' && alerts > 0 && <span className="tabbar__badge">{alerts}</span>}</span>
      <span className="tabbar__label">{t(`tab.${tab}`)}</span>
    </button>
  )
  return (
    <nav className="tabbar tabbar--mobile" aria-label={lang === 'zh' ? '主导航' : 'Primary navigation'}>
      {tabs.slice(0, 2).map(renderTab)}
      <button type="button" className="tabbar__sos" disabled={sosBusy} onClick={onSos}>{sosBusy ? '…' : t('sos')}</button>
      {tabs.slice(2).map(renderTab)}
    </nav>
  )
}
