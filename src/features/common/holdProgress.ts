/** Percent of a press-and-hold that has elapsed, clamped to 0–100. */
export function holdProgress(startedAt: number | null, now: number, durationMs: number): number {
  if (startedAt === null || !(durationMs > 0)) return 0
  return Math.min(100, Math.max(0, ((now - startedAt) / durationMs) * 100))
}

/**
 * "一切安好" must be held, not tapped (human decision 2026-11-02, "3~5秒的长按"):
 * a deliberate hold suits a safety confirmation, and the ring answers the press
 * at once instead of leaving the user waiting on the network. Three seconds is
 * the short end of that range, so someone who is unwell can still finish it.
 */
export const SAFE_HOLD_MS = 3000
