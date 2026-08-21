import { describe, expect, it } from 'vitest'
import { clientPlatformKind, clientPlatformLabel } from '@/lib/clientPlatformLabel'

// 生产库 clients.platform 里实际出现过的全部取值。
const PRODUCTION_CHANNELS = [
  'tauri',
  'android-apk',
  'ios-app',
  'ios-pwa',
  'desktop-web',
  'ios-web',
  'android-web',
]

describe('clientPlatformKind', () => {
  it('把桌面原生壳认成 native,它没有 - 后缀', () => {
    expect(clientPlatformKind('tauri')).toBe('native')
  })

  it('从后缀读运行形态', () => {
    expect(clientPlatformKind('android-apk')).toBe('apk')
    expect(clientPlatformKind('ios-app')).toBe('app')
    expect(clientPlatformKind('ios-pwa')).toBe('pwa')
    expect(clientPlatformKind('desktop-web')).toBe('web')
  })

  it('对空值和未知渠道返回 unknown,不猜', () => {
    expect(clientPlatformKind(null)).toBe('unknown')
    expect(clientPlatformKind(undefined)).toBe('unknown')
    expect(clientPlatformKind('')).toBe('unknown')
    expect(clientPlatformKind('watchos-widget')).toBe('unknown')
  })

  it('三个 *-web 都是 web,GMScreen 靠这个把浏览器排除出被动监护', () => {
    expect(clientPlatformKind('desktop-web')).toBe('web')
    expect(clientPlatformKind('ios-web')).toBe('web')
    expect(clientPlatformKind('android-web')).toBe('web')
  })
})

describe('clientPlatformLabel', () => {
  it('桌面原生壳不写死 Windows —— 存储值里没有操作系统', () => {
    expect(clientPlatformLabel('tauri', 'zh')).toBe('桌面 App')
    expect(clientPlatformLabel('tauri', 'en')).toBe('Desktop App')
  })

  it('浏览器访问一律叫网页版,不带操作系统前缀', () => {
    for (const p of ['desktop-web', 'ios-web', 'android-web']) {
      expect(clientPlatformLabel(p, 'zh')).toBe('网页版')
      expect(clientPlatformLabel(p, 'en')).toBe('Web')
    }
  })

  it('原生客户端保留操作系统', () => {
    expect(clientPlatformLabel('android-apk', 'zh')).toBe('Android APK')
    expect(clientPlatformLabel('ios-app', 'zh')).toBe('iOS App')
    expect(clientPlatformLabel('ios-pwa', 'en')).toBe('iOS PWA')
  })

  it('未知渠道返回 null,调用方不得编造设备类型', () => {
    expect(clientPlatformLabel(null, 'zh')).toBeNull()
    expect(clientPlatformLabel('watchos-widget', 'zh')).toBeNull()
    // 旧代码里 'android' / 'ios' 这两个裸值是死分支:clientChannel() 从不产出。
    expect(clientPlatformLabel('android', 'zh')).toBeNull()
  })

  it('未知语言回落英文,不返回 undefined', () => {
    expect(clientPlatformLabel('ios-app', 'ja')).toBe('iOS App')
    expect(clientPlatformLabel('tauri', 'ja')).toBe('Desktop App')
  })

  it('生产库里出现过的每个渠道都有标签', () => {
    for (const p of PRODUCTION_CHANNELS) {
      expect(clientPlatformLabel(p, 'zh'), p).not.toBeNull()
      expect(clientPlatformLabel(p, 'en'), p).not.toBeNull()
    }
  })

  it('桌面浏览器和桌面原生壳的标签不再撞概念', () => {
    expect(clientPlatformLabel('desktop-web', 'zh')).not.toBe(
      clientPlatformLabel('tauri', 'zh'),
    )
    expect(clientPlatformLabel('desktop-web', 'zh')).not.toContain('桌面')
  })
})
