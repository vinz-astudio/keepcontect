import { useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { useUpdateStatus } from '@/features/update/versionCheck'
import { useI18n } from '@/lib/i18n'
import './UpdateNotice.css'

const SNOOZE_KEY = 'kc.update.snoozeUntil'
const SNOOZE_MS = 3 * 24 * 3_600_000 // 暂时搁置 ~3 天

function readSnooze(): number {
  try {
    return Number(localStorage.getItem(SNOOZE_KEY)) || 0
  } catch {
    return 0
  }
}

/**
 * 有新版本时常驻的升级提示:马上升级 / 继续提醒(关掉但下次打开再提醒)/
 * 暂时搁置(几天内不提醒)。原生壳=去下载新 APK;网页/PWA=重载拿最新。
 */
export function UpdateNotice() {
  const { t } = useI18n()
  const { latest, outdated } = useUpdateStatus()
  const [snoozedUntil, setSnoozedUntil] = useState<number>(readSnooze)
  const [dismissed, setDismissed] = useState(false)

  if (!outdated || dismissed || Date.now() < snoozedUntil) return null

  const upgrade = () => {
    if (Capacitor.isNativePlatform() && latest?.apkUrl) {
      window.open(latest.apkUrl, '_blank')
    } else {
      window.location.reload()
    }
  }
  const snooze = () => {
    const until = Date.now() + SNOOZE_MS
    try {
      localStorage.setItem(SNOOZE_KEY, String(until))
    } catch {
      /* ignore */
    }
    setSnoozedUntil(until)
  }

  return (
    <div className="updnotice" role="alert">
      <div className="updnotice__text">
        <strong>{t('update.title')}</strong>
        <span>{t('update.body', { v: latest?.version ?? '' })}</span>
      </div>
      <div className="updnotice__actions">
        <button className="updnotice__go" onClick={upgrade}>
          {t('update.now')}
        </button>
        <button className="updnotice__keep" onClick={() => setDismissed(true)}>
          {t('update.keep')}
        </button>
        <button className="updnotice__snooze" onClick={snooze}>
          {t('update.snooze')}
        </button>
      </div>
    </div>
  )
}
