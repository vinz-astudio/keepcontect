import { useCallback, useEffect, useState } from 'react'
import {
  getGroupActivity,
  setShareActivity,
  type ActivityStatus,
  type GroupActivity,
  type GroupActivityView,
} from '@/features/relationships/groupActivity'
import { translate, useI18n } from '@/lib/i18n'
import { subscribeGroupStatusSignals } from '@/features/alerts/realtime'
import { formatGroupActivityStatus } from '@/features/relationships/groupActivityDisplay'
import { useUiMode } from '@/lib/uiMode'
import './GroupBoard.css'

const DOT: Record<ActivityStatus, string> = {
  self: 'board__dot--self',
  active: 'board__dot--active',
  quiet: 'board__dot--quiet',
  silent: 'board__dot--silent',
  alert: 'board__dot--silent',
  unknown: 'board__dot--unknown',
  hidden: 'board__dot--unknown',
}

export function GroupBoard({
  groupId,
  mode = 'group',
  initialData = null,
}: {
  groupId: string
  mode?: GroupActivityView
  initialData?: GroupActivity | null
}) {
  const { t, lang } = useI18n()
  const [uiMode] = useUiMode()
  const [data, setData] = useState<GroupActivity | null>(initialData)
  const [loading, setLoading] = useState(!initialData)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      setData(await getGroupActivity(groupId, mode))
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    } finally {
      setLoading(false)
    }
  }, [groupId, mode])

  useEffect(() => {
    setData(initialData)
    setLoading(!initialData)
  }, [groupId, mode, initialData])

  useEffect(() => {
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
    void subscribeGroupStatusSignals(scheduleLoad).then((fn) => {
      unsubscribe = fn
    })
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      unsubscribe?.()
    }
  }, [load])

  async function run(fn: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await fn()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    } finally {
      setBusy(false)
    }
  }

  if (loading) return <p className="muted board__loading">{t('home.loading')}</p>
  if (error) return <p className="home__error">{error}</p>
  if (!data) return null
  const others = data.members.filter((m) => !m.is_me)
  const hiddenOthers = others.filter((m) => m.status === 'hidden').length

  return (
    <div className={uiMode === 'v2' ? 'board board--flush' : 'board'}>
      {data.members.length <= 1 ? (
        <p className="muted board__empty">{t(mode === 'watch' ? 'board.emptyWatch' : 'board.emptyMembers')}</p>
      ) : uiMode === 'v2' ? (
        /* V2 空间模式：独立高亮暖白人头卡片列表 */
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', width: '100%', marginTop: '4px' }}>
          {data.members.map((m) => {
            const status = m.status
            return (
              <div key={m.user_id} className="person-card-v2">
                <div className="person-card-v2__header">
                  <div className="person-card-v2__name">
                    <span>{m.name}</span>
                    {m.is_me && (
                      <span className="person-card-v2__badge" style={{ background: 'var(--bg-soft)', color: 'var(--fg-muted)' }}>
                        {lang === 'zh' ? '我自己' : 'Me'}
                      </span>
                    )}
                  </div>
                  <span className={`board__dot ${DOT[status]}`} title={status} />
                </div>
                <div className="person-card-v2__status">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <circle cx="12" cy="12" r="10" />
                    <path d="M12 6v6l4 2" />
                  </svg>
                  <span>{formatGroupActivityStatus(status, m.hours, lang)}</span>
                </div>
              </div>
            )
          })}
        </div>
      ) : (
        /* 0.5.24 经典模式：紧凑点状列表 */
        <ul className="board__list">
          {data.members.map((m) => {
            const status = m.status
            return (
              <li key={m.user_id} className="board__row">
                <span className={`board__dot ${DOT[status]}`} aria-hidden />
                <span className="board__name">{m.name}</span>
                <span className="board__status">{formatGroupActivityStatus(status, m.hours, lang)}</span>
              </li>
            )
          })}
        </ul>
      )}


      {hiddenOthers > 0 && (
        <p className="muted board__empty">
          {t('board.hiddenNote', { n: hiddenOthers })}
        </p>
      )}

      {/* æœ¬äºº opt-inï¼šä¸å¼€å¯åˆ™åˆ«äººçœ‹ä¸åˆ°ä½  */}
      <label className="board__toggle">
        <input
          type="checkbox"
          checked={data.i_share}
          disabled={busy}
          onChange={(e) => run(() => setShareActivity(e.target.checked))}
        />
        {t('board.share')}
      </label>

      <p className="muted board__hint">
        {t(mode === 'watch' ? 'board.hint.watchView' : 'board.hint.groupView')}
      </p>
    </div>
  )
}
