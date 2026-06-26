import { useCallback, useEffect, useState } from 'react'
import {
  listMyCommunities,
  listMyGroups,
  type Community,
} from '@/features/relationships/api'
import {
  getGroupActivity,
  sendConcern,
  type GroupActivity,
} from '@/features/relationships/groupActivity'
import { GroupBoard } from '@/features/relationships/GroupBoard'
import { onAlertChange } from '@/features/alerts/alertBus'
import { subscribeAlertSignals } from '@/features/alerts/realtime'
import { translate, useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import './GroupBoard.css'
import './StatusBoard.css'

interface GData {
  id: string
  name: string
  communityId: string | null
  act: GroupActivity | null
  activityError: string | null
}

export function StatusBoard() {
  const { t } = useI18n()
  const [groups, setGroups] = useState<GData[]>([])
  const [communities, setCommunities] = useState<Community[]>([])
  const [open, setOpen] = useState<Set<string>>(new Set())
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [sentTo, setSentTo] = useState<Set<string>>(new Set())

  const load = useCallback(async () => {
    setError(null)
    try {
      const [comms, gs] = await Promise.all([
        listMyCommunities(),
        listMyGroups(),
      ])
      setCommunities(comms)
      const built = await Promise.all(
        gs.map(async ({ group }) => {
          try {
            return {
              id: group.id,
              name: group.name,
              communityId: group.community_id,
              act: await getGroupActivity(group.id, 'watch'),
              activityError: null,
            }
          } catch (e) {
            return {
              id: group.id,
              name: group.name,
              communityId: group.community_id,
              act: null,
              activityError: e instanceof Error ? e.message : translate('err.load'),
            }
          }
        }),
      )
      setGroups(built)
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
    const timer = window.setInterval(() => void load(), 60_000)
    const onVisible = () => {
      if (document.visibilityState === 'visible') void load()
    }
    document.addEventListener('visibilitychange', onVisible)
    // 本机任一界面「确认安全/报平安」后立即刷新看板（联动）
    const offBus = onAlertChange(() => void load())
    // 其它设备/成员的告警变更经 realtime 通知后也刷新
    let unsubscribe: (() => void) | undefined
    void subscribeAlertSignals(() => void load()).then((fn) => {
      unsubscribe = fn
    })
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      offBus()
      unsubscribe?.()
    }
  }, [load])

  function toggle(key: string) {
    setOpen((s) => {
      const n = new Set(s)
      if (n.has(key)) n.delete(key)
      else n.add(key)
      return n
    })
  }

  async function concern(uid: string) {
    setBusy(uid)
    setError(null)
    try {
      await sendConcern(uid)
      setSentTo((s) => new Set(s).add(uid))
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.op'))
    } finally {
      setBusy(null)
    }
  }

  const groupAlerted = (g: GData) =>
    g.act?.members.some((m) => m.alerted) ?? false

  const attention: { uid: string; name: string; groupName: string }[] = []
  const seen = new Set<string>()
  for (const g of groups) {
    for (const m of g.act?.members ?? []) {
      if (m.alerted && !seen.has(m.user_id)) {
        seen.add(m.user_id)
        attention.push({ uid: m.user_id, name: m.name, groupName: g.name })
      }
    }
  }

  function renderGroup(g: GData, topLevel = false) {
    const key = 'g:' + g.id
    const alerted = groupAlerted(g)
    const expanded = open.has(key) || alerted
    return (
      <li key={key} className={topLevel ? 'status__top' : ''}>
        <button className="status__node" onClick={() => toggle(key)}>
          <span className={`status__light ${alerted ? 'is-alert' : 'is-ok'}`} />
          <span className="status__nodename">{g.name}</span>
          <span className="status__chev">{expanded ? 'v' : '>'}</span>
        </button>
        {!expanded && g.activityError && (
          <p className="status__loaderr">{g.activityError}</p>
        )}
        {expanded && <GroupBoard groupId={g.id} mode="watch" />}
      </li>
    )
  }

  const standalone = groups.filter((g) => !g.communityId)
  const commsShown = communities.filter((c) =>
    groups.some((g) => g.communityId === c.id),
  )

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="group" />
        {t('status.title')}
      </h2>
      {error && <p className="home__error">{error}</p>}

      {loading ? (
        <p className="muted">{t('home.loading')}</p>
      ) : groups.length === 0 ? (
        <p className="muted">{t('status.empty')}</p>
      ) : (
        <>
          {attention.length > 0 && (
            <div className="status__attention">
              {attention.map((a) => (
                <div key={a.uid} className="status__alert">
                  <div className="status__alertinfo">
                    <span className="status__warn" aria-hidden>
                      !
                    </span>
                    <span className="status__alertname">{a.name}</span>
                    <span className="status__alertdesc">
                      {t('status.silentIn', { group: a.groupName })}
                    </span>
                  </div>
                  {sentTo.has(a.uid) ? (
                    <span className="status__sent">{t('status.sent')}</span>
                  ) : (
                    <button
                      className="status__concern"
                      disabled={busy === a.uid}
                      onClick={() => void concern(a.uid)}
                    >
                      {t('status.concern')}
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}

          <ul className="status__tree">
            {commsShown.map((c) => {
              const key = 'c:' + c.id
              const childGroups = groups.filter((g) => g.communityId === c.id)
              const alerted = childGroups.some(groupAlerted)
              const expanded = open.has(key) || alerted
              return (
                <li key={key}>
                  <button className="status__node" onClick={() => toggle(key)}>
                    <span
                      className={`status__light ${alerted ? 'is-alert' : 'is-ok'}`}
                    />
                    <span className="status__nodename">{c.name}</span>
                    <span className="status__chev">{expanded ? 'v' : '>'}</span>
                  </button>
                  {expanded && (
                    <ul className="status__children">
                      {childGroups.map((g) => renderGroup(g))}
                    </ul>
                  )}
                </li>
              )
            })}
            {standalone.map((g) => renderGroup(g, true))}
          </ul>
        </>
      )}
    </section>
  )
}