/** Server-derived policy. Never infer a pattern requirement from alert stage. */
export function getConfirmationMethod(alert: {
  status: string
  requires_explicit_unlock?: boolean
  stage?: string
} | null): 'button' | 'pattern' | 'pending' {
  if (!alert || alert.status !== 'open' || typeof alert.requires_explicit_unlock !== 'boolean') return 'pending'
  return alert.requires_explicit_unlock ? 'pattern' : 'button'
}
