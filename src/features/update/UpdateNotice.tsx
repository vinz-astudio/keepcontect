import { useState, useEffect } from 'react'
import { Capacitor } from '@capacitor/core'
import { Browser } from '@capacitor/browser'
import { useUpdateStatus } from '@/features/update/versionCheck'
import { useI18n } from '@/lib/i18n'
import { isTauri } from '@/lib/platform'
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
  const { t, lang } = useI18n()
  const { latest, outdated } = useUpdateStatus()
  const [snoozedUntil, setSnoozedUntil] = useState<number>(readSnooze)
  const [dismissed, setDismissed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState<number | null>(null)

  useEffect(() => {
    let unlisten: (() => void) | null = null
    const setupListener = async () => {
      try {
        const internals = (window as any).__TAURI_INTERNALS__
        if (internals && typeof internals.listen === 'function') {
          unlisten = (await internals.listen('download-progress', (event: any) => {
            const val = typeof event.payload === 'number' ? event.payload : parseInt(event.payload, 10)
            if (!isNaN(val)) {
              setProgress(val)
            }
          })) as () => void
        }
      } catch (err) {
        console.error('Failed to listen to download-progress:', err)
      }
    }
    setupListener()
    return () => {
      if (unlisten) unlisten()
    }
  }, [])

  if (!outdated || dismissed || Date.now() < snoozedUntil) return null

  const upgrade = async () => {
    if (isTauri() && latest?.exeUrl) {
      setBusy(true)
      setProgress(0)
      try {
        const internals = (window as any).__TAURI_INTERNALS__
        if (internals && typeof internals.invoke === 'function') {
          await internals.invoke('download_and_install', { url: latest.exeUrl })
        } else {
          window.open(latest.exeUrl, '_blank')
        }
      } catch (err) {
        console.error('Tauri update failed:', err)
        window.open(latest.exeUrl, '_blank')
      } finally {
        setBusy(false)
        setProgress(null)
      }
    } else if (Capacitor.isNativePlatform() && latest?.apkUrl) {
      void Browser.open({ url: latest.apkUrl }).catch((err) => {
        console.error('Failed to open APK URL with Capacitor Browser:', err)
        window.open(latest.apkUrl, '_blank')
      })
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
      {progress !== null ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', width: '100%', marginTop: '6px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', opacity: 0.9 }}>
            <span>{progress >= 100 ? (lang === 'zh' ? '正在准备安装...' : 'Preparing installation...') : (lang === 'zh' ? '正在下载更新...' : 'Downloading update...')}</span>
            <span>{progress}%</span>
          </div>
          <div style={{ width: '100%', height: '6px', backgroundColor: 'var(--line)', borderRadius: '3px', overflow: 'hidden' }}>
            <div style={{ width: `${progress}%`, height: '100%', backgroundColor: 'var(--accent)', transition: 'width 0.1s ease-out' }} />
          </div>
        </div>
      ) : (
        <div className="updnotice__actions">
          <button className="updnotice__go" onClick={upgrade} disabled={busy}>
            {busy ? (lang === 'zh' ? '正在下载更新...' : 'Downloading...') : t('update.now')}
          </button>
          <button className="updnotice__keep" onClick={() => setDismissed(true)}>
            {t('update.keep')}
          </button>
          <button className="updnotice__snooze" onClick={snooze}>
            {t('update.snooze')}
          </button>
        </div>
      )}
    </div>
  )
}
