/**
 * ADR-0039: Concern may only be sent to someone who already has an active
 * alert. The server enforces this and raises `active alert required`; the UI
 * gate below exists so an admin is not invited to attempt something that will
 * be refused, and so the refusal reads as a rule rather than a malfunction.
 *
 * The gate is a courtesy, never the contract. Do not treat a true return here
 * as permission — the RPC re-checks.
 */

export const CONCERN_REQUIRES_ACTIVE_ALERT = 'active alert required'

/**
 * Shown when the server refuses. Not translated yet: the button gate makes this
 * reachable only from a stale row, and adding an i18n key is outside this
 * package's write set. Tracked as a follow-up.
 */
export const CONCERN_NEEDS_ALERT_MESSAGE = 'Concern needs an active alert on this person.'

export type ConcernTarget = {
  alerted?: boolean | null
}

/** True only when the target is currently under an active alert. */
export function gmConcernEligible(target: ConcernTarget | null | undefined): boolean {
  return target?.alerted === true
}

/**
 * Maps a failed Concern RPC to a message that says what the rule is. Any other
 * failure is passed through untouched so real errors stay visible.
 */
export function concernErrorMessage(error: unknown, fallback: string): string {
  const raw = error instanceof Error ? error.message : ''
  if (raw.includes(CONCERN_REQUIRES_ACTIVE_ALERT)) {
    return CONCERN_NEEDS_ALERT_MESSAGE
  }
  return raw || fallback
}
