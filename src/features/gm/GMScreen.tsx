import { useCallback, useEffect, useState } from 'react'
import {
  gmListClients,
  gmNudgeUpdate,
  gmSendConcern,
  type GmClient,
} from '@/features/gm/gmApi'
import { translate, useI18n } from '@/lib/i18n'
import { toast } from '@/lib/toast'
import { Icon } from '@/features/common/Icon'
import './GMScreen.css'

interface UserRow {
  user_id: string
  name: string
  clients: GmClient[]
}

export function GMScreen() {
  const { t } = useI18n()
  const [rows, setRows] = useState<UserRow[]>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)

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

  function ago(iso: string | null): string {
    if (!iso) return t('gm.never')
    const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
    if (s < 3600) return t('time.min', { n: Math.max(1, Math.floor(s / 60)) })
    if (s < 86400) return t('time.hour', { n: Math.floor(s / 3600) })
    return t('time.day', { n: Math.floor(s / 86400) })
  }

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="shield" />
        {t('gm.title')}
      </h2>
      <p className="muted">{t('gm.desc')}</p>
      {error && <p className="home__error">{error}</p>}

      <ul className="gm__list">
        {rows.map((r) => (
          <li key={r.user_id} className="gm__item">
            <div className="gm__head">
              <strong className="gm__name">{r.name}</strong>
              <span className="gm__ver">
                {r.clients.length
                  ? r.clients
                      .map(
                        (c) => `${c.platform ?? '?'} · v${c.app_version ?? '?'}`,
                      )
                      .join('  /  ')
                  : t('gm.noreport')}
              </span>
            </div>
            {r.clients.length > 0 && (
              <span className="gm__seen">
                {t('gm.lastseen', { ago: ago(r.clients[0].last_seen_at) })}
              </span>
            )}
            <div className="gm__actions">
              <button
                disabled={busy === r.user_id + 'u'}
                onClick={() =>
                  void act(
                    r.user_id + 'u',
                    () => gmNudgeUpdate(r.user_id),
                    t('gm.nudged'),
                  )
                }
              >
                {t('gm.nudge')}
              </button>
              <button
                disabled={busy === r.user_id + 'c'}
                onClick={() =>
                  void act(
                    r.user_id + 'c',
                    () => gmSendConcern(r.user_id),
                    t('gm.concerned'),
                  )
                }
              >
                {t('gm.concern')}
              </button>
            </div>
          </li>
        ))}
      </ul>

      <button className="gm__refresh" onClick={() => void load()}>
        {t('gm.refresh')}
      </button>
    </section>
  )
}
