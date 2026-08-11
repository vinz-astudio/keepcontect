import { Capacitor } from '@capacitor/core'
import { Browser } from '@capacitor/browser'
import { openInExternalBrowser } from '@/features/passive/native'
import { isTauri } from '@/lib/platform'

export interface UpdateUrls {
  apkUrl?: string
  exeUrl?: string
}

export interface LaunchUpdateDeps {
  isTauri: () => boolean
  isNativePlatform: () => boolean
  getTauriInternals: () => { invoke?: (cmd: string, args?: unknown) => Promise<unknown> } | null
  openExternalBrowser: (url: string) => Promise<unknown>
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
    // The real browser, not a Custom Tab. A Custom Tab is a browser living
    // inside this app, and an APK downloaded there belongs to nobody the system
    // will let install it: the download finishes and offers no way to open it,
    // so the update dies silently on the last step. Handed to Chrome, the file
    // is Chrome's — it offers to open it, the package installer takes over, and
    // Play Protect scans it on the way in.
    try {
      await d.openExternalBrowser(urls.apkUrl)
      return
    } catch (err) {
      console.error('Failed to open APK URL in the external browser:', err)
    }
    // Older installs have no such bridge, and a device with no browser at all
    // is possible. Both are better served by the old path than by a dead button.
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
    openExternalBrowser: (url: string) => openInExternalBrowser(url),
    openCapacitorBrowser: (url: string) => Browser.open({ url }),
    openWindow: (url: string) => {
      window.open(url, '_blank')
    },
    reload: () => window.location.reload(),
  }
}
