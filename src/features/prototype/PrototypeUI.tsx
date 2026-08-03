import {
  type CSSProperties,
  type ReactNode,
  useId,
  useState,
} from 'react'
import './PrototypeUI.css'

export type PrototypeTone = 'ready' | 'limited' | 'unknown' | 'action' | 'danger'
export type PrototypeState = 'loading' | 'empty' | 'limited' | 'unknown' | 'error'

export function PrototypeIcon({
  name,
  label,
  className = '',
}: {
  name: string
  label?: string
  className?: string
}) {
  return (
    <span
      className={`material-symbols-rounded prototype-icon ${className}`.trim()}
      aria-hidden={label ? undefined : true}
      aria-label={label}
    >
      {name}
    </span>
  )
}

export function PrototypeSection({
  title,
  subtitle,
  action,
  children,
  className = '',
}: {
  title: string
  subtitle?: string
  action?: ReactNode
  children?: ReactNode
  className?: string
}) {
  const headingId = useId()
  return (
    <section
      className={`prototype-section ${className}`.trim()}
      aria-labelledby={headingId}
    >
      <header className="prototype-section__header">
        <div>
          <h2 id={headingId} className="prototype-section__title">{title}</h2>
          {subtitle && <p className="prototype-section__subtitle">{subtitle}</p>}
        </div>
        {action}
      </header>
      {children}
    </section>
  )
}

export function PrototypeCard({
  children,
  compact = false,
  tone,
  className = '',
  style,
}: {
  children?: ReactNode
  compact?: boolean
  tone?: PrototypeTone
  className?: string
  style?: CSSProperties
}) {
  const classes = [
    'prototype-card',
    compact ? 'prototype-card--compact' : '',
    tone ? `prototype-card--${tone}` : '',
    className,
  ].filter(Boolean).join(' ')
  return <div className={classes} style={style}>{children}</div>
}

export function PrototypeBadge({
  tone,
  children,
  className = '',
}: {
  tone: PrototypeTone
  children?: ReactNode
  className?: string
}) {
  return (
    <span className={`prototype-badge prototype-badge--${tone} ${className}`.trim()}>
      {children}
    </span>
  )
}

export function PrototypeRow({
  icon,
  title,
  subtitle,
  trailing,
  children,
  className = '',
}: {
  icon?: string
  title: ReactNode
  subtitle?: ReactNode
  trailing?: ReactNode
  children?: ReactNode
  className?: string
}) {
  return (
    <div className={`prototype-row ${className}`.trim()}>
      {icon && <span className="prototype-row__icon"><PrototypeIcon name={icon} /></span>}
      <div className="prototype-row__main">
        <div className="prototype-row__title">{title}</div>
        {subtitle && <div className="prototype-row__subtitle">{subtitle}</div>}
        {children}
      </div>
      {trailing && <div className="prototype-row__trailing">{trailing}</div>}
    </div>
  )
}

export function PrototypeDisclosure({
  label,
  children,
  defaultOpen = false,
}: {
  label: string
  children?: ReactNode
  defaultOpen?: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)
  const panelId = useId()
  return (
    <div className="prototype-disclosure">
      <button
        type="button"
        className="prototype-disclosure__button"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={() => setOpen((value) => !value)}
      >
        <span>{label}</span>
        <PrototypeIcon name="expand_more" />
      </button>
      <div id={panelId} className="prototype-disclosure__panel" hidden={!open}>
        {children}
      </div>
    </div>
  )
}

export function PrototypeSegmented<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: T
  options: ReadonlyArray<{ value: T; label: string }>
  onChange: (value: T) => void
}) {
  return (
    <div className="prototype-segmented" role="radiogroup" aria-label={label}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={value === option.value}
          className="prototype-segmented__option"
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  )
}

const STATE_ICONS: Record<PrototypeState, string> = {
  loading: 'progress_activity',
  empty: 'inbox',
  limited: 'warning',
  unknown: 'help',
  error: 'cloud_off',
}

export function PrototypeStatePanel({
  state,
  title,
  message,
  retryLabel,
  onRetry,
}: {
  state: PrototypeState
  title: string
  message?: string
  retryLabel?: string
  onRetry?: () => void
}) {
  return (
    <div className={`prototype-state prototype-state--${state}`} role={state === 'error' ? 'alert' : 'status'}>
      <PrototypeIcon name={STATE_ICONS[state]} />
      <div className="prototype-state__copy">
        <strong>{title}</strong>
        {message && <span>{message}</span>}
      </div>
      {onRetry && retryLabel && (
        <button type="button" className="prototype-button prototype-button--ghost" onClick={onRetry}>
          {retryLabel}
        </button>
      )}
    </div>
  )
}
