import { Capacitor } from '@capacitor/core'
import { getPlatform } from '@/lib/platform'

// Android APK 的稳定下载地址（GitHub Releases 的 latest 资产）。
export const APK_URL =
  'https://github.com/vinz-astudio/keepcontect/releases/latest/download/keep-contact.apk'

/** 运行在 Android 的网页/PWA（非原生壳）——适合引导安装或从 PWA 升级到 APK。 */
export function isAndroidWeb(): boolean {
  return getPlatform() === 'android' && !Capacitor.isNativePlatform()
}
