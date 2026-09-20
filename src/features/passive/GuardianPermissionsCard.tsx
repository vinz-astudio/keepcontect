import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import { getGuardianPermissions, sortByUrgency, type GuardianPermission, type PermissionState } from './guardianPermissions'
import { getAvailableSensors, isSensorEnabled, setSensorEnabled, type SensorConfig } from '@/features/signals/sensors'
import { openUsageStatsSettings, requestActivityRecognitionPermission } from './native'
import { resolveCollectionCapabilities, type CollectionCapabilitySnapshot, type CollectionCapabilityId } from './collectionCapabilities'
import { summarizePermissions, sensorPresentationState } from './permissionPresentation'
import { watchPermissionRefresh } from './permissionRefresh'
import './GuardianPermissionsCard.css'

const sensorCapability: Record<string, CollectionCapabilityId> = {
  interaction: 'interaction', system_idle: 'desktop-input', app_activity: 'app-activity', motion: 'motion', phone_charger: 'charger',
}
const permissionLabels: Record<PermissionState, [string, string]> = {
  checking: ['检查中', 'Checking'], granted: ['系统已允许', 'Allowed by system'],
  denied: ['系统未允许', 'Not allowed'], prompt: ['待授权', 'Not requested'],
  unavailable: ['未能确认', 'Unverified'], limited: ['无法核实授权', 'Authorization unverifiable'],
  restricted: ['系统限制', 'Restricted by system'],
}
const sensorLabels = {
  granted: ['已启用', 'Enabled'], denied: ['缺少系统权限', 'Permission needed'],
  disabled: ['已关闭', 'Off'], limited: ['已启用 · 受限', 'Enabled · Limited'], unavailable: ['状态未确认', 'Unverified'],
}

