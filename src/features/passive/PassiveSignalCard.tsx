import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useState } from 'react'
import {
  getHeartbeatToken,
  pingUrl,
} from '@/features/passive/api'
import { getDesktopOS, getPlatform, isTauri } from '@/lib/platform'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { APK_URL } from '@/features/install/apk'

import { getAvailableSensors, isSensorEnabled, setSensorEnabled } from '@/features/signals/sensors'
import { getGuardStatus, isAccessibilityEnabled, openAccessibilitySettings, openAutostartSettings, type GuardStatus } from '@/features/passive/native'

import './PassiveSignalCard.css'

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
  const [copied, setCopied] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [autostart, setAutostart] = useState(false)
  const [hasAutostartSupport, setHasAutostartSupport] = useState(false)
  const [_, setSensorRefresh] = useState(0)
  // Android:无障碍后台守护实况(设置开关 + 真实绑定/事件时间戳;轮询自动刷新)
  const [guard, setGuard] = useState<GuardStatus | null>(null)


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
      if (tok) localStorage.setItem('kc.passiveToken', tok)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    }
    if (Capacitor.getPlatform() === 'android') {
      setGuard(await getGuardStatus())
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


  // Accordion Sections definitions (Without duplicate update check buttons)
  const sections = [
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
              <a className="psig__import" href={APK_URL} download>
                {lang === 'zh' ? '下载安卓安装包 (.apk)' : 'Download Android APK'}
              </a>
            </div>
          )}
          {android === 'native' && (
            <div style={{ marginTop: '10px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              {(() => {
                // 三态:未开启 / 已开启·运行中 / 已开启但服务没在运行(HyperOS 常见)。
                // 打开本 App 本身就会产生一次窗口事件,所以「最近事件」足以判活。
                const alive =
                  guard != null &&
                  guard.lastEventAt > 0 &&
                  Date.now() - guard.lastEventAt < 10 * 60 * 1000
                const state: 'loading' | 'off' | 'running' | 'dead' =
                  guard == null ? 'loading' : !guard.enabled ? 'off' : alive ? 'running' : 'dead'
                const label =
                  state === 'loading'
                    ? '…'
                    : state === 'off'
                      ? lang === 'zh' ? '未开启' : 'Off'
                      : state === 'running'
                        ? lang === 'zh' ? '运行中' : 'Running'
                        : lang === 'zh' ? '已开启但未运行' : 'Enabled but not running'
                return (
                  <>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px', padding: '8px 10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)' }}>
                      <span style={{ fontSize: '0.85rem' }}>
                        {lang === 'zh' ? '后台守护(无障碍)' : 'Background guard (Accessibility)'}
                        {' · '}
                        <strong style={{ color: state === 'running' ? 'var(--ok)' : 'var(--danger)' }}>
                          {label}
                        </strong>
                      </span>
                      {(state === 'off' || state === 'dead') && (
                        <button className="share" onClick={() => void openAccessibilitySettings()}>
                          {state === 'off'
                            ? lang === 'zh' ? '去开启' : 'Enable'
                            : lang === 'zh' ? '去修复' : 'Fix'}
                        </button>
                      )}
                    </div>
                    {state === 'dead' && (
                      <p className="muted" style={{ margin: 0, fontSize: '0.78rem', color: 'var(--danger)' }}>
                        {lang === 'zh'
                          ? '系统显示无障碍已开启,但守护服务实际没在运行(小米/HyperOS 常见)。请到无障碍设置把 Keep Contact 的开关关掉再打开;仍不行就重启手机后再开一次。'
                          : 'The system shows Accessibility as enabled, but the guard service is not actually running (common on Xiaomi/HyperOS). Toggle Keep Contact off and on again in Accessibility settings; if that fails, reboot and re-enable.'}
                      </p>
                    )}
                  </>
                )
              })()}
              <p className="muted" style={{ margin: 0, fontSize: '0.8rem' }}>
                {lang === 'zh'
                  ? '小米/HyperOS 等国产系统还需：开启「自启动」、把省电策略设为「无限制」、不要在最近任务里清理本 App，否则守护会被系统杀掉。首次从应用商店外安装还需在「应用详情 → 右上角 ⋮ → 允许受限设置」解锁后才能打开无障碍。'
                  : 'On Xiaomi/HyperOS and similar ROMs, also enable Autostart, set battery saver to "No restrictions", and don\'t swipe this app away in recents — otherwise the system kills the guard. Sideloaded installs must first unlock "Allow restricted settings" (App info → ⋮) before Accessibility can be enabled.'}
              </p>
              <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
                <button className="share" onClick={() => void openAutostartSettings()}>
                  {lang === 'zh' ? '打开自启动/应用设置' : 'Open Autostart / App settings'}
                </button>
              </div>
              <p className="muted" style={{ margin: 0, fontSize: '0.78rem' }}>
                {lang === 'zh'
                  ? '守护上报最快每 5 分钟一次——测试时请与上次打开本 App 间隔 5 分钟以上再看效果。'
                  : 'The guard reports at most once every 5 minutes — when testing, wait 5+ minutes after last opening this app.'}
              </p>
            </div>
          )}
          {android !== 'native' && (
            <p className="muted" style={{ marginTop: '8px', fontSize: '0.82rem', color: 'var(--accent)' }}>
              {lang === 'zh'
                ? '提示：请在系统设置中允许本应用在后台运行，并关闭电池优化以获得最稳定的守护。'
                : 'Tip: Please allow background running in system settings and disable battery optimization for best stability.'}
            </p>
          )}
        </div>
      )
    },
    {
      id: 'ios_shortcuts',
      title: lang === 'zh' ? 'iOS 苹果快捷指令自动化 (推荐)' : 'iOS Apple Shortcuts Automation (Recommended)',
      isCurrent: platform === 'ios',
      render: () => (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <p className="muted" style={{ margin: 0, fontSize: '0.85rem' }}>
            {lang === 'zh'
              ? '由于 iOS 系统的后台限制，网页/PWA 关闭后无法自己捕获充电、闹钟或打开 App 等事件。你可以用 Apple 快捷指令自动化来触发报活：'
              : 'Due to iOS background restrictions, web/PWA mode cannot observe charging, alarms, or app-open events after it is closed. Use Apple Shortcuts automations to trigger check-ins:'}
          </p>
          
          <div style={{ background: 'var(--accent-soft)', borderLeft: '3px solid var(--accent)', padding: '10px', borderRadius: 'var(--r-sm)', fontSize: '0.82rem', display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <strong style={{ color: 'var(--accent)' }}>
              {lang === 'zh' ? '配置说明：' : 'Step-by-step Guide:'}
            </strong>
            <ol style={{ margin: 0, paddingLeft: '16px', lineHeight: '1.4', display: 'flex', flexDirection: 'column', gap: '4px' }}>
              <li>
                {lang === 'zh' 
                  ? '先复制下方的个人报活链接。'
                  : 'Copy your personal heartbeat URL below.'}
              </li>
              <li>
                {lang === 'zh'
                  ? '打开苹果自带的【快捷指令】App，手动创建一个名为 Keep Contact Ping 的快捷指令。'
                  : 'Open Apple\'s built-in "Shortcuts" app and manually create a Shortcut named Keep Contact Ping.'}
              </li>
              <li>
                {lang === 'zh'
                  ? '在快捷指令里添加【获取 URL 内容】动作，把刚才复制的链接填进去，并使用 HTTP GET。'
                  : 'Add a "Get Contents of URL" action, paste the copied URL, and leave it as HTTP GET.'}
              </li>
              <li>
                {lang === 'zh'
                  ? '切到【自动化】标签页，新建你需要的触发器，例如关闹钟、连接/断开充电器或每天会打开的 App。'
                  : 'Switch to the "Automation" tab and add triggers such as alarm dismissed, charger connected/disconnected, or an app you open daily.'}
              </li>
              <li>
                {lang === 'zh'
                  ? '把自动化设为【立即运行】，关闭【运行前询问】，并让它运行你刚手动创建的 Keep Contact Ping 快捷指令。'
                  : 'Set each automation to "Run Immediately", turn off "Ask Before Running", and run your manually created Keep Contact Ping Shortcut.'}
              </li>
            </ol>
          </div>

          <div style={{ display: 'flex', gap: '10px', marginTop: '4px', flexWrap: 'wrap' }}>
            <button className="share" disabled={!token} onClick={() => void copy()}>
              {copied ? t('passive.copied') : (lang === 'zh' ? '复制个人报活链接' : 'Copy Heartbeat URL')}
            </button>
          </div>
        </div>
      )
    },
    {
      id: 'windows_web',
      title: lang === 'zh' ? 'Windows 桌面 App' : 'Windows Desktop App',
      isCurrent: isTauri() || desktopOS === 'windows',
      render: () => (
        <div>
          {isTauri() && (
            <p className="muted">
              {lang === 'zh'
                ? '当前已运行在 Keep Contact 原生桌面版中；支持后台系统空闲自动感知、关闭窗口后托盘守护和开机自启。'
                : 'Currently running inside the Keep Contact desktop app. It supports background idle sensing, tray running after close, and auto-start at login.'}
            </p>
          )}
          {isTauri() && hasAutostartSupport && (
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
          <p className="muted" style={{ fontWeight: '600', color: 'var(--fg)' }}>
            {lang === 'zh' ? '安装桌面原生 App（推荐）' : 'Install Native Desktop App (Recommended)'}
          </p>
          <p className="muted" style={{ fontSize: '0.82rem' }}>
            {lang === 'zh'
              ? '支持开机自启、空闲自动感知、关闭窗口后后台运行与托盘小图标，体验最佳。'
              : 'Supports auto-start at login, system idle auto-ping, runs in background on close with tray icon.'}
          </p>
          <div style={{ display: 'flex', gap: '10px', marginTop: '10px', flexWrap: 'wrap' }}>
            <a className="psig__import" href="/desktop/KeepContact-Setup.exe" download="KeepContact-Setup.exe">
              {lang === 'zh' ? '下载 EXE 安装包' : 'Download EXE'}
            </a>
            <a className="psig__import" href="/desktop/KeepContact.msi" download="KeepContact.msi" style={{ backgroundColor: '#5c6bc0' }}>
              {lang === 'zh' ? '下载 MSI 安装包' : 'Download MSI'}
            </a>
          </div>
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

  const syncAppActivityPermission = useCallback(async () => {
    if (Capacitor.getPlatform() !== 'android') return
    const enabled = await isAccessibilityEnabled()
    const current = isSensorEnabled('app_activity')
    const pending = localStorage.getItem('kc.sensor.app_activity.pendingAccessibility') === 'true'
    if (enabled && pending) {
      localStorage.removeItem('kc.sensor.app_activity.pendingAccessibility')
      await setSensorEnabled('app_activity', true)
      setSensorRefresh(v => v + 1)
      return
    }
    if (!enabled && current) {
      localStorage.removeItem('kc.sensor.app_activity.pendingAccessibility')
      await setSensorEnabled('app_activity', false)
      setSensorRefresh(v => v + 1)
    }
  }, [])

  useEffect(() => {
    void syncAppActivityPermission()
    const onResume = () => void syncAppActivityPermission()
    const onVisible = () => {
      if (document.visibilityState === 'visible') onResume()
    }
    window.addEventListener('focus', onResume)
    window.addEventListener('pageshow', onResume)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      window.removeEventListener('focus', onResume)
      window.removeEventListener('pageshow', onResume)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [syncAppActivityPermission])

  const availableSensors = getAvailableSensors()

  return (
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
      {/* 1. Header with Title */}
      <h2 className="card__title" style={{ margin: 0, borderBottom: '1px solid var(--line)', paddingBottom: '0.75rem' }}>
        <Icon name="signal" />
        {t('passive.title')}
      </h2>

      {error && <p className="home__error">{error}</p>}

      {/* 守护活跃度已移至「作息」页短期组顶部(ActiveStatusBox) */}

      {/* Toggleable Sensors List */}
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
          {availableSensors.filter(s => s.supported).map((sensor) => {
            const isEnabled = isSensorEnabled(sensor.key)
            return (
              <label 
                key={sensor.key} 
                className="psig__hookconsent" 
                style={{ 
                  display: 'flex', 
                  alignItems: 'flex-start', 
                  gap: '8px', 
                  cursor: 'pointer',
                  padding: '8px',
                  borderRadius: 'var(--r-sm)',
                  background: 'var(--bg-soft)',
                  border: '1px solid var(--line)',
                }}
              >
                <input
                  type="checkbox"
                  checked={isEnabled}
                  style={{ marginTop: '3px' }}
                  onChange={async (e) => {
                    const checked = e.target.checked
                    if (sensor.key === 'app_activity' && checked) {
                      const alreadyGranted = await isAccessibilityEnabled()
                      if (!alreadyGranted) {
                        const ok = window.confirm(
                          lang === 'zh'
                            ? 'App 使用活跃需要先开启系统「无障碍」权限。确认后会打开 Android 设置；开启 Keep Contact 后返回 App，开关会自动变为启用。'
                            : 'App activity tracking needs Android Accessibility access. Continue to settings, enable Keep Contact, then return to the app and this switch will turn on automatically.',
                        )
                        await setSensorEnabled(sensor.key, false)
                        if (ok) {
                          localStorage.setItem('kc.sensor.app_activity.pendingAccessibility', 'true')
                          void openAccessibilitySettings()
                        }
                        setSensorRefresh(v => v + 1)
                        return
                      }
                    }
                    await setSensorEnabled(sensor.key, checked)
                    if (sensor.key === 'app_activity' && !checked) {
                      localStorage.removeItem('kc.sensor.app_activity.pendingAccessibility')
                    }
                    setSensorRefresh(v => v + 1)
                  }}
                />
                <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                  <span style={{ fontSize: '0.88rem', fontWeight: '600', color: 'var(--fg)' }}>
                    {lang === 'zh' ? sensor.labelZh : sensor.labelEn}
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

      {/* 4. Collapsible Accordions sorted by relevance */}
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
                <span className="psig__panel-title">{s.title}</span>
                <div className="psig__panel-right">
                  {s.isCurrent && (
                    <span className="psig__panel-badge">
                      {lang === 'zh' ? '当前设备' : 'Current Device'}
                    </span>
                  )}
                  <span className="psig__panel-arrow">{isOpen ? '▲' : '▼'}</span>
                </div>
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
