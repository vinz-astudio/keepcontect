import { useCallback, useEffect, useState } from 'react'
import { Capacitor } from '@capacitor/core'
import { useAuth } from '@/features/auth/AuthProvider'
import { EmergencyInfoCard } from '@/features/profile/EmergencyInfoCard'
import { GuardiansCard } from '@/features/guardians/GuardiansCard'
import { RoutineSettings } from '@/features/baseline/RoutineSettings'
import { CheckinTasksCard } from '@/features/tasks/CheckinTasksCard'
import { listMyTasks } from '@/features/tasks/api'
import { PasscodeSetup } from '@/features/pattern/PasscodeSetup'
import { availableUnlockMethods } from '@/features/pattern/patternStore'
import { GuardianPermissionsCard } from '@/features/passive/GuardianPermissionsCard'
import { PassiveSignalCard } from '@/features/passive/PassiveSignalCard'
import { ProtectionHealthCard } from '@/features/baseline/ProtectionHealthCard'
import { PassivePingBoot } from '@/features/passive/PassivePingBoot'
import { OnboardingWizard } from '@/features/passive/OnboardingWizard'
import { checkAndMigrateOnboarding, saveOnboardingCompleted } from '@/features/passive/onboardingState'
import { LivenessProvider, useLivenessContext } from '@/features/baseline/LivenessProvider'
import '@/features/baseline/LivenessCard.css'
import { AlertOverlay } from '@/features/baseline/AlertOverlay'
import { NotificationsCard } from '@/features/alerts/NotificationsCard'
import { listMyNotifications, listOpenAlerts } from '@/features/alerts/api'
import { dispatchSos, readLocalGpsConsent } from '@/features/alerts/sosDispatch'
import { loadEmergencyGpsConsent, setEmergencyGpsConsent } from '@/features/baseline/settingsApi'
import { subscribeAlertSignals, subscribeGroupStatusSignals } from '@/features/alerts/realtime'
import { setBadge } from '@/lib/badge'
import { reportClient } from '@/lib/clientReport'
import { GMScreen } from '@/features/gm/GMScreen'
import { UpdatesCard } from '@/features/update/UpdatesCard'
import { amIGm } from '@/features/gm/gmApi'
import { toast } from '@/lib/toast'
import { ToastHost } from '@/features/common/ToastHost'
import { ScanSyncModal } from '@/features/auth/ScanSyncModal'
import { supabase } from '@/lib/supabase'
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
  deleteCommunity,
  deleteGroup,
  type Community,
  type MyGroup,
} from '@/features/relationships/api'
import { GroupBoard } from '@/features/relationships/GroupBoard'
import { StatusBoard } from '@/features/relationships/StatusBoard'
import { QRModal } from '@/features/relationships/QRModal'
import { ApkUpgradeNotice } from '@/features/install/ApkUpgradeNotice'
import { EditableName } from '@/features/common/EditableName'
import { deleteMyAccount, setDisplayName } from '@/features/profile/profileApi'
import { becomeGuardianByCode } from '@/features/guardians/api'
import {
  buildInviteUrl,
  parseInviteText,
  shareInvite,
  takePendingInvite,
  type Invite,
} from '@/features/invites/inviteLink'
import { LangToggle, translate, useI18n } from '@/lib/i18n'
import { ThemeToggle } from '@/lib/theme'
import { ensurePushSubscription } from '@/features/push/pushApi'
import { AppShell } from '@/features/shell/AppShell'
import type { PrimaryTab } from '@/features/shell/appShellState'
import { WatchScreen } from '@/features/watch/WatchScreen'
import { RoutineScreen } from '@/features/routine/RoutineScreen'
import { CirclesScreen } from '@/features/circles/CirclesScreen'
import { MeScreen } from '@/features/me/MeScreen'
import {
  PrototypeBadge,
  PrototypeCard,
  PrototypeDisclosure,
  PrototypeIcon,
  PrototypeRow,
} from '@/features/prototype/PrototypeUI'
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

