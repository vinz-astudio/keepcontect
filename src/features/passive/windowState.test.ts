import { describe, expect, it } from 'vitest'
import { parsePassiveWindowState } from './windowState'

describe('parsePassiveWindowState', () => {
  it('parses server-owned window, chain, sleep defer and alert state', () => {
    expect(parsePassiveWindowState({
      engine_mode: 'passive_checkin',
      consecutive_misses: 3,
      sleep_deferred: true,
      current_window: {
        id: 'window-1', ordinal: 4,
        window_start: '2026-08-14T10:00:00Z',
        window_end: '2026-08-14T11:00:00Z',
        arrival_deadline: '2026-08-14T11:35:00Z', outcome: 'missed',
      },
      open_alert: null,
    })).toEqual(expect.objectContaining({
      engineMode: 'passive_checkin', consecutiveMisses: 3, sleepDeferred: true,
      currentWindow: expect.objectContaining({ ordinal: 4, outcome: 'missed' }),
      openAlert: null,
    }))
  })

  it('parses a legacy account without invented window state', () => {
    expect(parsePassiveWindowState({
      engine_mode: 'legacy', consecutive_misses: 0, current_window: null,
      open_alert: null, sleep_deferred: false,
    })).toEqual({
      engineMode: 'legacy', consecutiveMisses: 0, currentWindow: null,
      openAlert: null, sleepDeferred: false,
    })
  })

  it.each([
    { engine_mode: 'live', consecutive_misses: 0, current_window: null, open_alert: null, sleep_deferred: false },
    { engine_mode: 'shadow', consecutive_misses: -1, current_window: null, open_alert: null, sleep_deferred: false },
    { engine_mode: 'shadow', consecutive_misses: 0, current_window: { id: 'x', ordinal: 0, window_start: 'bad', window_end: 'bad', arrival_deadline: 'bad', outcome: 'pending' }, open_alert: null, sleep_deferred: false },
    { engine_mode: 'shadow', consecutive_misses: 0, current_window: null, open_alert: { id: 'a', stage: 'danger', opened_at: '2026-08-14T10:00:00Z' }, sleep_deferred: false },
  ])('rejects malformed or open-ended authority state', (value) => {
    expect(() => parsePassiveWindowState(value)).toThrow('Invalid passive window state')
  })
})
