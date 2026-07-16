import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useState } from 'react'
import {
  getHeartbeatToken,
  pingUrl,
  PING_SOURCES,
} from '@/features/passive/api'
import { getPlatform, isTauri } from '@/lib/platform'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { APK_URL } from '@/features/install/apk'

import { getAvailableSensors, isSensorEnabled, setSensorEnabled } from '@/features/signals/sensors'
import {
  getGuardStatus,
  isUsageStatsEnabled,
  openUsageStatsSettings,
  isActivityRecognitionEnabled,
  requestActivityRecognitionPermission,
  openAutostartSettings,
  type GuardStatus,
} from '@/features/passive/native'

import './PassiveSignalCard.css'

function androidRuntime(): 'native' | 'web' | null {
  if (getPlatform() !== 'android') return null
  return Capacitor.getPlatform() === 'android' ? 'native' : 'web'
}

export function PassiveSignalCard() {
  const { t, lang } = useI18n()
  const platform = getPlatform()
  const android = androidRuntime()

  const [token, setToken] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [autostart, setAutostart] = useState(false)
  const [hasAutostartSupport, setHasAutostartSupport] = useState(false)
  const [_, setSensorRefresh] = useState(0)
  // Android:无障碍后台守护实况(设置开关 + 真实绑定/事件时间戳;轮询自动刷新)
  const [guard, setGuard] = useState<GuardStatus | null>(null)
  const [usageStatsEnabled, setUsageStatsEnabled] = useState(false)
  const [activityRecognitionEnabled, setActivityRecognitionEnabled] = useState(false)


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
      const g = await getGuardStatus()
      setGuard(g)
      setUsageStatsEnabled(await isUsageStatsEnabled())
      setActivityRecognitionEnabled(await isActivityRecognitionEnabled())
    }
  }, [])

  useEffect(() => {
    void loadData()
    const timer = setInterval(() => void loadData(), 30000)
    return () => clearInterval(timer)
  }, [loadData])


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
            <div style={{ marginTop: '10px', display: 'flex', flexDirection: 'column', gap: '12px' }}>

              {/* 1. Usage Stats Permission Panel */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', padding: '10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' }}>
                  <span style={{ fontSize: '0.85rem', fontWeight: 'bold' }}>
                    {lang === 'zh' ? '手机使用情况监测' : 'Usage Stats Monitor'}
                  </span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <strong style={{ color: usageStatsEnabled ? 'var(--ok)' : 'var(--danger)', fontSize: '0.82rem' }}>
                      {usageStatsEnabled ? (lang === 'zh' ? '已授权' : 'Granted') : (lang === 'zh' ? '未授权' : 'Not Granted')}
                    </strong>
                    {!usageStatsEnabled && (
                      <button className="share" style={{ padding: '2px 8px', fontSize: '0.78rem' }} onClick={() => void openUsageStatsSettings()}>
                        {lang === 'zh' ? '去开启' : 'Enable'}
                      </button>
                    )}
                  </div>
                </div>
                <p className="muted" style={{ margin: 0, fontSize: '0.78rem', lineHeight: '1.3' }}>
                  {lang === 'zh'
                    ? '应用在后台被动检测手机解锁、使用微信等活跃信号（绝不收集个人隐私或应用内容），离线时自动回溯。'
                    : 'Passively detects phone unlocks and active app signals in the background (no private content read) to check in.'}
                </p>
              </div>

              {/* 2. Activity Recognition Permission Panel */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', padding: '10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' }}>
                  <span style={{ fontSize: '0.85rem', fontWeight: 'bold' }}>
                    {lang === 'zh' ? '运动状态活跃监测' : 'Motion Monitoring'}
                  </span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <strong style={{ color: activityRecognitionEnabled ? 'var(--ok)' : 'var(--danger)', fontSize: '0.82rem' }}>
                      {activityRecognitionEnabled ? (lang === 'zh' ? '已授权' : 'Granted') : (lang === 'zh' ? '未授权' : 'Not Granted')}
                    </strong>
                    {!activityRecognitionEnabled && (
                      <button className="share" style={{ padding: '2px 8px', fontSize: '0.78rem' }} onClick={() => void requestActivityRecognitionPermission()}>
                        {lang === 'zh' ? '去开启' : 'Enable'}
                      </button>
                    )}
                  </div>
                </div>
                <p className="muted" style={{ margin: 0, fontSize: '0.78rem', lineHeight: '1.3' }}>
                  {lang === 'zh'
                    ? '在您携手机行走或运动时，通过系统级低能耗加速度与计步状态判定活跃，无需点亮屏幕。'
                    : 'Detects active status using system-level low-power motion sensors when walking or moving around.'}
                </p>
              </div>

              {/* 3. Foreground Service Status */}
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)', fontSize: '0.82rem' }}>
                <span>
                  {lang === 'zh' ? '后台守护服务状态' : 'Background Guard Service'}
                </span>
                <strong style={{ color: guard?.enabled ? 'var(--ok)' : 'var(--danger)' }}>
                  {guard?.enabled
                    ? (lang === 'zh' ? '运行中 (前台通知常驻)' : 'Running (Foreground active)')
                    : (lang === 'zh' ? '未启动 (需授权上方权限)' : 'Not started (Grant permissions)')}
                </strong>
              </div>

              <p className="muted" style={{ margin: 0, fontSize: '0.8rem' }}>
                {lang === 'zh'
                  ? '小米/HyperOS、华为等国产系统需开启「自启动」并将省电策略设为「无限制」，否则后台仍会被强杀。'
                  : 'On Xiaomi/HyperOS, Huawei, and others, you must enable "Autostart" and set battery to "No restrictions" to avoid background killing.'}
              </p>
              <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
                <button className="share" onClick={() => void openAutostartSettings()}>
                  {lang === 'zh' ? '打开自启动/省电设置' : 'Open Autostart / Battery settings'}
                </button>
              </div>
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
      render: () => {
        const importShortcut = async () => {
          if (!token) return
          const url = pingUrl(token, PING_SOURCES.SHORTCUT)
          try {
            await navigator.clipboard.writeText(url)
            alert(
              lang === 'zh'
                ? '✅ 报活链接已复制到剪贴板！\n\n即将打开快捷指令导入页面。请在弹出的“报活链接”输入框中【长按粘贴】刚才复制的链接，然后点击“添加快捷指令”即可。'
                : '✅ Ping URL copied to clipboard!\n\nOpening Shortcuts. Please long-press and [Paste] the copied URL into the "Ping URL" input field, then tap "Add Shortcut".'
            )
            window.open('https://www.icloud.com/shortcuts/8f0e9eef33174e9d9d4351f2ae43a11a', '_blank')
          } catch (err) {
            console.error('Failed to copy and redirect:', err)
          }
        }

        return (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            <p className="muted" style={{ margin: 0, fontSize: '0.85rem' }}>
              {lang === 'zh'
                ? '由于 iOS 系统的后台限制，网页/PWA 关闭后无法在后台运行。你可以导入我们预设的 Apple 快捷指令，利用系统事件（如充电、亮屏）触发静默报活，无需保持 App 开启：'
                : 'Due to iOS background restrictions, web/PWA mode cannot run in the background. Import our pre-configured Apple Shortcut to trigger silent check-ins via system events (e.g. charging, screen unlock) without keeping the app open:'}
            </p>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', margin: '4px 0' }}>
              <button 
                className="share" 
                style={{ alignSelf: 'flex-start', background: 'var(--accent)', color: 'white', border: 'none', padding: '10px 16px', fontWeight: 'bold' }} 
                disabled={!token} 
                onClick={() => void importShortcut()}
              >
                {lang === 'zh' ? '📥 一键复制并导入快捷指令' : '📥 Copy URL & Import Shortcut'}
              </button>
            </div>

            <div style={{ background: 'var(--accent-soft)', borderLeft: '3px solid var(--accent)', padding: '10px', borderRadius: 'var(--r-sm)', fontSize: '0.82rem', display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <strong style={{ color: 'var(--accent)' }}>
                {lang === 'zh' ? '导入后的自动化配置步骤：' : 'Next Steps to Enable Automation:'}
              </strong>
              <ol style={{ margin: 0, paddingLeft: '16px', lineHeight: '1.4', display: 'flex', flexDirection: 'column', gap: '4px' }}>
                <li>
                  {lang === 'zh'
                    ? '点击上方按钮导入快捷指令，并将你的个人链接粘贴到设置问题中。'
                    : 'Tap the button above to import the Shortcut, pasting your link during setup.'}
                </li>
                <li>
                  {lang === 'zh'
                    ? '在快捷指令 App 中，切换到底部的【自动化】标签页，点击右上角【+】新建自动化。'
                    : 'In the Shortcuts app, switch to the "Automation" tab and tap the "+" icon.'}
                </li>
                <li>
                  {lang === 'zh'
                    ? '新建一个你需要的系统触发源（推荐：当“充电器连接时”、或当“屏幕解锁时”）。'
                    : 'Select a trigger event (Recommended: "When Charger is Connected" or "When Lock Screen is Unlocked").'}
                </li>
                <li>
                  {lang === 'zh'
                    ? '将自动化运行选项设为【立即运行】，并关闭【运行前询问】。'
                    : 'Set the execution option to "Run Immediately" and turn off "Ask Before Running".'}
                </li>
                <li>
                  {lang === 'zh'
                    ? '在执行动作中选择运行刚导入的【Keep Contact Ping】快捷指令即可。'
                    : 'Set the action to run the imported "Keep Contact Ping" Shortcut.'}
                </li>
              </ol>
            </div>
          </div>
        )
      }
    },
    {
      id: 'windows_web',
      title: lang === 'zh' ? 'Windows 桌面 App' : 'Windows Desktop App',
      isCurrent: isTauri(),
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
      isCurrent: !isTauri() && android !== 'native' && platform !== 'ios',
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
    const usageOk = await isUsageStatsEnabled()
    const motionOk = await isActivityRecognitionEnabled()
    const current = isSensorEnabled('app_activity')
    const pending = localStorage.getItem('kc.sensor.app_activity.pendingPermissions') === 'true'

    if ((usageOk || motionOk) && pending) {
      localStorage.removeItem('kc.sensor.app_activity.pendingPermissions')
      await setSensorEnabled('app_activity', true)
      setSensorRefresh(v => v + 1)
      return
    }
    if (!usageOk && !motionOk && current) {
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
                      const usageOk = await isUsageStatsEnabled()
                      const motionOk = await isActivityRecognitionEnabled()
                      if (!usageOk && !motionOk) {
                        const ok = window.confirm(
                          lang === 'zh'
                            ? '启用日常活跃监测需要授权系统使用情况或运动感知权限。确认后将引导您开启权限；授权后返回 App，开关会自动变为启用。'
                            : 'Enabling activity tracking requires Usage Stats or Motion sensors permission. Continue to settings, authorize them, then return to the app and this switch will turn on automatically.',
                        )
                        await setSensorEnabled(sensor.key, false)
                        if (ok) {
                          localStorage.setItem('kc.sensor.app_activity.pendingPermissions', 'true')
                          await requestActivityRecognitionPermission()
                          await openUsageStatsSettings()
                        }
                        setSensorRefresh(v => v + 1)
                        return
                      }
                    }
                    await setSensorEnabled(sensor.key, checked)
                    if (sensor.key === 'app_activity' && !checked) {
                      localStorage.removeItem('kc.sensor.app_activity.pendingPermissions')
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
