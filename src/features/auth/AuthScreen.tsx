import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'
import { useEffect, useState, type FormEvent } from 'react'
import {
  initialAuthCode,
  initialAuthError,
  initialAuthKind,
  supabase,
} from '@/lib/supabase'
import { peekPendingInvite } from '@/features/invites/inviteLink'
import {
  backupVerifier,
  clearVerifierBackup,
  hasVerifierInStorage,
  restoreVerifier,
} from '@/features/auth/pkceBackup'
import { xhrFetch } from '@/lib/resilientFetch'
import { InstallCard } from '@/features/install/InstallCard'
import { SUPABASE_ANON_KEY, SUPABASE_URL } from '@/lib/config'
import { authRedirectUrl } from '@/features/auth/authRedirect'
import { LangToggle, useI18n } from '@/lib/i18n'
import './AuthScreen.css'

import { APP_VERSION } from '@/lib/version'

type Mode = 'signin' | 'signup'
type SocialProvider = 'google' | 'apple' | 'facebook'

const BUILD_TAG = `v${APP_VERSION}`

/** 网络探针：fetch 与 XHR 双通道分别测 */
async function probeNetwork(): Promise<string> {
  const url = `${SUPABASE_URL}/auth/v1/settings`
  const headers = { apikey: SUPABASE_ANON_KEY }
  let f: string
  try {
    const r = await fetch(url, { method: 'GET', headers })
    f = `net:${r.status}`
  } catch (e) {
    f = `net:FAIL(${(e as Error).message})`
  }
  let x: string
  try {
    const r = await xhrFetch(url, { method: 'GET', headers })
    x = `xhr:${r.status}`
  } catch (e) {
    x = `xhr:FAIL(${(e as Error).message})`
  }
  return `${f} ${x}`
}

// 存储探针：发起 OAuth 时在 localStorage+cookie 各种一个标记；
// 落地诊断时报告标记是否可见 → 判定发起与落地是否同一存储上下文。
function plantStorageMarker() {
  try {
    localStorage.setItem('kc.oauth_marker', String(Date.now()))
  } catch { /* ignore */ }
  try {
    document.cookie = 'kc_oauth_marker=1; path=/; max-age=600; secure; samesite=lax'
  } catch { /* ignore */ }
}

function probeStorageMarker(): string {
  let ls = 'N'
  let ck = 'N'
  let vInit = '?'
  let vNow = 'N'
  let sess = 'N'
  try {
    ls = localStorage.getItem('kc.oauth_marker') ? 'Y' : 'N'
    vInit = localStorage.getItem('kc.verifier_at_init') ?? '?'
  } catch { /* ignore */ }
  try {
    ck = document.cookie.includes('kc_oauth_marker') ? 'Y' : 'N'
    vNow = document.cookie.includes('-code-verifier') ? 'Y' : 'N'
    sess = document.cookie.includes('-auth-token') ? 'Y' : 'N'
  } catch { /* ignore */ }
  const standalone = window.matchMedia?.('(display-mode: standalone)').matches
    ? 'Y'
    : 'N'
  return `ls:${ls} ck:${ck} vInit:${vInit} vNow:${vNow} sess:${sess} standalone:${standalone} ${BUILD_TAG}`
}

const SOCIAL: Array<{ provider: SocialProvider; label: string; icon: string }> = [
  { provider: 'google', label: 'Google', icon: 'G' },
  { provider: 'apple', label: 'Apple', icon: '' },
  { provider: 'facebook', label: 'Facebook', icon: 'f' },
]

