// 产品版本号(发布时与 public/version.json、android versionName 一起递增)。
// 运行中的 App 用它和线上 version.json 比较,判断是否有新版本。
// 由 scripts/release-android.mjs 在发布时自动同步。
export const APP_VERSION = '0.4.17'

// 线上版本清单(绝对地址:原生壳也能取到「线上最新」,而非 APK 内打包的那份)。
export const LATEST_URL = 'https://keep-contact-mauve.vercel.app/version.json'
