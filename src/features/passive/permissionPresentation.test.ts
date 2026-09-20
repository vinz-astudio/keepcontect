import { describe, expect, it } from 'vitest'
import { summarizePermissions, sensorPresentationState } from './permissionPresentation'

describe('device permission presentation', () => {
  it('never reports complete during initial, partial, or failed reads', () => {
    expect(summarizePermissions(['notifications'], {}, null)).toBe('checking')
    expect(summarizePermissions(['notifications'], { notifications: 'unavailable' }, null)).toBe('unavailable')
    expect(summarizePermissions(['notifications'], { notifications: 'granted' }, null)).toBe('unavailable')
  })
  it('does not call limited platforms or platforms with no checks fully ready', () => {
    expect(summarizePermissions(['notifications'], { notifications: 'granted' }, ['limited'])).toBe('limited')
    expect(summarizePermissions([], {}, [])).toBe('limited')
    expect(summarizePermissions(['notifications'], { notifications: 'denied' }, ['granted'])).toBe('denied')
    expect(summarizePermissions(['notifications'], { notifications: 'granted' }, ['granted'])).toBe('granted')
    expect(summarizePermissions(['background-refresh'], { 'background-refresh': 'restricted' }, ['granted'])).toBe('limited')
  })
  it('keeps optional disabled switches separate from denied system permission', () => {
    expect(summarizePermissions(['notifications'], { notifications: 'granted' }, ['disabled'])).toBe('granted')
    expect(sensorPresentationState(false, 'denied')).toBe('disabled')
    expect(sensorPresentationState(true, undefined)).toBe('unavailable')
    expect(sensorPresentationState(true, 'limited')).toBe('limited')
  })
})
