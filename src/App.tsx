import { AuthProvider, useAuth } from '@/features/auth/AuthProvider'
import { AuthScreen } from '@/features/auth/AuthScreen'
import { HomeScreen } from '@/features/relationships/HomeScreen'
import { ErrorBoundary } from '@/features/common/ErrorBoundary'
import { I18nProvider, useI18n } from '@/lib/i18n'
import {
  clearInviteFromUrl,
  parseInviteFromUrl,
  savePendingInvite,
} from '@/features/invites/inviteLink'
import './App.css'

// å¯åŠ¨å³æ•èŽ·é‚€è¯·é“¾æŽ¥å‚æ•°ï¼ˆç™»å½•å‰åŽéƒ½é€‚ç”¨ï¼‰ï¼Œæš‚å­˜åŽæ¸…ç†åœ°å€æ 
const urlInvite = parseInviteFromUrl()
if (urlInvite) {
  savePendingInvite(urlInvite)
  clearInviteFromUrl()
}

function Gate() {
  const { session, loading } = useAuth()
  const { t } = useI18n()

  if (loading) {
    return (
      <div className="app app--center">
        <p className="app__loading">{t('home.loading')}</p>
      </div>
    )
  }

  return session ? <HomeScreen /> : <AuthScreen />
}

export default function App() {
  return (
    <I18nProvider>
      <ErrorBoundary>
        <AuthProvider>
          <Gate />
        </AuthProvider>
      </ErrorBoundary>
    </I18nProvider>
  )
}

