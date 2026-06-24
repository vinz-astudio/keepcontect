import { useCallback, useEffect, useState } from 'react'
import {
  gmListClients,
  gmNudgeUpdate,
  gmSendConcern,
  gmDeleteAccount,
  type GmClient,
} from '@/features/gm/gmApi'
import { translate, useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import { Icon } from '@/features/common/Icon'
import { isNewer } from '@/features/update/versionCheck'
import { APP_VERSION } from '@/lib/version'
import './GMScreen.css'

interface UserRow {
  user_id: string
  name: string
  clients: GmClient[]
  /** 真实存活信号(device_state),与群组看板同源 */
  last_heartbeat_at: string | null
  /** 是否有 group+ open 告警 */
  alerted: boolean
  /** 统一活跃状态 */
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

  const load = useCallback(async () => {
    setError(null)
    try {
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
            alerted: false,
            status: 'never',
          }
        if (c.platform || c.app_version) r.clients.push(c)
        
        const hb = c.last_heartbeat_at || c.last_seen_at
        if (
          hb &&
          (!r.last_heartbeat_at || hb > r.last_heartbeat_at)
        ) {
          r.last_heartbeat_at = hb
        }
        
        if (c.alerted) r.alerted = true
        map.set(c.user_id, r)
      }

      // Compute unified status for each user
      for (const r of map.values()) {
        if (r.alerted) {
          r.status = 'alert'
        } else {
          const ts = r.last_heartbeat_at ? new Date(r.last_heartbeat_at).getTime() : null
          if (!ts) {
            r.status = 'never'
          } else {
            const diffH = (Date.now() - ts) / 3_600_000
            if (diffH < 6) {
              r.status = 'active'
            } else if (diffH < 24) {
              r.status = 'quiet'
            } else {
              r.status = 'silent'
            }
          }
        }
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
    return () => window.clearInterval(timer)
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
    const outdatedUsers = sorted.filter((r) =>
      r.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
    )

    if (!outdatedUsers.length) {
      toast(lang === 'zh' ? '当前列表下没有未升级的用户' : 'No outdated users found in this list', 'info')
      return
    }

    const confirmMsg = lang === 'zh'
      ? `确认要一键发送升级通知给这 ${outdatedUsers.length} 位用户吗？`
      : `Send update nudges to all ${outdatedUsers.length} outdated users?`
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

  // 1. Filter
  const filtered = rows.filter((r) => {
    const matchSearch =
      r.name.toLowerCase().includes(search.toLowerCase()) ||
      r.user_id.toLowerCase().includes(search.toLowerCase())
    
    if (!matchSearch) return false

    const hasOutdatedClient = r.clients.length === 0 || r.clients.some((c) => {
      return c.app_version ? isNewer(APP_VERSION, c.app_version) : true
    })

    if (onlyOutdated && !hasOutdatedClient) return false

    return true
  })

  // 2. Sort
  const sorted = [...filtered].sort((a, b) => {
    if (sortBy === 'name') {
      return a.name.localeCompare(b.name)
    }
    if (sortBy === 'seen') {
      const at = (r: UserRow) =>
        r.last_heartbeat_at
          ? new Date(r.last_heartbeat_at).getTime()
          : latestSeen(r.clients)
      return at(b) - at(a)
    }
    if (sortBy === 'version') {
      const aOutdated = a.clients.length === 0 || a.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
      const bOutdated = b.clients.length === 0 || b.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
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
              <th>{lang === 'zh' ? '设备与版本' : 'Devices & Versions'}</th>
              <th style={{ width: '320px', textAlign: 'right' }}>{lang === 'zh' ? '操作' : 'Actions'}</th>
            </tr>
          </thead>
          <tbody>
            {sorted.length === 0 ? (
              <tr>
                <td colSpan={5} className="gm__table-empty">
                  {lang === 'zh' ? '无匹配数据' : 'No records found'}
                </td>
              </tr>
            ) : (
              sorted.map((r) => {
                const status = r.status
                const isOutdated = r.clients.length === 0 || r.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
                return (
                  <tr key={r.user_id} className={isOutdated ? 'is-outdated-row' : ''}>
                    <td style={{ textAlign: 'center' }}>
                      <span
                        className={`gm__status-dot is-${status}`}
                        title={
                          status === 'alert' ? (lang === 'zh' ? '异常告警 · 需关注' : 'Alert · needs attention') :
                          status === 'active' ? (lang === 'zh' ? '近期活跃 (<6小时)' : 'Active (<6h)') :
                          status === 'quiet' ? (lang === 'zh' ? '安静 (<24小时)' : 'Quiet (<24h)') :
                          status === 'silent' ? (lang === 'zh' ? '长时间未活跃 (>24小时)' : 'Silent (>24h)') :
                          (lang === 'zh' ? '暂无数据' : 'No data')
                        }
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
