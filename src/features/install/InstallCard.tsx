import { useEffect, useState } from 'react'
import { getPlatform, isStandalone } from '@/lib/platform'
import {
  canInstall,
  onInstallChange,
  promptInstall,
} from '@/features/install/installPrompt'
import { useI18n } from '@/lib/i18n'

export function InstallCard({ compact = false }: { compact?: boolean }) {
  const { t } = useI18n()
  const platform = getPlatform()
  const [installable, setInstallable] = useState(canInstall())

  useEffect(() => onInstallChange(() => setInstallable(canInstall())), [])

  // 已经是独立 App，无需再引导安装
  if (isStandalone()) return null

  // 紧凑版：用于登录/注册页，省空间
  if (compact) {
    return (
      <div className="install__compact">
        {platform === 'ios' ? (
          <p className="install__compacthint">{t('install.ios.short')}</p>
        ) : installable ? (
          <button
            className="install__compactbtn"
            onClick={() => void promptInstall()}
          >
            {t('install.get')}
          </button>
        ) : (
          <p className="install__compacthint">{t('install.android.hint')}</p>
        )}
      </div>
    )
  }

  // iOS：无法用 JS 触发安装，给"添加到主屏"图文步骤
  if (platform === 'ios') {
    return (
      <section className="card">
        <h2 className="card__title">{t('install.title')}</h2>
        <p className="muted">{t('install.ios.desc')}</p>
        <ol className="install__steps">
          <li>{t('install.ios.s1')}</li>
          <li>{t('install.ios.s2')}</li>
          <li>{t('install.ios.s3')}</li>
        </ol>
      </section>
    )
  }

  // Android / 桌面：可直接触发安装
  return (
    <section className="card">
      <h2 className="card__title">{t('install.title')}</h2>
      <p className="muted">{t('install.android.desc')}</p>
      {installable ? (
        <button className="ei__save" onClick={() => void promptInstall()}>
          {t('install.get')}
        </button>
      ) : (
        <p className="muted">{t('install.android.hint')}</p>
      )}
    </section>
  )
}
