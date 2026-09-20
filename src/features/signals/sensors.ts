import { Capacitor } from '@capacitor/core'
import { isTauri } from '@/lib/platform'
import { syncNativeSensorPreferences } from '@/features/passive/native'

export interface SensorConfig {
  key: string
  labelZh: string
  labelEn: string
  descZh: string
  descEn: string
  supported: boolean
}

export function getAvailableSensors(): SensorConfig[] {
  const ios = Capacitor.getPlatform() === 'ios'
  return [
    {
      key: 'interaction',
      labelZh: 'App 使用互动',
      labelEn: 'App Interaction',
      descZh: '记录您在 KC 页面内的触摸、点击等操作；不代表其他 App 的活动或后台运行。',
      descEn: 'Records interactions within KC, such as taps and clicks; does not monitor other apps or verify background execution.',
      supported: true
    },
    {
      key: 'system_idle',
      labelZh: '电脑鼠标键盘活跃',
      labelEn: 'Computer Mouse/Keyboard Activity',
      descZh: '桌面程序运行时，定期读取最近的输入活动时间；不采集按键内容。程序退出或系统探测失败时不可用。',
      descEn: 'Periodically reads recent input activity while the desktop app runs, without keystroke content. Unavailable when the app exits or the system probe fails.',
      supported: isTauri()
    },
    {
      key: 'app_activity',
      labelZh: ios ? 'iOS 被动活动采集' : '屏幕解锁与 App 使用监测',
      labelEn: ios ? 'iOS passive activity collection' : 'Screen Unlock & App Usage',
      descZh: ios
        ? '控制 iOS 原生采集；仅在系统允许运行时观察解锁、运动历史与充电变化，无法持续监测其他 App。'
        : '通过系统使用记录回看手机活动；只记录活动时间，不上传内容或应用名称。',
      descEn: ios
        ? 'Controls native collection of unlocks, motion history and charging changes when iOS allows execution. Cannot continuously monitor other apps.'
        : 'Reads device activity from system usage records; never uploads content or app names.',
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
      descZh: '在系统允许运行时观察稳定的充电连接变化；不需要额外系统授权。',
      descEn: 'Observes stable charging changes when the system allows execution; no additional OS permission is required.',
      supported: Capacitor.getPlatform() === 'android'
    }
  ].filter((sensor) => sensor.supported)
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
  if (!getAvailableSensors().some((sensor) => sensor.key === key)) {
    throw new Error('This collection control is not supported on this device.')
  }
  const previous = isSensorEnabled(key)
  localStorage.setItem(`kc.sensor.${key}`, enabled ? 'true' : 'false')
  try {
    const platform = Capacitor.getPlatform()
    if ((platform === 'android' || platform === 'ios') && key !== 'interaction') {
      await syncNativeSensorPreferences()
    }
  } catch (cause) {
    localStorage.setItem(`kc.sensor.${key}`, previous ? 'true' : 'false')
    throw cause
  }
  if (typeof window !== 'undefined') window.dispatchEvent(new Event('kc:sensor-preference-changed'))
}
