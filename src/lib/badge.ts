// 主屏 App 图标角标（未读通知红点+数字）。Web Badging API：
// iOS 16.4+ 已安装 PWA / Android Chrome 支持；不支持的环境静默忽略。

type BadgeNav = Navigator & {
  setAppBadge?: (n?: number) => Promise<void>
  clearAppBadge?: () => Promise<void>
}

export function setBadge(count: number): void {
  const nav = navigator as BadgeNav
  try {
    if (count > 0) void nav.setAppBadge?.(count)
    else void nav.clearAppBadge?.()
  } catch {
    /* 不支持则忽略 */
  }
}

export function clearBadge(): void {
  const nav = navigator as BadgeNav
  try {
    void nav.clearAppBadge?.()
  } catch {
    /* 忽略 */
  }
}
