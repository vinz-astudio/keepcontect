import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

describe('Ping Endpoint Security & Database RPC Gating Contracts', () => {
  const pingFuncPath = path.resolve('supabase/functions/ping/index.ts')
  const configTomlPath = path.resolve('supabase/config.toml')

  it('asserts that the edge function parses POST requests as JSON and does not require credentials in the URL', () => {
    const source = fs.readFileSync(pingFuncPath, 'utf8')

    // Contract: The endpoint must parse JSON body (req.json())
    const parsesJson = source.includes('req.json()')
    expect(parsesJson).toBe(true) // FAIL: current function reads query searchParams

    // Contract: It should not require token to be in the URL (it should accept it from POST body/headers)
    const requiresUrlTokenOnly = source.includes("url.searchParams.get('token')") && !(source.includes('body.token') || source.includes('body?.token'))
    expect(requiresUrlTokenOnly).toBe(false) // FAIL: only extracts token from URL searchParams
  })

  it('asserts validation of token, event_id, observed_at, and source with explicit non-2xx failures', () => {
    const source = fs.readFileSync(pingFuncPath, 'utf8')

    // Contract: Endpoint must validate required payload parameters and return non-2xx status (e.g. 400 or 401)
    const validatesEventId = source.includes('event_id') && (source.includes('400') || source.includes('401'))
    const validatesObservedAt = source.includes('observed_at') || source.includes('observedAtMs') && (source.includes('400') || source.includes('401'))
    const validatesSource = source.includes('source') && (source.includes('400') || source.includes('401'))

    expect(validatesEventId).toBe(true) // FAIL: event_id is not validated
    expect(validatesObservedAt).toBe(true) // FAIL: observed_at is not validated
    expect(validatesSource).toBe(true) // FAIL: source is not returned with non-2xx status code
  })

  it('asserts that the ping function calls database RPCs rather than executing a direct table insert', () => {
    const source = fs.readFileSync(pingFuncPath, 'utf8')

    // Contract: The endpoint must call the secure RPC ('record_behavior_ping_for_user')
    // instead of performing a direct insert into the 'behavior_pings' table.
    // Whitespace tolerant regex for RPC/insert checks:
    const callsRpc = /rpc\s*\(\s*['"]record_behavior_ping_for_user['"]/.test(source)
    const doesDirectInsert = /from\s*\(\s*['"]behavior_pings['"]\s*\)\s*\.\s*insert/.test(source)

    expect(callsRpc).toBe(true) // FAIL: RPC call is not used
    expect(doesDirectInsert).toBe(false) // FAIL: endpoint performs direct table insert
  })

  it('asserts that duplicate event submissions (violating event_id uniqueness) return a status 200 to the client', () => {
    const source = fs.readFileSync(pingFuncPath, 'utf8')

    // Contract: Duplicate pings matching event_id must return 200 OK (idempotent success)
    // instead of a 500 error or RLS exception, handled in a duplicate-200 check block
    const hasDuplicate200Branch = source.includes('200') && (source.includes('duplicate') || source.includes('unique_violation') || source.includes('23505'))
    expect(hasDuplicate200Branch).toBe(true) // FAIL: duplicate handler is not implemented
  })

  it('asserts that legacy GET requests are handled in a distinct branch with rate-limiting/telemetry and do not interpolate/log token', () => {
    const source = fs.readFileSync(pingFuncPath, 'utf8')

    // Contract: Legacy GET requests must be separated, rate-limited or logged for telemetry, and must not log the token using interpolation
    const hasGetBranch = source.includes("method === 'GET'") || source.includes('method === "GET"')
    const logsTokenInterpolated = source.includes('token: ${token}') || source.includes('token:${token}')

    // Assert GET branch contains some rate limit or telemetry tracking syntax
    const hasRateLimitOrTelemetry = source.includes('rate') || source.includes('limit') || source.includes('telemetry') || source.includes('metric')

    expect(hasGetBranch).toBe(true) // FAIL: legacy GET requests do not have their own restricted handler branch
    expect(hasRateLimitOrTelemetry).toBe(true) // FAIL: GET branch lacks rate-limiting/telemetry logic
    expect(logsTokenInterpolated).toBe(false) // FAIL: logs raw token via interpolation
  })

  it('asserts that supabase/config.toml specifies an explicit verify_jwt policy for the ping function', () => {
    const configSource = fs.readFileSync(configTomlPath, 'utf8')

    // Contract: config.toml must define verify_jwt = false explicitly scoped to [functions.ping]
    // Scoped regex check:
    const hasScopedVerifyJwtFalse = /\[functions\.ping\][\s\S]*?verify_jwt\s*=\s*false/.test(configSource)

    expect(hasScopedVerifyJwtFalse).toBe(true) // FAIL: verify_jwt is not configured under functions.ping
  })
})
