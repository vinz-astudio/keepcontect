// Token-authenticated passive ping endpoint. It records only a timestamped
// coarse activity signal, then refreshes the user's heartbeat state.

import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization',
}

const eligibleSources = ['installed_pwa', 'tauri', 'capacitor', 'shortcut', 'manual', 'app']
const uuidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const method = req.method
  const url = new URL(req.url)

  if (method === 'POST') {
    let body: any = null
    try {
      body = await req.json()
    } catch {
      return new Response(JSON.stringify({ ok: false, reason: 'malformed json body' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    let token = body?.token
    const authHeader = req.headers.get('Authorization')
    if (authHeader) {
      if (authHeader.startsWith('Bearer ')) {
        token = authHeader.substring(7)
      } else {
        return new Response(JSON.stringify({ ok: false, reason: 'invalid authorization header format' }), {
          status: 400,
          headers: { ...cors, 'Content-Type': 'application/json' },
        })
      }
    }

    if (!token || typeof token !== 'string') {
      return new Response(JSON.stringify({ ok: false, reason: 'missing or invalid token' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const event_id = body?.event_id
    if (!event_id || typeof event_id !== 'string' || !uuidRegex.test(event_id)) {
      return new Response(JSON.stringify({ ok: false, reason: 'missing or invalid event_id' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const observed_at = body?.observed_at
    if (!observed_at || typeof observed_at !== 'string' || isNaN(Date.parse(observed_at))) {
      return new Response(JSON.stringify({ ok: false, reason: 'missing or invalid observed_at' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const source = body?.source
    if (!source || typeof source !== 'string' || !eligibleSources.includes(source)) {
      return new Response(JSON.stringify({ ok: false, reason: 'missing or invalid source' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    // Lookup token without logging it
    const { data: row, error: tokenErr } = await supabase
      .from('heartbeat_tokens')
      .select('user_id')
      .eq('token', token)
      .maybeSingle()

    if (tokenErr || !row) {
      return new Response(JSON.stringify({ ok: false, reason: 'invalid token' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const uid = row.user_id as string

    const { data: status, error: pingError } = await supabase.rpc('record_behavior_ping_for_user', {
      _user_id: uid,
      _event_id: event_id,
      _observed_at: observed_at,
      _source: source,
      _kind: 'app'
    })

    if (pingError) {
      console.error('Failed to record behavior ping:', pingError)
      return new Response(JSON.stringify({ ok: false, reason: 'database error' }), {
        status: 500,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    if (status === 'inserted' || status === 'coalesced') {
      return new Response(JSON.stringify({ ok: true, status }), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    } else if (status === 'duplicate') {
      return new Response(JSON.stringify({ ok: true, status: 'duplicate' }), {
        status: 200,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    } else if (status === 'invalid') {
      return new Response(JSON.stringify({ ok: false, reason: 'invalid' }), {
        status: 422,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    } else {
      // Fail closed (500) for unexpected or null status
      return new Response(JSON.stringify({ ok: false, reason: 'internal server error' }), {
        status: 500,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }
  }

  if (method === 'GET') {
    const token = url.searchParams.get('token')
    const sourceParam = url.searchParams.get('source')

    if (!token || typeof token !== 'string') {
      return new Response(JSON.stringify({ ok: false, reason: 'missing token' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const rawSource = sourceParam || 'app'
    if (!eligibleSources.includes(rawSource)) {
      return new Response(JSON.stringify({ ok: false, reason: 'invalid source' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const { data: row, error: tokenErr } = await supabase
      .from('heartbeat_tokens')
      .select('user_id')
      .eq('token', token)
      .maybeSingle()

    if (tokenErr || !row) {
      return new Response(JSON.stringify({ ok: false, reason: 'invalid token' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    const uid = row.user_id as string
    const event_id = crypto.randomUUID()
    const observed_at = new Date().toISOString()

    // Legacy GET telemetry: db coalescing and 5-minute rate bound are enforced in the shared DB RPC
    console.log("Legacy GET telemetry rate-limit check: heartbeat received")

    const { data: status, error: pingError } = await supabase.rpc('record_behavior_ping_for_user', {
      _user_id: uid,
      _event_id: event_id,
      _observed_at: observed_at,
      _source: rawSource,
      _kind: 'app'
    })

    if (pingError) {
      console.error('Failed to record behavior ping:', pingError)
      return new Response(JSON.stringify({ ok: false, reason: 'database error' }), {
        status: 500,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }

    if (status === 'inserted' || status === 'coalesced') {
      return new Response(JSON.stringify({ ok: true, status }), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    } else if (status === 'duplicate') {
      return new Response(JSON.stringify({ ok: true, status: 'duplicate' }), {
        status: 200,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    } else if (status === 'invalid') {
      return new Response(JSON.stringify({ ok: false, reason: 'invalid' }), {
        status: 422,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    } else {
      // Fail closed (500) for unexpected or null status
      return new Response(JSON.stringify({ ok: false, reason: 'internal server error' }), {
        status: 500,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }
  }

  // Reject other methods
  return new Response(JSON.stringify({ ok: false, reason: 'method not allowed' }), {
    status: 405,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
})
