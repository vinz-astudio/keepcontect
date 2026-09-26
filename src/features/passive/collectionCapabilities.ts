import { Capacitor } from '@capacitor/core'
import { getGuardianPermissions } from '@/features/passive/guardianPermissions'
import { getGuardStatus, type GuardStatus } from '@/features/passive/native'
import { isSensorEnabled } from '@/features/signals/sensors'
import { isTauri, isStandalone } from '@/lib/platform'
import { getTauriEvidenceStatus } from './shadowCoverage'

export type CollectionSurface = 'android-native' | 'ios-native' | 'tauri' | 'pwa'
export type CollectionDistribution =
  | 'apk-or-aab'
  | 'testflight-or-app-store'
  | 'desktop-installer'
  | 'web-or-installed-pwa'
export type CollectionCapabilityId =
  | 'interaction'
  | 'app-activity'
  | 'motion'
  | 'charger'
  | 'background-collection'
  | 'native-evidence'
  | 'desktop-input'
export type CollectionCapabilityState = 'granted' | 'denied' | 'disabled' | 'limited' | 'unavailable'
export type GuardianPermissionId = 'notifications' | 'battery' | 'motion' | 'usage'

export interface CollectionCapabilityDefinition {
  id: CollectionCapabilityId
  requirement: GuardianPermissionId | null
}

export interface CollectionSurfaceDefinition {
  distribution: CollectionDistribution
  capabilities: readonly CollectionCapabilityDefinition[]
}

/**
 * Static platform truth. APK and AAB intentionally share one Android-native
 * entry: they execute the same Capacitor bridge and must not diverge in UI
 * claims merely because they were distributed differently.
 */
export const COLLECTION_CAPABILITY_REGISTRY: Readonly<Record<CollectionSurface, CollectionSurfaceDefinition>> = {
  'android-native': {
    distribution: 'apk-or-aab',
    capabilities: [
      { id: 'app-activity', requirement: 'usage' },
      { id: 'motion', requirement: 'motion' },
      { id: 'charger', requirement: null },
      { id: 'background-collection', requirement: 'battery' },
      { id: 'native-evidence', requirement: null },
      { id: 'interaction', requirement: null },
    ],
  },
  'ios-native': {
    distribution: 'testflight-or-app-store',
    capabilities: [
      { id: 'app-activity', requirement: null },
      { id: 'motion', requirement: null },
      { id: 'charger', requirement: null },
      { id: 'background-collection', requirement: null },
      { id: 'native-evidence', requirement: null },
      { id: 'interaction', requirement: null },
    ],
  },
  tauri: {
    distribution: 'desktop-installer',
    capabilities: [
      { id: 'desktop-input', requirement: null },
      { id: 'native-evidence', requirement: null },
      { id: 'interaction', requirement: null },
    ],
  },
  pwa: {
    distribution: 'web-or-installed-pwa',
    capabilities: [
      { id: 'app-activity', requirement: null },
      { id: 'background-collection', requirement: null },
      { id: 'native-evidence', requirement: null },
      { id: 'interaction', requirement: null },
    ],
  },
}

export interface ResolvedCollectionCapability extends CollectionCapabilityDefinition {
  state: CollectionCapabilityState
}

export interface CollectionCapabilitySnapshot {
  surface: CollectionSurface
  distribution: CollectionDistribution
  capabilities: ResolvedCollectionCapability[]
}

export interface CollectionCapabilityDeps {
  capacitorPlatform: () => string
  isTauri: () => boolean
  isSensorEnabled: (key: string) => boolean
  permissionGranted: (id: GuardianPermissionId) => Promise<boolean | null>
  getGuardStatus: () => Promise<GuardStatus | null>
  desktopProbeAvailable: () => Promise<boolean | null>
  desktopCollectorReady?: () => boolean
  isStandalone: () => boolean
}

const defaultDeps: CollectionCapabilityDeps = {
  capacitorPlatform: () => Capacitor.getPlatform(),
  isTauri,
  isSensorEnabled,
  isStandalone,
  permissionGranted: async (id) => {
    const permission = getGuardianPermissions().find((candidate) => candidate.id === id)
    const state = permission ? await permission.check() : 'unavailable'
    return state === 'granted' ? true : state === 'denied' || state === 'prompt' ? false : null
  },
  getGuardStatus,
  desktopCollectorReady: () => getTauriEvidenceStatus().state === 'ready',
  desktopProbeAvailable: async () => {
    const internals = (window as unknown as {
      __TAURI_INTERNALS__?: { invoke?: (name: string) => Promise<{ idleProbeAvailable?: boolean }> }
    }).__TAURI_INTERNALS__
    if (!internals?.invoke) return null
    const result = await internals.invoke('get_alert_shadow_coverage_capability')
    return typeof result?.idleProbeAvailable === 'boolean' ? result.idleProbeAvailable : null
  },
}

