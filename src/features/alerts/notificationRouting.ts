const SELF_CHECK_NOTIFICATION_KINDS = new Set(['self', 'concern'])

export function shouldShowSelfCheckForNotificationKind(kind: unknown): boolean {
  return typeof kind === 'string' && SELF_CHECK_NOTIFICATION_KINDS.has(kind)
}