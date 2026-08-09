/**
 * ADR-0039 Special Attention — client-side rules.
 *
 * A private, default-off notification preference. The server owns eligibility,
 * privacy and the notice itself; nothing here grants any data visibility or
 * operational authority, and a client can only ever read its own subscriptions.
 *
 * The RPC wrappers and the UI toggle land with S3-C, which owns protection
 * health and therefore the surface where the notice and the `Limited` state are
 * shown. They also need `src/lib/database.types.ts` regenerated for the new
 * functions, which is outside this package's write set.
 */

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
