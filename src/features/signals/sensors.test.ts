import { beforeEach, describe, expect, it, vi } from 'vitest'

const store = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (key: string) => store.get(key) ?? null,
  setItem: (key: string, value: string) => store.set(key, value),
  clear: () => store.clear(),
})

const harness = vi.hoisted(() => ({ platform: 'android', tauri: false, sync: vi.fn() }))
vi.mock('@capacitor/core', () => ({ Capacitor: { getPlatform: () => harness.platform } }))

vi.mock('@/lib/platform', () => ({
  isTauri: () => harness.tauri,
}))

vi.mock('@/features/passive/native', () => ({
  syncNativeSensorPreferences: harness.sync,
}))

const { isSensorEnabled, getAvailableSensors, setSensorEnabled } = await import('@/features/signals/sensors')

describe('sensor preferences', () => {
  beforeEach(() => {
    store.clear()
    harness.platform = 'android'
    harness.tauri = false
    harness.sync.mockReset().mockResolvedValue(undefined)
  })

  it('defaults app activity tracking to enabled by default', () => {
    expect(isSensorEnabled('app_activity')).toBe(true)
  })

  it('keeps established passive sensors enabled by default', () => {
    expect(isSensorEnabled('interaction')).toBe(true)
    expect(isSensorEnabled('phone_charger')).toBe(true)
  })

  it.each([
    ['android', false, ['interaction', 'app_activity', 'motion', 'phone_charger']],
    ['ios', false, ['interaction', 'app_activity']],
    ['web', false, ['interaction']],
    ['web', true, ['interaction', 'system_idle']],
  ])('only offers controls implemented by %s (desktop=%s)', (platform, tauri, keys) => {
    harness.platform = platform
    harness.tauri = tauri
    expect(getAvailableSensors().map((sensor) => sensor.key)).toEqual(keys)
  })

  it('synchronizes native preferences without a legacy localStorage token', async () => {
    await setSensorEnabled('app_activity', false)
    expect(harness.sync).toHaveBeenCalledOnce()
    expect(isSensorEnabled('app_activity')).toBe(false)
  })

  it('reports a failed native update and restores the saved preference', async () => {
    harness.sync.mockRejectedValue(new Error('bridge unavailable'))
    await expect(setSensorEnabled('motion', false)).rejects.toThrow('bridge unavailable')
    expect(isSensorEnabled('motion')).toBe(true)
  })

  it('does not reconfigure native collectors for the separate page interaction switch', async () => {
    await setSensorEnabled('interaction', false)
    expect(harness.sync).not.toHaveBeenCalled()
  })
})
