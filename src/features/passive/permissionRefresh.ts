import { App } from '@capacitor/app'
import { Capacitor } from '@capacitor/core'

/** Read again when returning from OS settings; late listener setup is also cleaned up. */
export function watchPermissionRefresh(refresh: () => void): () => void {
  let disposed = false
  let removeNative: (() => void) | undefined
  const onVisible = () => { if (document.visibilityState === 'visible') refresh() }
  window.addEventListener('focus', onVisible)
  window.addEventListener('storage', onVisible)
  window.addEventListener('kc:sensor-preference-changed', onVisible)
  document.addEventListener('visibilitychange', onVisible)
  if (Capacitor.isNativePlatform()) {
    void App.addListener('appStateChange', ({ isActive }) => {
      if (isActive && !disposed) refresh()
    }).then((handle) => {
      if (disposed) void handle.remove()
      else removeNative = () => { void handle.remove() }
    }).catch(() => { /* Web focus/visibility remain the old-shell fallback. */ })
  }
  return () => {
    disposed = true
    removeNative?.()
    window.removeEventListener('focus', onVisible)
    window.removeEventListener('storage', onVisible)
    window.removeEventListener('kc:sensor-preference-changed', onVisible)
    document.removeEventListener('visibilitychange', onVisible)
  }
}
