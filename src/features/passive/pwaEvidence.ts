import type { PassiveEvidenceDraft, PassiveSurfaceType } from './evidenceContract'
import { APP_VERSION } from '@/lib/version'

const FIVE_MINUTES = 5 * 60_000

interface PwaEvidenceDeps {
  eligible: () => boolean
  visible: () => boolean
  getUserId: () => Promise<string | null>
  now: () => number
  randomUUID: () => string
  instanceId: string
  bind: (instance: string, surface: PassiveSurfaceType, version: string) => Promise<{ bindingId: string }>
  send: (bindingId: string, event: PassiveEvidenceDraft) => Promise<string>
  revoke: (bindingId: string) => Promise<boolean>
}

/** One signed-in session. Timers retry genuine events; they never create one. */
export function createPwaEvidenceCollector(ownerId: string, deps: PwaEvidenceDeps) {
  let stopped = false
  let bindingId: string | null = null
  let sequence = 0
  let lastInteraction = -Infinity
  let queue: PassiveEvidenceDraft[] = []
  let serial = Promise.resolve()
  const revoke = (id: string) => { void deps.revoke(id).catch(() => {}) }
  const stillOwned = async () => {
    if (stopped) return false
    const current = await deps.getUserId()
    if (stopped || current !== ownerId) {
      stopped = true
      queue = []
      if (bindingId) revoke(bindingId)
      bindingId = null
      return false
    }
    return true
  }

  async function flush() {
    if (!await stillOwned() || !deps.eligible()) return
    queue = queue.filter((event) => deps.now() - Date.parse(event.observedAt) <= FIVE_MINUTES)
    if (!queue.length) return
    if (!bindingId) {
      const bound = await deps.bind(deps.instanceId, 'pwa_browser', APP_VERSION)
      if (!await stillOwned()) { revoke(bound.bindingId); return }
      bindingId = bound.bindingId
    }
    while (queue.length && await stillOwned() && deps.eligible()) {
      const event = queue[0]
      if (deps.now() - Date.parse(event.observedAt) > FIVE_MINUTES) { queue.shift(); continue }
      const status = await deps.send(bindingId!, event)
      if (['inserted', 'duplicate', 'invalid', 'outside_epoch', 'conflict'].includes(status)) {
        queue.shift()
      } else if (['revoked', 'unregistered_binding', 'credential_mismatch'].includes(status)) {
        // Never reassign an old event to a replacement identity.
        queue = []
        bindingId = null
        sequence = 0
        return
      } else {
        return // Unknown response: retain the original identity for a bounded retry.
      }
    }
  }

  function retry() {
    serial = serial.then(flush).catch(() => { /* keep the original event while offline */ })
    return serial
  }

  return {
    interaction(trusted: boolean): Promise<void> {
      if (stopped || !trusted || !deps.visible() || !deps.eligible()) return Promise.resolve()
      const now = deps.now()
      if (now - lastInteraction < FIVE_MINUTES) return retry()
      lastInteraction = now
      queue.push({ eventId: deps.randomUUID(), sequence: sequence++, observedAt: new Date(now).toISOString(),
        evidenceClass: 'direct_device_use', correlationId: null, qualificationFacts: { interaction: true } })
      return retry()
    },
    retry,
    stop() {
      stopped = true
      queue = []
      if (bindingId) revoke(bindingId)
      bindingId = null
    },
  }
}
