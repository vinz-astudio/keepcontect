export const PASSIVE_QUALIFICATION_POLICY = 'passive-qualification-v1' as const

export type EvidenceClass =
  | 'direct_device_use'
  | 'personal_device_motion'
  | 'power_transition'
  | 'explicit_self_activity'

export interface PassiveEvidenceAssertion {
  binding_id: string
  event_id: string
  sequence: number
  observed_at: string
  evidence_class: EvidenceClass
  qualification_policy_version: typeof PASSIVE_QUALIFICATION_POLICY
  correlation_id: string | null
  qualification_facts: Record<string, boolean | number | string>
  query_started_at: string | null
  query_ended_at: string | null
  query_succeeded: boolean
}

export type PassiveEvidenceParseResult =
  | { ok: true; credential: string; data: PassiveEvidenceAssertion }
  | { ok: false; status: 400 | 422; code: string }

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const ALLOWED_KEYS = new Set([
  'binding_id', 'credential', 'event_id', 'sequence', 'observed_at',
  'evidence_class', 'qualification_policy_version', 'correlation_id',
  'qualification_facts', 'query_started_at', 'query_ended_at', 'query_succeeded',
])
const CLASSES = new Set<EvidenceClass>([
  'direct_device_use', 'personal_device_motion', 'power_transition', 'explicit_self_activity',
])
const FACT_KEYS = new Set([
  'interaction', 'steps_positive', 'floors_positive', 'pedestrian', 'automotive',
  'prior_power_state', 'new_power_state', 'stable_for_ms',
])
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
const FIVE_MINUTES_MS = 5 * 60 * 1000

function fail(status: 400 | 422, code: string): PassiveEvidenceParseResult {
  return { ok: false, status, code }
}

function iso(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const time = Date.parse(value)
  return Number.isFinite(time) ? new Date(time).toISOString() : null
}

function parseFacts(value: unknown): Record<string, boolean | number | string> | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const entries = Object.entries(value as Record<string, unknown>)
  if (entries.some(([key]) => !FACT_KEYS.has(key))) return null
  if (entries.some(([, item]) => !['boolean', 'number', 'string'].includes(typeof item))) return null
  return Object.fromEntries(entries) as Record<string, boolean | number | string>
}

export function parsePassiveEvidenceRequest(raw: string, nowMs = Date.now()): PassiveEvidenceParseResult {
  let value: unknown
  try { value = JSON.parse(raw) } catch { return fail(400, 'malformed_json') }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail(400, 'invalid_request')
  const body = value as Record<string, unknown>
  if (Object.keys(body).some((key) => !ALLOWED_KEYS.has(key))) return fail(400, 'unknown_field')
  if (typeof body.credential !== 'string' || body.credential.length < 32 || body.credential.length > 256) {
    return fail(400, 'invalid_credential')
  }
  if (typeof body.binding_id !== 'string' || !UUID.test(body.binding_id)) return fail(400, 'invalid_binding_id')
  if (typeof body.event_id !== 'string' || !UUID.test(body.event_id)) return fail(400, 'invalid_event_id')
  if (!Number.isSafeInteger(body.sequence) || (body.sequence as number) < 0) return fail(400, 'invalid_sequence')
  const observedAt = iso(body.observed_at)
  if (!observedAt) return fail(400, 'invalid_observed_time')
  const observedMs = Date.parse(observedAt)
  if (observedMs > nowMs + FIVE_MINUTES_MS || observedMs < nowMs - SEVEN_DAYS_MS) {
    return fail(422, 'observed_time_out_of_range')
  }
  if (!CLASSES.has(body.evidence_class as EvidenceClass)) return fail(422, 'unsupported_evidence_class')
  if (body.qualification_policy_version !== PASSIVE_QUALIFICATION_POLICY) {
    return fail(422, 'unsupported_qualification_policy')
  }
  const qualificationFacts = parseFacts(body.qualification_facts)
  if (!qualificationFacts) return fail(400, 'invalid_qualification_facts')
  const queryStartedAt = body.query_started_at === null ? null : iso(body.query_started_at)
  const queryEndedAt = body.query_ended_at === null ? null : iso(body.query_ended_at)
  if ((body.query_started_at !== null && !queryStartedAt) || (body.query_ended_at !== null && !queryEndedAt)) {
    return fail(400, 'invalid_query_interval')
  }
  if (typeof body.query_succeeded !== 'boolean') return fail(400, 'invalid_query_interval')
  if ((queryStartedAt === null) !== (queryEndedAt === null)) return fail(400, 'invalid_query_interval')
  if (queryStartedAt && queryEndedAt
      && (Date.parse(queryStartedAt) > observedMs || observedMs > Date.parse(queryEndedAt))) {
    return fail(422, 'query_does_not_contain_event')
  }
  if (body.correlation_id !== null && (
    typeof body.correlation_id !== 'string'
    || body.correlation_id.length < 1
    || body.correlation_id.length > 128
  )) return fail(400, 'invalid_correlation_id')

  return {
    ok: true,
    credential: body.credential,
    data: {
      binding_id: body.binding_id.toLowerCase(),
      event_id: body.event_id.toLowerCase(),
      sequence: body.sequence as number,
      observed_at: observedAt,
      evidence_class: body.evidence_class as EvidenceClass,
      qualification_policy_version: PASSIVE_QUALIFICATION_POLICY,
      correlation_id: body.correlation_id as string | null,
      qualification_facts: qualificationFacts,
      query_started_at: queryStartedAt,
      query_ended_at: queryEndedAt,
      query_succeeded: body.query_succeeded,
    },
  }
}

export function mapPassiveEvidenceStatus(value: unknown) {
  if (value === 'inserted' || value === 'duplicate') {
    return { httpStatus: 200, body: { ok: true, status: value } }
  }
  if (value === 'conflict' || value === 'invalid' || value === 'outside_epoch') {
    return { httpStatus: 422, body: { ok: false, status: value } }
  }
  if (value === 'revoked' || value === 'unregistered_binding' || value === 'credential_mismatch') {
    return { httpStatus: 409, body: { ok: false, status: value } }
  }
  return { httpStatus: 500, body: { ok: false, status: 'database_error' } }
}
