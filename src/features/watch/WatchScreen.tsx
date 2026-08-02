import type { ReactNode } from 'react'
import {
  PrototypeCard,
  PrototypeIcon,
  PrototypeSection,
} from '@/features/prototype/PrototypeUI'
import { buildWatchSections, type WatchSectionKey } from './watchPresentation'
import './WatchScreen.css'

export function WatchScreen({
  title,
  subtitle,
  isGm,
  hasOwnTask,
  hasActiveAlert,
  summary,
  ownTask,
  gmTools,
  notifications,
  people,
  alertResponse,
  labels,
}: {
  title: string
  subtitle: string
  isGm: boolean
  hasOwnTask: boolean
  hasActiveAlert: boolean
  summary: ReactNode
  ownTask?: ReactNode
  gmTools?: ReactNode
  notifications: ReactNode
  people: ReactNode
  alertResponse?: ReactNode
  labels?: Partial<Record<'gm' | 'notifications' | 'people' | 'alert', string>>
}) {
  const sections = buildWatchSections({ hasOwnTask, isGm, hasActiveAlert })

  const renderSection = (section: WatchSectionKey) => {
    switch (section) {
      case 'summary':
        return (
          <section key={section} className="watch-screen__hero" aria-labelledby="watch-title">
            <span className={`watch-screen__status-icon${hasActiveAlert ? ' is-alert' : ''}`}>
              <PrototypeIcon name={hasActiveAlert ? 'emergency' : 'check_circle'} />
            </span>
            <h1 id="watch-title">{title}</h1>
            <p>{subtitle}</p>
            <div className="watch-screen__summary">{summary}</div>
          </section>
        )
      case 'own-task':
        return (
          <PrototypeCard key={section} compact className="watch-screen__own-task">
            {ownTask}
          </PrototypeCard>
        )
      case 'gm-tools':
        return (
          <PrototypeSection key={section} title={labels?.gm ?? 'Manager tools'}>
            <PrototypeCard compact className="watch-screen__manager">
              <span className="watch-screen__manager-icon"><PrototypeIcon name="admin_panel_settings" /></span>
              <div className="watch-screen__manager-content">{gmTools}</div>
            </PrototypeCard>
          </PrototypeSection>
        )
      case 'notifications':
        return (
          <PrototypeSection key={section} title={labels?.notifications ?? 'Notifications'}>
            {notifications}
          </PrototypeSection>
        )
      case 'people':
        return (
          <PrototypeSection key={section} title={labels?.people ?? 'Everyone’s Status'}>
            {people}
          </PrototypeSection>
        )
      case 'alert-response':
        return (
          <PrototypeSection key={section} title={labels?.alert ?? 'Needs action'}>
            <PrototypeCard tone="danger" className="watch-screen__alert-response">
              {alertResponse}
            </PrototypeCard>
          </PrototypeSection>
        )
    }
  }

  return <div className="watch-screen">{sections.map(renderSection)}</div>
}
