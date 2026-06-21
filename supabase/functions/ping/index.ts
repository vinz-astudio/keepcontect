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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const url = new URL(req.url)
  const token = url.searchParams.get('token')
  const kind = 'app'

  if (!token) {
    return new Response(JSON.stringify({ ok: false, reason: 'missing token' }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
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
