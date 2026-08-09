import { describe, expect, it } from 'vitest'
import {
  protectionCopyKeys,
  protectionState,
  shouldPromptOnce,
  shouldSurfaceProtection,
  type ProtectionHealth,
} from './protectionHealth'

const health = (over: Partial<ProtectionHealth> = {}): ProtectionHealth => ({
  state: 'ready',
  since: null,
  cause: null,
  prompted_at: null,
  acknowledged_at: null,
  recovery_required: null,
  last_valid_coverage_at: null,
  ...over,
})

describe('protectionState', () => {
  it('reports what the server proved', () => {
    expect(protectionState(health({ state: 'ready' }))).toBe('ready')
    expect(protectionState(health({ state: 'limited' }))).toBe('limited')
  })

  it('never lets missing data read as healthy', () => {
    expect(protectionState(null)).toBe('unknown')
    expect(protectionState(undefined)).toBe('unknown')
    expect(protectionState(health({ state: 'something-new' as never }))).toBe('unknown')
  })
})

describe('shouldSurfaceProtection', () => {
  it('stays quiet only when protection is proven healthy', () => {
    expect(shouldSurfaceProtection(health({ state: 'ready' }))).toBe(false)
  })

  it('shows itself when protection is limited or unknown', () => {
    expect(shouldSurfaceProtection(health({ state: 'limited' }))).toBe(true)
    expect(shouldSurfaceProtection(null)).toBe(true)
  })
})

describe('shouldPromptOnce', () => {
  it('prompts once while limited and not yet acknowledged', () => {
    expect(shouldPromptOnce(health({ state: 'limited' }))).toBe(true)
  })

  it('stops prompting after acknowledgement', () => {
    expect(
      shouldPromptOnce(health({ state: 'limited', acknowledged_at: '2026-08-10T00:00:00Z' }))
    ).toBe(false)
  })

  it('does not prompt for unknown, which is a standing condition rather than an event', () => {
    expect(shouldPromptOnce(null)).toBe(false)
  })
})

describe('protectionCopyKeys', () => {
  it('gives each state its own words, so unknown is never dressed as ready', () => {
    expect(protectionCopyKeys('ready').label).toBe('health.ready')
    expect(protectionCopyKeys('limited').label).toBe('health.limited')
    expect(protectionCopyKeys('unknown').label).toBe('health.unknown')
  })
})
