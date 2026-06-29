import { beforeEach, describe, expect, it, vi } from 'vitest'

const store = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (key: string) => store.get(key) ?? null,
  setItem: (key: string, value: string) => store.set(key, value),
  clear: () => store.clear(),
})

vi.mock('@capacitor/core', () => ({
  Capacitor: { getPlatform: () => 'android' },
}))

vi.mock('@/lib/platform', () => ({
  isTauri: () => false,
}))

vi.mock('@/features/passive/native', () => ({
  configureNativePassivePing: vi.fn(),
}))

const { isSensorEnabled } = await import('@/features/signals/sensors')

describe('sensor preferences', () => {
  beforeEach(() => {
    store.clear()
  })

  it('defaults app activity tracking to off until the user grants accessibility', () => {
    expect(isSensorEnabled('app_activity')).toBe(false)
  })

  it('keeps established passive sensors enabled by default', () => {
    expect(isSensorEnabled('interaction')).toBe(true)
    expect(isSensorEnabled('phone_charger')).toBe(true)
  })
})
