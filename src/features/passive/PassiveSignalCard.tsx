import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useState } from 'react'
import {
  countTodayPings,
  getHeartbeatToken,
  lastPingAt,
  listRecentPings,
  pingUrl,
  shortcutImportUrl,
  summaryUrl,
  type BehaviorPing,
} from '@/features/passive/api'
import { getDesktopOS, getPlatform, isTauri } from '@/lib/platform'
import { buildWindowsHookCmd } from '@/features/passive/windowsHook'
import { APP_VERSION, LATEST_URL } from '@/lib/version'
import { translate, useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { supabase } from '@/lib/supabase'
import { toast } from '@/lib/toast'
import { ScanSyncModal } from '@/features/auth/ScanSyncModal'
import { fetchLatest, isNewer } from '@/features/update/versionCheck'
import './PassiveSignalCard.css'

function downloadText(name: string, text: string): void {
  const blob = new Blob([text], { type: 'application/octet-stream' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

function ago(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return translate('time.now')
  if (s < 3600) return translate('time.min', { n: Math.floor(s / 60) })
  if (s < 86400) return translate('time.hour', { n: Math.floor(s / 3600) })
  return translate('time.day', { n: Math.floor(s / 86400) })
}

function androidRuntime(): 'native' | 'web' | null {
  if (getPlatform() !== 'android') return null
  return Capacitor.getPlatform() === 'android' ? 'native' : 'web'
}

export function PassiveSignalCard() {
  const { t, lang } = useI18n()
  const platform = getPlatform()
  const android = androidRuntime()
  const desktopOS = platform === 'desktop' ? getDesktopOS() : null
  
  const [token, setToken] = useState<string | null>(null)
  const [pings, setPings] = useState<BehaviorPing[]>([])
  const [copied, setCopied] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [hookConsent, setHookConsent] = useState(false)
  const [autostart, setAutostart] = useState(false)
  const [hasAutostartSupport, setHasAutostartSupport] = useState(false)

  // Scan & Update check states
  const [isScanning, setIsScanning] = useState(false)
  const [updBusy, setUpdBusy] = useState<string | null>(null)
  const [updateCheck, setUpdateCheck] = useState<Record<string, {
    status: 'idle' | 'checking' | 'checked'
    isNew?: boolean
    version?: string
    apkUrl?: string
    exeUrl?: string
  }>>({})

  // Tauri autostart check
  useEffect(() => {
    if (isTauri()) {
      const checkAutostart = async () => {
        try {
          const internals = (window as any).__TAURI_INTERNALS__
          if (internals && typeof internals.invoke === 'function') {
            const enabled = (await internals.invoke(
              'plugin:autostart|is_enabled',
            )) as boolean
            setAutostart(enabled)
            setHasAutostartSupport(true)
          }
        } catch (e) {
          console.error('Failed to check autostart status:', e)
        }
      }
      void checkAutostart()
    }
  }, [])

  const toggleAutostart = async (checked: boolean) => {
    try {
      const internals = (window as any).__TAURI_INTERNALS__
      if (internals && typeof internals.invoke === 'function') {
        if (checked) {
          await internals.invoke('plugin:autostart|enable')
        } else {
          await internals.invoke('plugin:autostart|disable')
        }
        setAutostart(checked)
      }
    } catch (e) {
      console.error('Failed to toggle autostart:', e)
    }
  }

  const refresh = useCallback(async () => {
    try {
      const [tk, ps] = await Promise.all([getHeartbeatToken(), listRecentPings()])
      setToken(tk)
      setPings(ps)
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const todayCount = countTodayPings(pings)
  const lastAt = lastPingAt(pings)
  const url = token ? pingUrl(token) : ''

  async function copy() {
    try {
      await navigator.clipboard.writeText(url)
    } catch {
      /* Clipboard fallback */
    }
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  // Version Check Handler
  async function handleCheckUpdate(sectionId: string) {
    setUpdateCheck((prev) => ({
      ...prev,
      [sectionId]: { status: 'checking' }
    }))
    await new Promise((r) => setTimeout(r, 800)) // Visual effect
    try {
      const l = await fetchLatest()
      if (l) {
        const outdated = isNewer(l.version, APP_VERSION)
        setUpdateCheck((prev) => ({
          ...prev,
          [sectionId]: {
            status: 'checked',
            isNew: outdated,
            version: l.version,
            apkUrl: l.apkUrl,
            exeUrl: l.exeUrl
          }
        }))
      } else {
        setUpdateCheck((prev) => ({
          ...prev,
          [sectionId]: { status: 'checked', isNew: false, version: APP_VERSION }
        }))
      }
    } catch (err) {
      console.error('Check update failed:', err)
      setUpdateCheck((prev) => ({
        ...prev,
        [sectionId]: { status: 'checked', isNew: false, version: APP_VERSION }
      }))
    }
  }

  // Version Upgrade Handler
  async function handleTriggerUpdate(sectionId: string, info: { apkUrl?: string; exeUrl?: string }) {
    if (isTauri() && info.exeUrl) {
      setUpdBusy(sectionId)
      try {
        const internals = (window as any).__TAURI_INTERNALS__
        if (internals && typeof internals.invoke === 'function') {
          await internals.invoke('download_and_install', { url: info.exeUrl })
        } else {
          window.open(info.exeUrl, '_blank')
        }
      } catch (err) {
        console.error('Tauri update failed:', err)
        window.open(info.exeUrl, '_blank')
      } finally {
        setUpdBusy(null)
      }
    } else if (Capacitor.isNativePlatform() && info.apkUrl) {
      window.open(info.apkUrl, '_blank')
    } else {
      window.location.reload()
    }
  }

  // Mobile Scan QR sync handler
  async function handleQrScan(data: string) {
    setIsScanning(false)
    if (!data.startsWith('keepcontact://sync?token=')) {
      toast(t('profile.scan.failed'), 'danger')
      return
    }
    const targetToken = data.replace('keepcontact://sync?token=', '')
    toast(t('profile.scan.success'), 'info')
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        toast(t('err.load'), 'danger')
        return
      }
      const channel = supabase.channel(`scan2sync:${targetToken}`, {
        config: { broadcast: { self: false } }
      })
      channel.subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await channel.send({
            type: 'broadcast',
            event: 'sync',
            payload: {
              access_token: session.access_token,
              refresh_token: session.refresh_token
            }
          })
          toast(t('profile.scan.success'), 'ok')
          setTimeout(() => {
            void supabase.removeChannel(channel)
          }, 2000)
        }
      })
    } catch (err) {
      console.error('Scan sync broadcast failed:', err)
      toast(t('profile.scan.failed'), 'danger')
    }
  }

  // Accordion Sections definitions
  const sections = [
    {
      id: 'windows_native',
      title: lang === 'zh' ? 'Windows 桌面原生应用' : 'Windows Native App',
      isCurrent: isTauri(),
      render: () => {
        const check = updateCheck['windows_native']
        return (
          <div>
            <p className="muted">
              {lang === 'zh' 
                ? '当前已运行在 Keep Contact 原生桌面版中。支持后台系统空闲自动感知上报，即使关闭窗口仍会在系统托盘中维持守护状态。'
                : 'Currently running inside Keep Contact native desktop app. Supports automatic idle detection reporting and runs in system tray when closed.'}
            </p>
            
            <div className="psig__version-row" style={{ marginTop: '12px', display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
              <span className="psig__version-label" style={{ fontWeight: '600', fontSize: '0.85rem' }}>
                {lang === 'zh' ? `当前版本: v${APP_VERSION}` : `Version: v${APP_VERSION}`}
              </span>
              
              {(!check || check.status === 'idle') && (
                <button className="psig__small-btn" onClick={() => void handleCheckUpdate('windows_native')}>
                  {t('update.check')}
                </button>
              )}
              {check?.status === 'checking' && (
                <span className="psig__status-text">{t('update.checking')}</span>
              )}
              {check?.status === 'checked' && !check.isNew && (
                <span className="psig__status-text psig__status-text--ok">✓ {t('update.latest')}</span>
              )}
              {check?.status === 'checked' && check.isNew && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span className="psig__status-text psig__status-text--warn">
                    {t('update.found').replace('{v}', check.version || '')}
                  </span>
                  <button 
                    className="psig__small-btn psig__small-btn--highlight" 
                    disabled={updBusy === 'windows_native'}
                    onClick={() => void handleTriggerUpdate('windows_native', { exeUrl: check.exeUrl })}
                  >
                    {updBusy === 'windows_native' ? (lang === 'zh' ? '正在下载...' : 'Downloading...') : (lang === 'zh' ? '立即更新' : 'Update Now')}
                  </button>
                </div>
              )}
            </div>

            {hasAutostartSupport && (
              <div className="psig__autostart-option" style={{ marginTop: '12px', borderTop: '1px dashed var(--line)', paddingTop: '10px' }}>
                <label className="psig__hookconsent" style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={autostart}
                    onChange={(e) => void toggleAutostart(e.target.checked)}
                  />
                  <span style={{ fontSize: '0.9rem', fontWeight: '500' }}>{t('hook.win.autostart')}</span>
                </label>
              </div>
            )}
          </div>
        )
      }
    },
    {
      id: 'android_native',
      title: lang === 'zh' ? 'Android 安卓原生客户端' : 'Android Native App',
      isCurrent: android === 'native',
      render: () => {
        const check = updateCheck['android_native']
        return (
          <div>
            <p className="muted">
              {t('passive.setup.androidNative')}
            </p>
            
            <div className="psig__version-row" style={{ marginTop: '12px', marginBottom: '12px', display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
              <span className="psig__version-label" style={{ fontWeight: '600', fontSize: '0.85rem' }}>
                {lang === 'zh' ? `当前版本: v${APP_VERSION}` : `Version: v${APP_VERSION}`}
              </span>
              
              {(!check || check.status === 'idle') && (
                <button className="psig__small-btn" onClick={() => void handleCheckUpdate('android_native')}>
                  {t('update.check')}
                </button>
              )}
              {check?.status === 'checking' && (
                <span className="psig__status-text">{t('update.checking')}</span>
              )}
              {check?.status === 'checked' && !check.isNew && (
                <span className="psig__status-text psig__status-text--ok">✓ {t('update.latest')}</span>
              )}
              {check?.status === 'checked' && check.isNew && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span className="psig__status-text psig__status-text--warn">
                    {t('update.found').replace('{v}', check.version || '')}
                  </span>
                  <button 
                    className="psig__small-btn psig__small-btn--highlight" 
                    onClick={() => void handleTriggerUpdate('android_native', { apkUrl: check.apkUrl })}
                  >
                    {lang === 'zh' ? '下载 APK' : 'Download APK'}
                  </button>
                </div>
              )}
            </div>

            {/* Direct Installer download when not running native APK or when on web/other platforms */}
            {android !== 'native' && (
              <div style={{ marginTop: '12px', marginBottom: '12px' }}>
                <a className="psig__import" href="https://keep-contact-mauve.vercel.app/keep-contact.apk" download>
                  {lang === 'zh' ? '下载安卓安装包 (.apk)' : 'Download Android APK'}
                </a>
              </div>
            )}

            <p className="muted" style={{ marginTop: '8px', fontSize: '0.82rem', color: 'var(--accent)' }}>
              {lang === 'zh'
                ? '提示：请在系统设置中允许本应用在后台运行，并关闭电池优化以获得最稳定的守护。'
                : 'Tip: Please allow background running in system settings and disable battery optimization for best stability.'}
            </p>
          </div>
        )
      }
    },
    {
      id: 'ios_shortcuts',
      title: lang === 'zh' ? 'iOS 苹果快捷指令' : 'iOS Apple Shortcuts',
      isCurrent: platform === 'ios',
      render: () => {
        const check = updateCheck['ios_shortcuts']
        return (
          <div>
            <p className="muted">{t('passive.setup.ios')}</p>
            
            <div className="psig__version-row" style={{ marginTop: '12px', marginBottom: '12px', display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
              <span className="psig__version-label" style={{ fontWeight: '600', fontSize: '0.85rem' }}>
                {lang === 'zh' ? `当前版本: v${APP_VERSION}` : `Version: v${APP_VERSION}`}
              </span>
              
              {(!check || check.status === 'idle') && (
                <button className="psig__small-btn" onClick={() => void handleCheckUpdate('ios_shortcuts')}>
                  {t('update.check')}
                </button>
              )}
              {check?.status === 'checking' && (
                <span className="psig__status-text">{t('update.checking')}</span>
              )}
              {check?.status === 'checked' && !check.isNew && (
                <span className="psig__status-text psig__status-text--ok">✓ {t('update.latest')}</span>
              )}
              {check?.status === 'checked' && check.isNew && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span className="psig__status-text psig__status-text--warn">
                    {t('update.found').replace('{v}', check.version || '')}
                  </span>
                  <button 
                    className="psig__small-btn psig__small-btn--highlight" 
                    onClick={() => void handleTriggerUpdate('ios_shortcuts', {})}
                  >
                    {lang === 'zh' ? '刷新应用' : 'Reload App'}
                  </button>
                </div>
              )}
            </div>

            <div style={{ display: 'flex', gap: '10px', marginTop: '12px' }}>
              {token && (
                <a className="psig__import" href={shortcutImportUrl(token)}>
                  {t('passive.import')}
                </a>
              )}
              <button className="share" disabled={!token} onClick={() => void copy()}>
                {t('passive.copy')}
              </button>
            </div>
          </div>
        )
      }
    },
    {
      id: 'windows_web',
      title: lang === 'zh' ? 'Windows 网页版 & 守护脚本' : 'Windows Web & CLI Hook',
      isCurrent: !isTauri() && desktopOS === 'windows',
      render: () => {
        const check = updateCheck['windows_web']
        return (
          <div>
            <p className="muted" style={{ fontWeight: '600', color: 'var(--fg)' }}>
              {lang === 'zh' ? '【推荐方案一】安装桌面原生 App (仅 7MB)' : '[Recommended Option 1] Install Native Desktop App (7MB)'}
            </p>
            <p className="muted" style={{ fontSize: '0.82rem' }}>
              {lang === 'zh'
                ? '支持开机自启、空闲自动感知、关闭窗口后后台运行与托盘小图标，体验最佳。'
                : 'Supports auto-start at login, system idle auto-ping, runs in background on close with tray icon.'}
            </p>
            <div style={{ display: 'flex', gap: '10px', marginTop: '10px', marginBottom: '16px', flexWrap: 'wrap' }}>
              <a className="psig__import" href="/desktop/KeepContact-Setup.exe" download="KeepContact-Setup.exe">
                {lang === 'zh' ? '下载 EXE 安装包' : 'Download EXE'}
              </a>
              <a className="psig__import" href="/desktop/KeepContact.msi" download="KeepContact.msi" style={{ backgroundColor: '#5c6bc0' }}>
                {lang === 'zh' ? '下载 MSI 安装包' : 'Download MSI'}
              </a>
            </div>

            <div className="psig__version-row" style={{ marginTop: '12px', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
              <span className="psig__version-label" style={{ fontWeight: '600', fontSize: '0.85rem' }}>
                {lang === 'zh' ? `当前网页版本: v${APP_VERSION}` : `Web Version: v${APP_VERSION}`}
              </span>
              
              {(!check || check.status === 'idle') && (
                <button className="psig__small-btn" onClick={() => void handleCheckUpdate('windows_web')}>
                  {t('update.check')}
                </button>
              )}
              {check?.status === 'checking' && (
                <span className="psig__status-text">{t('update.checking')}</span>
              )}
              {check?.status === 'checked' && !check.isNew && (
                <span className="psig__status-text psig__status-text--ok">✓ {t('update.latest')}</span>
              )}
              {check?.status === 'checked' && check.isNew && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span className="psig__status-text psig__status-text--warn">
                    {t('update.found').replace('{v}', check.version || '')}
                  </span>
                  <button 
                    className="psig__small-btn psig__small-btn--highlight" 
                    onClick={() => void handleTriggerUpdate('windows_web', {})}
                  >
                    {lang === 'zh' ? '刷新网页' : 'Reload Page'}
                  </button>
                </div>
              )}
            </div>

            <div className="psig__hookdiv" />

            <p className="muted" style={{ fontWeight: '600', color: 'var(--fg)' }}>
              {t('hook.pwa.title')}
            </p>
            <p className="muted" style={{ fontSize: '0.82rem' }}>
              {t('hook.pwa.desc')}
            </p>
            <ol className="psig__steps" style={{ margin: '8px 0' }}>
              <li>{t('hook.pwa.s1')}</li>
              <li>{t('hook.pwa.s2')}</li>
              <li>{t('hook.pwa.s3')}</li>
            </ol>

            <div className="psig__hookdiv" />

            <p className="muted" style={{ fontWeight: '600', color: 'var(--fg)' }}>
              {t('hook.win.title')}
            </p>
            <p className="muted" style={{ fontSize: '0.82rem' }}>
              {t('hook.win.desc')}
            </p>
            <p className="muted psig__hookwarn">{t('hook.win.smartscreen')}</p>
            <label className="psig__hookconsent">
              <input
                type="checkbox"
                checked={hookConsent}
                onChange={(e) => setHookConsent(e.target.checked)}
              />
              <span>{t('hook.win.consent')}</span>
            </label>
            <button
              className="psig__import"
              disabled={!token || !hookConsent}
              onClick={() => {
                if (!token) return
                downloadText(
                  'KeepContact-Setup.cmd',
                  buildWindowsHookCmd(
                    pingUrl(token),
                    summaryUrl(token),
                    window.location.origin,
                    LATEST_URL,
                    APP_VERSION,
                  ),
                )
              }}
            >
              {t('hook.win.download')}
            </button>
          </div>
        )
      }
    },
    {
      id: 'general',
      title: lang === 'zh' ? '常规配置与手动上报' : 'Manual Reporting & Others',
      isCurrent: !isTauri() && android !== 'native' && platform !== 'ios' && desktopOS !== 'windows',
      render: () => (
        <div>
          <p className="muted">
            {t('passive.desc')}
          </p>
          <p className="muted psig__triggers" style={{ marginTop: '10px' }}>
            {t('passive.triggers')}
          </p>
        </div>
      )
    }
  ]

  // Sort sections: current platform is pinned at index 0
  const sortedSections = [...sections].sort((a, b) => (b.isCurrent ? 1 : 0) - (a.isCurrent ? 1 : 0))
  const currentSectionId = sections.find(s => s.isCurrent)?.id || 'general'

  // Expanded section state (defaults to current platform)
  const [expanded, setExpanded] = useState<string | null>(currentSectionId)

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="signal" />
        {t('passive.title')}
      </h2>
      
      {error && <p className="home__error">{error}</p>}

      {/* Scan to Sync button (Only on mobile devices) */}
      {(platform === 'android' || platform === 'ios') && (
        <div style={{ marginBottom: '1.25rem' }}>
          <button
            className="psig__scan-btn"
            style={{
              width: '100%',
              padding: '0.75rem',
              background: 'var(--accent-soft)',
              color: 'var(--accent)',
              border: '1px solid var(--accent-line)',
              borderRadius: 'var(--r-md)',
              fontWeight: '600',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '6px'
            }}
            onClick={() => setIsScanning(true)}
          >
            <span>📷</span>
            {t('profile.scan')}
          </button>
        </div>
      )}

      {/* Global Status Box */}
      <div className="psig__status-box">
        <div className="psig__status-header">
          <strong>{lang === 'zh' ? '守护活跃度' : 'Active Status'}</strong>
          <span className="psig__status-badge">
            {todayCount > 0 ? (lang === 'zh' ? '运行中' : 'Running') : (lang === 'zh' ? '待活跃' : 'Idle')}
          </span>
        </div>
        
        <div className="psig__status-grid">
          <div className="psig__status-cell">
            <span className="psig__status-label">{lang === 'zh' ? '今日上报次数' : 'Today Pings'}</span>
            <span className="psig__status-value">{todayCount}</span>
          </div>
          <div className="psig__status-cell">
            <span className="psig__status-label">{lang === 'zh' ? '最近活跃时间' : 'Last Active'}</span>
            <span className="psig__status-value psig__status-value--time">
              {lastAt ? t('passive.last', { ago: ago(lastAt) }) : t('passive.never')}
            </span>
          </div>
        </div>

        <div className="psig__status-url-area">
          <div className="psig__status-url-title">{lang === 'zh' ? '专属上报 Webhook 链接' : 'Personal Webhook URL'}</div>
          <div className="psig__status-url-row">
            <code className="psig__status-code">{url}</code>
            <button className="psig__status-copy-btn" disabled={!token} onClick={() => void copy()}>
              {copied ? t('passive.copied') : t('passive.copy')}
            </button>
          </div>
        </div>
      </div>

      {/* Collapsible Accordion sorted by relevance */}
      <div className="psig__accordion">
        {sortedSections.map((s) => {
          const isOpen = expanded === s.id
          return (
            <div key={s.id} className={`psig__panel${s.isCurrent ? ' is-current' : ''}${isOpen ? ' is-open' : ''}`}>
              <button 
                type="button" 
                className="psig__panel-header"
                onClick={() => setExpanded(isOpen ? null : s.id)}
              >
                <div className="psig__panel-title-wrap">
                  <span>{s.title}</span>
                  {s.isCurrent && (
                    <span className="psig__panel-badge">
                      {lang === 'zh' ? '当前设备' : 'Current Device'}
                    </span>
                  )}
                </div>
                <span className="psig__panel-arrow">{isOpen ? '▲' : '▼'}</span>
              </button>
              {isOpen && (
                <div className="psig__panel-content">
                  {s.render()}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {isScanning && (
        <ScanSyncModal 
          onClose={() => setIsScanning(false)}
          onScan={(data) => void handleQrScan(data)}
        />
      )}
    </section>
  )
}