/**
 * 账户和设备是一张卡,不是两张。
 *
 * 「这个账号是谁」和「它在哪几台机器上」是同一个问题的两半。拆成两张卡之后,
 * 用户会以为那是两件要分别处理的事,而且中间那条卡片边界什么信息都不携带。
 */
function AccountCard({ onScan, signOut }: { onScan: () => void; signOut: () => Promise<void> }) {
  const { user } = useAuth()
  const { t, lang } = useI18n()
  return (
    <>
      <PrototypeRow
        icon="person"
        title={<EditableName value={(user?.user_metadata?.display_name as string | undefined) ?? user?.email ?? ''} canEdit onSave={setDisplayName} />}
        subtitle={user?.email ?? ''}
      />
      <PrototypeRow
        icon="qr_code_scanner"
        title={lang === 'zh' ? '登录到另一台设备' : 'Sign in on another device'}
        subtitle={lang === 'zh'
          ? '用一次性二维码把这个账号登录到新设备。设备越多,KC 越不容易漏掉您的活动。'
          : 'Use a one-time QR code to sign this account in on another device. More devices means fewer gaps in what KC can see.'}
        trailing={<button type="button" className="prototype-button prototype-button--ghost" onClick={onScan}>{lang === 'zh' ? '扫描' : 'Scan'}</button>}
      />
      <PrototypeDisclosure label={lang === 'zh' ? '账户操作' : 'Account actions'}>
        <div className="home-prototype__danger-actions">
          <button type="button" className="prototype-button prototype-button--ghost" onClick={() => void signOut()}>{t('header.signout')}</button>
          <button
            type="button"
            className="prototype-button home-prototype__danger"
            onClick={() => {
              const message = lang === 'zh'
                ? '确定要注销账号并永久删除所有个人数据吗？此操作无法恢复。'
                : 'Delete your account and all personal data permanently? This cannot be undone.'
              if (window.confirm(message)) void deleteMyAccount()
            }}
          >
            {lang === 'zh' ? '删除账户与全部数据' : 'Delete account and all data'}
          </button>
        </div>
      </PrototypeDisclosure>
    </>
  )
}

function SafetyCheckinCard() {
  const { startSetup, startPractice } = useLivenessContext()
  const { user } = useAuth()
  const { t, lang } = useI18n()
  const zh = lang === 'zh'
  const [settingPasscode, setSettingPasscode] = useState(false)
  const [methods, setMethods] = useState(() =>
    user?.id ? availableUnlockMethods(user.id) : { pattern: false, passcode: false })

  // 两者各自独立,都能解锁。所以这里报的是「设了哪些」,不是「当前是哪个」。
  const set = [methods.pattern && (zh ? '手势' : 'Pattern'), methods.passcode && (zh ? '数字密码' : 'Passcode')]
    .filter(Boolean) as string[]

  return (
    <>
      <PrototypeRow
        icon="lock"
        title={t('live.pattern')}
        subtitle={set.length === 0
          ? (zh ? '还没有设置。用于本人安全确认与解除误报。' : 'Not set yet. Used to confirm you are safe and clear a false alarm.')
          : (zh
              ? `已设置:${set.join(' 和 ')}。解锁时可以任选一种。`
              : `Set: ${set.join(' and ')}. Either one unlocks.`)}
      />
      {settingPasscode && user?.id ? (
        <PasscodeSetup
          uid={user.id}
          zh={zh}
          onDone={() => {
            if (user?.id) setMethods(availableUnlockMethods(user.id))
            setSettingPasscode(false)
          }}
          onCancel={() => setSettingPasscode(false)}
        />
      ) : (
        <div className="home-prototype__button-row">
          <button type="button" className="prototype-button prototype-button--ghost" onClick={() => { setSettingPasscode(false); startSetup() }}>
            {zh ? '设置手势' : 'Set pattern'}
          </button>
          <button type="button" className="prototype-button prototype-button--ghost" onClick={() => setSettingPasscode(true)}>
            {methods.passcode ? (zh ? '更改数字密码' : 'Change passcode') : (zh ? '设置数字密码' : 'Set passcode')}
          </button>
          <button type="button" className="prototype-button prototype-button--ghost" onClick={startPractice}>{t('live.practice')}</button>
        </div>
      )}
    </>
  )
}

