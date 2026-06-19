// push-dispatch：扫描未推送的站内通知，向收件人的所有 Web Push 订阅发送，标记 pushed_at。
// 触发：pg_cron 每分钟 + 客户端在 SOS 后即时 invoke。
// VAPID 密钥：优先环境变量（Edge Function Secrets），回退 private.app_config（经 service-role RPC）。

import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

async function getVapid(): Promise<{
  publicKey: string
  privateKey: string
  subject: string
} | null> {
  const envPub = Deno.env.get('VAPID_PUBLIC_KEY')
  const envPriv = Deno.env.get('VAPID_PRIVATE_KEY')
  const envSub = Deno.env.get('VAPID_SUBJECT')
  if (envPub && envPriv) {
    return { publicKey: envPub, privateKey: envPriv, subject: envSub ?? 'mailto:admin@example.com' }
  }
  const { data, error } = await supabase.rpc('get_app_config')
  if (error) return null
  const cfg = data as Record<string, string>
  if (cfg.vapid_public_key && cfg.vapid_private_key) {
    return {
      publicKey: cfg.vapid_public_key,
      privateKey: cfg.vapid_private_key,
      subject: cfg.vapid_subject ?? 'mailto:admin@example.com',
    }
  }
  return null
}

Deno.serve(async () => {
  const vapid = await getVapid()
  if (!vapid) {
    return new Response(JSON.stringify({ ok: false, reason: 'vapid_not_configured' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  webpush.setVapidDetails(vapid.subject, vapid.publicKey, vapid.privateKey)

  // 取最近 24h 内未推送的通知（限批量，cron 每分钟会续扫）
  const { data: pending, error } = await supabase
    .from('notifications')
    .select('id, recipient_id, kind, body, params, alert_id')
    .is('pushed_at', null)
    .gt('created_at', new Date(Date.now() - 86_400_000).toISOString())
    .order('created_at', { ascending: true })
    .limit(100)
  if (error) {
    return new Response(JSON.stringify({ ok: false, reason: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  if (!pending || pending.length === 0) {
    return new Response(JSON.stringify({ ok: true, sent: 0, pendingCount: 0 }), {
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 收件人 → 订阅
  const recipientIds = [...new Set(pending.map((n) => n.recipient_id))]
  const { data: subs } = await supabase
    .from('push_subscriptions')
    .select('id, user_id, endpoint, p256dh, auth')
    .in('user_id', recipientIds)
  const subsByUser = new Map<string, NonNullable<typeof subs>>()
  for (const s of subs ?? []) {
    const arr = subsByUser.get(s.user_id) ?? []
    arr.push(s)
    subsByUser.set(s.user_id, arr)
  }

  // 每个收件人当前未读通知数 → 主屏图标角标
  const badgeByUser = new Map<string, number>()
  for (const uid of recipientIds) {
    const { count } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('recipient_id', uid)
      .is('read_at', null)
    badgeByUser.set(uid, count ?? 0)
  }

  let sent = 0
  const deadSubIds: string[] = []
  for (const n of pending) {
    const targets = subsByUser.get(n.recipient_id) ?? []
    // payload 给 SW：kind+params 供本地化渲染，body 作兜底，badge 更新角标
    const payload = JSON.stringify({
      kind: n.kind,
      params: n.params ?? {},
      body: n.body,
      alertId: n.alert_id,
      badge: badgeByUser.get(n.recipient_id) ?? 0,
    })
    for (const s of targets) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
          { TTL: 3600, urgency: 'high' },
        )
        sent++
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode
        if (code === 404 || code === 410) deadSubIds.push(s.id) // 订阅已失效
      }
    }
  }

  // 标记已推送（无订阅的也标记，避免反复扫）
  await supabase
    .from('notifications')
    .update({ pushed_at: new Date().toISOString() })
    .in('id', pending.map((n) => n.id))

  if (deadSubIds.length > 0) {
    await supabase.from('push_subscriptions').delete().in('id', deadSubIds)
  }

  return new Response(
    JSON.stringify({ ok: true, sent, pendingCount: pending.length, prunedSubs: deadSubIds.length }),
    { headers: { 'Content-Type': 'application/json' } },
  )
})
