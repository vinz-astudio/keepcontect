import { App as CapacitorApp } from '@capacitor/app'
import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'
import { useEffect } from 'react'
import { deepLinkToInternalAuthUrl } from '@/features/auth/authRedirect'

function openInsideApp(openedUrl: string): boolean {
  const target = deepLinkToInternalAuthUrl(openedUrl)
  if (!target) return false
  if (window.location.href === target) return true
  window.location.replace(target)
  return true
}

export function NativeAuthRedirectBridge() {
  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return

    let disposed = false
    let removeListener: (() => void) | null = null

    CapacitorApp.getLaunchUrl()
      .then((launch) => {
        if (!disposed && launch?.url && openInsideApp(launch.url)) {
          void Browser.close().catch(() => {})
        }
      })
      .catch(() => {})

    void CapacitorApp.addListener('appUrlOpen', ({ url }) => {
      if (openInsideApp(url)) void Browser.close().catch(() => {})
    }).then((handle) => {
      if (disposed) {
        void handle.remove()
      } else {
        removeListener = () => void handle.remove()
      }
    })

    return () => {
      disposed = true
      removeListener?.()
    }
  }, [])

  return null
}
