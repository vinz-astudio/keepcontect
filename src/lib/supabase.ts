import { createClient } from '@supabase/supabase-js'
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

// 存储引擎：优先使用 localStorage 保证在 iOS Native (Capacitor/TestFlight) 及各端 100% 永久保持登录，
// 同时也镜像写入 document.cookie (带 1年 max-age) 满足 PWA 模式下 OAuth 跨层传参需求。
const cookieAndLocalStorage = {
  getItem: (key: string): string | null => {
    try {
      const lsVal = localStorage.getItem(key)
      if (lsVal) return lsVal
    } catch {}
    try {
      const escapedKey = key.replace(/[-[\]{}()*+?.:=\\^$|#\s]/g, '\\$&')
      const match = document.cookie.match(new RegExp(`(?:^|;\\s*)${escapedKey}=([^;]*)`))
      if (match && match[1]) {
        const decoded = decodeURIComponent(match[1])
        try { localStorage.setItem(key, decoded) } catch {}
        return decoded
      }
    } catch {}
    return null
  },
  setItem: (key: string, value: string): void => {
    try {
      localStorage.setItem(key, value)
    } catch {}
    try {
      document.cookie = `${key}=${encodeURIComponent(value)}; path=/; max-age=31536000; SameSite=Lax`
    } catch {}
  },
  removeItem: (key: string): void => {
    try {
      localStorage.removeItem(key)
    } catch {}
    try {
      document.cookie = `${key}=; path=/; max-age=0; SameSite=Lax`
    } catch {}
  },
}

export const supabase = createClient<Database>(url, anonKey, {
  global: {
    // iOS 主屏 PWA 的 fetch 可能全局失败(TypeError)，自动降级 XHR
    fetch: resilientFetch,
  },
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
    storage: cookieAndLocalStorage,
  },
})
