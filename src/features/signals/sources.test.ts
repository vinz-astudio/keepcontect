import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: () => false,
  },
}))

vi.mock('@/lib/platform', () => ({
  isTauri: () => false,
}))

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
