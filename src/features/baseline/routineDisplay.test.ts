import { describe, expect, it } from 'vitest'
import { localizeQuietWindowReason } from '@/features/baseline/routineDisplay'

describe('routine display helpers', () => {
  it('localizes the built-in sleep quiet-window reason', () => {
    expect(localizeQuietWindowReason('sleep', 'en')).toBe('Sleep')
    expect(localizeQuietWindowReason('睡眠', 'en')).toBe('Sleep')
    expect(localizeQuietWindowReason('sleep', 'zh')).toBe('睡眠')
  })

  it('preserves user-provided quiet-window labels', () => {
    expect(localizeQuietWindowReason('Gym', 'en')).toBe('Gym')
    expect(localizeQuietWindowReason('健身', 'zh')).toBe('健身')
    expect(localizeQuietWindowReason('  Movie  ', 'en')).toBe('Movie')
  })
})
