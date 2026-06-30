import { describe, expect, it } from 'vitest'
import { shouldShowSelfCheckForNotificationKind } from '@/features/alerts/notificationRouting'

describe('notification routing', () => {
  it('only opens the self-check overlay for notifications about the current user', () => {
    expect(shouldShowSelfCheckForNotificationKind('self')).toBe(true)
    expect(shouldShowSelfCheckForNotificationKind('concern')).toBe(true)

    for (const kind of ['group', 'community', 'terminal', 'on_it', 'resolved', 'task_missed', undefined, null]) {
      expect(shouldShowSelfCheckForNotificationKind(kind)).toBe(false)
    }
  })
})