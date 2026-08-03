import type { ReactNode } from 'react'
import { PrototypeIcon, PrototypeSection } from '@/features/prototype/PrototypeUI'
import './CirclesScreen.css'

export function CirclesScreen({
  title,
  subtitle,
  circles,
  community,
  responsibilities,
  onScanJoin,
  onCreateGroup,
  onCreateCommunity,
  labels,
}: {
  title: string
  subtitle: string
  circles: ReactNode
  community: ReactNode
  responsibilities: ReactNode
  onScanJoin?: () => void
  onCreateGroup?: () => void
  onCreateCommunity?: () => void
  labels?: Partial<Record<'circles' | 'community' | 'responsibilities', string>>
}) {
  return (
    <div className="circles-screen" data-circle-sections="circles,community,responsibilities">
      <header className="circles-screen__heading">
        <div className="circles-screen__header-row">
          <div>
            <h1>{title}</h1>
            <p>{subtitle}</p>
          </div>
          {onScanJoin && (
            <button
              type="button"
              className="prototype-button prototype-button--ghost circles-screen__scan-btn"
              onClick={onScanJoin}
            >
              <PrototypeIcon name="qr_code_scanner" />
              <span>Scan QR</span>
            </button>
          )}
        </div>
      </header>

      <div className="circles-screen__section-wrap">
        <div className="circles-screen__section-header">
          <span>{labels?.circles ?? 'Circles'}</span>
          {onCreateGroup && (
            <button type="button" className="prototype-button prototype-button--ghost circles-screen__add-btn" onClick={onCreateGroup}>
              + Create
            </button>
          )}
        </div>
        <PrototypeSection>{circles}</PrototypeSection>
      </div>

      <div className="circles-screen__section-wrap">
        <div className="circles-screen__section-header">
          <span>{labels?.community ?? 'Community'}</span>
          {onCreateCommunity && (
            <button type="button" className="prototype-button prototype-button--ghost circles-screen__add-btn" onClick={onCreateCommunity}>
              + Create
            </button>
          )}
        </div>
        <PrototypeSection>{community}</PrototypeSection>
      </div>

      <PrototypeSection title={labels?.responsibilities ?? 'Responsibilities'}>{responsibilities}</PrototypeSection>
    </div>
  )
}
