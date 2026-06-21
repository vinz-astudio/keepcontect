import { useState } from 'react'
import { isStandalone } from '@/lib/platform'
import { APK_URL, isAndroidWeb } from '@/features/install/apk'
import { useI18n } from '@/lib/i18n'
import './ApkUpgradeNotice.css'

const DISMISS_KEY = 'kc.apkNoticeDismissed'

/**
 * 提示「已把 PWA 装到主屏」的 Android 用户升级到原生 APK。
 * 仅对 Android 网页 + 独立显示(已安装 PWA)显示;可手动收起(localStorage 记忆)。
 * 浏览器里的新用户由 InstallCard 引导,原生壳内不显示。
 */
export function ApkUpgradeNotice() {
  const { t } = useI18n()
  const [dismissed, setDismissed] = useState(() => {
    try {
      return localStorage.getItem(DISMISS_KEY) === '1'
    } catch {
      return false
    }
  })

  if (dismissed || !isAndroidWeb() || !isStandalone()) return null

  return (
    <div className="apknotice" role="status">
      <div className="apknotice__text">
        <strong>{t('apk.notice.title')}</strong>
        <span>{t('apk.notice.body')}</span>
      </div>
      <div className="apknotice__actions">
        <a className="apknotice__get" href={APK_URL} download>
          {t('install.apk.get')}
        </a>
        <button
          type="button"
          className="apknotice__dismiss"
          onClick={() => {
            try {
              localStorage.setItem(DISMISS_KEY, '1')
            } catch {
              /* ignore */
            }
            setDismissed(true)
          }}
        >
          {t('apk.notice.dismiss')}
        </button>
      </div>
    </div>
  )
}
