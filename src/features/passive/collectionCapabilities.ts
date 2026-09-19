import { Capacitor } from '@capacitor/core'
import { getGuardianPermissions } from '@/features/passive/guardianPermissions'
import { getGuardStatus, type GuardStatus } from '@/features/passive/native'
import { isSensorEnabled } from '@/features/signals/sensors'
import { isTauri } from '@/lib/platform'

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
  permissionGranted: (id: GuardianPermissionId) => Promise<boolean>
  getGuardStatus: () => Promise<GuardStatus | null>
}

const defaultDeps: CollectionCapabilityDeps = {
  capacitorPlatform: () => Capacitor.getPlatform(),
  isTauri,
  isSensorEnabled,
  permissionGranted: async (id) => {
    const permission = getGuardianPermissions().find((candidate) => candidate.id === id)
    return permission ? permission.check() : false
  },
  getGuardStatus,
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
    return definition.requirement && await deps.permissionGranted(definition.requirement) ? 'granted' : 'denied'
  }
  // iOS has these collectors, but they run only when the OS permits execution.
  // A bound/armed watcher does not verify continuous background coverage.
  if (definition.id === 'motion' || definition.id === 'charger') return 'limited'
  if (definition.id === 'background-collection') {
    return 'limited'
  }
  if (definition.id === 'app-activity') {
    if (!deps.isSensorEnabled('app_activity')) return 'disabled'
    const status = await deps.getGuardStatus()
    return status?.enabled === true && status.evidenceConfigured === true ? 'granted' : 'limited'
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
      ? (deps.isSensorEnabled('system_idle') ? 'granted' : 'disabled')
      : definition.id === 'interaction'
        ? (deps.isSensorEnabled('interaction') ? 'granted' : 'disabled')
      : 'unavailable'
  } else {
    state = definition.id === 'native-evidence' ? 'unavailable'
      : definition.id === 'interaction'
        ? (deps.isSensorEnabled('interaction') ? 'granted' : 'disabled')
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
    capabilities: await Promise.all(definition.capabilities.map((capability) => resolveCapability(surface, capability, deps))),
  }
}
