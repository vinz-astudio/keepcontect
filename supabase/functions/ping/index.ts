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
  const kind = 'app'

  if (!token) {
    return new Response(JSON.stringify({ ok: false, reason: 'missing token' }), {
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

  // Store the activity pulse.
  await supabase.from('behavior_pings').insert({ user_id: uid, kind, at: now })

  // Refresh heartbeat state.
  await supabase
    .from('device_state')
    .upsert(
      { user_id: uid, status: 'normal', last_heartbeat_at: now, updated_at: now },
      { onConflict: 'user_id' },
    )

  // Becoming active again clears the false alarm: resolve open silence/
  // dark-device alerts AND remove the now-moot notifications others received
  // about this user (so they refresh away, not linger). SOS is never auto-
  // cleared by a ping — it stays until a responder confirms safe.
  const { data: stale } = await supabase
    .from('alerts')
    .select('id')
    .eq('user_id', uid)
    .eq('status', 'open')
    .in('cause', ['silence', 'dark_device'])
  if (stale && stale.length) {
    const ids = stale.map((a) => a.id as string)
    await supabase
      .from('alerts')
      .update({
        status: 'resolved',
        resolved_at: now,
        resolved_by: uid,
        updated_at: now,
      })
      .in('id', ids)
    await supabase
      .from('alert_events')
      .insert(ids.map((id) => ({ alert_id: id, actor_id: uid, kind: 'resolved' })))
    // Clear the alarm notifications everyone received for these alerts.
    await supabase.from('notifications').delete().in('alert_id', ids)
  }

  // Clear this user's own "please check in" nudges — they are active now.
  await supabase
    .from('notifications')
    .delete()
    .eq('recipient_id', uid)
    .in('kind', ['self', 'concern'])

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
