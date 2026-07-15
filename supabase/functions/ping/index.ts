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
  'Access-Control-Allow-Headers': 'content-type',
}

async function verifyHmac(token: string, t: string, sig: string): Promise<boolean> {
  try {
    const encoder = new TextEncoder()
    const keyBytes = encoder.encode(token)
    const messageBytes = encoder.encode(t)

    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    )

    if (sig.length !== 64 || !/^[0-9a-fA-F]+$/.test(sig)) {
      return false
    }

    const signatureBytes = new Uint8Array(32)
    for (let i = 0; i < 32; i++) {
      signatureBytes[i] = parseInt(sig.substring(i * 2, i * 2 + 2), 16)
    }

    return await crypto.subtle.verify(
      'HMAC',
      cryptoKey,
      signatureBytes,
      messageBytes
    )
  } catch (err) {
    console.error('Error verifying HMAC signature:', err)
    return false
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const url = new URL(req.url)
  const token = url.searchParams.get('token')
  const t = url.searchParams.get('t')
  const sig = url.searchParams.get('sig')
  const source = url.searchParams.get('source')
  const kind = 'app'

  if (!token) {
    return new Response(JSON.stringify({ ok: false, reason: 'missing token' }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }

  // Treat missing source as 'app' (legacy). Accept it.
  // Reject only if source is present but not in the set {installed_pwa, tauri, capacitor, shortcut, manual, app}
  const eligibleSources = ['installed_pwa', 'tauri', 'capacitor', 'shortcut', 'manual', 'app']
  const effectiveSource = source || 'app'
  if (source && !eligibleSources.includes(source)) {
    return new Response(JSON.stringify({ ok: false, reason: 'invalid source' }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }

  if (t && sig) {
    const nowSeconds = Math.floor(Date.now() / 1000)
    const tNum = parseInt(t, 10)
    if (isNaN(tNum) || Math.abs(nowSeconds - tNum) > 300) {
      return new Response(JSON.stringify({ ok: false, reason: 'expired timestamp' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }
    const isValid = await verifyHmac(token, t, sig)
    if (!isValid) {
      return new Response(JSON.stringify({ ok: false, reason: 'invalid signature' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      })
    }
  } else {
    console.warn(`Unsigned ping received for token: ${token}`)
  }

  // token -> user
  const { data: row } = await supabase
    .from('heartbeat_tokens')
    .select('user_id')
    .eq('token', token)
    .maybeSingle()
  if (!row) {
    return new Response(JSON.stringify({ ok: false, reason: 'invalid token' }), {
      status: 401,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }
  const uid = row.user_id as string
  const now = new Date().toISOString()

  // Store the activity pulse. Database triggers own all derived side effects:
  // device_state refresh, alert auto-resolution, notification cleanup, and push dispatch.
  const { error: pingError } = await supabase
    .from('behavior_pings')
    .insert({ user_id: uid, kind, at: now, source: effectiveSource })

  if (pingError) {
    console.error('Failed to insert behavior ping:', pingError)
    return new Response(JSON.stringify({ ok: false, reason: 'insert failed' }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }

  // Keep roughly 35 days of passive pings.
  await supabase
    .from('behavior_pings')
    .delete()
    .eq('user_id', uid)
    .lt('at', new Date(Date.now() - 35 * 86_400_000).toISOString())

  return new Response(JSON.stringify({ ok: true, kind }), {
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
})
