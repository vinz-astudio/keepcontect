import { describe, expect, it } from 'vitest'
import { getDefaultOpenStatusKeys } from '@/features/relationships/statusBoardDisplay'

const quietActivity = {
  i_share: true,
  members: [
    { user_id: 'me', name: 'Me', is_me: true, status: 'self', hours: null, alerted: false },
  ],
}

const alertedActivity = {
  i_share: true,
  members: [
    { user_id: 'me', name: 'Me', is_me: true, status: 'self', hours: null, alerted: false },
    { user_id: 'them', name: 'Them', is_me: false, status: 'alert', hours: 4, alerted: true },
  ],
}

describe('status board default expansion', () => {
  it('keeps quiet groups collapsed so empty watch boards do not stack', () => {
    const open = getDefaultOpenStatusKeys(
      [
        { id: 'g1', communityId: 'c1', act: quietActivity },
        { id: 'g2', communityId: null, act: quietActivity },
      ],
      [{ id: 'c1' }],
    )

    expect([...open]).toEqual([])
  })

  it('opens only communities and groups that contain an active alert', () => {
    const open = getDefaultOpenStatusKeys(
      [
        { id: 'g1', communityId: 'c1', act: quietActivity },
        { id: 'g2', communityId: 'c1', act: alertedActivity },
      ],
      [{ id: 'c1' }],
    )

    expect(open.has('c:c1')).toBe(true)
    expect(open.has('g:g2')).toBe(true)
    expect(open.has('g:g1')).toBe(false)
  })
})
