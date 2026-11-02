import { beforeEach, describe, expect, it, vi } from 'vitest'

// D2 (human decision 2026-11-02): when iOS notifications are allowed but Time
// Sensitive is off for KC, the safety ask will not get through Focus. The
// notification row says so instead of showing a plain "allowed".
const harness = vi.hoisted(() => ({
  platform: 'ios', state: 'granted', timeSensitive: 'disabled',
  openSettings: vi.fn(), request: vi.fn(), status: { granted: true, canRequest: false },
}))
vi.mock('@capacitor/core', () => ({ Capacitor: { getPlatform: () => harness.platform, isNativePlatform: () => true } }))
vi.mock('@/lib/platform', () => ({ isTauri: () => false }))
vi.mock('@/features/push/pushApi', () => ({ enablePush: vi.fn(), pushSupported: () => true }))
vi.mock('./native', () => ({
  getNativePermissionState: async () => harness.state,
  getNativeTimeSensitiveSetting: async () => harness.timeSensitive,
  getNativeNotificationPermissionStatus: async () => harness.status,
  requestNativeNotificationPermission: harness.request,
  openNativeNotificationSettings: harness.openSettings,
  openNativeAppSettings: vi.fn(), openUsageStatsSettings: vi.fn(),
  requestActivityRecognitionPermission: vi.fn(), requestBatteryExemption: vi.fn(),
}))

import { getGuardianPermissions } from './guardianPermissions'

const notifications = () => getGuardianPermissions().find((permission) => permission.id === 'notifications')!

describe('iOS Time Sensitive in the permission center', () => {
  beforeEach(() => {
    harness.platform = 'ios'; harness.state = 'granted'; harness.timeSensitive = 'disabled'
    harness.openSettings.mockReset(); harness.request.mockReset()
  })

  it('shows notifications as limited, with the reason, when Time Sensitive is off', async () => {
    expect(await notifications().check()).toBe('limited')
    expect(notifications().limitedZh).toContain('专注模式')
    expect(notifications().limitedEn).toMatch(/Focus/)
  })

  it.each(['enabled', 'unsupported', 'unknown'])('stays allowed when Time Sensitive is %s', async (setting) => {
    harness.timeSensitive = setting
    expect(await notifications().check()).toBe('granted')
  })

  it('leaves denied notifications reported as denied, not limited', async () => {
    harness.state = 'denied'
    expect(await notifications().check()).toBe('denied')
  })

  it('does not apply on Android', async () => {
    harness.platform = 'android'
    expect(await notifications().check()).toBe('granted')
  })

  it('opens the notification settings to fix it', async () => {
    await notifications().fix()
    expect(harness.openSettings).toHaveBeenCalledTimes(1)
  })
})
