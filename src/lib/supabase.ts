import { createBrowserClient } from '@supabase/ssr'
import { resilientFetch } from '@/lib/resilientFetch'
import { SUPABASE_ANON_KEY, SUPABASE_URL } from '@/lib/config'
import type { Database } from '@/lib/database.types'

// OAuth 失败回跳的错误参数必须在 createClient 之前捕获——
// detectSessionInUrl 会在 client 创建时立即消费并清理 URL。
export const initialAuthError: string | null = (() => {
  try {
    const h = new URLSearchParams(window.location.hash.replace(/^#/, ''))
    const q = new URLSearchParams(window.location.search)
    return (
      h.get('error_description') ??
      q.get('error_description') ??
      h.get('error') ??
      q.get('error')
    )
  } catch {
    return null
  }
})()

// 诊断：本次加载的 URL 携带了哪种 OAuth 凭证（在 client 消费前记录）。
// 'hash'=implicit 令牌、'code'=PKCE 授权码、null=没带凭证（被中途丢弃）。
export const initialAuthKind: 'hash' | 'code' | null = (() => {
  try {
    if (window.location.hash.includes('access_token')) return 'hash'
    if (new URLSearchParams(window.location.search).has('code')) return 'code'
    return null
  } catch {
    return null
  }
})()

export const initialAuthCode: string | null = (() => {
  try {
    return new URLSearchParams(window.location.search).get('code')
  } catch {
    return null
  }
})()

export const initialHadAuthTokens: boolean = initialAuthKind !== null

const url = SUPABASE_URL
const anonKey = SUPABASE_ANON_KEY

// createBrowserClient（@supabase/ssr）：认证状态存 cookie 而非 localStorage。
// iOS 主屏 PWA 点 OAuth 时授权在内嵌浏览器层完成，该层与 PWA 不共享
// localStorage（PKCE code verifier 找不到、会话也带不回来），但共享 cookie——
// 用 cookie 存储后 verifier/会话双向可见，配合 AuthProvider 的 focus 重查闭环。
export const supabase = createBrowserClient<Database>(url, anonKey, {
  global: {
    // iOS 主屏 PWA 的 fetch 可能全局失败(TypeError)，自动降级 XHR
    fetch: resilientFetch,
  },
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
})
