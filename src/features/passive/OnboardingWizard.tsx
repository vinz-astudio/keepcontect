import { useState, useEffect, useCallback } from 'react'
import { Capacitor } from '@capacitor/core'
import { useI18n } from '@/lib/i18n'
import { getPlatform, isStandalone, isTauri } from '@/lib/platform'
import {
  isUsageStatsEnabled,
  openUsageStatsSettings,
  isActivityRecognitionEnabled,
  requestActivityRecognitionPermission,
  openAutostartSettings,
} from '@/features/passive/native'
import { getHeartbeatToken, pingUrl, PING_SOURCES, listRecentPings } from '@/features/passive/api'
import { getReadinessState, type OnboardingPlatform } from './onboardingState'
import './OnboardingWizard.css'

interface OnboardingWizardProps {
  isGm: boolean
  onComplete: () => void
}

export function OnboardingWizard({ isGm, onComplete }: OnboardingWizardProps) {
  const { lang } = useI18n()
  const p = getPlatform()
  const isDesktop = isTauri()
  const isNativeAndroid = p === 'android' && Capacitor.getPlatform() === 'android'
  const isPwa = isStandalone()

  // Determine Onboarding Platform Target
  let onboardingPlatform: OnboardingPlatform = 'plain_web'
  if (isDesktop) {
    onboardingPlatform = 'desktop_tauri'
  } else if (isNativeAndroid) {
    onboardingPlatform = 'android_native'
  } else if (p === 'ios') {
    onboardingPlatform = 'ios'
  } else if (p === 'android' && isPwa) {
    onboardingPlatform = 'android_pwa'
  } else {
    onboardingPlatform = 'plain_web'
  }

  const totalSteps = (isGm || onboardingPlatform === 'plain_web') ? 3 : 4

  const [step, setStep] = useState(1)
  const [token, setToken] = useState<string | null>(null)

  // Android specific permissions state
  const [usageStatsOk, setUsageStatsOk] = useState(false)
  const [motionOk, setActivityRecognitionOk] = useState(false)
  const [autostartAck, setAutostartAck] = useState(false)

  // Desktop specific autostart state
  const [desktopAutostart, setDesktopAutostart] = useState(false)

  // Test ping verification states
  const [pingOk, setPingOk] = useState(false)
  const [polling, setPolling] = useState(false)
  const [verifySecondsLeft, setVerifySecondsLeft] = useState(60)
  const [pingTimeout, setPingTimeout] = useState(false)

  // Load token and initial permissions
  useEffect(() => {
    void getHeartbeatToken().then(setToken)
    if (isNativeAndroid) {
      void checkAndroidPermissions()
    }
    if (isDesktop) {
      void checkDesktopAutostart()
    }
  }, [isNativeAndroid, isDesktop])

  // Poll permissions on window focus/resume
  const checkAndroidPermissions = useCallback(async () => {
    if (!isNativeAndroid) return
    const uOk = await isUsageStatsEnabled()
    const mOk = await isActivityRecognitionEnabled()
    setUsageStatsOk(uOk)
    setActivityRecognitionOk(mOk)
  }, [isNativeAndroid])

  useEffect(() => {
    if (!isNativeAndroid) return
    const handleCheck = () => {
      void checkAndroidPermissions()
    }
    window.addEventListener('focus', handleCheck)
    window.addEventListener('pageshow', handleCheck)
    return () => {
      window.removeEventListener('focus', handleCheck)
      window.removeEventListener('pageshow', handleCheck)
    }
  }, [isNativeAndroid, checkAndroidPermissions])

  // Desktop autostart helper
  const checkDesktopAutostart = async () => {
    try {
      const internals = (window as any).__TAURI_INTERNALS__
      if (internals && typeof internals.invoke === 'function') {
        const enabled = await internals.invoke('plugin:autostart|is_enabled')
        setDesktopAutostart(!!enabled)
      }
    } catch (err) {
      console.error('Failed to query desktop autostart status:', err)
    }
  }

  const toggleDesktopAutostart = async (val: boolean) => {
    try {
      const internals = (window as any).__TAURI_INTERNALS__
      if (internals && typeof internals.invoke === 'function') {
        if (val) {
          await internals.invoke('plugin:autostart|enable')
        } else {
          await internals.invoke('plugin:autostart|disable')
        }
        setDesktopAutostart(val)
      }
    } catch (err) {
      console.error('Failed to toggle desktop autostart:', err)
    }
  }

  // iOS Manual Clipboard helper (No one-click import claim)
  const importIosShortcut = async () => {
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

  // Verification step polling and countdown
  useEffect(() => {
    if (step === 3 && !isGm && onboardingPlatform !== 'plain_web') {
      setPingOk(false)
      setVerifySecondsLeft(60)
      setPingTimeout(false)
      setPolling(true)
    } else {
      setPolling(false)
    }
  }, [step, isGm, onboardingPlatform])

  useEffect(() => {
    if (!polling || pingOk || pingTimeout) return

    let timerId: number
    let pollId: number

    // Countdown timer
    timerId = window.setInterval(() => {
      setVerifySecondsLeft((prev) => {
        if (prev <= 1) {
          setPingTimeout(true)
          setPolling(false)
          return 0
        }
        return prev - 1
      })
    }, 1000)

    // Polling function
    const doPoll = async () => {
      try {
        const pings = await listRecentPings()
        const now = Date.now()
        const fiveMinutes = 5 * 60 * 1000
        const hasRecentPing = pings.some((p) => {
          const pingTime = new Date(p.at).getTime()
          return now - pingTime <= fiveMinutes
        })
        if (hasRecentPing) {
          setPingOk(true)
          setPolling(false)
        }
      } catch (err) {
        console.error('Error polling pings:', err)
      }
    }

    void doPoll()

    pollId = window.setInterval(() => {
      void doPoll()
    }, 3000)

    return () => {
      clearInterval(timerId)
      clearInterval(pollId)
    }
  }, [polling, pingOk, pingTimeout])

  // Next and prev step controls
  const next = () => setStep((s) => s + 1)
  const prev = () => setStep((s) => Math.max(1, s - 1))

  // Render Step 1 (Welcome)
  const renderStep1 = () => {
    if (isGm) {
      return (
        <>
          <div className="onb-illustration">
            <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z" />
              <path d="M9 12l2 2 4-4" />
            </svg>
          </div>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '守护者模式启动' : 'Caregiver Mode Activated'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '您已作为「守护者 (Caregiver)」登录。您可以通过主控制面板，实时感知被守护人身处安全、安心的状态，并在对方发生异常时接收主动预警。'
                : 'You are logged in as a Caregiver. You will monitor the safety status of your loved ones in real-time and receive alerts when anomalous inactive periods are detected.'}
            </p>
          </div>
          <div className="onb-body">
            <div className="onb-panel">
              <p className="onb-panel__desc" style={{ fontSize: '0.86rem' }}>
                💡 <strong>{lang === 'zh' ? '平静式健康守护' : 'Calm Safety Monitoring'}</strong>
                <br />
                {lang === 'zh'
                  ? 'Keep Contact 的设计主旨是「平静技术」。我们不收集被守护者的聊天记录、不追踪 GPS 轨迹。当他们正常使用手机、行走活动时，系统会自动产生隐性的安全回执。'
                  : 'Keep Contact is designed as Calm Technology. We do not inspect private messages or track active GPS coordinates. When the care recipient uses their phone or walks, subtle safety check-ins are recorded.'}
              </p>
            </div>
          </div>
        </>
      )
    }

    return (
      <>
        <div className="onb-illustration">
          <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
            <circle cx="12" cy="11" r="3" />
          </svg>
        </div>
        <div className="onb-header">
          <h1 className="onb-title">
            {lang === 'zh' ? '被守护者设备初始化' : 'Care Recipient Device Setup'}
          </h1>
          <p className="onb-desc">
            {lang === 'zh'
              ? '为了在您遇到突发人身危机而无法操作手机时，您的家人能够及时收到预警，系统需要依靠底层的传感器和活跃监测在后台进行静默守护。'
              : 'To ensure your family receives timely safety alerts if you encounter an emergency and cannot operate your phone, the app needs light background active sensing.'}
          </p>
        </div>
        <div className="onb-body">
          <div className="onb-panel">
            <p className="onb-panel__desc" style={{ fontSize: '0.86rem' }}>
              🔒 <strong>{lang === 'zh' ? '我们绝不侵犯您的个人隐私：' : 'Your Privacy is 100% Guarded:'}</strong>
              <br />
              {lang === 'zh'
                ? '我们不读取您的短信和社交软件、不追踪精确 GPS 轨迹，仅在您携手机行走或解锁使用手机时进行静默的本地健康迹象采集。'
                : 'We do not read your text chats, social apps, or record real-time GPS locations. We only gather local interaction signs when you unlock your phone or walk.'}
            </p>
          </div>
        </div>
      </>
    )
  }

  // Render Step 2 (Setup/Config instructions)
  const renderStep2 = () => {
    if (isGm) {
      return (
        <>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '如何开始守望守护？' : 'How to Monitor Safely'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '请花一分钟了解 Keep Contact 的核心守护界面和功能使用。'
                : 'Take a minute to get familiar with Keep Contact\'s core safety indicators.'}
            </p>
          </div>
          <div className="onb-body" style={{ gap: '12px' }}>
            <div className="onb-panel">
              <span className="onb-panel__title" style={{ fontSize: '0.88rem' }}>
                👥 {lang === 'zh' ? '第一步：邀请或绑定被守护者' : 'Step 1: Invite Care Recipients'}
              </span>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '切到「社区」标签页，创建一个共享社区，生成邀请码并发送给您的父母或独居亲友。对方接受后即可建立联结。'
                  : 'Go to the "Circles" tab, create a community, and generate an invite link. Share it with your parents, elderly relatives, or friends living alone.'}
              </p>
            </div>
            <div className="onb-panel">
              <span className="onb-panel__title" style={{ fontSize: '0.88rem' }}>
                📊 {lang === 'zh' ? '第二步：关注状态看板' : 'Step 2: Check Safety Status Board'}
              </span>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '在主控制面板，您将直观地看到对方设备的自动感知报活记录（如行走、玩手机），无需对方频繁给您发微信保平安。'
                  : 'On the main screen, you will see a status board aggregating their device activity logs. You do not need to call or text them constantly to check on them.'}
              </p>
            </div>
            <div className="onb-panel">
              <span className="onb-panel__title" style={{ fontSize: '0.88rem' }}>
                ⏰ {lang === 'zh' ? '第三步：定义守护阈值' : 'Step 3: Define Safety Routine'}
              </span>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '可以在「作息」页设置他们的习惯（如最晚起床时间），超时无响应时，系统才会给您推送紧急安全警报。'
                  : 'In the "Routine" tab, set up their usual habits (like wake-up window). If they remain inactive past the limit, a safety alarm is triggered.'}
              </p>
            </div>
          </div>
        </>
      )
    }

    // Recipient specific platform configuration screens
    if (onboardingPlatform === 'android_native') {
      return (
        <>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '配置底座：允许后台静默守护' : 'Base Configuration: Background Guard'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '为了防止 App 在您锁屏后被系统休眠或误杀，请根据引导完成您的设备授权。'
                : 'To prevent the system from killing the background monitoring when your screen is locked, please grant permissions:'}
            </p>
          </div>
          <div className="onb-body">
            {/* Usage Stats Panel */}
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  1. {lang === 'zh' ? '手机使用情况监测' : 'Usage Stats Access'}
                </span>
                <span className={`onb-panel__status onb-panel__status--${usageStatsOk ? 'active' : 'inactive'}`}>
                  {usageStatsOk ? (lang === 'zh' ? '已授权' : 'Granted') : (lang === 'zh' ? '待授权' : 'Grant')}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '用于检测日常玩手机、亮屏交互和解锁等最被动的平安迹象。'
                  : 'Checks passive interaction signs such as screen unlocks and daily app usage.'}
              </p>
              {!usageStatsOk && (
                <button className="onb-panel__btn" onClick={() => void openUsageStatsSettings()}>
                  {lang === 'zh' ? '去开启' : 'Go to Settings'}
                </button>
              )}
            </div>

            {/* Activity Recognition Panel */}
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  2. {lang === 'zh' ? '运动状态活跃监测' : 'Motion Monitoring'}
                </span>
                <span className={`onb-panel__status onb-panel__status--${motionOk ? 'active' : 'inactive'}`}>
                  {motionOk ? (lang === 'zh' ? '已授权' : 'Granted') : (lang === 'zh' ? '待授权' : 'Grant')}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '用于在您携带手机散步、行走或移动时自动判定活跃。'
                  : 'Detects active status using system-level low-power motion sensors when walking.'}
              </p>
              {!motionOk && (
                <button className="onb-panel__btn" onClick={async () => {
                  await requestActivityRecognitionPermission()
                  await checkAndroidPermissions()
                }}>
                  {lang === 'zh' ? '去开启' : 'Go to Settings'}
                </button>
              )}
            </div>

            {/* Battery / Autostart Panel (Explicit instruction setting with manual ack) */}
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  3. {lang === 'zh' ? '开机自启动与电池无限制' : 'Autostart & Battery Saver'}
                </span>
                <span className={`onb-panel__status onb-panel__status--${autostartAck ? 'active' : 'inactive'}`}>
                  {autostartAck ? (lang === 'zh' ? '已确认' : 'Confirmed') : (lang === 'zh' ? '待确认' : 'Pending')}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '防止系统因清理后台把常驻守护强杀。请将电池策略设为「无限制」，并允许自启动。'
                  : 'Prevents system from killing the guard. Allow Autostart and set Battery to "No Restrictions".'}
              </p>
              <button className="onb-panel__btn" onClick={() => void openAutostartSettings()}>
                {lang === 'zh' ? '打开系统自启动/省电设置' : 'Open Battery Settings'}
              </button>
              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', marginTop: '6px' }}>
                <input
                  type="checkbox"
                  checked={autostartAck}
                  onChange={(e) => setAutostartAck(e.target.checked)}
                />
                <span style={{ fontSize: '0.82rem', fontWeight: '600' }}>
                  {lang === 'zh' ? '我已完成此设置' : 'I did this'}
                </span>
              </label>
            </div>
          </div>
        </>
      )
    }

    if (onboardingPlatform === 'ios') {
      return (
        <>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '打开快捷指令设置' : 'Open Shortcut setup'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? 'iOS 网页/PWA 在关闭后无法常驻后台。请导入官方快捷指令，绑定特定触发器以静默上报平安回执：'
                : 'iOS PWA cannot run in the background after closing. Import our official Shortcut to ping via system triggers:'}
            </p>
          </div>
          <div className="onb-body">
            {/* Install recommend panel if not standalone */}
            {!isPwa && (
              <div className="onb-panel" style={{ border: '1px solid var(--accent-soft)', background: 'rgba(92, 107, 192, 0.04)' }}>
                <p className="onb-panel__desc" style={{ color: 'var(--accent)', fontSize: '0.82rem', fontWeight: 'bold' }}>
                  💡 {lang === 'zh' ? '小提示：建议将本页面「添加到主屏幕」以获得独立 App 级别更稳定的守护体验。' : 'Tip: Add this page to your Home Screen for a more stable standalone App experience.'}
                </p>
              </div>
            )}

            {/* iOS Setup Step 1: Manual copy and link redirect */}
            <div className="onb-panel">
              <span className="onb-panel__title" style={{ fontSize: '0.88rem' }}>
                1. {lang === 'zh' ? '导入快捷指令' : 'Import Shortcut'}
              </span>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '点击下方按钮，复制您的个人报活链接并打开官方指令导入页面。'
                  : 'Tap below to copy your personal ping URL and load the official Apple Shortcut page.'}
              </p>
              <button 
                className="onb-btn onb-btn--primary" 
                style={{ alignSelf: 'flex-start', fontSize: '0.82rem', padding: '8px 14px' }} 
                onClick={() => void importIosShortcut()}
              >
                📥 {lang === 'zh' ? '复制报活链接并导入快捷指令' : 'Copy URL & Import'}
              </button>
            </div>

            {/* iOS Setup Step 2: Personal Automation setup triggers */}
            <div className="onb-panel">
              <span className="onb-panel__title" style={{ fontSize: '0.88rem' }}>
                2. {lang === 'zh' ? '创建个人自动化' : 'Create Personal Automation'}
              </span>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '请在苹果「快捷指令」App 切换至「自动化」并新建：'
                  : 'Open Apple Shortcuts -> "Automation" -> tap "+" to create:'}
              </p>
              <div className="onb-panel__desc" style={{ fontSize: '0.78rem', background: 'rgba(255,255,255,0.01)', padding: '8px', borderRadius: '4px', border: '1px dashed var(--line)' }}>
                <ul style={{ margin: 0, paddingLeft: '16px', display: 'flex', flexDirection: 'column', gap: '4px' }}>
                  <li>
                    {lang === 'zh'
                      ? '选择触发器：[接通电源] 或 [打开 App] 或 [停止闹钟]'
                      : 'Choose trigger: [Charger connected] or [App opened] or [Alarm stopped]'}
                  </li>
                  <li>
                    {lang === 'zh'
                      ? '设置运行选项为【立即运行】，并关闭【运行前询问】'
                      : 'Set option to "Run Immediately" and disable "Ask Before Running"'}
                  </li>
                  <li>
                    {lang === 'zh'
                      ? '执行动作选择刚导入的【Keep Contact Ping】快捷指令'
                      : 'Set Action to run the imported "Keep Contact Ping" Shortcut'}
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </>
      )
    }

    if (onboardingPlatform === 'android_pwa') {
      return (
        <>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '网页版 (PWA) 后台守护设置' : 'PWA Background Setup'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '常规网页/PWA 在关闭后容易被清理。请按照提示开启配置以确保后台运行。'
                : 'PWA running in browser tabs has background limits. Apply settings to protect background task:'}
            </p>
          </div>
          <div className="onb-body">
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  {lang === 'zh' ? '自启动与电池保护配置' : 'Autostart & Battery Strategy'}
                </span>
                <span className={`onb-panel__status onb-panel__status--${autostartAck ? 'active' : 'inactive'}`}>
                  {autostartAck ? (lang === 'zh' ? '已确认' : 'Confirmed') : (lang === 'zh' ? '待确认' : 'Pending')}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '请打开您所在浏览器（如 Chrome）的设置，允许自启动，并将其电池优化选项设为「无限制」。'
                  : 'Open settings of your browser (e.g. Chrome), allow Autostart, and set Battery to "No Restrictions".'}
              </p>
              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', marginTop: '6px' }}>
                <input
                  type="checkbox"
                  checked={autostartAck}
                  onChange={(e) => setAutostartAck(e.target.checked)}
                />
                <span style={{ fontSize: '0.82rem', fontWeight: '600' }}>
                  {lang === 'zh' ? '我已完成此设置' : 'I did this'}
                </span>
              </label>
            </div>
          </div>
        </>
      )
    }

    if (onboardingPlatform === 'desktop_tauri') {
      return (
        <>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '开机自启动设置' : 'Start on Boot'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '启用开机自启后，应用将在开机时静默运行于系统托盘，并在您使用电脑时自动感知平安状态。'
                : 'Start on boot runs the app silently in the system tray. It will register active signs when you use your PC.'}
            </p>
          </div>
          <div className="onb-body">
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  {lang === 'zh' ? '系统托盘自启启动' : 'Boot Autostart'}
                </span>
                <span className={`onb-panel__status onb-panel__status--${desktopAutostart ? 'active' : 'inactive'}`}>
                  {desktopAutostart ? (lang === 'zh' ? '已启用' : 'Enabled') : (lang === 'zh' ? '未启用' : 'Disabled')}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '开关启用后，系统每次开机时都将自动把守护加载到系统后台。'
                  : 'When toggled on, the active background sensing is automatically loaded at login.'}
              </p>
              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', marginTop: '6px' }}>
                <input
                  type="checkbox"
                  checked={desktopAutostart}
                  onChange={(e) => void toggleDesktopAutostart(e.target.checked)}
                />
                <span style={{ fontSize: '0.85rem', fontWeight: '600' }}>
                  {lang === 'zh' ? '开机时自动后台启动' : 'Launch automatically at system boot'}
                </span>
              </label>
            </div>
          </div>
        </>
      )
    }

    // plain_web (Ordinary browser tab) read-only install guide
    return (
      <>
        <div className="onb-header">
          <h1 className="onb-title">
            {lang === 'zh' ? '网页版限制说明' : 'Browser Tab Sandbox Limits'}
          </h1>
          <p className="onb-desc">
            {lang === 'zh'
              ? '当前设备处于普通浏览器标签页中，由于沙盒策略，关闭页面后无法进行后台值守。'
              : 'You are currently in a standard browser tab. Sandbox policies block background sensing when closed.'}
          </p>
        </div>
        <div className="onb-body">
          <div className="onb-panel" style={{ border: '1px solid var(--danger-soft)' }}>
            <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.84rem' }}>
              ⚠️ {lang === 'zh' ? '普通网页标签页无法发送自动被动保活，家人将无法收到您的自动安全反馈。' : 'Browser tabs cannot emit background heartbeats; Caregivers will not receive passive safety reports.'}
            </p>
          </div>
          <div className="onb-panel">
            <span className="onb-panel__title" style={{ fontSize: '0.88rem' }}>
              📥 {lang === 'zh' ? '最佳解决方案：' : 'Recommended Action:'}
            </span>
            <p className="onb-panel__desc" style={{ fontSize: '0.82rem', lineHeight: '1.4' }}>
              {lang === 'zh'
                ? '• 移动端：请使用浏览器菜单中「添加到主屏幕 / 安装应用」，使其作为 PWA 运行。\n• 桌面端 (Windows)：建议下载并运行桌面客户端以实现系统级默默值守。'
                : '• Mobile: Add to Home Screen / Install PWA to bypass background freezes.\n• Desktop (Windows): Download and install our Native Client for autostart & system idle guards.'}
            </p>
            {p === 'desktop' && (
              <div style={{ display: 'flex', gap: '8px', marginTop: '6px' }}>
                <a className="onb-panel__btn" style={{ textDecoration: 'none' }} href="/desktop/KeepContact-Setup.exe" download>
                  {lang === 'zh' ? '下载 Windows 客户端' : 'Download Windows App'}
                </a>
              </div>
            )}
          </div>
        </div>
      </>
    )
  }

  // Render Step 3 (Verification step - only shown if totalSteps === 4)
  const renderStep3 = () => {
    return (
      <>
        <div className="onb-header">
          <h1 className="onb-title">
            {lang === 'zh' ? '发送测试信号验证' : 'Send Test Ping Verification'}
          </h1>
          <p className="onb-desc">
            {lang === 'zh'
              ? '我们需要确认底层报活信号可以穿透并顺利送达服务器。'
              : 'Verify that background heartbeats are correctly reaching our servers.'}
          </p>
        </div>
        <div className="onb-body">
          <div className="onb-panel" style={{ background: 'rgba(255,255,255,0.01)', borderStyle: 'dashed' }}>
            <span className="onb-panel__title" style={{ fontSize: '0.86rem' }}>
              {lang === 'zh' ? '如何手动触发测试信号？' : 'How to trigger the ping:'}
            </span>
            <p className="onb-panel__desc" style={{ fontSize: '0.8rem', lineHeight: '1.4' }}>
              {onboardingPlatform === 'android_native' && (
                lang === 'zh'
                  ? '请退出至手机桌面，或者稍微走动/使用其他App，然后切回本应用。'
                  : 'Please press the home button, locking/unlocking or using other apps, then return to this app.'
              )}
              {onboardingPlatform === 'ios' && (
                lang === 'zh'
                  ? '请连接/断开充电器，或者打开刚才配置自动化对应的App，或在「快捷指令」App中手动点击运行刚导入的指令。'
                  : 'Please plug/unplug the charger, open your automated app, or open Shortcuts app to run the Shortcut manually.'
              )}
              {(onboardingPlatform === 'android_pwa' || onboardingPlatform === 'desktop_tauri') && (
                lang === 'zh'
                  ? '请在前台轻点页面，或者刷新/与本页面进行一次交互。'
                  : 'Please tap on this page or trigger an interaction on the window.'
              )}
            </p>
          </div>

          {pingOk ? (
            <div className="onb-panel" style={{ border: '1px solid var(--ok-soft)', background: 'rgba(92, 201, 154, 0.04)' }}>
              <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.86rem', fontWeight: 'bold' }}>
                ✅ {lang === 'zh' ? '服务器已收到测试回执！自动静默守护验证通过。' : 'Server Acknowledged! Silent background guard verified successfully.'}
              </p>
            </div>
          ) : polling ? (
            <div className="onb-panel" style={{ border: '1px solid var(--warn-soft)', background: 'rgba(251, 192, 45, 0.04)' }}>
              <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.86rem' }}>
                ⏳ {lang === 'zh' ? `正在等待测试信号，剩余 ${verifySecondsLeft} 秒...` : `Waiting for test ping, ${verifySecondsLeft}s remaining...`}
              </p>
            </div>
          ) : (
            <div className="onb-panel" style={{ border: '1px solid var(--danger-soft)', background: 'rgba(232, 100, 90, 0.04)' }}>
              <span className="onb-panel__title" style={{ color: 'var(--danger)', fontSize: '0.86rem' }}>
                ⚠️ {lang === 'zh' ? '未检测到信号回执' : 'No Ping Detected'}
              </span>
              <p className="onb-panel__desc" style={{ fontSize: '0.8rem', lineHeight: '1.4' }}>
                {lang === 'zh'
                  ? '系统在过去 5 分钟内未接收到该设备的有效回执。请确认是否正确配置并允许前述设置。您仍可以点击继续完成，稍后可随时在首页「签到」手动上报平安。'
                  : 'No heartbeat has been recorded in the last 5 minutes. Check if settings/Shortcut triggers are correct. You can proceed and manually check-in later via the home screen.'}
              </p>
            </div>
          )}
        </div>
      </>
    )
  }

  // Render Step 3 or 4 (Finish)
  const renderFinishStep = () => {
    if (isGm) {
      return (
        <>
          <div className="onb-illustration">
            <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="var(--ok)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
              <polyline points="22 4 12 14.01 9 11.01" />
            </svg>
          </div>
          <div className="onb-header">
            <h1 className="onb-title">
              {lang === 'zh' ? '一切就绪！' : 'All Configured!'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '您已成功配置并了解守护者权限。请进入主控台开始添加和守望您的亲友。'
                : 'You are ready to go. Go to your dashboard to add and care for your loved ones.'}
            </p>
          </div>
          <div className="onb-body">
            <div className="onb-panel" style={{ border: '1px solid var(--ok-soft)', background: 'rgba(92, 201, 154, 0.03)' }}>
              <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.86rem' }}>
                💚 <strong>{lang === 'zh' ? '温馨提示' : 'Friendly Reminder'}</strong>
                <br />
                {lang === 'zh'
                  ? '被守护者若需要手动上报当前平安（如临时外出或准备去睡觉），可在首页轻点「签到」按钮。底部的「SOS」环仅用于紧急求助（长按将触发紧急警报并通知家人），请勿用于日常签到。'
                  : 'To manually report safety (e.g. going out or ready to sleep), care recipients can tap the "Check-in" button on the home screen. The "SOS" ring at the bottom is for emergencies only (long-press triggers a panic alert); do not use it for daily check-ins.'}
              </p>
            </div>
          </div>
        </>
      )
    }

    if (onboardingPlatform === 'plain_web') {
      return (
        <>
          <div className="onb-illustration">
            <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="var(--danger)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
              <line x1="12" y1="9" x2="12" y2="13" />
              <line x1="12" y1="17" x2="12.01" y2="17" />
            </svg>
          </div>
          <div className="onb-header">
            <h1 className="onb-title" style={{ color: 'var(--danger)' }}>
              {lang === 'zh' ? '未启用后台守护' : 'Monitoring Inactive'}
            </h1>
            <p className="onb-desc">
              {lang === 'zh'
                ? '网页版普通浏览器标签页无法进行后台默默值守。'
                : 'Normal browser tab sandbox limitations block passive checks.'}
            </p>
          </div>
          <div className="onb-body">
            <div className="onb-panel" style={{ border: '1px solid var(--danger-soft)', background: 'rgba(232, 100, 90, 0.02)' }}>
              <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.86rem' }}>
                {lang === 'zh'
                  ? '因沙盒机制，当您关闭浏览器或页面进入后台时，守护将被休眠。我们极力推荐您下载 Windows 桌面客户端，或在手机上安装为 PWA (添加到主屏幕) 运行。'
                  : 'Background guard is currently inactive on this browser page. Download our desktop client or install PWA to guarantee passive safety checks.'}
              </p>
            </div>
          </div>
        </>
      )
    }

    // Other recipient platforms: gated finish view
    const readiness = getReadinessState({
      platform: onboardingPlatform,
      usageStatsOk,
      motionOk: motionOk,
      pingOk
    })

    return (
      <>
        <div className="onb-illustration">
          {readiness === 'ready' ? (
            <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="var(--ok)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
              <polyline points="22 4 12 14.01 9 11.01" />
            </svg>
          ) : (
            <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="var(--warn)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="12" x2="12" y2="16" />
              <line x1="12" y1="8" x2="12.01" y2="8" />
            </svg>
          )}
        </div>
        <div className="onb-header">
          <h1 className="onb-title">
            {readiness === 'ready' 
              ? (lang === 'zh' ? '一切就绪！' : 'All Configured!')
              : (lang === 'zh' ? '配置部分完成/未验证' : 'Partially Set Up / Unverified')}
          </h1>
          <p className="onb-desc">
            {readiness === 'ready'
              ? (lang === 'zh' ? '设备被动保活基座配置已就绪。系统将在后台默默值守您的平安状况。' : 'Background guard base is ready. Keep Contact will silently monitor your status.')
              : (lang === 'zh' ? '由于部分设置未通过，后台被动保活功能可能会受到系统限制。' : 'Some setup tasks are unverified. System power plans may restrict background runs.')}
          </p>
        </div>
        <div className="onb-body">
          {/* Detailed Gated Checklist Status */}
          <div className="onb-panel" style={{ fontSize: '0.82rem', gap: '8px' }}>
            <span className="onb-panel__title" style={{ fontSize: '0.84rem' }}>
              📋 {lang === 'zh' ? '被动感知项自检清单：' : 'Background Sensors Checklist:'}
            </span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' }}>
              {onboardingPlatform === 'android_native' && (
                <>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span>1. {lang === 'zh' ? '使用情况权限' : 'Usage Access'}</span>
                    <strong style={{ color: usageStatsOk ? 'var(--ok)' : 'var(--danger)' }}>
                      {usageStatsOk ? (lang === 'zh' ? '已授权' : 'Granted') : (lang === 'zh' ? '待授权' : 'Pending')}
                    </strong>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span>2. {lang === 'zh' ? '运动监测权限' : 'Motion Monitoring'}</span>
                    <strong style={{ color: motionOk ? 'var(--ok)' : 'var(--danger)' }}>
                      {motionOk ? (lang === 'zh' ? '已授权' : 'Granted') : (lang === 'zh' ? '待授权' : 'Pending')}
                    </strong>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span>3. {lang === 'zh' ? '省电/开机自启' : 'Battery/Autostart'}</span>
                    <strong style={{ color: autostartAck ? 'var(--ok)' : 'var(--danger)' }}>
                      {autostartAck ? (lang === 'zh' ? '已确认' : 'Confirmed') : (lang === 'zh' ? '待确认' : 'Pending')}
                    </strong>
                  </div>
                </>
              )}
              {onboardingPlatform === 'android_pwa' && (
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>1. {lang === 'zh' ? '省电/开机自启' : 'Battery/Autostart'}</span>
                  <strong style={{ color: autostartAck ? 'var(--ok)' : 'var(--danger)' }}>
                    {autostartAck ? (lang === 'zh' ? '已确认' : 'Confirmed') : (lang === 'zh' ? '待确认' : 'Pending')}
                  </strong>
                </div>
              )}
              {onboardingPlatform === 'desktop_tauri' && (
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>1. {lang === 'zh' ? '自启动设置' : 'Autostart'}</span>
                  <strong style={{ color: desktopAutostart ? 'var(--ok)' : 'var(--danger)' }}>
                    {desktopAutostart ? (lang === 'zh' ? '已开启' : 'Enabled') : (lang === 'zh' ? '未开启' : 'Disabled')}
                  </strong>
                </div>
              )}
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>{onboardingPlatform === 'android_native' ? '4.' : onboardingPlatform === 'ios' ? '1.' : '2.'} {lang === 'zh' ? '测试信号回执' : 'Test Ping Verification'}</span>
                <strong style={{ color: pingOk ? 'var(--ok)' : 'var(--danger)' }}>
                  {pingOk ? (lang === 'zh' ? '已验证' : 'Verified') : (lang === 'zh' ? '未验证' : 'Unverified')}
                </strong>
              </div>
            </div>
          </div>

          <div className="onb-panel" style={{ border: '1px solid var(--ok-soft)', background: 'rgba(92, 201, 154, 0.03)' }}>
            <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.86rem' }}>
              💚 <strong>{lang === 'zh' ? '温馨提示' : 'Friendly Reminder'}</strong>
              <br />
              {lang === 'zh'
                ? '若您需要手动上报当前平安（如临时外出或准备去睡觉），可在首页轻点「签到」按钮。底部的「SOS」环仅用于紧急求助（长按将触发紧急警报并通知家人），请勿用于日常签到。'
                : 'To manually report safety (e.g. going out or ready to sleep), tap the "Check-in" button on the home screen. The "SOS" ring at the bottom is for emergencies only (long-press triggers a panic alert); do not use it for daily check-ins.'}
              {readiness !== 'ready' && (
                <span style={{ display: 'block', marginTop: '6px', fontStyle: 'italic', opacity: 0.85 }}>
                  {lang === 'zh' 
                    ? '您随时可以先关闭并开始使用。之后可在「我」页面 -「常规被动配置说明」中继续完成设置。'
                    : 'You can close and start now. Resume and finish the setup later in the "Me" settings tab.'}
                </span>
              )}
            </p>
          </div>
        </div>
      </>
    )
  }

  return (
    <div className="onb-overlay">
      <div className="onb-card">
        <div className="onb-glow" />
        
        {/* Dynamic step progress indicator dots */}
        <div className="onb-progress">
          {Array.from({ length: totalSteps }).map((_, idx) => {
            const stepNum = idx + 1
            const isActive = step === stepNum
            const isDone = step > stepNum
            return (
              <span
                key={stepNum}
                className={`onb-dot ${isActive ? 'is-active' : isDone ? 'is-done' : ''}`}
              />
            )
          })}
        </div>

        {/* Dynamic Step Content */}
        {step === 1 && renderStep1()}
        {step === 2 && renderStep2()}
        {step === 3 && (totalSteps === 4 ? renderStep3() : renderFinishStep())}
        {step === 4 && renderFinishStep()}

        {/* Footer controls */}
        <div className="onb-footer">
          {step > 1 ? (
            <button className="onb-btn onb-btn--muted" onClick={prev}>
              {lang === 'zh' ? '上一步' : 'Back'}
            </button>
          ) : (
            <div />
          )}

          {step < totalSteps ? (
            <button className="onb-btn onb-btn--primary" onClick={next}>
              {lang === 'zh' ? '继续' : 'Next'}
            </button>
          ) : (
            <button className="onb-btn onb-btn--success" onClick={onComplete}>
              {lang === 'zh' ? '完成，开始使用' : 'Complete & Start'}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
