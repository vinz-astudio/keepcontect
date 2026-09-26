import { Capacitor } from '@capacitor/core'
import { getClientId } from '@/lib/clientReport'
import { SUPABASE_URL } from '@/lib/config'
import { isTauri } from '@/lib/platform'
import { supabase } from '@/lib/supabase'
import { APP_VERSION } from '@/lib/version'
import { isSensorEnabled } from '@/features/signals/sensors'
import {
  bindPassiveCollector,
  buildPassiveEvidenceRequest,
  revokePassiveCollector,
  resumePassiveCollector,
  sameNativeInputIdentity,
  type PassiveCollectorBinding,
  type PassiveEvidenceDraft,
} from './evidenceContract'

export interface TauriCoverageCapability {
  collectorContract: 'tauri-idle-v1'
  collectorState: 'operational' | 'unavailable'
  idleProbeAvailable: boolean
  appVersion: string
  channel: 'tauri'
}

export interface CoverageLeaseArgs {
  _client_id: string
  _channel: 'tauri'
  _collector_contract: 'tauri-idle-v1'
  _collector_state: 'operational'
  _capability_sha256: string
  _observed_at: string
  _event_id: string
}

type TimerHandle = ReturnType<typeof globalThis.setInterval>

export interface ShadowCoverageDeps {
  isTauri: () => boolean
  isNativePlatform: () => boolean
  invokeCapability: () => Promise<TauriCoverageCapability>
  recordLease: (
    args: CoverageLeaseArgs,
  ) => Promise<{ error: unknown | null; data?: unknown }>
  getClientId: () => string
  now: () => number
  randomUUID: () => string
  hashCanonical: (canonical: string) => Promise<string>
  setInterval: (callback: () => void, delay: number) => TimerHandle
  clearInterval: (handle: TimerHandle) => void
  /** Runtime user toggle; absent in legacy tests/consumers means enabled. */
  isCollectionEnabled?: () => boolean
}

const FIVE_MINUTES_MS = 5 * 60_000

const TAURI_OWNER_KEY = 'kc.tauriEvidence.ownerId'
const TAURI_BINDING_KEY = 'kc.tauriEvidence.bindingId'
const TAURI_SEQUENCE_KEY = 'kc.tauriEvidence.sequence'
const TAURI_LAST_INPUT_KEY = 'kc.tauriEvidence.lastInputAt'
const TAURI_LAST_INPUT_ID_KEY = 'kc.tauriEvidence.lastInputIdentity'
const TAURI_QUEUE_KEY = 'kc.tauriEvidence.queue'
const TAURI_LIMITED_KEY = 'kc.tauriEvidence.limited'

export interface TauriEvidenceStatus { state: 'ready' | 'limited' | 'off'; reason: string }
let tauriEvidenceStatus: TauriEvidenceStatus = { state: 'off', reason: 'not_started' }
export function getTauriEvidenceStatus(): TauriEvidenceStatus { return { ...tauriEvidenceStatus } }
function setTauriEvidenceStatus(state: TauriEvidenceStatus['state'], reason: string): void {
  if (tauriEvidenceStatus.state === state && tauriEvidenceStatus.reason === reason) return
  tauriEvidenceStatus = { state, reason }
  if (typeof window !== 'undefined') window.dispatchEvent(new Event('kc-tauri-evidence-status'))
}
const evidenceStops = new Set<() => void>()

export interface TauriInputSample {
  collectorContract: 'tauri-passive-evidence-v1'
  channel: 'tauri'
  probeAvailable: boolean
  sampleTime: string
  idleDurationMs: number
  lastInputAt: string
  inputIdentity?: string
}

interface StoredTauriEvidence {
  ownerId: string
  bindingId: string
  draft: PassiveEvidenceDraft
}

export interface TauriEvidenceDeps {
  isTauri: () => boolean
  isNativePlatform: () => boolean
  getUserId: () => Promise<string | null>
  getClientId: () => string
  invokeInputSample: () => Promise<TauriInputSample | null>
  bind: typeof bindPassiveCollector
  resume: typeof resumePassiveCollector
  revoke: typeof revokePassiveCollector
  sendEvidence: (
    binding: PassiveCollectorBinding,
    draft: PassiveEvidenceDraft,
    signal?: AbortSignal,
  ) => Promise<string>
  randomUUID: () => string
  now: () => number
  storage: Storage
  setInterval: (callback: () => void, delay: number) => TimerHandle
  clearInterval: (handle: TimerHandle) => void
  /** Runtime user toggle; absent in legacy tests/consumers means enabled. */
  isCollectionEnabled?: () => boolean
  subscribeWake?: (callback: () => void) => () => void
  subscribeOwner?: (callback: (owner: string | null) => void) => () => void
}

