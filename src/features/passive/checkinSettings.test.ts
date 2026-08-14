import { describe, expect, it, vi } from 'vitest'
import type { PassiveCheckinStatus } from './checkinContract'
import { canActivatePassive, formatHorizonMinutes, savePassiveSettingsSafe } from './checkinSettings'

const status: PassiveCheckinStatus = {
  engineMode: 'shadow', killSwitchActive: false, collectorHealth: null, recommendation: null,
  contract: null, currentWindow: null,
  epoch: { id: 'e1', startedAt: '2026-08-01T00:00:00Z', startReason: 'contract_saved' },
}
const draft = { intervalMinutes: 60, consecutiveMisses: 4, sleep: { policy: 'none' as const, acknowledged: true } }

describe('passive settings model', () => {
  it('formats the full D/N horizon without unsafe overflow', () => {
    expect(formatHorizonMinutes(60, 4)).toBe('4h')
    expect(formatHorizonMinutes(360, 1_000_000)).toBe('250000d')
    expect(formatHorizonMinutes(Number.MAX_SAFE_INTEGER, 2)).toBe('—')
  })

  it('requires explicit 14-day shadow history and a bound collector', () => {
    expect(canActivatePassive(status, true, Date.parse('2026-08-15T00:00:00Z'))).toBe(true)
    expect(canActivatePassive(status, false, Date.parse('2026-08-15T00:00:00Z'))).toBe(false)
    expect(canActivatePassive(status, true, Date.parse('2026-08-14T23:59:59Z'))).toBe(false)
  })

  it('keeps last server truth when the one-RPC save fails', async () => {
    const result = await savePassiveSettingsSafe(draft, 'shadow', status, vi.fn().mockRejectedValue(new Error('offline')))
    expect(result).toEqual({ success: false, status, error: 'offline' })
  })
})
