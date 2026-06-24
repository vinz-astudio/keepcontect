import { useState, useEffect } from 'react'
import { Capacitor } from '@capacitor/core'
import { isTauri, getPlatform } from '@/lib/platform'
import { APP_VERSION } from '@/lib/version'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { fetchLatest, isNewer } from '@/features/update/versionCheck'

export function UpdatesCard() {
  const { lang } = useI18n()
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
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
      {/* Title: "Version · x.x.x" */}
      <h2 className="card__title" style={{ margin: 0 }}>
        <Icon name="signal" />
        {lang === 'zh' ? `版本 · ${APP_VERSION}` : `Version · ${APP_VERSION}`}
      </h2>

      {/* Single content row */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: '12px',
        background: 'var(--bg)',
        border: '1px solid var(--line)',
        borderRadius: 'var(--r-md)',
        padding: '10px 14px',
      }}>
        {/* Left: device type + current version */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', minWidth: 0 }}>
          <span style={{ fontWeight: '600', fontSize: '0.88rem', color: 'var(--fg)' }}>
            {getDeviceLabel()}
          </span>
          <span style={{ fontSize: '0.75rem', color: 'var(--fg-muted)' }}>
            {`v${APP_VERSION}`}
            {hasNewUpdate && updStatus === 'checked' && (
              <span style={{ marginLeft: '6px', color: 'var(--accent)', fontWeight: '600' }}>
                {' '}→{' '}v{newVersion}
              </span>
            )}
          </span>
        </div>

        {/* Right: contextual button */}
        <div style={{ flexShrink: 0 }}>
          {progress !== null ? (
            /* Downloading – show inline progress bar */
            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', minWidth: '120px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', opacity: 0.85 }}>
                <span>
                  {progress >= 100
                    ? (lang === 'zh' ? '准备安装…' : 'Installing…')
                    : (lang === 'zh' ? '下载中…' : 'Downloading…')}
                </span>
                <span>{progress}%</span>
              </div>
              <div style={{ width: '100%', height: '5px', backgroundColor: 'var(--line)', borderRadius: '3px', overflow: 'hidden' }}>
                <div style={{ width: `${progress}%`, height: '100%', backgroundColor: 'var(--accent)', transition: 'width 0.1s ease-out' }} />
              </div>
            </div>
          ) : updStatus === 'checking' ? (
            /* Checking – disabled spinner label */
            <button className="share" style={{ padding: '5px 14px', fontSize: '0.8rem', opacity: 0.6 }} disabled>
              {lang === 'zh' ? '检查中…' : 'Checking…'}
            </button>
          ) : updStatus === 'checked' && !hasNewUpdate ? (
            /* Up to date – grey, non-interactive */
            <button
              className="share"
              style={{ padding: '5px 14px', fontSize: '0.8rem', opacity: 0.4, cursor: 'default', pointerEvents: 'none' }}
              disabled
            >
              {lang === 'zh' ? '已是最新版本' : 'Up to date'}
            </button>
          ) : updStatus === 'checked' && hasNewUpdate ? (
            /* Update available – coloured & active */
            <button
              className="share"
              style={{ padding: '5px 14px', fontSize: '0.8rem', background: 'var(--accent)', color: 'var(--bg)', fontWeight: '700', border: 'none' }}
              disabled={updBusy}
              onClick={() => void handleTriggerUpdate()}
            >
              {updBusy
                ? (lang === 'zh' ? '安装中…' : 'Installing…')
                : (isTauri()
                  ? (lang === 'zh' ? '立即更新' : 'Update')
                  : (lang === 'zh' ? '下载更新' : 'Download'))}
            </button>
          ) : (
            /* Idle – tap to check */
            <button
              className="share"
              style={{ padding: '5px 14px', fontSize: '0.8rem' }}
              onClick={() => void handleCheckUpdate()}
            >
              {lang === 'zh' ? '检查更新' : 'Check'}
            </button>
          )}
        </div>
      </div>
    </section>
  )
}

