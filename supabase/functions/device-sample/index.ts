// Multi-signal liveness sampling intake.
//
// Deliberately a separate function from `ping` rather than another field on it.
// `ping` is on the safety-critical path — it refreshes heartbeats and can clear
// an alert — and this endpoint must never be able to do either, however the
// payload is shaped or malformed. Keeping them apart makes that a property of
// the deployment rather than a promise in a code comment.
//
// Authentication is the same heartbeat token the passive collectors already
// hold, because these samples come from a process woken in the background with
// no user session to speak of.

import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization',
}

const uuidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ ok: false, reason: 'method not allowed' }, 405)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ ok: false, reason: 'malformed json body' }, 400)
  }

  const token = typeof body?.token === 'string' ? body.token : null
  if (!token) return json({ ok: false, reason: 'missing or invalid token' }, 400)

  const eventId = body?.event_id
  if (typeof eventId !== 'string' || !uuidRegex.test(eventId)) {
    return json({ ok: false, reason: 'missing or invalid event_id' }, 400)
  }

  const { data: row, error: tokenErr } = await supabase
    .from('heartbeat_tokens')
    .select('user_id')
    .eq('token', token)
    .maybeSingle()

  if (tokenErr || !row) return json({ ok: false, reason: 'invalid token' }, 401)

  // The token is stripped before the payload goes anywhere near the database:
  // it is a credential, not evidence, and it has no business being stored
  // alongside readings.
  const { token: _drop, event_id: _drop2, ...payload } = body

  const { data: status, error } = await supabase.rpc('record_device_sample_for_user', {
    _user_id: row.user_id,
    _event_id: eventId,
    _payload: payload,
  })

  if (error) {
    console.error('Failed to record device sample:', error)
    return json({ ok: false, reason: 'database error' }, 500)
  }

  // 'invalid' is a 200, not a 4xx, on purpose: the collector retries anything it
  // cannot distinguish from a transport failure, and a sample the server has
  // judged unusable should be dropped rather than resent forever.
  return json({ ok: status !== 'invalid', status })
})
