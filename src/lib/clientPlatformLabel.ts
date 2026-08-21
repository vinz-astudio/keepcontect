// clients.platform 的展示层。存储值由 clientChannel() 生成,是服务端契约的一部分
// (record_alert_shadow_coverage_lease 硬校验 platform = 'tauri' / 'android-apk'),
// 所以这里只做"原始值 -> 人话"的单向映射,绝不反过来改存储值。
//
// 渠道形如 {ios|android|desktop}-{pwa|app|apk|web},外加无后缀的 tauri。
import type { Lang } from '@/lib/i18n'

/** 客户端的运行形态。'native' 是桌面原生壳(Tauri),它没有 - 后缀。 */
export type ClientPlatformKind = 'pwa' | 'app' | 'apk' | 'web' | 'native' | 'unknown'

const OS_LABEL: Record<Lang, Record<string, string>> = {
  zh: { ios: 'iOS', android: 'Android' },
  en: { ios: 'iOS', android: 'Android' },
}

const KIND_LABEL: Record<Lang, Record<string, string>> = {
  zh: { pwa: 'PWA', app: 'App', apk: 'APK' },
  en: { pwa: 'PWA', app: 'App', apk: 'APK' },
}

// 浏览器访问不带操作系统前缀。桌面浏览器叫 "桌面" 会和 Tauri 桌面原生壳撞概念,
// 而 *-web 一律被排除在被动监护之外(见 GMScreen.liveDevices),操作系统对判断没有价值。
const WEB_LABEL: Record<Lang, string> = { zh: '网页版', en: 'Web' }

// Tauri 只上报 'tauri',不带操作系统。目前只有 Windows 构建产物,但标签不写死
// Windows —— 存储值里没有这个信息,写死会在 Linux/macOS 上线当天变成错误标签。
const NATIVE_DESKTOP_LABEL: Record<Lang, string> = { zh: '桌面 App', en: 'Desktop App' }

function dict<T>(table: Record<Lang, T>, lang: string): T {
  return table[lang as Lang] ?? table.en
}

/** 运行形态;无法识别时返回 'unknown',调用方据此决定是否编造设备类型。 */
export function clientPlatformKind(platform: string | null | undefined): ClientPlatformKind {
  const raw = (platform ?? '').toLowerCase()
  if (raw === 'tauri') return 'native'
  const suffix = raw.split('-')[1] ?? ''
  if (suffix === 'pwa' || suffix === 'app' || suffix === 'apk' || suffix === 'web') return suffix
  return 'unknown'
}

/**
 * 设备标签。无法识别的渠道返回 null —— 不编造设备类型,由调用方降级显示。
 */
export function clientPlatformLabel(
  platform: string | null | undefined,
  lang: string,
): string | null {
  const kind = clientPlatformKind(platform)
  if (kind === 'unknown') return null
  if (kind === 'native') return dict(NATIVE_DESKTOP_LABEL, lang)
  if (kind === 'web') return dict(WEB_LABEL, lang)

  const os = (platform ?? '').toLowerCase().split('-')[0]
  const osLabel = dict(OS_LABEL, lang)[os]
  const kindLabel = dict(KIND_LABEL, lang)[kind]
  if (!osLabel || !kindLabel) return null
  return `${osLabel} ${kindLabel}`
}
