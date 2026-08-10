import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const platform = vi.hoisted(() => ({
  getPlatform: vi.fn(() => 'desktop' as 'ios' | 'android' | 'desktop'),
  isStandalone: vi.fn(() => false),
  isTauri: vi.fn(() => false),
}))

const capacitor = vi.hoisted(() => ({
  isNativePlatform: vi.fn(() => false),
}))

vi.mock('@/lib/platform', () => platform)
vi.mock('@capacitor/core', () => ({ Capacitor: capacitor }))
vi.mock('@/lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))

const { clientChannel } = await import('@/lib/clientReport')

beforeEach(() => {
  platform.getPlatform.mockReturnValue('desktop')
  platform.isStandalone.mockReturnValue(false)
  platform.isTauri.mockReturnValue(false)
  capacitor.isNativePlatform.mockReturnValue(false)
})

afterEach(() => {
  vi.clearAllMocks()
})

describe('clientChannel', () => {
  it('reports the desktop native shell as tauri, not as a browser tab', () => {
    // 服务端 record_alert_shadow_coverage_lease 只在 clients.platform = 'tauri'
    // 时才收桌面覆盖凭据;报成 desktop-web 会被静默判为 capability_mismatch。
    platform.isTauri.mockReturnValue(true)
    expect(clientChannel()).toBe('tauri')
  })

  it('prefers tauri over the standalone/display-mode heuristic', () => {
    // Tauri 的 WebView 在部分平台上会命中 display-mode: standalone。
    platform.isTauri.mockReturnValue(true)
    platform.isStandalone.mockReturnValue(true)
    expect(clientChannel()).toBe('tauri')
  })

  it('keeps the existing channel names for every non-Tauri client', () => {
    expect(clientChannel()).toBe('desktop-web')

    platform.isStandalone.mockReturnValue(true)
    platform.getPlatform.mockReturnValue('ios')
    expect(clientChannel()).toBe('ios-pwa')

    platform.isStandalone.mockReturnValue(false)
    capacitor.isNativePlatform.mockReturnValue(true)
    expect(clientChannel()).toBe('ios-app')

    platform.getPlatform.mockReturnValue('android')
    expect(clientChannel()).toBe('android-apk')
  })
})
