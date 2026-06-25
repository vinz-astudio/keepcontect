import { describe, expect, it } from 'vitest'
import { formatBehaviorTime } from '@/features/gm/behaviorTime'

describe('formatBehaviorTime', () => {
  const now = new Date('2026-06-25T17:30:00Z').getTime()

  it('shows an empty state when no behavior signal exists', () => {
    expect(formatBehaviorTime(null, now, 'en')).toEqual({
      relative: 'No behavior yet',
      exact: '',
    })
  })

  it('formats recent behavior in minutes and includes the exact time', () => {
    expect(formatBehaviorTime('2026-06-25T17:05:00Z', now, 'en', 'UTC')).toEqual({
      relative: '25m ago',
      exact: 'Jun 25, 17:05',
    })
  })

  it('formats older behavior in days for Chinese UI', () => {
    expect(formatBehaviorTime('2026-06-23T17:05:00Z', now, 'zh', 'Asia/Dhaka')).toEqual({
      relative: '2天前',
      exact: '6月23日 23:05',
    })
  })
})