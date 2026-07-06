import { describe, expect, it } from 'vitest'
import { getPushPromptPlacement } from '@/features/push/pushPrompt'

describe('push prompt placement', () => {
  it('does not keep denied notification warnings on the home feed', () => {
    expect(
      getPushPromptPlacement({
        status: 'denied',
        platform: 'desktop',
        standalone: false,
        dismissed: false,
      }).home,
    ).toBe(false)
  })

  it('keeps denied notification guidance available in Me', () => {
    expect(
      getPushPromptPlacement({
        status: 'denied',
        platform: 'android',
        standalone: true,
        dismissed: false,
      }).profile,
    ).toBe(true)
  })

  it('lets a browser permission prompt be dismissed from the home feed', () => {
    expect(
      getPushPromptPlacement({
        status: 'need_permission',
        platform: 'desktop',
        standalone: false,
        dismissed: true,
      }).home,
    ).toBe(false)
  })
})
