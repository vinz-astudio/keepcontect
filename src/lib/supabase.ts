import { createBrowserClient } from '@supabase/ssr'
import { createClient } from '@supabase/supabase-js'
import { Capacitor } from '@capacitor/core'
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

// 混合存储引擎：iOS PWA 独立主屏进程需要 cookie 传递与继承 OAuth 会话，而 iOS Native (Capacitor/TestFlight)
// 在 WKWebView 进程重启时会清理无 max-age 的 cookie。
// 混合引擎同时写入 document.cookie (带 1年 max-age) 和 localStorage；
// 当 WKWebView/PWA 丢失单侧存储时，自动交叉恢复会话，实现 100% 持久保持登录。
const hybridStorage = {
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

const authOptions = {
  persistSession: true,
  autoRefreshToken: true,
  detectSessionInUrl: true,
  flowType: 'pkce' as const,
  storage: hybridStorage,
}

const globalOptions = {
  // iOS 主屏 PWA 的 fetch 可能全局失败(TypeError)，自动降级 XHR
  fetch: resilientFetch,
}

// 两端的存储需求是相反的，必须分叉，一个全局选择必然顾此失彼。
//
// Web/PWA 用 createBrowserClient：iOS 主屏 PWA 是独立进程，OAuth 回跳要靠
// cookie 才能把会话交接过来。
//
// 原生(Capacitor)用标准 createClient：createBrowserClient 会用自己的 cookie
// storage **覆盖**调用方传入的 auth.storage(见 @supabase/ssr 的
// createBrowserClient，storage 排在 ...options.auth 之后)，于是会话只落在
// cookie 里；而 WKWebView 进程重启会清掉 cookie，App 每次冷启动都变成未登录。
// 走标准 createClient 时 storage 才真正生效，会话落在 localStorage，能活过
// 进程重启。
export const supabase = Capacitor.isNativePlatform()
  ? createClient<Database>(url, anonKey, {
      global: globalOptions,
      auth: authOptions,
    })
  : createBrowserClient<Database>(url, anonKey, {
      global: globalOptions,
      auth: authOptions,
    })
