import { Capacitor } from '@capacitor/core'
import { isTauri } from '@/lib/platform'
import { desktopHasRealUpdate } from '@/features/update/desktopOffer'

// Only tell a surface about an update it can actually install (human decision
// 2026-11-02). Comparing the bare version number told TestFlight 0.7.9 and the
// 0.7.9 desktop installer to "update" after Android alone shipped 0.7.10; the
// desktop app then reinstalled 0.7.9 and asked again (see desktopOffer.ts).
export type UpdateSurface = 'web' | 'android-native' | 'ios-native' | 'tauri'

export interface OfferedUpdate {
  version: string
  apkUrl?: string
  exeUrl?: string
  iosUrl?: string
}

/** The version the APK behind this URL installs, or null for the unversioned alias. */
export function offeredApkVersion(apkUrl: string | undefined | null): string | null {
  if (!apkUrl) return null
  return /keep-contact-v(\d+\.\d+\.\d+)\.apk/i.exec(apkUrl)?.[1] ?? null
}

export function hasRealUpdate(
  surface: UpdateSurface,
  latest: OfferedUpdate,
  currentVersion: string,
  isNewer: (candidate: string, current: string) => boolean,
): boolean {
  switch (surface) {
    case 'tauri':
      return desktopHasRealUpdate(currentVersion, latest.exeUrl, isNewer)
    case 'android-native': {
      const offered = offeredApkVersion(latest.apkUrl)
      return offered !== null && isNewer(offered, currentVersion)
    }
    case 'ios-native':
      // TestFlight and the App Store announce new builds themselves, and the
      // row carries no versioned iOS artifact to check against.
      return false
    case 'web':
      // The newer bundle is already deployed; a reload installs it.
      return isNewer(latest.version, currentVersion)
  }
}

export function currentUpdateSurface(): UpdateSurface {
  if (isTauri()) return 'tauri'
  const platform = Capacitor.getPlatform()
  if (platform === 'android') return 'android-native'
  if (platform === 'ios') return 'ios-native'
  return 'web'
}
