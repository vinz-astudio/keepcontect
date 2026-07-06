export function shouldShowSosHoldHint({
  started,
  fired,
}: {
  started: boolean
  fired: boolean
}): boolean {
  return started && !fired
}
