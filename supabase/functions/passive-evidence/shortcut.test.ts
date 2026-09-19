import { describe, expect, it } from 'vitest'
import { parseShortcutEvidenceRequest } from './shortcut'

const binding = '11111111-1111-4111-8111-111111111111'
const event = '22222222-2222-4222-8222-222222222222'
const now = Date.parse('2026-09-19T00:00:00Z')
const url = () => new URL(`https://example.test/passive-evidence?binding_id=${binding}&credential=${'a'.repeat(64)}&trigger=app_open`)

describe('bound App-open Shortcut ingestion', () => {
  it('qualifies only a scoped app-open invocation, using server occurrence time', () => {
    const result = parseShortcutEvidenceRequest(url(), now, event)
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.data).toMatchObject({ binding_id: binding, event_id: event,
      sequence: now, observed_at: new Date(now).toISOString(),
      evidence_class: 'direct_device_use', qualification_facts: { interaction: true },
      query_succeeded: false,
    })
  })
  it('rejects legacy tokens and unspecified/unsupported triggers', () => {
    expect(parseShortcutEvidenceRequest(new URL('https://example.test/?token=legacy'), now, event).ok).toBe(false)
    const input = url()
    for (const trigger of ['', 'timer', 'charging', 'push', 'motion']) {
      input.searchParams.set('trigger', trigger)
      expect(parseShortcutEvidenceRequest(input, now, event).ok).toBe(false)
    }
  })
  it('rejects caller-supplied time, class or raw activity data', () => {
    const input = url()
    input.searchParams.set('observed_at', new Date(now - 100_000).toISOString())
    expect(parseShortcutEvidenceRequest(input, now, event).ok).toBe(false)
    input.searchParams.delete('observed_at')
    input.searchParams.append('binding_id', binding)
    expect(parseShortcutEvidenceRequest(input, now, event).ok).toBe(false)
  })
})
