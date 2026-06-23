import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'

interface AuthState {
  session: Session | null
  user: User | null
  loading: boolean
  /** 同步得知本地是否已存在会话凭据，供首帧乐观渲染用 */
  hasStoredAuth: boolean
  signOut: () => Promise<void>
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
  const hasStoredAuth = useMemo(() => readHasStoredAuth(), [])

  useEffect(() => {
    if (session && window.location.pathname !== '/') {
      window.history.replaceState({}, '', '/')
    }
  }, [session])

  useEffect(() => {
    let mounted = true

    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return
      setSession(data.session)
      setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
    })

    // iOS PWA：OAuth 在内嵌浏览器层完成后回到 App 不会自动刷新，
    // 重新聚焦/可见时主动重查会话，把已落盘的登录捡起来。
    const refetch = () => {
      void supabase.auth.getSession().then(({ data }) => {
        if (mounted) setSession(data.session)
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

  const value = useMemo<AuthState>(
    () => ({
      session,
      user: session?.user ?? null,
      loading,
      hasStoredAuth,
      signOut: async () => {
        await supabase.auth.signOut()
      },
    }),
    [session, loading, hasStoredAuth],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthState {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth 必须在 <AuthProvider> 内使用')
  return ctx
}
