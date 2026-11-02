import { describe, expect, it } from 'vitest'
import { FOCUS_TIME_SENSITIVE_HINT, parseTimeSensitiveSetting, timeSensitiveLimitation } from '@/features/passive/timeSensitiveNotice'
import fs from 'node:fs'

describe('time-sensitive notification setting', () => {
  it('reads only the values the native bridge can send', () => {
    expect(parseTimeSensitiveSetting('enabled')).toBe('enabled')
    expect(parseTimeSensitiveSetting('disabled')).toBe('disabled')
    expect(parseTimeSensitiveSetting('unsupported')).toBe('unsupported')
    // Old app shells do not send the field at all; that is not "enabled".
    expect(parseTimeSensitiveSetting(undefined)).toBe('unknown')
    expect(parseTimeSensitiveSetting('weird')).toBe('unknown')
  })

  it('reports a limitation only when notifications are on but cannot break through Focus', () => {
    const limited = timeSensitiveLimitation('disabled', true)
    expect(limited?.zh).toContain('专注模式')
    expect(limited?.en).toMatch(/Focus/)
  })

  it('makes no claim when it cannot know, and no duplicate claim when notifications are off', () => {
    expect(timeSensitiveLimitation('enabled', true)).toBeNull()
    expect(timeSensitiveLimitation('unknown', true)).toBeNull()
    // iOS 14 has no such setting; nothing the user can change.
    expect(timeSensitiveLimitation('unsupported', true)).toBeNull()
    // Notifications denied is already reported by the notification row itself.
    expect(timeSensitiveLimitation('disabled', false)).toBeNull()
  })

  // IOS-FOCUS-01 (2026-11-02 device acceptance): with the Focus's own Time
  // Sensitive switch off, the safety ask was silenced although both switches
  // KC can see were on. iOS gives apps no way to read Focus settings, so the
  // permission center can only say where to look.
  it('tells iPhone users where the Focus switch is, since KC cannot read it', () => {
    expect(FOCUS_TIME_SENSITIVE_HINT.zh).toContain('专注模式')
    expect(FOCUS_TIME_SENSITIVE_HINT.zh).toContain('时效性通知')
    expect(FOCUS_TIME_SENSITIVE_HINT.en).toMatch(/Focus/)
    expect(FOCUS_TIME_SENSITIVE_HINT.en).toMatch(/Time Sensitive/)
    const rows = fs.readFileSync('src/features/passive/guardianPermissions.ts', 'utf8')
    expect(rows).toContain('FOCUS_TIME_SENSITIVE_HINT.zh')
  })
})
