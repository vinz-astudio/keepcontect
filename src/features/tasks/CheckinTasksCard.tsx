import { useCallback, useEffect, useState } from 'react'
import {
  listMyTasks,
  respondTask,
  revokeTask,
  utcTimeToLocal,
  type CheckinTask,
} from '@/features/tasks/api'
import { getProfileName } from '@/features/alerts/api'
import { translate, useI18n } from '@/lib/i18n'

export function CheckinTasksCard() {
  const { t } = useI18n()
  const [tasks, setTasks] = useState<CheckinTask[]>([])
  const [names, setNames] = useState<Map<string, string>>(new Map())
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    setError(null)
    try {
      const list = await listMyTasks()
      setTasks(list)
      const otherIds = [
        ...new Set(
          list.filter((x) => x.created_by !== x.ward_id).map((x) => x.created_by),
        ),
      ]
      const m = new Map<string, string>()
      for (const id of otherIds) {
        m.set(id, (await getProfileName(id)) ?? translate('notif.someone'))
      }
      setNames(m)
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  async function run(fn: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await fn()
      await refresh()
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.op'))
    } finally {
      setBusy(false)
    }
  }

  function ruleText(x: CheckinTask): string {
    return x.kind === 'daily' && x.due_time_utc
      ? t('tasks.daily', { time: utcTimeToLocal(x.due_time_utc) })
      : t('tasks.interval', { h: x.interval_hours ?? 0 })
  }

  // 自设晨间打卡已废弃（被"关闹钟自动 ping"取代）。此卡只在守护人给你设了任务时出现。
  if (!loading && tasks.length === 0) return null

  return (
    <section className="card">
      <h2 className="card__title">{t('tasks.title')}</h2>
      <p className="muted">{t('tasks.desc')}</p>

      {error && <p className="home__error">{error}</p>}

      {loading ? (
        <p className="muted">{t('home.loading')}</p>
      ) : (
        <ul className="list">
          {tasks.map((x) => {
            const mine = x.created_by === x.ward_id
            return (
              <li key={x.id} className="list__item list__item--group">
                <div className="list__row1">
                  <span>
                    {x.label || t('tasks.morning.label')} · {ruleText(x)}
                  </span>
                  <span className="role">
                    {mine
                      ? t('tasks.byMe')
                      : t('tasks.byOther', {
                          name: names.get(x.created_by) ?? '',
                        })}
                  </span>
                </div>
                <div className="list__row2">
                  {x.status === 'pending' ? (
                    <>
                      <span className="muted">{t('tasks.pending')}</span>
                      <button
                        className="share"
                        disabled={busy}
                        onClick={() => run(() => respondTask(x, true))}
                      >
                        {t('tasks.accept')}
                      </button>
                      <button
                        className="leave"
                        disabled={busy}
                        onClick={() => run(() => respondTask(x, false))}
                      >
                        {t('tasks.decline')}
                      </button>
                    </>
                  ) : (
                    <button
                      className="leave"
                      style={{ marginLeft: 'auto' }}
                      disabled={busy}
                      onClick={() => run(() => revokeTask(x.id))}
                    >
                      {t('tasks.remove')}
                    </button>
                  )}
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </section>
  )
}
