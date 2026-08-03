export type WatchSectionKey =
  | 'summary'
  | 'own-task'
  | 'gm-tools'
  | 'notifications'
  | 'people'
  | 'alert-response'

export type EvidenceQuality = 'ready' | 'limited' | 'unknown'
export type PersonAction = 'manage-checkin-task' | 'send-concern' | 'contact'

export function buildWatchSections({
  hasOwnTask,
  isGm,
  hasActiveAlert,
}: {
  hasOwnTask: boolean
  isGm: boolean
  hasActiveAlert: boolean
}): WatchSectionKey[] {
  return [
    'summary',
    ...(hasOwnTask ? ['own-task' as const] : []),
    ...(isGm ? ['gm-tools' as const] : []),
    'notifications',
    'people',
    ...(hasActiveAlert ? ['alert-response' as const] : []),
  ]
}

export function getPersonActions({
  hasActiveAlert,
  canManageWardTasks,
  concernEligible,
}: {
  hasActiveAlert: boolean
  canManageWardTasks: boolean
  concernEligible: boolean
  evidenceQuality: EvidenceQuality
}): PersonAction[] {
  const actions: PersonAction[] = []
  if (canManageWardTasks) actions.push('manage-checkin-task')
  if (hasActiveAlert && concernEligible) actions.push('send-concern', 'contact')
  return actions
}
