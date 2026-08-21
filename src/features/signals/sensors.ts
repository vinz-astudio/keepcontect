import { Capacitor } from '@capacitor/core'
import { isTauri } from '@/lib/platform'
import { configureNativePassivePing } from '@/features/passive/native'

export interface SensorConfig {
  key: string
  labelZh: string
  labelEn: string
  descZh: string
  descEn: string
  supported: boolean
}

export function getAvailableSensors(): SensorConfig[] {
  return [
    {
      key: 'interaction',
      labelZh: 'App 使用互动',
      labelEn: 'App Interaction',
      descZh: '您在页面上的触摸、点击，或打开本 App 的动作',
      descEn: 'Taps, clicks on page, or simply opening the app',
      supported: true
    },
    {
      key: 'system_idle',
      labelZh: '电脑鼠标键盘活跃',
      labelEn: 'Computer Mouse/Keyboard Activity',
      descZh: '每 2 分钟检测一次，若鼠标或键盘有活动则自动上报（保持后台静默守护）',
      descEn: 'Checks every 2 minutes. Automatically pings if mouse or keyboard activity is detected',
      supported: isTauri()
    },
    {
      key: 'app_activity',
      labelZh: '屏幕解锁与 App 使用监测',
      labelEn: 'Screen Unlock & App Usage',
      descZh: '离线或使用手机解锁、切换应用时在后台静默上报；只记录"在用手机"，绝不上报具体内容或应用名称',
      descEn: 'Passively detects screen unlocks and app usage signs in background (records device active time, never private content)',
      // iOS reports unlocks only — it has no app-usage equivalent — but it is
      // the same "am I using my phone" evidence, so it shares the toggle.
      supported: Capacitor.getPlatform() === 'android' || Capacitor.getPlatform() === 'ios'
    },
    {
      key: 'motion',
      labelZh: '运动状态活跃监测',
      labelEn: 'Motion Monitoring',
      descZh: '行走、跑步或携带手机移动时，通过系统低能耗感应器自动判定活跃',
      descEn: 'Detects active status using system-level low-power motion sensors when walking or moving around',
      supported: Capacitor.getPlatform() === 'android'
    },
    {
      key: 'phone_charger',
      labelZh: '插拔充电器',
      labelEn: 'Charger Connect/Disconnect',
      descZh: '接通充电器电源或断开充电器连接时，自动触发后台上报',
      descEn: 'Plugging in or unplugging the charger automatically triggers a background ping',
      supported: Capacitor.getPlatform() === 'android'
    }
  ]
}

const SENSOR_DEFAULTS: Record<string, boolean> = {
  app_activity: true,
  motion: true,
  phone_charger: true,
}

export function isSensorEnabled(key: string): boolean {
  try {
    const val = localStorage.getItem(`kc.sensor.${key}`)
    if (val === 'true') return true
    if (val === 'false') return false
    return SENSOR_DEFAULTS[key] ?? true
  } catch {
    return SENSOR_DEFAULTS[key] ?? true
  }
}

export async function setSensorEnabled(key: string, enabled: boolean): Promise<void> {
  try {
    localStorage.setItem(`kc.sensor.${key}`, enabled ? 'true' : 'false')
    
    // If we're on Android or iOS native app and changing native sensors, re-configure
    const platform = Capacitor.getPlatform()
    if (platform === 'android' || platform === 'ios') {
      const token = localStorage.getItem('kc.passiveToken')
      if (token) {
        await configureNativePassivePing(token)
      }
    }
  } catch {
    /* ignore */
  }
}
