import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: () => false,
  },
}))

const platform = vi.hoisted(() => ({ tauri: false }))
vi.mock('@/lib/platform', () => ({ isTauri: () => platform.tauri }))
const tray = vi.hoisted(() => ({ listen: vi.fn() }))
vi.mock('@tauri-apps/api/event', () => ({ listen: tray.listen }))

vi.mock('@/features/signals/sensors', () => ({
  isSensorEnabled: () => true,
}))

import { startSignalSources } from '@/features/signals/sources'

describe('web interaction signal source', () => {
  let windowTarget: EventTarget
  let documentTarget: EventTarget & { visibilityState: DocumentVisibilityState }

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(1_000_000)

    windowTarget = new EventTarget()
    documentTarget = Object.assign(new EventTarget(), {
      visibilityState: 'visible' as DocumentVisibilityState,
    })

    vi.stubGlobal('window', windowTarget)
    vi.stubGlobal('document', documentTarget)
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('bounds repeated interaction activity to one ping per five minutes and removes its listeners', () => {
    const record = vi.fn()
    const stop = startSignalSources(record)

    expect(record).toHaveBeenCalledTimes(1)
    expect(record).toHaveBeenLastCalledWith('interaction')

    windowTarget.dispatchEvent(new Event('pointerdown'))
    windowTarget.dispatchEvent(new Event('focus'))
    expect(record).toHaveBeenCalledTimes(1)

    vi.advanceTimersByTime(5 * 60_000 - 1)
    windowTarget.dispatchEvent(new Event('pointerdown'))
    expect(record).toHaveBeenCalledTimes(1)

    vi.advanceTimersByTime(1)
    windowTarget.dispatchEvent(new Event('focus'))
    expect(record).toHaveBeenCalledTimes(2)
    expect(record).toHaveBeenLastCalledWith('interaction')

    stop()
    vi.advanceTimersByTime(5 * 60_000)
    windowTarget.dispatchEvent(new Event('pointerdown'))
    windowTarget.dispatchEvent(new Event('focus'))
    expect(record).toHaveBeenCalledTimes(2)
  })
})


describe('Tauri input occurrence and tray lifecycle', () => {
  const values = new Map<string, string>()
  let target: EventTarget & { __TAURI_INTERNALS__: { invoke: ReturnType<typeof vi.fn> } }
  const input = 1_000_000
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(input + 60_000)
    platform.tauri = true
    values.clear()
    vi.stubGlobal('localStorage', { getItem: (k: string) => values.get(k) ?? null, setItem: (k: string, v: string) => values.set(k, v) })
    target = Object.assign(new EventTarget(), { __TAURI_INTERNALS__: { invoke: vi.fn(async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTimeMs: Date.now(), idleDurationMs: Date.now() - input, lastInputAtMs: input,
    })) } })
    vi.stubGlobal('window', target)
    vi.stubGlobal('document', Object.assign(new EventTarget(), { visibilityState: 'hidden' }))
    tray.listen.mockReset().mockResolvedValue(vi.fn())
  })
  afterEach(() => { platform.tauri = false; vi.useRealTimers(); vi.unstubAllGlobals() })

  it('records the actual input once across idle polls and restart jitter', async () => {
    const events: Array<[string, number | undefined]> = []
    let stop = startSignalSources((kind, at) => events.push([kind, at]), 'user-a')
    await vi.advanceTimersByTimeAsync(8 * 60_000)
    stop()
    expect(events).toEqual([['interaction', input]])
    target.__TAURI_INTERNALS__.invoke.mockImplementation(async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTimeMs: Date.now(), idleDurationMs: Date.now() - input - 16, lastInputAtMs: input + 16,
    }))
    stop = startSignalSources((kind, at) => events.push([kind, at]), 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    stop()
    expect(events).toEqual([['interaction', input]])
  })

  it('releases a tray listener that resolves after stop and ignores late callbacks', async () => {
    let resolve!: (value: () => void) => void
    tray.listen.mockImplementation(() => new Promise<() => void>((done) => { resolve = done }))
    const events: string[] = []
    const stop = startSignalSources((kind) => events.push(kind), 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    stop()
    const unlisten = vi.fn()
    expect(tray.listen).toHaveBeenCalledWith('tray-checkin', expect.any(Function))
    resolve(unlisten)
    await vi.advanceTimersByTimeAsync(0)
    tray.listen.mock.calls[0][1]({ payload: null })
    expect(unlisten).toHaveBeenCalledTimes(1)
    expect(events).not.toContain('manual_checkin')
  })

  it('does not replay the same native input after the wall clock advances', async () => {
    const record = vi.fn()
    target.__TAURI_INTERNALS__.invoke.mockImplementation(async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTimeMs: Date.now(), idleDurationMs: 60_000, lastInputAtMs: Date.now() - 60_000,
      inputIdentity: 'windows:1234',
    }))
    let stop = startSignalSources(record, 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    stop()
    vi.setSystemTime(Date.now() + 3_600_000)
    stop = startSignalSources(record, 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    stop()
    expect(record).toHaveBeenCalledTimes(1)
  })

  it('records a later real input at its occurrence time and a tray click as explicit check-in', async () => {
    const record = vi.fn()
    const stop = startSignalSources(record, 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    const nextInput = Date.now() + 90_000
    target.__TAURI_INTERNALS__.invoke.mockImplementation(async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTimeMs: Date.now(), idleDurationMs: Date.now() - nextInput, lastInputAtMs: nextInput,
    }))
    await vi.advanceTimersByTimeAsync(2 * 60_000)
    expect(record).toHaveBeenNthCalledWith(2, 'interaction', nextInput)
    tray.listen.mock.calls[0][1]({ payload: null })
    expect(record).toHaveBeenLastCalledWith('manual_checkin')
    stop()
  })

  it('deduplicates macOS monotonic identity jitter after a clock jump and restart', async () => {
    let identity = 'macos:boot-a:120000:160000'
    const record = vi.fn()
    target.__TAURI_INTERNALS__.invoke.mockImplementation(async () => ({
      collectorContract: 'tauri-passive-evidence-v1', channel: 'tauri', probeAvailable: true,
      sampleTimeMs: Date.now(), idleDurationMs: 60_000, lastInputAtMs: Date.now() - 60_000,
      inputIdentity: identity,
    }))
    let stop = startSignalSources(record, 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    stop()
    vi.setSystemTime(Date.now() + 3_600_000)
    identity = 'macos:boot-a:120016:160016'
    stop = startSignalSources(record, 'user-a')
    await vi.advanceTimersByTimeAsync(0)
    stop()
    expect(record).toHaveBeenCalledTimes(1)
  })
})
