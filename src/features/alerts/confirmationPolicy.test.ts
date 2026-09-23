import { describe, expect, it } from 'vitest'
import { getConfirmationMethod } from './confirmationPolicy'

describe('confirmation presentation', () => {
  it('uses a button for ordinary alerts at every escalation stage', () => {
    for (const stage of ['self','group','community','terminal']) {
      expect(getConfirmationMethod({ status:'open', stage, requires_explicit_unlock:false })).toBe('button')
    }
  })
  it('requires pattern only when the authoritative alert policy requires it', () => {
    expect(getConfirmationMethod({ status:'open', requires_explicit_unlock:true })).toBe('pattern')
  })
  it('does not guess the policy while the alert is loading or already closed', () => {
    expect(getConfirmationMethod(null)).toBe('pending')
    expect(getConfirmationMethod({ status:'resolved', requires_explicit_unlock:true })).toBe('pending')
  })
})
