export const CIRCLE_SECTIONS = ['circles', 'community', 'responsibilities'] as const
export type CircleRole = 'member' | 'guardian' | 'gm'
export type CircleAction =
  | 'create-circle'
  | 'join-circle'
  | 'share-invite'
  | 'leave-circle'
  | 'manage-ward-task'
  | 'manage-community'

export function getCircleActions({
  role,
  hasCommunity,
}: {
  role: CircleRole
  hasCommunity: boolean
}): CircleAction[] {
  const actions: CircleAction[] = [
    'create-circle',
    'join-circle',
    'share-invite',
    'leave-circle',
  ]
  if (role === 'guardian') actions.push('manage-ward-task')
  if (role === 'gm' && hasCommunity) actions.push('manage-community')
  return actions
}