export function detectCollectionSurface(
  deps: Pick<CollectionCapabilityDeps, 'capacitorPlatform' | 'isTauri'> = defaultDeps,
): CollectionSurface {
  if (deps.isTauri()) return 'tauri'
  if (deps.capacitorPlatform() === 'android') return 'android-native'
  if (deps.capacitorPlatform() === 'ios') return 'ios-native'
  return 'pwa'
}

async function nativeEvidenceState(deps: CollectionCapabilityDeps): Promise<CollectionCapabilityState> {
  const status = await deps.getGuardStatus()
  return status?.evidenceConfigured === true ? 'granted' : 'limited'
}

async function resolveNativeCapability(
  surface: 'android-native' | 'ios-native',
  definition: CollectionCapabilityDefinition,
  deps: CollectionCapabilityDeps,
): Promise<CollectionCapabilityState> {
  if (definition.id === 'native-evidence') return nativeEvidenceState(deps)
  if (definition.id === 'interaction') return deps.isSensorEnabled('interaction') ? 'granted' : 'disabled'
  if (surface === 'android-native') {
    if (definition.id === 'charger') return deps.isSensorEnabled('phone_charger') ? 'granted' : 'disabled'
    if (definition.id === 'app-activity' && !deps.isSensorEnabled('app_activity')) return 'disabled'
    if (definition.id === 'motion' && !deps.isSensorEnabled('motion')) return 'disabled'
    const allowed = definition.requirement ? await deps.permissionGranted(definition.requirement) : null
    if (allowed === null) return 'unavailable'
    if (!allowed) return 'denied'
    return definition.id === 'background-collection' ? 'limited' : 'granted'
  }
  // iOS has these collectors, but they run only when the OS permits execution.
  // A bound/armed watcher does not verify continuous background coverage.
  if (definition.id === 'motion' || definition.id === 'charger') return deps.isSensorEnabled('app_activity') ? 'limited' : 'disabled'
  if (definition.id === 'background-collection') {
    return 'limited'
  }
  if (definition.id === 'app-activity') {
    if (!deps.isSensorEnabled('app_activity')) return 'disabled'
    return 'limited'
  }
  return 'unavailable'
}

async function resolveCapability(
  surface: CollectionSurface,
  definition: CollectionCapabilityDefinition,
  deps: CollectionCapabilityDeps,
): Promise<ResolvedCollectionCapability> {
  let state: CollectionCapabilityState
  if (surface === 'android-native' || surface === 'ios-native') {
    state = await resolveNativeCapability(surface, definition, deps)
  } else if (surface === 'tauri') {
    state = definition.id === 'desktop-input'
      ? (!deps.isSensorEnabled('system_idle') ? 'disabled' : await deps.desktopProbeAvailable() !== true ? 'unavailable' : deps.desktopCollectorReady?.() === false ? 'limited' : 'granted')
      : definition.id === 'interaction'
        ? (deps.isSensorEnabled('interaction') ? 'granted' : 'disabled')
      : 'unavailable'
  } else {
    state = definition.id === 'native-evidence' ? 'unavailable'
      : definition.id === 'interaction'
        ? (deps.isSensorEnabled('interaction') ? (deps.isStandalone() ? 'granted' : 'limited') : 'disabled')
        : 'limited'
  }
  return { ...definition, state }
}

export async function resolveCollectionCapabilities(
  deps: CollectionCapabilityDeps = defaultDeps,
): Promise<CollectionCapabilitySnapshot> {
  const surface = detectCollectionSurface(deps)
  const definition = COLLECTION_CAPABILITY_REGISTRY[surface]
  return {
    surface,
    distribution: definition.distribution,
    capabilities: await Promise.all(definition.capabilities.map(async (capability) => {
      try { return await resolveCapability(surface, capability, deps) }
      catch { return { ...capability, state: 'unavailable' as const } }
    })),
  }
}