function EmergencyGpsCard() {
  const { lang } = useI18n()
  // Seeded from the local mirror so the switch renders instantly, then
  // reconciled against the account-level answer on the server.
  const [enabled, setEnabled] = useState<boolean>(() => readLocalGpsConsent())
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    void loadEmergencyGpsConsent()
      .then(setEnabled)
      .catch(() => {
        /* offline: the mirror already seeded the switch */
      })
  }, [])

  async function handleToggle(checked: boolean) {
    if (!checked) {
      setBusy(true)
      try {
        await setEmergencyGpsConsent(false)
      } catch (err) {
        setBusy(false)
        toast(
          lang === 'zh'
            ? `关闭失败,请重试:${err instanceof Error ? err.message : String(err)}`
            : `Could not turn this off: ${err instanceof Error ? err.message : String(err)}`,
          'danger',
        )
        return
      }
      setBusy(false)
      setEnabled(false)
      // 'limited' is a PrototypeCard/Badge *tone*, not a ToastKind — the two
      // vocabularies got crossed here. Turning a consent off is a state change,
      // not a failure, so it reads as info.
      toast(lang === 'zh' ? '已关闭紧急 GPS 授权' : 'Emergency GPS consent disabled', 'info')
      return
    }

    setBusy(true)
    try {
      if ('geolocation' in navigator) {
        await new Promise<GeolocationPosition>((resolve, reject) => {
          navigator.geolocation.getCurrentPosition(resolve, reject, {
            timeout: 8000,
            enableHighAccuracy: true,
          })
        })
      }
      await setEmergencyGpsConsent(true)
      setEnabled(true)
      toast(lang === 'zh' ? '已开启紧急 GPS 授权，设备定位权限申请成功' : 'Emergency GPS consent granted & location ready', 'ok')
    } catch (e) {
      // The OS prompt being declined or timing out is not a reason to lose the
      // consent itself — the user said yes to sharing, iOS just has not handed
      // over a fix yet. But if recording that consent fails, the switch must
      // not claim to be on: SOS reads the stored answer, so a switch that shows
      // "on" over an unstored consent would silently withhold the location.
      console.warn('Geolocation permission error:', e)
      try {
        await setEmergencyGpsConsent(true)
        setEnabled(true)
        toast(lang === 'zh' ? '紧急 GPS 授权已开启（如弹窗请允许定位权限）' : 'Emergency GPS enabled (please allow location prompt)', 'ok')
      } catch (saveErr) {
        setEnabled(false)
        toast(
          lang === 'zh'
            ? `授权未能保存,请重试:${saveErr instanceof Error ? saveErr.message : String(saveErr)}`
            : `Consent was not saved, please retry: ${saveErr instanceof Error ? saveErr.message : String(saveErr)}`,
          'danger',
        )
      }
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <label className="home-prototype__consent" style={{ cursor: 'pointer' }}>
        <input
          type="checkbox"
          checked={enabled}
          disabled={busy}
          onChange={(e) => void handleToggle(e.target.checked)}
        />
        <span>
          <strong>{lang === 'zh' ? '紧急定位' : 'Emergency location'}</strong>
          {/* 和这一块其他权限一样写后果:少了它,来找您的人不知道去哪里找。
              「勾选即可发起设备定位权限申请」说的是系统流程,不是用户关心的事。 */}
          <small>
            {enabled
              ? (lang === 'zh'
                  ? '开启。位置只在告警真正发生时读取一次,平时不记录,也不追踪行程。'
                  : 'On. Your location is read once, only when an alert actually fires. Nothing is recorded or tracked otherwise.')
              : (lang === 'zh'
                  ? '未开启。出事时,来找您的人不知道该去哪里找。'
                  : 'Off. If something happens, the people coming for you will not know where to look.')}
          </small>
        </span>
      </label>
    </>
  )
}

