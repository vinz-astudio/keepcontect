import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  clearTauriPassiveEvidence,
  startTauriPassiveEvidence,
  type TauriEvidenceDeps,
  type TauriInputSample,
} from './shadowCoverage'

const sample = (
  lastInputAt: string,
  sampleTime = '2026-08-14T12:05:00.000Z',
): TauriInputSample => ({
  collectorContract: 'tauri-passive-evidence-v1',
  channel: 'tauri',
  probeAvailable: true,
  sampleTime,
  idleDurationMs: Date.parse(sampleTime) - Date.parse(lastInputAt),
  lastInputAt,
})

const values = new Map<string, string>()
const storage: Storage = {
  get length() { return values.size },
  clear: () => values.clear(),
  getItem: (key) => values.get(key) ?? null,
  key: (index) => [...values.keys()][index] ?? null,
  removeItem: (key) => { values.delete(key) },
  setItem: (key, value) => { values.set(key, value) },
}

function deps(overrides: Partial<TauriEvidenceDeps> = {}): TauriEvidenceDeps {
  return {
    isTauri: () => true,
    isNativePlatform: () => false,
    getUserId: vi.fn().mockResolvedValue('user-a'),
    getClientId: () => 'client-a',
    invokeInputSample: vi.fn().mockResolvedValue(sample('2026-08-14T12:04:00.000Z')),
    bind: vi.fn().mockResolvedValue({
      bindingId: '00000000-0000-4000-8000-000000000001',
      credential: 'c'.repeat(32),
      credentialVersion: 1,
      surfaceType: 'tauri_native',
      collectorContract: 'tauri-passive-evidence-v1',
    }),
    revoke: vi.fn().mockResolvedValue(true),
    sendEvidence: vi.fn().mockResolvedValue('inserted'),
    randomUUID: () => '00000000-0000-4000-8000-000000000002',
    now: () => Date.parse('2026-08-14T12:05:00.000Z'),
    storage,
    setInterval: globalThis.setInterval,
    clearInterval: globalThis.clearInterval,
    ...overrides,
  }
}

async function flush() {
  for (let i = 0; i < 8; i += 1) await Promise.resolve()
}

describe('Tauri reconstructed input evidence', () => {
  beforeEach(() => {
    storage.clear()
    vi.useFakeTimers()
  })

  it('uses the reconstructed occurrence time and closed direct-input facts', async () => {
    const d = deps()
    const stop = startTauriPassiveEvidence(d)
    await flush()
    expect(d.sendEvidence).toHaveBeenCalledWith(
      expect.objectContaining({ surfaceType: 'tauri_native' }),
      expect.objectContaining({
        observedAt: '2026-08-14T12:04:00.000Z',
        evidenceClass: 'direct_device_use',
        qualificationFacts: { interaction: true },
        queryStartedAt: '2026-08-14T12:04:00.000Z',
        queryEndedAt: '2026-08-14T12:05:00.000Z',
        querySucceeded: true,
      }),
    )
    expect(JSON.stringify((d.sendEvidence as ReturnType<typeof vi.fn>).mock.calls)).not.toMatch(/key|app|url|content/i)
    stop()
  })

  it('emits once until reconstructed last input advances', async () => {
    const invoke = vi.fn()
      .mockResolvedValueOnce(sample('2026-08-14T12:04:00.000Z'))
      .mockResolvedValueOnce(sample('2026-08-14T12:04:00.000Z'))
      .mockResolvedValue(sample('2026-08-14T12:09:00.000Z', '2026-08-14T12:10:00.000Z'))
    const d = deps({ invokeInputSample: invoke })
    const stop = startTauriPassiveEvidence(d)
    await flush()
    await vi.advanceTimersByTimeAsync(5 * 60_000)
    await flush()
    expect(d.sendEvidence).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(5 * 60_000)
    await flush()
    expect(d.sendEvidence).toHaveBeenCalledTimes(2)
    stop()
  })

  it('clears another account queue and never sends it as the current owner', async () => {
    storage.setItem('kc.tauriEvidence.ownerId', 'user-old')
    storage.setItem('kc.tauriEvidence.queue', JSON.stringify([{ ownerId: 'user-old' }]))
    const d = deps()
    const stop = startTauriPassiveEvidence(d)
    await flush()
    expect(storage.getItem('kc.tauriEvidence.queue')).not.toContain('user-old')
    expect(d.sendEvidence).toHaveBeenCalledTimes(1)
    stop()
  })

  it('rejects future or mismatched-channel samples', async () => {
    for (const invalid of [
      { ...sample('2026-08-14T12:06:00.000Z') },
      { ...sample('2026-08-14T12:04:00.000Z'), channel: 'browser' },
    ]) {
      const d = deps({ invokeInputSample: vi.fn().mockResolvedValue(invalid) })
      const stop = startTauriPassiveEvidence(d)
      await flush()
      expect(d.sendEvidence).not.toHaveBeenCalled()
      stop()
      storage.clear()
    }
  })

  it('revokes and clears binding, sequence and queue before sign-out', async () => {
    storage.setItem('kc.tauriEvidence.ownerId', 'user-a')
    storage.setItem('kc.tauriEvidence.bindingId', '00000000-0000-4000-8000-000000000001')
    storage.setItem('kc.tauriEvidence.sequence', '4')
    storage.setItem('kc.tauriEvidence.queue', '[{"ownerId":"user-a"}]')
    const revoke = vi.fn().mockResolvedValue(true)

    await clearTauriPassiveEvidence({ isTauri: () => true, storage, revoke })

    expect(revoke).toHaveBeenCalledWith('00000000-0000-4000-8000-000000000001')
    expect(storage.getItem('kc.tauriEvidence.ownerId')).toBeNull()
    expect(storage.getItem('kc.tauriEvidence.sequence')).toBeNull()
    expect(storage.getItem('kc.tauriEvidence.queue')).toBeNull()
  })
})
