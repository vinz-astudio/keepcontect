import { raiseSos as defaultRaiseSos, updateSosLocation as defaultUpdateSosLocation } from './api'
import { triggerPushDispatch as defaultTriggerPushDispatch } from '@/features/push/pushApi'
import { getCurrentCoords as defaultGetCurrentCoords } from '@/lib/geo'

export interface SosDispatchDeps {
  raiseSos?: () => Promise<string>
  updateSosLocation?: (lat: number, lng: number) => Promise<boolean>
  triggerPushDispatch?: () => Promise<void>
  getCurrentCoords?: () => Promise<{ lat: number; lng: number } | null>
  /** Whether the user agreed to share coordinates during an SOS. */
  hasGpsConsent?: () => boolean
}

/**
 * Read from the local mirror rather than the server on purpose. This runs on
 * the SOS path, where a network round-trip before deciding anything is the
 * wrong trade; the account-level answer in `user_settings.emergency_gps_consent`
 * is loaded into this key at sign-in and whenever the switch is used.
 *
 * Unreadable storage denies consent. An emergency is the worst possible moment
 * to discover we guessed generously about a privacy decision.
 */
export function readLocalGpsConsent(): boolean {
  try {
    return localStorage.getItem('kc.emergency_gps_consent') === 'true'
  } catch {
    return false
  }
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
  const consented = deps.hasGpsConsent || readLocalGpsConsent

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
      // The consent switch used to have no effect here: coordinates were
      // fetched and uploaded whether or not the user had agreed, which made the
      // control on the Me screen a promise KC did not keep. Checked before the
      // fetch, not after, so a user who declined is never even asked for a
      // position — the alert still goes out, just without a location.
      if (!consented()) return
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
