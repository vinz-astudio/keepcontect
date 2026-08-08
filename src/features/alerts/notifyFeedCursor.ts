// Deliberate duplicate of supabase/functions/notify-feed/index.ts (edge runtime cannot import across the src/ boundary at deploy time); keep in sync.

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/

/**
 * Resolve the `created_at >` bound notify-feed queries with.
 *
 * `notifications.created_at` is a timestamptz, stored to the microsecond, and a
 * JavaScript Date holds only milliseconds. Passing the cursor through a Date
 * therefore truncates it — and a bound one microsecond *below* a row's own
 * timestamp makes that row newer than itself, so it is returned again on every
 * poll. The client compares the returned `created_at` against its stored cursor
 * to decide whether to advance; seeing the identical string it does not, and
 * the row is re-delivered on every wake until `read_at` is set.
 *
 * The cursor is therefore handed to Postgres exactly as the client sent it.
 * Date.parse survives only as a validator and for the lookback clamp, which
 * keeps a stale or absent cursor from dumping ancient history as fresh.
 */
export function feedCursor(since: string | null | undefined, weekAgo: string): string {
  if (!since) return weekAgo
  const parsed = Date.parse(since)
  if (Number.isNaN(parsed) || parsed < Date.parse(weekAgo)) return weekAgo
  return ISO_TIMESTAMP.test(since) ? since : new Date(parsed).toISOString()
}
