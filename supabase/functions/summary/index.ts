// Token-authenticated tiny summary for the desktop tray.
// Returns ONLY non-sensitive counts/flags (no names, addresses, or contents):
//   alerted = 本人当前是否有开放告警(异常沉默/SOS)
//   unread  = 未读通知数
//   today   = 今日(UTC)报活次数
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const token = new URL(req.url).searchParams.get('token')
  if (!token) return json({ ok: false, reason: 'missing token' }, 400)

  const { data: row } = await supabase
    .from('heartbeat_tokens')
    .select('user_id')
    .eq('token', token)
    .maybeSingle()
  if (!row) return json({ ok: false, reason: 'invalid token' }, 401)
  const uid = row.user_id as string

  const start = new Date()
  start.setUTCHours(0, 0, 0, 0)

  const [alerts, notifs, pings] = await Promise.all([
    supabase
      .from('alerts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', uid)
      .eq('status', 'open'),
    supabase
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('recipient_id', uid)
      .is('read_at', null),
    supabase
      .from('behavior_pings')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', uid)
      .gte('at', start.toISOString()),
  ])

  return json({
    ok: true,
    alerted: (alerts.count ?? 0) > 0,
    unread: notifs.count ?? 0,
    today: pings.count ?? 0,
  })
})
