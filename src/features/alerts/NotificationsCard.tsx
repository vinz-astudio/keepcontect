import { useCallback, useEffect, useState } from 'react'
import {
  ackAlert,
  clearMyNotifications,
  deleteNotification,
  getAlert,
  getEmergencyInfoForUser,
  getProfileName,
  listMyNotifications,
  markNotificationRead,
  resolveAlert,
  type AppNotification,
  type Alert,
  type EmergencyInfo,
} from '@/features/alerts/api'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import {
  enablePush,
  getPushStatus,
  sendTestNotification,
  sendTestUnlock,
  type PushStatus,
} from '@/features/push/pushApi'
import './NotificationsCard.css'

interface ResponderItem {
  alert: Alert
  name: string
  emergency: EmergencyInfo | null
}

const NOTIF_KINDS = new Set([
  'self',
  'group',
  'community',
  'terminal',
  'on_it',
  'resolved',
  'task_invite',
  'task_due',
  'task_missed',
  'task_accepted',
  'task_declined',
  'test',
  'concern',
])

/** 优先按 kind+params 本地化渲染；旧数据/未知 kind 回退 body */
function renderNotif(n: AppNotification): string {
  if (!NOTIF_KINDS.has(n.kind)) return n.body
  const params = (n.params ?? {}) as Record<string, string>
  const fill = (v: string | undefined) => v || translate('notif.someone')
  return translate(`notif.${n.kind}` as I18nKey, {
    name: fill(params.name),
    actor: fill(params.actor),
    target: fill(params.target),
  })
}

function ago(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return translate('time.now')
  if (s < 3600) return translate('time.min', { n: Math.floor(s / 60) })
  if (s < 86400) return translate('time.hour', { n: Math.floor(s / 3600) })
  return translate('time.day', { n: Math.floor(s / 86400) })
}

