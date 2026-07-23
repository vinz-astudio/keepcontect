import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { purgeLocalSafetyState } from '@/features/pattern/patternStore'
import { bootstrapSession } from './authBootstrap'

interface AuthState {
  session: Session | null
  user: User | null
  loading: boolean
  /** 同步得知本地是否已存在会话凭据，供首帧乐观渲染用 */
  hasStoredAuth: boolean
  signOut: () => Promise<void>
  bootstrapError: Error | null
  bootstrapTimedOut: boolean
  retryBootstrap: () => void
}

const AuthContext = createContext<AuthState | undefined>(undefined)

/**
 * 同步判断本地是否已有 Supabase 会话凭据（cookie 优先，localStorage 兜底）。
 * 老用户开 App 时据此首帧直接进 watch，不必等异步 getSession 解析完。
 */
function readHasStoredAuth(): boolean {
  try {
    if (/(?:^|;\s*)sb-[^=;]*-auth-token(?:\.\d+)?=[^;\s]/.test(document.cookie)) {
      return true
    }
  } catch {
    /* document 不可用时忽略 */
  }
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      if (k && k.startsWith('sb-') && k.includes('-auth-token')) return true
    }
  } catch {
    /* localStorage 不可用时忽略 */
  }
  return false
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const [bootstrapError, setBootstrapError] = useState<Error | null>(null)
  const [bootstrapTimedOut, setBootstrapTimedOut] = useState(false)
  const [retryCount, setRetryCount] = useState(0)

  const hasStoredAuth = useMemo(() => readHasStoredAuth(), [])

  const retryBootstrap = useCallback(() => {
    setLoading(true)
    setBootstrapError(null)
    setBootstrapTimedOut(false)
    setRetryCount((c) => c + 1)
  }, [])

  useEffect(() => {
    if (session && window.location.pathname !== '/') {
      window.history.replaceState({}, '', '/')
    }
  }, [session])

  // Initial bounded session bootstrap
  useEffect(() => {
    let mounted = true

    const runBootstrap = async () => {
      const getSessionFn = () => supabase.auth.getSession()
      const result = await bootstrapSession(getSessionFn, 5000)
      if (!mounted) return

      if (result.timedOut) {
        setBootstrapTimedOut(true)
        setLoading(false)
      } else if (result.error) {
        setBootstrapError(result.error)
        setLoading(false)
      } else {
        setSession(result.session)
        setLoading(false)
      }
    }

    void runBootstrap()

    return () => {
      mounted = false
    }
  }, [retryCount])

  // General auth change and iOS focus refetch
  useEffect(() => {
    let mounted = true

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      if (mounted) {
        setSession(next)
        if (next) {
          setBootstrapError(null)
          setBootstrapTimedOut(false)
        }
      }
    })

    const refetch = () => {
      void supabase.auth.getSession().then(({ data }) => {
        if (mounted) {
          setSession(data.session)
        }
      })
    }
    const onVisible = () => {
      if (document.visibilityState === 'visible') refetch()
    }
    window.addEventListener('focus', refetch)
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('pageshow', refetch)

    return () => {
      mounted = false
      sub.subscription.unsubscribe()
      window.removeEventListener('focus', refetch)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('pageshow', refetch)
    }
  }, [])

  // 仅 DEV：从 .env.local 读一次性测试账号自动登录，方便本地把登录后的页面
  // 跑起来做 UI 自验。生产构建里 import.meta.env.DEV 为 false，整段会被剔除。
  useEffect(() => {
    if (!import.meta.env.DEV) return
    const env = import.meta.env as Record<string, string | undefined>
    const email = env.VITE_DEV_EMAIL
    const password = env.VITE_DEV_PASSWORD
    if (!email || !password) return
    let cancelled = false
    void supabase.auth.getSession().then(({ data }) => {
      if (cancelled || data.session) return
      void supabase.auth.signInWithPassword({ email, password })
    })
    return () => {
      cancelled = true
    }
  }, [])

  const value = useMemo<AuthState>(
    () => ({
      session,
      user: session?.user ?? null,
      loading,
      hasStoredAuth,
      signOut: async () => {
        // KCA-04：先清本机安全状态（手势哈希/openAlert），保证即使网络登出挂起
        // 也不会把上一个账户的凭据留给下一个登录者。
        purgeLocalSafetyState()
        await supabase.auth.signOut()
      },
      bootstrapError,
      bootstrapTimedOut,
      retryBootstrap,
    }),
    [session, loading, hasStoredAuth, bootstrapError, bootstrapTimedOut, retryBootstrap],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthState {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth 必须在 <AuthProvider> 内使用')
  return ctx
}
