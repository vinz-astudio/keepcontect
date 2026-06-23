import { useCallback, useEffect, useState } from 'react'
import {
  getGroupActivity,
  setGroupVisibility,
  setShareActivity,
  type ActivityStatus,
  type GroupActivity,
} from '@/features/relationships/groupActivity'
import { translate, useI18n } from '@/lib/i18n'
import './GroupBoard.css'

const DOT: Record<ActivityStatus, string> = {
  self: 'board__dot--self',
  active: 'board__dot--active',
  quiet: 'board__dot--quiet',
  silent: 'board__dot--silent',
  unknown: 'board__dot--unknown',
  hidden: 'board__dot--unknown',
}

function statusText(status: ActivityStatus, hours: number | null): string {
  switch (status) {
    case 'self':
      return translate('board.you')
    case 'active':
      return translate('board.active')
    case 'quiet':
      return translate('board.quiet', { h: hours ?? 0 })
    case 'silent':
      return translate('board.silent', { d: Math.max(1, Math.floor((hours ?? 24) / 24)) })
    case 'unknown':
      return translate('board.unknown')
    case 'hidden':
    default:
      return translate('board.hidden')
  }
}

export function GroupBoard({ groupId }: { groupId: string }) {
  const { t } = useI18n()
  const [data, setData] = useState<GroupActivity | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      setData(await getGroupActivity(groupId))
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    } finally {
      setLoading(false)
    }
  }, [groupId])

  useEffect(() => {
    void load()
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
    <div className="board">
      {data.members.length <= 1 ? (
        <p className="muted board__empty">{t('board.emptyMembers')}</p>
      ) : (
        <ul className="board__list">
          {data.members.map((m) => {
            const status = m.alerted ? 'silent' : m.status
            return (
              <li key={m.user_id} className="board__row">
                <span className={`board__dot ${DOT[status]}`} aria-hidden />
                <span className="board__name">{m.name}</span>
                <span className="board__status">{statusText(status, m.hours)}</span>
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

      {/* 本人 opt-in：不开启则别人看不到你 */}
      <label className="board__toggle">
        <input
          type="checkbox"
          checked={data.i_share}
          disabled={busy}
          onChange={(e) => run(() => setShareActivity(e.target.checked))}
        />
        {t('board.share')}
      </label>

      {/* 组主可切换本组可见范围 */}
      {data.is_owner && (
        <div className="board__vis">
          <span className="board__vislabel">{t('board.vis.label')}</span>
          <div className="board__visseg">
            {(['watchers_only', 'group_wide'] as const).map((v) => (
              <button
                key={v}
                className={data.visibility === v ? 'active' : ''}
                disabled={busy}
                onClick={() => run(() => setGroupVisibility(groupId, v))}
              >
                {t(v === 'watchers_only' ? 'board.vis.watchers' : 'board.vis.all')}
              </button>
            ))}
          </div>
        </div>
      )}

      <p className="muted board__hint">
        {data.visibility === 'watchers_only'
          ? t('board.hint.watchers')
          : t('board.hint.all')}
      </p>
    </div>
  )
}
