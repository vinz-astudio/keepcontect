import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { pickNewNotifications, type NotifierCursor } from '@/features/desktop/notificationPicker'

const row = (id: string, created_at: string, read_at: string | null = null) =>
  ({ id, created_at, read_at, kind: 'group', body: 'b', params: {} })

describe('desktop system notifications: which rows to show', () => {
  it('shows nothing on the first run, so history is not replayed', () => {
    const { show, cursor } = pickNewNotifications([row('a', '2026-11-02T10:00:00Z')], null, '2026-11-02T12:00:00Z')
    expect(show).toEqual([])
    expect(cursor).toEqual({ since: '2026-11-02T12:00:00Z', seen: [] })
  })

  it('shows unread rows newer than the cursor, oldest first, then advances the cursor', () => {
    const cursor: NotifierCursor = { since: '2026-11-02T12:00:00Z', seen: [] }
    const rows = [row('c', '2026-11-02T12:02:00Z'), row('b', '2026-11-02T12:01:00Z'), row('old', '2026-11-02T11:00:00Z')]
    const result = pickNewNotifications(rows, cursor, '2026-11-02T12:03:00Z')
    expect(result.show.map((n) => n.id)).toEqual(['b', 'c'])
    expect(result.cursor.since).toBe('2026-11-02T12:02:00Z')
    // The same poll again shows nothing.
    expect(pickNewNotifications(rows, result.cursor, '2026-11-02T12:04:00Z').show).toEqual([])
  })

  it('does not drop a second row that shares the cursor timestamp, and never repeats one', () => {
    const first = pickNewNotifications([row('x', '2026-11-02T12:05:00Z')],
      { since: '2026-11-02T12:00:00Z', seen: [] }, '2026-11-02T12:05:01Z')
    const second = pickNewNotifications([row('y', '2026-11-02T12:05:00Z'), row('x', '2026-11-02T12:05:00Z')],
      first.cursor, '2026-11-02T12:05:02Z')
    expect(second.show.map((n) => n.id)).toEqual(['y'])
  })

  it('skips rows the user already read in the app', () => {
    const result = pickNewNotifications([row('r', '2026-11-02T12:01:00Z', '2026-11-02T12:01:30Z')],
      { since: '2026-11-02T12:00:00Z', seen: [] }, '2026-11-02T12:02:00Z')
    expect(result.show).toEqual([])
  })

  it('keeps the seen list bounded', () => {
    const rows = Array.from({ length: 250 }, (_, i) => row(`n${i}`, '2026-11-02T12:01:00Z'))
    const result = pickNewNotifications(rows, { since: '2026-11-02T12:00:00Z', seen: [] }, '2026-11-02T12:02:00Z')
    expect(result.cursor.seen.length).toBeLessThanOrEqual(200)
  })
})

describe('desktop system notifications: wiring (DESK-01)', () => {
  const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8')
  it('registers the official notification plugin with permission', () => {
    expect(read('src-tauri/Cargo.toml')).toMatch(/tauri-plugin-notification\s*=/)
    expect(read('src-tauri/src/lib.rs')).toContain('.plugin(tauri_plugin_notification::init())')
    expect(JSON.parse(read('src-tauri/capabilities/default.json')).permissions).toContain('notification:default')
    expect(JSON.parse(read('package.json')).dependencies['@tauri-apps/plugin-notification']).toBeTruthy()
  })
  // DESK-02: the plugin drops toast clicks on Windows; the app's own command
  // shows the toast and brings the window to the front when it is clicked.
  it('shows notices through the click-aware command', () => {
    const lib = read('src-tauri/src/lib.rs')
    expect(lib).toMatch(/fn show_safety_notification\(/)
    expect(lib).toMatch(/on_activated\(move \|_\| \{\s*focus_main_window\(&handle\)/)
    expect(lib).toMatch(/generate_handler!\[[^\]]*show_safety_notification/)
    expect(read('src-tauri/Cargo.toml')).toMatch(/\[target\.'cfg\(windows\)'\.dependencies\]\s*\ntauri-winrt-notification = "0\.8"/)
    const notifier = read('src/features/desktop/DesktopNotifier.tsx')
    expect(notifier).toContain("invoke('show_safety_notification'")
    expect(notifier).not.toContain('sendNotification(')
  })
  // 2026-11-02: tray click and "Open Keep Contact" restore a minimized window too.
  it('opens the window from the tray through the restore-and-focus helper', () => {
    const lib = read('src-tauri/src/lib.rs')
    expect(lib).toContain('"show" => focus_main_window(app)')
    expect(lib).toMatch(/MouseButton::Left, \.\. \} = event \{\s*focus_main_window\(tray\.app_handle\(\)\)/)
    expect(lib).toMatch(/fn focus_main_window[\s\S]*?unminimize\(\)/)
  })

  it('mounts the notifier for signed-in desktop users', () => {
    expect(read('src/App.tsx')).toContain('<DesktopNotifier />')
  })
  // The panel used to be enabled for desktop while the button that opens it
  // stayed behind pushStatus === 'subscribed', and the v2 header (the only UI
  // mode) had no button at all, so nobody could reach the test tools.
  it('lets the desktop app open the self-test tools and send itself a test notification', () => {
    const card = read('src/features/alerts/NotificationsCard.tsx')
    expect(card).toContain("const canSelfTest = pushStatus === 'subscribed' || nativePushReady || desktop")
    expect(card).toContain('getNativeNotificationPermissionStatus().then((s) => setNativePushReady(s.granted))')
    expect(card).not.toContain("pushStatus === 'subscribed' && (")
    const v2Header = card.slice(card.indexOf('className="spatial-v2-header"'), card.indexOf(') : ('))
    expect(v2Header).toContain('{canSelfTest && (')
    expect(v2Header).toContain('setShowTools((v) => !v)')
    expect(card).toContain('if (desktop) requestDesktopNotifierCheck()')
    expect(read('src/features/desktop/DesktopNotifier.tsx')).toContain('addEventListener(DESKTOP_NOTIFIER_CHECK_EVENT, onWake)')
  })
})
