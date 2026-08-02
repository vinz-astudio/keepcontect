/** Compatibility bridge for legacy embedded cards. */
export type UiMode = 'v2'

export function getUiMode(): UiMode {
  return 'v2'
}

export function setUiMode(_mode: UiMode): void {
  // The approved product has one immutable presentation.
}

export function useUiMode(): [UiMode, (mode: UiMode) => void] {
  return ['v2', setUiMode]
}
