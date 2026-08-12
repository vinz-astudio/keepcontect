import { describe, expect, it } from 'vitest'
import {
  isAndroidRequiredSetupReady,
  isIosRequiredSetupReady,
  resolveNativeNotificationReadiness,
} from './onboardingReadiness'

describe('native onboarding readiness', () => {
  it('requires both OS notification authorization and an FCM token', () => {
    expect(resolveNativeNotificationReadiness({ permissionGranted: true, tokenAvailable: true })).toBe('ready')
    expect(resolveNativeNotificationReadiness({ permissionGranted: false, tokenAvailable: true })).toBe('action')
    expect(resolveNativeNotificationReadiness({ permissionGranted: true, tokenAvailable: false })).toBe('unknown')
    expect(resolveNativeNotificationReadiness({ permissionGranted: false, tokenAvailable: false })).toBe('action')
  })

  it('keeps Android motion, battery exemption, and autostart outside the required gate', () => {
    expect(isAndroidRequiredSetupReady({
      notification: 'ready',
      usageGranted: true,
      guardEnabled: true,
    })).toBe(true)

    expect(isAndroidRequiredSetupReady({
      notification: 'ready',
      usageGranted: false,
      guardEnabled: true,
    })).toBe(false)
  })

  it('requires only verified notifications and the guard on iOS', () => {
    expect(isIosRequiredSetupReady({ notification: 'ready', guardEnabled: true })).toBe(true)
    expect(isIosRequiredSetupReady({ notification: 'unknown', guardEnabled: true })).toBe(false)
    expect(isIosRequiredSetupReady({ notification: 'ready', guardEnabled: false })).toBe(false)
  })
})
