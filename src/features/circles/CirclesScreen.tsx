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
  labels,
}: {
  title: string
  subtitle: string
  circles: ReactNode
  community: ReactNode
  responsibilities: ReactNode
  onScanJoin?: () => void
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
      <PrototypeSection title={labels?.circles ?? 'Circles'}>{circles}</PrototypeSection>
      <PrototypeSection title={labels?.community ?? 'Community'}>{community}</PrototypeSection>
      <PrototypeSection title={labels?.responsibilities ?? 'Responsibilities'}>{responsibilities}</PrototypeSection>
    </div>
  )
}
