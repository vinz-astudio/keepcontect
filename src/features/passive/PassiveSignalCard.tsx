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
import { getAvailableSensors, isSensorEnabled, setSensorEnabled } from '@/features/signals/sensors'
import { configureNativePassivePing } from '@/features/passive/native'
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
  
  const [todayCount, setTodayCount] = useState(0)
  const [lastAt, setLastAt] = useState<string | null>(null)
  const [token, setToken] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [hookConsent, setHookConsent] = useState(false)
  const [autostart, setAutostart] = useState(false)
  const [hasAutostartSupport, setHasAutostartSupport] = useState(false)
  const [sensorRefresh, setSensorRefresh] = useState(0)

  // Scan & Update check states
  const [isScanning, setIsScanning] = useState(false)
  const [updBusy, setUpdBusy] = useState(false)
  const [updStatus, setUpdStatus] = useState<'idle' | 'checking' | 'checked'>('idle')
  const [hasNewUpdate, setHasNewUpdate] = useState(false)
  const [newVersion, setNewVersion] = useState('')
  const [updateUrls, setUpdateUrls] = useState<{ apkUrl?: string; exeUrl?: string }>({})

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

  const loadData = useCallback(async () => {
    try {
      const tok = await getHeartbeatToken()
      setToken(tok)
      if (tok) {
        localStorage.setItem('kc.passiveToken', tok)
        const [c, l] = await Promise.all([countTodayPings(tok), lastPingAt(tok)])
        setTodayCount(c)
        setLastAt(l)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    }
  }, [])

  useEffect(() => {
    void loadData()
    const timer = setInterval(() => void loadData(), 30000)
    return () => clearInterval(timer)
  }, [loadData])

  const copy = async () => {
    if (!token) return
    const url = pingUrl(token)
    await navigator.clipboard.writeText(url)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  // Unified Update Check Handler
  async function handleCheckUpdate() {
    setUpdStatus('checking')
    await new Promise((r) => setTimeout(r, 800)) // Visual effect
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

  // Version Upgrade Handler
  async function handleTriggerUpdate() {
    if (isTauri() && updateUrls.exeUrl) {
      setUpdBusy(true)
      try {
        const internals = (window as any).__TAURI_INTERNALS__
        if (internals && typeof internals.invoke === 'function') {
          await internals.invoke('download_and_install', { url: updateUrls.exeUrl })
        } else {
          window.open(updateUrls.exeUrl, '_blank')
        }
      } catch (err) {
        console.error('Tauri update failed:', err)
        // Fallback command to open in browser safely
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
      }
    } else if (Capacitor.isNativePlatform() && updateUrls.apkUrl) {
      window.open(updateUrls.apkUrl, '_blank')
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

  const getDeviceLabel = () => {
    if (isTauri()) return lang === 'zh' ? 'Windows 桌面客户端' : 'Windows Desktop App'
    if (android === 'native') return lang === 'zh' ? 'Android 原生客户端' : 'Android Native App'
    if (platform === 'ios') return lang === 'zh' ? 'iOS 网页/快捷指令' : 'iOS Web/Shortcuts'
    if (platform === 'android') return lang === 'zh' ? 'Android 网页版' : 'Android Web PWA'
    return lang === 'zh' ? '网页版' : 'Web Browser'
  }

  const url = token ? pingUrl(token) : '...'

  // Accordion Sections definitions (Without duplicate update check buttons)
  const sections = [
    {
      id: 'windows_native',
      title: lang === 'zh' ? 'Windows 原生桌面守护' : 'Windows Tray Service',
      isCurrent: isTauri(),
      render: () => (
        <div>
          <p className="muted">
            {lang === 'zh' 
              ? '当前已运行在 Keep Contact 原生桌面版中。支持后台系统空闲自动感知上报，即使关闭窗口仍会在系统托盘中维持守护状态。'
              : 'Currently running inside Keep Contact native desktop app. Supports automatic idle detection reporting and runs in system tray when closed.'}
          </p>
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
    },
    {
      id: 'android_native',
      title: lang === 'zh' ? 'Android 原生自动化报活' : 'Android Native Service',
      isCurrent: android === 'native',
      render: () => (
        <div>
          <p className="muted">
            {t('passive.setup.androidNative')}
          </p>
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
    },
    {
      id: 'ios_shortcuts',
      title: lang === 'zh' ? 'iOS 苹果快捷指令联动' : 'iOS Apple Shortcuts Link',
      isCurrent: platform === 'ios',
      render: () => (
        <div>
          <p className="muted">{t('passive.setup.ios')}</p>
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
    },
    {
      id: 'windows_web',
      title: lang === 'zh' ? 'Windows 网页及自动化脚本' : 'Windows Web & CLI Script',
      isCurrent: !isTauri() && desktopOS === 'windows',
      render: () => (
        <div>
          <p className="muted" style={{ fontWeight: '600', color: 'var(--fg)' }}>
            {lang === 'zh' ? '安装桌面原生 App (仅 7MB，推荐)' : 'Install Native Desktop App (7MB, Recommended)'}
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
    },
    {
      id: 'general',
      title: lang === 'zh' ? '常规被动配置说明' : 'Manual Reporting & Others',
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

  const sortedSections = [...sections].sort((a, b) => (b.isCurrent ? 1 : 0) - (a.isCurrent ? 1 : 0))
  const currentSectionId = sections.find(s => s.isCurrent)?.id || 'general'
  const [expanded, setExpanded] = useState<string | null>(currentSectionId)

  const availableSensors = getAvailableSensors()

  return (
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
      {/* 1. Header with Title & Unified Version Info */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--line)', paddingBottom: '0.75rem', flexWrap: 'wrap', gap: '8px' }}>
        <h2 className="card__title" style={{ margin: 0 }}>
          <Icon name="signal" />
          {t('passive.title')}
        </h2>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '0.85rem' }}>
          <span style={{ fontWeight: '600' }}>v{APP_VERSION}</span>
          <span style={{ opacity: 0.6 }}>({getDeviceLabel()})</span>
        </div>
      </div>

      {/* 2. Unified Check Update Panel */}
      <div style={{ background: 'var(--bg-soft)', padding: '0.75rem 1rem', borderRadius: 'var(--r-md)', display: 'flex', flexDirection: 'column', gap: '8px', border: '1px solid var(--line)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
          <span style={{ fontSize: '0.9rem', fontWeight: '500' }}>
            {lang === 'zh' ? '检测最新版本与固件' : 'Check for System Updates'}
          </span>
          {updStatus === 'idle' && (
            <button className="psig__small-btn" onClick={() => void handleCheckUpdate()}>
              {t('update.check')}
            </button>
          )}
          {updStatus === 'checking' && (
            <span className="psig__status-text" style={{ fontSize: '0.85rem' }}>{t('update.checking')}</span>
          )}
          {updStatus === 'checked' && !hasNewUpdate && (
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <span className="psig__status-text psig__status-text--ok" style={{ fontSize: '0.85rem' }}>✓ {t('update.latest')}</span>
              <button className="psig__small-btn" onClick={() => void handleCheckUpdate()}>
                {lang === 'zh' ? '重新检测' : 'Re-check'}
              </button>
            </div>
          )}
        </div>
        
        {updStatus === 'checked' && hasNewUpdate && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', borderTop: '1px dashed var(--line)', paddingTop: '8px', marginTop: '4px' }}>
            <p className="psig__status-text psig__status-text--warn" style={{ fontSize: '0.85rem', margin: 0 }}>
              {t('update.found').replace('{v}', newVersion)}
            </p>
            <button 
              className="psig__small-btn psig__small-btn--highlight" 
              style={{ width: '100%', padding: '6px' }}
              disabled={updBusy}
              onClick={() => void handleTriggerUpdate()}
            >
              {updBusy 
                ? (lang === 'zh' ? '正在安装...' : 'Installing...') 
                : (isTauri() ? (lang === 'zh' ? '立即更新安装' : 'Update & Install') : (lang === 'zh' ? '下载新版本' : 'Download Update'))}
            </button>
          </div>
        )}
      </div>

      {/* 3. Toggleable Sensors List */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.6rem' }}>
        <h3 style={{ margin: '0 0 4px 0', fontSize: '0.95rem', fontWeight: '600' }}>
          {lang === 'zh' ? '本设备自动感知触发源' : 'Active Sensors on this Device'}
        </h3>
        <p className="muted" style={{ fontSize: '0.8rem', margin: '0 0 6px 0' }}>
          {lang === 'zh' 
            ? '勾选你希望自动收集的迹象。关闭的选项将不再自动上报报活。'
            : 'Toggle behaviors you want to monitor. Disabled options will not trigger auto check-in.'}
        </p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {availableSensors.map((sensor) => {
            const isEnabled = isSensorEnabled(sensor.key)
            return (
              <label 
                key={sensor.key} 
                className="psig__hookconsent" 
                style={{ 
                  display: 'flex', 
                  alignItems: 'flex-start', 
                  gap: '8px', 
                  cursor: sensor.supported ? 'pointer' : 'not-allowed',
                  padding: '8px',
                  borderRadius: 'var(--r-sm)',
                  background: 'var(--bg-soft)',
                  border: '1px solid var(--line)',
                  opacity: sensor.supported ? 1 : 0.4
                }}
              >
                <input
                  type="checkbox"
                  checked={isEnabled && sensor.supported}
                  disabled={!sensor.supported}
                  style={{ marginTop: '3px' }}
                  onChange={async (e) => {
                    await setSensorEnabled(sensor.key, e.target.checked)
                    setSensorRefresh(v => v + 1)
                  }}
                />
                <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                  <span style={{ fontSize: '0.88rem', fontWeight: '600', color: 'var(--fg)' }}>
                    {lang === 'zh' ? sensor.labelZh : sensor.labelEn}
                    {!sensor.supported && (
                      <span style={{ fontSize: '0.75rem', fontWeight: 'normal', opacity: 0.6, marginLeft: '6px' }}>
                        ({lang === 'zh' ? '当前设备不支持' : 'Not supported on this device'})
                      </span>
                    )}
                  </span>
                  <span className="muted" style={{ fontSize: '0.78rem', lineHeight: '1.3' }}>
                    {lang === 'zh' ? sensor.descZh : sensor.descEn}
                  </span>
                </div>
              </label>
            )
          })}
        </div>
      </div>

      {/* 4. Scan to Sync (Only on mobile devices) */}
      {(platform === 'android' || platform === 'ios') && (
        <div>
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

      {/* 5. Global Status Box */}
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

      {/* 6. Collapsible Accordions sorted by relevance */}
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
