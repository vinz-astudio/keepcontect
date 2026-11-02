// Geometry for the hold-to-confirm ring: a stroke that starts at 12 o'clock
// and runs clockwise back to 12 as the hold completes (the 2026-08 prototype's
// SOS ring, which the human asked to bring back on 2026-11-02).

export const HOLD_RING_SIZE = 140
export const HOLD_RING_STROKE = 6
export const HOLD_RING_RADIUS = (HOLD_RING_SIZE - HOLD_RING_STROKE) / 2
export const HOLD_RING_CIRCUMFERENCE = 2 * Math.PI * HOLD_RING_RADIUS

/** Stroke offset for a hold progress of 0–100: full circle hidden at 0, none hidden at 100. */
export function holdRingDashOffset(progress: number, circumference = HOLD_RING_CIRCUMFERENCE): number {
  const p = Number.isFinite(progress) ? Math.min(100, Math.max(0, progress)) : 0
  return circumference * (1 - p / 100)
}
