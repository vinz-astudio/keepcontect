import { beforeEach, describe, expect, it, vi } from 'vitest'

const nativeHarness = vi.hoisted(() => ({
  platform: 'ios',
  activityEnabled: true,
  binding: {
    bind: vi.fn(),
    revoke: vi.fn(),
  },
  token: {
    get: vi.fn(),
  },
  plugin: {
    configure: vi.fn().mockResolvedValue(undefined),
    clear: vi.fn().mockResolvedValue(undefined),
    pingApp: vi.fn().mockResolvedValue(undefined),
    getGuardStatus: vi.fn(),
    getNotificationPermissionStatus: vi.fn(),
    isBatteryExempt: vi.fn(),
    isUsageStatsEnabled: vi.fn(),
    isActivityRecognitionEnabled: vi.fn(),
    getCollectionPermissionStatus: vi.fn(),
    openNotificationSettings: vi.fn().mockResolvedValue(undefined),
    enableHealthWake: vi.fn().mockResolvedValue({ granted: true }),
  },
}))

vi.mock('@capacitor/core', () => ({
  Capacitor: { getPlatform: () => nativeHarness.platform },
  registerPlugin: () => nativeHarness.plugin,
}))

vi.mock('@/features/signals/sensors', () => ({ isSensorEnabled: (key: string) => key !== 'app_activity' || nativeHarness.activityEnabled }))
vi.mock('@/lib/clientReport', () => ({ getClientId: () => 'native-test-client' }))
vi.mock('@/lib/config', () => ({ SUPABASE_URL: 'https://example.invalid' }))
vi.mock('@/lib/version', () => ({ APP_VERSION: '0.6.0-test' }))
vi.mock('@/lib/supabase', () => ({
  supabase: { auth: { getUser: vi.fn().mockResolvedValue({ data: { user: { id: 'user-1' } } }) } },
}))
vi.mock('./evidenceContract', () => ({
  bindPassiveCollector: nativeHarness.binding.bind,
  revokePassiveCollector: nativeHarness.binding.revoke,
}))
vi.mock('./api', () => ({ getHeartbeatToken: nativeHarness.token.get }))

const storage = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (key: string) => storage.get(key) ?? null,
  setItem: (key: string, value: string) => storage.set(key, value),
  removeItem: (key: string) => storage.delete(key),
  clear: () => storage.clear(),
})

const native = await import('./native')

