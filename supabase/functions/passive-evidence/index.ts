import { createClient } from 'npm:@supabase/supabase-js@2'
import { mapPassiveEvidenceStatus, parsePassiveEvidenceRequest } from './contract.ts'

// Deploy with verify_jwt=false. Native/Tauri requests authenticate with the
// one-time-issued collector credential; the database stores only its digest.
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
}
const headers = { ...cors, 'Content-Type': 'application/json' }

function response(body: { ok: boolean; status: string }, status: number) {
  return new Response(JSON.stringify(body), { status, headers })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return response({ ok: false, status: 'method_not_allowed' }, 405)
  const parsed = parsePassiveEvidenceRequest(await request.text())
  if (!parsed.ok) return response({ ok: false, status: parsed.code }, parsed.status)
  const event = parsed.data
  const { data, error } = await supabase.rpc('record_passive_evidence_with_credential', {
    _binding_id: event.binding_id,
    _credential: parsed.credential,
    _event_id: event.event_id,
    _sequence: event.sequence,
    _observed_at: event.observed_at,
    _evidence_class: event.evidence_class,
    _qualification_policy_version: event.qualification_policy_version,
    _correlation_id: event.correlation_id,
    _qualification_facts: event.qualification_facts,
    _query_started_at: event.query_started_at,
    _query_ended_at: event.query_ended_at,
    _query_succeeded: event.query_succeeded,
  })
  if (error) return response({ ok: false, status: 'database_error' }, 500)
  const mapped = mapPassiveEvidenceStatus(data)
  return response(mapped.body, mapped.httpStatus)
})
