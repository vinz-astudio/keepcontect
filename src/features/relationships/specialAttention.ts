/**
 * ADR-0039 Special Attention — client-side rules.
 *
 * A private, default-off notification preference. The server owns eligibility,
 * privacy and the notice itself; nothing here grants any data visibility or
 * operational authority, and a client can only ever read its own subscriptions.
 */

import { supabase } from '@/lib/supabase'

export const RELATIONSHIP_NOT_ACTIVE = 'relationship not active'

export interface SpecialAttentionSubscription {
  subject_id: string
  created_at: string
}

/** Off unless the person has explicitly said otherwise. */
export function isSpecialAttentionOn(
  subscriptions: readonly SpecialAttentionSubscription[] | null | undefined,
  subject: string
): boolean {
  return (subscriptions ?? []).some((row) => row.subject_id === subject)
}

/**
 * Maps a failed subscribe to copy that states the rule. Any other failure is
 * passed through so real errors stay visible.
 */
export function specialAttentionErrorKey(error: unknown): 'special.needsActive' | null {
  const raw = error instanceof Error ? error.message : ''
  return raw.includes(RELATIONSHIP_NOT_ACTIVE) ? 'special.needsActive' : null
}

/** The caller's own subscriptions. Never anyone else's. */
export async function listMySpecialAttention(): Promise<SpecialAttentionSubscription[]> {
  const { data, error } = await supabase.rpc('my_special_attention')
  if (error) throw new Error(error.message)
  return (data ?? []) as SpecialAttentionSubscription[]
}

/**
 * Turns the preference on or off. Turning it on needs a currently active
 * relationship; turning it off never does, so withdrawal is always available.
 */
export async function setSpecialAttention(subject: string, enabled: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_special_attention', {
    _subject: subject,
    _enabled: enabled,
  })
  if (error) throw new Error(error.message)
}