export function AuthScreen() {
  const { t } = useI18n()
  const [mode, setMode] = useState<Mode>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [busy, setBusy] = useState(false)
  // OAuth 失败时 Supabase 重定向回来、错误在 URL 里，由 supabase.ts 模块加载时捕获
  const [error, setError] = useState<string | null>(initialAuthError)
  const [notice, setNotice] = useState<string | null>(null)
  // 自动兑换耗尽后展示"完成登录"手动按钮（用户手势触发的请求在 iOS 上更可靠）
  const [showCompleteLogin, setShowCompleteLogin] = useState(false)
  // 版本号连点 3 次 → 卸载 Service Worker + 清缓存（排查 SW 与 fetch 纠缠）
  const [tapCount, setTapCount] = useState(0)

  async function onVersionTap() {
    const n = tapCount + 1
    setTapCount(n)
    if (n < 3) return
    setTapCount(0)
    try {
      const regs = await navigator.serviceWorker.getRegistrations()
      await Promise.all(regs.map((r) => r.unregister()))
      const keys = await caches.keys()
      await Promise.all(keys.map((k) => caches.delete(k)))
      setNotice('Service Worker 已卸载，正在重载…')
      setTimeout(() => window.location.reload(), 600)
    } catch (e) {
      setError(`SW 卸载失败: ${(e as Error).message}`)
    }
  }

  // 单次兑换尝试：verifier 缺失则从备份恢复后再换
  async function attemptExchange(code: string): Promise<string | null> {
    if (!hasVerifierInStorage() && !restoreVerifier()) {
      return 'verifier 备份不可用'
    }
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      clearVerifierBackup()
      return null
    }
    return error.message
  }

  // 自救 + 诊断：首次自动兑换被 iOS 掐死时（TypeError、gotrue 已删 verifier），
  // 恢复备份并在 ~10s 窗口内多次重试；耗尽后亮出手动按钮 + 完整诊断。
  useEffect(() => {
    if (!initialAuthKind) return
    setNotice('正在完成登录… / Finishing sign-in…')
    let cancelled = false

    const run = async () => {
      const initResult = await supabase.auth
        .initialize()
        .catch((e: Error) => ({ error: e }))
      const initErr =
        (initResult as { error?: { message?: string } | null }).error?.message ??
        'none'

      const sessionReady = async () =>
        (await supabase.auth.getSession()).data.session != null

      if (await sessionReady()) {
        clearVerifierBackup()
        return
      }

      if (initialAuthKind === 'code' && initialAuthCode) {
        let lastErr = ''
        const delays = [0, 1800, 3000, 5000] // 累计约 10s，等 iOS 网络栈恢复
        for (const d of delays) {
          if (d > 0) await new Promise((r) => setTimeout(r, d))
          if (cancelled) return
          const err = await attemptExchange(initialAuthCode)
          if (err === null) return // 成功，onAuthStateChange 切主页
          lastErr = err
          if (/flow state|already used|expired/i.test(lastErr)) break
        }
        if (cancelled) return
        if (await sessionReady()) {
          clearVerifierBackup()
          return
        }
        const net = await probeNetwork()
        console.warn('oauth-diag', probeStorageMarker(), net, initErr, lastErr)
        setNotice(null)
        setShowCompleteLogin(true)
        setError(t('auth.oauthFail'))
      } else {
        console.warn('oauth-diag', probeStorageMarker(), initErr, initialAuthKind)
        setNotice(null)
        setError(t('auth.oauthFail'))
      }
    }

    const timer = window.setTimeout(() => void run(), 1200)
    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [])

  // 手动完成登录（用户手势上下文）
  async function completeLoginManually() {
    if (!initialAuthCode) return
    setError(null)
    setNotice('正在完成登录… / Finishing sign-in…')
    const err = await attemptExchange(initialAuthCode)
    if (err === null) return
    const net = await probeNetwork()
    console.warn('oauth-diag-manual', probeStorageMarker(), net, err)
    setNotice(null)
    setError(t('auth.oauthFail'))
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: { display_name: displayName || null },
            emailRedirectTo: authRedirectUrl(),
          },
        })
        if (error) throw error
        // 若项目开启了邮箱确认，session 会为空，需用户点确认邮件
        if (!data.session) {
          setNotice(t('auth.confirmEmail'))
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        })
        if (error) throw error
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : t('auth.fail'))
    } finally {
      setBusy(false)
    }
  }
  async function social(provider: SocialProvider) {
    setError(null)
    plantStorageMarker()
    // skipBrowserRedirect：先拿 URL，确认 verifier 已写入存储后再跳转
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: authRedirectUrl(),
        skipBrowserRedirect: true,
        queryParams: {
          prompt: 'select_account',
        },
      },
    })
    if (error || !data?.url) {
      setError(error?.message ?? 'OAuth URL missing')
      return
    }
    // 备份 verifier：首次兑换若被 iOS 掐死（verifier 被删），落地后可恢复重试
    const backedUp = backupVerifier()
    try {
      localStorage.setItem('kc.verifier_at_init', backedUp ? 'Y' : 'N')
    } catch { /* ignore */ }
    if (Capacitor.isNativePlatform()) {
      await Browser.open({ url: data.url })
    } else {
      window.location.assign(data.url)
    }
  }

  const pendingInvite = peekPendingInvite()

  return (
    <div className="auth">
      <div className="auth__card">
        <LangToggle className="auth__lang" />
        <span className="auth__logo" aria-hidden>
          ◉
        </span>
        <h1 className="auth__title">Keep Contact</h1>
        <p className="auth__subtitle">
          {mode === 'signin' ? t('auth.subtitle.signin') : t('auth.subtitle.signup')}
        </p>

        {pendingInvite && (
          <p className="auth__notice">{t(`auth.invite.${pendingInvite.kind}`)}</p>
        )}

        {showCompleteLogin && (
          <button
            type="button"
            className="auth__submit"
            style={{ marginBottom: '1rem' }}
            onClick={() => void completeLoginManually()}
          >
            完成登录 / Complete sign-in
          </button>
        )}

        <div className="auth__social">
          {SOCIAL.map(({ provider, label, icon }) => (
            <button
              key={provider}
              type="button"
              className={`auth__socialbtn auth__socialbtn--${provider}`}
              onClick={() => void social(provider)}
            >
              <span className="auth__socialicon" aria-hidden>
                {icon}
              </span>
              {label}
            </button>
          ))}
        </div>

        <div className="auth__divider">
          <span>{t('auth.or')}</span>
        </div>

        <form className="auth__form" onSubmit={onSubmit}>
          {mode === 'signup' && (
            <label className="auth__field">
              <span>{t('auth.nickname')}</span>
              <input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder={t('auth.nickname.ph')}
                autoComplete="name"
              />
            </label>
          )}
          <label className="auth__field">
            <span>{t('auth.email')}</span>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              autoComplete="email"
            />
          </label>
          <label className="auth__field">
            <span>{t('auth.password')}</span>
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder={t('auth.password.ph')}
              autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
            />
          </label>

          {error && <p className="auth__error">{error}</p>}
          {notice && <p className="auth__notice">{notice}</p>}

          <button type="submit" className="auth__submit" disabled={busy}>
            {busy
              ? t('auth.busy')
              : mode === 'signin'
                ? t('auth.signin')
                : t('auth.signup')}
          </button>
        </form>

        <button
          type="button"
          className="auth__switch"
          onClick={() => {
            setMode(mode === 'signin' ? 'signup' : 'signin')
            setError(null)
            setNotice(null)
          }}
        >
          {mode === 'signin' ? t('auth.toSignup') : t('auth.toSignin')}
        </button>

        <InstallCard compact />

        <p className="auth__build" onClick={() => void onVersionTap()}>
          {BUILD_TAG}
        </p>
      </div>
    </div>
  )
}
