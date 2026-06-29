import { useEffect, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { getPlatform, isStandalone, isTauri } from '@/lib/platform'
import {
  canInstall,
  onInstallChange,
  promptInstall,
} from '@/features/install/installPrompt'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { APK_URL } from '@/features/install/apk'

export function InstallCard({ compact = false }: { compact?: boolean }) {
  const { t, lang } = useI18n()
  const platform = getPlatform()
  const [installable, setInstallable] = useState(canInstall())

  useEffect(() => onInstallChange(() => setInstallable(canInstall())), [])

  // 已在桌面原生 App 内 → 无需任何安装引导
  if (isTauri()) return null

  // 已在原生 App 内 → 无需任何安装引导
  if (Capacitor.isNativePlatform()) return null

  // Android：始终提供 APK（浏览器=安装，已装 PWA=升级到原生），作为「获取/升级 App」入口
  if (platform === 'android') {
    if (compact) {
      return (
        <div className="install__compact">
          <a className="install__compactbtn" href={APK_URL} download>
            {t('install.apk.get')}
          </a>
        </div>
      )
    }
    return (
      <section className="card">
        <h2 className="card__title">
          <Icon name="download" />
          {t('install.title')}
        </h2>
        <p className="muted">{t('install.apk.desc')}</p>
        <a className="ei__save" href={APK_URL} download>
          {t('install.apk.get')}
        </a>
        <p className="muted install__apkhint">{t('install.apk.hint')}</p>
      </section>
    )
  }

  // iOS / 桌面：已作为独立 App 安装则不再引导
  if (isStandalone()) return null

  // iOS：无法用 JS 触发安装、也无法装 APK，给"添加到主屏"图文步骤
  if (platform === 'ios') {
    if (compact) {
      return (
        <div className="install__compact">
          <p className="install__compacthint">{t('install.ios.short')}</p>
        </div>
      )
    }
    return (
      <section className="card">
        <h2 className="card__title">
          <Icon name="download" />
          {t('install.title')}
        </h2>
        <p className="muted">{t('install.ios.desc')}</p>
        <ol className="install__steps">
          <li>{t('install.ios.s1')}</li>
          <li>{t('install.ios.s2')}</li>
          <li>{t('install.ios.s3')}</li>
        </ol>
      </section>
    )
  }

  // Desktop browser: keep this generic; native desktop setup lives in Passive sensing.
  if (compact) {
    if (!installable) return null
    return (
      <div className="install__compact">
        <button
          className="install__compactbtn"
          onClick={() => void promptInstall()}
        >
          {t('install.get')} (PWA)
        </button>
      </div>
    )
  }

  if (!installable) return null

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="download" />
        {t('install.title')}
      </h2>
      <p className="muted">
        {lang === 'zh'
          ? '在这个浏览器里安装轻量网页版，方便从桌面直接打开。需要后台自动感知时，登录后到「我的」里的被动感知设置。'
          : 'Install the lightweight web app in this browser for quick desktop access. For background sensing, sign in and use Passive sensing under Profile.'}
      </p>
      <button className="ei__save" onClick={() => void promptInstall()}>
        {lang === 'zh' ? '安装 PWA 网页版' : 'Install PWA Web App'}
      </button>
    </section>
  )
}
