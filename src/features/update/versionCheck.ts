import { useCallback, useEffect, useState } from 'react'
import { APP_VERSION, LATEST_URL } from '@/lib/version'
import { translate } from '@/lib/i18n'
import { supabase } from '@/lib/supabase'
import {
  isNewer,
  selectLatestVersion,
  type VersionChannel,
  type VersionRecord,
} from '@/features/update/versionSelection'

export { isNewer }

export interface LatestInfo {
  version: string
  apkUrl?: string
  exeUrl?: string
  status?: Exclude<VersionChannel, 'public'>
  publicRollout?: boolean
}

export interface FetchLatestOptions {
  channel?: VersionChannel
}

interface DbVersionRow extends VersionRecord {
  apk_url?: string | null
  exe_url?: string | null
}

const NOTIFIED_DAY_KEY = 'kc.update.notifiedDay'
const DB_VERSION_LIMIT = 50

function toLatestInfo(row: DbVersionRow): LatestInfo {
  return {
    version: row.version,
    apkUrl: row.apk_url || undefined,
    exeUrl: row.exe_url || undefined,
    status: row.status ?? 'released',
    publicRollout: row.public_rollout === true,
  }
}

export async function fetchLatest(options: FetchLatestOptions = {}): Promise<LatestInfo | null> {
  const channel = options.channel ?? 'released'

  try {
    const { data: u } = await supabase.auth.getUser()
    if (u?.user) {
      let query = (supabase as any)
        .from('app_versions')
        .select('version, apk_url, exe_url, status, public_rollout, created_at')
        .order('created_at', { ascending: false })
        .limit(DB_VERSION_LIMIT)

      if (channel === 'canary') {
        query = query.in('status', ['canary', 'released'])
      } else if (channel === 'public') {
        query = query.or('status.eq.released,and(status.eq.canary,public_rollout.eq.true)')
      } else {
        query = query.eq('status', 'released')
      }

      const { data, error } = await query
      if (!error && Array.isArray(data) && data.length > 0) {
        const latest = selectLatestVersion(data as DbVersionRow[], channel)
        if (latest) return toLatestInfo(latest)
      }
    }
  } catch (err) {
    console.warn('Failed to fetch latest version from Supabase:', err)
  }

  try {
    const r = await fetch(LATEST_URL, { cache: 'no-store' })
    if (!r.ok) return null
    const j = (await r.json()) as Partial<LatestInfo>
    if (typeof j.version === 'string') {
      return { version: j.version, apkUrl: j.apkUrl, exeUrl: j.exeUrl, status: 'released' }
    }
  } catch {
    // Offline, CORS, preview, and shell cases should not interrupt app use.
  }
  return null
}

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
    // Notification failures are non-critical.
  }
}

export function useUpdateStatus(
  options: FetchLatestOptions = {},
): { latest: LatestInfo | null; outdated: boolean } {
  const [latest, setLatest] = useState<LatestInfo | null>(null)
  const channel = options.channel ?? 'released'

  const check = useCallback(async () => {
    const l = await fetchLatest({ channel })
    if (l) setLatest(l)
  }, [channel])

  useEffect(() => {
    void check()
    const onVisible = () => {
      if (document.visibilityState === 'visible') void check()
    }
    const onFocus = () => void check()
    const onOnline = () => void check()

    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('focus', onFocus)
    window.addEventListener('online', onOnline)
    const timer = window.setInterval(() => void check(), 30 * 60_000)
    return () => {
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('focus', onFocus)
      window.removeEventListener('online', onOnline)
      window.clearInterval(timer)
    }
  }, [check])

  const outdated = latest ? isNewer(latest.version, APP_VERSION) : false

  useEffect(() => {
    if (outdated) void maybeNotifyOnce(translate('update.notify'))
  }, [outdated])

  return { latest, outdated }
}
