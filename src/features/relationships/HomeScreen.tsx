import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '@/features/auth/AuthProvider'
import { EmergencyInfoCard } from '@/features/profile/EmergencyInfoCard'
import { GuardiansCard } from '@/features/guardians/GuardiansCard'
import { LivenessCard } from '@/features/baseline/LivenessCard'
import { RoutineSettings } from '@/features/baseline/RoutineSettings'
import { CheckinTasksCard } from '@/features/tasks/CheckinTasksCard'
import { PassiveSignalCard } from '@/features/passive/PassiveSignalCard'
import { PassivePingBoot } from '@/features/passive/PassivePingBoot'
import { LivenessProvider } from '@/features/baseline/LivenessProvider'
import { AlertOverlay } from '@/features/baseline/AlertOverlay'
import { NotificationsCard } from '@/features/alerts/NotificationsCard'
import { TabBar, type Tab } from '@/features/nav/TabBar'
import { listMyNotifications, raiseSos } from '@/features/alerts/api'
import { setBadge } from '@/lib/badge'
import { toast } from '@/lib/toast'
import { ToastHost } from '@/features/common/ToastHost'
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
import { InstallCard } from '@/features/install/InstallCard'
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
  const { t } = useI18n()
  const [communities, setCommunities] = useState<Community[]>([])
  const [groups, setGroups] = useState<MyGroup[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const [newCommunity, setNewCommunity] = useState('')
  const [newGroup, setNewGroup] = useState('')
  const [newGroupCommunity, setNewGroupCommunity] = useState<string>('')
  const [joinText, setJoinText] = useState('')
  const [notice, setNotice] = useState<string | null>(null)
  const [openBoard, setOpenBoard] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>('home')
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
    return () => window.clearInterval(tmr)
  }, [refreshUnread])

  async function doSos() {
    if (sosBusy) return
    setSosBusy(true)
    toast(t('sos.sending'), 'info')
    try {
      const coords = await getCurrentCoords() // 附带实时位置，给 Group/Community
      await raiseSos(coords?.lat, coords?.lng)
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
    void refresh()
    void ensurePushSubscription() // 已授权过的设备登录后静默续订推送
  }, [refresh])

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
    <div className="home">
      <PassivePingBoot />
      <AlertOverlay />
      <ToastHost />
      <header className="home__header">
        <div>
          <span className="home__logo" aria-hidden>
            ◍
          </span>
          <span className="home__appname">Keep Contact</span>
        </div>
        <div className="home__headerbtns">
          <LangToggle className="home__signout" />
          <button className="home__signout" onClick={() => void signOut()}>
            {t('header.signout')}
          </button>
        </div>
      </header>

      <p className="home__hello">
        {t('home.hello')}
        {(user?.user_metadata?.display_name as string | undefined) ??
          user?.email}
      </p>

      {error && <p className="home__error">{error}</p>}
      {notice && <p className="home__notice">{notice}</p>}

      <main className="home__page">
      {tab === 'home' && (
        <>
          <StatusBoard />
          <LivenessCard />
          <NotificationsCard onChanged={refreshUnread} />
          <CheckinTasksCard />
        </>
      )}

      {tab === 'routine' && <RoutineSettings />}

      {tab === 'profile' && (
        <>
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
          </section>
          <EmergencyInfoCard />
          <PassiveSignalCard />
          <InstallCard />
        </>
      )}

      {tab === 'circles' && (
        <>
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

      <GuardiansCard />
        </>
      )}
      </main>

      <TabBar
        active={tab}
        onChange={setTab}
        onSos={() => void doSos()}
        sosBusy={sosBusy}
        alerts={unread}
      />
    </div>
    </LivenessProvider>
  )
}
