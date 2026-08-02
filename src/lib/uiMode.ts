import { useState, useEffect } from 'react'

export type UiMode = 'v2' | 'classic'

const STORAGE_KEY = 'kc_ui_mode'
const CHANGE_EVENT = 'kc_ui_mode_change'

export function getUiMode(): UiMode {
  if (typeof window === 'undefined') return 'v2'
  const saved = localStorage.getItem(STORAGE_KEY)
  if (saved === 'classic') return 'classic'
  return 'v2' // Default to 0.5.25 V2 Spatial UI
}

export function setUiMode(mode: UiMode): void {
  if (typeof window === 'undefined') return
  localStorage.setItem(STORAGE_KEY, mode)
  window.dispatchEvent(new CustomEvent(CHANGE_EVENT, { detail: mode }))
}

export function useUiMode(): [UiMode, (mode: UiMode) => void] {
  const [mode, setModeState] = useState<UiMode>(getUiMode)

  useEffect(() => {
    const handleStorage = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY && e.newValue) {
        setModeState(e.newValue === 'classic' ? 'classic' : 'v2')
      }
    }
    const handleCustom = (e: Event) => {
      const customEvent = e as CustomEvent<UiMode>
      if (customEvent.detail) {
        setModeState(customEvent.detail)
      }
    }

    window.addEventListener('storage', handleStorage)
    window.addEventListener(CHANGE_EVENT, handleCustom)
    return () => {
      window.removeEventListener('storage', handleStorage)
      window.removeEventListener(CHANGE_EVENT, handleCustom)
    }
  }, [])

  const setMode = (newMode: UiMode) => {
    setUiMode(newMode)
    setModeState(newMode)
  }

  return [mode, setMode]
}
