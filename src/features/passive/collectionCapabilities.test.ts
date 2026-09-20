import { describe, expect, it } from 'vitest'

import {
  resolveCollectionCapabilities,
  type CollectionCapabilityDeps,
} from './collectionCapabilities'

function deps(overrides: Partial<CollectionCapabilityDeps> = {}): CollectionCapabilityDeps {
  return {
    capacitorPlatform: () => 'web',
    isTauri: () => false,
    isSensorEnabled: () => true,
    permissionGranted: async () => false,
    getGuardStatus: async () => null,
    desktopProbeAvailable: async () => true,
    isStandalone: () => true,
    ...overrides,
  }
}

describe('collection capability resolver', () => {
  it('normalizes Android APK/AAB collection and its existing permissions', async () => {
    const result = await resolveCollectionCapabilities(deps({
      capacitorPlatform: () => 'android',
      permissionGranted: async (id) => id !== 'usage',
      isSensorEnabled: (key) => key !== 'phone_charger',
      getGuardStatus: async () => ({
        enabled: true,
        connectedAt: 1,
        lastEventAt: 2,
        lastPingAt: 3,
        evidenceConfigured: true,
      }),
    }))

    expect(result.surface).toBe('android-native')
    expect(result.distribution).toBe('apk-or-aab')
    const capability = (id: string) => result.capabilities.find((item) => item.id === id)
    expect(capability('app-activity')).toMatchObject({ state: 'denied', requirement: 'usage' })
    expect(capability('motion')).toMatchObject({ state: 'granted', requirement: 'motion' })
    expect(capability('charger')).toMatchObject({ state: 'disabled', requirement: null })
    expect(capability('background-collection')).toMatchObject({ state: 'limited', requirement: 'battery' })
    expect(capability('native-evidence')).toMatchObject({ state: 'granted', requirement: null })
    expect(capability('interaction')).toMatchObject({ state: 'granted', requirement: null })
  })

  it('does not equate an armed iOS observer with verified background delivery', async () => {
    const result = await resolveCollectionCapabilities(deps({
      capacitorPlatform: () => 'ios',
      permissionGranted: async (id) => id === 'notifications',
      getGuardStatus: async () => ({
        enabled: true,
        connectedAt: 1,
        lastEventAt: 2,
        lastPingAt: 3,
        health: { supported: true, asked: true, observing: true },
        evidenceConfigured: true,
      }),
    }))

    expect(result.surface).toBe('ios-native')
    expect(result.distribution).toBe('testflight-or-app-store')
    const capability = (id: string) => result.capabilities.find((item) => item.id === id)
    expect(capability('app-activity')).toMatchObject({ state: 'limited', requirement: null })
    expect(capability('motion')).toMatchObject({ state: 'limited' })
    expect(capability('charger')).toMatchObject({ state: 'limited' })
    expect(capability('background-collection')).toMatchObject({ state: 'limited' })
    expect(capability('native-evidence')).toMatchObject({ state: 'granted' })
    expect(capability('interaction')).toMatchObject({ state: 'granted' })
  })

  it('separates Tauri and PWA capability limits without claiming native permissions', async () => {
    const tauri = await resolveCollectionCapabilities(deps({ isTauri: () => true }))
    const pwa = await resolveCollectionCapabilities(deps())

    expect(tauri.surface).toBe('tauri')
    expect(tauri.capabilities.find((item) => item.id === 'desktop-input')).toMatchObject({ state: 'granted' })
    expect(tauri.capabilities.find((item) => item.id === 'native-evidence')).toMatchObject({ state: 'unavailable' })
    expect(tauri.capabilities.find((item) => item.id === 'interaction')).toMatchObject({ state: 'granted' })
    expect(pwa.surface).toBe('pwa')
    expect(pwa.capabilities.find((item) => item.id === 'app-activity')).toMatchObject({ state: 'limited' })
    expect(pwa.capabilities.find((item) => item.id === 'background-collection')).toMatchObject({ state: 'limited' })
    expect(pwa.capabilities.find((item) => item.id === 'native-evidence')).toMatchObject({ state: 'unavailable' })
    expect(pwa.capabilities.find((item) => item.id === 'interaction')).toMatchObject({ state: 'granted' })
  })

  it('does not assume a desktop probe works just because its local switch is on', async () => {
    const result = await resolveCollectionCapabilities(deps({
      isTauri: () => true,
      desktopProbeAvailable: async () => { throw new Error('old shell') },
    }))
    expect(result.capabilities.find((item) => item.id === 'desktop-input')?.state).toBe('unavailable')
    expect(result.capabilities.find((item) => item.id === 'interaction')?.state).toBe('granted')
  })

  it('does not promise automatic evidence from an ordinary browser tab', async () => {
    const result = await resolveCollectionCapabilities(deps({ isStandalone: () => false }))
    expect(result.capabilities.find((item) => item.id === 'interaction')?.state).toBe('limited')
  })

  it('preserves unknown native permission reads rather than presenting a denial', async () => {
    const result = await resolveCollectionCapabilities(deps({ capacitorPlatform: () => 'android', permissionGranted: async () => null }))
    expect(result.capabilities.find((item) => item.id === 'motion')?.state).toBe('unavailable')
  })
})
