export const PRIMARY_TABS = ['watch', 'routine', 'circles', 'me'] as const
export type PrimaryTab = (typeof PRIMARY_TABS)[number]

export const SOS_HOLD_MS = 1400

export function isPrimaryTab(value: string): value is PrimaryTab {
  return PRIMARY_TABS.includes(value as PrimaryTab)
}

export function getSosHoldProgress(
  startedAt: number | null,
  now: number,
  holdMs = SOS_HOLD_MS,
): number {
  if (startedAt === null || holdMs <= 0) return 0
  const elapsed = Math.max(0, now - startedAt)
  return Math.min(100, Math.round((elapsed / holdMs) * 100))
}
