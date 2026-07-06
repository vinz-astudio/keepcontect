import { useCallback, useEffect, useState } from 'react'
import {
  gmListClients,
  gmNudgeUpdate,
  gmSendConcern,
  gmDeleteAccount,
  gmListVersions,
  gmReleaseVersion,
  type GmClient,
  type DbVersionInfo,
} from '@/features/gm/gmApi'
import { ViewportDiagnosticsCard } from '@/features/profile/ViewportDiagnosticsCard'
import { subscribeGmStatusSignals } from '@/features/alerts/realtime'
import { translate, useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import { Icon } from '@/features/common/Icon'
import {
  isClientBehindTarget,
  selectLatestVersion,
  type VersionChannel,
} from '@/features/update/versionSelection'
import { APP_VERSION } from '@/lib/version'
import { formatBehaviorTime } from '@/features/gm/behaviorTime'
import './GMScreen.css'

interface UserRow {
  user_id: string
  name: string
  clients: GmClient[]
  /** 设备心跳时间(device_state) — 仅作参考 */
  last_heartbeat_at: string | null
  /** 最后真实行为信号时间(behavior_pings) — 与 silence 检测同源 */
  last_behavior_at: string | null
  /** 是否有 group+ open 告警 */
  alerted: boolean
  /** 基于 behavior_pings 的统一状态，与 process_escalations 保持一致 */
  status: 'alert' | 'active' | 'quiet' | 'silent' | 'never'
}

// 设备在用判定:30 天内有上报才算"目前在用"
const RECENCY_MS = 30 * 86_400_000

const BASE_LABEL: Record<string, Record<string, string>> = {
  zh: { ios: 'iOS', android: 'Android', desktop: '桌面' },
  en: { ios: 'iOS', android: 'Android', desktop: 'Desktop' },
}
const KIND_LABEL: Record<string, Record<string, string>> = {
  zh: { pwa: 'PWA', app: 'App', apk: 'APK', web: '网页' },
  en: { pwa: 'PWA', app: 'App', apk: 'APK', web: 'Web' },
}

// 渠道形如 {ios|android|desktop}-{pwa|app|apk|web}
function platBase(p: string | null | undefined): string {
  return (p ?? '').toLowerCase().split('-')[0]
}
function platKind(p: string | null | undefined): string {
  return (p ?? '').toLowerCase().split('-')[1] ?? ''
}

function latestSeen(clients: GmClient[]): number {
  let m = 0
  for (const c of clients) {
    const t = c.last_seen_at ? new Date(c.last_seen_at).getTime() : 0
    if (t > m) m = t
  }
  return m
}

/**
 * 折叠"已删除/一次性"的旧设备,得到目前实际在用的设备:
 * - 仅保留 30 天内有上报的(更早的视为已不再使用)。
 * - 网页会话(*-web)清空 localStorage / 隐身 / 换浏览器都会换 id,属一次性会话:
 *   按平台折叠成一条,显示最近一次 + 会话数,不再每次都堆一行。
 * - 已安装客户端(pwa/app/apk)的 id 在该安装内稳定,各自单独列出。
 */
function liveDevices(clients: GmClient[]): GmClient[] {
  const now = Date.now()
  const recent = clients.filter(
    (c) =>
      c.last_seen_at && now - new Date(c.last_seen_at).getTime() < RECENCY_MS,
  )
  
  const nativeByPlatform = new Map<string, GmClient>()
  const webByBase = new Map<string, GmClient[]>()
  
  for (const c of recent) {
    const kind = platKind(c.platform)
    const base = platBase(c.platform)
    
    if (kind === 'web') {
      const arr = webByBase.get(base) ?? []
      arr.push(c)
      webByBase.set(base, arr)
    } else {
      // Installed app client (apk, app, pwa). 
      // De-duplicate by keeping only the latest active client ID for this platform.
      const platKey = c.platform || 'unknown'
      const existing = nativeByPlatform.get(platKey)
      if (!existing || new Date(c.last_seen_at!).getTime() > new Date(existing.last_seen_at!).getTime()) {
        nativeByPlatform.set(platKey, c)
      }
    }
  }
  
  const out = Array.from(nativeByPlatform.values())
  for (const [, arr] of webByBase) {
    const latest = arr.reduce((a, b) =>
      new Date(a.last_seen_at!).getTime() >= new Date(b.last_seen_at!).getTime()
        ? a
        : b,
    )
    out.push({ ...latest, web_count: arr.length })
  }
  out.sort(
    (a, b) =>
      new Date(b.last_seen_at ?? 0).getTime() -
      new Date(a.last_seen_at ?? 0).getTime(),
  )
  return out
}

/** 单设备标签;平台无法识别时不编造设备类型,只显示版本 */
function deviceLabel(c: GmClient, lang: string): string {
  const baseLabel = (BASE_LABEL[lang] ?? BASE_LABEL.en)[platBase(c.platform)]
  const kindLabel = (KIND_LABEL[lang] ?? KIND_LABEL.en)[platKind(c.platform)]
  const ver = c.app_version ? `v${c.app_version}` : '?'
  const count = c.web_count && c.web_count > 1 ? ` ×${c.web_count}` : ''
  if (!baseLabel) return `${ver}${count}`
  return `${baseLabel}${kindLabel ? ` ${kindLabel}` : ''} ${ver}${count}`
}

function formatDevices(clients: GmClient[], lang: string): string {
  const live = liveDevices(clients)
  if (!live.length) return lang === 'zh' ? '无在用设备' : 'No active device'
  return live.map((c) => deviceLabel(c, lang)).join(' | ')
}

function renderDevicesList(clients: GmClient[], lang: string) {
  const live = liveDevices(clients)
  if (!live.length) {
    return (
      <span className="gm__device-empty" style={{ opacity: 0.5 }}>
        {lang === 'zh' ? '无在用设备' : 'No active device'}
      </span>
    )
  }
  return live.map((c, i) => (
    <div
      key={i}
      className="gm__device-line"
      style={{ display: 'block', whiteSpace: 'nowrap' }}
    >
      {deviceLabel(c, lang)}
    </div>
  ))
}

interface GMScreenProps {
  active?: boolean
  onBack?: () => void
}

export function GMScreen({ active = true, onBack }: GMScreenProps) {
  const { t, lang } = useI18n()
  const [rows, setRows] = useState<UserRow[]>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  
  // Search, filter & sort states
  const [search, setSearch] = useState('')
  const [onlyOutdated, setOnlyOutdated] = useState(false)
  const [sortBy, setSortBy] = useState<'name' | 'seen' | 'version'>('name')
  const [bulkNudgeBusy, setBulkNudgeBusy] = useState(false)
  
  const [dbVersions, setDbVersions] = useState<DbVersionInfo[]>([])
  const [versionChannel, setVersionChannel] = useState<VersionChannel>('canary')
  const [releaseBusy, setReleaseBusy] = useState(false)
  const [showDiagnostics, setShowDiagnostics] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try {
      // Query latest version rollout info
      try {
        const versions = await gmListVersions()
        setDbVersions(versions)
      } catch (e) {
        console.warn('Failed to load version info from database:', e)
      }

      const list = await gmListClients()
      const map = new Map<string, UserRow>()
      for (const c of list) {
        const r =
          map.get(c.user_id) ??
          {
            user_id: c.user_id,
            name: c.name,
            clients: [] as GmClient[],
            last_heartbeat_at: null,
            last_behavior_at: null,
            alerted: false,
            status: 'never' as const,
          }
        if (c.platform || c.app_version) r.clients.push(c)

        // Track latest device heartbeat (informational only)
        const hb = c.last_heartbeat_at || c.last_seen_at
        if (hb && (!r.last_heartbeat_at || hb > r.last_heartbeat_at)) {
          r.last_heartbeat_at = hb
        }

        // Track latest behavior ping — this is the source of truth for silence detection
        const bp = c.last_behavior_at
        if (bp && (!r.last_behavior_at || bp > r.last_behavior_at)) {
          r.last_behavior_at = bp
        }

        if (c.alerted) r.alerted = true

        // Use server-computed status (based on behavior_pings, matching process_escalations)
        if (c.status) {
          r.status = c.status as UserRow['status']
        }

        map.set(c.user_id, r)
      }

      setRows([...map.values()])
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    }
  }, [])

  useEffect(() => {
    if (!active) return
    void load()
    const timer = window.setInterval(() => void load(), 30_000)
    const onVisible = () => {
      if (document.visibilityState === 'visible') void load()
    }
    document.addEventListener('visibilitychange', onVisible)
    let unsubscribe: (() => void) | undefined
    let pending = false
    const scheduleLoad = () => {
      if (pending) return
      pending = true
      window.setTimeout(() => {
        pending = false
        void load()
      }, 500)
    }
    void subscribeGmStatusSignals(scheduleLoad).then((fn) => {
      unsubscribe = fn
    })
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      unsubscribe?.()
    }
  }, [load, active])

  async function act(key: string, fn: () => Promise<void>, okMsg: string) {
    setBusy(key)
    try {
      await fn()
      toast(okMsg, 'ok')
    } catch (e) {
      toast(e instanceof Error ? e.message : translate('err.op'), 'danger')
    } finally {
      setBusy(null)
    }
  }

  const selectedVersion = selectLatestVersion(dbVersions, versionChannel)
  const targetVersion = selectedVersion?.version ?? APP_VERSION

  function isRowOutdated(row: UserRow): boolean {
    return row.clients.length === 0 || row.clients.some((client) =>
      isClientBehindTarget(client.app_version, targetVersion),
    )
  }

  async function handleDeleteAccount(userId: string, name: string) {
    const confirmMsg = lang === 'zh'
      ? `【警告】确认要物理删除/封禁用户「${name}」的账号吗？此操作将级联删除该用户的所有数据（设备、警报、群组等）且不可逆！`
      : `[WARNING] Are you sure you want to permanently delete/ban account "${name}"? This will cascade delete all associated user data and is IRREVERSIBLE!`
    if (!window.confirm(confirmMsg)) return

    setBusy(userId + 'd')
    try {
      await gmDeleteAccount(userId)
      toast(lang === 'zh' ? '删除成功！' : 'Account deleted successfully!', 'ok')
      void load()
    } catch (e) {
      toast(e instanceof Error ? e.message : translate('err.op'), 'danger')
    } finally {
      setBusy(null)
    }
  }

  async function bulkNudge() {
    const outdatedUsers = sorted.filter(isRowOutdated)

    if (!outdatedUsers.length) {
      toast(lang === 'zh' ? '当前列表下没有未升级的用户' : 'No outdated users found in this list', 'info')
      return
    }

    const confirmMsg = lang === 'zh'
      ? `确认要一键发送升级通知给这 ${outdatedUsers.length} 位用户吗？目标版本：v${targetVersion}`
      : `Send update nudges to all ${outdatedUsers.length} outdated users for v${targetVersion}?`
    if (!window.confirm(confirmMsg)) return

    setBulkNudgeBusy(true)
    let count = 0
    try {
      for (const u of outdatedUsers) {
        await gmNudgeUpdate(u.user_id)
        count++
      }
      toast(lang === 'zh' ? `成功一键通知了 ${count} 名用户！` : `Nudged ${count} users successfully!`, 'ok')
    } catch (e) {
      toast(e instanceof Error ? e.message : '一键操作失败', 'danger')
    } finally {
      setBulkNudgeBusy(false)
      void load()
    }
  }

  const handleReleaseVersion = async () => {
    if (!selectedVersion) return
    const ok = window.confirm(
      lang === 'zh'
        ? `确认要发布版本 ${selectedVersion.version} 给所有用户吗？这会启动所有被守护者端的更新通知。`
        : `Are you sure you want to release version ${selectedVersion.version} to all users? This will trigger update notifications on recipients' devices.`
    )
    if (!ok) return
    setReleaseBusy(true)
    try {
      await gmReleaseVersion(selectedVersion.version)
      toast(lang === 'zh' ? '新版本发布成功！' : 'New version released successfully!', 'ok')
      await load()
    } catch (err) {
      console.error('Failed to release version:', err)
      toast(lang === 'zh' ? '发布失败' : 'Failed to release version', 'danger')
    } finally {
      setReleaseBusy(false)
    }
  }

  // 1. Filter
  const filtered = rows.filter((r) => {
    const matchSearch =
      r.name.toLowerCase().includes(search.toLowerCase()) ||
      r.user_id.toLowerCase().includes(search.toLowerCase())
    
    if (!matchSearch) return false

    const hasOutdatedClient = isRowOutdated(r)

    if (onlyOutdated && !hasOutdatedClient) return false

    return true
  })

  // 2. Sort
  const sorted = [...filtered].sort((a, b) => {
    if (sortBy === 'name') {
      return a.name.localeCompare(b.name)
    }
    if (sortBy === 'seen') {
      // Sort by last real behavior signal (same source as silence detection)
      const at = (r: UserRow) =>
        r.last_behavior_at
          ? new Date(r.last_behavior_at).getTime()
          : (r.last_heartbeat_at ? new Date(r.last_heartbeat_at).getTime() : latestSeen(r.clients))
      return at(b) - at(a)
    }
    if (sortBy === 'version') {
      const aOutdated = isRowOutdated(a)
      const bOutdated = isRowOutdated(b)
      return (bOutdated ? 1 : 0) - (aOutdated ? 1 : 0)
    }
    return 0
  })

  return (
    <section className="card gm-panel" style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
      {onBack && (
        <button 
          onClick={onBack}
          className="share"
          style={{ 
            alignSelf: 'flex-start',
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            padding: '6px 12px',
            fontSize: '0.85rem',
            background: 'var(--bg)',
            color: 'var(--fg)',
            border: '1px solid var(--line)',
            borderRadius: 'var(--r-md)',
            cursor: 'pointer'
          }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <path d="M19 12H5M12 19l-7-7 7-7" />
          </svg>
          {lang === 'zh' ? '返回群组' : 'Back to Circles'}
        </button>
      )}
      <h2 className="card__title" style={{ margin: 0 }}>
        <Icon name="shield" />
        {t('gm.title')}
      </h2>
      <p className="muted">{t('gm.desc')}</p>

      {/* 1. Canary Version Release Control Panel */}
      <div style={{ background: 'var(--bg-soft)', border: '1px solid var(--line-strong)', borderRadius: 'var(--r-md)', padding: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
        <h3 style={{ margin: 0, fontSize: '0.98rem', fontWeight: '700', display: 'flex', alignItems: 'center', gap: '8px' }}>
          📦 {lang === 'zh' ? '客户端版本管理 (灰度发布控制)' : 'App Version Management (Canary Control)'}
        </h3>
        <p className="muted" style={{ fontSize: '0.82rem', margin: 0, lineHeight: '1.4' }}>
          {lang === 'zh'
            ? '新版本发布后，状态默认为「内测 (Canary)」，此时仅守护者能检测并升级体验。确认稳定后，可在此一键发布给所有普通用户。'
            : 'New updates start as "Canary" and are only visible to GMs. Once verified stable, release it here to notify all general recipients.'}
        </p>
        <div
          role="group"
          aria-label={lang === 'zh' ? '版本通道' : 'Version channel'}
          style={{ display: 'inline-flex', alignSelf: 'flex-start', gap: '6px', padding: '4px', background: 'var(--bg)', border: '1px solid var(--line)', borderRadius: 'var(--r-sm)' }}
        >
          {(['canary', 'released'] as const).map((channel) => {
            const selected = versionChannel === channel
            return (
              <button
                key={channel}
                type="button"
                onClick={() => setVersionChannel(channel)}
                aria-pressed={selected}
                style={{
                  border: '1px solid transparent',
                  borderRadius: 'var(--r-sm)',
                  padding: '6px 10px',
                  minWidth: '88px',
                  background: selected ? 'var(--accent)' : 'transparent',
                  color: selected ? 'white' : 'var(--fg)',
                  fontWeight: 700,
                  cursor: 'pointer',
                }}
              >
                {channel === 'canary' ? 'Canary' : 'Released'}
              </button>
            )
          })}
        </div>
        {selectedVersion ? (
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: '12px', background: 'rgba(0,0,0,0.15)', padding: '10px 14px', borderRadius: 'var(--r-sm)', fontSize: '0.85rem' }}>
            <div>
              <span style={{ fontWeight: 'bold', marginRight: '8px' }}>{lang === 'zh' ? '目标版本:' : 'Target Version:'}</span>
              <strong style={{ color: 'var(--accent)' }}>v{selectedVersion.version}</strong>
              <span style={{ margin: '0 12px', color: 'var(--line-strong)' }}>|</span>
              <span style={{ fontWeight: 'bold', marginRight: '8px' }}>{lang === 'zh' ? '当前状态:' : 'Rollout Status:'}</span>
              <strong style={{ color: selectedVersion.status === 'canary' ? 'var(--warn)' : 'var(--ok)' }}>
                {selectedVersion.status === 'canary'
                  ? (lang === 'zh' ? 'Canary 内测中 (仅 GM 可见)' : 'Canary (GMs only)')
                  : (lang === 'zh' ? 'Released 已全量发布' : 'Released to Public')}
              </strong>
            </div>
            {selectedVersion.status === 'canary' && (
              <button
                className="share"
                disabled={releaseBusy}
                onClick={() => void handleReleaseVersion()}
                style={{ 
                  background: 'var(--accent)', 
                  color: 'white', 
                  border: 'none', 
                  padding: '6px 12px', 
                  fontWeight: 'bold', 
                  borderRadius: 'var(--r-sm)',
                  cursor: 'pointer'
                }}
              >
                {releaseBusy ? '...' : (lang === 'zh' ? '发布给所有用户' : 'Release to Public')}
              </button>
            )}
          </div>
        ) : (
          <p className="muted" style={{ fontSize: '0.82rem', fontStyle: 'italic' }}>
            {lang === 'zh' ? '暂无数据库版本记录。将在检测到首个新版本时自动创建。' : 'No version records found in the database.'}
          </p>
        )}
      </div>

      {/* 2. Collapsible Layout Diagnostics Card */}
      <div style={{ background: 'var(--bg-soft)', border: '1px solid var(--line-strong)', borderRadius: 'var(--r-md)', padding: '12px 16px' }}>
        <button
          onClick={() => setShowDiagnostics(!showDiagnostics)}
          style={{
            width: '100%',
            background: 'none',
            border: 'none',
            color: 'var(--fg)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            cursor: 'pointer',
            padding: 0,
            fontSize: '0.94rem',
            fontWeight: '600'
          }}
        >
          <span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            🛠️ {lang === 'zh' ? '系统布局与诊断调试' : 'System Layout & Diagnostics'}
          </span>
          <span>{showDiagnostics ? '▼' : '▶'}</span>
        </button>
        {showDiagnostics && (
          <div style={{ marginTop: '14px', borderTop: '1px dashed var(--line)', paddingTop: '12px', display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid var(--line)', padding: '12px', borderRadius: 'var(--r-sm)' }}>
              <h4 style={{ margin: '0 0 6px 0', fontSize: '0.85rem', fontWeight: 'bold' }}>
                {lang === 'zh' ? '🔄 体验与引导调试' : '🔄 Onboarding Debugging'}
              </h4>
              <p className="muted" style={{ fontSize: '0.78rem', margin: '0 0 10px 0', lineHeight: '1.4' }}>
                {lang === 'zh'
                  ? '点击下方按钮将重置本地浏览器中的「引导完成标记」，这会使 App 重新加载并进入新人打开 App 时的强制设置向导。该操作绝不会删除你的 Supabase 数据库记录或已累积的历史信号数据。'
                  : 'Clicking below resets the "onboarding completed flag" in local storage. This reloads the page and launches the setup wizard. No database records or local signal history will be deleted.'}
              </p>
              <button
                onClick={() => {
                  localStorage.removeItem('kc.onboardingCompleted')
                  window.location.reload()
                }}
                style={{
                  background: 'var(--warn-soft)',
                  color: 'var(--warn)',
                  border: '1px solid var(--warn)',
                  padding: '6px 12px',
                  borderRadius: 'var(--r-sm)',
                  fontSize: '0.8rem',
                  fontWeight: 'bold',
                  cursor: 'pointer'
                }}
              >
                {lang === 'zh' ? '🔄 重新开启新人引导向导' : '🔄 Replay Onboarding Wizard'}
              </button>
            </div>
            <ViewportDiagnosticsCard />
          </div>
        )}
      </div>

      {/* Top action and filter bar */}
      <div className="gm__controls">
        <div className="gm__search-row">
          <input
            type="text"
            className="gm__search"
            placeholder={lang === 'zh' ? '搜索名字或 ID...' : 'Search Name or ID...'}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select
            className="gm__sort"
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value as any)}
            aria-label={lang === 'zh' ? '排序方式' : 'Sort by'}
          >
            <option value="name">{lang === 'zh' ? '按名称排序' : 'Sort by Name'}</option>
            <option value="seen">{lang === 'zh' ? '最近活跃优先' : 'Sort by Activity'}</option>
            <option value="version">{lang === 'zh' ? '未升级用户优先' : 'Sort by Outdated'}</option>
          </select>
        </div>
        
        <div className="gm__actions-row">
          <label className="gm__filter-label">
            <input
              type="checkbox"
              checked={onlyOutdated}
              onChange={(e) => setOnlyOutdated(e.target.checked)}
            />
            <span>{lang === 'zh' ? '仅显示未升级用户' : 'Outdated version only'}</span>
          </label>
          
          <button
            className="gm__bulk-nudge"
            disabled={bulkNudgeBusy}
            onClick={() => void bulkNudge()}
          >
            {bulkNudgeBusy ? '...' : (lang === 'zh' ? '一键通知未升级用户' : 'Nudge Outdated Users')}
          </button>
        </div>
      </div>

      {error && <p className="home__error">{error}</p>}

      {/* Responsive table container */}
      <div className="gm__table-wrapper">
        <table className="gm__table">
          <thead>
            <tr>
              <th style={{ width: '60px', textAlign: 'center' }}>{lang === 'zh' ? '状态' : 'Status'}</th>
              <th style={{ width: '100px' }}>ID</th>
              <th>{lang === 'zh' ? '名字' : 'Name'}</th>
              <th style={{ width: '150px' }}>{lang === 'zh' ? '最新行为' : 'Last behavior'}</th>
              <th>{lang === 'zh' ? '设备与版本' : 'Devices & Versions'}</th>
              <th style={{ width: '320px', textAlign: 'right' }}>{lang === 'zh' ? '操作' : 'Actions'}</th>
            </tr>
          </thead>
          <tbody>
            {sorted.length === 0 ? (
              <tr>
                <td colSpan={6} className="gm__table-empty">
                  {lang === 'zh' ? '无匹配数据' : 'No records found'}
                </td>
              </tr>
            ) : (
              sorted.map((r) => {
                const status = r.status
                const isOutdated = isRowOutdated(r)
                const behaviorTime = formatBehaviorTime(r.last_behavior_at, Date.now(), lang)
                return (
                  <tr key={r.user_id} className={isOutdated ? 'is-outdated-row' : ''}>
                    <td style={{ textAlign: 'center' }}>
                      <span
                        className={`gm__status-dot is-${status}`}
                        title={(() => {
                          const lastBehavior = r.last_behavior_at
                            ? (() => {
                                const s = Math.floor((Date.now() - new Date(r.last_behavior_at).getTime()) / 1000)
                                if (s < 60) return lang === 'zh' ? '行为信号: 刚刚' : 'Signal: just now'
                                if (s < 3600) return lang === 'zh' ? `行为信号: ${Math.floor(s/60)}分钟前` : `Signal: ${Math.floor(s/60)}m ago`
                                if (s < 86400) return lang === 'zh' ? `行为信号: ${Math.floor(s/3600)}小时前` : `Signal: ${Math.floor(s/3600)}h ago`
                                return lang === 'zh' ? `行为信号: ${Math.floor(s/86400)}天前` : `Signal: ${Math.floor(s/86400)}d ago`
                              })()
                            : (lang === 'zh' ? '暂无行为信号' : 'No signal yet')
                          const base =
                            status === 'alert' ? (lang === 'zh' ? '异常告警 · 需关注' : 'Alert · needs attention') :
                            status === 'active' ? (lang === 'zh' ? '近期活跃 (<6h)' : 'Active (<6h)') :
                            status === 'quiet' ? (lang === 'zh' ? '安静 (<24h)' : 'Quiet (<24h)') :
                            status === 'silent' ? (lang === 'zh' ? '长时间无行为信号 (>24h)' : 'No activity signal (>24h)') :
                            (lang === 'zh' ? '暂无数据' : 'No data')
                          return `${base} · ${lastBehavior}`
                        })()}
                      />
                    </td>
                    <td>
                      <span className="gm__short-id" title={r.user_id}>
                        {r.user_id.slice(0, 8)}
                      </span>
                    </td>
                    <td className="gm__table-name" title={r.name}>
                      {r.name}
                    </td>
                    <td className="gm__table-behavior" title={r.last_behavior_at ?? ''}>
                      <span className="gm__behavior-relative">{behaviorTime.relative}</span>
                      {behaviorTime.exact && (
                        <span className="gm__behavior-exact">{behaviorTime.exact}</span>
                      )}
                    </td>
                    <td className="gm__table-device" title={formatDevices(r.clients, lang)}>
                      {renderDevicesList(r.clients, lang)}
                    </td>
                    <td>
                      <div className="gm__table-actions">
                        <button
                          className="gm__row-btn nudge"
                          disabled={busy != null}
                          onClick={() =>
                            void act(
                              r.user_id + 'u',
                              () => gmNudgeUpdate(r.user_id),
                              t('gm.nudged')
                            )
                          }
                          title={t('gm.nudge')}
                        >
                          Nudge
                        </button>
                        <button
                          className="gm__row-btn concern"
                          disabled={busy != null}
                          onClick={() =>
                            void act(
                              r.user_id + 'c',
                              () => gmSendConcern(r.user_id),
                              t('gm.concerned')
                            )
                          }
                          title={t('gm.concern')}
                        >
                          Concern
                        </button>
                        <button
                          className="gm__row-btn ban"
                          disabled={busy != null}
                          onClick={() => void handleDeleteAccount(r.user_id, r.name)}
                          title={lang === 'zh' ? '物理删除/封禁' : 'Delete/Ban Account'}
                        >
                          Ban
                        </button>
                      </div>
                    </td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>

      <button className="gm__refresh" onClick={() => void load()} style={{ marginTop: '20px' }}>
        {t('gm.refresh')}
      </button>
    </section>
  )
}
