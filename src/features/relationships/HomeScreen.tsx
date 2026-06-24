import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '@/features/auth/AuthProvider'
import { EmergencyInfoCard } from '@/features/profile/EmergencyInfoCard'
import { GuardiansCard } from '@/features/guardians/GuardiansCard'
import { SafeAwayBar } from '@/features/baseline/SafeAwayBar'
import { RoutineSettings } from '@/features/baseline/RoutineSettings'
import { CheckinTasksCard } from '@/features/tasks/CheckinTasksCard'
import { PassiveSignalCard } from '@/features/passive/PassiveSignalCard'
import { PassivePingBoot } from '@/features/passive/PassivePingBoot'
import { LivenessProvider } from '@/features/baseline/LivenessProvider'
import { AlertOverlay } from '@/features/baseline/AlertOverlay'
import { NotificationsCard } from '@/features/alerts/NotificationsCard'
import { TabBar, type Tab } from '@/features/nav/TabBar'
import { listMyNotifications, raiseSos } from '@/features/alerts/api'
import { subscribeAlertSignals } from '@/features/alerts/realtime'
import { setBadge } from '@/lib/badge'
import { reportClient } from '@/lib/clientReport'
import { GMScreen } from '@/features/gm/GMScreen'
import { UpdatesCard } from '@/features/update/UpdatesCard'
import { amIGm } from '@/features/gm/gmApi'
import { toast } from '@/lib/toast'
import { ToastHost } from '@/features/common/ToastHost'
import { ScanSyncModal } from '@/features/auth/ScanSyncModal'
import { supabase } from '@/lib/supabase'
import { getPlatform } from '@/lib/platform'
import {
  createCommunity,
  createGroup,
  joinCommunityByCode,
  joinGroupByCode,
  leaveGroup,
  listMyCommunities,
  listMyGroups,
  renameCommunity,
  renameGroup,
  setGroupCommunity,
  setMonitoringDirection,
  type Community,
  type MyGroup,
} from '@/features/relationships/api'
import { GroupBoard } from '@/features/relationships/GroupBoard'
import { StatusBoard } from '@/features/relationships/StatusBoard'
import { ApkUpgradeNotice } from '@/features/install/ApkUpgradeNotice'
import { EditableName } from '@/features/common/EditableName'
import { Icon } from '@/features/common/Icon'
import { setDisplayName } from '@/features/profile/profileApi'
import { getCurrentCoords } from '@/lib/geo'
import { becomeGuardianByCode } from '@/features/guardians/api'
import {
  parseInviteText,
  shareInvite,
  takePendingInvite,
  type Invite,
} from '@/features/invites/inviteLink'
import { LangToggle, translate, useI18n } from '@/lib/i18n'
import { ThemeToggle } from '@/lib/theme'
import {
  ensurePushSubscription,
  triggerPushDispatch,
} from '@/features/push/pushApi'
import './HomeScreen.css'

async function joinByInvite(inv: Invite): Promise<string> {
  if (inv.kind === 'group') {
    await joinGroupByCode(inv.code)
    return translate('invite.joined.group')
  }
  if (inv.kind === 'community') {
    await joinCommunityByCode(inv.code)
    return translate('invite.joined.community')
  }
  await becomeGuardianByCode(inv.code)
  return translate('invite.joined.guardian')
}

