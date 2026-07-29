import { Capacitor } from '@capacitor/core'
import { getPlatform } from '@/lib/platform'
import { APP_VERSION } from '@/lib/version'

// Android APK 的稳定下载地址（Vercel 托管，保证静态 200 OK 资源不会 404）。
export const APK_URL = 'https://keep-contact-mauve.vercel.app/keep-contact.apk'

/** 获取客户端下载时保存的版本化文件名，如 keep-contact-v0.5.21.apk */
export function getApkDownloadFilename(ver: string = APP_VERSION): string {
  return `keep-contact-v${ver}.apk`
}

/** 运行在 Android 的网页/PWA（非原生壳）——适合引导安装或从 PWA 升级到 APK。 */
export function isAndroidWeb(): boolean {
  return getPlatform() === 'android' && !Capacitor.isNativePlatform()
}
