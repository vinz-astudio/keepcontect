import { Capacitor } from '@capacitor/core'
import { getClientId } from '@/lib/clientReport'
import { SUPABASE_URL } from '@/lib/config'
import { isTauri } from '@/lib/platform'
import { supabase } from '@/lib/supabase'
import { APP_VERSION } from '@/lib/version'
import {
  bindPassiveCollector,
  buildPassiveEvidenceRequest,
  revokePassiveCollector,
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
}

const FIVE_MINUTES_MS = 5 * 60_000

const TAURI_OWNER_KEY = 'kc.tauriEvidence.ownerId'
const TAURI_BINDING_KEY = 'kc.tauriEvidence.bindingId'
const TAURI_SEQUENCE_KEY = 'kc.tauriEvidence.sequence'
const TAURI_LAST_INPUT_KEY = 'kc.tauriEvidence.lastInputAt'
const TAURI_QUEUE_KEY = 'kc.tauriEvidence.queue'

export interface TauriInputSample {
  collectorContract: 'tauri-passive-evidence-v1'
  channel: 'tauri'
  probeAvailable: boolean
  sampleTime: string
  idleDurationMs: number
  lastInputAt: string
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
  revoke: typeof revokePassiveCollector
  sendEvidence: (
    binding: PassiveCollectorBinding,
    draft: PassiveEvidenceDraft,
  ) => Promise<string>
  randomUUID: () => string
  now: () => number
  storage: Storage
  setInterval: (callback: () => void, delay: number) => TimerHandle
  clearInterval: (handle: TimerHandle) => void
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
    TAURI_QUEUE_KEY,
  ]) storage.removeItem(key)
}

async function defaultSendEvidence(
  binding: PassiveCollectorBinding,
  draft: PassiveEvidenceDraft,
): Promise<string> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/passive-evidence`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(buildPassiveEvidenceRequest(binding, draft)),
  })
  const body = await response.json().catch(() => ({})) as { status?: string }
  if (!response.ok && response.status >= 500) throw new Error('passive evidence unavailable')
  return body.status ?? 'invalid'
}

const defaultTauriEvidenceDeps: TauriEvidenceDeps = {
  isTauri,
  isNativePlatform: () => Capacitor.isNativePlatform(),
  getUserId: async () => {
    const { data } = await supabase.auth.getUser()
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
    }
    if (!raw) return null
    return {
      collectorContract: raw.collectorContract as TauriInputSample['collectorContract'],
      channel: raw.channel as TauriInputSample['channel'],
      probeAvailable: raw.probeAvailable,
      sampleTime: new Date(raw.sampleTimeMs).toISOString(),
      idleDurationMs: raw.idleDurationMs,
      lastInputAt: new Date(raw.lastInputAtMs).toISOString(),
    }
  },
  bind: bindPassiveCollector,
  revoke: revokePassiveCollector,
  sendEvidence: defaultSendEvidence,
  randomUUID: () => globalThis.crypto.randomUUID(),
  now: () => Date.now(),
  storage: globalThis.localStorage,
  setInterval: (callback, delay) => globalThis.setInterval(callback, delay),
  clearInterval: (handle) => globalThis.clearInterval(handle),
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
  let inFlight = false
  let timer: TimerHandle | null = null
  let ownerId: string | null = null
  let binding: PassiveCollectorBinding | null = null

  const flush = async () => {
    if (!binding || !ownerId) return
    const queue = readQueue(deps.storage)
      .filter((item) => item.ownerId === ownerId && item.bindingId === binding?.bindingId)
    deps.storage.setItem(TAURI_QUEUE_KEY, JSON.stringify(queue))
    const first = queue[0]
    if (!first) return
    const status = await deps.sendEvidence(binding, first.draft)
    if (status === 'inserted' || status === 'duplicate' || status === 'invalid'
      || status === 'outside_epoch' || status === 'conflict') {
      queue.shift()
      deps.storage.setItem(TAURI_QUEUE_KEY, JSON.stringify(queue))
    } else if (status === 'revoked' || status === 'unregistered_binding'
      || status === 'credential_mismatch') {
      clearTauriStorage(deps.storage)
      binding = null
    }
  }

  const sampleInput = async () => {
    if (stopped || inFlight || !binding || !ownerId) return
    inFlight = true
    try {
      await flush()
      if (!binding) return
      const sample = await deps.invokeInputSample()
      if (!sample || !validInputSample(sample, deps.now())) return
      const lastStored = Date.parse(deps.storage.getItem(TAURI_LAST_INPUT_KEY) ?? '')
      const observed = Date.parse(sample.lastInputAt)
      if (Number.isFinite(lastStored) && observed <= lastStored) return
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
      await flush()
    } catch {
      // Offline evidence remains in the owner-partitioned queue for the next tick.
    } finally {
      inFlight = false
    }
  }

  void (async () => {
    ownerId = await deps.getUserId()
    if (stopped || !ownerId) return
    const storedOwner = deps.storage.getItem(TAURI_OWNER_KEY)
    const storedBinding = deps.storage.getItem(TAURI_BINDING_KEY)
    if (storedOwner !== ownerId) {
      clearTauriStorage(deps.storage)
    } else if (storedBinding) {
      try { await deps.revoke(storedBinding) } catch { /* replacement fails closed */ }
      clearTauriStorage(deps.storage)
    }
    if (stopped) return
    binding = await deps.bind(deps.getClientId(), 'tauri_native', APP_VERSION)
    deps.storage.setItem(TAURI_OWNER_KEY, ownerId)
    deps.storage.setItem(TAURI_BINDING_KEY, binding.bindingId)
    deps.storage.setItem(TAURI_SEQUENCE_KEY, '-1')
    deps.storage.setItem(TAURI_QUEUE_KEY, '[]')
    await sampleInput()
    if (!stopped) timer = deps.setInterval(() => void sampleInput(), FIVE_MINUTES_MS)
  })().catch(() => {})

  return () => {
    stopped = true
    if (timer !== null) deps.clearInterval(timer)
  }
}

export async function clearTauriPassiveEvidence(
  deps: Pick<TauriEvidenceDeps, 'isTauri' | 'storage' | 'revoke'> = defaultTauriEvidenceDeps,
): Promise<void> {
  if (!deps.isTauri()) return
  const bindingId = deps.storage.getItem(TAURI_BINDING_KEY)
  if (bindingId) {
    try { await deps.revoke(bindingId) } catch { /* local clear is authoritative */ }
  }
  clearTauriStorage(deps.storage)
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
    if (stopped || inFlight) return
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
