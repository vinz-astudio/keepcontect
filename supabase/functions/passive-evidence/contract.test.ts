import { describe, expect, it } from 'vitest'
import { mapPassiveEvidenceStatus, parsePassiveEvidenceRequest } from './contract.ts'

const now = Date.parse('2026-08-14T12:00:00.000Z')
const valid = {
  binding_id: '11111111-1111-4111-8111-111111111111',
  credential: 'c'.repeat(64),
  event_id: '22222222-2222-4222-8222-222222222222',
  sequence: 7,
  observed_at: '2026-08-14T11:59:00.000Z',
  evidence_class: 'direct_device_use',
  qualification_policy_version: 'passive-qualification-v1',
  correlation_id: null,
  qualification_facts: { interaction: true },
  query_started_at: null,
  query_ended_at: null,
  query_succeeded: false,
}

describe('passive evidence edge contract', () => {
  it('returns normalized evidence with the credential separated', () => {
    const result = parsePassiveEvidenceRequest(JSON.stringify(valid), now)
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.credential).toBe(valid.credential)
    expect(result.data).not.toHaveProperty('credential')
  })

  it.each(['package_name', 'url', 'typed_content', 'latitude', 'raw_motion'])(
    'rejects prohibited or unknown field %s',
    (field) => expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, [field]: 'raw' }), now))
      .toMatchObject({ ok: false, code: 'unknown_field' }),
  )

  it('rejects invalid identifiers, sequence, policy and fact keys', () => {
    expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, binding_id: 'bad' }), now).ok).toBe(false)
    expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, sequence: -1 }), now).ok).toBe(false)
    expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, qualification_policy_version: 'v0' }), now).ok).toBe(false)
    expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, qualification_facts: { package: 'x' } }), now).ok).toBe(false)
  })

  it('enforces future and seven-day bounds', () => {
    const future = new Date(now + 5 * 60_000 + 1).toISOString()
    const stale = new Date(now - 7 * 24 * 60 * 60_000 - 1).toISOString()
    expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, observed_at: future }), now).ok).toBe(false)
    expect(parsePassiveEvidenceRequest(JSON.stringify({ ...valid, observed_at: stale }), now).ok).toBe(false)
  })

  it('rejects a query interval that does not contain the event', () => {
    expect(parsePassiveEvidenceRequest(JSON.stringify({
      ...valid,
      query_started_at: '2026-08-14T11:00:00.000Z',
      query_ended_at: '2026-08-14T11:30:00.000Z',
      query_succeeded: true,
    }), now)).toMatchObject({ ok: false, code: 'query_does_not_contain_event' })
  })

  it('maps validator results fail closed', () => {
    expect(mapPassiveEvidenceStatus('inserted').httpStatus).toBe(200)
    expect(mapPassiveEvidenceStatus('duplicate').httpStatus).toBe(200)
    expect(mapPassiveEvidenceStatus('conflict').httpStatus).toBe(422)
    expect(mapPassiveEvidenceStatus('credential_mismatch').httpStatus).toBe(409)
    expect(mapPassiveEvidenceStatus('surprise').httpStatus).toBe(500)
  })
})
