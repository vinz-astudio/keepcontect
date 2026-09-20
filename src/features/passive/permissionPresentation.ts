import type { PermissionState } from './guardianPermissions'
import type { CollectionCapabilityState } from './collectionCapabilities'

export function summarizePermissions(
  ids: string[], states: Record<string, PermissionState>, capabilities: CollectionCapabilityState[] | null,
): Exclude<PermissionState, 'restricted'> {
  const values = ids.map((id) => states[id] ?? 'checking')
  if (values.includes('checking')) return 'checking'
  if (values.includes('unavailable') || !capabilities) return 'unavailable'
  if (values.some((value) => value === 'denied' || value === 'prompt')) return 'denied'
  if (!ids.length || values.includes('limited') || values.includes('restricted') || capabilities.some((value) => ['limited', 'unavailable', 'denied'].includes(value))) return 'limited'
  return 'granted'
}

export function sensorPresentationState(enabled: boolean, capability: CollectionCapabilityState | undefined): CollectionCapabilityState {
  return enabled ? capability ?? 'unavailable' : 'disabled'
}
