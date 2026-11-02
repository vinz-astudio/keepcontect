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
  'coverage_interrupted',
  'protection_limited',
])

/**
 * ADR-0039: a coverage interruption is a technical fact about a device, not a
 * claim about the person. It must never be given emergency treatment, and the
 * server says so machine-readably with params.means_danger = false.
 */
export function notificationClaimsDanger(input: NotificationCopyInput): boolean {
  const params = paramsRecord(input.params)
  if (params.means_danger === 'false') return false
  return input.kind === 'sos'
}

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

// ADR-0039 rev.1 / ADR-0040 rev.1 / ADR-0042: the server names which silence it found.
// Losing the device, or not being allowed to look, is not evidence about the person, and in
// passive check-in even a silent miss is worded as "KC lost contact", never as danger. Both
// engines send params.miss_kind; passive alerts also send this cause. Legacy silence alerts
// carry neither and keep their original copy.
const DEVICE_LOSS_KINDS = new Set(['device_unreachable', 'collection_restricted'])
const LOST_CONTACT_STAGES = new Set(['group', 'community'])
const PASSIVE_CHECKIN_CAUSE = 'passive_checkin_lost_contact'

function lostContactKey(kind: string, params: Record<string, string>): string | null {
  if (!LOST_CONTACT_STAGES.has(kind)) return null
  const missKind = params.miss_kind ?? ''
  if (DEVICE_LOSS_KINDS.has(missKind)) return `notif.${kind}.${missKind}`
  if (params.cause === PASSIVE_CHECKIN_CAUSE && missKind === 'silent') return `notif.${kind}.silent`
  return null
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
  const key = lostContactKey(notification.kind, params) ??
    (targetIsViewer &&
    (notification.kind === 'on_it' ||
      notification.kind === 'resolved' ||
      notification.kind === 'auto_resolved')
      ? `notif.${notification.kind}.you`
      : `notif.${notification.kind}`)

  return translate(key as I18nKey, {
    name: fill(params.name),
    actor: fill(params.actor),
    target: fill(params.target),
  })
}
