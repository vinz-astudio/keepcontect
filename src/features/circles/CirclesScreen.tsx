import type { ReactNode } from 'react'
import { PrototypeSection } from '@/features/prototype/PrototypeUI'
import './CirclesScreen.css'

export function CirclesScreen({
  title,
  subtitle,
  circles,
  community,
  responsibilities,
  labels,
}: {
  title: string
  subtitle: string
  circles: ReactNode
  community: ReactNode
  responsibilities: ReactNode
  labels?: Partial<Record<'circles' | 'community' | 'responsibilities', string>>
}) {
  return (
    <div className="circles-screen" data-circle-sections="circles,community,responsibilities">
      <header className="circles-screen__heading">
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </header>
      <PrototypeSection title={labels?.circles ?? 'Circles'}>{circles}</PrototypeSection>
      <PrototypeSection title={labels?.community ?? 'Community'}>{community}</PrototypeSection>
      <PrototypeSection title={labels?.responsibilities ?? 'Responsibilities'}>{responsibilities}</PrototypeSection>
    </div>
  )
}
