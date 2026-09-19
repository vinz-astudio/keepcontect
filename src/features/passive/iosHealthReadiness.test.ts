import { expect, it } from 'vitest'
import { iosHealthReadiness } from './iosHealthReadiness'
it('does not turn registration or an empty successful query into a background guarantee', () => {
  expect(iosHealthReadiness(undefined)).toBe('unknown')
  expect(iosHealthReadiness({ supported: true, asked: false, observing: false })).toBe('action')
  expect(iosHealthReadiness({ supported: true, asked: true, observing: true })).toBe('limited')
  expect(iosHealthReadiness({ supported: true, asked: true, observing: true, backgroundDeliveryEnabled: true, lastQuerySucceeded: true })).toBe('limited')
})
