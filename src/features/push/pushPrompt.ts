import type { Platform } from '@/lib/platform'
import type { PushStatus } from '@/features/push/pushApi'

export interface PushPromptPlacementInput {
  status: PushStatus
  platform: Platform
  standalone: boolean
  dismissed: boolean
}

export function getPushPromptPlacement(input: PushPromptPlacementInput): {
  home: boolean
  profile: boolean
} {
  return {
    home: input.status === 'need_permission' && !input.dismissed,
    profile: input.status === 'denied',
  }
}
