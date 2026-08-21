import { useCallback, useEffect, useState } from 'react'
import { useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import {
  getGuardianPermissions,
  sortByUrgency,
  type GuardianPermission,
  type PermissionState,
} from './guardianPermissions'
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
  }, [permissions])

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

  if (permissions.length === 0) {
    return (
      <p className="guardian-perms__none">
          {zh
            ? '浏览器里没有可以授予的系统权限。装上 App 之后,这里会列出 KC 需要的权限和每一项的用途。'
            : 'A browser has no system permissions to grant. Once the app is installed, this lists what KC needs and why.'}
      </p>
    )
  }

  const missing = permissions.filter((p) => states[p.id] === 'denied').length

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

  return (
    <>
      <p className={`guardian-perms__summary${missing > 0 ? ' is-missing' : ''}`}>
        {missing === 0
          ? (zh ? 'KC 需要的权限都已开启。' : 'KC has everything it needs.')
          : (zh ? `有 ${missing} 项没有开启,KC 的守护是不完整的。` : `${missing} not granted. KC's guard is incomplete.`)}
      </p>
      <ul className="guardian-perms__list">
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
      </ul>
    </>
  )
}
