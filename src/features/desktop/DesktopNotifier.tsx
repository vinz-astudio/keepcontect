import { useEffect } from 'react'
import { isPermissionGranted, requestPermission, sendNotification } from '@tauri-apps/plugin-notification'
import { useAuth } from '@/features/auth/AuthProvider'
import { listMyNotifications } from '@/features/alerts/api'
import { subscribeAlertSignals } from '@/features/alerts/realtime'
import { renderNotificationCopy } from '@/features/alerts/notificationCopy'
import { isTauri } from '@/lib/platform'
import { pickNewNotifications, readNotifierCursor, writeNotifierCursor } from '@/features/desktop/desktopNotifier'

const POLL_MS = 60_000

async function canNotify(): Promise<boolean> {
  try {
    if (await isPermissionGranted()) return true
    return (await requestPermission()) === 'granted'
  } catch {
    return false
  }
}

/** DESK-01: shows new unread notifications as OS notifications on the desktop app. */
export function DesktopNotifier() {
  const { user } = useAuth()
  const userId = user?.id
  const displayName = user?.user_metadata?.display_name as string | undefined
  const email = user?.email

  useEffect(() => {
    if (!isTauri() || !userId) return
    const key = `kc.desktopNotifier.cursor.${userId}`
    const viewer = { userId, displayName, email }
    let stopped = false
    let running = false
    let stopRealtime: (() => void) | null = null

    const check = async () => {
      if (running || stopped) return
      running = true
      try {
        const rows = (await listMyNotifications(30)).filter((row) => row.recipient_id === userId)
        const { show, cursor } = pickNewNotifications(rows, readNotifierCursor(key), new Date().toISOString())
        // Advance first: a failed toast is better than the same toast every minute.
        writeNotifierCursor(key, cursor)
        if (show.length > 0 && (await canNotify())) {
          for (const row of show) sendNotification({ title: 'Keep Contact', body: renderNotificationCopy(row, viewer) })
        }
      } catch {
        /* offline or signed out: the next poll retries */
      } finally {
        running = false
      }
    }

    void check()
    const timer = window.setInterval(() => void check(), POLL_MS)
    const onWake = () => void check()
    window.addEventListener('online', onWake)
    window.addEventListener('focus', onWake)
    void subscribeAlertSignals(onWake).then((stop) => {
      if (stopped) stop()
      else stopRealtime = stop
    })
    return () => {
      stopped = true
      window.clearInterval(timer)
      window.removeEventListener('online', onWake)
      window.removeEventListener('focus', onWake)
      stopRealtime?.()
    }
  }, [userId, displayName, email])

  return null
}
