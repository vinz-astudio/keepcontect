import { describe, expect, it } from 'vitest'
import {
  buildPassiveEvidenceRequest,
  COLLECTOR_CONTRACTS,
  parsePassiveCollectorBinding,
} from './evidenceContract'

const binding = parsePassiveCollectorBinding({
  binding_id: '11111111-1111-4111-8111-111111111111',
  credential: 'c'.repeat(64),
  credential_version: 1,
  surface_type: 'android_native',
  collector_contract: 'android-passive-evidence-v1',
})

describe('passive collector client contract', () => {
  it('uses the accepted closed surface names', () => {
    expect(Object.keys(COLLECTOR_CONTRACTS)).toEqual([
      'tauri_native', 'tauri_native_linux', 'android_native', 'ios_native', 'pwa_browser', 'shortcut',
    ])
    expect(COLLECTOR_CONTRACTS).not.toHaveProperty('installed_pwa')
  })

  it('rejects a mismatched contract and surface', () => {
    expect(() => parsePassiveCollectorBinding({
      binding_id: 'id', credential: 'c'.repeat(64), credential_version: 1,
      surface_type: 'android_native', collector_contract: 'ios-passive-evidence-v1',
    })).toThrow('Invalid passive collector binding')
  })

  it('builds only normalized evidence fields and preserves occurrence time', () => {
    const request = buildPassiveEvidenceRequest(binding, {
      eventId: '22222222-2222-4222-8222-222222222222',
      sequence: 4,
      observedAt: '2026-08-14T10:00:00+06:00',
      evidenceClass: 'direct_device_use',
      correlationId: null,
      qualificationFacts: { interaction: true },
    })
    expect(request.observed_at).toBe('2026-08-14T04:00:00.000Z')
    expect(request).not.toHaveProperty('package_name')
    expect(request).not.toHaveProperty('received_at')
  })

  it('does not accept upload time as a missing occurrence time', () => {
    expect(() => buildPassiveEvidenceRequest(binding, {
      eventId: '22222222-2222-4222-8222-222222222222', sequence: 0,
      observedAt: '', evidenceClass: 'direct_device_use', correlationId: null,
      qualificationFacts: { interaction: true },
    })).toThrow('Invalid passive evidence draft')
  })
})
