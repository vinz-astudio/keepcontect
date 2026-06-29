import { Capacitor } from '@capacitor/core'
import { Browser } from '@capacitor/browser'
import { isTauri } from '@/lib/platform'

export interface UpdateUrls {
  apkUrl?: string
  exeUrl?: string
}

export interface LaunchUpdateDeps {
  isTauri: () => boolean
  isNativePlatform: () => boolean
  getTauriInternals: () => { invoke?: (cmd: string, args?: unknown) => Promise<unknown> } | null
  openCapacitorBrowser: (url: string) => Promise<unknown>
  openWindow: (url: string) => void
  reload: () => void
}

export const PRODUCTION_UPDATE_URLS: UpdateUrls = {
  apkUrl: 'https://keep-contact-mauve.vercel.app/keep-contact.apk',
  exeUrl: 'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe',
}

export async function launchUpdate(
  urls: UpdateUrls,
  deps?: LaunchUpdateDeps,
): Promise<void> {
  const d = deps ?? defaultDeps()

  if (d.isTauri() && urls.exeUrl) {
    const internals = d.getTauriInternals()
    if (internals?.invoke) {
      try {
        await internals.invoke('download_and_install', { url: urls.exeUrl })
        return
      } catch (err) {
        console.error('Tauri update failed:', err)
        try {
          await internals.invoke('open_in_browser', { url: urls.exeUrl })
          return
        } catch {
          d.openWindow(urls.exeUrl)
          return
        }
      }
    }
    d.openWindow(urls.exeUrl)
    return
  }

  if (d.isNativePlatform() && urls.apkUrl) {
    try {
      await d.openCapacitorBrowser(urls.apkUrl)
    } catch (err) {
      console.error('Failed to open APK URL with Capacitor Browser:', err)
      d.openWindow(urls.apkUrl)
    }
    return
  }

  d.reload()
}

function defaultDeps(): LaunchUpdateDeps {
  return {
    isTauri,
    isNativePlatform: () => Capacitor.isNativePlatform(),
    getTauriInternals: () => {
      const internals = (window as any).__TAURI_INTERNALS__
      return internals && typeof internals.invoke === 'function' ? internals : null
    },
    openCapacitorBrowser: (url: string) => Browser.open({ url }),
    openWindow: (url: string) => {
      window.open(url, '_blank')
    },
    reload: () => window.location.reload(),
  }
}
