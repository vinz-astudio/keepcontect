import { describe, expect, it } from 'vitest'
import { parsePassiveCollectorHealth, passiveHealthCopy } from './passiveCheckinPresentation'

describe('passive collector health presentation', () => {
  it('names the affected device and never claims Limited pauses misses', () => {
    const health = parsePassiveCollectorHealth({
      state: 'limited', miss_counting_continues: true, evaluated_at: '2026-08-14T12:00:00Z',
      devices: [{ binding_id: 'b1', device: 'my-phone', surface_type: 'android_native',
        state: 'limited', reason: 'silent', repair_action: 'Open Keep Contact.', last_contact_at: null }],
    })
    expect(health.devices[0]).toMatchObject({ device: 'my-phone', reason: 'silent' })
    expect(passiveHealthCopy(health, 'zh').detail).toContain('漏签计数仍会继续')
    expect(passiveHealthCopy(health, 'en').detail).toContain('Miss counting continues')
    expect(health.globalReason).toBeNull()
  })

  it('rejects reassuring malformed or contradictory health', () => {
    expect(() => parsePassiveCollectorHealth({ state: 'ready', devices: [], miss_counting_continues: false })).toThrow()
    expect(() => parsePassiveCollectorHealth({ state: 'off', devices: [{}], miss_counting_continues: true, evaluated_at: '2026-08-14T12:00:00Z' })).toThrow()
  })
})
