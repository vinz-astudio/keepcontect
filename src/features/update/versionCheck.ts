import { useCallback, useEffect, useState } from 'react'
import { APP_VERSION, LATEST_URL } from '@/lib/version'

export interface LatestInfo {
  version: string
  apkUrl?: string
}

const NOTIFIED_DAY_KEY = 'kc.update.notifiedDay'

function parse(v: string): number[] {
  return v
    .replace(/^v/i, '')
    .split('.')
    .map((n) => parseInt(n, 10) || 0)
}

/** latest 是否比 current 新(语义化:逐段比较 major.minor.patch) */
export function isNewer(latest: string, current: string): boolean {
  const a = parse(latest)
  const b = parse(current)
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const d = (a[i] ?? 0) - (b[i] ?? 0)
    if (d !== 0) return d > 0
  }
  return false
}

export async function fetchLatest(): Promise<LatestInfo | null> {
  try {
    const r = await fetch(LATEST_URL, { cache: 'no-store' })
    if (!r.ok) return null
    const j = (await r.json()) as Partial<LatestInfo>
    if (typeof j.version === 'string') {
      return { version: j.version, apkUrl: j.apkUrl }
    }
  } catch {
    /* 离线/跨域/预览环境等:静默忽略,不打扰 */
  }
  return null
}

/** 外部(系统)通知,最多一天一次。仅在已授权通知时触发。 */
async function maybeNotifyOnce(body: string): Promise<void> {
  try {
    if (typeof Notification === 'undefined' || Notification.permission !== 'granted') {
      return
    }
    const today = new Date().toISOString().slice(0, 10)
    if (localStorage.getItem(NOTIFIED_DAY_KEY) === today) return
    localStorage.setItem(NOTIFIED_DAY_KEY, today)
    const reg = await navigator.serviceWorker?.getRegistration?.()
    if (reg?.showNotification) {
      await reg.showNotification('Keep Contact', {
        body,
        tag: 'kc-update',
        icon: '/icons/icon-192.png',
      })
    } else {
      new Notification('Keep Contact', { body, tag: 'kc-update' })
    }
  } catch {
    /* ignore */
  }
}

/** 周期性 + 可见时检测版本;返回最新信息与是否过期。 */
export function useUpdateStatus(): { latest: LatestInfo | null; outdated: boolean } {
  const [latest, setLatest] = useState<LatestInfo | null>(null)

  const check = useCallback(async () => {
    const l = await fetchLatest()
    if (l) setLatest(l)
  }, [])

  useEffect(() => {
    void check()
    const onVisible = () => {
      if (document.visibilityState === 'visible') void check()
    }
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('focus', () => void check())
    const timer = window.setInterval(() => void check(), 6 * 3_600_000)
    return () => {
      document.removeEventListener('visibilitychange', onVisible)
      window.clearInterval(timer)
    }
  }, [check])

  const outdated = latest ? isNewer(latest.version, APP_VERSION) : false

  useEffect(() => {
    if (outdated) void maybeNotifyOnce('Keep Contact 有新版本可用,打开 App 升级。')
  }, [outdated])

  return { latest, outdated }
}
