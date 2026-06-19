// 平台检测：iOS / Android / 桌面，以及是否已"添加到主屏/已安装"。
// 用于按平台呈现不同界面（iOS 才需要快捷指令；Android 走安装 App）。

export type Platform = 'ios' | 'android' | 'desktop'

export function getPlatform(): Platform {
  const ua = navigator.userAgent || ''
  // iPadOS 13+ 伪装成 Mac，靠触点数区分
  const iPadOS =
    navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1
  if (/iPhone|iPad|iPod/.test(ua) || iPadOS) return 'ios'
  if (/Android/.test(ua)) return 'android'
  return 'desktop'
}

/** 是否以独立 App（已添加到主屏/已安装）方式打开 */
export function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    (navigator as unknown as { standalone?: boolean }).standalone === true
  )
}
