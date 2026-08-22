// delete-account: 真实永久注销账户与清理个人数据 (Fail-Closed & Transactional)
// 符合 Google Play Data Deletion 与 Apple App Store 5.1.1(v) 政策。
// 严格处理全部外键依赖，采用数据库事务 RPC 清理，任何错误立即阻断报错，杜绝部分删除与虚假注销。

import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(JSON.stringify({ ok: false, error: 'Server configuration error' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ ok: false, error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)
    if (userError || !user) {
      return new Response(JSON.stringify({ ok: false, error: 'Invalid user token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const uid = user.id

    // 1. 调用原子数据库存储过程 purge_user_data 清理所有表外键与数据
    const { error: purgeError } = await supabaseAdmin.rpc('purge_user_data', { target_user_id: uid })
    if (purgeError) {
      console.error('purge_user_data RPC failed:', purgeError)
      return new Response(JSON.stringify({ ok: false, error: `Database purge failed: ${purgeError.message}` }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 2. 销毁 Supabase Auth 账号 (带重试机制，确保最终一致性)
    let authDeleteSuccess = false
    let lastAuthError: any = null
    for (let attempt = 1; attempt <= 3; attempt++) {
      const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(uid)
      if (!deleteAuthError) {
        authDeleteSuccess = true
        break
      }
      lastAuthError = deleteAuthError
      console.warn(`Auth deleteUser attempt ${attempt} failed:`, deleteAuthError)
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, attempt * 500))
      }
    }

    if (!authDeleteSuccess) {
      console.error('Failed to delete auth user after 3 attempts, applying durable tombstone ban:', lastAuthError)
      // Durable tombstone: scramble email and permanently ban account so it can never be signed into or reused
      const tombstoneEmail = `deleted_${uid}@deleted.keepcontact.invalid`
      const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(uid, {
        email: tombstoneEmail,
        ban_duration: '87660000h',
        user_metadata: { account_deleted_at: new Date().toISOString(), tombstone: true },
      })
      if (banError) {
        console.error('Tombstone ban fallback failed:', banError)
        return new Response(JSON.stringify({ ok: false, error: `Auth deletion and tombstone failed: ${banError.message}` }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      return new Response(JSON.stringify({ ok: true, tombstone: true, deletedUserId: uid }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ ok: true, deletedUserId: uid }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {

    console.error('delete-account fail-closed error:', error)
    return new Response(JSON.stringify({ ok: false, error: error?.message || String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
