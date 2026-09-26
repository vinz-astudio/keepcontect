import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { startTauriPassiveEvidence, type TauriEvidenceDeps } from './shadowCoverage'
import type { PassiveCollectorBinding, PassiveEvidenceDraft } from './evidenceContract'

const binding: PassiveCollectorBinding = { bindingId: 'binding-a', credential: 'c'.repeat(32), credentialVersion: 2, surfaceType: 'tauri_native', collectorContract: 'tauri-passive-evidence-v1' }
const draft: PassiveEvidenceDraft = { eventId: 'offline-event', sequence: 7, observedAt: '2026-09-24T06:00:00.000Z', evidenceClass: 'direct_device_use', correlationId: null, qualificationFacts: { interaction: true }, queryStartedAt: '2026-09-24T06:00:00.000Z', queryEndedAt: '2026-09-24T06:01:00.000Z', querySucceeded: true }
const values = new Map<string, string>()
const storage: Storage = { get length() { return values.size }, clear: () => values.clear(), getItem: k => values.get(k) ?? null, key: i => [...values.keys()][i] ?? null, removeItem: k => { values.delete(k) }, setItem: (k,v) => { values.set(k,v) } }
const settle = async () => { for (let i=0; i<30; i++) await Promise.resolve() }
function setup(overrides: Partial<TauriEvidenceDeps> = {}) {
  const sent: PassiveEvidenceDraft[] = []
  const d: TauriEvidenceDeps = {
    isTauri: () => true, isNativePlatform: () => false, getUserId: async () => 'user-a', getClientId: () => 'client-a',
    bind: vi.fn(async () => binding), resume: vi.fn(async () => ({ ...binding, nextSequence: 8 })), revoke: vi.fn(async () => true),
    invokeInputSample: async () => null,
    sendEvidence: async (_binding, event) => { sent.push(structuredClone(event)); return 'inserted' },
    randomUUID: () => 'new-event', now: () => Date.now(), storage,
    setInterval: globalThis.setInterval, clearInterval: globalThis.clearInterval,
    ...overrides,
  }
  return { d, sent }
}
function seed() {
  storage.setItem('kc.tauriEvidence.ownerId', 'user-a')
  storage.setItem('kc.tauriEvidence.bindingId', binding.bindingId)
  storage.setItem('kc.tauriEvidence.sequence', '7')
  storage.setItem('kc.tauriEvidence.queue', JSON.stringify([{ ownerId: 'user-a', bindingId: binding.bindingId, draft }]))
}
beforeEach(() => { values.clear(); vi.useFakeTimers(); vi.setSystemTime(Date.parse('2026-09-24T06:01:00.000Z')) })
afterEach(() => { vi.useRealTimers() })
describe('Tauri recovery', () => {
  it.each(['auth', 'bind'])('recovers after initial %s network failure without restarting', async (failure) => {
    seed()
    if (failure === 'bind') { storage.removeItem('kc.tauriEvidence.bindingId'); storage.setItem('kc.tauriEvidence.queue', '[]') }
    let online = false
    const { d, sent } = setup({
      getUserId: async () => { if (!online && failure === 'auth') throw Error('offline'); return 'user-a' },
      bind: async () => { if (!online) throw Error('offline'); return binding },
      invokeInputSample: async () => ({ collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true, sampleTime: '2026-09-24T06:01:00.000Z', lastInputAt: '2026-09-24T06:00:30.000Z', idleDurationMs: 30_000 }),
    })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    online = true
    await vi.advanceTimersByTimeAsync(60_000)
    stop()
    expect(sent.length).toBeGreaterThan(0)
  })

  it('resumes the same owner binding and sends the queued event unchanged', async () => {
    seed()
    const { d, sent } = setup()
    const stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    expect(sent).toEqual([draft])
    expect(d.bind).not.toHaveBeenCalled()
    expect(d.revoke).not.toHaveBeenCalled()
    expect(storage.getItem('kc.tauriEvidence.sequence')).toBe('7')
  })

  it('preserves an offline queue when resume fails and sends on an online wake', async () => {
    seed()
    let wake!: () => void
    let online = false
    const { d, sent } = setup({ resume: async () => { if (!online) throw Error('offline'); return binding }, subscribeWake: callback => { wake = callback; return () => {} } })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    expect(JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)[0].draft).toEqual(draft)
    online = true
    wake()
    await settle()
    stop()
    expect(sent).toEqual([draft])
  })

  it('does not auto-bind a revoked collector across retries or restart', async () => {
    seed()
    const { d, sent } = setup({ resume: async () => { throw { code: '55000', message: 'passive collector is revoked or unavailable' } } })
    let stop = startTauriPassiveEvidence(d)
    await settle()
    await vi.advanceTimersByTimeAsync(10 * 60_000)
    stop()
    stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    expect(sent).toEqual([])
    expect(d.bind).not.toHaveBeenCalled()
  })

  it('discards a pending old-owner bind callback after an account switch', async () => {
    let owner = 'user-a'
    let changed!: (owner: string | null) => void
    let resolve!: (value: PassiveCollectorBinding) => void
    const { d, sent } = setup({
      getUserId: async () => owner,
      subscribeOwner: callback => { changed = callback; return () => {} },
      bind: vi.fn().mockImplementationOnce(() => new Promise(done => { resolve = done })).mockResolvedValue({ ...binding, bindingId: 'binding-b' }),
    })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    owner = 'user-b'
    changed(owner)
    resolve(binding)
    await settle()
    stop()
    expect(sent).toEqual([])
    expect(storage.getItem('kc.tauriEvidence.ownerId')).toBe('user-b')
    expect(storage.getItem('kc.tauriEvidence.bindingId')).toBe('binding-b')
  })

  it('keeps collecting original input times while a queued upload is offline', async () => {
    seed()
    const { d } = setup({
      sendEvidence: async () => { throw Error('offline') },
      invokeInputSample: async () => ({ collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true, sampleTime: '2026-09-24T06:01:00.000Z', lastInputAt: '2026-09-24T06:00:30.000Z', idleDurationMs: 30_000 }),
    })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    const queue = JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)
    expect(queue.map((item: { draft: PassiveEvidenceDraft }) => item.draft.observedAt)).toEqual([draft.observedAt, '2026-09-24T06:00:30.000Z'])
    expect(queue[1].draft.sequence).toBe(8)
    expect([...values.values()].join('')).not.toContain(binding.credential)
  })

  it('a late old-account upload result cannot replace the new account queue', async () => {
    seed()
    let owner = 'user-a'
    let changed!: (owner: string | null) => void
    let resolve!: (status: string) => void
    const { d } = setup({
      getUserId: async () => owner,
      subscribeOwner: callback => { changed = callback; return () => {} },
      sendEvidence: () => new Promise(done => { resolve = done }),
      bind: async () => ({ ...binding, bindingId: 'binding-b' }),
    })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    owner = 'user-b'
    changed(owner)
    await settle()
    const newQueue = [{ ownerId: owner, bindingId: 'binding-b', draft: { ...draft, eventId: 'b-event' } }]
    storage.setItem('kc.tauriEvidence.queue', JSON.stringify(newQueue))
    resolve('inserted')
    await settle()
    stop()
    expect(JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)).toEqual(newQueue)
    expect(storage.getItem('kc.tauriEvidence.bindingId')).toBe('binding-b')
  })

  it('only explicit disable then enable can replace a revoked binding', async () => {
    seed()
    let enabled = true
    let wake!: () => void
    const { d } = setup({
      resume: async () => { throw { code: '55000' } },
      bind: vi.fn(async () => ({ ...binding, bindingId: 'explicit-new-binding' })),
      isCollectionEnabled: () => enabled,
      subscribeWake: callback => { wake = callback; return () => {} },
    })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    wake()
    await settle()
    expect(d.bind).not.toHaveBeenCalled()
    enabled = false
    wake()
    enabled = true
    wake()
    await settle()
    stop()
    expect(d.bind).toHaveBeenCalledTimes(1)
    expect(storage.getItem('kc.tauriEvidence.bindingId')).toBe('explicit-new-binding')
    expect(JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)[0].draft).toEqual(draft)
  })

  it('does not manufacture a new input when the clock changes but native identity does not', async () => {
    const { d, sent } = setup({ invokeInputSample: async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTime: new Date(Date.now()).toISOString(), lastInputAt: new Date(Date.now() - 60_000).toISOString(),
      idleDurationMs: 60_000, inputIdentity: 'windows:1234',
    }) })
    let stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    vi.setSystemTime(Date.now() + 3_600_000)
    stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    expect(sent).toHaveLength(1)
  })

  it('deduplicates macOS monotonic input jitter across clock jumps, sleep, and restart', async () => {
    let identity = 'macos:boot-a:120000:160000'
    const { d, sent } = setup({ invokeInputSample: async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTime: new Date(Date.now()).toISOString(), lastInputAt: new Date(Date.now() - 60_000).toISOString(),
      idleDurationMs: 60_000, inputIdentity: identity,
    }) })
    let stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    vi.setSystemTime(Date.now() + 3_600_000)
    identity = 'macos:boot-a:120016:160016'
    stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    identity = 'macos:boot-a:-3479984:160016'
    stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    expect(sent).toHaveLength(1)
    vi.setSystemTime(Date.now() + 60_000)
    identity = 'macos:boot-a:200000:3840000'
    stop = startTauriPassiveEvidence(d)
    await settle()
    stop()
    expect(sent).toHaveLength(2)
  })

  it('times out a hung upload, preserves its event, and recovers on a later tick', async () => {
    seed()
    const signals: AbortSignal[] = []
    let resolveLate!: (status: string) => void
    const send = vi.fn().mockImplementationOnce((_binding, _draft, signal) => {
      signals.push(signal)
      return new Promise(done => { resolveLate = done })
    }).mockResolvedValue('inserted')
    const { d } = setup({ sendEvidence: send })
    const stop = startTauriPassiveEvidence(d)
    await settle()
    await vi.advanceTimersByTimeAsync(15_000)
    expect(JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)[0].draft).toEqual(draft)
    expect(signals[0].aborted).toBe(true)
    await vi.advanceTimersByTimeAsync(45_000)
    expect(send).toHaveBeenCalledTimes(2)
    expect(JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)).toEqual([])
    const later = [{ ownerId: 'user-a', bindingId: binding.bindingId, draft: { ...draft, eventId: 'later' } }]
    storage.setItem('kc.tauriEvidence.queue', JSON.stringify(later))
    resolveLate('inserted')
    await settle()
    expect(JSON.parse(storage.getItem('kc.tauriEvidence.queue')!)).toEqual(later)
    d.invokeInputSample = async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTime: new Date(Date.now()).toISOString(), lastInputAt: new Date(Date.now() - 30_000).toISOString(),
      idleDurationMs: 30_000, inputIdentity: 'windows:5678',
    })
    await vi.advanceTimersByTimeAsync(5 * 60_000)
    expect(send.mock.calls.some((call) => call[1].eventId === 'new-event')).toBe(true)
    stop()
  })
})
