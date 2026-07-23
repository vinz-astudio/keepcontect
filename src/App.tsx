import { AuthProvider, useAuth } from '@/features/auth/AuthProvider'
import { AuthScreen } from '@/features/auth/AuthScreen'
import { HomeScreen } from '@/features/relationships/HomeScreen'
import { ErrorBoundary } from '@/features/common/ErrorBoundary'
import { NativeAuthRedirectBridge } from '@/features/auth/NativeAuthRedirectBridge'
import { UpdateNotice } from '@/features/update/UpdateNotice'
import { I18nProvider, useI18n } from '@/lib/i18n'
import { initialHadAuthTokens } from '@/lib/supabase'
import {
  clearInviteFromUrl,
  parseInviteFromUrl,
  savePendingInvite,
} from '@/features/invites/inviteLink'
import { ThemeProvider } from '@/lib/theme'
import './App.css'

// 启动即捕获邀请链接参数（登录前后都适用），暂存后清理地址栏
const urlInvite = parseInviteFromUrl()
if (urlInvite) {
  savePendingInvite(urlInvite)
  clearInviteFromUrl()
}

function Gate() {
  const { session, loading, hasStoredAuth, bootstrapError, bootstrapTimedOut, retryBootstrap } = useAuth()
  const { t } = useI18n()

  if (!session && (bootstrapError || bootstrapTimedOut)) {
    return (
      <div className="app app--center" style={{ flexDirection: 'column', gap: '16px', padding: '24px', textAlign: 'center' }}>
        <p className="home__error" style={{ margin: 0 }}>{t('auth.bootstrap.error')}</p>
        <button className="share" onClick={retryBootstrap}>
          {t('auth.bootstrap.retry')}
        </button>
      </div>
    )
  }

  // 老用户：本地已有会话凭据 → 首帧直接进 watch，不等异步 getSession / 网络
  if (session || (loading && hasStoredAuth)) return <HomeScreen />

  // 仅在 OAuth 回跳、正用 URL 凭据换取会话时短暂等待
  if (loading && initialHadAuthTokens) {
    return (
      <div className="app app--center">
        <p className="app__loading">{t('home.loading')}</p>
      </div>
    )
  }

  // 其余情况（无凭据 / 已确认未登录）直接进登录页，不显示全屏 loading
  return <AuthScreen />
}

export default function App() {
  return (
    <I18nProvider>
      <ThemeProvider>
        <NativeAuthRedirectBridge />
        <UpdateNotice />
        <ErrorBoundary>
          <AuthProvider>
            <Gate />
          </AuthProvider>
        </ErrorBoundary>
      </ThemeProvider>
    </I18nProvider>
  )
}
