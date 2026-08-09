import { describe, expect, it } from 'vitest'
import {
  CONCERN_NEEDS_ALERT_MESSAGE,
  CONCERN_REQUIRES_ACTIVE_ALERT,
  concernErrorMessage,
  gmConcernEligible,
} from './gmConcernEligibility'

describe('gmConcernEligible', () => {
  it('allows Concern only while the target has an active alert', () => {
    expect(gmConcernEligible({ alerted: true })).toBe(true)
  })

  it('refuses a target with no active alert', () => {
    expect(gmConcernEligible({ alerted: false })).toBe(false)
  })

  it('treats unknown alert state as ineligible rather than assuming it is safe to ask', () => {
    expect(gmConcernEligible({})).toBe(false)
    expect(gmConcernEligible({ alerted: null })).toBe(false)
    expect(gmConcernEligible(null)).toBe(false)
    expect(gmConcernEligible(undefined)).toBe(false)
  })
})

describe('concernErrorMessage', () => {
  it('explains the rule when the server refuses for want of an active alert', () => {
    const message = concernErrorMessage(
      new Error(`db error: ${CONCERN_REQUIRES_ACTIVE_ALERT}`),
      'err.op'
    )
    expect(message).toBe(CONCERN_NEEDS_ALERT_MESSAGE)
  })

  it('passes any other failure through so real errors stay visible', () => {
    expect(concernErrorMessage(new Error('network down'), 'err.op')).toBe('network down')
  })

  it('falls back to the generic operation error when there is no message', () => {
    expect(concernErrorMessage({}, 'err.op')).toBe('err.op')
  })
})
