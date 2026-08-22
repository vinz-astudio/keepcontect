import { describe, expect, it, vi } from 'vitest'
import { launchUpdate } from '@/features/update/launchUpdate'

describe('launchUpdate', () => {
  it('uses the native desktop installer command when running in Tauri', async () => {
    const invoke = vi.fn().mockResolvedValue(undefined)
    const reload = vi.fn()
    const openWindow = vi.fn()

    await launchUpdate(
      { exeUrl: 'https://example.com/setup.exe', apkUrl: 'https://example.com/app.apk' },
      {
        isTauri: () => true,
        isNativePlatform: () => false,
        getTauriInternals: () => ({ invoke }),
        openExternalBrowser: vi.fn(),
        openCapacitorBrowser: vi.fn(),
        openWindow,
        reload,
      },
    )

    expect(invoke).toHaveBeenCalledWith('download_and_install', {
      url: 'https://example.com/setup.exe',
    })
    expect(openWindow).not.toHaveBeenCalled()
    expect(reload).not.toHaveBeenCalled()
  })

  it('falls back to opening the desktop installer URL when Tauri install fails', async () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const invoke = vi.fn()
      .mockRejectedValueOnce(new Error('download failed'))
      .mockResolvedValueOnce(undefined)
    const openWindow = vi.fn()

    await launchUpdate(
      { exeUrl: 'https://example.com/setup.exe' },
      {
        isTauri: () => true,
        isNativePlatform: () => false,
        getTauriInternals: () => ({ invoke }),
        openExternalBrowser: vi.fn(),
        openCapacitorBrowser: vi.fn(),
        openWindow,
        reload: vi.fn(),
      },
    )

    try {
      expect(invoke).toHaveBeenNthCalledWith(2, 'open_in_browser', {
        url: 'https://example.com/setup.exe',
      })
      expect(openWindow).not.toHaveBeenCalled()
    } finally {
      errorSpy.mockRestore()
    }
  })

  it('hands the APK to the real browser, not to an in-app tab', async () => {
    // A Custom Tab download has no owner the system will let install it: the
    // file lands and nothing offers to open it, which is how the update died
    // silently on 0.6.0.
    const openExternalBrowser = vi.fn().mockResolvedValue(undefined)
    const openCapacitorBrowser = vi.fn()
    const openWindow = vi.fn()

    await launchUpdate(
      { apkUrl: 'https://example.com/app.apk' },
      {
        isTauri: () => false,
        isNativePlatform: () => true,
        getTauriInternals: () => null,
        openExternalBrowser,
        openCapacitorBrowser,
        openWindow,
        reload: vi.fn(),
      },
    )

    expect(openExternalBrowser).toHaveBeenCalledWith('https://example.com/app.apk')
    expect(openCapacitorBrowser).not.toHaveBeenCalled()
    expect(openWindow).not.toHaveBeenCalled()
  })

  it('falls back to the in-app tab where no external bridge exists', async () => {
    const openCapacitorBrowser = vi.fn().mockResolvedValue(undefined)
    const openWindow = vi.fn()

    await launchUpdate(
      { apkUrl: 'https://example.com/app.apk' },
      {
        isTauri: () => false,
        isNativePlatform: () => true,
        getTauriInternals: () => null,
        openExternalBrowser: vi.fn().mockRejectedValue(new Error('no bridge')),
        openCapacitorBrowser,
        openWindow,
        reload: vi.fn(),
      },
    )

    expect(openCapacitorBrowser).toHaveBeenCalledWith('https://example.com/app.apk')
    expect(openWindow).not.toHaveBeenCalled()
  })

  it('reloads or opens TestFlight on iOS Native and never downloads APK', async () => {
    const openExternalBrowser = vi.fn().mockResolvedValue(undefined)
    const openCapacitorBrowser = vi.fn()
    const reload = vi.fn()

    // Without custom iOS URL, iOS native reloads rather than downloading APK
    await launchUpdate(
      { apkUrl: 'https://example.com/app.apk' },
      {
        isTauri: () => false,
        isNativePlatform: () => true,
        getNativePlatform: () => 'ios',
        getTauriInternals: () => null,
        openExternalBrowser,
        openCapacitorBrowser,
        openWindow: vi.fn(),
        reload,
      },
    )

    expect(openExternalBrowser).toHaveBeenCalledWith('https://testflight.apple.com')
    expect(openCapacitorBrowser).not.toHaveBeenCalled()
    expect(reload).not.toHaveBeenCalled()



    // With custom iOS URL, opens iOS URL
    const openIosExternal = vi.fn().mockResolvedValue(undefined)
    await launchUpdate(
      { apkUrl: 'https://example.com/app.apk', iosUrl: 'https://testflight.apple.com/join/xyz' },
      {
        isTauri: () => false,
        isNativePlatform: () => true,
        getNativePlatform: () => 'ios',
        getTauriInternals: () => null,
        openExternalBrowser: openIosExternal,
        openCapacitorBrowser: vi.fn(),
        openWindow: vi.fn(),
        reload: vi.fn(),
      },
    )

    expect(openIosExternal).toHaveBeenCalledWith('https://testflight.apple.com/join/xyz')
  })

  it('reloads the web app when no native installer is needed', async () => {
    const reload = vi.fn()

    await launchUpdate(
      {},
      {
        isTauri: () => false,
        isNativePlatform: () => false,
        getTauriInternals: () => null,
        openExternalBrowser: vi.fn(),
        openCapacitorBrowser: vi.fn(),
        openWindow: vi.fn(),
        reload,
      },
    )

    expect(reload).toHaveBeenCalledOnce()
  })
})
