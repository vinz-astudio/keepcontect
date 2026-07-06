export function canShowViewportDiagnostics({
  isDev,
  unlocked,
}: {
  isDev: boolean
  unlocked: boolean
}): boolean {
  return isDev || unlocked
}
