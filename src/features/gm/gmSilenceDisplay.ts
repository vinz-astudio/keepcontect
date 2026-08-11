/**
 * Turning a GM row into the two things a GM has to decide between.
 *
 * `silent` on its own is not actionable. A person who has gone quiet is a
 * welfare question; a device that stopped reporting is a maintenance question,
 * and treating the second as the first spends the group's willingness to
 * respond on a technical fault. ADR-0039: a known failure must be visible, and
 * must not be dressed up as danger.
 */

export type SilenceKind = 'person_quiet' | 'device_dark' | 'unknown'
export type AlertCause = 'silence' | 'dark_device' | 'concern' | 'sos'

export interface SilenceRow {
  status?: string | null
  alert_cause?: AlertCause | null
  silence_kind?: SilenceKind | null
  threshold_minutes?: number | null
  threshold_basis?: { has_usable_signal?: boolean | null } | null
}

export type SilenceReading =
  | 'person_quiet'
  | 'device_dark'
  | 'unknown'
  | null

/**
 * What this row's quiet actually is.
 *
 * An open alert names its own cause and that wins: it is the judgement the
 * system already acted on, and the badge must not contradict the reason printed
 * beside it. Without an alert the device heartbeat decides, which is how a
 * dark device gets noticed before it ever escalates.
 */
export function readSilence(row: SilenceRow): SilenceReading {
  if (row.alert_cause === 'dark_device') return 'device_dark'
  if (row.alert_cause === 'silence') return 'person_quiet'
  // concern and sos are about a person by construction, and say nothing about
  // whether the device is reporting, so they fall through to the evidence.
  return row.silence_kind ?? null
}

/**
 * Whether a silence alert can fire for this account at all.
 *
 * ADR-0037 returns no threshold until there is usable evidence, and a NULL
 * threshold means this person is not being judged for silence — a fact the
 * console had no way of showing, so an account could sit there looking
 * monitored while nothing could ever escalate.
 */
export function isSilenceJudgeable(row: SilenceRow): boolean {
  return typeof row.threshold_minutes === 'number' && row.threshold_minutes > 0
}

/** `5h 30m`, or a dash when there is no threshold to show. */
export function formatThreshold(minutes: number | null | undefined): string {
  if (typeof minutes !== 'number' || !Number.isFinite(minutes) || minutes <= 0) {
    return '—'
  }
  const hours = Math.floor(minutes / 60)
  const rest = Math.round(minutes % 60)
  if (hours === 0) return `${rest}m`
  if (rest === 0) return `${hours}h`
  return `${hours}h ${rest}m`
}
