export interface CoverageLeaseRequest {
  token: string
  client_id: string
  channel: 'android-apk' | 'tauri' | 'ios-app'
  collector_contract: 'android-passive-v1' | 'tauri-idle-v1' | 'ios-wake-v1'
  collector_state: 'operational'
  capability_sha256: string
  observed_at: string
  event_id: string
}

export type CoverageLeaseFailureCode =
  | 'malformed_json'
  | 'invalid_request'
  | 'invalid_capability_hash'
  | 'invalid_event_id'
  | 'invalid_observed_time'
  | 'unsupported_channel'
  | 'unsupported_contract'
  | 'unsupported_state'

export type CoverageLeaseParseResult =
  | { ok: true; data: CoverageLeaseRequest }
  | { ok: false; status: 400 | 422; code: CoverageLeaseFailureCode }

export type CoverageLeaseSqlStatus =
  | 'inserted'
  | 'duplicate'
  | 'disabled'
  | 'invalid'
  | 'unsupported'
  | 'unregistered_client'
  | 'capability_mismatch'

export interface CoverageLeaseHttpResult {
  httpStatus: number
  body: { ok: boolean; status: CoverageLeaseSqlStatus | 'database_error' }
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const sha256Pattern = /^[0-9a-f]{64}$/i
const MAX_OBSERVED_DRIFT_MS = 5 * 60 * 1000

function fail(
  status: 400 | 422,
  code: CoverageLeaseFailureCode,
): CoverageLeaseParseResult {
  return { ok: false, status, code }
}

export function parseCoverageLeaseRequest(
  raw: string,
  nowMs = Date.now(),
): CoverageLeaseParseResult {
  let value: unknown
  try {
    value = JSON.parse(raw)
  } catch {
    return fail(400, 'malformed_json')
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return fail(400, 'invalid_request')
  }

  const body = value as Record<string, unknown>
  if (typeof body.token !== 'string' || body.token.length === 0) {
    return fail(400, 'invalid_request')
  }
  if (
    typeof body.client_id !== 'string' ||
    body.client_id.trim().length === 0 ||
    body.client_id.trim().length > 64
  ) {
    return fail(400, 'invalid_request')
  }
  // iOS reports from its background wakes: the silent push the passive-poll
  // job sends every fifteen minutes, and HealthKit background delivery, which
  // is the one mechanism that relaunches a force-quit app. Its cadence matches
  // Android's at the median and has a much heavier tail, so the honest place
  // to absorb that difference is the interval builder's gap allowance, not
  // here — this only decides whether the channel is one we know.
  const contractsByChannel = {
    'android-apk': 'android-passive-v1',
    'tauri': 'tauri-idle-v1',
    'ios-app': 'ios-wake-v1',
  } as const
  if (!Object.hasOwn(contractsByChannel, body.channel as string)) {
    return fail(422, 'unsupported_channel')
  }
  const expectedContract =
    contractsByChannel[body.channel as keyof typeof contractsByChannel]
  if (body.collector_contract !== expectedContract) {
    return fail(422, 'unsupported_contract')
  }
  if (body.collector_state !== 'operational') {
    return fail(422, 'unsupported_state')
  }
  if (
    typeof body.capability_sha256 !== 'string' ||
    !sha256Pattern.test(body.capability_sha256)
  ) {
    return fail(400, 'invalid_capability_hash')
  }
  if (
    typeof body.event_id !== 'string' ||
    !uuidPattern.test(body.event_id)
  ) {
    return fail(400, 'invalid_event_id')
  }
  if (typeof body.observed_at !== 'string') {
    return fail(400, 'invalid_observed_time')
  }
  const observedMs = Date.parse(body.observed_at)
  if (!Number.isFinite(observedMs)) {
    return fail(400, 'invalid_observed_time')
  }
  if (Math.abs(nowMs - observedMs) > MAX_OBSERVED_DRIFT_MS) {
    return fail(422, 'invalid_observed_time')
  }

  return {
    ok: true,
    data: {
      token: body.token,
      client_id: body.client_id.trim(),
      channel: body.channel,
      collector_contract: expectedContract,
      collector_state: 'operational',
      capability_sha256: body.capability_sha256.toLowerCase(),
      observed_at: new Date(observedMs).toISOString(),
      event_id: body.event_id.toLowerCase(),
    },
  }
}

export function mapCoverageLeaseStatus(value: unknown): CoverageLeaseHttpResult {
  switch (value) {
    case 'inserted':
    case 'duplicate':
      return { httpStatus: 200, body: { ok: true, status: value } }
    case 'disabled':
      return { httpStatus: 503, body: { ok: false, status: value } }
    case 'invalid':
    case 'unsupported':
      return { httpStatus: 422, body: { ok: false, status: value } }
    case 'unregistered_client':
    case 'capability_mismatch':
      return { httpStatus: 409, body: { ok: false, status: value } }
    default:
      return {
        httpStatus: 500,
        body: { ok: false, status: 'database_error' },
      }
  }
}
