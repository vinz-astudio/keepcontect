import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  startTauriShadowCoverage,
  type ShadowCoverageDeps,
  type TauriCoverageCapability,
} from './shadowCoverage'

const operational: TauriCoverageCapability = {
  collectorContract: 'tauri-idle-v1',
  collectorState: 'operational',
  idleProbeAvailable: true,
  appVersion: '0.5.20',
  channel: 'tauri',
}

function makeDeps(
  overrides: Partial<ShadowCoverageDeps> = {},
): ShadowCoverageDeps {
  return {
    isTauri: () => true,
    isNativePlatform: () => false,
    invokeCapability: vi.fn().mockResolvedValue(operational),
    recordLease: vi.fn().mockResolvedValue({ error: null, data: 'inserted' }),
    getClientId: () => 'client-001',
    now: () => Date.parse('2026-07-27T10:00:00.000Z'),
    randomUUID: () => '00000000-0000-4000-8000-000000000001',
    hashCanonical: vi.fn().mockResolvedValue('a'.repeat(64)),
    setInterval: globalThis.setInterval,
    clearInterval: globalThis.clearInterval,
    ...overrides,
  }
}

async function flush(): Promise<void> {
  await Promise.resolve()
  await Promise.resolve()
  await Promise.resolve()
}

describe('startTauriShadowCoverage', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  it.each([
    ['plain browser', false, false],
    ['Capacitor Android', true, true],
  ])('%s never invokes Tauri or submits a lease', async (_name, tauri, native) => {
    const deps = makeDeps({
      isTauri: () => tauri,
      isNativePlatform: () => native,
    })
    const stop = startTauriShadowCoverage(deps)
    await flush()
    expect(deps.invokeCapability).not.toHaveBeenCalled()
    expect(deps.recordLease).not.toHaveBeenCalled()
    stop()
  })

  it('unavailable native capability sends nothing', async () => {
    const deps = makeDeps({
      invokeCapability: vi.fn().mockResolvedValue({
        ...operational,
        collectorState: 'unavailable',
        idleProbeAvailable: false,
      }),
    })
    const stop = startTauriShadowCoverage(deps)
    await flush()
    expect(deps.invokeCapability).toHaveBeenCalledOnce()
    expect(deps.recordLease).not.toHaveBeenCalled()
    stop()
  })

  it('sends immediately and every five minutes with exact RPC arguments', async () => {
    const deps = makeDeps()
    const stop = startTauriShadowCoverage(deps)
    await flush()
    expect(deps.recordLease).toHaveBeenCalledTimes(1)
    expect(deps.hashCanonical).toHaveBeenCalledWith(
      '{"appVersion":"0.5.20","channel":"tauri","collectorContract":"tauri-idle-v1","idleProbeAvailable":true}',
    )
    expect(deps.recordLease).toHaveBeenLastCalledWith({
      _client_id: 'client-001',
      _channel: 'tauri',
      _collector_contract: 'tauri-idle-v1',
      _collector_state: 'operational',
      _capability_sha256: 'a'.repeat(64),
      _observed_at: '2026-07-27T10:00:00.000Z',
      _event_id: '00000000-0000-4000-8000-000000000001',
    })
    await vi.advanceTimersByTimeAsync(5 * 60_000)
    await flush()
    expect(deps.recordLease).toHaveBeenCalledTimes(2)
    stop()
  })

  it('does not overlap requests and cleanup cancels future ticks', async () => {
    let resolveCapability!: (value: TauriCoverageCapability) => void
    const deps = makeDeps({
      invokeCapability: vi.fn().mockImplementation(
        () => new Promise<TauriCoverageCapability>((resolve) => {
          resolveCapability = resolve
        }),
      ),
    })
    const stop = startTauriShadowCoverage(deps)
    await vi.advanceTimersByTimeAsync(10 * 60_000)
    expect(deps.invokeCapability).toHaveBeenCalledTimes(1)
    resolveCapability(operational)
    await flush()
    expect(deps.recordLease).toHaveBeenCalledTimes(1)
    stop()
    await vi.advanceTimersByTimeAsync(10 * 60_000)
    expect(deps.invokeCapability).toHaveBeenCalledTimes(1)
  })

  it('RPC errors wait for the next normal tick', async () => {
    const recordLease = vi
      .fn()
      .mockResolvedValueOnce({ error: new Error('offline') })
      .mockResolvedValue({ error: null, data: 'inserted' })
    const deps = makeDeps({ recordLease })
    const stop = startTauriShadowCoverage(deps)
    await flush()
    expect(recordLease).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(4 * 60_000)
    expect(recordLease).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(60_000)
    await flush()
    expect(recordLease).toHaveBeenCalledTimes(2)
    stop()
  })

  it('surfaces a refusal the RPC reports in its return value, not as an error', async () => {
    // capability_mismatch 曾让桌面壳连续 7 天每 5 分钟被拒一次而无人察觉:
    // RPC 不报 error,只在返回值里说"不收",客户端从不读它。
    const consoleError = vi
      .spyOn(console, 'error')
      .mockImplementation(() => {})
    const deps = makeDeps({
      recordLease: vi
        .fn()
        .mockResolvedValue({ error: null, data: 'capability_mismatch' }),
    })
    const stop = startTauriShadowCoverage(deps)
    await flush()
    expect(consoleError).toHaveBeenCalledWith(
      '[coverage] shadow lease refused:',
      'capability_mismatch',
    )
    stop()
    consoleError.mockRestore()
  })

  it('stays quiet when the server accepts, dedupes, or is switched off', async () => {
    const consoleError = vi
      .spyOn(console, 'error')
      .mockImplementation(() => {})
    for (const outcome of ['inserted', 'duplicate', 'disabled']) {
      const deps = makeDeps({
        recordLease: vi.fn().mockResolvedValue({ error: null, data: outcome }),
      })
      const stop = startTauriShadowCoverage(deps)
      await flush()
      stop()
    }
    expect(consoleError).not.toHaveBeenCalled()
    consoleError.mockRestore()
  })
})
