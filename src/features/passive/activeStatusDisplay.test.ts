import { describe, expect, it } from 'vitest'
import { chooseLastActivityTruth } from '@/features/passive/activeStatusDisplay'

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
