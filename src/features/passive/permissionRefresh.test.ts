import { beforeEach, describe, expect, it, vi } from 'vitest'
const harness = vi.hoisted(() => ({ add: vi.fn() }))
vi.mock('@capacitor/app', () => ({ App: { addListener: harness.add } }))
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => true } }))
import { watchPermissionRefresh } from './permissionRefresh'

describe('permission refresh lifecycle', () => {
  beforeEach(() => {
    vi.stubGlobal('window', new EventTarget())
    vi.stubGlobal('document', Object.assign(new EventTarget(), { visibilityState: 'visible' }))
    harness.add.mockReset()
  })

  it('refreshes on foreground and native resume, ignores hidden transitions, and cleans up', async () => {
    const refresh = vi.fn()
    const remove = vi.fn()
    harness.add.mockResolvedValue({ remove })
    const stop = watchPermissionRefresh(refresh)
    await Promise.resolve()
    window.dispatchEvent(new Event('focus'))
    Object.assign(document, { visibilityState: 'hidden' })
    document.dispatchEvent(new Event('visibilitychange'))
    const [event, handler] = harness.add.mock.calls[0]
    expect(event).toBe('appStateChange')
    handler({ isActive: false })
    handler({ isActive: true })
    expect(refresh).toHaveBeenCalledTimes(2)
    stop()
    Object.assign(document, { visibilityState: 'visible' })
    window.dispatchEvent(new Event('focus'))
    handler({ isActive: true })
    expect(refresh).toHaveBeenCalledTimes(2)
    expect(remove).toHaveBeenCalledOnce()
  })

  it('removes a native listener whose registration finishes after unmount', async () => {
    let finish!: (value: { remove: () => void }) => void
    harness.add.mockReturnValue(new Promise((resolve) => { finish = resolve }))
    const remove = vi.fn()
    const stop = watchPermissionRefresh(vi.fn())
    stop()
    finish({ remove })
    await Promise.resolve()
    expect(remove).toHaveBeenCalledOnce()
  })
})
