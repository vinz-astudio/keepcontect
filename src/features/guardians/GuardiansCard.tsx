import { useCallback, useEffect, useState } from 'react'
import {
  becomeGuardianByCode,
  getMyGuardianCode,
  listGuardianships,
  revokeGuardianship,
  type GuardianLink,
} from '@/features/guardians/api'
import { buildInviteUrl, shareInvite } from '@/features/invites/inviteLink'
import {
  createTaskForWard,
  listTasksISet,
  revokeTask,
  updateTaskForWard,
  utcTimeToLocal,
  type CheckinTask,
} from '@/features/tasks/api'
import { useAuth } from '@/features/auth/AuthProvider'
import { translate, useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import { ScanSyncModal } from '@/features/auth/ScanSyncModal'
import { QRModal } from '@/features/relationships/QRModal'
import { toast } from '@/lib/toast'

export function GuardiansCard() {
  const { t } = useI18n()
  const { user } = useAuth()
  const displayName =
    (user?.user_metadata?.display_name as string | undefined) ??
    user?.email ??
    '我'
  const [myCode, setMyCode] = useState<string>('')
  const [links, setLinks] = useState<GuardianLink[]>([])
  const [tasksISet, setTasksISet] = useState<CheckinTask[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [isScanning, setIsScanning] = useState(false)
  const [showQR, setShowQR] = useState(false)
  // 给 ward 设任务的内联表单(同一时刻只展开一个 ward 的)
  const [formWard, setFormWard] = useState<string | null>(null)
  const [formMode, setFormMode] = useState<'daily' | 'interval'>('daily')
  const [formTime, setFormTime] = useState('09:00')
  const [formHours, setFormHours] = useState(3)
  const [editingTask, setEditingTask] = useState<string | null>(null)

  function openCreate(wardId: string) {
    setEditingTask(null)
    setFormMode('daily')
    setFormTime('09:00')
    setFormHours(3)
    setFormWard(formWard === wardId && !editingTask ? null : wardId)
  }

  function openEdit(x: CheckinTask) {
    setEditingTask(x.id)
    setFormWard(x.ward_id)
    if (x.kind === 'daily' && x.due_time_utc) {
      setFormMode('daily')
      setFormTime(utcTimeToLocal(x.due_time_utc))
    } else {
      setFormMode('interval')
      setFormHours(x.interval_hours ?? 3)
    }
  }

  const refresh = useCallback(async () => {
    setError(null)
    try {
      const [c, l, ts] = await Promise.all([
        getMyGuardianCode(),
        listGuardianships(),
        listTasksISet(),
      ])
      setMyCode(c)
      setLinks(l)
      setTasksISet(ts)
    } catch (e) {
      setError(e instanceof Error ? e.message : '加载失败')
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
      setError(e instanceof Error ? e.message : '操作失败')
    } finally {
      setBusy(false)
    }
  }

  const wards = links.filter((l) => l.direction === 'i_guard')
  const guardians = links.filter((l) => l.direction === 'guards_me')

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="shield" />
        {t('guard.title')}
      </h2>
      <p className="muted">{t('guard.desc')}</p>

      {loading ? (
        <p className="muted">{t('home.loading')}</p>
      ) : (
        <>
          {/* Share invite + QR */}
          <div className="row">
            <button
              className="share"
              style={{ flex: 1 }}
              onClick={() =>
                void shareInvite('guardian', myCode, displayName).then((r) => {
                  if (r.status === 'copied') setNotice(t('guard.copied'))
                  else if (r.status === 'manual')
                    setNotice(t('guard.manual', { url: r.url }))
                })
              }
            >
              {t('guard.invite')}
            </button>
            <button
              className="share"
              title={t('qr.show')}
              onClick={() => setShowQR(true)}
              style={{ display: 'flex', alignItems: 'center', gap: '4px' }}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <rect x="3" y="3" width="7" height="7"/>
                <rect x="14" y="3" width="7" height="7"/>
                <rect x="3" y="14" width="7" height="7"/>
                <rect x="14" y="14" width="3" height="3"/>
                <rect x="19" y="14" width="2" height="2"/>
                <rect x="14" y="19" width="2" height="2"/>
                <rect x="19" y="19" width="2" height="2"/>
              </svg>
              {t('qr.show')}
            </button>
          </div>

          {/* Scan to become a guardian */}
          <button
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '10px 14px',
              background: 'var(--bg)',
              border: '1px solid var(--line)',
              borderRadius: 'var(--r-md)',
              cursor: 'pointer',
              color: 'var(--fg)',
              transition: 'all 0.2s ease',
              marginTop: '0.25rem',
            }}
            onClick={() => setIsScanning(true)}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ color: 'var(--accent)' }}>
                <path d="M3 7V5a2 2 0 0 1 2-2h2m10 0h2a2 2 0 0 1 2 2v2m0 10v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2" />
                <path d="M7 12h10M12 7v10" />
              </svg>
              <span style={{ fontWeight: '600', fontSize: '0.88rem' }}>
                {t('guard.scanToBecome')}
              </span>
            </div>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" style={{ opacity: 0.5 }}>
              <path d="M9 18l6-6-6-6" />
            </svg>
          </button>

          {error && <p className="home__error">{error}</p>}
          {notice && <p className="ei__saved">{notice}</p>}

          {guardians.length > 0 && (
            <>
              <p className="muted" style={{ marginTop: '0.75rem' }}>
                {t('guard.guardsMe')}
              </p>
              <ul className="list">
                {guardians.map((l) => (
                  <li key={l.id} className="list__item">
                    <span>{l.otherName ?? l.otherUserId.slice(0, 8)}</span>
                    <button
                      className="leave"
                      disabled={busy}
                      onClick={() => run(() => revokeGuardianship(l.id))}
                    >
                      {t('guard.revoke')}
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}

          {wards.length > 0 && (
            <>
              <p className="muted" style={{ marginTop: '0.75rem' }}>
                {t('guard.iGuard')}
              </p>
              <ul className="list">
                {wards.map((l) => {
                  const wardTasks = tasksISet.filter(
                    (x) => x.ward_id === l.otherUserId,
                  )
                  const open = formWard === l.otherUserId
                  return (
                    <li key={l.id} className="list__item list__item--group">
                      <div className="list__row1">
                        <span>{l.otherName ?? l.otherUserId.slice(0, 8)}</span>
                        <div style={{ display: 'flex', gap: '0.4rem', flexWrap: 'wrap' }}>
                          <button
                            className="share"
                            disabled={busy}
                            onClick={() => openCreate(l.otherUserId)}
                          >
                            {t('tasks.set.title')}
                          </button>
                          <button
                            className="leave"
                            disabled={busy}
                            onClick={() => run(() => revokeGuardianship(l.id))}
                          >
                            {t('guard.quit')}
                          </button>
                        </div>
                      </div>

                      {/* 我给这位设过的任务 + 对方接受状态(知情) + 编辑/取消 */}
                      {wardTasks.length > 0 && (
                        <ul className="tasklist">
                          {wardTasks.map((x) => (
                            <li key={x.id} className="tasklist__item">
                              <span className="muted">
                                {x.kind === 'daily' && x.due_time_utc
                                  ? t('tasks.daily', {
                                      time: utcTimeToLocal(x.due_time_utc),
                                    })
                                  : t('tasks.interval', {
                                      h: x.interval_hours ?? 0,
                                    })}
                                {' — '}
                                {t(
                                  x.status === 'pending'
                                    ? 'tasks.status.pending'
                                    : x.status === 'active'
                                      ? 'tasks.status.active'
                                      : 'tasks.status.declined',
                                )}
                              </span>
                              <div className="tasklist__btns">
                                {x.status !== 'declined' && (
                                  <button
                                    className="tasklist__edit"
                                    disabled={busy}
                                    onClick={() => openEdit(x)}
                                  >
                                    {t('tasks.edit')}
                                  </button>
                                )}
                                <button
                                  className="tasklist__cancel"
                                  disabled={busy}
                                  onClick={() => run(() => revokeTask(x.id))}
                                >
                                  {t('tasks.cancel')}
                                </button>
                              </div>
                            </li>
                          ))}
                        </ul>
                      )}

                      {open && (
                        <>
                          <div className="row">
                            <select
                              value={formMode}
                              onChange={(e) =>
                                setFormMode(e.target.value as 'daily' | 'interval')
                              }
                            >
                              <option value="daily">{t('tasks.set.daily')}</option>
                              <option value="interval">
                                {t('tasks.set.interval')}
                              </option>
                            </select>
                            {formMode === 'daily' ? (
                              <input
                                type="time"
                                value={formTime}
                                onChange={(e) => setFormTime(e.target.value)}
                              />
                            ) : (
                              <input
                                type="number"
                                min={2}
                                max={24}
                                value={formHours}
                                onChange={(e) =>
                                  setFormHours(Number(e.target.value))
                                }
                              />
                            )}
                            <button
                              disabled={busy}
                              onClick={() =>
                                run(async () => {
                                  const opts =
                                    formMode === 'daily'
                                      ? ({
                                          kind: 'daily',
                                          localHHMM: formTime,
                                          label: translate('tasks.morning.label'),
                                        } as const)
                                      : ({
                                          kind: 'interval',
                                          hours: Math.max(2, formHours),
                                          label: '',
                                        } as const)
                                  if (editingTask) {
                                    await updateTaskForWard(editingTask, opts)
                                  } else {
                                    await createTaskForWard(l.otherUserId, opts)
                                  }
                                  setFormWard(null)
                                  setEditingTask(null)
                                })
                              }
                            >
                              {editingTask
                                ? t('tasks.set.save')
                                : t('tasks.set.create')}
                            </button>
                            {editingTask && (
                              <button
                                className="leave"
                                disabled={busy}
                                onClick={() => {
                                  setFormWard(null)
                                  setEditingTask(null)
                                }}
                              >
                                {t('tasks.set.cancelEdit')}
                              </button>
                            )}
                          </div>
                          <p className="muted">{t('tasks.set.note')}</p>
                        </>
                      )}
                    </li>
                  )
                })}
              </ul>
            </>
          )}
        </>
      )}

      {isScanning && (
        <ScanSyncModal
          onClose={() => setIsScanning(false)}
          onScan={async (data) => {
            setIsScanning(false)
            // Parse invite link from QR
            let code = data
            try {
              const url = new URL(data)
              const raw = url.searchParams.get('invite')
              if (raw) {
                const dot = raw.indexOf('.')
                const kind = raw.slice(0, dot)
                const c = decodeURIComponent(raw.slice(dot + 1))
                if (kind === 'guardian' && c) code = c
                else {
                  toast(t('invite.invalid'), 'danger')
                  return
                }
              }
            } catch {
              // not a URL, use raw
            }
            run(async () => {
              await becomeGuardianByCode(code)
              setNotice(t('invite.joined.guardian'))
            })
          }}
        />
      )}
      {showQR && myCode && (
        <QRModal
          url={buildInviteUrl('guardian', myCode)}
          title={t('guard.title')}
          onClose={() => setShowQR(false)}
        />
      )}
    </section>
  )
}