describe('native passive setup truth', () => {
  beforeEach(() => {
    nativeHarness.platform = 'ios'
    nativeHarness.activityEnabled = true
    vi.clearAllMocks()
    nativeHarness.plugin.configure.mockResolvedValue(undefined)
    nativeHarness.plugin.pingApp.mockResolvedValue(undefined)
    nativeHarness.plugin.enableHealthWake.mockResolvedValue({ granted: true })
    nativeHarness.binding.bind.mockResolvedValue({
      bindingId: '00000000-0000-4000-8000-000000000001',
      credential: 'a'.repeat(64),
      credentialVersion: 1,
      surfaceType: nativeHarness.platform === 'android' ? 'android_native' : 'ios_native',
      collectorContract: nativeHarness.platform === 'android'
        ? 'android-passive-evidence-v1'
        : 'ios-passive-evidence-v1',
    })
    nativeHarness.binding.revoke.mockResolvedValue(true)
    nativeHarness.token.get.mockResolvedValue('session-token')
    storage.clear()
  })

  it('reads notification authorization from the native OS bridge', async () => {
    nativeHarness.plugin.getNotificationPermissionStatus.mockResolvedValue({ granted: true, canRequest: false })
    await expect(native.getNativeNotificationPermissionStatus()).resolves.toEqual({ granted: true, canRequest: false })

    nativeHarness.plugin.getNotificationPermissionStatus.mockResolvedValue({ granted: false, canRequest: true })
    await expect(native.getNativeNotificationPermissionStatus()).resolves.toEqual({ granted: false, canRequest: true })
  })

  it('treats a missing or broken permission bridge as not verified', async () => {
    nativeHarness.plugin.getNotificationPermissionStatus.mockRejectedValue(new Error('old shell'))
    await expect(native.getNativeNotificationPermissionStatus()).resolves.toEqual({ granted: false, canRequest: false })
  })

  it('opens the native notification settings repair surface', async () => {
    await native.openNativeNotificationSettings()
    expect(nativeHarness.plugin.openNotificationSettings).toHaveBeenCalledOnce()
  })

  it('does not surprise an iOS user with the HealthKit sheet during routine configuration', async () => {
    await native.configureNativePassivePing('session-token')

    expect(nativeHarness.binding.bind).toHaveBeenCalledWith(
      'native-test-client', 'ios_native', '0.6.0-test',
    )
    expect(nativeHarness.plugin.configure).toHaveBeenCalledOnce()
    expect(nativeHarness.plugin.configure).toHaveBeenCalledWith(expect.objectContaining({
      bindingId: '00000000-0000-4000-8000-000000000001',
      evidenceCredential: 'a'.repeat(64),
      evidenceCollectorContract: 'ios-passive-evidence-v1',
    }))
    expect(nativeHarness.plugin.pingApp).toHaveBeenCalledOnce()
    expect(nativeHarness.plugin.enableHealthWake).not.toHaveBeenCalled()
  })

  it('binds Android evidence and hands the one-time credential to the native secure store', async () => {
    nativeHarness.platform = 'android'
    await native.configureNativePassivePing('legacy-token')

    expect(nativeHarness.binding.bind).toHaveBeenCalledWith(
      'native-test-client', 'android_native', '0.6.0-test',
    )
    expect(nativeHarness.plugin.configure).toHaveBeenCalledWith(expect.objectContaining({
      token: 'legacy-token',
      bindingId: '00000000-0000-4000-8000-000000000001',
      evidenceCredential: 'a'.repeat(64),
      evidenceCollectorContract: 'android-passive-evidence-v1',
    }))
  })

  it('clears native collection and revokes the current binding on logout', async () => {
    nativeHarness.platform = 'android'
    await native.configureNativePassivePing('legacy-token')
    await native.configureNativePassivePing(null)

    expect(nativeHarness.binding.revoke).toHaveBeenCalledWith(
      '00000000-0000-4000-8000-000000000001',
    )
    expect(nativeHarness.plugin.clear).toHaveBeenCalledOnce()
  })

  it('rotates the binding when the native secure credential is missing', async () => {
    nativeHarness.platform = 'android'
    await native.configureNativePassivePing('legacy-token')
    nativeHarness.plugin.configure
      .mockResolvedValueOnce({ evidenceConfigured: false })
      .mockResolvedValueOnce({ evidenceConfigured: true })

    await native.configureNativePassivePing('legacy-token')

    expect(nativeHarness.binding.revoke).toHaveBeenCalledWith(
      '00000000-0000-4000-8000-000000000001',
    )
    expect(nativeHarness.binding.bind).toHaveBeenCalledTimes(2)
    expect(nativeHarness.plugin.configure).toHaveBeenCalledTimes(3)
  })

  it('retries iOS evidence binding after routine configuration makes the account eligible', async () => {
    nativeHarness.binding.bind.mockRejectedValueOnce(new Error('legacy account'))

    await native.configureNativePassivePing('session-token')
    await native.refreshNativePassivePing()

    expect(nativeHarness.token.get).toHaveBeenCalledOnce()
    expect(nativeHarness.binding.bind).toHaveBeenCalledTimes(2)
    expect(nativeHarness.plugin.configure).toHaveBeenLastCalledWith(expect.objectContaining({
      bindingId: '00000000-0000-4000-8000-000000000001',
      evidenceCredential: 'a'.repeat(64),
      evidenceCollectorContract: 'ios-passive-evidence-v1',
    }))
  })

  it('fails closed when an older native shell omits evidence readiness', async () => {
    nativeHarness.platform = 'android'
    nativeHarness.plugin.getGuardStatus.mockResolvedValue({
      enabled: true,
      connectedAt: 1,
      lastEventAt: 2,
      lastPingAt: 3,
      usageGranted: true,
      activityGranted: true,
    })

    await expect(native.getGuardStatus()).resolves.toMatchObject({
      enabled: true,
      evidenceConfigured: false,
    })
  })

  it('applies native settings with the authenticated token without fabricating an app event', async () => {
    nativeHarness.platform = 'android'
    await native.syncNativeSensorPreferences()
    expect(nativeHarness.token.get).toHaveBeenCalledOnce()
    expect(nativeHarness.plugin.configure).toHaveBeenCalledWith(expect.objectContaining({ token: 'session-token' }))
    expect(nativeHarness.plugin.pingApp).not.toHaveBeenCalled()
  })

  it('stops iOS collection without needing an online token lookup', async () => {
    nativeHarness.activityEnabled = false
    nativeHarness.token.get.mockRejectedValue(new Error('offline'))
    await native.syncNativeSensorPreferences()
    expect(nativeHarness.plugin.clear).toHaveBeenCalledOnce()
    expect(nativeHarness.token.get).not.toHaveBeenCalled()
  })

  it('clears a bound iOS collector before waiting for remote revocation', async () => {
    await native.configureNativePassivePing('session-token')
    nativeHarness.activityEnabled = false
    let finish!: (value: boolean) => void
    nativeHarness.binding.revoke.mockReturnValueOnce(new Promise((resolve) => { finish = resolve }))
    const stopping = native.syncNativeSensorPreferences()
    await Promise.resolve()
    await Promise.resolve()
    expect(nativeHarness.plugin.clear).toHaveBeenCalledOnce()
    expect(storage.has('kc.passiveEvidence.bindingId')).toBe(false)
    finish(true)
    await stopping
  })

  it('propagates native bridge failure for an explicit settings update', async () => {
    nativeHarness.plugin.configure.mockRejectedValueOnce(new Error('bridge failed'))
    await expect(native.syncNativeSensorPreferences()).rejects.toThrow('bridge failed')
  })

  it('distinguishes revoked Android permissions from a failed OS read', async () => {
    nativeHarness.platform = 'android'
    nativeHarness.plugin.isUsageStatsEnabled.mockResolvedValueOnce({ enabled: false })
    expect(await native.getNativePermissionState('usage')).toBe('denied')
    nativeHarness.plugin.isUsageStatsEnabled.mockRejectedValueOnce(new Error('missing bridge'))
    expect(await native.getNativePermissionState('usage')).toBe('unavailable')
    nativeHarness.plugin.isBatteryExempt.mockResolvedValue({ exempt: true })
    expect(await native.getNativePermissionState('battery')).toBe('granted')
  })

  it('reads iOS motion and background refresh without inferring them from guard binding', async () => {
    nativeHarness.plugin.getCollectionPermissionStatus.mockResolvedValue({ motion: 'denied', backgroundRefresh: 'granted' })
    expect(await native.getNativePermissionState('motion')).toBe('denied')
    expect(await native.getNativePermissionState('background-refresh')).toBe('granted')
    nativeHarness.plugin.getCollectionPermissionStatus.mockResolvedValue({ motion: 'granted', backgroundRefresh: 'restricted' })
    expect(await native.getNativePermissionState('background-refresh')).toBe('restricted')
    nativeHarness.plugin.getCollectionPermissionStatus.mockRejectedValue(new Error('old shell'))
    expect(await native.getNativePermissionState('motion')).toBe('unavailable')
  })
})
