// Notification feed for the native Android poller (NotifyWorker).
// DEPLOY NOTE: verify_jwt=false — it authenticates itself via the heartbeat
// token. Unlike `summary` (non-sensitive counts, bare token), this returns
// notification content (names in params), so a fresh HMAC signature is
// REQUIRED: t within 300s and sig = HMAC_SHA256(message=t, key=token) —
// the same scheme the /ping endpoint accepts for signed requests.
import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })

async function verifyHmac(token: string, t: string, sig: string): Promise<boolean> {
  try {
    const encoder = new TextEncoder()
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      encoder.encode(token),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify'],
    )
    if (sig.length !== 64 || !/^[0-9a-fA-F]+$/.test(sig)) return false
    const signatureBytes = new Uint8Array(32)
    for (let i = 0; i < 32; i++) {
      signatureBytes[i] = parseInt(sig.substring(i * 2, i * 2 + 2), 16)
    }
    return await crypto.subtle.verify('HMAC', cryptoKey, signatureBytes, encoder.encode(t))
  } catch {
    return false
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const url = new URL(req.url)
  const token = url.searchParams.get('token')
  const t = url.searchParams.get('t')
  const sig = url.searchParams.get('sig')
  const since = url.searchParams.get('since')

  if (!token || !t || !sig) return json({ ok: false, reason: 'missing auth' }, 400)

  const nowSeconds = Math.floor(Date.now() / 1000)
  const tNum = parseInt(t, 10)
  if (isNaN(tNum) || Math.abs(nowSeconds - tNum) > 300) {
    return json({ ok: false, reason: 'expired timestamp' }, 401)
  }
  if (!(await verifyHmac(token, t, sig))) {
    return json({ ok: false, reason: 'invalid signature' }, 401)
  }

  const { data: row } = await supabase
    .from('heartbeat_tokens')
    .select('user_id')
    .eq('token', token)
    .maybeSingle()
  if (!row) return json({ ok: false, reason: 'invalid token' }, 401)
  const uid = row.user_id as string

  // Undelivered = unread and newer than the client's cursor; cap the lookback
  // so a stale cursor can never dump ancient history as fresh notifications.
  const weekAgo = new Date(Date.now() - 7 * 86_400_000).toISOString()
  let cursor = weekAgo
  if (since) {
    const parsed = Date.parse(since)
    if (!Number.isNaN(parsed) && parsed > Date.parse(weekAgo)) {
      cursor = new Date(parsed).toISOString()
    }
  }

  const { data: notifications, error } = await supabase
    .from('notifications')
    .select('id, kind, params, alert_id, body, created_at')
    .eq('recipient_id', uid)
    .is('read_at', null)
    .gt('created_at', cursor)
    .order('created_at', { ascending: true })
    .limit(20)

  if (error) {
    console.error('notify-feed query failed:', error)
    return json({ ok: false, reason: 'query failed' }, 500)
  }

  return json({ ok: true, notifications: notifications ?? [] })
})
