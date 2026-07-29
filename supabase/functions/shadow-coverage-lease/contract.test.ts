import { describe, it, expect } from 'vitest'
import { mapCoverageLeaseStatus, parseCoverageLeaseRequest } from './contract'

describe('parseCoverageLeaseRequest', () => {
  const validBody = {
    token: 'test-token-12345',
    client_id: 'client-001',
    channel: 'android-apk',
    collector_contract: 'android-passive-v1',
    collector_state: 'operational',
    capability_sha256: 'a'.repeat(64),
    observed_at: new Date().toISOString(),
    event_id: '00000000-0000-4000-8000-000000000001',
  }

  it('normalizes valid request for internal token lookup', () => {
    const raw = JSON.stringify(validBody)
    const result = parseCoverageLeaseRequest(raw)
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.client_id).toBe('client-001')
      expect(result.data.channel).toBe('android-apk')
      expect(result.data.collector_contract).toBe('android-passive-v1')
      expect(result.data.collector_state).toBe('operational')
      expect(result.data.capability_sha256).toBe('a'.repeat(64))
      expect(result.data.event_id).toBe('00000000-0000-4000-8000-000000000001')
      expect(result.data.token).toBe('test-token-12345')
    }
  })

  it('accepts the paired Tauri idle collector contract', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({
      ...validBody,
      channel: 'tauri',
      collector_contract: 'tauri-idle-v1',
    }))
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.channel).toBe('tauri')
      expect(result.data.collector_contract).toBe('tauri-idle-v1')
    }
  })

  it('rejects a collector contract paired with the wrong channel', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({
      ...validBody,
      channel: 'tauri',
      collector_contract: 'android-passive-v1',
    }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(422)
      expect(result.code).toBe('unsupported_contract')
    }
  })

  it('rejects malformed JSON with 400', () => {
    const result = parseCoverageLeaseRequest('{invalid json')
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(400)
      expect(result.code).toBe('malformed_json')
    }
  })

  it('rejects missing or blank token with 400', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, token: '' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(400)
      expect(result.code).toBe('invalid_request')
    }
  })

  it('rejects invalid client_id with 400', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, client_id: '' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(400)
      expect(result.code).toBe('invalid_request')
    }
  })

  it('rejects wrong channel with 422', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, channel: 'web' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(422)
      expect(result.code).toBe('unsupported_channel')
    }
  })

  it('rejects wrong collector_contract with 422', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, collector_contract: 'tauri-idle-v1' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(422)
      expect(result.code).toBe('unsupported_contract')
    }
  })

  it('rejects wrong collector_state with 422', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, collector_state: 'degraded' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(422)
      expect(result.code).toBe('unsupported_state')
    }
  })

  it('rejects invalid capability_sha256 with 400', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, capability_sha256: 'short' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(400)
      expect(result.code).toBe('invalid_capability_hash')
    }
  })

  it('rejects invalid or missing event_id UUID with 400', () => {
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, event_id: 'not-a-uuid' }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(400)
      expect(result.code).toBe('invalid_event_id')
    }
  })

  it('rejects stale observed_at (> 300s in past) with 422', () => {
    const pastDate = new Date(Date.now() - 360 * 1000).toISOString()
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, observed_at: pastDate }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(422)
      expect(result.code).toBe('invalid_observed_time')
    }
  })

  it('rejects future observed_at (> 300s in future) with 422', () => {
    const futureDate = new Date(Date.now() + 360 * 1000).toISOString()
    const result = parseCoverageLeaseRequest(JSON.stringify({ ...validBody, observed_at: futureDate }))
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.status).toBe(422)
      expect(result.code).toBe('invalid_observed_time')
    }
  })
})


describe('mapCoverageLeaseStatus', () => {
  it('maps only the seven stable SQL statuses', () => {
    expect(mapCoverageLeaseStatus('inserted')).toEqual({
      httpStatus: 200,
      body: { ok: true, status: 'inserted' },
    })
    expect(mapCoverageLeaseStatus('duplicate')).toEqual({
      httpStatus: 200,
      body: { ok: true, status: 'duplicate' },
    })
    expect(mapCoverageLeaseStatus('disabled').body.status).toBe('disabled')
    expect(mapCoverageLeaseStatus('invalid').body.status).toBe('invalid')
    expect(mapCoverageLeaseStatus('unsupported').body.status).toBe('unsupported')
    expect(mapCoverageLeaseStatus('unregistered_client').body.status).toBe('unregistered_client')
    expect(mapCoverageLeaseStatus('capability_mismatch').body.status).toBe('capability_mismatch')
  })

  it('hides unexpected database output', () => {
    expect(mapCoverageLeaseStatus('raw postgres error')).toEqual({
      httpStatus: 500,
      body: { ok: false, status: 'database_error' },
    })
  })
})
