import { useCallback, useEffect, useRef, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import {
  getGuardianPermissions,
  sortByUrgency,
  summarizeDevicePermissions,
  type GuardianPermission,
  type PermissionState,
} from './guardianPermissions'
import { openAutostartSettings } from './native'
import { watchPermissionRefresh } from './permissionRefresh'
import './GuardianPermissionsCard.css'

const permissionLabels: Record<PermissionState, [string, string]> = {
  checking: ['检查中', 'Checking'],
  granted: ['已允许', 'Allowed'],
  denied: ['未开启', 'Off'],
  prompt: ['未开启', 'Off'],
  unavailable: ['未确认', 'Unverified'],
  limited: ['受限', 'Limited'],
  restricted: ['系统受限', 'Restricted'],
}

export function GuardianPermissionsCard() {
  const { lang } = useI18n()
  const zh = lang === 'zh'
  const [permissions] = useState(() => getGuardianPermissions())
  const [states, setStates] = useState<Record<string, PermissionState>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const [checking, setChecking] = useState(true)
  const generation = useRef(0)

  const refresh = useCallback(async () => {
    const request = ++generation.current
    setChecking(true)
    const entries = await Promise.all(
      permissions.map(async (permission): Promise<[string, PermissionState]> => {
        try {
          return [permission.id, await permission.check()]
        } catch {
          return [permission.id, 'unavailable']
        }
      }),
    )
    if (request !== generation.current) return
    setStates(Object.fromEntries(entries))
    setChecking(false)
  }, [permissions])

  useEffect(() => {
    void refresh()
    const stop = watchPermissionRefresh(() => {
      void refresh()
    })
    return () => {
      generation.current++
      stop()
    }
  }, [refresh])

  const summary = summarizeDevicePermissions(permissions, states, checking)
  const summaryText = {
    checking: zh ? '正在同步权限状态...' : 'Syncing permission status...',
    unavailable: zh ? '未能确认权限状态，可点击刷新重试。' : 'Could not verify permissions. Tap refresh to retry.',
    denied: zh ? '部分系统权限尚未开启，请按需设置。' : 'Some system permissions are not enabled.',
    prompt: zh ? '部分系统权限待开启。' : 'Some permissions are not enabled.',
    restricted: zh ? '部分系统权限受系统限制。' : 'Some permissions are restricted by the system.',
    limited: zh ? '部分系统权限受限。' : 'Some permissions are limited.',
    granted: zh ? '系统权限已全部就绪。' : 'All system permissions are ready.',
  }[summary]

  async function fix(permission: GuardianPermission) {
    setBusy(permission.id)
    try {
      await permission.fix()
      await refresh()
    } catch (cause) {
      toast(cause instanceof Error ? cause.message : String(cause), 'danger')
    } finally {
      setBusy(null)
    }
  }

  const isAndroid = Capacitor.getPlatform() === 'android'

  return (
    <div className="guardian-perms">
      <div className="guardian-perms__header">
        <p
          className={`guardian-perms__summary${summary !== 'granted' ? ' is-missing' : ''}`}
          data-summary={summary}
          aria-live="polite"
        >
          {summaryText}
        </p>
        <button
          type="button"
          className="prototype-button prototype-button--ghost guardian-perms__refresh"
          disabled={checking || busy !== null}
          onClick={() => void refresh()}
        >
          {checking ? (zh ? '同步中...' : 'Syncing...') : (zh ? '刷新' : 'Refresh')}
        </button>
      </div>

      {permissions.length === 0 ? (
        <p className="guardian-perms__none">
          {zh ? '当前设备无需配置额外的系统权限。' : 'No additional system permissions needed on this device.'}
        </p>
      ) : (
        <ul className="guardian-perms__list">
          {sortByUrgency(permissions, states).map((permission) => {
            const state = checking ? 'checking' : states[permission.id] ?? 'unavailable'
            const isGranted = state === 'granted'
            return (
              <li key={permission.id} className={`guardian-perms__item is-${state}`}>
                <div className="guardian-perms__text">
                  <span className="guardian-perms__label">
                    {zh ? permission.labelZh : permission.labelEn}
                  </span>
                  <span className="guardian-perms__cost">
                    {zh ? permission.costZh : permission.costEn}
                  </span>
                </div>
                <div className="guardian-perms__action">
                  <span className={`guardian-perms__status is-${state}`}>
                    {permissionLabels[state][zh ? 0 : 1]}
                  </span>
                  {!isGranted && state !== 'checking' && (
                    <button
                      type="button"
                      className="prototype-button prototype-button--ghost guardian-perms__fix-btn"
                      disabled={busy !== null || checking}
                      onClick={() => void fix(permission)}
                    >
                      {permission.fixIsSettings || state === 'denied' || state === 'restricted'
                        ? (zh ? '去设置' : 'Settings')
                        : (zh ? '开启' : 'Enable')}
                    </button>
                  )}
                </div>
              </li>
            )
          })}
        </ul>
      )}

      {isAndroid && (
        <div className="guardian-perms__footer">
          <button
            type="button"
            className="prototype-button prototype-button--ghost"
            onClick={() => void openAutostartSettings()}
          >
            {zh ? '打开系统自启动管理' : 'Open autostart settings'}
          </button>
        </div>
      )}
    </div>
  )
}
