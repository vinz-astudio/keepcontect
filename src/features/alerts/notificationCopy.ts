import { translate, type I18nKey } from '@/lib/i18n'

const NOTIF_KINDS = new Set([
  'self',
  'group',
  'community',
  'terminal',
  'sos',
  'on_it',
  'resolved',
  'auto_resolved',
  'task_invite',
  'task_due',
  'task_missed',
  'task_accepted',
  'task_declined',
  'test',
  'concern',
  'update',
])

export interface NotificationCopyInput {
  kind: string
  body: string
  params: unknown
}

export interface NotificationViewer {
  userId?: string | null
  displayName?: string | null
  email?: string | null
}

function paramsRecord(params: unknown): Record<string, string> {
  if (!params || typeof params !== 'object' || Array.isArray(params)) return {}
  const out: Record<string, string> = {}
  for (const [key, value] of Object.entries(params)) {
    if (typeof value === 'string') out[key] = value
    else if (typeof value === 'number' || typeof value === 'boolean') out[key] = String(value)
  }
  return out
}

function norm(value: string | null | undefined): string {
  return (value ?? '').trim().toLocaleLowerCase()
}

function isCurrentUserTarget(params: Record<string, string>, viewer?: NotificationViewer): boolean {
  if (params.target_is_recipient === 'true') return true

  const userId = norm(viewer?.userId)
  const targetId = norm(params.target_id || params.targetId || params.user_id || params.userId)
  if (userId && targetId && userId === targetId) return true

  const target = norm(params.target)
  if (!target) return false
  return target === norm(viewer?.displayName) || target === norm(viewer?.email)
}

function fill(value: string | undefined): string {
  return value || translate('notif.someone')
}

export function renderNotificationCopy(
  notification: NotificationCopyInput,
  viewer?: NotificationViewer,
): string {
  if (!NOTIF_KINDS.has(notification.kind)) return notification.body
  const params = paramsRecord(notification.params)
  const targetIsViewer = isCurrentUserTarget(params, viewer)
  const key =
    targetIsViewer &&
    (notification.kind === 'on_it' ||
      notification.kind === 'resolved' ||
      notification.kind === 'auto_resolved')
      ? `notif.${notification.kind}.you`
      : `notif.${notification.kind}`

  return translate(key as I18nKey, {
    name: fill(params.name),
    actor: fill(params.actor),
    target: fill(params.target),
  })
}
