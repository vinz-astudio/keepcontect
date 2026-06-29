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

  it('opens the APK URL with Capacitor Browser on native mobile', async () => {
    const openCapacitorBrowser = vi.fn().mockResolvedValue(undefined)
    const openWindow = vi.fn()

    await launchUpdate(
      { apkUrl: 'https://example.com/app.apk' },
      {
        isTauri: () => false,
        isNativePlatform: () => true,
        getTauriInternals: () => null,
        openCapacitorBrowser,
        openWindow,
        reload: vi.fn(),
      },
    )

    expect(openCapacitorBrowser).toHaveBeenCalledWith('https://example.com/app.apk')
    expect(openWindow).not.toHaveBeenCalled()
  })

  it('reloads the web app when no native installer is needed', async () => {
    const reload = vi.fn()

    await launchUpdate(
      {},
      {
        isTauri: () => false,
        isNativePlatform: () => false,
        getTauriInternals: () => null,
        openCapacitorBrowser: vi.fn(),
        openWindow: vi.fn(),
        reload,
      },
    )

    expect(reload).toHaveBeenCalledOnce()
  })
})
