import { Capacitor } from '@capacitor/core'
import { getPlatform } from '@/lib/platform'

import { APP_VERSION } from '@/lib/version'

/** Android APK 的动态版本下载地址（Vercel 托管）。 */
export function getApkUrl(ver: string = APP_VERSION): string {
  return `https://keep-contact-mauve.vercel.app/keep-contact-v${ver}.apk`
}

export const APK_URL = getApkUrl()

/** 运行在 Android 的网页/PWA（非原生壳）——适合引导安装或从 PWA 升级到 APK。 */
export function isAndroidWeb(): boolean {
  return getPlatform() === 'android' && !Capacitor.isNativePlatform()
}
