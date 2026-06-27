import type { Lang } from '@/lib/i18n'

const SLEEP_REASON_KEYS = new Set(['sleep', '睡眠'])

export function localizeQuietWindowReason(
  reason: string | null | undefined,
  lang: Lang,
): string | null {
  const key = reason?.trim()
  if (!key) return null
  if (SLEEP_REASON_KEYS.has(key.toLowerCase())) {
    return lang === 'zh' ? '睡眠' : 'Sleep'
  }
  return key
}
