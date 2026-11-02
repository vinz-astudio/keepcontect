import { describe, expect, it } from 'vitest'
import { hasRealUpdate, offeredApkVersion } from '@/features/update/platformOffer'
import { isNewer } from '@/features/update/versionSelection'

// A surface is only told about an update it can actually install. Android
// released 0.7.10 while TestFlight and the desktop installer were still 0.7.9;
// comparing the bare version number told those users to update to nothing (the
// desktop one then reinstalled 0.7.9 and asked again).
const latest = {
  version: '0.7.10',
  apkUrl: 'https://keep-contact-mauve.vercel.app/keep-contact-v0.7.10.apk',
  exeUrl: 'https://github.com/vinz-astudio/keepcontect/releases/download/v0.7.9/KeepContact-0.7.9-Setup.exe',
  iosUrl: 'https://testflight.apple.com',
}

describe('update offers per surface', () => {
  it('reads the version out of a versioned APK url, and nothing out of the unversioned alias', () => {
    expect(offeredApkVersion(latest.apkUrl)).toBe('0.7.10')
    expect(offeredApkVersion('https://keep-contact-mauve.vercel.app/keep-contact.apk')).toBeNull()
    expect(offeredApkVersion(undefined)).toBeNull()
  })

  it('offers Android the APK it can install', () => {
    expect(hasRealUpdate('android-native', latest, '0.7.9', isNewer)).toBe(true)
    expect(hasRealUpdate('android-native', latest, '0.7.10', isNewer)).toBe(false)
    expect(hasRealUpdate('android-native', { ...latest, apkUrl: undefined }, '0.7.9', isNewer)).toBe(false)
  })

  it('does not offer the desktop app a version its installer does not carry', () => {
    expect(hasRealUpdate('tauri', latest, '0.7.9', isNewer)).toBe(false)
    expect(hasRealUpdate('tauri', { ...latest, exeUrl: latest.exeUrl.replaceAll('0.7.9', '0.7.10') }, '0.7.9', isNewer)).toBe(true)
  })

  it('never shows an in-app prompt on iOS native: TestFlight and the App Store announce their own builds', () => {
    expect(hasRealUpdate('ios-native', latest, '0.7.9', isNewer)).toBe(false)
  })

  it('offers the web/PWA a reload whenever the number is newer, because the new bundle is already deployed', () => {
    expect(hasRealUpdate('web', latest, '0.7.9', isNewer)).toBe(true)
    expect(hasRealUpdate('web', latest, '0.7.10', isNewer)).toBe(false)
  })
})
