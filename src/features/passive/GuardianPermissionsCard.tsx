import { useCallback, useEffect, useMemo, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import {
  getGuardianPermissions,
  sortByUrgency,
  type GuardianPermission,
  type PermissionState,
} from './guardianPermissions'
import { getAvailableSensors, isSensorEnabled, setSensorEnabled, type SensorConfig } from '@/features/signals/sensors'
import { getGuardStatus, isActivityRecognitionEnabled, isUsageStatsEnabled, openUsageStatsSettings, requestActivityRecognitionPermission } from './native'
import { resolveCollectionCapabilities, type CollectionCapabilitySnapshot } from './collectionCapabilities'
import './GuardianPermissionsCard.css'

/**
 * 一处回答「这台设备被允许做什么」。
 *
 * 之前这些权限散在各自的功能里,用户没有办法一眼看出哪一项没给 —— 而没给的那些
 * 恰恰是静默失效的:功能看起来开着,实际上什么都收不到。所以这里写的是后果
 * (「KC 无法在判断你可能有事时问你」),不是权限名。
 */
export function GuardianPermissionsCard() {
  const { lang } = useI18n()
  const zh = lang === 'zh'
  const [permissions] = useState<GuardianPermission[]>(() => getGuardianPermissions())
  const [states, setStates] = useState<Record<string, PermissionState>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const [sensorStates, setSensorStates] = useState<Record<string, PermissionState>>({})
  const [capabilitySnapshot, setCapabilitySnapshot] = useState<CollectionCapabilitySnapshot | null>(null)
  const sensors = useMemo(() => getAvailableSensors(), [])

  const refresh = useCallback(async () => {
    const next: Record<string, PermissionState> = {}
    await Promise.all(permissions.map(async (permission) => {
      try {
        next[permission.id] = (await permission.check()) ? 'granted' : 'denied'
      } catch {
        next[permission.id] = 'unavailable'
      }
    }))
    setStates(next)
    const sensorNext: Record<string, PermissionState> = {}
    await Promise.all(sensors.map(async (sensor) => {
      try {
        const enabled = isSensorEnabled(sensor.key)
        const iosGuard = sensor.key === 'app_activity' && Capacitor.getPlatform() === 'ios'
          ? await getGuardStatus()
          : null
        const permission = sensor.key === 'app_activity' && Capacitor.getPlatform() === 'android'
          ? await isUsageStatsEnabled()
          : sensor.key === 'app_activity' && Capacitor.getPlatform() === 'ios'
            ? iosGuard?.enabled === true && iosGuard.evidenceConfigured === true
          : sensor.key === 'motion' && Capacitor.getPlatform() === 'android'
            ? await isActivityRecognitionEnabled()
            : true
        sensorNext[sensor.key] = enabled && permission ? 'granted' : 'denied'
      } catch {
        sensorNext[sensor.key] = 'unavailable'
      }
    }))
    setSensorStates(sensorNext)
    setCapabilitySnapshot(await resolveCollectionCapabilities())
  }, [permissions, sensors])

  useEffect(() => {
    void refresh()
    // 用户是去系统设置里改的,回到 App 才知道结果。
    const onFocus = () => void refresh()
    window.addEventListener('focus', onFocus)
    document.addEventListener('visibilitychange', onFocus)
    return () => {
      window.removeEventListener('focus', onFocus)
      document.removeEventListener('visibilitychange', onFocus)
    }
  }, [refresh])

  const missing = permissions.filter((p) => states[p.id] === 'denied').length
    + Object.values(sensorStates).filter((state) => state === 'denied').length

  async function fix(permission: GuardianPermission) {
    setBusy(permission.id)
    try {
      await permission.fix()
      await refresh()
      if (permission.fixIsSettings) {
        toast(zh ? '在系统设置里开启后回到 KC,这里会自动更新。' : 'Turn it on in system settings, then come back — this updates itself.', 'info')
      }
    } catch (cause) {
      toast(cause instanceof Error ? cause.message : String(cause), 'danger')
    }
    setBusy(null)
  }

  async function toggleSensor(sensor: SensorConfig, enabled: boolean) {
    setBusy(sensor.key)
    try {
      await setSensorEnabled(sensor.key, enabled)
      if (enabled && sensor.key === 'app_activity' && Capacitor.getPlatform() === 'android') {
        await openUsageStatsSettings()
      }
      if (enabled && sensor.key === 'motion' && Capacitor.getPlatform() === 'android') {
        await requestActivityRecognitionPermission()
      }
      await refresh()
    } catch (cause) {
      toast(cause instanceof Error ? cause.message : String(cause), 'danger')
    }
    setBusy(null)
  }

  return (
    <>
      {permissions.length === 0 && (
        <p className="guardian-perms__none">
          {zh
            ? '当前平台没有可授予的系统权限；下面仍会显示这台设备实际支持的采集开关。'
            : 'This platform has no system permission sheet; the supported collection controls are still shown below.'}
        </p>
      )}
      {capabilitySnapshot && (
        <>
          <p className="guardian-perms__surface">
            {zh ? `当前采集面：${capabilitySnapshot.distribution}` : `Collection surface: ${capabilitySnapshot.distribution}`}
          </p>
          {capabilitySnapshot.capabilities.some((capability) => capability.state === 'limited' || capability.state === 'unavailable') && (
            <p className="guardian-perms__surface guardian-perms__surface--notice">
              {zh
                ? '部分能力受当前平台限制；KC 只会把实际能观察到的事件计入活跃证据。'
                : 'Some capabilities are limited by this platform; KC counts only events it can actually observe.'}
            </p>
          )}
        </>
      )}
      <p className={`guardian-perms__summary${missing > 0 ? ' is-missing' : ''}`}>
        {missing === 0
          ? (zh ? 'KC 需要的权限都已开启。' : 'KC has everything it needs.')
          : (zh ? `有 ${missing} 项没有开启,KC 的守护是不完整的。` : `${missing} not granted. KC's guard is incomplete.`)}
      </p>
      {permissions.length > 0 && <ul className="guardian-perms__list">
        {sortByUrgency(permissions, states).map((permission) => {
          const state = states[permission.id] ?? 'checking'
          return (
            <li key={permission.id} className={`guardian-perms__item is-${state}`}>
              <div className="guardian-perms__text">
                <span className="guardian-perms__label">
                  {zh ? permission.labelZh : permission.labelEn}
                </span>
                {state !== 'granted' && (
                  <span className="guardian-perms__cost">
                    {zh ? permission.costZh : permission.costEn}
                  </span>
                )}
              </div>
              {state === 'granted' ? (
                <span className="guardian-perms__ok">{zh ? '已开启' : 'On'}</span>
              ) : (
                <button
                  type="button"
                  className="prototype-button prototype-button--ghost"
                  disabled={busy === permission.id || state === 'checking'}
                  onClick={() => void fix(permission)}
                >
                  {permission.fixIsSettings
                    ? (zh ? '去设置' : 'Settings')
                    : (zh ? '开启' : 'Turn on')}
                </button>
              )}
            </li>
          )
        })}
      </ul>}
      <div className="guardian-perms__sensors">
        <p className="guardian-perms__sensors-heading">{zh ? '采集开关' : 'Collection controls'}</p>
        <ul className="guardian-perms__list">
          {sensors.map((sensor) => {
            const state = sensorStates[sensor.key] ?? 'checking'
            const enabled = isSensorEnabled(sensor.key)
            return (
              <li key={sensor.key} className={`guardian-perms__item is-${state}`}>
                <div className="guardian-perms__text">
                  <span className="guardian-perms__label">{zh ? sensor.labelZh : sensor.labelEn}</span>
                  <span className="guardian-perms__cost">{zh ? sensor.descZh : sensor.descEn}</span>
                </div>
                <div className="guardian-perms__sensor-action">
                  <span className={`guardian-perms__status is-${state}`}>
                    {state === 'checking' ? (zh ? '检查中' : 'Checking') : state === 'granted' ? (zh ? '已授权' : 'Granted') : state === 'unavailable' ? (zh ? '不可用' : 'Unavailable') : (zh ? '未开启' : 'Denied')}
                  </span>
                  <button type="button" className="prototype-button prototype-button--ghost" disabled={busy === sensor.key || state === 'checking'} onClick={() => void toggleSensor(sensor, !enabled)}>
                    {enabled ? (zh ? '关闭' : 'Turn off') : (zh ? '开启' : 'Turn on')}
                  </button>
                </div>
              </li>
            )
          })}
        </ul>
      </div>
    </>
  )
}
