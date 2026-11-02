import { Capacitor } from '@capacitor/core'
import { Browser } from '@capacitor/browser'
import { openInExternalBrowser } from '@/features/passive/native'
import { isTauri } from '@/lib/platform'
import { toast } from '@/lib/toast'

export interface UpdateUrls {
  apkUrl?: string
  exeUrl?: string
  iosUrl?: string
}

export interface LaunchUpdateDeps {
  isTauri: () => boolean
  isNativePlatform: () => boolean
  getNativePlatform?: () => string
  getTauriInternals: () => { invoke?: (cmd: string, args?: unknown) => Promise<unknown> } | null
  openExternalBrowser: (url: string) => Promise<unknown>
  openCapacitorBrowser: (url: string) => Promise<unknown>
  openWindow: (url: string) => void
  reload: () => void
  /** Android: the browser downloads the APK but does not open the installer by itself. */
  showApkInstallHint?: () => void
}

export const PRODUCTION_UPDATE_URLS: UpdateUrls = {
  apkUrl: 'https://keep-contact-mauve.vercel.app/keep-contact.apk',
  exeUrl: 'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe',
  iosUrl: 'https://testflight.apple.com',
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

  if (d.isNativePlatform()) {
    const nativePlat = d.getNativePlatform ? d.getNativePlatform() : Capacitor.getPlatform()
    if (nativePlat === 'ios') {
      const targetIosUrl = urls.iosUrl || PRODUCTION_UPDATE_URLS.iosUrl
      if (targetIosUrl) {
        try {
          await d.openExternalBrowser(targetIosUrl)
          return
        } catch {
          d.openWindow(targetIosUrl)
          return
        }
      }
      return
    }



    if (urls.apkUrl) {
      // The real browser, not a Custom Tab. A Custom Tab is a browser living
      // inside this app, and an APK downloaded there belongs to nobody the system
      // will let install it: the download finishes and offers no way to open it,
      // so the update dies silently on the last step. Handed to Chrome, the file
      // is Chrome's — it offers to open it, the package installer takes over, and
      // Play Protect scans it on the way in.
      d.showApkInstallHint?.()
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
  }

  d.reload()
}

function defaultDeps(): LaunchUpdateDeps {
  return {
    isTauri,
    isNativePlatform: () => Capacitor.isNativePlatform(),
    getNativePlatform: () => Capacitor.getPlatform(),
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
    showApkInstallHint: () => {
      let en = false
      try { en = localStorage.getItem('kc.lang') === 'en' } catch { /* storage blocked */ }
      toast(en
        ? 'When the download finishes, tap it in the notification bar (or Downloads) to install.'
        : '下载完成后，点通知栏（或"下载"）里的安装包即可安装。', 'info')
    },
  }
}
