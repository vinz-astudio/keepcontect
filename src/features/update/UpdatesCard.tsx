import { useState, useEffect } from 'react'
import { Capacitor } from '@capacitor/core'
import { isTauri, getPlatform } from '@/lib/platform'
import { APP_VERSION } from '@/lib/version'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { fetchLatest, isNewer } from '@/features/update/versionCheck'

export function UpdatesCard() {
  const { t, lang } = useI18n()
  const [updBusy, setUpdBusy] = useState(false)
  const [updStatus, setUpdStatus] = useState<'idle' | 'checking' | 'checked'>('idle')
  const [hasNewUpdate, setHasNewUpdate] = useState(false)
  const [newVersion, setNewVersion] = useState('')
  const [updateUrls, setUpdateUrls] = useState<{ apkUrl?: string; exeUrl?: string }>({})
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

  const android = (() => {
    if (getPlatform() !== 'android') return null
    return Capacitor.getPlatform() === 'android' ? 'native' : 'web'
  })()

  const getDeviceLabel = () => {
    const platform = getPlatform()
    if (isTauri()) return lang === 'zh' ? 'Windows 桌面客户端' : 'Windows Desktop App'
    if (android === 'native') return lang === 'zh' ? 'Android 原生客户端' : 'Android Native App'
    if (platform === 'ios') return lang === 'zh' ? 'iOS 网页/快捷指令' : 'iOS Web/Shortcuts'
    if (platform === 'android') return lang === 'zh' ? 'Android 网页版' : 'Android Web PWA'
    return lang === 'zh' ? '网页版' : 'Web Browser'
  }

  async function handleCheckUpdate() {
    setUpdStatus('checking')
    await new Promise((r) => setTimeout(r, 800))
    try {
      const l = await fetchLatest()
      if (l) {
        const outdated = isNewer(l.version, APP_VERSION)
        setHasNewUpdate(outdated)
        setNewVersion(l.version)
        setUpdateUrls({ apkUrl: l.apkUrl, exeUrl: l.exeUrl })
        setUpdStatus('checked')
      } else {
        setHasNewUpdate(false)
        setUpdStatus('checked')
      }
    } catch (err) {
      console.error('Check update failed:', err)
      setHasNewUpdate(false)
      setUpdStatus('checked')
    }
  }

  async function handleTriggerUpdate() {
    if (isTauri() && updateUrls.exeUrl) {
      setUpdBusy(true)
      setProgress(0)
      try {
        const internals = (window as any).__TAURI_INTERNALS__
        if (internals && typeof internals.invoke === 'function') {
          await internals.invoke('download_and_install', { url: updateUrls.exeUrl })
        } else {
          window.open(updateUrls.exeUrl, '_blank')
        }
      } catch (err) {
        console.error('Tauri update failed:', err)
        try {
          const internals = (window as any).__TAURI_INTERNALS__
          if (internals && typeof internals.invoke === 'function') {
            await internals.invoke('open_in_browser', { url: updateUrls.exeUrl })
          } else {
            window.open(updateUrls.exeUrl, '_blank')
          }
        } catch {
          window.open(updateUrls.exeUrl, '_blank')
        }
      } finally {
        setUpdBusy(false)
        setProgress(null)
      }
    } else if (Capacitor.isNativePlatform() && updateUrls.apkUrl) {
      window.open(updateUrls.apkUrl, '_blank')
    } else {
      window.location.reload()
    }
  }

  return (
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.85rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h2 className="card__title" style={{ margin: 0 }}>
          <Icon name="signal" />
          {lang === 'zh' ? '系统版本与更新' : 'Updates & Versions'}
        </h2>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.82rem' }}>
          <span style={{ fontWeight: '700', color: 'var(--accent)' }}>beta {APP_VERSION}</span>
          <span style={{ opacity: 0.6 }}>({getDeviceLabel()})</span>
        </div>
      </div>

      <div style={{ background: 'var(--bg-soft)', padding: '0.75rem 1rem', borderRadius: 'var(--r-md)', display: 'flex', flexDirection: 'column', gap: '8px', border: '1px solid var(--line)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
          <span style={{ fontSize: '0.88rem', fontWeight: '600' }}>
            {lang === 'zh' ? '检测最新版本与固件' : 'Check for System Updates'}
          </span>
          {updStatus === 'idle' && (
            <button className="share" style={{ padding: '6px 12px', fontSize: '0.8rem' }} onClick={() => void handleCheckUpdate()}>
              {t('update.check')}
            </button>
          )}
          {updStatus === 'checking' && (
            <span className="psig__status-text" style={{ fontSize: '0.82rem', opacity: 0.7 }}>{t('update.checking')}</span>
          )}
          {updStatus === 'checked' && !hasNewUpdate && (
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <span className="psig__status-text psig__status-text--ok" style={{ fontSize: '0.82rem', color: 'var(--ok)', fontWeight: '600' }}>✓ {t('update.latest')}</span>
              <button className="share" style={{ padding: '6px 12px', fontSize: '0.8rem' }} onClick={() => void handleCheckUpdate()}>
                {lang === 'zh' ? '重新检测' : 'Re-check'}
              </button>
            </div>
          )}
        </div>
        
        {updStatus === 'checked' && hasNewUpdate && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', borderTop: '1px dashed var(--line)', paddingTop: '8px', marginTop: '4px' }}>
            <p className="psig__status-text psig__status-text--warn" style={{ fontSize: '0.82rem', color: 'var(--warning)', fontWeight: '600', margin: 0 }}>
              {t('update.found').replace('{v}', newVersion)}
            </p>
            {progress !== null ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', width: '100%', marginTop: '4px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', opacity: 0.9 }}>
                  <span>{progress >= 100 ? (lang === 'zh' ? '正在准备安装...' : 'Preparing installation...') : (lang === 'zh' ? '正在下载更新...' : 'Downloading update...')}</span>
                  <span>{progress}%</span>
                </div>
                <div style={{ width: '100%', height: '6px', backgroundColor: 'var(--line)', borderRadius: '3px', overflow: 'hidden' }}>
                  <div style={{ width: `${progress}%`, height: '100%', backgroundColor: 'var(--accent)', transition: 'width 0.1s ease-out' }} />
                </div>
              </div>
            ) : (
              <button 
                className="share" 
                style={{ width: '100%', padding: '8px', background: 'var(--accent)', color: 'var(--bg)' }}
                disabled={updBusy}
                onClick={() => void handleTriggerUpdate()}
              >
                {updBusy 
                  ? (lang === 'zh' ? '正在安装...' : 'Installing...') 
                  : (isTauri() ? (lang === 'zh' ? '立即更新安装' : 'Update & Install') : (lang === 'zh' ? '下载新版本' : 'Download Update'))}
              </button>
            )}
          </div>
        )}
      </div>
    </section>
  )
}
