import { raiseSos as defaultRaiseSos, updateSosLocation as defaultUpdateSosLocation } from './api'
import { triggerPushDispatch as defaultTriggerPushDispatch } from '@/features/push/pushApi'
import { getCurrentCoords as defaultGetCurrentCoords } from '@/lib/geo'

export interface SosDispatchDeps {
  raiseSos?: () => Promise<string>
  updateSosLocation?: (lat: number, lng: number) => Promise<boolean>
  triggerPushDispatch?: () => Promise<void>
  getCurrentCoords?: () => Promise<{ lat: number; lng: number } | null>
}

/**
 * Dispatches an SOS alert immediately and asynchronously fetches and updates the location.
 * Awaits the initial SOS creation (raise_sos), then triggers detached push notification
 * and geolocation update. Sync/async failures in the detached stages are swallowed.
 */
export async function dispatchSos(deps: SosDispatchDeps = {}): Promise<string> {
  const raise = deps.raiseSos || defaultRaiseSos
  const push = deps.triggerPushDispatch || defaultTriggerPushDispatch
  const geo = deps.getCurrentCoords || defaultGetCurrentCoords
  const update = deps.updateSosLocation || defaultUpdateSosLocation

  // 1. Await raiseSos (must succeed before starting push or geo)
  const alertId = await raise()

  // 2. Detached Push (immediately-invoked async wrapper, fire-and-forget, swallow any failures)
  ;(async () => {
    try {
      await push()
    } catch (err) {
      console.error('Detached push dispatch failed:', err)
    }
  })()

  // 3. Detached Geo (immediately-invoked async wrapper, fire-and-forget, swallow any failures, late coords once, null no update, false no retry)
  ;(async () => {
    try {
      const coords = await geo()
      if (coords && coords.lat != null && coords.lng != null) {
        await update(coords.lat, coords.lng)
      }
    } catch (err) {
      console.error('Detached geo update failed:', err)
    }
  })()

  return alertId
}
