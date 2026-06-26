import { describe, expect, it } from 'vitest'
import { formatGroupActivityStatus } from '@/features/relationships/groupActivityDisplay'

describe('formatGroupActivityStatus', () => {
  it('does not describe an active alert as one or more days silent', () => {
    expect(formatGroupActivityStatus('alert', 3, 'en')).toBe('Needs attention - 3h since activity')
  })

  it('keeps true over-24h silence as days', () => {
    expect(formatGroupActivityStatus('silent', 27, 'en')).toBe('1+ day(s) no activity')
  })

  it('shows Chinese alert copy with actual behavior age', () => {
    expect(formatGroupActivityStatus('alert', 4, 'zh')).toBe('需要关注 · 4小时前有行为')
  })
})
