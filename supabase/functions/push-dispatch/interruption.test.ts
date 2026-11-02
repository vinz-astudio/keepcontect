import { describe, expect, it } from 'vitest'
import { apnsInterruptionLevel } from './interruption.ts'

// 2026-11-02 (human decision D1): the subject's own safety ask and real
// emergencies break through Focus; lost-contact notices to the circle do not.
describe('APNs interruption level for visible pushes', () => {
  it.each(['self', 'concern', 'sos', 'terminal'])('marks %s as time-sensitive', kind => {
    expect(apnsInterruptionLevel(kind)).toBe('time-sensitive')
  })

  it.each(['group', 'community', 'on_it', 'resolved', 'auto_resolved', 'task_due', 'test', '', undefined])(
    'keeps %s as an ordinary active notification', kind => {
      expect(apnsInterruptionLevel(kind)).toBe('active')
    })
})