function readQueue(storage: Storage): StoredTauriEvidence[] {
  try {
    const value = JSON.parse(storage.getItem(TAURI_QUEUE_KEY) ?? '[]')
    return Array.isArray(value) ? value : []
  } catch {
    return []
  }
}

function clearTauriStorage(storage: Storage): void {
  for (const key of [
    TAURI_OWNER_KEY,
    TAURI_BINDING_KEY,
    TAURI_SEQUENCE_KEY,
    TAURI_LAST_INPUT_KEY,
    TAURI_LAST_INPUT_ID_KEY,
    TAURI_QUEUE_KEY,
    TAURI_LIMITED_KEY,
  ]) storage.removeItem(key)
}

async function defaultSendEvidence(
  binding: PassiveCollectorBinding,
  draft: PassiveEvidenceDraft,
  signal?: AbortSignal,
): Promise<string> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/passive-evidence`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(buildPassiveEvidenceRequest(binding, draft)),
    signal,
  })
  const body = await response.json().catch(() => ({})) as { status?: string }
  if (response.status === 429 || response.status >= 500) throw new Error('passive evidence unavailable')
  // Unknown/empty HTTP responses are not proof that a durable event was handled.
  if (!body.status) throw new Error('passive evidence response missing status')
  return body.status
}

const defaultTauriEvidenceDeps: TauriEvidenceDeps = {
  isTauri,
  isNativePlatform: () => Capacitor.isNativePlatform(),
  getUserId: async () => {
    const { data, error } = await supabase.auth.getUser()
    if (error) throw error
    return data.user?.id ?? null
  },
  getClientId,
  invokeInputSample: async () => {
    const internals = (window as unknown as {
      __TAURI_INTERNALS__?: { invoke?: (command: string) => Promise<unknown> }
    }).__TAURI_INTERNALS__
    if (typeof internals?.invoke !== 'function') return null
    const raw = await internals.invoke('get_tauri_input_evidence_sample') as null | {
      collectorContract: string
      channel: string
      probeAvailable: boolean
      sampleTimeMs: number
      idleDurationMs: number
      lastInputAtMs: number
      inputIdentity?: string
    }
    if (!raw) return null
    return {
      collectorContract: raw.collectorContract as TauriInputSample['collectorContract'],
      channel: raw.channel as TauriInputSample['channel'],
      probeAvailable: raw.probeAvailable,
      sampleTime: new Date(raw.sampleTimeMs).toISOString(),
      idleDurationMs: raw.idleDurationMs,
      lastInputAt: new Date(raw.lastInputAtMs).toISOString(),
      inputIdentity: raw.inputIdentity,
    }
  },
  bind: bindPassiveCollector,
  resume: resumePassiveCollector,
  revoke: revokePassiveCollector,
  sendEvidence: defaultSendEvidence,
  randomUUID: () => globalThis.crypto.randomUUID(),
  now: () => Date.now(),
  storage: globalThis.localStorage,
  setInterval: (callback, delay) => globalThis.setInterval(callback, delay),
  clearInterval: (handle) => globalThis.clearInterval(handle),
  isCollectionEnabled: () => isSensorEnabled('system_idle'),
  subscribeWake: (callback) => {
    const visible = () => { if (document.visibilityState === 'visible') callback() }
    window.addEventListener('online', callback)
    window.addEventListener('focus', callback)
    window.addEventListener('kc:sensor-preference-changed', callback)
    document.addEventListener('visibilitychange', visible)
    return () => {
      window.removeEventListener('online', callback)
      window.removeEventListener('focus', callback)
      window.removeEventListener('kc:sensor-preference-changed', callback)
      document.removeEventListener('visibilitychange', visible)
    }
  },
  subscribeOwner: (callback) => {
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      // Never await a Supabase operation inside the synchronous auth callback.
      queueMicrotask(() => callback(session?.user?.id ?? null))
    })
    return () => data.subscription.unsubscribe()
  },
}

function validInputSample(sample: TauriInputSample, now: number): boolean {
  const sampled = Date.parse(sample.sampleTime)
  const input = Date.parse(sample.lastInputAt)
  return sample.collectorContract === 'tauri-passive-evidence-v1'
    && sample.channel === 'tauri'
    && sample.probeAvailable
    && Number.isFinite(sample.idleDurationMs)
    && sample.idleDurationMs >= 0
    && Number.isFinite(sampled)
    && Number.isFinite(input)
    && input <= sampled
    && sampled <= now + FIVE_MINUTES_MS
    && input >= sampled - sample.idleDurationMs - 1_000
    && input <= sampled - sample.idleDurationMs + 1_000
}

export function startTauriPassiveEvidence(
  deps: TauriEvidenceDeps = defaultTauriEvidenceDeps,
): () => void {
  if (!deps.isTauri() || deps.isNativePlatform()) return () => {}
  let stopped = false
  let generation = 0
  let activeGeneration: number | null = null
  let ownerId: string | null = null
  let ownerKnown = false
  let binding: PassiveCollectorBinding | null = null
  let retryAt = 0
  let failures = 0
  let lastSampleAt = -Infinity
  let collectionWasEnabled = deps.isCollectionEnabled?.() ?? true
  let activeUpload: AbortController | null = null
  const current = (epoch: number) => !stopped && epoch === generation
  const selectOwner = (next: string | null) => {
    if (ownerKnown && next === ownerId) return
    generation++
    ownerKnown = true
    ownerId = next
    binding = null
    activeGeneration = null
    retryAt = 0
    failures = 0
    lastSampleAt = -Infinity
    if (deps.storage.getItem(TAURI_OWNER_KEY) !== next) clearTauriStorage(deps.storage)
    if (next) deps.storage.setItem(TAURI_OWNER_KEY, next)
    setTauriEvidenceStatus(next ? 'limited' : 'off', next ? 'connecting' : 'signed_out')
  }
  const terminal = (reason: string) => {
    binding = null
    deps.storage.setItem(TAURI_LIMITED_KEY, reason)
    setTauriEvidenceStatus('limited', reason)
  }

  const flush = async (epoch: number) => {
    if (!binding || !ownerId || !(deps.isCollectionEnabled?.() ?? true)) return
    const sendingBinding = binding
    const queue = readQueue(deps.storage)
    const first = queue.find((item) => item.ownerId === ownerId && item.bindingId === sendingBinding.bindingId)
    if (!first) return
    const controller = new AbortController()
    activeUpload = controller
    let timeout: ReturnType<typeof setTimeout> | undefined
    let status: string
    try {
      status = await Promise.race([
        deps.sendEvidence(sendingBinding, first.draft, controller.signal),
        new Promise<never>((_resolve, reject) => {
          timeout = setTimeout(() => {
            controller.abort()
            reject(new Error('passive evidence upload timed out'))
          }, 15_000)
        }),
      ])
    } finally {
      clearTimeout(timeout)
      if (activeUpload === controller) activeUpload = null
    }
    if (!current(epoch)) return
    if (status === 'inserted' || status === 'duplicate' || status === 'invalid'
      || status === 'outside_epoch' || status === 'conflict') {
      deps.storage.setItem(TAURI_QUEUE_KEY, JSON.stringify(readQueue(deps.storage).filter(
        (item) => !(item.bindingId === first.bindingId && item.draft.eventId === first.draft.eventId),
      )))
    } else if (status === 'revoked' || status === 'unregistered_binding'
      || status === 'credential_mismatch') {
      terminal(status)
    } else throw new Error(`passive evidence pending: ${status}`)
  }

  const run = async () => {
    if (stopped || activeGeneration === generation || deps.now() < retryAt) return
    if (!(deps.isCollectionEnabled?.() ?? true)) {
      setTauriEvidenceStatus('off', 'disabled')
      return
    }
    let epoch = generation
    activeGeneration = epoch
    try {
      if (!ownerKnown) {
        const userId = await deps.getUserId()
        if (!current(epoch)) return
        selectOwner(userId)
        epoch = generation
        activeGeneration = epoch
      }
      if (!ownerId) return
      const limited = deps.storage.getItem(TAURI_LIMITED_KEY)
      if (limited) { setTauriEvidenceStatus('limited', limited); return }
      if (!binding) {
        const storedBinding = deps.storage.getItem(TAURI_BINDING_KEY)
        const resumed = storedBinding
          ? await deps.resume(storedBinding, APP_VERSION)
          : await deps.bind(deps.getClientId(), 'tauri_native', APP_VERSION)
        if (!current(epoch)) return
        if (storedBinding && resumed.bindingId !== storedBinding) throw new Error('Collector resume changed identity')
        binding = resumed
        deps.storage.setItem(TAURI_BINDING_KEY, binding.bindingId)
        const queuedMaximum = readQueue(deps.storage).reduce((max, item) => item.bindingId === binding?.bindingId
          ? Math.max(max, item.draft.sequence) : max, -1)
        const storedSequence = Number(deps.storage.getItem(TAURI_SEQUENCE_KEY) ?? '-1')
        deps.storage.setItem(TAURI_SEQUENCE_KEY, String(Math.max(
          Number.isSafeInteger(storedSequence) ? storedSequence : -1,
          queuedMaximum, (binding.nextSequence ?? 0) - 1,
        )))
      }
      // Capture before attempting network IO: an offline head must not stop
      // newer device inputs from becoming durable events in this same queue.
      if (deps.now() - lastSampleAt < FIVE_MINUTES_MS) {
        await flush(epoch)
        if (current(epoch) && binding) { failures = 0; setTauriEvidenceStatus('ready', 'collecting') }
        return
      }
      const sample = await deps.invokeInputSample()
      if (!current(epoch)) return
      if (!sample || !validInputSample(sample, deps.now())) {
        await flush(epoch)
        if (!current(epoch) || !binding) return
        setTauriEvidenceStatus('limited', 'input_probe_unavailable')
        return
      }
      lastSampleAt = deps.now()
      const lastStored = Date.parse(deps.storage.getItem(TAURI_LAST_INPUT_KEY) ?? '')
      const observed = Date.parse(sample.lastInputAt)
      if (sameNativeInputIdentity(sample.inputIdentity, deps.storage.getItem(TAURI_LAST_INPUT_ID_KEY))
        || (Number.isFinite(lastStored) && observed <= lastStored + 1_000)) {
        await flush(epoch)
        if (current(epoch) && binding) { failures = 0; setTauriEvidenceStatus('ready', 'collecting') }
        return
      }
      const sequence = Number(deps.storage.getItem(TAURI_SEQUENCE_KEY) ?? '-1') + 1
      const draft: PassiveEvidenceDraft = {
        eventId: deps.randomUUID(),
        sequence,
        observedAt: sample.lastInputAt,
        evidenceClass: 'direct_device_use',
        correlationId: null,
        qualificationFacts: { interaction: true },
        queryStartedAt: sample.lastInputAt,
        queryEndedAt: sample.sampleTime,
        querySucceeded: true,
      }
      const queue = readQueue(deps.storage)
      queue.push({ ownerId, bindingId: binding.bindingId, draft })
      deps.storage.setItem(TAURI_QUEUE_KEY, JSON.stringify(queue))
      deps.storage.setItem(TAURI_SEQUENCE_KEY, String(sequence))
      deps.storage.setItem(TAURI_LAST_INPUT_KEY, sample.lastInputAt)
      if (sample.inputIdentity) deps.storage.setItem(TAURI_LAST_INPUT_ID_KEY, sample.inputIdentity)
      await flush(epoch)
      if (current(epoch) && binding) { failures = 0; setTauriEvidenceStatus('ready', 'collecting') }
    } catch (error) {
      if (!current(epoch)) return
      const code = (error as { code?: string })?.code
      if (ownerId && (code === '55000' || code === '42501')) terminal('collector_unavailable')
      else {
        setTauriEvidenceStatus('limited', 'retry_pending')
        retryAt = deps.now() + Math.min(FIVE_MINUTES_MS, 30_000 * 2 ** Math.min(failures++, 4))
      }
    } finally {
      if (activeGeneration === epoch) activeGeneration = null
    }
  }

  const wake = () => {
    const enabled = deps.isCollectionEnabled?.() ?? true
    if (enabled !== collectionWasEnabled) {
      generation++
      activeGeneration = null
      binding = null
      if (enabled && ownerId && deps.storage.getItem(TAURI_OWNER_KEY) === ownerId
        && deps.storage.getItem(TAURI_LIMITED_KEY)) {
        // An observed off→on user action can re-enroll. Retain old binding's
        // rejected queue for diagnosis; never relabel its events to the new ID.
        for (const key of [TAURI_BINDING_KEY, TAURI_LIMITED_KEY, TAURI_SEQUENCE_KEY, TAURI_LAST_INPUT_KEY, TAURI_LAST_INPUT_ID_KEY]) {
          deps.storage.removeItem(key)
        }
      }
      collectionWasEnabled = enabled
      lastSampleAt = -Infinity
    }
    retryAt = 0
    void run()
  }
  const unsubscribeOwner = deps.subscribeOwner?.((next) => { if (!stopped) { selectOwner(next); wake() } })
  const unsubscribeWake = deps.subscribeWake?.(wake)
  const timer = deps.setInterval(() => void run(), 30_000)
  void run()
  const stop = () => {
    stopped = true
    activeUpload?.abort()
    generation++
    binding = null
    deps.clearInterval(timer)
    unsubscribeOwner?.()
    unsubscribeWake?.()
    evidenceStops.delete(stop)
  }
  evidenceStops.add(stop)
  return stop
}

export async function clearTauriPassiveEvidence(
  deps: Pick<TauriEvidenceDeps, 'isTauri' | 'storage' | 'revoke'> = defaultTauriEvidenceDeps,
): Promise<void> {
  if (!deps.isTauri()) return
  for (const stop of evidenceStops) stop()
  const bindingId = deps.storage.getItem(TAURI_BINDING_KEY)
  clearTauriStorage(deps.storage)
  setTauriEvidenceStatus('off', 'signed_out')
  if (bindingId) {
    // No account credential is retained for this best-effort cleanup. A hung
    // authenticated request must not delay erasing the local collector.
    void deps.revoke(bindingId).catch(() => {})
  }
}

/** Outcomes that mean the server took the lease (or is deliberately not taking any). */
const ACCEPTED_LEASE_OUTCOMES = new Set(['inserted', 'duplicate', 'disabled'])

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value)
  const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest))
    .map((item) => item.toString(16).padStart(2, '0'))
    .join('')
}

const defaultDeps: ShadowCoverageDeps = {
  isTauri,
  isNativePlatform: () => Capacitor.isNativePlatform(),
  invokeCapability: async () => {
    const internals = (window as unknown as {
      __TAURI_INTERNALS__?: {
        invoke?: (command: string) => Promise<unknown>
      }
    }).__TAURI_INTERNALS__
    if (typeof internals?.invoke !== 'function') {
      throw new Error('Tauri invoke unavailable')
    }
    return await internals.invoke(
      'get_alert_shadow_coverage_capability',
    ) as TauriCoverageCapability
  },
  recordLease: async (args) => {
    const { data, error } = await supabase.rpc(
      'record_alert_shadow_coverage_lease' as never,
      args as never,
    )
    return { error, data }
  },
  getClientId,
  now: () => Date.now(),
  randomUUID: () => globalThis.crypto.randomUUID(),
  hashCanonical: sha256,
  setInterval: (callback, delay) => globalThis.setInterval(callback, delay),
  clearInterval: (handle) => globalThis.clearInterval(handle),
  isCollectionEnabled: () => isSensorEnabled('system_idle'),
}

function isOperational(
  capability: TauriCoverageCapability,
): capability is TauriCoverageCapability & {
  collectorState: 'operational'
} {
  return capability.collectorContract === 'tauri-idle-v1'
    && capability.collectorState === 'operational'
    && capability.idleProbeAvailable
    && capability.channel === 'tauri'
    && capability.appVersion.trim().length > 0
}

export function startTauriShadowCoverage(
  deps: ShadowCoverageDeps = defaultDeps,
): () => void {
  if (!deps.isTauri() || deps.isNativePlatform()) return () => {}

  let stopped = false
  let inFlight = false

  const submit = async () => {
    if (stopped || inFlight || !(deps.isCollectionEnabled?.() ?? true)) return
    inFlight = true
    try {
      const capability = await deps.invokeCapability()
      if (stopped || !isOperational(capability)) return

      const canonical = JSON.stringify({
        appVersion: capability.appVersion,
        channel: capability.channel,
        collectorContract: capability.collectorContract,
        idleProbeAvailable: capability.idleProbeAvailable,
      })
      const capabilitySha256 = await deps.hashCanonical(canonical)
      if (stopped) return

      const { error, data } = await deps.recordLease({
        _client_id: deps.getClientId(),
        _channel: 'tauri',
        _collector_contract: 'tauri-idle-v1',
        _collector_state: 'operational',
        _capability_sha256: capabilitySha256,
        _observed_at: new Date(deps.now()).toISOString(),
        _event_id: deps.randomUUID(),
      })

      // The RPC reports refusals in its return value, not as an error, so a
      // rejected lease looks exactly like a healthy one from here. Left unread,
      // a watcher can be refused every five minutes for days while the server
      // records no coverage at all — which is what happened to the desktop
      // shell reporting itself as `desktop-web`.
      if (!error && !ACCEPTED_LEASE_OUTCOMES.has(data as string)) {
        console.error('[coverage] shadow lease refused:', data)
      }
    } catch {
      // Coverage is evidence-only. A failed lease waits for the next normal tick.
    } finally {
      inFlight = false
    }
  }

  void submit()
  const timer = deps.setInterval(() => void submit(), FIVE_MINUTES_MS)

  return () => {
    stopped = true
    deps.clearInterval(timer)
  }
}