export function GuardianPermissionsCard() {
  const { lang } = useI18n()
  const zh = lang === 'zh'
  const [permissions] = useState(() => getGuardianPermissions())
  const [states, setStates] = useState<Record<string, PermissionState>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const [checking, setChecking] = useState(true)
  const [capabilitySnapshot, setCapabilitySnapshot] = useState<CollectionCapabilitySnapshot | null>(null)
  const sensors = useMemo(() => getAvailableSensors(), [])
  const generation = useRef(0)

  const refresh = useCallback(async () => {
    const request = ++generation.current
    setChecking(true)
    const [entries, snapshot] = await Promise.all([
      Promise.all(permissions.map(async (permission): Promise<[string, PermissionState]> => {
        try { return [permission.id, await permission.check()] }
        catch { return [permission.id, 'unavailable'] }
      })),
      resolveCollectionCapabilities().catch(() => null),
    ])
    // A slow read from before a settings change must not overwrite the newer result.
    if (request !== generation.current) return
    setStates(Object.fromEntries(entries))
    setCapabilitySnapshot(snapshot)
    setChecking(false)
  }, [permissions])

  useEffect(() => {
    void refresh()
    const stop = watchPermissionRefresh(() => { void refresh() })
    return () => { generation.current++; stop() }
  }, [refresh])

  const summary = checking ? 'checking' : summarizePermissions(
    permissions.map((permission) => permission.id), states,
    capabilitySnapshot?.capabilities.map((capability) => capability.state) ?? null,
  )
  const summaryText = {
    checking: ['正在读取这台设备的权限状态。', 'Reading this device’s permission settings.'],
    unavailable: ['部分状态未能确认，请刷新检查或到系统设置核对。', 'Some settings could not be verified. Refresh or check system settings.'],
    denied: ['部分系统权限尚未允许，相关能力受限。', 'Some system permissions are not allowed; related capabilities are limited.'],
    prompt: ['部分权限待授权。', 'Some permissions have not been requested.'],
    limited: ['当前设备存在无法核实或受系统限制的能力。', 'Some capabilities remain unverified or limited by the system.'],
    granted: ['已核实可查询的系统权限；这不保证后台运行或通知送达。', 'Queryable system permissions verified; background execution and notification delivery are not guaranteed.'],
  }[summary][zh ? 0 : 1]

  async function fix(permission: GuardianPermission) {
    setBusy(permission.id)
    try { await permission.fix(); await refresh() }
    catch (cause) { toast(cause instanceof Error ? cause.message : String(cause), 'danger') }
    finally { setBusy(null) }
  }

  async function toggleSensor(sensor: SensorConfig, enabled: boolean) {
    setBusy(sensor.key)
    try {
      await setSensorEnabled(sensor.key, enabled)
      if (enabled && Capacitor.getPlatform() === 'android') {
        if (sensor.key === 'app_activity') await openUsageStatsSettings()
        if (sensor.key === 'motion') await requestActivityRecognitionPermission()
      }
    } catch (cause) { toast(cause instanceof Error ? cause.message : String(cause), 'danger') }
    finally { await refresh(); setBusy(null) }
  }

  return (
    <>
      <p className={`guardian-perms__summary${summary !== 'granted' ? ' is-missing' : ''}`} data-summary={summary} aria-live="polite">{summaryText}</p>
      <button type="button" className="prototype-button prototype-button--ghost" disabled={checking || busy !== null} onClick={() => void refresh()}>
        {zh ? '刷新检查' : 'Refresh checks'}
      </button>
      {permissions.length === 0 && <p className="guardian-perms__none">
        {zh ? '当前桌面版本未提供系统权限查询。下方只显示采集设置与探测结果。' : 'This desktop version has no system permission query. Collection settings and probe results are shown below.'}
      </p>}
      {permissions.length > 0 && <ul className="guardian-perms__list">
        {sortByUrgency(permissions, states).map((permission) => {
          const state = checking ? 'checking' : states[permission.id] ?? 'unavailable'
          return <li key={permission.id} className={`guardian-perms__item is-${state}`}>
            <div className="guardian-perms__text">
              <span className="guardian-perms__label">{zh ? permission.labelZh : permission.labelEn}</span>
              <span className="guardian-perms__cost">{zh ? permission.costZh : permission.costEn}</span>
            </div>
            <div className="guardian-perms__sensor-action">
              <span className={`guardian-perms__status is-${state}`}>{permissionLabels[state][zh ? 0 : 1]}</span>
              {state !== 'granted' && state !== 'limited' && state !== 'restricted' && (state !== 'unavailable' || Capacitor.isNativePlatform()) && (
                <button type="button" className="prototype-button prototype-button--ghost" disabled={busy !== null || checking} onClick={() => void fix(permission)}>
                  {permission.fixIsSettings ? (zh ? '去设置' : 'Settings') : (zh ? '设置权限' : 'Set permission')}
                </button>
              )}
            </div>
          </li>
        })}
      </ul>}
      <div className="guardian-perms__sensors">
        <p className="guardian-perms__sensors-heading">{zh ? '采集设置（不是系统授权）' : 'Collection settings (separate from OS permission)'}</p>
        <ul className="guardian-perms__list">
          {sensors.map((sensor) => {
            const enabled = isSensorEnabled(sensor.key)
            const capability = capabilitySnapshot?.capabilities.find((item) => item.id === sensorCapability[sensor.key])
            const state = sensorPresentationState(enabled, capability?.state)
            return <li key={sensor.key} className={`guardian-perms__item is-${state}`}>
              <div className="guardian-perms__text">
                <span className="guardian-perms__label">{zh ? sensor.labelZh : sensor.labelEn}</span>
                <span className="guardian-perms__cost">{zh ? sensor.descZh : sensor.descEn}</span>
              </div>
              <div className="guardian-perms__sensor-action">
                <span className={`guardian-perms__status is-${checking ? 'checking' : state}`}>
                  {checking ? (zh ? '检查中' : 'Checking') : sensorLabels[state][zh ? 0 : 1]}
                </span>
                <button type="button" className="prototype-button prototype-button--ghost" disabled={busy !== null || checking} onClick={() => void toggleSensor(sensor, !enabled)}>
                  {enabled ? (zh ? '关闭' : 'Turn off') : (zh ? '开启' : 'Turn on')}
                </button>
              </div>
            </li>
          })}
        </ul>
      </div>
    </>
  )
}
