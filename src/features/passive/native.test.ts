import { beforeEach, describe, expect, it, vi } from 'vitest'

const nativeHarness = vi.hoisted(() => ({
  platform: 'ios',
  plugin: {
    configure: vi.fn().mockResolvedValue(undefined),
    clear: vi.fn().mockResolvedValue(undefined),
    pingApp: vi.fn().mockResolvedValue(undefined),
    getNotificationPermissionStatus: vi.fn(),
    enableHealthWake: vi.fn().mockResolvedValue({ granted: true }),
  },
}))

vi.mock('@capacitor/core', () => ({
  Capacitor: { getPlatform: () => nativeHarness.platform },
  registerPlugin: () => nativeHarness.plugin,
}))

vi.mock('@/features/signals/sensors', () => ({ isSensorEnabled: () => true }))
vi.mock('@/lib/clientReport', () => ({ getClientId: () => 'native-test-client' }))
vi.mock('@/lib/config', () => ({ SUPABASE_URL: 'https://example.invalid' }))
vi.mock('@/lib/version', () => ({ APP_VERSION: '0.6.0-test' }))

const native = await import('./native')

describe('native passive setup truth', () => {
  beforeEach(() => {
    nativeHarness.platform = 'ios'
    vi.clearAllMocks()
    nativeHarness.plugin.configure.mockResolvedValue(undefined)
    nativeHarness.plugin.pingApp.mockResolvedValue(undefined)
    nativeHarness.plugin.enableHealthWake.mockResolvedValue({ granted: true })
  })

  it('reads notification authorization from the native OS bridge', async () => {
    nativeHarness.plugin.getNotificationPermissionStatus.mockResolvedValue({ granted: true })
    await expect(native.getNativeNotificationPermissionStatus()).resolves.toBe(true)

    nativeHarness.plugin.getNotificationPermissionStatus.mockResolvedValue({ granted: false })
    await expect(native.getNativeNotificationPermissionStatus()).resolves.toBe(false)
  })

  it('treats a missing or broken permission bridge as not verified', async () => {
    nativeHarness.plugin.getNotificationPermissionStatus.mockRejectedValue(new Error('old shell'))
    await expect(native.getNativeNotificationPermissionStatus()).resolves.toBe(false)
  })

  it('does not surprise an iOS user with the HealthKit sheet during routine configuration', async () => {
    await native.configureNativePassivePing('session-token')

    expect(nativeHarness.plugin.configure).toHaveBeenCalledOnce()
    expect(nativeHarness.plugin.pingApp).toHaveBeenCalledOnce()
    expect(nativeHarness.plugin.enableHealthWake).not.toHaveBeenCalled()
  })
})
