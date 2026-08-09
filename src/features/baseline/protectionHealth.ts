import { supabase } from '@/lib/supabase'

/**
 * ADR-0039 protection health.
 *
 * The server is authoritative; this module only fetches and presents. The one
 * rule the presentation must never break is that `unknown` is not `ready`.
 * Rendering "we have no idea whether anyone is watching" as if it were fine is
 * the same failure the whole package exists to prevent — quiet is exactly what
 * this app looks like when everything is working.
 */

export type ProtectionState = 'ready' | 'limited' | 'unknown'

export interface ProtectionHealth {
  state: ProtectionState
  since: string | null
  cause: string | null
  prompted_at: string | null
  acknowledged_at: string | null
  recovery_required: string | null
  last_valid_coverage_at: string | null
}

export async function fetchProtectionHealth(): Promise<ProtectionHealth | null> {
  const { data, error } = await supabase.rpc('my_protection_health')
  if (error) throw new Error(error.message)
  const row = Array.isArray(data) ? data[0] : data
  return (row as ProtectionHealth | undefined) ?? null
}

/** Stops the re-prompting. It does not restore protection and never will. */
export async function acknowledgeProtectionHealth(): Promise<void> {
  const { error } = await supabase.rpc('acknowledge_protection_health')
  if (error) throw new Error(error.message)
}

/**
 * Missing data is `unknown`, never `ready`. A failed fetch tells us nothing
 * about whether somebody is watching, so it must not be allowed to look
 * reassuring.
 */
export function protectionState(health: ProtectionHealth | null | undefined): ProtectionState {
  const state = health?.state
  return state === 'ready' || state === 'limited' ? state : 'unknown'
}

/** Only a proven-healthy account is quiet. Everything else has to show itself. */
export function shouldSurfaceProtection(health: ProtectionHealth | null | undefined): boolean {
  return protectionState(health) !== 'ready'
}

/**
 * The one-time prompt is separate from the persistent banner: dismissing it
 * silences the prompt and leaves the state exactly where it was.
 */
export function shouldPromptOnce(health: ProtectionHealth | null | undefined): boolean {
  return protectionState(health) === 'limited' && !health?.acknowledged_at
}

export type ProtectionCopyKeys = {
  label: 'health.ready' | 'health.limited' | 'health.unknown'
  detail: 'health.ready.detail' | 'health.limited.detail' | 'health.unknown.detail'
}

export function protectionCopyKeys(state: ProtectionState): ProtectionCopyKeys {
  if (state === 'ready') return { label: 'health.ready', detail: 'health.ready.detail' }
  if (state === 'limited') return { label: 'health.limited', detail: 'health.limited.detail' }
  return { label: 'health.unknown', detail: 'health.unknown.detail' }
}
