import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useState } from 'react'
import {
  getHeartbeatToken,
  pingUrl,
  PING_SOURCES,
} from '@/features/passive/api'
import { getPlatform, isTauri } from '@/lib/platform'
import { toast } from '@/lib/toast'
import { useI18n } from '@/lib/i18n'
import { APK_URL, getApkDownloadFilename } from '@/features/install/apk'

import { getAvailableSensors, isSensorEnabled, setSensorEnabled } from '@/features/signals/sensors'
import {
  getGuardMode,
  getGuardStatus,
  resolveGuardDemotion,
  isUsageStatsEnabled,
  openUsageStatsSettings,
  openAutostartSettings,
  type GuardMode,
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
  const [guardMode, setGuardMode] = useState<GuardMode | null>(null)
  const iosEvidenceReady = guard?.enabled === true && guard.evidenceConfigured === true

  const handleResolveDemotion = async (accepted: boolean) => {
    await resolveGuardDemotion(accepted)
    setGuardMode(await getGuardMode())
    toast(
      accepted
        ? (lang === 'zh' ? '已开启常驻守护' : 'Persistent guard is on')
        : (lang === 'zh' ? '守护将保持安静' : 'The guard will stay quiet'),
      'ok',
    )
  }


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
    const capPlatform = Capacitor.getPlatform()
    if (capPlatform === 'android' || capPlatform === 'ios') {
      const g = await getGuardStatus()
      setGuard(g)
      if (capPlatform === 'android') {
        setGuardMode(await getGuardMode())
      }
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
              <a className="psig__import" href={APK_URL} download={getApkDownloadFilename()}>
                {lang === 'zh' ? '下载安卓安装包 (.apk)' : 'Download Android APK'}
              </a>
            </div>
          )}
          {android === 'native' && (
            <div style={{ marginTop: '10px', display: 'flex', flexDirection: 'column', gap: '12px' }}>

              {/* KC has concluded this phone freezes it, and is asking before it
                  becomes visible. Raised here rather than as a notification: the
                  whole point of the request is that KC promised to stay out of
                  the shade, so announcing it there would break the promise while
                  asking permission to break it. */}
              {guardMode?.demotionPending && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', padding: '12px', background: 'var(--accent-soft)', borderLeft: '3px solid var(--accent)', borderRadius: 'var(--r-sm)' }}>
                  <strong style={{ fontSize: '0.88rem' }}>
                    {lang === 'zh' ? '这台手机在让 Keep Contact 休眠' : 'This phone keeps putting Keep Contact to sleep'}
                  </strong>
                  <p className="muted" style={{ margin: 0, fontSize: '0.82rem', lineHeight: 1.45 }}>
                    {lang === 'zh'
                      ? 'Keep Contact 本来安静地待在后台,不在通知栏留下任何东西。但这台手机会把它冻结,冻结时它就看不到您了,关心您的人也可能因此收到不必要的提醒。在通知栏常驻一条最小的状态,可以让它不被冻结。'
                      : 'Keep Contact has been sitting quietly in the background, leaving your notification shade alone. This phone keeps freezing it, and while frozen it cannot see you — which can send the people who care about you a needless alert. Keeping one small item in the shade stops it being frozen.'}
                  </p>
                  <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
                    <button
                      className="share"
                      style={{ background: 'var(--accent)', color: 'white', border: 'none', fontWeight: 'bold' }}
                      onClick={() => void handleResolveDemotion(true)}
                    >
                      {lang === 'zh' ? '好,显示状态' : 'Show it'}
                    </button>
                    <button className="share" onClick={() => void handleResolveDemotion(false)}>
                      {lang === 'zh' ? '保持安静' : 'Keep it quiet'}
                    </button>
                  </div>
                </div>
              )}

              <p className="muted" style={{ margin: 0, fontSize: '0.82rem', lineHeight: '1.45' }}>
                {lang === 'zh'
                  ? '采集开关与系统授权已集中到上方「采集权限」区块；这里保留后台守护运行状态，避免同一开关出现两份。'
                  : 'Collection toggles and system permissions live in the Collection permissions section above; this panel shows the guard runtime only.'}
              </p>

              {/* 3. Foreground Service Status */}
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px', flexWrap: 'wrap', padding: '8px 10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)', fontSize: '0.82rem' }}>
                <span style={{ fontWeight: '600' }}>
                  {lang === 'zh' ? '后台守护服务状态' : 'Background Guard Service'}
                </span>
                <strong style={{ color: guard?.enabled ? 'var(--ok)' : 'var(--danger)', flexShrink: 0, textAlign: 'right' }}>
                  {guard?.enabled
                    ? (lang === 'zh' ? '运行中 (前台通知常驻)' : 'Running (Foreground active)')
                    : (lang === 'zh' ? '未启动 (需授权上方权限)' : 'Not started (Grant permissions)')}
                </strong>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px', flexWrap: 'wrap', padding: '8px 10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)', fontSize: '0.82rem' }}>
                <span style={{ fontWeight: '600' }}>
                  {lang === 'zh' ? '被动证据采集状态' : 'Passive Evidence Collection'}
                </span>
                <strong style={{ color: guard?.evidenceConfigured ? 'var(--ok)' : 'var(--danger)', flexShrink: 0, textAlign: 'right' }}>
                  {guard?.evidenceConfigured
                    ? (lang === 'zh' ? '已绑定并可采集' : 'Bound and collecting')
                    : (lang === 'zh' ? '未就绪（仅心跳）' : 'Not ready (heartbeat only)')}
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

        const isNativeIos = Capacitor.getPlatform() === 'ios'
        return (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            {isNativeIos && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', padding: '10px', background: 'var(--bg-soft)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span style={{ fontWeight: 'bold', fontSize: '0.85rem' }}>
                    {lang === 'zh' ? 'iOS 原生解锁被动守护 (PassiveGuard)' : 'iOS Native Unlock Guard'}
                  </span>
                  <strong style={{ color: iosEvidenceReady ? 'var(--ok)' : 'var(--danger)', fontSize: '0.82rem' }}>
                    {iosEvidenceReady
                      ? (lang === 'zh' ? '运行中 (解锁静默告活已就绪)' : 'Running (Unlock detection active)')
                      : (lang === 'zh' ? '未就绪 (等待被动证据绑定)' : 'Not ready (Passive evidence binding required)')}
                  </strong>
                </div>
                <p className="muted" style={{ margin: 0, fontSize: '0.78rem', lineHeight: '1.3' }}>
                  {lang === 'zh'
                    ? '只采集 KC 能观察到的解锁和前台事件，不会把一般手机使用当作可见信号。保存 Routine 后，必须成功绑定被动证据才会显示“已就绪”。'
                    : 'Collects only KC-observable unlock and foreground events; general phone use is not visible to iOS. It shows ready only after passive evidence binds successfully.'}
                </p>
              </div>
            )}

            <p className="muted" style={{ margin: 0, fontSize: '0.85rem' }}>
              {lang === 'zh'
                ? '您也可以导入我们预设的 Apple 快捷指令，利用系统事件（如充电、特定 App 打开）触发静默报活：'
                : 'You can also import our pre-configured Apple Shortcut to trigger silent check-ins via system events (e.g. charging, specific app opened):'}
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
                    ? '点击上方按钮导入快捷指令，并将您的个人链接粘贴到设置问题中。'
                    : 'Tap the button above to import the Shortcut, pasting your link during setup.'}
                </li>
                <li>
                  {lang === 'zh'
                    ? '在快捷指令 App 中，切换到底部的【自动化】标签页，点击右上角【+】新建自动化。'
                    : 'In the Shortcuts app, switch to the "Automation" tab and tap the "+" icon.'}
                </li>
                <li>
                  {lang === 'zh'
                    ? '新建一个您需要的系统触发源（推荐：当“充电器连接时”、或当“屏幕解锁时”）。'
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
    }
  ]

  // 只显示这台设备。别的平台怎么采集,对着眼前这台机器做设置的人一点用都没有,
  // 而且它把「我这台到底设好了没有」这个唯一重要的问题淹掉了。
  const sortedSections = sections.filter((s) => s.isCurrent)
  // 默认收起。展开态一进页面就摊出两段密集说明,而那些内容只有想调细节的人才需要。
  const [expanded, setExpanded] = useState<string | null>(null)

  const syncAppActivityPermission = useCallback(async () => {
    if (Capacitor.getPlatform() !== 'android') return
    setSensorRefresh(v => v + 1)
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

  /**
   * The Android section above already renders these three, each wired to its
   * own permission prompt and status line. The generic list below then rendered
   * every supported sensor again, so an Android user got two checkboxes for the
   * same setting — both writing the same `kc.sensor.*` key, so they even
   * disagreed visually until the card re-rendered.
   *
   * The dedicated controls win because they carry the permission handling; the
   * generic list keeps whatever the platform section does not cover.
   */
  const SECTION_OWNED_SENSORS = ['app_activity', 'motion', 'phone_charger']
  const isDuplicatedBySection = (key: string) =>
    android === 'native' && SECTION_OWNED_SENSORS.includes(key)

  return (
    <div className="psig__card">

      {error && <p className="home__error">{error}</p>}

      {/* 守护活跃度已移至「作息」页短期组顶部(ActiveStatusBox) */}

      {/* 这一段的标题由外层区块给,卡片内部不再重复一次。 */}
      <div className="psig__sensors">
        <p className="psig__sensors-lead">
          {lang === 'zh'
            ? '勾选您希望自动收集的迹象。关闭的选项将不再自动上报报活。'
            : 'Toggle behaviors you want to monitor. Disabled options will not trigger auto check-in.'}
        </p>
        <div className="psig__sensor-list">
          {availableSensors.filter(s => s.supported && !isDuplicatedBySection(s.key)).map((sensor) => {
            const isEnabled = isSensorEnabled(sensor.key)
            return (
              <label
                key={sensor.key}
                className="psig__sensor-row"
              >
                <input
                  type="checkbox"
                  checked={isEnabled}
                  onChange={async (e) => {
                    const checked = e.target.checked
                    await setSensorEnabled(sensor.key, checked)
                    setSensorRefresh(v => v + 1)

                    if (sensor.key === 'app_activity' && checked) {
                      const usageOk = await isUsageStatsEnabled()
                      if (!usageOk) {
                        const ok = window.confirm(
                          lang === 'zh'
                            ? '启用“屏幕解锁与 App 使用监测”需要系统使用情况权限。点击确认将引导您开启系统授权。'
                            : 'Enabling Screen Unlock & App Usage requires Usage Access permission. Tap OK to open settings.',
                        )
                        if (ok) {
                          await openUsageStatsSettings()
                        }
                      }
                    }
                  }}
                />
                <div className="psig__sensor-text">
                  <span className="psig__sensor-label">
                    {lang === 'zh' ? sensor.labelZh : sensor.labelEn}
                  </span>
                  <span className="psig__sensor-desc">
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
    </div>
  )
}
