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
const notifyFeed = read('ios-passive-ping/ios/Sources/KcPassivePingPlugin/NotifyFeed.swift')
const fastfile = read('ios/App/fastlane/Fastfile')
const iosWorkflow = read('.github/workflows/ios-testflight.yml')
const urgencyPath = 'ios-passive-ping/ios/Sources/KcPassivePingPlugin/NotificationUrgency.swift'

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
  // Revised 2026-11-02 (human decision): the significant-change relaunch wake is
  // removed. It produced 0-3 unplugged wakes a week in production, and "Always"
  // location for an app that says it never reads location is what App Review
  // 5.1.5 / 2.5.4 rejects. History: removed 2026-08-10, restored 2026-08-14,
  // removed again here. The only location left is SOS "while using" from the
  // WebView. A one-time stop call stays, because the registration survives app
  // updates and would keep relaunching the new version.
  test('ADR0039-IOS-01 no Always location and no significant-change wake', () => {
    expect(infoPlist).not.toMatch(/<string>location<\/string>/)
    expect(infoPlist).not.toMatch(/NSLocationAlwaysAndWhenInUseUsageDescription/)
    // SOS still asks for location while the app is in use.
    expect(infoPlist).toMatch(/NSLocationWhenInUseUsageDescription/)

    const iosSources = fs.readdirSync(path.join(root, 'ios-passive-ping/ios/Sources/KcPassivePingPlugin'))
      .filter((name) => name.endsWith('.swift'))
      .map((name) => read(`ios-passive-ping/ios/Sources/KcPassivePingPlugin/${name}`))
      .join('\n') + '\n' + appDelegate
    expect(iosSources).not.toMatch(/requestAlwaysAuthorization/)
    expect(iosSources).not.toMatch(/startMonitoringSignificantLocationChanges/)
    expect(iosSources).not.toMatch(/startUpdatingLocation|allowsBackgroundLocationUpdates/)
    expect(iosSources).not.toMatch(/CLLocationManagerDelegate/)
    // The leftover registration from older builds is cleared on every start.
    expect(passiveGuard).toMatch(/stopMonitoringSignificantLocationChanges\(\)/)
  })

  // 2026-11-02: Apple ITMS-90068 warned on build 0.7.9 (46) that apps must
  // target iOS 15.0 or later from April 2027. iOS 15 runs on every iPhone that
  // ran iOS 14, so only people who never updated iOS lose new versions. The app,
  // its pods and the native plugin must agree, or one of them drags it back.
  test('IOS-TARGET-01 iOS deployment target is at least 15.0 everywhere', () => {
    const atLeast15 = (v) => Number(v.split('.')[0]) >= 15
    const pbx = [...read('ios/App/App.xcodeproj/project.pbxproj')
      .matchAll(/IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);/g)].map((m) => m[1])
    expect(pbx.length).toBeGreaterThan(0)
    expect(pbx.every(atLeast15)).toBe(true)
    const podfile = read('ios/App/Podfile').match(/platform :ios, '([\d.]+)'/)
    expect(podfile && atLeast15(podfile[1])).toBe(true)
    const podspec = read('ios-passive-ping/KcPassivePing.podspec').match(/deployment_target = '([\d.]+)'/)
    expect(podspec && atLeast15(podspec[1])).toBe(true)
  })

  // 2026-11-02: the safety ask must reach the subject through Focus. Time
  // Sensitive is Apple's self-serve level for notifications that need prompt
  // action (Critical Alerts would need Apple's approval and is not used).
  test('ADR0039-IOS-06 safety notifications are Time Sensitive on iOS 15+', () => {
    expect(iosEntitlements).toMatch(/<key>com\.apple\.developer\.usernotifications\.time-sensitive<\/key>\s*<true\/>/)
    // Not enableable through the App Store Connect API; the Fastfile must say
    // so and point at the one-time portal step instead of pretending.
    expect(fastfile).not.toMatch(/USERNOTIFICATIONS_TIMESENSITIVE/)
    expect(fastfile).toMatch(/Time Sensitive Notifications[\s\S]{0,400}Apple Developer portal/)
    const urgency = read(urgencyPath)
    for (const kind of ['self', 'concern', 'sos', 'terminal']) expect(urgency).toContain(`"${kind}"`)
    expect(urgency).not.toMatch(/"group"|"community"/)
    expect(notifyFeed).toMatch(/NotificationUrgency\.isTimeSensitive\(kind:/)
    expect(notifyFeed).toMatch(/#available\(iOS 15\.0, \*\)/)
    expect(notifyFeed).toMatch(/interruptionLevel = \.timeSensitive/)
    // The rule is compiled and executed on the macOS runner, not only grepped.
    expect(iosWorkflow).toMatch(/NotificationUrgency\.swift/)
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
