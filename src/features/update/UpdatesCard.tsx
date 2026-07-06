import { useEffect, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { getPlatform, isTauri } from '@/lib/platform'
import { APP_VERSION } from '@/lib/version'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { launchUpdate } from '@/features/update/launchUpdate'
import { fetchLatest, isNewer } from '@/features/update/versionCheck'
import { useGmVersionChannel } from '@/features/update/versionChannelPreference'
import { toast } from '@/lib/toast'
import type { VersionStatus } from '@/features/update/versionSelection'

interface UpdatesCardProps {
  isGm?: boolean
  onVersionTap?: () => void
}

export function UpdatesCard({ isGm = false, onVersionTap }: UpdatesCardProps) {
  const { lang } = useI18n()
  const [gmVersionChannel, setGmVersionChannel] = useGmVersionChannel(isGm)
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
            if (!Number.isNaN(val)) setProgress(val)
          })) as () => void
        }
      } catch (err) {
        console.error('Failed to listen to download-progress:', err)
      }
    }
    void setupListener()
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
    await new Promise((resolve) => setTimeout(resolve, 800))
    try {
      const latest = await fetchLatest({ channel: isGm ? gmVersionChannel : 'public' })
      if (latest) {
        const outdated = isNewer(latest.version, APP_VERSION)
        setHasNewUpdate(outdated)
        setNewVersion(latest.version)
        setUpdateUrls({ apkUrl: latest.apkUrl, exeUrl: latest.exeUrl })
      } else {
        setHasNewUpdate(false)
        setNewVersion('')
        setUpdateUrls({})
      }
    } catch (err) {
      console.error('Check update failed:', err)
      setHasNewUpdate(false)
      setNewVersion('')
      setUpdateUrls({})
    } finally {
      setUpdStatus('checked')
    }
  }

  async function handleTriggerUpdate() {
    setUpdBusy(true)
    if (isTauri() && updateUrls.exeUrl) setProgress(0)
    try {
      await launchUpdate(updateUrls)
    } finally {
      setUpdBusy(false)
      setProgress(null)
    }
  }

  const title = lang === 'zh' ? `版本 · ${APP_VERSION}` : `Version · ${APP_VERSION}`
  const changeGmChannel = (channel: VersionStatus) => {
    setGmVersionChannel(channel)
    setUpdStatus('idle')
    setHasNewUpdate(false)
    setNewVersion('')
    setUpdateUrls({})
    toast(
      lang === 'zh'
        ? `GM 更新通道已切换为 ${channel === 'canary' ? 'Canary' : 'Released'}`
        : `GM update channel set to ${channel === 'canary' ? 'Canary' : 'Released'}`,
      'info',
    )
  }

  return (
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
      <h2 className="card__title" style={{ margin: 0 }}>
        {onVersionTap ? (
          <button
            type="button"
            aria-label={lang === 'zh' ? '版本信息' : 'Version information'}
            onClick={onVersionTap}
            style={{
              all: 'unset',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.5rem',
              cursor: 'pointer',
            }}
          >
            <Icon name="signal" />
            {title}
          </button>
        ) : (
          <>
            <Icon name="signal" />
            {title}
          </>
        )}
      </h2>

      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '12px',
          background: 'var(--bg)',
          border: '1px solid var(--line)',
          borderRadius: 'var(--r-md)',
          padding: '10px 14px',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', minWidth: 0 }}>
          <span style={{ fontWeight: 600, fontSize: '0.88rem', color: 'var(--fg)' }}>
            {getDeviceLabel()}
          </span>
          <span style={{ fontSize: '0.75rem', color: 'var(--fg-muted)' }}>
            v{APP_VERSION}
            {hasNewUpdate && updStatus === 'checked' && (
              <span style={{ marginLeft: '6px', color: 'var(--accent)', fontWeight: 600 }}>
                {' '}→ v{newVersion}
              </span>
            )}
          </span>
        </div>

        <div style={{ flexShrink: 0 }}>
          {progress !== null ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', minWidth: '120px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', opacity: 0.85 }}>
                <span>
                  {progress >= 100
                    ? (lang === 'zh' ? '准备安装...' : 'Installing...')
                    : (lang === 'zh' ? '下载中...' : 'Downloading...')}
                </span>
                <span>{progress}%</span>
              </div>
              <div style={{ width: '100%', height: '5px', backgroundColor: 'var(--line)', borderRadius: '3px', overflow: 'hidden' }}>
                <div style={{ width: `${progress}%`, height: '100%', backgroundColor: 'var(--accent)', transition: 'width 0.1s ease-out' }} />
              </div>
            </div>
          ) : updStatus === 'checking' ? (
            <button className="share" style={{ padding: '5px 14px', fontSize: '0.8rem', opacity: 0.6 }} disabled>
              {lang === 'zh' ? '检查中...' : 'Checking...'}
            </button>
          ) : updStatus === 'checked' && !hasNewUpdate ? (
            <button
              className="share"
              style={{ padding: '5px 14px', fontSize: '0.8rem', opacity: 0.4, cursor: 'default', pointerEvents: 'none' }}
              disabled
            >
              {lang === 'zh' ? '已是最新版本' : 'Up to date'}
            </button>
          ) : updStatus === 'checked' && hasNewUpdate ? (
            <button
              className="share"
              style={{ padding: '5px 14px', fontSize: '0.8rem', background: 'var(--accent)', color: '#15130e', fontWeight: 700, border: 'none' }}
              disabled={updBusy}
              onClick={() => void handleTriggerUpdate()}
            >
              {updBusy
                ? (lang === 'zh' ? '安装中...' : 'Installing...')
                : (isTauri()
                  ? (lang === 'zh' ? '立即更新' : 'Update')
                  : (lang === 'zh' ? '下载更新' : 'Download'))}
            </button>
          ) : (
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

      {isGm && (
        <div
          style={{
            marginTop: '6px',
            padding: '12px',
            border: '1px solid var(--accent-line)',
            borderRadius: 'var(--r-md)',
            background: 'var(--accent-soft)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            flexWrap: 'wrap',
            gap: '8px',
          }}
        >
          <span style={{ fontWeight: 700, fontSize: '0.82rem', color: 'var(--accent)' }}>
            {lang === 'zh' ? 'GM 更新通道' : 'GM update channel'}
          </span>
          <div
            role="group"
            aria-label={lang === 'zh' ? 'GM 更新通道' : 'GM update channel'}
            style={{ display: 'inline-flex', gap: '4px', padding: '3px', background: 'var(--bg)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)' }}
          >
            {(['canary', 'released'] as const).map((channel) => {
              const selected = gmVersionChannel === channel
              return (
                <button
                  key={channel}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => changeGmChannel(channel)}
                  style={{
                    minWidth: '82px',
                    padding: '6px 10px',
                    border: '1px solid transparent',
                    borderRadius: 'var(--r-sm)',
                    background: selected ? 'var(--accent)' : 'transparent',
                    color: selected ? '#15130e' : 'var(--fg)',
                    fontSize: '0.78rem',
                    fontWeight: 800,
                    cursor: 'pointer',
                  }}
                >
                  {channel === 'canary' ? 'Canary' : 'Released'}
                </button>
              )
            })}
          </div>
          <span style={{ flexBasis: '100%', fontSize: '0.75rem', lineHeight: 1.3, color: 'var(--fg)' }}>
            {lang === 'zh'
              ? '只影响这个 GM 设备的检查与提示。'
              : 'Only affects update checks and banners on this GM device.'}
            </span>
        </div>
      )}
    </section>
  )
}
