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
}

const PLAT_MAP: Record<string, string> = {
  ios: 'iOS',
  android: 'Android',
  windows: 'Win',
  tauri: 'Win',
  mac: 'Mac',
  linux: 'Linux',
}

function formatDevices(clients: GmClient[], lang: string): string {
  if (!clients.length) {
    return lang === 'zh' ? '未上报版本' : 'No version reported'
  }
  let mobileCount = 0
  let desktopCount = 0
  const parts = clients.map((c) => {
    const platLower = (c.platform ?? '').toLowerCase()
    const isMobile = platLower === 'ios' || platLower === 'android'
    let prefix = ''
    if (isMobile) {
      mobileCount++
      const char = String.fromCharCode(64 + mobileCount)
      prefix = `Mobile ${char}`
    } else {
      desktopCount++
      const char = String.fromCharCode(64 + desktopCount)
      prefix = `Desktop ${char}`
    }
    const plat = PLAT_MAP[platLower] || c.platform || '?'
    const ver = c.app_version ? `v${c.app_version}` : '?'
    return `${prefix}: ${plat} ${ver}`
  })
  return parts.join(' | ')
}

function renderDevicesList(clients: GmClient[], lang: string) {
  if (!clients.length) {
    return <span className="gm__device-empty" style={{ opacity: 0.5 }}>{lang === 'zh' ? '未上报版本' : 'No version reported'}</span>
  }
  let mobileCount = 0
  let desktopCount = 0
  return clients.map((c, i) => {
    const platLower = (c.platform ?? '').toLowerCase()
    const isMobile = platLower === 'ios' || platLower === 'android'
    let prefix = ''
    if (isMobile) {
      mobileCount++
      const char = String.fromCharCode(64 + mobileCount)
      prefix = `Mobile ${char}`
    } else {
      desktopCount++
      const char = String.fromCharCode(64 + desktopCount)
      prefix = `Desktop ${char}`
    }
    const plat = PLAT_MAP[platLower] || c.platform || '?'
    const ver = c.app_version ? `v${c.app_version}` : '?'
    return (
      <div key={i} className="gm__device-line" style={{ display: 'block', whiteSpace: 'nowrap' }}>
        {prefix}: {plat} {ver}
      </div>
    )
  })
}

function getStatus(clients: GmClient[]) {
  if (!clients.length || !clients[0].last_seen_at) return 'never'
  const lastSeen = new Date(clients[0].last_seen_at).getTime()
  const diffHours = (Date.now() - lastSeen) / 3600000
  if (diffHours < 2) return 'active'
  if (diffHours < 24) return 'quiet'
  return 'silent'
}

export function GMScreen() {
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
          map.get(c.user_id) ?? { user_id: c.user_id, name: c.name, clients: [] }
        if (c.platform || c.app_version) r.clients.push(c)
        map.set(c.user_id, r)
      }
      setRows([...map.values()])
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

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
      const aTime = a.clients[0]?.last_seen_at ? new Date(a.clients[0].last_seen_at).getTime() : 0
      const bTime = b.clients[0]?.last_seen_at ? new Date(b.clients[0].last_seen_at).getTime() : 0
      return bTime - aTime
    }
    if (sortBy === 'version') {
      const aOutdated = a.clients.length === 0 || a.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
      const bOutdated = b.clients.length === 0 || b.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
      return (bOutdated ? 1 : 0) - (aOutdated ? 1 : 0)
    }
    return 0
  })

  return (
    <section className="card gm-panel">
      <h2 className="card__title">
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
                const status = getStatus(r.clients)
                const isOutdated = r.clients.length === 0 || r.clients.some((c) => c.app_version ? isNewer(APP_VERSION, c.app_version) : true)
                return (
                  <tr key={r.user_id} className={isOutdated ? 'is-outdated-row' : ''}>
                    <td style={{ textAlign: 'center' }}>
                      <span
                        className={`gm__status-dot is-${status}`}
                        title={
                          status === 'active' ? (lang === 'zh' ? '近期活跃 (<2小时)' : 'Active (<2h)') :
                          status === 'quiet' ? (lang === 'zh' ? '离线 (<24小时)' : 'Quiet (<24h)') :
                          status === 'silent' ? (lang === 'zh' ? '长时间未活跃 (>24小时)' : 'Silent (>24h)') :
                          (lang === 'zh' ? '从未活跃' : 'Never seen')
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