function PreferencesCard({ isGm }: { isGm: boolean }) {
  const { lang } = useI18n()
  return (
    <>
      <PrototypeRow icon="language" title={lang === 'zh' ? '语言' : 'Language'} trailing={<LangToggle className="prototype-button prototype-button--ghost" />} />
      <PrototypeRow icon="contrast" title={lang === 'zh' ? '外观' : 'Appearance'} trailing={<ThemeToggle className="prototype-button prototype-button--ghost" />} />
      <UpdatesCard isGm={isGm} />
    </>
  )
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
  const [scanningJoin, setScanningJoin] = useState(false)
  const [newCommunity, setNewCommunity] = useState('')
  const [newGroup, setNewGroup] = useState('')
  const [newGroupCommunity, setNewGroupCommunity] = useState('')
  const [notice, setNotice] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState<PrimaryTab>('watch')
  const [gmOpen, setGmOpen] = useState(false)
  const [isGm, setIsGm] = useState(false)
  const [unread, setUnread] = useState(0)
  const [ownTaskCount, setOwnTaskCount] = useState(0)
  const [activeAlertCount, setActiveAlertCount] = useState(0)
  const [sosBusy, setSosBusy] = useState(false)
  const [qrTarget, setQrTarget] = useState<{ url: string; name: string } | null>(null)
  const [onboardingCompleted, setOnboardingCompleted] = useState(true)
  const [gmResolved, setGmResolved] = useState(false)

  async function handleQrScan(data: string) {
    setIsScanning(false)
    if (!data.startsWith('keepcontact://sync?token=')) {
      toast(t('profile.scan.failed'), 'danger')
      return
    }
    const targetToken = data.replace('keepcontact://sync?token=', '')
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error(t('err.load'))
      const { data: payload, error: syncError } = await supabase.functions.invoke('sync-auth')
      if (syncError || !payload?.email || !payload?.otp) throw syncError ?? new Error('sync-auth unavailable')
      const channel = supabase.channel(`scan2sync:${targetToken}`, { config: { broadcast: { self: false } } })
      channel.subscribe(async (status) => {
        if (status !== 'SUBSCRIBED') return
        await channel.send({ type: 'broadcast', event: 'sync', payload: { email: payload.email, otp: payload.otp } })
        toast(t('profile.scan.success'), 'ok')
        window.setTimeout(() => void supabase.removeChannel(channel), 2000)
      })
    } catch {
      toast(t('profile.scan.failed'), 'danger')
    }
  }

  const refresh = useCallback(async () => {
    setError(null)
    try {
      const [nextCommunities, nextGroups] = await Promise.all([listMyCommunities(), listMyGroups()])
      setCommunities(nextCommunities)
      setGroups(nextGroups)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : translate('err.load'))
    } finally {
      setLoading(false)
    }
  }, [])

  const refreshWatchMeta = useCallback(async () => {
    const [notifications, tasks, alerts] = await Promise.all([
      listMyNotifications().catch(() => []),
      listMyTasks().catch(() => []),
      listOpenAlerts().catch(() => []),
    ])
    const nextUnread = notifications.filter((item) => !item.read_at).length
    setUnread(nextUnread)
    setOwnTaskCount(tasks.length)
    setActiveAlertCount(alerts.length)
    setBadge(nextUnread)
  }, [])

  useEffect(() => {
    if (!gmResolved || !user?.id) return
    setOnboardingCompleted(checkAndMigrateOnboarding(user.id, isGm))
  }, [gmResolved, isGm, user?.id])

  useEffect(() => {
    void ensurePushSubscription()
    void reportClient()
    void amIGm().then((gm) => { setIsGm(gm); setGmResolved(true) })
    void refresh()
    void refreshWatchMeta()
    if (!Capacitor.isNativePlatform() && 'geolocation' in navigator) {
      navigator.permissions?.query({ name: 'geolocation' as PermissionName }).then((permission) => {
        if (permission.state === 'prompt') navigator.geolocation.getCurrentPosition(() => undefined, () => undefined, { timeout: 2000 })
      }).catch(() => undefined)
    }
  }, [refresh, refreshWatchMeta])

  useEffect(() => {
    const refreshAll = () => { void refresh(); void refreshWatchMeta() }
    const timer = window.setInterval(refreshAll, 60_000)
    const onVisible = () => { if (document.visibilityState === 'visible') refreshAll() }
    document.addEventListener('visibilitychange', onVisible)
    let stopAlerts: (() => void) | undefined
    let stopGroups: (() => void) | undefined
    void subscribeAlertSignals(refreshAll).then((stop) => { stopAlerts = stop })
    void subscribeGroupStatusSignals(refreshAll).then((stop) => { stopGroups = stop })
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      stopAlerts?.()
      stopGroups?.()
    }
  }, [refresh, refreshWatchMeta])

  useEffect(() => {
    const invite = takePendingInvite()
    if (!invite) return
    joinByInvite(invite).then((message) => { setNotice(message); void refresh() }).catch((caught) => setError(caught instanceof Error ? caught.message : translate('err.load')))
  }, [refresh])

  async function run(operation: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await operation()
      await refresh()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : translate('err.op'))
    } finally {
      setBusy(false)
    }
  }

  async function doSos() {
    if (sosBusy) return
    setSosBusy(true)
    try {
      await dispatchSos()
      toast(t('sos.sent'), 'danger')
      await refreshWatchMeta()
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : t('sos.failed'), 'danger')
    } finally {
      setSosBusy(false)
    }
  }

  async function onShare(invite: Invite, name: string) {
    const result = await shareInvite(invite.kind, invite.code, name)
    if (result.status === 'copied') setNotice(t('invite.copied'))
    else if (result.status === 'manual') setNotice(t('invite.manual', { url: result.url }))
  }

  function onShowQr(invite: Invite, name: string) {
    setQrTarget({ url: buildInviteUrl(invite.kind, invite.code), name })
  }

  async function handleJoinScan(data: string) {
    setScanningJoin(false)
    const invite = parseInviteText(data)
    if (!invite) {
      toast(t('invite.invalid'), 'danger')
      return
    }
    await run(async () => setNotice(await joinByInvite(invite)))
  }

  const [showCreateGroup, setShowCreateGroup] = useState(false)
  const [showCreateCommunity, setShowCreateCommunity] = useState(false)

  const communityCards = (
    <div className="home-prototype__stack">
      {showCreateCommunity && (
        <PrototypeCard compact className="home-prototype__create-row">
          <input value={newCommunity} onChange={(event) => setNewCommunity(event.target.value)} placeholder={t('comm.new.ph')} />
          <button type="button" className="prototype-button prototype-button--primary" disabled={busy || !newCommunity.trim()} onClick={() => void run(async () => { await createCommunity(newCommunity.trim()); setNewCommunity(''); setShowCreateCommunity(false) })}>{t('comm.create')}</button>
          <button type="button" className="prototype-button prototype-button--ghost" onClick={() => setShowCreateCommunity(false)}>{lang === 'zh' ? '取消' : 'Cancel'}</button>
        </PrototypeCard>
      )}
      {loading ? <PrototypeCard compact>{t('home.loading')}</PrototypeCard> : communities.map((community) => (
        <PrototypeCard key={community.id} compact>
          <PrototypeRow
            icon="diversity_3"
            title={<EditableName value={community.name} canEdit={community.created_by === user?.id} onSave={async (name) => { await renameCommunity(community.id, name); await refresh() }} />}
            subtitle={lang === 'zh' ? '阶梯响应网络 · 仅在危机分配时分享细节' : 'Escalation network · crisis details shared only when assigned'}
            trailing={<PrototypeBadge tone="ready">{lang === 'zh' ? '社群' : 'Community'}</PrototypeBadge>}
          />
          <PrototypeDisclosure label={lang === 'zh' ? '谁能看到什么' : 'Who can see what'}>
            <p className="home-prototype__privacy-text">
              {lang === 'zh'
                ? '社群响应者只能看到分配给他们的告警和最低必要的处理信息。日常活动和作息时间戳只保留在您的关照圈内。'
                : 'Community responders see an assigned alert and the minimum information needed to act. Routine evidence stays inside your Circle.'}
            </p>
          </PrototypeDisclosure>
          <div className="home-prototype__action-grid">
            <button type="button" className="prototype-button prototype-button--ghost" onClick={() => void onShare({ kind: 'community', code: community.invite_code }, community.name)}>
              <PrototypeIcon name="person_add" />
              {t('share.invite')}
            </button>
            <button type="button" className="prototype-button prototype-button--ghost" onClick={() => onShowQr({ kind: 'community', code: community.invite_code }, community.name)}>
              <PrototypeIcon name="qr_code_2" />
              {t('qr.show')}
            </button>
            {community.created_by === user?.id && (
              <button type="button" className="prototype-button home-prototype__danger" disabled={busy} onClick={() => { if (window.confirm(t('admin.delete.confirm.community'))) void run(() => deleteCommunity(community.id)) }}>
                {t('admin.delete')}
              </button>
            )}
          </div>
        </PrototypeCard>
      ))}
    </div>
  )

  const circleCards = (
    <div className="home-prototype__stack">
      {showCreateGroup && (
        <PrototypeCard compact className="home-prototype__create-row">
          <input value={newGroup} onChange={(event) => setNewGroup(event.target.value)} placeholder={t('group.new.ph')} />
          <select value={newGroupCommunity} onChange={(event) => setNewGroupCommunity(event.target.value)}>
            <option value="">{t('group.standalone')}</option>
            {communities.map((community) => <option key={community.id} value={community.id}>{community.name}</option>)}
          </select>
          <button type="button" className="prototype-button prototype-button--primary" disabled={busy || !newGroup.trim()} onClick={() => void run(async () => { await createGroup(newGroup.trim(), newGroupCommunity || null); setNewGroup(''); setShowCreateGroup(false) })}>{t('comm.create')}</button>
          <button type="button" className="prototype-button prototype-button--ghost" onClick={() => setShowCreateGroup(false)}>{lang === 'zh' ? '取消' : 'Cancel'}</button>
        </PrototypeCard>
      )}
      {loading ? <PrototypeCard compact>{t('home.loading')}</PrototypeCard> : groups.map(({ group, monitored, watching, role }) => (
        <PrototypeCard key={group.id} compact>
          <PrototypeRow
            icon="groups"
            title={<EditableName value={group.name} canEdit={group.created_by === user?.id} onSave={async (name) => { await renameGroup(group.id, name); await refresh() }} />}
            subtitle={lang === 'zh'
              ? `${role === 'admin' ? '管理员 · ' : ''}${monitored && watching ? '双向关照 · 时间戳共享' : monitored ? '对方关照您' : watching ? '您关照对方' : '单向'}`
              : `${role === 'admin' ? 'Admin · ' : ''}${monitored && watching ? 'Reciprocal care' : 'One-way care'}`
            }
            trailing={<PrototypeBadge tone={monitored && watching ? 'ready' : 'limited'}>{monitored && watching ? (lang === 'zh' ? '双向' : 'Reciprocal') : (lang === 'zh' ? '单向' : 'One-way')}</PrototypeBadge>}
          />

          <PrototypeDisclosure label={lang === 'zh' ? '查看成员与权限' : 'View members & settings'}>
            <GroupBoard groupId={group.id} mode="group" isAdmin={role === 'admin'} />
            <div className="home-prototype__toggle-row">
              <label>
                <input type="checkbox" checked={monitored} disabled={busy} onChange={(event) => void run(() => setMonitoringDirection(group.id, { monitored: event.target.checked }))} />
                {t('group.monitored')}
              </label>
              <label>
                <input type="checkbox" checked={watching} disabled={busy} onChange={(event) => void run(() => setMonitoringDirection(group.id, { watching: event.target.checked }))} />
                {t('group.watching')}
              </label>
            </div>
            {group.created_by === user?.id && (
              <label className="home-prototype__select-row">
                {t('group.community')}
                <select value={group.community_id ?? ''} disabled={busy} onChange={(event) => void run(() => setGroupCommunity(group.id, event.target.value || null))}>
                  <option value="">{t('group.standalone')}</option>
                  {communities.map((community) => <option key={community.id} value={community.id}>{community.name}</option>)}
                </select>
              </label>
            )}
          </PrototypeDisclosure>

          <div className="home-prototype__action-grid">
            <button type="button" className="prototype-button prototype-button--ghost" onClick={() => void onShare({ kind: 'group', code: group.invite_code }, group.name)}>
              <PrototypeIcon name="person_add" />
              {t('share.invite')}
            </button>
            <button type="button" className="prototype-button prototype-button--ghost" onClick={() => onShowQr({ kind: 'group', code: group.invite_code }, group.name)}>
              <PrototypeIcon name="qr_code_2" />
              {t('qr.show')}
            </button>
            <button type="button" className="prototype-button home-prototype__danger" disabled={busy} onClick={() => { if (window.confirm(t('group.leave.confirm'))) void run(() => leaveGroup(group.id)) }}>
              {t('group.leave')}
            </button>
            {group.created_by === user?.id && (
              <button type="button" className="prototype-button home-prototype__danger" disabled={busy} onClick={() => { if (window.confirm(t('admin.delete.confirm.group'))) void run(() => deleteGroup(group.id)) }}>
                {t('admin.delete')}
              </button>
            )}
          </div>
        </PrototypeCard>
      ))}
    </div>
  )

  const screen = gmOpen && isGm ? (
    <GMScreen active onBack={() => setGmOpen(false)} />
  ) : activeTab === 'watch' ? (
    <WatchScreen
      title={activeAlertCount > 0 ? (lang === 'zh' ? '有人需要确认' : 'Someone needs confirmation') : (lang === 'zh' ? '一切都在正常运作' : 'Everything looks steady')}
      subtitle={activeAlertCount > 0 ? (lang === 'zh' ? `${activeAlertCount} 个告警正在处理中` : `${activeAlertCount} active alert${activeAlertCount === 1 ? '' : 's'}`) : (lang === 'zh' ? 'Keep Contact 会安静留意真正值得关注的变化。' : 'Keep Contact stays quiet until something actually needs attention.')}
      isGm={isGm}
      hasOwnTask={ownTaskCount > 0}
      hasActiveAlert={activeAlertCount > 0}
      summary={<PrototypeCard compact><PrototypeRow icon="radar" title={lang === 'zh' ? `${groups.length} 个关照圈正在连接` : `${groups.length} circle${groups.length === 1 ? '' : 's'} connected`} subtitle={lang === 'zh' ? '下方保留每个人的真实活动时间与告警状态。' : 'Real activity timing and alert state remain visible below.'} /></PrototypeCard>}
      ownTask={<CheckinTasksCard />}
      gmTools={<><strong>{lang === 'zh' ? '管理工具' : 'Manager tools'}</strong><p>{lang === 'zh' ? '查看成员、版本与运营状态。' : 'Review members, versions, and operational status.'}</p><button type="button" className="prototype-button prototype-button--primary" onClick={() => setGmOpen(true)}>{lang === 'zh' ? '进入' : 'Open'}</button></>}
      notifications={<div className="home-prototype__stack"><ProtectionHealthCard /><ApkUpgradeNotice /><NotificationsCard onChanged={refreshWatchMeta} /></div>}
      people={<StatusBoard />}
      alertResponse={<p>{lang === 'zh' ? 'Concern 只会在真实告警发生后出现，用来先确认是否误报。' : 'Concern is available only after a real alert, to check whether it may be a false alarm.'}</p>}
      labels={{ gm: lang === 'zh' ? '管理员工具' : 'Manager tools', notifications: lang === 'zh' ? '通知' : 'Notifications', people: lang === 'zh' ? '大家的状态' : "Everyone's status", alert: lang === 'zh' ? '需要处理' : 'Needs action' }}
    />
  ) : activeTab === 'routine' ? (
    <RoutineScreen title={lang === 'zh' ? '日常与节奏' : 'Routine & rhythm'} subtitle={lang === 'zh' ? '调整系统如何理解您的正常生活。' : 'Tune how Keep Contact understands your normal day.'}><RoutineSettings /></RoutineScreen>
  ) : activeTab === 'circles' ? (
    <CirclesScreen
      title={lang === 'zh' ? '关照圈' : 'Circles'}
      subtitle={lang === 'zh' ? '关系、社群与特别责任各自清楚分开。' : 'Keep relationships, communities, and special responsibilities distinct.'}
      circles={circleCards}
      community={communityCards}
      responsibilities={<div className="home-prototype__stack"><GuardiansCard /></div>}
      onScanJoin={() => setScanningJoin(true)}
      onCreateGroup={() => setShowCreateGroup(!showCreateGroup)}
      onCreateCommunity={() => setShowCreateCommunity(!showCreateCommunity)}
      labels={{ circles: lang === 'zh' ? '群组' : 'Circles', community: lang === 'zh' ? '社群' : 'Community', responsibilities: lang === 'zh' ? '特别关照与责任' : 'Responsibilities' }}
    />
  ) : (
    <MeScreen
      title={lang === 'zh' ? '我' : 'Me'}
      subtitle={lang === 'zh' ? '账户、设备与紧急资料都在这里。' : 'Your account, devices, and emergency information.'}
      account={<AccountCard onScan={() => setIsScanning(true)} signOut={signOut} />}
      safetyCheckin={<SafetyCheckinCard />}
      guardianPermissions={<><GuardianPermissionsCard /><PassiveSignalCard /></>}
      emergency={<EmergencyInfoCard section="all" />}
      emergencyGps={<EmergencyGpsCard />}
      preferencesUpdates={<PreferencesCard isGm={isGm} />}
      labels={{ account: lang === 'zh' ? '账户与设备' : 'Account & devices', safetyCheckin: lang === 'zh' ? '安全确认' : 'Safety check-in', guardianPermissions: lang === 'zh' ? '守护权限与设置' : 'Guardian permissions', emergency: lang === 'zh' ? '紧急资料' : 'Emergency information', preferencesUpdates: lang === 'zh' ? '偏好与更新' : 'Preferences & updates' }}
    />
  )

  return (
    <LivenessProvider>
      <div className="home home-prototype">
        <PassivePingBoot />
        <AlertOverlay />
        <ToastHost />
        {error && <p className="home-prototype__floating-message is-error">{error}</p>}
        {notice && <p className="home-prototype__floating-message">{notice}</p>}
        {!onboardingCompleted ? (
          <OnboardingWizard isGm={isGm} onComplete={() => { if (user?.id) saveOnboardingCompleted(user.id, isGm); setOnboardingCompleted(true) }} />
        ) : (
          <AppShell
            activeTab={activeTab}
            onTabChange={(tab) => { setGmOpen(false); setActiveTab(tab) }}
            onSos={doSos}
            displayName={(user?.user_metadata?.display_name as string | undefined) ?? user?.email ?? ''}
            unreadCount={unread}
            sosBusy={sosBusy}
            contentKey={gmOpen ? 'gm' : activeTab}
          >
            {screen}
          </AppShell>
        )}
        {isScanning && <ScanSyncModal onClose={() => setIsScanning(false)} onScan={handleQrScan} />}
        {scanningJoin && <ScanSyncModal onClose={() => setScanningJoin(false)} onScan={handleJoinScan} />}
        {qrTarget && <QRModal url={qrTarget.url} title={qrTarget.name} onClose={() => setQrTarget(null)} />}
      </div>
    </LivenessProvider>
  )
}