export function NotificationsCard({
  onChanged,
}: {
  onChanged?: () => void
} = {}) {
  const { t } = useI18n()
  const [notifs, setNotifs] = useState<AppNotification[]>([])
  const [items, setItems] = useState<ResponderItem[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pushStatus, setPushStatus] = useState<PushStatus>('unsupported')
  const [testMsg, setTestMsg] = useState<string | null>(null)
  const [expanded, setExpanded] = useState(false)
  const [showTools, setShowTools] = useState(false)

  useEffect(() => {
    void getPushStatus().then(setPushStatus)
  }, [])

  const refresh = useCallback(async () => {
    setError(null)
    try {
      const list = await listMyNotifications()
      setNotifs(list)

      // 需要我响应的：有 alert_id 且为 group/community/terminal 的去重
      const ids = [
        ...new Set(
          list
            .filter(
              (n) =>
                n.alert_id &&
                ['group', 'community', 'terminal'].includes(n.kind),
            )
            .map((n) => n.alert_id as string),
        ),
      ]
      const built: ResponderItem[] = []
      for (const id of ids) {
        const alert = await getAlert(id)
        if (!alert || alert.status !== 'open') continue
        const [name, emergency] = await Promise.all([
          getProfileName(alert.user_id),
          getEmergencyInfoForUser(alert.user_id).catch(() => null),
        ])
        built.push({
          alert,
          name: name ?? translate('notif.someone'),
          emergency,
        })
      }
      setItems(built)
      onChanged?.() // 通知顶层同步未读数/角标
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    }
  }, [onChanged])

  useEffect(() => {
    void refresh()
    const timer = window.setInterval(() => void refresh(), 20_000)
    return () => window.clearInterval(timer)
  }, [refresh])

  async function act(fn: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await fn()
      await refresh()
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.op'))
    } finally {
      setBusy(false)
    }
  }

  const unread = notifs.filter((n) => !n.read_at).length

  // 默认以"成员的情况"通知为主；与自己账户相关的只在展开时显示
  const SELF_KINDS = new Set([
    'self',
    'task_invite',
    'task_due',
    'task_updated',
    'test',
    'concern',
  ])
  const memberNotifs = notifs.filter((n) => !SELF_KINDS.has(n.kind))
  const FEED_CAP = 3
  const shown = expanded ? notifs : memberNotifs.slice(0, FEED_CAP)
  const hasMore =
    !expanded &&
    (memberNotifs.length > FEED_CAP || notifs.length > memberNotifs.length)

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="bell" />
        {t('notif.title')}
        {unread > 0 && <span className="nbadge">{unread}</span>}
      </h2>

      {error && <p className="home__error">{error}</p>}

      {pushStatus === 'need_permission' && (
        <div className="pushbar">
          <p className="muted">{t('push.desc')}</p>
          <button
            className="pushbar__btn"
            onClick={() => void enablePush().then(setPushStatus)}
          >
            {t('push.enable')}
          </button>
        </div>
      )}
      {pushStatus === 'denied' && <p className="muted">{t('push.denied')}</p>}

      {pushStatus === 'subscribed' && (
        <>
          <button
            className="nfeed__more"
            style={{ marginBottom: '0.5rem' }}
            aria-expanded={showTools}
            onClick={() => setShowTools((v) => !v)}
          >
            {t('push.tools')} {showTools ? '▴' : '▾'}
          </button>
          {showTools && (
            <div className="pushbar">
              <p className="muted">{testMsg ?? t('push.test.hint')}</p>
              <div className="pushbar__btns">
                <button
                  className="pushbar__btn"
                  disabled={busy}
                  onClick={() =>
                    act(async () => {
                      await sendTestNotification()
                      setTestMsg(t('push.test.sent'))
                    })
                  }
                >
                  {t('push.test')}
                </button>
                <button
                  className="pushbar__btn"
                  disabled={busy}
                  onClick={() =>
                    act(async () => {
                      await sendTestUnlock()
                      setTestMsg(t('push.testUnlock.sent'))
                    })
                  }
                >
                  {t('push.testUnlock')}
                </button>
              </div>
            </div>
          )}
        </>
      )}

      {items.length > 0 && (
        <div className="resp">
          {items.map(({ alert, name, emergency }) => (
            <div key={alert.id} className={`resp__item resp__item--${alert.stage}`}>
              <div className="resp__head">
                <strong>{name}</strong>
                <span className="resp__stage">
                  {t(`notif.stage.${alert.stage}` as I18nKey)}
                </span>
              </div>
              {alert.paused_until &&
                new Date(alert.paused_until).getTime() > Date.now() && (
                  <p className="resp__paused">{t('notif.paused')}</p>
                )}
              {alert.sos_lat != null && alert.sos_lng != null && (
                <div className="resp__loc">
                  📍{' '}
                  <a
                    href={`https://www.google.com/maps?q=${alert.sos_lat},${alert.sos_lng}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {t('resp.location')}
                  </a>
                </div>
              )}
              {emergency && (
                <div className="resp__emergency">
                  {emergency.home_address && <div>📍 {emergency.home_address}</div>}
                  {emergency.emergency_contact_phone && (
                    <div>
                      ☎{' '}
                      <a href={`tel:${emergency.emergency_contact_phone}`}>
                        {emergency.emergency_contact_name ?? t('ei.contact')}:
                        {emergency.emergency_contact_phone}
                      </a>
                    </div>
                  )}
                  {emergency.medical_notes && <div>🩺 {emergency.medical_notes}</div>}
                </div>
              )}
              <div className="resp__actions">
                <button
                  disabled={busy}
                  onClick={() => act(() => ackAlert(alert.id))}
                >
                  {t('notif.onIt')}
                </button>
                <button
                  className="resp__safe"
                  disabled={busy}
                  onClick={() => act(() => resolveAlert(alert.id))}
                >
                  {t('notif.confirmSafe')}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {notifs.length === 0 ? (
        <p className="muted">{t('notif.empty')}</p>
      ) : shown.length === 0 ? (
        <p className="muted">{t('notif.noMember')}</p>
      ) : (
        <ul className="nfeed">
          {shown.map((n) => (
            <li
              key={n.id}
              className={`nfeed__item${n.read_at ? '' : ' is-unread'}`}
            >
              <div
                className="nfeed__main"
                onClick={() => {
                  if (!n.read_at) void markNotificationRead(n.id).then(refresh)
                }}
              >
                <span className="nfeed__body">{renderNotif(n)}</span>
                <span className="nfeed__time">{ago(n.created_at)}</span>
              </div>
              <button
                className="nfeed__del"
                aria-label={t('notif.delete')}
                disabled={busy}
                onClick={() => act(() => deleteNotification(n.id))}
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}

      {notifs.length > 0 && (
        <div className="nfeed__controls">
          {(hasMore || expanded) && (
            <button
              className="nfeed__more"
              onClick={() => setExpanded((v) => !v)}
            >
              {expanded ? t('notif.less') : t('notif.more')}
            </button>
          )}
          <button
            className="nfeed__clear"
            disabled={busy}
            onClick={() => act(clearMyNotifications)}
          >
            {t('notif.clearAll')}
          </button>
        </div>
      )}
    </section>
  )
}
