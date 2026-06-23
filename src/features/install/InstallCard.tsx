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
  const { t } = useI18n()
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

  // 桌面：提供原生 Windows 安装包下载 + PWA 安装
  const lang = useI18n().lang
  if (compact) {
    return (
      <div className="install__compact" style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
        <a
          className="install__compactbtn"
          href="/desktop/KeepContact-Setup.exe"
          download
          style={{ textDecoration: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
        >
          {lang === 'zh' ? '下载 EXE 安装包' : 'Download EXE'}
        </a>
        {installable && (
          <button
            className="install__compactbtn"
            onClick={() => void promptInstall()}
            style={{ backgroundColor: 'var(--surface-2)' }}
          >
            {t('install.get')} (PWA)
          </button>
        )}
      </div>
    )
  }
  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="download" />
        {t('install.title')}
      </h2>
      <p className="muted">
        {lang === 'zh'
          ? '直接安装 Keep Contact 原生桌面版，支持托盘后台运行、开机自启和更稳定的被动报平安。'
          : 'Install the native Keep Contact desktop app for background tray running, auto-start at login, and more reliable passive check-ins.'}
      </p>

      <div style={{ display: 'flex', gap: '12px', marginTop: '12px', marginBottom: '16px', flexWrap: 'wrap' }}>
        <a
          className="ei__save"
          href="/desktop/KeepContact-Setup.exe"
          download
          style={{ textDecoration: 'none', textAlign: 'center', display: 'inline-block' }}
        >
          {lang === 'zh' ? '下载 Windows 安装包 (.exe)' : 'Download Windows Setup (.exe)'}
        </a>
        <a
          className="ei__save"
          href="/desktop/KeepContact.msi"
          download
          style={{ textDecoration: 'none', textAlign: 'center', display: 'inline-block', backgroundColor: '#5c6bc0' }}
        >
          {lang === 'zh' ? '下载 MSI 安装包' : 'Download MSI Package'}
        </a>
      </div>

      {installable && (
        <div style={{ borderTop: '1px dashed var(--line)', paddingTop: '12px', marginTop: '12px' }}>
          <p className="muted" style={{ marginBottom: '8px' }}>
            {lang === 'zh' ? '或者，你也可以选择一键安装轻量 PWA 网页版：' : 'Or, you can install the lightweight PWA web app:'}
          </p>
          <button className="ei__save" onClick={() => void promptInstall()} style={{ backgroundColor: 'var(--surface-2)', color: 'var(--fg)' }}>
            {lang === 'zh' ? '安装 PWA 网页版' : 'Install PWA Web App'}
          </button>
        </div>
      )}
    </section>
  )
}
