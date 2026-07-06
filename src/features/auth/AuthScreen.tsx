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
import { ThemeToggle } from '@/lib/theme'
import './AuthScreen.css'

import { APP_VERSION } from '@/lib/version'

type Mode = 'signin' | 'signup'
type SocialProvider = 'google' | 'facebook'

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
  // Phone Auth and Scan2Sync states
  const [authMethod, setAuthMethod] = useState<'email' | 'phone' | 'scan'>('email')
  const [phone, setPhone] = useState('')
  const [countryCode, setCountryCode] = useState('+60')
  const [scanToken, setScanToken] = useState<string | null>(null)

  // Realtime sync login subscriber
  useEffect(() => {
    if (authMethod !== 'scan' || !scanToken) return
    
    setNotice(t('auth.scan2sync.waiting'))
    const channel = supabase.channel(`scan2sync:${scanToken}`, {
      config: { broadcast: { self: false } }
    })
    
    channel.on('broadcast', { event: 'sync' }, async (payload: any) => {
      const { email, otp, access_token, refresh_token } = payload.payload
      setNotice(t('auth.scan2sync.success'))
      
      let result
      if (email && otp) {
        result = await supabase.auth.verifyOtp({
          email,
          token: otp,
          type: 'magiclink'
        })
      } else {
        result = await supabase.auth.setSession({ access_token, refresh_token })
      }

      if (result.error) {
        setError(result.error.message)
        setNotice(null)
      } else {
        setNotice(null)
      }
    })
    
    channel.subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [authMethod, scanToken, t])

  async function onPhoneSubmit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    setNotice(null)
    const fullPhone = `${countryCode}${phone}`
    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({
          phone: fullPhone,
          password,
          options: {
            data: { display_name: displayName || null },
          },
        })
        if (error) throw error
        if (!data.session) {
          setNotice(t('auth.phone.registered'))
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          phone: fullPhone,
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
        <div style={{ position: 'absolute', top: '1.25rem', right: '1.25rem', display: 'flex', gap: '0.6rem' }}>
          <ThemeToggle className="auth__lang" style={{ position: 'static' }} />
          <LangToggle className="auth__lang" style={{ position: 'static' }} />
        </div>
        <span className="auth__logo" aria-hidden style={{ display: 'block', margin: '0 auto 0.5rem', width: '48px', height: '48px' }}>
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <circle cx="12" cy="12" r="10" />
            <circle cx="12" cy="12" r="4" fill="currentColor" />
          </svg>
        </span>
        <h1 className="auth__title">Keep Contact</h1>
        <p className="auth__subtitle">
          {authMethod === 'scan'
            ? t('auth.scan2sync')
            : mode === 'signin'
              ? t('auth.subtitle.signin')
              : t('auth.subtitle.signup')}
        </p>

        <div className="auth__tabs">
          <button
            type="button"
            className={`auth__tab${authMethod === 'email' ? ' is-active' : ''}`}
            onClick={() => {
              setAuthMethod('email')
              setError(null)
              setNotice(null)
            }}
          >
            {t('auth.email')}
          </button>
          <button
            type="button"
            className={`auth__tab${authMethod === 'phone' ? ' is-active' : ''}`}
            onClick={() => {
              setAuthMethod('phone')
              setError(null)
              setNotice(null)
            }}
          >
            {t('auth.phone')}
          </button>
          <button
            type="button"
            className={`auth__tab${authMethod === 'scan' ? ' is-active' : ''}`}
            onClick={() => {
              setAuthMethod('scan')
              setError(null)
              setNotice(null)
              setScanToken(Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2))
            }}
          >
            {t('auth.scan2sync')}
          </button>
        </div>

        {pendingInvite && authMethod !== 'scan' && (
          <p className="auth__notice" style={{ marginBottom: '1rem' }}>
            {t(`auth.invite.${pendingInvite.kind}`)}
          </p>
        )}

        {showCompleteLogin && authMethod === 'email' && (
          <button
            type="button"
            className="auth__submit"
            style={{ marginBottom: '1rem' }}
            onClick={() => void completeLoginManually()}
          >
            完成登录 / Complete sign-in
          </button>
        )}

        {authMethod === 'email' && (
          <>
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
          </>
        )}

        {authMethod === 'phone' && (
          <>
            <form className="auth__form" onSubmit={onPhoneSubmit}>
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
              <div className="auth__field">
                <span>{t('auth.phone')}</span>
                <div className="auth__phone-row">
                  <select
                    className="auth__country"
                    value={countryCode}
                    onChange={(e) => setCountryCode(e.target.value)}
                  >
                    <option value="+60">🇲🇾 +60</option>
                    <option value="+65">🇸🇬 +65</option>
                    <option value="+975">🇧🇹 +975</option>
                  </select>
                  <input
                    type="tel"
                    required
                    className="auth__phone-input"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder={t('auth.phone.ph')}
                    autoComplete="tel"
                  />
                </div>
              </div>
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
          </>
        )}

        {authMethod === 'scan' && (
          <div style={{ width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            {scanToken && (
              <img
                src={`https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(
                  `keepcontact://sync?token=${scanToken}`,
                )}`}
                alt="Scan to Sync"
                style={{
                  margin: '1.2rem auto',
                  display: 'block',
                  borderRadius: '8px',
                  border: '1px solid var(--line)',
                  background: '#fff',
                  padding: '6px',
                }}
              />
            )}
            
            {error && <p className="auth__error">{error}</p>}
            {notice && <p className="auth__notice">{notice}</p>}

            <p className="auth__scan-hint" style={{ marginTop: '1rem' }}>
              {t('auth.scan2sync.desc')}
            </p>

            <button
              type="button"
              className="auth__switch"
              onClick={() => {
                setAuthMethod('email')
                setError(null)
                setNotice(null)
              }}
            >
              {t('auth.scan2sync.cancel')}
            </button>
          </div>
        )}

        {authMethod !== 'scan' && <InstallCard compact />}

        <p className="auth__build" onClick={() => void onVersionTap()}>
          {BUILD_TAG}
        </p>
      </div>
    </div>
  )
}
