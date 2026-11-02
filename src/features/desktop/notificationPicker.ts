// Desktop (Tauri) system notifications — DESK-01, 2026-11-02.
//
// The desktop app had no way to reach a user outside its own window: Web Push
// is disabled under Tauri and nothing else drew an OS notification, so a safety
// notice was only seen if the window happened to be open. The app lives in the
// tray, so its web layer keeps running; it watches the user's notifications
// (realtime, with a 60-second poll as fallback) and shows new unread ones as OS
// notifications using the same copy as the in-app list.

export interface NotifierRow {
  id: string
  created_at: string
  read_at: string | null
}

export interface NotifierCursor {
  /** Newest created_at already handled. */
  since: string
  /** Ids already shown, to break ties at the same timestamp. */
  seen: string[]
}

const SEEN_LIMIT = 200

/**
 * Which rows to show now. The first run shows nothing and starts the cursor at
 * `nowIso`, so installing or updating never replays old notifications. Read
 * rows are skipped: the user has already seen them in the app.
 */
export function pickNewNotifications<T extends NotifierRow>(
  rows: T[],
  cursor: NotifierCursor | null,
  nowIso: string,
): { show: T[]; cursor: NotifierCursor } {
  if (!cursor) return { show: [], cursor: { since: nowIso, seen: [] } }
  const since = Date.parse(cursor.since)
  const seen = new Set(cursor.seen)
  const show = rows
    .filter((row) => !row.read_at && !seen.has(row.id) && Date.parse(row.created_at) >= since)
    .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at))
  if (show.length === 0) return { show, cursor }
  const newest = show.reduce(
    (latest, row) => (Date.parse(row.created_at) > Date.parse(latest) ? row.created_at : latest),
    cursor.since,
  )
  return { show, cursor: { since: newest, seen: [...cursor.seen, ...show.map((row) => row.id)].slice(-SEEN_LIMIT) } }
}

export function readNotifierCursor(key: string): NotifierCursor | null {
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return null
    const parsed = JSON.parse(raw) as NotifierCursor
    return typeof parsed?.since === 'string' && Array.isArray(parsed.seen) ? parsed : null
  } catch {
    return null
  }
}

export function writeNotifierCursor(key: string, cursor: NotifierCursor): void {
  try {
    localStorage.setItem(key, JSON.stringify(cursor))
  } catch {
    /* storage unavailable: worst case a notice is shown again */
  }
}

/** Window event that asks the desktop notifier to check right away (after a self-test). */
export const DESKTOP_NOTIFIER_CHECK_EVENT = 'kc:desktop-notifier-check'

export function requestDesktopNotifierCheck(): void {
  try {
    window.dispatchEvent(new Event(DESKTOP_NOTIFIER_CHECK_EVENT))
  } catch {
    /* no window (tests, SSR) */
  }
}
