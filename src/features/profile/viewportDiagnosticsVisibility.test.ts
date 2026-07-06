import { describe, expect, it } from 'vitest'
import { canShowViewportDiagnostics } from '@/features/profile/viewportDiagnosticsVisibility'

describe('viewport diagnostics visibility', () => {
  it('hides layout diagnostics from normal users in production', () => {
    expect(canShowViewportDiagnostics({ isDev: false, unlocked: false })).toBe(false)
  })

  it('shows layout diagnostics in dev or after the hidden unlock', () => {
    expect(canShowViewportDiagnostics({ isDev: true, unlocked: false })).toBe(true)
    expect(canShowViewportDiagnostics({ isDev: false, unlocked: true })).toBe(true)
  })
})
