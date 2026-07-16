import { describe, expect, it } from 'vitest'
import {
  chooseLastActivityTruth,
  getActiveStatusDisplayState,
} from '@/features/passive/activeStatusDisplay'

describe('active status display truth', () => {
  it('uses server behavior time instead of local pings when server truth is required', () => {
    const chosen = chooseLastActivityTruth({
      serverLastAt: '2026-07-06T00:00:00.000Z',
      localLastAt: '2026-07-06T10:00:00.000Z',
      serverTruthRequired: true,
    })

    expect(chosen).toEqual({
      iso: '2026-07-06T00:00:00.000Z',
      source: 'server',
    })
  })

  it('does not fall back to local pings while waiting for server truth', () => {
    const chosen = chooseLastActivityTruth({
      serverLastAt: null,
      localLastAt: '2026-07-06T10:00:00.000Z',
      serverTruthRequired: true,
    })

    expect(chosen).toEqual({ iso: null, source: 'server' })
  })

  it('can still use local pings for local-only cards', () => {
    const chosen = chooseLastActivityTruth({
      serverLastAt: null,
      localLastAt: '2026-07-06T10:00:00.000Z',
      serverTruthRequired: false,
    })

    expect(chosen).toEqual({
      iso: '2026-07-06T10:00:00.000Z',
      source: 'local',
    })
  })
})

describe('getActiveStatusDisplayState helper', () => {
  it('(a) online + server -> server/no marker, not degraded', () => {
    const state = getActiveStatusDisplayState({
      serverLastAt: '2026-07-06T00:00:00.000Z',
      localLastAt: '2026-07-06T10:00:00.000Z',
      serverTruthRequired: false,
      online: true,
    })

    expect(state).toEqual({
      iso: '2026-07-06T00:00:00.000Z',
      source: 'server',
      showMarker: false,
      isDegraded: false,
      degradedHint: null,
    })
  })

  it('(b) server absent + serverTruthRequired -> null + degraded, never local', () => {
    const state = getActiveStatusDisplayState({
      serverLastAt: null,
      localLastAt: '2026-07-06T10:00:00.000Z',
      serverTruthRequired: true,
      online: true,
    })

    expect(state).toEqual({
      iso: null,
      source: 'server',
      showMarker: false,
      isDegraded: true,
      degradedHint: null,
    })
  })

  it('(c) offline + local -> local + marker + degraded + offline hint', () => {
    const state = getActiveStatusDisplayState({
      serverLastAt: '2026-07-06T00:00:00.000Z',
      localLastAt: '2026-07-06T10:00:00.000Z',
      serverTruthRequired: false,
      online: false,
    })

    expect(state).toEqual({
      iso: '2026-07-06T10:00:00.000Z',
      source: 'local',
      showMarker: true,
      isDegraded: true,
      degradedHint: {
        zh: '离线,显示本机记录',
        en: 'Offline — showing this device',
      },
    })
  })

  it('(d) offline + nothing -> null + degraded', () => {
    const state = getActiveStatusDisplayState({
      serverLastAt: null,
      localLastAt: null,
      serverTruthRequired: false,
      online: false,
    })

    expect(state).toEqual({
      iso: null,
      source: 'local',
      showMarker: false,
      isDegraded: true,
      degradedHint: null,
    })
  })
})
