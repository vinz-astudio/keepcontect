// push-dispatch：扫描未推送的站内通知，向收件人的所有 Web Push 订阅发送，标记 pushed_at。
// 另有 FCM 快路径(ADR-0004 Phase 2)：对注册了 FCM token 的原生 Android 设备发
// data-only 空唤醒(不带任何内容)，设备被唤醒后自行从 notify-feed 拉取通知——
// 通知内容永不经过 Google。凭据缺失时该分支静默跳过，Web Push 不受影响。
// 触发：pg_cron 每分钟 + 客户端在 SOS 后即时 invoke。
// VAPID/FCM 凭据：优先环境变量（Edge Function Secrets），回退 private.app_config。

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

// ---- FCM (data-only wake tickle) ----

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
  token_uri: string
}

async function getFcmServiceAccount(): Promise<ServiceAccount | null> {
  const raw =
    Deno.env.get('FCM_SERVICE_ACCOUNT') ??
    ((await supabase.rpc('get_app_config')).data as Record<string, string> | null)
      ?.fcm_service_account
  if (!raw) return null
  try {
    const sa = JSON.parse(raw)
    if (sa.project_id && sa.client_email && sa.private_key) {
      sa.token_uri = sa.token_uri || 'https://oauth2.googleapis.com/token'
      return sa as ServiceAccount
    }
  } catch {
    /* malformed secret */
  }
  return null
}

function b64url(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '')
  const bin = atob(body)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes
}

// Access-token cache: edge isolates are reused between invocations, so this
// avoids one OAuth round-trip per cron tick most of the time.
let cachedFcmToken: { token: string; expiresAt: number } | null = null

function normalizeName(value: unknown): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : ''
}

function paramsWithRecipientMark(
  params: unknown,
  recipientId: string,
  recipientName?: string | null,
): Record<string, unknown> {
  const p =
    params && typeof params === 'object' && !Array.isArray(params)
      ? { ...(params as Record<string, unknown>) }
      : {}
  const targetId = String(p.target_id ?? p.targetId ?? p.user_id ?? p.userId ?? '')
  const targetName = normalizeName(p.target)
  const nameMatches =
    targetName.length > 0 && targetName === normalizeName(recipientName)
  p.target_is_recipient =
    p.target_is_recipient === true ||
    p.target_is_recipient === 'true' ||
    (targetId.length > 0 && targetId === recipientId) ||
    nameMatches
  return p
}

async function fcmAccessToken(sa: ServiceAccount): Promise<string | null> {
  if (cachedFcmToken && Date.now() < cachedFcmToken.expiresAt - 60_000) {
    return cachedFcmToken.token
  }
  try {
    const enc = new TextEncoder()
    const now = Math.floor(Date.now() / 1000)
    const header = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
    const claims = b64url(enc.encode(JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: sa.token_uri,
      iat: now,
      exp: now + 3600,
    })))
    const input = `${header}.${claims}`
    const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToDer(sa.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    )
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(input))
    const jwt = `${input}.${b64url(new Uint8Array(sig))}`
    const res = await fetch(sa.token_uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${jwt}`,
    })
    if (!res.ok) return null
    const j = await res.json()
    if (!j.access_token) return null
    cachedFcmToken = {
      token: j.access_token,
      expiresAt: Date.now() + (Number(j.expires_in) || 3600) * 1000,
    }
    return cachedFcmToken.token
  } catch (e) {
    console.error('FCM token exchange failed:', e)
    return null
  }
}

/** Send one data-only high-priority tickle. Returns 'sent' | 'dead' | 'failed'. */
async function sendTickle(
  sa: ServiceAccount,
  accessToken: string,
  deviceToken: string,
): Promise<'sent' | 'dead' | 'failed'> {
  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            data: { kind: 'tickle' },
            android: { priority: 'HIGH' },
          },
        }),
      },
    )
    if (res.ok) return 'sent'
    const body = await res.text().catch(() => '')
    if (res.status === 404 || body.includes('UNREGISTERED') || body.includes('INVALID_ARGUMENT')) {
      return 'dead'
    }
    console.warn(`FCM send failed ${res.status}: ${body.slice(0, 200)}`)
    return 'failed'
  } catch {
    return 'failed'
  }
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
  const { data: recipientProfiles } = await supabase
    .from('profiles')
    .select('id, display_name')
    .in('id', recipientIds)
  const recipientNameByUser = new Map(
    (recipientProfiles ?? []).map((p) => [p.id, p.display_name as string | null]),
  )
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
      params: paramsWithRecipientMark(
        n.params,
        n.recipient_id,
        recipientNameByUser.get(n.recipient_id),
      ),
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

  // FCM 快路径：每个收件人的每台原生设备发一次空唤醒（与通知条数无关）。
  let fcmSent = 0
  const deadFcmTokens: string[] = []
  const sa = await getFcmServiceAccount()
  if (sa) {
    const accessToken = await fcmAccessToken(sa)
    if (accessToken) {
      const { data: fcmRows } = await supabase
        .from('push_tokens')
        .select('token, user_id')
        .in('user_id', recipientIds)
      for (const row of fcmRows ?? []) {
        const result = await sendTickle(sa, accessToken, row.token)
        if (result === 'sent') fcmSent++
        else if (result === 'dead') deadFcmTokens.push(row.token)
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
  if (deadFcmTokens.length > 0) {
    await supabase.from('push_tokens').delete().in('token', deadFcmTokens)
  }

  return new Response(
    JSON.stringify({
      ok: true,
      sent,
      fcmSent,
      fcmConfigured: !!sa,
      pendingCount: pending.length,
      prunedSubs: deadSubIds.length,
      prunedFcmTokens: deadFcmTokens.length,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  )
})
