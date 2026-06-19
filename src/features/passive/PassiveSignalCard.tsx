import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useState } from 'react'
import {
  countTodayPings,
  getHeartbeatToken,
  lastPingAt,
  listRecentPings,
  pingUrl,
  shortcutImportUrl,
  type BehaviorPing,
} from '@/features/passive/api'
import { getPlatform } from '@/lib/platform'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import './PassiveSignalCard.css'

function ago(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return translate('time.now')
  if (s < 3600) return translate('time.min', { n: Math.floor(s / 60) })
  if (s < 86400) return translate('time.hour', { n: Math.floor(s / 3600) })
  return translate('time.day', { n: Math.floor(s / 86400) })
}

function androidRuntime(): 'native' | 'web' | null {
  if (getPlatform() !== 'android') return null
  return Capacitor.getPlatform() === 'android' ? 'native' : 'web'
}

export function PassiveSignalCard() {
  const { t } = useI18n()
  const platform = getPlatform()
  const android = androidRuntime()
  const [token, setToken] = useState<string | null>(null)
  const [pings, setPings] = useState<BehaviorPing[]>([])
  const [copied, setCopied] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)

  const refresh = useCallback(async () => {
    try {
      const [tk, ps] = await Promise.all([getHeartbeatToken(), listRecentPings()])
      setToken(tk)
      setPings(ps)
    } catch (e) {
      setError(e instanceof Error ? e.message : translate('err.load'))
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const todayCount = countTodayPings(pings)
  const lastAt = lastPingAt(pings)
  const url = token ? pingUrl(token) : ''

  const platformMessage: I18nKey =
    platform === 'ios'
      ? 'passive.platform.ios'
      : android === 'native'
        ? 'passive.platform.androidNative'
        : android === 'web'
          ? 'passive.platform.androidWeb'
          : 'passive.platform.desktop'

  const modeLabel: I18nKey =
    platform === 'ios'
      ? 'passive.mode.shortcut'
      : android === 'native'
        ? 'passive.mode.auto'
        : 'passive.mode.manual'

  async function copy() {
    try {
      await navigator.clipboard.writeText(url)
    } catch {
      /* Clipboard can fail in older webviews; the URL remains selectable. */
    }
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <section className="card">
      <h2 className="card__title">{t('passive.title')}</h2>
      <p className="muted">{t('passive.desc')}</p>

      {error && <p className="home__error">{error}</p>}

      <p className="psig__stat">{t(platformMessage)}</p>

      <div className="psig__item">
        <div className="psig__itemhead">
          <div>
            <strong>{t('passive.url')}</strong>
            <span className="psig__mode">{t(modeLabel)}</span>
          </div>
          <div className="psig__btns">
            {platform === 'ios' && token && (
              <a className="psig__import" href={shortcutImportUrl(token)}>
                {t('passive.import')}
              </a>
            )}
            <button className="share" disabled={!token} onClick={() => void copy()}>
              {copied ? t('passive.copied') : t('passive.copy')}
            </button>
          </div>
        </div>
        <p className="psig__kinddesc">{t('passive.url.desc')}</p>
        <p className="psig__statline">
          <strong>{t('passive.today', { n: todayCount })}</strong>
          {' / '}
          {lastAt ? t('passive.last', { ago: ago(lastAt) }) : t('passive.never')}
        </p>
        <code className="psig__url">{url}</code>
      </div>

      <p className="muted psig__triggers">{t('passive.triggers')}</p>

      <button className="psig__toggle" onClick={() => setOpen((v) => !v)}>
        {t('passive.setup')} {open ? '^' : 'v'}
      </button>
      {open && (
        <div className="psig__help">
          <p>{t('passive.setup.steps')}</p>
          {android === 'native' && <p>{t('passive.setup.androidNative')}</p>}
          {android === 'web' && <p>{t('passive.setup.androidWeb')}</p>}
          {platform === 'ios' && <p>{t('passive.setup.ios')}</p>}
          <p className="muted">{t('passive.setup.tip')}</p>
        </div>
      )}
    </section>
  )
}
