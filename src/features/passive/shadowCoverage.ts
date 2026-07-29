import { Capacitor } from '@capacitor/core'
import { getClientId } from '@/lib/clientReport'
import { isTauri } from '@/lib/platform'
import { supabase } from '@/lib/supabase'

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
  ) => Promise<{ error: unknown | null }>
  getClientId: () => string
  now: () => number
  randomUUID: () => string
  hashCanonical: (canonical: string) => Promise<string>
  setInterval: (callback: () => void, delay: number) => TimerHandle
  clearInterval: (handle: TimerHandle) => void
}

const FIVE_MINUTES_MS = 5 * 60_000

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
    const { error } = await supabase.rpc(
      'record_alert_shadow_coverage_lease' as never,
      args as never,
    )
    return { error }
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

      await deps.recordLease({
        _client_id: deps.getClientId(),
        _channel: 'tauri',
        _collector_contract: 'tauri-idle-v1',
        _collector_state: 'operational',
        _capability_sha256: capabilitySha256,
        _observed_at: new Date(deps.now()).toISOString(),
        _event_id: deps.randomUUID(),
      })
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
