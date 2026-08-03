import { useCallback, useEffect, useState } from 'react'
import {
  getGroupActivity,
  setShareActivity,
  type ActivityStatus,
  type GroupActivity,
  type GroupActivityView,
} from '@/features/relationships/groupActivity'
import { removeGroupMember } from '@/features/relationships/api'
import { translate, useI18n } from '@/lib/i18n'
import { subscribeGroupStatusSignals } from '@/features/alerts/realtime'
import { formatGroupActivityStatus } from '@/features/relationships/groupActivityDisplay'
import { PrototypeIcon } from '@/features/prototype/PrototypeUI'
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
  isAdmin = false,
}: {
  groupId: string
  mode?: GroupActivityView
  initialData?: GroupActivity | null
  isAdmin?: boolean
}) {
  const { t, lang } = useI18n()
  const [data, setData] = useState<GroupActivity | null>(initialData)
  const [loading, setLoading] = useState(!initialData)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      setData(await getGroupActivity(groupId, mode))
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : translate('err.load'))
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
    void subscribeGroupStatusSignals(scheduleLoad).then((stop) => {
      unsubscribe = stop
    })
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      unsubscribe?.()
    }
  }, [load])

  async function run(operation: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await operation()
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : translate('err.load'))
    } finally {
      setBusy(false)
    }
  }

  if (loading) return <p className="muted board__loading">{t('home.loading')}</p>
  if (error) return <p className="home__error">{error}</p>
  if (!data) return null

  const others = data.members.filter((member) => !member.is_me)
  const hiddenOthers = others.filter((member) => member.status === 'hidden').length

  return (
    <div className="board board--flush">
      {data.members.length <= 1 ? (
        <p className="muted board__empty">
          {t(mode === 'watch' ? 'board.emptyWatch' : 'board.emptyMembers')}
        </p>
      ) : (
        <div className="board__people">
          {data.members.map((member) => (
            <div key={member.user_id} className="person-card-v2">
              <div className="person-card-v2__header">
                <div className="person-card-v2__name">
                  <span>{member.name}</span>
                  {member.is_me && (
                    <span className="person-card-v2__badge">
                      {lang === 'zh' ? '我自己' : 'Me'}
                    </span>
                  )}
                </div>
                <span className={`board__dot ${DOT[member.status]}`} title={member.status} />
              </div>

              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 8,
                }}
              >
                <div className="person-card-v2__status">
                  <PrototypeIcon name="schedule" />
                  <span>{formatGroupActivityStatus(member.status, member.hours, lang)}</span>
                </div>

                {isAdmin && !member.is_me && (
                  <button
                    type="button"
                    className="prototype-button home-prototype__danger"
                    style={{ minHeight: 28, padding: '0 10px', fontSize: '0.74rem' }}
                    disabled={busy}
                    onClick={() => {
                      if (
                        window.confirm(
                          lang === 'zh'
                            ? `确定要将成员 ${member.name} 移出本圈子吗？`
                            : `Remove ${member.name} from group?`
                        )
                      ) {
                        void run(() => removeGroupMember(groupId, member.user_id))
                      }
                    }}
                  >
                    {lang === 'zh' ? '移出群组' : 'Remove Member'}
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
      {hiddenOthers > 0 && (
        <p className="muted board__empty">{t('board.hiddenNote', { n: hiddenOthers })}</p>
      )}
      <label className="board__toggle">
        <input
          type="checkbox"
          checked={data.i_share}
          disabled={busy}
          onChange={(event) => void run(() => setShareActivity(event.target.checked))}
        />
        {t('board.share')}
      </label>
      <p className="muted board__hint">
        {t(mode === 'watch' ? 'board.hint.watchView' : 'board.hint.groupView')}
      </p>
    </div>
  )
}
