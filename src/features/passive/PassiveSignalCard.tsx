import { Capacitor } from '@capacitor/core'
import { useCallback, useEffect, useState } from 'react'
import {
  countTodayPings,
  getHeartbeatToken,
  lastPingAt,
  listRecentPings,
  pingUrl,
  shortcutImportUrl,
  summaryUrl,
  type BehaviorPing,
} from '@/features/passive/api'
import { getDesktopOS, getPlatform } from '@/lib/platform'
import { buildWindowsHookCmd } from '@/features/passive/windowsHook'
import { APP_VERSION, LATEST_URL } from '@/lib/version'
import { translate, useI18n, type I18nKey } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'
import './PassiveSignalCard.css'

function downloadText(name: string, text: string): void {
  const blob = new Blob([text], { type: 'application/octet-stream' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

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
  const desktopOS = platform === 'desktop' ? getDesktopOS() : null
  const [token, setToken] = useState<string | null>(null)
  const [pings, setPings] = useState<BehaviorPing[]>([])
  const [copied, setCopied] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [hookConsent, setHookConsent] = useState(false)

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
      <h2 className="card__title">
        <Icon name="signal" />
        {t('passive.title')}
      </h2>
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

      {desktopOS === 'windows' && (
        <div className="psig__hook">
          {/* 选项一:零安装(推荐)——让 PWA 登录时自动启动 */}
          <p className="psig__hooktitle">{t('hook.pwa.title')}</p>
          <p className="muted">{t('hook.pwa.desc')}</p>
          <ol className="psig__steps">
            <li>{t('hook.pwa.s1')}</li>
            <li>{t('hook.pwa.s2')}</li>
            <li>{t('hook.pwa.s3')}</li>
          </ol>

          {/* 选项二:进阶——关掉窗口也后台 + 托盘小图标 */}
          <div className="psig__hookdiv" />
          <p className="psig__hooktitle">{t('hook.win.title')}</p>
          <p className="muted">{t('hook.win.desc')}</p>
          <p className="muted psig__hookwarn">{t('hook.win.smartscreen')}</p>
          <label className="psig__hookconsent">
            <input
              type="checkbox"
              checked={hookConsent}
              onChange={(e) => setHookConsent(e.target.checked)}
            />
            <span>{t('hook.win.consent')}</span>
          </label>
          <button
            className="psig__import"
            disabled={!token || !hookConsent}
            onClick={() => {
              if (!token) return
              downloadText(
                'KeepContact-Setup.cmd',
                buildWindowsHookCmd(
                  pingUrl(token),
                  summaryUrl(token),
                  window.location.origin,
                  LATEST_URL,
                  APP_VERSION,
                ),
              )
            }}
          >
            {t('hook.win.download')}
          </button>
          <p className="muted psig__hooknote">{t('hook.win.note')}</p>
        </div>
      )}
      {(desktopOS === 'mac' || desktopOS === 'linux') && (
        <p className="muted psig__hook">{t('hook.other')}</p>
      )}

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
