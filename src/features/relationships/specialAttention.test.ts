import { describe, expect, it } from 'vitest'
import {
  RELATIONSHIP_NOT_ACTIVE,
  isSpecialAttentionOn,
  specialAttentionErrorKey,
} from './specialAttention'

const subscribed = [{ subject_id: 'u-1', created_at: '2026-08-09T00:00:00Z' }]

describe('isSpecialAttentionOn', () => {
  it('is on only for a subject the person actually subscribed to', () => {
    expect(isSpecialAttentionOn(subscribed, 'u-1')).toBe(true)
  })

  it('is off for everyone else', () => {
    expect(isSpecialAttentionOn(subscribed, 'u-2')).toBe(false)
  })

  it('is off by default when nothing has been loaded or nothing is subscribed', () => {
    expect(isSpecialAttentionOn([], 'u-1')).toBe(false)
    expect(isSpecialAttentionOn(null, 'u-1')).toBe(false)
    expect(isSpecialAttentionOn(undefined, 'u-1')).toBe(false)
  })
})

describe('specialAttentionErrorKey', () => {
  it('recognises the inactive-relationship refusal so the UI can state the rule', () => {
    expect(
      specialAttentionErrorKey(new Error(`db error: ${RELATIONSHIP_NOT_ACTIVE}`))
    ).toBe('special.needsActive')
  })

  it('leaves any other failure to be reported as itself', () => {
    expect(specialAttentionErrorKey(new Error('network down'))).toBeNull()
    expect(specialAttentionErrorKey({})).toBeNull()
  })
})
