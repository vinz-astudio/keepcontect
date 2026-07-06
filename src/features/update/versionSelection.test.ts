import { describe, expect, it } from 'vitest'
import {
  isClientBehindTarget,
  selectLatestVersion,
  type VersionRecord,
} from './versionSelection'

describe('version channel selection', () => {
  const rolloutRows: VersionRecord[] = [
    {
      version: '0.5.16',
      status: 'released',
      created_at: '2026-07-06T22:00:00.000Z',
    },
    {
      version: '0.5.17',
      status: 'canary',
      created_at: '2026-07-06T22:00:00.000Z',
    },
  ]

  it('selects the newest canary version without relying on created_at order', () => {
    expect(selectLatestVersion(rolloutRows, 'canary')?.version).toBe('0.5.17')
  })

  it('keeps released users on the latest released version', () => {
    expect(selectLatestVersion(rolloutRows, 'released')?.version).toBe('0.5.16')
  })

  it('falls canary back to released when no canary build exists', () => {
    expect(
      selectLatestVersion(
        [{ version: '0.5.16', status: 'released', created_at: '2026-07-06T22:00:00.000Z' }],
        'canary',
      )?.version,
    ).toBe('0.5.16')
  })
})

describe('GM target version comparisons', () => {
  it('marks 0.5.16 clients behind a 0.5.17 canary target', () => {
    expect(isClientBehindTarget('0.5.16', '0.5.17')).toBe(true)
  })

  it('does not mark clients behind when they match the selected target', () => {
    expect(isClientBehindTarget('0.5.16', '0.5.16')).toBe(false)
  })

  it('treats clients without a reported version as behind the target', () => {
    expect(isClientBehindTarget(null, '0.5.17')).toBe(true)
  })
})
