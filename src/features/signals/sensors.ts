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
      descZh: '你在页面上的触摸、点击，或打开本 App 的动作',
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
      key: 'phone_unlock',
      labelZh: '手机屏幕解锁',
      labelEn: 'Phone Screen Unlock',
      descZh: '解锁手机屏幕进入系统时，自动触发后台上报',
      descEn: 'Unlocking the phone screen automatically triggers a background ping',
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

export function isSensorEnabled(key: string): boolean {
  try {
    const val = localStorage.getItem(`kc.sensor.${key}`)
    return val !== 'false' // default to true
  } catch {
    return true
  }
}

export async function setSensorEnabled(key: string, enabled: boolean): Promise<void> {
  try {
    localStorage.setItem(`kc.sensor.${key}`, enabled ? 'true' : 'false')
    
    // If we're on Android native app and changing native sensors, re-configure
    if (Capacitor.getPlatform() === 'android') {
      const token = localStorage.getItem('kc.passiveToken')
      if (token) {
        await configureNativePassivePing(token)
      }
    }
  } catch {
    /* ignore */
  }
}