export function HomeScreen() {
  const { user, signOut } = useAuth()
  const { t, lang } = useI18n()
  const [communities, setCommunities] = useState<Community[]>([])
  const [groups, setGroups] = useState<MyGroup[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [isScanning, setIsScanning] = useState(false)

  // Mobile Scan QR sync handler
  async function handleQrScan(data: string) {
    setIsScanning(false)
    if (!data.startsWith('keepcontact://sync?token=')) {
      toast(t('profile.scan.failed'), 'danger')
      return
    }
    const targetToken = data.replace('keepcontact://sync?token=', '')
    toast(t('profile.scan.success'), 'info')
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        toast(t('err.load'), 'danger')
        return
      }

      let payload: any = {
        access_token: session.access_token,
        refresh_token: session.refresh_token
      }

      try {
        const { data: funcData, error: funcError } = await supabase.functions.invoke('sync-auth')
        if (funcError) {
          console.warn('Edge function sync-auth failed, falling back to legacy token sync:', funcError)
        } else if (funcData && funcData.email && funcData.otp) {
          payload = {
            email: funcData.email,
            otp: funcData.otp
          }
        }
      } catch (err) {
        console.warn('Edge function sync-auth failed, falling back to legacy token sync:', err)
      }

      const channel = supabase.channel(`scan2sync:${targetToken}`, {
        config: { broadcast: { self: false } }
      })
      channel.subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await channel.send({
            type: 'broadcast',
            event: 'sync',
            payload
          })
          toast(t('profile.scan.success'), 'ok')
          setTimeout(() => {
            void supabase.removeChannel(channel)
          }, 2000)
        }
      })
    } catch (err) {
      console.error('Scan sync broadcast failed:', err)
      toast(t('profile.scan.failed'), 'danger')
    }
  }

  const [newCommunity, setNewCommunity] = useState('')
  const [newGroup, setNewGroup] = useState('')
  const [newGroupCommunity, setNewGroupCommunity] = useState<string>('')
  const [joinText, setJoinText] = useState('')
  const [notice, setNotice] = useState<string | null>(null)
  const [openBoard, setOpenBoard] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>('home')
  const [isGm, setIsGm] = useState(false)
  const [unread, setUnread] = useState(0)
  const [sosBusy, setSosBusy] = useState(false)

  // 未读数提到顶层：任何 tab 都更新 App 图标角标 + 底部"通知"页红点
  const refreshUnread = useCallback(async () => {
    try {
      const list = await listMyNotifications()
      const u = list.filter((n) => !n.read_at).length
      setUnread(u)
      setBadge(u)
    } catch {
      /* 忽略 */
    }
  }, [])

  useEffect(() => {
    void refreshUnread()
    const tmr = window.setInterval(() => void refreshUnread(), 30_000)
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refreshUnread()
    }
    document.addEventListener('visibilitychange', onVisible)
    let unsubscribe: (() => void) | undefined
    void subscribeAlertSignals(refreshUnread).then((fn) => {
      unsubscribe = fn
    })
    return () => {
      window.clearInterval(tmr)
      document.removeEventListener('visibilitychange', onVisible)
      unsubscribe?.()
    }
  }, [refreshUnread])

  async function doSos() {
    if (sosBusy) return
    setSosBusy(true)
    toast(t('sos.sending'), 'info')
    try {
      const coords = await getCurrentCoords() // 附带实时位置，给 Group/Community
      await raiseSos(coords?.lat, coords?.lng, coords?.accuracy)
      void triggerPushDispatch() // 不等 cron，立即推送到 Group 锁屏
      toast(t('sos.sent'), 'danger')
      await refresh()
      void refreshUnread()
    } catch (err) {
      toast(err instanceof Error ? err.message : t('sos.failed'), 'danger')
    } finally {
      setSosBusy(false)
    }
  }

  const refresh = useCallback(async () => {
    setError(null)
    try {
      const [c, g] = await Promise.all([listMyCommunities(), listMyGroups()])
      setCommunities(c)
      setGroups(g)
    } catch (err) {
      setError(err instanceof Error ? err.message : '加载失败')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void ensurePushSubscription() // 已授权过的设备登录后静默续订推送
    void reportClient() // 上报客户端版本/平台(供运营查看)
    void amIGm().then(setIsGm) // GM 才显示 GM 页

    // Request geolocation permission early to prevent SOS latency/blocks
    try {
      if ('geolocation' in navigator) {
        if (navigator.permissions && typeof navigator.permissions.query === 'function') {
          navigator.permissions.query({ name: 'geolocation' as PermissionName }).then((result) => {
            if (result.state === 'prompt') {
              navigator.geolocation.getCurrentPosition(() => {}, () => {}, { timeout: 2000 })
            }
          }).catch(() => {
            navigator.geolocation.getCurrentPosition(() => {}, () => {}, { timeout: 2000 })
          })
        } else {
          navigator.geolocation.getCurrentPosition(() => {}, () => {}, { timeout: 2000 })
        }
      }
    } catch (err) {
      console.warn('Failed to check/prompt early geolocation:', err)
    }
  }, [])

  useEffect(() => {
    if (tab === 'circles') void refresh()
  }, [refresh, tab])

  // 邀请链接自动加入：打开链接 →（登录后）自动完成加入
  useEffect(() => {
    const inv = takePendingInvite()
    if (!inv) return
    joinByInvite(inv)
      .then((msg) => {
        setNotice(msg)
        void refresh()
      })
      .catch((e) =>
        setError(
          translate('invite.joinFail', {
            msg: e instanceof Error ? e.message : '',
          }),
        ),
      )
  }, [refresh])

  async function onShare(inv: Invite, name: string) {
    const r = await shareInvite(inv.kind, inv.code, name)
    if (r.status === 'copied') setNotice(t('invite.copied'))
    else if (r.status === 'manual') setNotice(t('invite.manual', { url: r.url }))
  }

  async function run(fn: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await fn()
      await refresh()
    } catch (err) {
      setError(err instanceof Error ? err.message : '操作失败')
    } finally {
      setBusy(false)
    }
  }

  return (
    <LivenessProvider>
    <div className={`home home--${tab}`}>
      <PassivePingBoot />
      <AlertOverlay />
      <ToastHost />

      <div className="home__body">
        <header className="home__header">
          <div style={{ display: 'flex', alignItems: 'center' }}>
            <span className="home__logo" aria-hidden>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ display: 'inline-block', verticalAlign: 'middle' }}>
                <circle cx="12" cy="12" r="10" />
                <circle cx="12" cy="12" r="4" fill="currentColor" />
              </svg>
            </span>
            <span className="home__appname">Keep Contact</span>
          </div>
          <div className="home__headerbtns">
            <ThemeToggle className="home__signout" />
            <LangToggle className="home__signout" />
            <button className="home__signout" onClick={() => void signOut()}>
              {t('header.signout')}
            </button>
          </div>
        </header>

        <div className="home__hello" style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: '8px', padding: '0 1rem 0.25rem' }}>
          <span style={{ color: 'var(--fg-muted)', fontSize: '0.9rem' }}>
            {t('home.hello')}
            {(user?.user_metadata?.display_name as string | undefined) ?? user?.email}
          </span>
          <span style={{ 
            display: 'inline-flex', 
            alignItems: 'center', 
            padding: '2px 8px', 
            fontSize: '0.75rem', 
            fontWeight: '600', 
            borderRadius: '9999px',
            background: isGm ? 'var(--accent-soft)' : 'var(--bg-soft)',
            color: isGm ? 'var(--accent)' : 'var(--fg-muted)',
            border: isGm ? '1px solid var(--accent-line)' : '1px solid var(--line)'
          }}>
            {isGm ? (lang === 'zh' ? '守护者 (GM)' : 'Caregiver (GM)') : (lang === 'zh' ? '被守护者' : 'Care Recipient')}
          </span>
        </div>

        {error && <p className="home__error">{error}</p>}
        {notice && <p className="home__notice">{notice}</p>}

        <ApkUpgradeNotice />

        <main className="home__page">
          <div className={`dashboard-grid ${tab !== 'home' ? 'home__tab-content--hidden' : ''}`}>
            <div className="dashboard-grid__col1">
              <SafeAwayBar />
              <NotificationsCard onChanged={refreshUnread} />
            </div>
            <div className="dashboard-grid__col2">
              <StatusBoard />
              <CheckinTasksCard />
            </div>
          </div>

          <div className={tab !== 'routine' ? 'home__tab-content--hidden' : ''}>
            <RoutineSettings />
          </div>

          {isGm && (
            <div className={tab !== 'gm' ? 'home__tab-content--hidden' : ''}>
              <GMScreen onBack={() => setTab('circles')} />
            </div>
          )}

          <div className={`profile-grid ${tab !== 'profile' ? 'home__tab-content--hidden' : ''}`}>
            <div className="profile-grid__col1">
              <section className="card">
                <h2 className="card__title">
                  <Icon name="user" />
                  {t('tab.profile')}
                </h2>
                <p className="profile__name">
                  {t('profile.title')}：
                  <EditableName
                    value={
                      (user?.user_metadata?.display_name as string | undefined) ??
                      user?.email ??
                      ''
                    }
                    canEdit
                    onSave={async (next) => {
                      await setDisplayName(next)
                    }}
                  />
                </p>
                <p className="muted">{t('profile.desc')}</p>

                {/* Scan to Sync (Only on mobile devices) */}
                {(getPlatform() === 'android' || getPlatform() === 'ios') && (
                  <div className="profile__actions" style={{ marginTop: '1.25rem', borderTop: '1px solid var(--line)', paddingTop: '1.25rem' }}>
                    <button
                      className="profile__scan-action"
                      style={{
                        width: '100%',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        padding: '12px 16px',
                        background: 'var(--bg-soft)',
                        border: '1px solid var(--line)',
                        borderRadius: 'var(--r-md)',
                        cursor: 'pointer',
                        color: 'var(--fg)',
                        transition: 'all 0.2s ease',
                      }}
                      onClick={() => setIsScanning(true)}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ color: 'var(--accent)' }}>
                          <path d="M3 7V5a2 2 0 0 1 2-2h2m10 0h2a2 2 0 0 1 2 2v2m0 10v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2" />
                          <path d="M7 12h10M12 7v10" />
                        </svg>
                        <span style={{ fontWeight: '600', fontSize: '0.92rem' }}>
                          {lang === 'zh' ? '扫码同步登录新设备' : 'Scan to Sync Login'}
                        </span>
                      </div>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ opacity: 0.5 }}>
                        <path d="M9 18l6-6-6-6" />
                      </svg>
                    </button>
                  </div>
                )}
              </section>
              <EmergencyInfoCard />
              <UpdatesCard />
            </div>
            <div className="profile-grid__col2">
              <PassiveSignalCard />
            </div>
          </div>

          <div className={`circles-grid ${tab !== 'circles' ? 'home__tab-content--hidden' : ''}`}>
            <div className="circles-grid__col1">
              {isGm && (
                <section className="card" style={{ border: '1px solid var(--accent-line)', background: 'var(--accent-soft)', display: 'flex', flexDirection: 'column', gap: '0.6rem' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '12px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ color: 'var(--accent)', flexShrink: 0 }}>
                        <path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z" />
                        <path d="M9 12l2 2 4-4" />
                      </svg>
                      <div>
                        <h3 style={{ margin: 0, fontSize: '0.95rem', fontWeight: '600', color: 'var(--fg)' }}>
                          {lang === 'zh' ? '管理员控制台' : 'Manager Console'}
                        </h3>
                        <p className="muted" style={{ margin: 0, fontSize: '0.8rem', lineHeight: '1.4' }}>
                          {lang === 'zh' ? '管理本群组成员状态及客户端版本' : 'Manage member statuses and client versions'}
                        </p>
                      </div>
                    </div>
                    <button 
                      className="share" 
                      onClick={() => setTab('gm')}
                      style={{ background: 'var(--accent)', color: 'var(--bg)', border: 'none', cursor: 'pointer' }}
                    >
                      {lang === 'zh' ? '进入' : 'Enter'}
                    </button>
                  </div>
                </section>
              )}
              {/* 加入：邀请链接（收到链接直接点开即可自动加入；此处为手动兜底） */}
              <section className="card">
                <h2 className="card__title">
                  <Icon name="share" />
                  {t('invite.title')}
                </h2>
                <p className="muted">{t('invite.desc')}</p>
                <div className="row">
                  <input
                    value={joinText}
                    onChange={(e) => setJoinText(e.target.value)}
                    placeholder={t('invite.ph')}
                  />
                  <button
                    disabled={busy || !parseInviteText(joinText)}
                    onClick={() =>
                      run(async () => {
                        const inv = parseInviteText(joinText)
                        if (!inv) throw new Error(t('invite.invalid'))
                        setNotice(await joinByInvite(inv))
                        setJoinText('')
                      })
                    }
                  >
                    {t('invite.join')}
                  </button>
                </div>
              </section>

              {/* Communities */}
              <section className="card">
                <h2 className="card__title">
                  <Icon name="community" />
                  {t('comm.title')}
                </h2>
                {loading ? (
                  <p className="muted">{t('home.loading')}</p>
                ) : communities.length === 0 ? (
                  <p className="muted">{t('comm.empty')}</p>
                ) : (
                  <ul className="list">
                    {communities.map((c) => (
                      <li key={c.id} className="list__item">
                        <EditableName
                          value={c.name}
                          canEdit={c.created_by === user?.id}
                          onSave={async (next) => {
                            await renameCommunity(c.id, next)
                            await refresh()
                          }}
                        />
                        <button
                          className="share"
                          onClick={() =>
                            void onShare({ kind: 'community', code: c.invite_code }, c.name)
                          }
                        >
                          {t('share.invite')}
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
                <div className="row">
                  <input
                    value={newCommunity}
                    onChange={(e) => setNewCommunity(e.target.value)}
                    placeholder={t('comm.new.ph')}
                  />
                  <button
                    disabled={busy || !newCommunity.trim()}
                    onClick={() =>
                      run(async () => {
                        await createCommunity(newCommunity.trim())
                        setNewCommunity('')
                      })
                    }
                  >
                    {t('comm.create')}
                  </button>
                </div>
              </section>

              <GuardiansCard />
            </div>

            <div className="circles-grid__col2">
              {/* Groups */}
              <section className="card">
                <h2 className="card__title">
                  <Icon name="group" />
                  {t('group.title')}
                </h2>
                {loading ? (
                  <p className="muted">{t('home.loading')}</p>
                ) : groups.length === 0 ? (
                  <p className="muted">{t('group.empty')}</p>
                ) : (
                  <ul className="list">
                    {groups.map(({ group, monitored, watching, role }) => (
                      <li key={group.id} className="list__item list__item--group">
                        <div className="list__row1">
                          <EditableName
                            value={group.name}
                            canEdit={group.created_by === user?.id}
                            onSave={async (next) => {
                              await renameGroup(group.id, next)
                              await refresh()
                            }}
                          />
                          <button
                            className="share"
                            onClick={() =>
                              void onShare(
                                { kind: 'group', code: group.invite_code },
                                group.name,
                              )
                            }
                          >
                            {t('share.invite')}
                          </button>
                        </div>
                        <div className="list__row2">
                          <label className="toggle">
                            <input
                              type="checkbox"
                              checked={monitored}
                              disabled={busy}
                              onChange={(e) =>
                                run(() =>
                                  setMonitoringDirection(group.id, {
                                    monitored: e.target.checked,
                                  }),
                                )
                              }
                            />
                            {t('group.monitored')}
                          </label>
                          <label className="toggle">
                            <input
                              type="checkbox"
                              checked={watching}
                              disabled={busy}
                              onChange={(e) =>
                                run(() =>
                                  setMonitoringDirection(group.id, {
                                    watching: e.target.checked,
                                  }),
                                )
                              }
                            />
                            {t('group.watching')}
                          </label>
                          {group.created_by === user?.id && (
                            <label className="toggle">
                              {t('group.community')}
                              <select
                                value={group.community_id ?? ''}
                                disabled={busy}
                                onChange={(e) =>
                                  run(() =>
                                    setGroupCommunity(group.id, e.target.value || null),
                                  )
                                }
                              >
                                <option value="">{t('group.standalone')}</option>
                                {communities.map((c) => (
                                  <option key={c.id} value={c.id}>
                                    {c.name}
                                  </option>
                                ))}
                              </select>
                            </label>
                          )}
                          <span className="role">{role === 'admin' ? t('group.admin') : ''}</span>
                          <button
                            className="share"
                            disabled={busy}
                            onClick={() =>
                              setOpenBoard(openBoard === group.id ? null : group.id)
                            }
                          >
                            {openBoard === group.id ? t('board.hide') : t('board.show')}
                          </button>
                          <button
                            className="leave"
                            disabled={busy}
                            onClick={() => run(() => leaveGroup(group.id))}
                          >
                            {t('group.leave')}
                          </button>
                        </div>
                        {openBoard === group.id && <GroupBoard groupId={group.id} />}
                      </li>
                    ))}
                  </ul>
                )}
                <div className="row">
                  <input
                    value={newGroup}
                    onChange={(e) => setNewGroup(e.target.value)}
                    placeholder={t('group.new.ph')}
                  />
                  <select
                    value={newGroupCommunity}
                    onChange={(e) => setNewGroupCommunity(e.target.value)}
                  >
                    <option value="">{t('group.standalone')}</option>
                    {communities.map((c) => (
                      <option key={c.id} value={c.id}>
                        {t('group.belong', { name: c.name })}
                      </option>
                    ))}
                  </select>
                  <button
                    disabled={busy || !newGroup.trim()}
                    onClick={() =>
                      run(async () => {
                        await createGroup(newGroup.trim(), newGroupCommunity || null)
                        setNewGroup('')
                      })
                    }
                  >
                    {t('comm.create')}
                  </button>
                </div>
              </section>
            </div>
          </div>
        </main>
      </div>

      <TabBar
        active={tab}
        onChange={setTab}
        onSos={() => void doSos()}
        sosBusy={sosBusy}
        alerts={unread}
        isGm={isGm}
      />
      {isScanning && (
        <ScanSyncModal
          onClose={() => setIsScanning(false)}
          onScan={handleQrScan}
        />
      )}
    </div>
    </LivenessProvider>
  )
}
