import { describe, expect, it } from 'vitest'
import {
  buildPassiveContractArgs,
  parsePassiveCheckinStatus,
  validatePassiveContractDraft,
  type PassiveContractDraft,
} from './checkinContract'

describe('passive check-in contract client boundary', () => {
  it('parses a legacy account without inventing a contract', () => {
    expect(parsePassiveCheckinStatus({
      engine_mode: 'legacy',
      kill_switch_active: false,
      contract: null,
      epoch: null,
      current_window: null,
      collector_health: null,
      recommendation: null,
    })).toEqual({
      engineMode: 'legacy',
      killSwitchActive: false,
      contract: null,
      epoch: null,
      currentWindow: null,
      collectorHealth: null,
      recommendation: null,
    })
  })

  it('parses the server-acknowledged active contract and epoch', () => {
    const status = parsePassiveCheckinStatus({
      engine_mode: 'shadow',
      kill_switch_active: false,
      contract: {
        id: '71000000-0000-4000-8000-000000000011',
        version_number: 2,
        interval_minutes: 30,
        consecutive_misses: 4,
        nominal_h_minutes: 120,
        sleep_policy: 'configured',
        sleep_start_local: '23:00:00',
        sleep_end_local: '07:00:00',
        timezone: 'Asia/Dhaka',
        client_contract_version: 'passive-checkin-v1',
        effective_at: '2026-08-14T12:00:00Z',
      },
      epoch: {
        id: '71000000-0000-4000-8000-000000000012',
        started_at: '2026-08-14T12:00:00Z',
        start_reason: 'contract_saved',
      },
      current_window: {
        id: '71000000-0000-4000-8000-000000000013',
        ordinal: 0,
        window_start: '2026-08-14T12:00:00Z',
        window_end: '2026-08-14T12:30:00Z',
        arrival_deadline: '2026-08-14T12:30:00Z',
        outcome: 'pending',
      },
      collector_health: null,
      recommendation: null,
    })

    expect(status.engineMode).toBe('shadow')
    expect(status.contract).toMatchObject({
      versionNumber: 2,
      intervalMinutes: 30,
      consecutiveMisses: 4,
      nominalHMinutes: 120,
      sleepPolicy: 'configured',
      timezone: 'Asia/Dhaka',
    })
    expect(status.epoch?.startReason).toBe('contract_saved')
    expect(status.currentWindow).toMatchObject({ ordinal: 0, outcome: 'pending' })
  })

  it.each(['live', '', null])('rejects an unknown engine mode: %s', (mode) => {
    expect(() => parsePassiveCheckinStatus({ engine_mode: mode })).toThrow(
      'Invalid passive check-in status',
    )
  })

  it.each([
    [19, 3, 'Collection interval must be between 20 and 360 minutes'],
    [361, 3, 'Collection interval must be between 20 and 360 minutes'],
    [60, 0, 'Consecutive misses must be between 1 and 1000000'],
    [60, 1_000_001, 'Consecutive misses must be between 1 and 1000000'],
  ])('rejects an out-of-range D/N pair', (intervalMinutes, consecutiveMisses, message) => {
    const draft: PassiveContractDraft = {
      intervalMinutes,
      consecutiveMisses,
      sleep: { policy: 'none', acknowledged: true },
    }
    expect(validatePassiveContractDraft(draft)).toContain(message)
  })

  it('requires explicit acknowledgement when sleep gating is disabled', () => {
    expect(validatePassiveContractDraft({
      intervalMinutes: 60,
      consecutiveMisses: 3,
      sleep: { policy: 'none', acknowledged: false },
    })).toContain('Confirm that overnight inactivity counts as missed check-ins')
  })

  it('requires distinct configured sleep bounds and a timezone', () => {
    expect(validatePassiveContractDraft({
      intervalMinutes: 60,
      consecutiveMisses: 3,
      sleep: {
        policy: 'configured',
        start: '23:00',
        end: '23:00',
        timezone: '',
      },
    })).toEqual(expect.arrayContaining([
      'Sleep start and end must be different',
      'A timezone is required for configured sleep',
    ]))
  })

  it('builds the exact additive RPC arguments only after validation', () => {
    expect(buildPassiveContractArgs({
      intervalMinutes: 30,
      consecutiveMisses: 4,
      sleep: {
        policy: 'configured',
        start: '23:00',
        end: '07:00',
        timezone: 'Asia/Dhaka',
      },
    })).toEqual({
      _interval_minutes: 30,
      _consecutive_misses: 4,
      _sleep_policy: 'configured',
      _sleep_start_local: '23:00:00',
      _sleep_end_local: '07:00:00',
      _timezone: 'Asia/Dhaka',
      _target_mode: 'shadow',
      _client_contract_version: 'passive-checkin-v1',
    })
  })

  it('builds explicit no-sleep arguments without stale sleep values', () => {
    expect(buildPassiveContractArgs({
      intervalMinutes: 360,
      consecutiveMisses: 1_000_000,
      sleep: { policy: 'none', acknowledged: true },
    })).toMatchObject({
      _sleep_policy: 'none',
      _sleep_start_local: null,
      _sleep_end_local: null,
      _timezone: null,
    })
  })
})
