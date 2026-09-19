import { parsePassiveEvidenceRequest, type PassiveEvidenceParseResult } from './contract.ts'

/** Compatibility with a Shortcut's Get Contents of URL action, explicitly scoped at setup. */
export function parseShortcutEvidenceRequest(url: URL, now: number, eventId: string): PassiveEvidenceParseResult {
  const allowed = new Set(['binding_id', 'credential', 'trigger'])
  const keys = [...url.searchParams.keys()]
  if (keys.some((key) => !allowed.has(key)) || new Set(keys).size !== keys.length
    || url.searchParams.get('trigger') !== 'app_open') {
    return { ok: false, status: 400, code: 'unsupported_shortcut_trigger' }
  }
  return parsePassiveEvidenceRequest(JSON.stringify({
    binding_id: url.searchParams.get('binding_id'), credential: url.searchParams.get('credential'),
    event_id: eventId, sequence: now, observed_at: new Date(now).toISOString(),
    evidence_class: 'direct_device_use', qualification_policy_version: 'passive-qualification-v1',
    correlation_id: null, qualification_facts: { interaction: true },
    query_started_at: null, query_ended_at: null, query_succeeded: false,
  }), now)
}
