// iOS "Time Sensitive" notification setting, as reported by the native bridge
// (PushRegistrar.status → getNotificationPermissionStatus().timeSensitive).
//
// Human decision D2 (2026-11-02): when the user has turned Time Sensitive off
// for KC, the permission center says so instead of implying the safety ask will
// get through Focus. Unknown and unsupported make no claim either way.
export type TimeSensitiveSetting = 'enabled' | 'disabled' | 'unsupported' | 'unknown'

export function parseTimeSensitiveSetting(raw: unknown): TimeSensitiveSetting {
  return raw === 'enabled' || raw === 'disabled' || raw === 'unsupported' ? raw : 'unknown'
}

export interface TimeSensitiveLimitation {
  zh: string
  en: string
}

export function timeSensitiveLimitation(
  setting: TimeSensitiveSetting,
  notificationsGranted: boolean,
): TimeSensitiveLimitation | null {
  // Notifications off is reported by the notification row itself.
  if (!notificationsGranted || setting !== 'disabled') return null
  return {
    zh: '时效性通知已关闭:开启专注模式时,你可能收不到 KC 的安全询问。可在 设置 › Keep Contact › 通知 中开启"时效性通知"。',
    en: 'Time Sensitive notifications are off: with a Focus on, you may miss KC’s safety check. Turn on "Time Sensitive Notifications" in Settings › Keep Contact › Notifications.',
  }
}

/**
 * IOS-FOCUS-01: each Focus has its own "Time Sensitive Notifications" switch,
 * and iOS gives apps no way to read it. When it is off, the safety ask is
 * silenced even though KC's own switches are on, so the permission center can
 * only say where to look.
 */
export const FOCUS_TIME_SENSITIVE_HINT: TimeSensitiveLimitation = {
  zh: '开了勿扰仍收不到安全询问?到 设置 › 专注模式 › 勿扰模式 › App,打开"时效性通知"。',
  en: 'Missing the safety check during Do Not Disturb? In Settings › Focus › Do Not Disturb › Apps, turn on "Time Sensitive Notifications".',
}
