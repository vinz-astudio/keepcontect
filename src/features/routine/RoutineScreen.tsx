import type { ReactNode } from 'react'
import { ROUTINE_SECTION_ORDER } from './routinePresentation'
import './RoutineScreen.css'

export function RoutineScreen({
  title,
  subtitle,
  children,
}: {
  title: string
  subtitle: string
  children?: ReactNode
}) {
  return (
    <div
      className="routine-screen"
      data-routine-sections={ROUTINE_SECTION_ORDER.join(',')}
    >
      <header className="routine-screen__heading">
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </header>
      {children}
    </div>
  )
}
