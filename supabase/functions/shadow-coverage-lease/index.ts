import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  mapCoverageLeaseStatus,
  parseCoverageLeaseRequest,
} from './contract.ts'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
}
const jsonHeaders = { ...cors, 'Content-Type': 'application/json' }

function response(
  body: { ok: boolean; status: string },
  status = 200,
): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: cors })
  }
  if (request.method !== 'POST') {
    return response({ ok: false, status: 'method_not_allowed' }, 405)
  }

  const parsed = parseCoverageLeaseRequest(await request.text())
  if (!parsed.ok) {
    return response({ ok: false, status: parsed.code }, parsed.status)
  }
  const lease = parsed.data

  const { data: tokenRow, error: tokenError } = await supabase
    .from('heartbeat_tokens')
    .select('user_id')
    .eq('token', lease.token)
    .maybeSingle()
  if (tokenError) {
    return response({ ok: false, status: 'database_error' }, 500)
  }
  if (!tokenRow?.user_id) {
    return response({ ok: false, status: 'invalid_token' }, 401)
  }

  const { data: sqlStatus, error: leaseError } = await supabase.rpc(
    'record_alert_shadow_coverage_lease_for_user',
    {
      _user_id: tokenRow.user_id,
      _client_id: lease.client_id,
      _channel: lease.channel,
      _collector_contract: lease.collector_contract,
      _collector_state: lease.collector_state,
      _capability_sha256: lease.capability_sha256,
      _observed_at: lease.observed_at,
      _event_id: lease.event_id,
    },
  )
  if (leaseError) {
    return response({ ok: false, status: 'database_error' }, 500)
  }

  const mapped = mapCoverageLeaseStatus(sqlStatus)
  return response(mapped.body, mapped.httpStatus)
})
