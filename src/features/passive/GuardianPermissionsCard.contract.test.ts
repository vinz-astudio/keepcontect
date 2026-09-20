import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const harness = vi.hoisted(() => ({ platform: 'web', tauri: false, push: true, permission: 'default' }))
vi.mock('@capacitor/core', () => ({ Capacitor: {
  getPlatform: () => harness.platform, isNativePlatform: () => harness.platform !== 'web',
} }))
vi.mock('@/lib/platform', () => ({ isTauri: () => harness.tauri, isStandalone: () => true, getPlatform: () => harness.platform === 'web' ? 'desktop' : harness.platform }))
vi.mock('@/lib/i18n', () => ({ useI18n: () => ({ lang: 'zh', t: (key: string) => key }) }))
vi.mock('@/features/auth/AuthProvider', () => ({ useAuth: () => ({ user: null }) }))
vi.mock('@/lib/supabase', () => ({ supabase: {} }))
vi.mock('@/lib/toast', () => ({ toast: vi.fn() }))
vi.mock('./permissionRefresh', () => ({ watchPermissionRefresh: () => () => {} }))
vi.mock('./native', () => ({
  getNativeNotificationPermissionStatus: vi.fn(), getNativePermissionState: async () => 'unavailable',
  openNativeNotificationSettings: vi.fn(), openNativeAppSettings: vi.fn(), openUsageStatsSettings: vi.fn(),
  requestActivityRecognitionPermission: vi.fn(), requestBatteryExemption: vi.fn(), requestNativeNotificationPermission: vi.fn(),
  getGuardStatus: async () => null, syncNativeSensorPreferences: vi.fn(),
  getGuardMode: vi.fn(), enableHealthWake: vi.fn(), resolveGuardDemotion: vi.fn(),
  isUsageStatsEnabled: vi.fn(), openAutostartSettings: vi.fn(),
}))
vi.mock('@/features/push/pushApi', () => ({ enablePush: vi.fn(), pushSupported: () => harness.push }))
vi.stubGlobal('Notification', { get permission() { return harness.permission } })

import { GuardianPermissionsCard } from './GuardianPermissionsCard'
import { getGuardianPermissions } from './guardianPermissions'
import { PassiveSignalCard } from './PassiveSignalCard'

describe('device permission center', () => {
  beforeEach(() => { harness.platform = 'web'; harness.tauri = false; harness.push = true; harness.permission = 'default' })

  it.each([
    ['android', false, ['notifications', 'battery', 'motion', 'usage']],
    ['ios', false, ['notifications', 'motion', 'background-refresh']],
    ['web', false, ['notifications']],
    ['web', true, ['autostart']],
  ])('uses the permission list for %s (desktop=%s)', (platform, tauri, ids) => {
    harness.platform = platform; harness.tauri = tauri
    expect(getGuardianPermissions().map((permission) => permission.id)).toEqual(ids)
  })

  it('does not initially claim all permissions are granted', () => {
    const html = renderToStaticMarkup(createElement(GuardianPermissionsCard))
    expect(html).toContain('data-summary="checking"')
    expect(html).not.toContain('系统权限已全部就绪')
    expect(html).not.toContain('电脑鼠标键盘活跃')
    expect(html).not.toContain('运动状态活跃监测')
    expect(html).toContain('通知权限')
  })

  it('does not label native iOS binding as an OS permission or show Android controls', () => {
    harness.platform = 'ios'
    const html = renderToStaticMarkup(createElement(GuardianPermissionsCard))
    expect(html).not.toContain('iOS 后台守护')
    expect(html).not.toContain('使用情况访问')
    expect(html).toContain('运动与健身')
    expect(html).toContain('后台 App 刷新')
    expect(html).not.toContain('健康数据读取')
  })

  it('rereads web notification permission after revocation and keeps unsupported unknown', async () => {
    const notification = getGuardianPermissions()[0]
    expect(await notification.check()).toBe('prompt')
    harness.permission = 'granted'
    expect(await notification.check()).toBe('granted')
    harness.permission = 'denied'
    expect(await notification.check()).toBe('denied')
    harness.push = false
    expect(await notification.check()).toBe('unavailable')
  })

  it('does not include unqueryable health-read in iOS permissions', async () => {
    harness.platform = 'ios'
    expect(getGuardianPermissions().find((item) => item.id === 'health-read')).toBeUndefined()
    expect(await getGuardianPermissions().find((item) => item.id === 'motion')?.check()).toBe('unavailable')
  })

  it('keeps one set of collection controls in Me instead of a second stale copy below', () => {
    harness.platform = 'ios'
    const html = renderToStaticMarkup(createElement(PassiveSignalCard))
    expect(html).not.toContain('psig__sensor-row')
  })
})
