// Asks iOS devices for liveness evidence.
//
// Android and desktop can observe activity on their own — Android is woken by
// a system broadcast on unlock, the desktop app polls the idle timer. iOS gives
// third parties neither: an unlock is delivered only to a process that is
// already running, and there is no readable unlock history to reconstruct
// afterwards. So on iOS the server has to do the asking.
//
// This sends a silent (content-available) push. iOS launches the app into the
// background to handle it, which is why the client needs no keepalive and no
// persistent location session. The app answers by handing over its local
// record; a locked device deliberately answers with nothing, because
// reachability is not liveness.
//
// What this function does NOT do is decide anything. It only knocks. Whether
// silence means trouble is `process_escalations`' judgement, and a device that
// never answers must still be treated as unusual — that authority stays in the
// database, not here.

import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

interface ServiceAccount {
  client_email: string
  private_key: string
  project_id: string
  token_uri: string
}

/** Same source and precedence as push-dispatch, so both share one credential. */
async function getServiceAccount(): Promise<ServiceAccount | null> {
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
    // fall through
  }
  return null
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '')
  const binary = atob(body)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input
  let binary = ''
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

let cachedToken: { token: string; expiresAt: number } | null = null

async function accessToken(sa: ServiceAccount): Promise<string | null> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.token
  }
  try {
    const now = Math.floor(Date.now() / 1000)
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
    const claims = base64url(JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: sa.token_uri,
      iat: now,
      exp: now + 3600,
    }))
    const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToArrayBuffer(sa.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    )
    const signature = new Uint8Array(
      await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`)),
    )
    const assertion = `${header}.${claims}.${base64url(signature)}`
    const res = await fetch(sa.token_uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    })
    const json = await res.json()
    if (!json.access_token) return null
    cachedToken = { token: json.access_token, expiresAt: Date.now() + 3500_000 }
    return cachedToken.token
  } catch (e) {
    console.error('FCM token exchange failed:', e)
    return null
  }
}

/** One silent knock. Returns 'sent' | 'dead' | 'failed'. */
async function knock(
  sa: ServiceAccount,
  token: string,
  deviceToken: string,
): Promise<'sent' | 'dead' | 'failed'> {
  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            data: { kind: 'passive-poll' },
            apns: {
              headers: {
                // background type + priority 5 is what makes APNs treat this as
                // a silent push. Priority 10 on a content-available payload is
                // rejected outright by Apple.
                'apns-push-type': 'background',
                'apns-priority': '5',
              },
              payload: { aps: { 'content-available': 1 } },
            },
          },
        }),
      },
    )
    if (res.ok) return 'sent'
    const body = await res.text().catch(() => '')
    if (res.status === 404 || body.includes('UNREGISTERED') || body.includes('INVALID_ARGUMENT')) {
      return 'dead'
    }
    console.warn(`passive-poll send failed ${res.status}: ${body.slice(0, 200)}`)
    return 'failed'
  } catch {
    return 'failed'
  }
}

Deno.serve(async () => {
  const sa = await getServiceAccount()
  if (!sa) {
    return new Response(JSON.stringify({ ok: false, reason: 'no service account' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  const token = await accessToken(sa)
  if (!token) {
    return new Response(JSON.stringify({ ok: false, reason: 'no access token' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const { data: tokens, error } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('platform', 'ios')

  if (error) {
    return new Response(JSON.stringify({ ok: false, reason: 'query failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  if (!tokens?.length) {
    return new Response(JSON.stringify({ ok: true, knocked: 0 }), {
      headers: { 'Content-Type': 'application/json' },
    })
  }

  let knocked = 0
  const dead: string[] = []
  for (const row of tokens) {
    const result = await knock(sa, token, row.token as string)
    if (result === 'sent') knocked++
    if (result === 'dead') dead.push(row.token as string)
  }

  // A token FCM calls unregistered belongs to an app that was deleted or
  // reinstalled. Keeping it would make this function look busier than it is.
  if (dead.length) {
    await supabase.from('push_tokens').delete().in('token', dead)
  }

  return new Response(JSON.stringify({ ok: true, knocked, dead: dead.length }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
