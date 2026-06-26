import { useCallback, useEffect, useState } from 'react'
import {
  ackAlert,
  clearFinishedNotifications,
  deleteNotification,
  getAlert,
  getEmergencyInfoForUser,
  getProfileName,
  listMyNotifications,
  markNotificationRead,
  resolveAlert,
  getUserClients,
  type AppNotification,
  type Alert,
  type EmergencyInfo,
  type ClientDevice,
} from '@/features/alerts/api'
import { subscribeAlertSignals } from '@/features/alerts/realtime'
import { useAuth } from '@/features/auth/AuthProvider'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import {
  enablePush,
  getPushStatus,
  sendTestNotification,
  sendTestUnlock,
  type PushStatus,
} from '@/features/push/pushApi'
import { isTauri } from '@/lib/platform'
import { Capacitor } from '@capacitor/core'
import './NotificationsCard.css'

interface ResponderItem {
  alert: Alert
  name: string
  emergency: EmergencyInfo | null
  /** 已认领「我去联系」的成员名（alerts.paused_by 对应的 profile） */
  reacherName: string | null
  clients: ClientDevice[]
}

const NOTIF_KINDS = new Set([
  'self',
  'group',
  'community',
  'terminal',
  'sos',
  'on_it',
  'resolved',
  'task_invite',
  'task_due',
  'task_missed',
  'task_accepted',
  'task_declined',
  'test',
  'concern',
  'update',
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
  const { t, lang } = useI18n()
  const { user } = useAuth()
  const [notifs, setNotifs] = useState<AppNotification[]>([])
  const [updBusy, setUpdBusy] = useState<string | null>(null)
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

      // 需要我响应的：有 alert_id 且为 group/community/terminal/sos 的去重
      const ids = [
        ...new Set(
          list
            .filter(
              (n) =>
                n.alert_id &&
                ['group', 'community', 'terminal', 'sos'].includes(n.kind),
            )
            .map((n) => n.alert_id as string),
        ),
      ]
      const built: ResponderItem[] = []
      for (const id of ids) {
        const alert = await getAlert(id)
        if (!alert || alert.status !== 'open') continue
        const [name, emergency, reacherName, clients] = await Promise.all([
          getProfileName(alert.user_id),
          getEmergencyInfoForUser(alert.user_id).catch(() => null),
          alert.paused_by
            ? getProfileName(alert.paused_by).catch(() => null)
            : Promise.resolve(null),
          getUserClients(alert.user_id).catch(() => []),
        ])
        built.push({
          alert,
          name: name ?? translate('notif.someone'),
          emergency,
          reacherName,
          clients,
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
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh()
    }
    document.addEventListener('visibilitychange', onVisible)
    let unsubscribe: (() => void) | undefined
    void subscribeAlertSignals(refresh).then((fn) => {
      unsubscribe = fn
    })
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      unsubscribe?.()
    }
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
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
        <h2 className="card__title" style={{ margin: 0 }}>
          <Icon name="bell" />
          {t('notif.title')}
          {unread > 0 && <span className="nbadge">{unread}</span>}
        </h2>
        {pushStatus === 'subscribed' && (
          <button
            className="notif-tools-toggle"
            aria-expanded={showTools}
            onClick={() => setShowTools((v) => !v)}
          >
            {t('push.tools')} {showTools ? '▴' : '▾'}
          </button>
        )}
      </div>

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
          {items.map(({ alert, name, emergency, reacherName, clients }) => {
            const isSos = alert.cause === 'sos'
            const reached = !!alert.paused_by
            const iAmReacher = !!user && user.id === alert.paused_by
            return (
              <div
                key={alert.id}
                className={`resp__item resp__item--${alert.stage}${
                  isSos ? ' resp__item--sos' : ''
                }`}
              >
                <div className="resp__head">
                  <strong>{name}</strong>
                  <span className="resp__stage">
                    {isSos
                      ? t('resp.sos')
                      : t(`notif.stage.${alert.stage}` as I18nKey)}
                  </span>
                </div>
                {items.find(i => i.alert.id === alert.id)?.emergency ? (
                  <div className="resp__emergency" style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                    {emergency?.home_address && (
                      <div style={{ display: 'flex', gap: '6px' }}>
                        <span>🏠</span>
                        <div>
                          <strong>{lang === 'zh' ? '登记住址 (兜底)' : 'Registered Address (Fallback)'}</strong>
                          <div style={{ marginTop: '2px' }}>{emergency.home_address}</div>
                        </div>
                      </div>
                    )}
                    
                    {/* Live GPS Map */}
                    {emergency?.latitude != null && emergency?.longitude != null ? (
                      <div style={{ display: 'flex', gap: '6px', borderTop: '1px dashed var(--line)', paddingTop: '6px' }}>
                        <span>📍</span>
                        <div>
                          <strong>{lang === 'zh' ? '手机实时定位 (Live Map)' : 'Mobile Live Map'}</strong>
                          <div style={{ marginTop: '2px' }}>
                            <a
                              href={`https://www.google.com/maps?q=${emergency.latitude},${emergency.longitude}`}
                              target="_blank"
                              rel="noreferrer"
                              style={{ color: 'var(--accent)', fontWeight: '600', textDecoration: 'underline' }}
                            >
                              {lang === 'zh' ? '在地图中打开' : 'Open in Google Maps'}
                            </a>
                            {emergency.location_accuracy != null && (
                              <span style={{ fontSize: '0.8rem', opacity: 0.7, marginLeft: '8px' }}>
                                ({lang === 'zh' ? `精度约 ${Math.round(emergency.location_accuracy)} 米` : `accuracy ~${Math.round(emergency.location_accuracy)}m`})
                              </span>
                            )}
                            {emergency.location_updated_at && (
                              <div style={{ fontSize: '0.75rem', opacity: 0.6, marginTop: '2px' }}>
                                {lang === 'zh' ? `更新于 ${ago(emergency.location_updated_at)}` : `updated ${ago(emergency.location_updated_at)}`}
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    ) : (
                      /* Fallback: alert SOS location */
                      alert.sos_lat != null && alert.sos_lng != null && (
                        <div style={{ display: 'flex', gap: '6px', borderTop: '1px dashed var(--line)', paddingTop: '6px' }}>
                          <span>📍</span>
                          <div>
                            <strong>{lang === 'zh' ? 'SOS 触发时定位' : 'SOS Trigger Location'}</strong>
                            <div style={{ marginTop: '2px' }}>
                              <a
                                href={`https://www.google.com/maps?q=${alert.sos_lat},${alert.sos_lng}`}
                                target="_blank"
                                rel="noreferrer"
                                style={{ color: 'var(--accent)', fontWeight: '600', textDecoration: 'underline' }}
                              >
                                {lang === 'zh' ? '打开定位' : 'Open Location'}
                              </a>
                            </div>
                          </div>
                        </div>
                      )
                    )}
 
                    {emergency?.emergency_contact_phone && (
                      <div style={{ display: 'flex', gap: '6px', borderTop: '1px dashed var(--line)', paddingTop: '6px' }}>
                        <span>☎️</span>
                        <div>
                          <strong>{emergency.emergency_contact_name ?? t('ei.contact')}</strong>
                          <div style={{ marginTop: '2px' }}>
                            <a href={`tel:${emergency.emergency_contact_phone}`} style={{ color: 'var(--accent)', fontWeight: '600' }}>
                              {emergency.emergency_contact_phone}
                            </a>
                          </div>
                        </div>
                      </div>
                    )}
 
                    {emergency?.medical_notes && (
                      <div style={{ display: 'flex', gap: '6px', borderTop: '1px dashed var(--line)', paddingTop: '6px' }}>
                        <span>🩺</span>
                        <div>
                          <strong>{lang === 'zh' ? '病史与备注' : 'Medical Notes'}</strong>
                          <div style={{ marginTop: '2px' }}>{emergency.medical_notes}</div>
                        </div>
                      </div>
                    )}
 
                    {/* Active Devices status feed */}
                    {clients && clients.length > 0 && (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', borderTop: '1px dashed var(--line)', paddingTop: '6px', fontSize: '0.82rem' }}>
                        <div style={{ fontWeight: '600', opacity: 0.8 }}>
                          💻 {lang === 'zh' ? '多设备活跃状态' : 'Active Devices Status'}
                        </div>
                        <ul style={{ margin: 0, paddingLeft: '20px', listStyleType: 'circle', display: 'flex', flexDirection: 'column', gap: '2px' }}>
                          {clients.map((c) => (
                            <li key={c.client_id} style={{ opacity: 0.85 }}>
                              <span style={{ fontWeight: '600' }}>
                                {c.platform === 'tauri' ? (lang === 'zh' ? 'Windows 电脑' : 'Windows PC') : c.platform === 'android' ? 'Android' : c.platform === 'ios' ? 'iOS' : c.platform}
                              </span>:
                              <span style={{ fontSize: '0.78rem', marginLeft: '6px', opacity: 0.7 }}>
                                {lang === 'zh' ? `${ago(c.last_seen_at)}前活跃` : `active ${ago(c.last_seen_at)}`}
                              </span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>
                ) : (
                  /* If no emergency info, show basic SOS location if available */
                  alert.sos_lat != null && alert.sos_lng != null && (
                    <div className="resp__loc" style={{ marginTop: '8px' }}>
                      📍{' '}
                      <a
                        href={`https://www.google.com/maps?q=${alert.sos_lat},${alert.sos_lng}`}
                        target="_blank"
                        rel="noreferrer"
                        style={{ color: 'var(--accent)', fontWeight: '600', textDecoration: 'underline' }}
                      >
                        {t('resp.location')}
                      </a>
                    </div>
                  )
                )}

                {!reached ? (
                  // 还没人认领：只给「我去联系」
                  <div className="resp__actions">
                    <button
                      className="resp__reach"
                      disabled={busy}
                      onClick={() => act(() => ackAlert(alert.id))}
                    >
                      {t('notif.onIt')}
                    </button>
                  </div>
                ) : (
                  // 已有人认领：所有人都看到是谁；仅认领者能「确认安全」
                  <>
                    <p className="resp__reaching">
                      {t('notif.reaching', {
                        name: reacherName || t('notif.someone'),
                      })}
                    </p>
                    {iAmReacher && (
                      <div className="resp__actions">
                        <button
                          className="resp__safe"
                          disabled={busy}
                          onClick={() => act(() => resolveAlert(alert.id))}
                        >
                          {t('notif.confirmSafe')}
                        </button>
                      </div>
                    )}
                  </>
                )}
              </div>
            )
          })}
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
              className={`nfeed__item${n.read_at ? '' : ' is-unread'}${
                n.kind === 'sos' ? ' nfeed__item--sos' : ''
              }`}
            >
              <div
                className="nfeed__main"
                onClick={() => {
                  if (!n.read_at) void markNotificationRead(n.id).then(refresh)
                }}
              >
                <span className="nfeed__body">{renderNotif(n)}</span>
                {n.kind === 'update' && (
                  <div className="nfeed__update-action">
                    <button
                      className="nfeed__update-btn"
                      disabled={busy || updBusy === n.id}
                      onClick={async (e) => {
                        e.stopPropagation()
                        if (!n.read_at) {
                          void markNotificationRead(n.id).then(refresh)
                        }
                        if (isTauri()) {
                          setUpdBusy(n.id)
                          try {
                            const internals = (window as any).__TAURI_INTERNALS__
                            if (internals && typeof internals.invoke === 'function') {
                              await internals.invoke('download_and_install', { url: 'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe' })
                            } else {
                              window.open('https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe', '_blank')
                            }
                          } catch (err) {
                            console.error('Tauri update failed:', err)
                            window.open('https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe', '_blank')
                          } finally {
                            setUpdBusy(null)
                          }
                        } else if (Capacitor.isNativePlatform()) {
                          window.open('https://keep-contact-mauve.vercel.app/keep-contact.apk', '_blank')
                        } else {
                          window.location.reload()
                        }
                      }}
                    >
                      {updBusy === n.id ? (lang === 'zh' ? '正在下载更新...' : 'Downloading...') : t('update.now')}
                    </button>
                  </div>
                )}
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
            onClick={() =>
              act(() => clearFinishedNotifications(items.map((i) => i.alert.id)))
            }
          >
            {t('notif.clearAll')}
          </button>
        </div>
      )}
    </section>
  )
}
