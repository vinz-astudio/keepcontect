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

  // Accordion Sections definitions
  const sections = [
    {
      id: 'windows_native',
      title: lang === 'zh' ? 'Windows 桌面原生应用' : 'Windows Native App',
      isCurrent: isTauri(),
      render: () => (
        <div>
          <p className="muted">
            {lang === 'zh' 
              ? '当前已运行在 Keep Contact 原生桌面版中。支持后台系统空闲自动感知上报，即使关闭窗口仍会在系统托盘中维持守护状态。'
              : 'Currently running inside Keep Contact native desktop app. Supports automatic idle detection reporting and runs in system tray when closed.'}
          </p>
          {hasAutostartSupport && (
            <div className="psig__autostart-option" style={{ marginTop: '12px' }}>
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
      title: lang === 'zh' ? 'Android 安卓原生客户端' : 'Android Native App',
      isCurrent: android === 'native',
      render: () => (
        <div>
          <p className="muted">
            {t('passive.setup.androidNative')}
          </p>
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
      title: lang === 'zh' ? 'iOS 苹果快捷指令' : 'iOS Apple Shortcuts',
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
      title: lang === 'zh' ? 'Windows 网页版 & 守护脚本' : 'Windows Web & CLI Hook',
      isCurrent: !isTauri() && desktopOS === 'windows',
      render: () => (
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
    </section>
  )
}
