import { describe, expect, it } from 'vitest'
import { feedCursor } from '@/features/alerts/notifyFeedCursor'

const weekAgo = '2026-08-01T00:00:00.000Z'

/** What Postgres does with `created_at > cursor`, at the column's own precision. */
function postgresGreaterThan(createdAt: string, cursor: string): boolean {
  const micros = (iso: string) => {
    const fraction = /\.(\d+)/.exec(iso)?.[1] ?? ''
    const seconds = Date.parse(iso.replace(/\.\d+/, '')) / 1000
    return BigInt(seconds) * 1_000_000n + BigInt(fraction.padEnd(6, '0').slice(0, 6))
  }
  return micros(createdAt) > micros(cursor)
}

describe('notify-feed cursor', () => {
  it('excludes the very row the cursor was taken from, at microsecond precision', () => {
    // The regression: this row's own created_at, handed back as the cursor,
    // used to re-qualify as newer than itself and be delivered again forever.
    const createdAt = '2026-08-07T21:44:00.123456+00:00'

    const cursor = feedCursor(createdAt, weekAgo)

    expect(postgresGreaterThan(createdAt, cursor)).toBe(false)
  })

  it('still admits a row created microseconds after the cursor', () => {
    const cursor = feedCursor('2026-08-07T21:44:00.123456+00:00', weekAgo)

    expect(postgresGreaterThan('2026-08-07T21:44:00.123457+00:00', cursor)).toBe(true)
  })

  it('fails the same way the old millisecond round-trip did', () => {
    // Guards the fix itself: if anyone reintroduces the Date round-trip, the
    // first assertion above stops being true, and this documents why.
    const createdAt = '2026-08-07T21:44:00.123456+00:00'
    const truncated = new Date(Date.parse(createdAt)).toISOString()

    expect(postgresGreaterThan(createdAt, truncated)).toBe(true)
  })

  it('clamps a missing cursor to the one-week lookback', () => {
    expect(feedCursor(null, weekAgo)).toBe(weekAgo)
    expect(feedCursor(undefined, weekAgo)).toBe(weekAgo)
    expect(feedCursor('', weekAgo)).toBe(weekAgo)
  })

  it('clamps a cursor older than the lookback so history is never replayed', () => {
    expect(feedCursor('2026-07-01T00:00:00.000Z', weekAgo)).toBe(weekAgo)
  })

  it('clamps an unparseable cursor rather than trusting it', () => {
    expect(feedCursor('not-a-timestamp', weekAgo)).toBe(weekAgo)
  })

  it('passes both client cursor formats through untouched', () => {
    // The iOS client primes with yyyy-MM-dd'T'HH:mm:ss.SSS'Z'; every later
    // cursor is a created_at echoed back from Postgres with an offset.
    expect(feedCursor('2026-08-07T21:44:00.123Z', weekAgo)).toBe('2026-08-07T21:44:00.123Z')
    expect(feedCursor('2026-08-07T21:44:00.123456+00:00', weekAgo)).toBe(
      '2026-08-07T21:44:00.123456+00:00',
    )
  })

  it('normalises a non-ISO but parseable cursor instead of forwarding it raw', () => {
    expect(feedCursor('Fri, 07 Aug 2026 21:44:00 GMT', weekAgo)).toBe('2026-08-07T21:44:00.000Z')
  })
})
