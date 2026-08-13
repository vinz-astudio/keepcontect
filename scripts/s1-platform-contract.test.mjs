import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, test } from 'vitest'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')

const androidManifest = read('android/app/src/main/AndroidManifest.xml')
const notifyWorker = read('android/app/src/main/java/com/keepcontact/app/NotifyWorker.java')
const passivePing = read('android/app/src/main/java/com/keepcontact/app/PassivePing.java')
const packageJson = read('package.json')
const releaseAndroid = read('scripts/release-android.mjs')
const onboardingPresentation = read('src/features/onboarding/onboardingPresentation.ts')

const infoPlist = read('ios/App/App/Info.plist')
const iosEntitlements = read('ios/App/App/App.entitlements')
const appDelegate = read('ios/App/App/AppDelegate.swift')
const passiveGuard = read('ios-passive-ping/ios/Sources/KcPassivePingPlugin/PassiveGuard.swift')
const healthWake = read('ios-passive-ping/ios/Sources/KcPassivePingPlugin/HealthWake.swift')

const tauriLib = read('src-tauri/src/lib.rs')
const tauriCapabilities = read('src-tauri/capabilities/default.json')
const tauriConfig = read('src-tauri/tauri.conf.json')

describe('S1 Android AAB repository contracts', () => {
  test('ADR0039-AAB-01 store manifest has no AccessibilityService', () => {
    expect(androidManifest).not.toMatch(/BIND_ACCESSIBILITY_SERVICE|AppActivityService/)
  })

  test('ADR0039-AAB-02 release tooling builds a distinct Play App Bundle', () => {
    expect(packageJson).toMatch(/"build:aab"\s*:\s*"[^"]*bundleRelease/)
    expect(releaseAndroid).toMatch(/assembleRelease bundleRelease/)
    expect(releaseAndroid).toMatch(/outputs[\\/]bundle[\\/]release[\\/]app-release\.aab/)
  })

  test('ADR0039-AAB-03 review-gated capabilities are optional detected paths', () => {
    expect(notifyWorker).toMatch(/canUseFullScreenIntent\(context\)/)
    expect(notifyWorker).toMatch(/if \(canUseFullScreenIntent\(context\)\)/)
    expect(passivePing).toMatch(/GUARD_PERSISTENT/)
    expect(passivePing).toMatch(/GUARD_PERSISTENT\.equals\(guardMode\(context\)\)/)
  })

  test('ADR0039-AAB-04 unavailable capability cannot become Ready', () => {
    expect(onboardingPresentation).toMatch(/if \(unavailable \|\| !requiredReady\) return 'limited'/)
  })
})

describe('S1 iOS Native repository contracts', () => {
  test('ADR0039-IOS-01 background location is not a relaunch-only hack', () => {
    expect(infoPlist).not.toMatch(/<string>location<\/string>[\s\S]*restart its guardian/i)
    expect(passiveGuard).not.toMatch(/CoreLocation|CLLocationManager|requestAlwaysAuthorization|startMonitoringSignificantLocationChanges/)
  })

  test('ADR0039-IOS-02 native project carries APNs and HealthKit capabilities', () => {
    expect(appDelegate).toMatch(/class AppDelegate/)
    expect(iosEntitlements).toMatch(/<key>aps-environment<\/key>[\s\S]*<string>production<\/string>/)
    expect(iosEntitlements).toMatch(/com\.apple\.developer\.healthkit/)
  })

  test('ADR0039-IOS-03 silent push wording states that coverage is not guaranteed', () => {
    expect(`${infoPlist}\n${appDelegate}`).toMatch(/best[- ]effort|not guaranteed|may not wake/i)
  })

  test('ADR0039-IOS-04 motion and HealthKit never resolve an alert', () => {
    expect(`${passiveGuard}\n${healthWake}`).not.toMatch(/resolve_alert|resolve_my_alert|confirmed_safe/)
  })

  test('ADR0039-IOS-05 Family Controls capability is absent and therefore not proven', () => {
    expect(iosEntitlements).not.toMatch(/family-controls|deviceactivity|managedsettings/i)
  })
})

describe('S1 Tauri repository contracts', () => {
  test('ADR0039-TAURI-01 unavailable idle probe is explicit non-operational state', () => {
    expect(tauriLib).toMatch(/idle_probe_available[\s\S]*"unavailable"/)
    expect(tauriLib).toMatch(/idle_probe_available[\s\S]*"operational"/)
  })

  test('ADR0039-TAURI-02 desktop autostart is configured and permissioned', () => {
    expect(tauriLib).toMatch(/tauri_plugin_autostart::init/)
    expect(tauriCapabilities).toMatch(/autostart:default/)
  })

  test('ADR0039-TAURI-03 signed updater and desktop bundle targets are configured', () => {
    expect(tauriConfig).toMatch(/"updater"[\s\S]*"pubkey"/)
    expect(tauriConfig).toMatch(/"targets"[\s\S]*"nsis"[\s\S]*"msi"/)
  })
})
