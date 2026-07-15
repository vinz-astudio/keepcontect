import { useState, useEffect, useCallback } from 'react'
import { Capacitor } from '@capacitor/core'
import { useI18n } from '@/lib/i18n'
import { isTauri } from '@/lib/platform'
import {
  isUsageStatsEnabled,
  openUsageStatsSettings,
  isActivityRecognitionEnabled,
  requestActivityRecognitionPermission,
  openAutostartSettings,
} from '@/features/passive/native'
import { getHeartbeatToken, pingUrl, PING_SOURCES } from '@/features/passive/api'
import './OnboardingWizard.css'

interface OnboardingWizardProps {
  isGm: boolean
  onComplete: () => void
}

export function OnboardingWizard({ isGm, onComplete }: OnboardingWizardProps) {
  const { lang } = useI18n()
  const platform = Capacitor.getPlatform()
  const isDesktop = isTauri()

  const [step, setStep] = useState(1)
  const [token, setToken] = useState<string | null>(null)

  // Android specific permissions state
  const [usageStatsOk, setUsageStatsOk] = useState(false)
  const [motionOk, setActivityRecognitionOk] = useState(false)

  // Desktop specific autostart state
  const [desktopAutostart, setDesktopAutostart] = useState(false)

  // Load token and initial permissions
  useEffect(() => {
    void getHeartbeatToken().then(setToken)
    if (platform === 'android') {
      void checkAndroidPermissions()
    }
    if (isDesktop) {
      void checkDesktopAutostart()
    }
  }, [platform, isDesktop])

  // Poll permissions on window focus/resume
  const checkAndroidPermissions = useCallback(async () => {
    if (platform !== 'android') return
    const uOk = await isUsageStatsEnabled()
    const mOk = await isActivityRecognitionEnabled()
    setUsageStatsOk(uOk)
    setActivityRecognitionOk(mOk)
  }, [platform])

  useEffect(() => {
    if (platform !== 'android') return
    window.addEventListener('focus', () => void checkAndroidPermissions())
    window.addEventListener('pageshow', () => void checkAndroidPermissions())
    return () => {
      window.removeEventListener('focus', () => void checkAndroidPermissions())
      window.removeEventListener('pageshow', () => void checkAndroidPermissions())
    }
  }, [platform, checkAndroidPermissions])

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

  // iOS One-Click import action
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

  // Next and prev step controls
  const next = () => setStep((s) => s + 1)
  const prev = () => setStep((s) => Math.max(1, s - 1))

  // Render Role-specific Step 1 (Welcome)
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

  // Render Role-specific Step 2 (Setup)
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

    // Recipient specific permission panels
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
          {platform === 'android' && (
            <>
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

              {/* Battery / Autostart Panel */}
              <div className="onb-panel">
                <div className="onb-panel__header">
                  <span className="onb-panel__title">
                    3. {lang === 'zh' ? '开机自启动与电池无限制' : 'Autostart & Battery Saver'}
                  </span>
                </div>
                <p className="onb-panel__desc">
                  {lang === 'zh'
                    ? '防止小米/华为/OPPO等系统因清理后台把常驻守护强制强杀。请将电池策略设为「无限制」，并允许自启动。'
                    : 'Prevents HyperOS/EMUI/OriginOS from killing the guard. Allow Autostart and set Battery to "No Restrictions".'}
                </p>
                <button className="onb-panel__btn" onClick={() => void openAutostartSettings()}>
                  {lang === 'zh' ? '打开系统自启动/省电设置' : 'Open Battery Settings'}
                </button>
              </div>
            </>
          )}

          {platform === 'ios' && (
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  {lang === 'zh' ? '苹果 iOS 快捷指令自动报活' : 'iOS Shortcuts Automation'}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? 'iOS 网页/PWA 在关闭后无法常驻后台。点击下方按钮导入官方快捷指令，绑定“解锁屏幕”或“插上充电器”即可让系统在后台帮您发送平安信号：'
                  : 'iOS PWA cannot run in the background after closing Safari. Import our official Shortcut to ping via system triggers (e.g. charging or unlock):'}
              </p>
              <button 
                className="onb-btn onb-btn--primary" 
                style={{ alignSelf: 'flex-start', fontSize: '0.82rem', padding: '8px 14px' }} 
                onClick={() => void importIosShortcut()}
              >
                📥 {lang === 'zh' ? '一键复制并导入快捷指令' : 'Copy URL & Import Shortcut'}
              </button>
            </div>
          )}

          {isDesktop && (
            <div className="onb-panel">
              <div className="onb-panel__header">
                <span className="onb-panel__title">
                  {lang === 'zh' ? '开机自启动设置' : 'Start on Boot'}
                </span>
                <span className={`onb-panel__status onb-panel__status--${desktopAutostart ? 'active' : 'inactive'}`}>
                  {desktopAutostart ? (lang === 'zh' ? '已启用' : 'Enabled') : (lang === 'zh' ? '未启用' : 'Disabled')}
                </span>
              </div>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '启用开机自启后，应用将在开机时静默运行于系统托盘，并在您使用电脑（打字/移鼠标）时自动感知平安状态。'
                  : 'Start on boot runs the app silently in the system tray. It will register active signs whenever you use your PC.'}
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
          )}

          {platform !== 'android' && platform !== 'ios' && !isDesktop && (
            <div className="onb-panel">
              <span className="onb-panel__title">
                {lang === 'zh' ? '网页版 (PWA) 最佳实践' : 'PWA Best Practices'}
              </span>
              <p className="onb-panel__desc">
                {lang === 'zh'
                  ? '1. 请将应用「添加到主屏幕」以独立窗口运行。\n2. 请经常打开应用同步数据。\n3. 可在系统设置中为本浏览器关闭省电模式以提升稳定性。'
                  : '1. Add the app to your Home Screen to run it as a standalone app.\n2. Open the app periodically to sync data.\n3. Turn off battery optimization for the browser to improve stability.'}
              </p>
            </div>
          )}
        </div>
      </>
    )
  }

  // Render Step 3 (Verification & Finish)
  const renderStep3 = () => {
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
            {isGm
              ? (lang === 'zh' ? '您已成功配置并了解守护者权限。请进入主控台开始添加和守望您的亲友。' : 'You are ready to go. Go to your dashboard to add and care for your loved ones.')
              : (lang === 'zh' ? '设备被动保活基座配置已就绪。系统将在后台默默值守您的平安状况。' : 'The background active sensing base is ready. Keep Contact will silently guard your safety in the background.')}
          </p>
        </div>
        <div className="onb-body">
          <div className="onb-panel" style={{ border: '1px solid var(--ok-soft)', background: 'rgba(92, 201, 154, 0.03)' }}>
            <p className="onb-panel__desc" style={{ color: 'var(--fg)', fontSize: '0.86rem' }}>
              💚 <strong>{lang === 'zh' ? '温馨提示' : 'Friendly Reminder'}</strong>
              <br />
              {lang === 'zh'
                ? '若您需要手动上报当前平安（如临时外出或准备去睡觉），随时长按底部的「SOS」环或者在首页轻点一下即可。'
                : 'If you want to manually report status (e.g. going out or ready to sleep), simply hold the SOS ring at the bottom or check-in on the home screen.'}
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
        
        {/* Progress indicator dots */}
        <div className="onb-progress">
          <span className={`onb-dot ${step === 1 ? 'is-active' : 'is-done'}`} />
          <span className={`onb-dot ${step === 2 ? 'is-active' : step > 2 ? 'is-done' : ''}`} />
          <span className={`onb-dot ${step === 3 ? 'is-active' : ''}`} />
        </div>

        {/* Dynamic Step Content */}
        {step === 1 && renderStep1()}
        {step === 2 && renderStep2()}
        {step === 3 && renderStep3()}

        {/* Footer controls */}
        <div className="onb-footer">
          {step > 1 ? (
            <button className="onb-btn onb-btn--muted" onClick={prev}>
              {lang === 'zh' ? '上一步' : 'Back'}
            </button>
          ) : (
            <div />
          )}

          {step < 3 ? (
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
