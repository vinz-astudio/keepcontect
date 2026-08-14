import { useCallback, useEffect, useRef, useState } from 'react'
import { PrototypeBadge, PrototypeCard, PrototypeSection } from '@/features/prototype/PrototypeUI'
import { useI18n } from '@/lib/i18n'
import {
  getPassiveCheckinStatus,
  savePassiveCheckinContract,
  validatePassiveContractDraft,
  type PassiveCheckinStatus,
  type PassiveContractDraft,
} from './checkinContract'
import { canActivatePassive, formatHorizonMinutes, savePassiveSettingsSafe, shadowDays } from './checkinSettings'
import { explainPassiveRecommendation, getPassiveCheckinRecommendation, type PassiveRecommendation } from './recommendation'
import { getPassiveCollectorHealth, passiveHealthCopy, type PassiveCollectorHealth } from './passiveCheckinPresentation'
import './PassiveCheckinSettings.css'

const DEFAULT_DRAFT: PassiveContractDraft = {
  intervalMinutes: 60,
  consecutiveMisses: 6,
  sleep: { policy: 'none', acknowledged: false },
}

function draftFromStatus(status: PassiveCheckinStatus): PassiveContractDraft {
  const contract = status.contract
  if (!contract) return DEFAULT_DRAFT
  return {
    intervalMinutes: contract.intervalMinutes,
    consecutiveMisses: contract.consecutiveMisses,
    sleep: contract.sleepPolicy === 'configured'
      ? { policy: 'configured', start: contract.sleepStartLocal!.slice(0, 5), end: contract.sleepEndLocal!.slice(0, 5), timezone: contract.timezone! }
      : { policy: 'none', acknowledged: true },
  }
}

export function PassiveCheckinSettings() {
  const { lang } = useI18n()
  const zh = lang === 'zh'
  const [status, setStatus] = useState<PassiveCheckinStatus | null>(null)
  const [recommendation, setRecommendation] = useState<PassiveRecommendation | null>(null)
  const [health, setHealth] = useState<PassiveCollectorHealth | null>(null)
  const [draft, setDraft] = useState<PassiveContractDraft>(DEFAULT_DRAFT)
  const [sleepChoiceMade, setSleepChoiceMade] = useState(false)
  const [busy, setBusy] = useState(false)
  const [migrationConfirmed, setMigrationConfirmed] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const errorRef = useRef<HTMLParagraphElement>(null)

  const load = useCallback(async () => {
    try {
      const [serverStatus, advice, collectorHealth] = await Promise.all([
        getPassiveCheckinStatus(), getPassiveCheckinRecommendation(), getPassiveCollectorHealth(),
      ])
      setStatus(serverStatus)
      setDraft(draftFromStatus(serverStatus))
      setSleepChoiceMade(serverStatus.contract !== null)
      setRecommendation(advice)
      setHealth(collectorHealth)
      setError(null)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause))
    }
  }, [])

  useEffect(() => { void load() }, [load])
  useEffect(() => { if (error) errorRef.current?.focus() }, [error])

  if (!status || !health) {
    return <PrototypeSection title={zh ? '被动联系确认' : 'Passive check-ins'}><PrototypeCard><p role={error ? 'alert' : 'status'}>{error ?? (zh ? '正在读取服务器设置…' : 'Loading server settings…')}</p></PrototypeCard></PrototypeSection>
  }

  const validation = [
    ...(sleepChoiceMade ? [] : [zh ? '请选择睡眠处理方式' : 'Choose how sleep should be handled']),
    ...validatePassiveContractDraft(draft),
  ]
  const hasBoundCollector = health.devices.length > 0
  const eligible = canActivatePassive(status, hasBoundCollector)
  const target = status.engineMode === 'passive_checkin' || (eligible && migrationConfirmed)
    ? 'passive_checkin' : 'shadow'
  const healthCopy = passiveHealthCopy(health, lang)

  async function save() {
    if (validation.length || busy || !status) return
    setBusy(true)
    setError(null)
    const previous = status
    const result = await savePassiveSettingsSafe(draft, target, previous, savePassiveCheckinContract)
    setStatus(result.status)
    if (!result.success) {
      setDraft(draftFromStatus(previous))
      setSleepChoiceMade(previous.contract !== null)
      setError(result.error)
    } else {
      setDraft(draftFromStatus(result.status))
      setSleepChoiceMade(true)
      setMigrationConfirmed(false)
    }
    setBusy(false)
  }

  const setSleepPolicy = (policy: 'configured' | 'none') => {
    setSleepChoiceMade(true)
    setDraft((current) => ({
      ...current,
      sleep: policy === 'configured'
        ? { policy: 'configured', start: '23:00', end: '07:00', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC' }
        : { policy: 'none', acknowledged: false },
    }))
  }
  const updateConfiguredSleep = (patch: Partial<{ start: string; end: string; timezone: string }>) => {
    setDraft((current) => current.sleep.policy === 'configured'
      ? { ...current, sleep: { ...current.sleep, ...patch } }
      : current)
  }

  return (
    <PrototypeSection
      title={zh ? '被动联系确认' : 'Passive check-ins'}
      subtitle={zh
        ? 'KC 只根据“最近有活动”的正证据判断是否仍保持联系；它不能检测事故，也不能保证后台始终可用。'
        : 'KC uses only positive “recent activity” evidence to judge contact. It does not detect accidents or guarantee background delivery.'}
    >
      <PrototypeCard className="passive-checkin-settings">
        <div className="passive-checkin-settings__status">
          <PrototypeBadge tone={status.engineMode === 'passive_checkin' ? 'ready' : status.engineMode === 'shadow' ? 'limited' : 'unknown'}>
            {status.engineMode === 'passive_checkin' ? (zh ? '已启用' : 'On') : status.engineMode === 'shadow' ? (zh ? '观察中' : 'Shadow') : (zh ? '旧模式' : 'Legacy')}
          </PrototypeBadge>
          {status.contract && <span>{zh ? `服务器版本 ${status.contract.versionNumber}` : `Server version ${status.contract.versionNumber}`} · {new Date(status.contract.effectiveAt).toLocaleString()}</span>}
        </div>

        {status.engineMode === 'legacy' && <div className="passive-checkin-settings__migration">
          <strong>{zh ? '先观察 14 天，不会改变现有告警。' : 'Start with 14 days of observation; existing alerts do not change.'}</strong>
          <p>{zh ? '保存后只计算对照窗口，不会发送新式失联告警。14 天后仍需你再次明确确认。' : 'Saving computes comparison windows only. It cannot send passive lost-contact alerts; you must confirm again after 14 days.'}</p>
        </div>}

        <div className="passive-checkin-settings__grid">
          <label><span>{zh ? '每个窗口 D（分钟）' : 'Window D (minutes)'}</span><input aria-label="D" type="number" min={20} max={360} step={1} value={draft.intervalMinutes} onChange={(event) => setDraft({ ...draft, intervalMinutes: Number(event.target.value) })} /></label>
          <label><span>{zh ? '连续漏签 N' : 'Consecutive misses N'}</span><input aria-label="N" type="number" min={1} max={1_000_000} step={1} value={draft.consecutiveMisses} onChange={(event) => setDraft({ ...draft, consecutiveMisses: Number(event.target.value) })} /></label>
        </div>
        <p className="passive-checkin-settings__h"><strong>H = D × N = {formatHorizonMinutes(draft.intervalMinutes, draft.consecutiveMisses)}</strong></p>

        <fieldset className="passive-checkin-settings__sleep">
          <legend>{zh ? '睡眠期间如何处理（必须选择）' : 'Sleep handling (required)'}</legend>
          <label><input type="radio" name="passive-sleep" checked={sleepChoiceMade && draft.sleep.policy === 'configured'} onChange={() => setSleepPolicy('configured')} /> {zh ? '设置睡眠时间' : 'Configure sleep hours'}</label>
          <label><input type="radio" name="passive-sleep" checked={sleepChoiceMade && draft.sleep.policy === 'none'} onChange={() => setSleepPolicy('none')} /> {zh ? '不设置睡眠时间' : 'No sleep schedule'}</label>
          {draft.sleep.policy === 'configured' ? <div className="passive-checkin-settings__grid">
            <label><span>{zh ? '开始' : 'Start'}</span><input type="time" value={draft.sleep.start} onChange={(event) => updateConfiguredSleep({ start: event.target.value })} /></label>
            <label><span>{zh ? '结束' : 'End'}</span><input type="time" value={draft.sleep.end} onChange={(event) => updateConfiguredSleep({ end: event.target.value })} /></label>
            <label className="passive-checkin-settings__timezone"><span>{zh ? 'IANA 时区' : 'IANA timezone'}</span><input value={draft.sleep.timezone} onChange={(event) => updateConfiguredSleep({ timezone: event.target.value })} /></label>
          </div> : <label className="passive-checkin-settings__ack"><input type="checkbox" checked={draft.sleep.acknowledged} onChange={(event) => setDraft({ ...draft, sleep: { policy: 'none', acknowledged: event.target.checked } })} /> {zh ? '我明白：夜间没有活动也会被计为漏签。' : 'I understand that overnight inactivity will count as missed check-ins.'}</label>}
        </fieldset>

        {recommendation && <div className="passive-checkin-settings__advice">
          <strong>{zh ? `建议：D ${recommendation.proposedIntervalMinutes} 分钟，N ${recommendation.proposedConsecutiveMisses}，H ${formatHorizonMinutes(recommendation.proposedIntervalMinutes, recommendation.proposedConsecutiveMisses)}` : `Suggested: D ${recommendation.proposedIntervalMinutes} min, N ${recommendation.proposedConsecutiveMisses}, H ${formatHorizonMinutes(recommendation.proposedIntervalMinutes, recommendation.proposedConsecutiveMisses)}`}</strong>
          {explainPassiveRecommendation(recommendation, lang).map((line) => <p key={line}>{line}</p>)}
        </div>}

        <div className={`passive-checkin-settings__health is-${health.state}`}>
          <strong>{zh ? '采集状态' : 'Collector health'}: {healthCopy.label}</strong>
          <p>{healthCopy.detail}</p>
          {health.devices.filter((device) => device.state === 'limited').map((device) => <p key={device.bindingId}><b>{device.device}</b> · {device.reason} · {device.repairAction}</p>)}
        </div>

        {status.engineMode === 'shadow' && <div className="passive-checkin-settings__migration">
          <p>{zh ? `已观察 ${shadowDays(status)} 天；满 14 天且设备已绑定后才能启用。` : `${shadowDays(status)} shadow days complete; 14 days and a bound collector are required.`}</p>
          {eligible && <label className="passive-checkin-settings__ack"><input type="checkbox" checked={migrationConfirmed} onChange={(event) => setMigrationConfirmed(event.target.checked)} /> {zh ? '我确认启用：连续 N 次漏签后，KC 可能询问我并通知信任的人。' : 'I confirm activation: after N misses, KC may ask me and notify people I trust.'}</label>}
        </div>}

        {validation.length > 0 && <ul className="passive-checkin-settings__errors">{validation.map((message) => <li key={message}>{message}</li>)}</ul>}
        {error && <p ref={errorRef} tabIndex={-1} role="alert" className="passive-checkin-settings__error">{zh ? '保存失败，已恢复服务器设置：' : 'Save failed; server settings were restored: '}{error}</p>}
        <button type="button" className="prototype-button prototype-button--primary" disabled={busy || validation.length > 0} onClick={() => void save()}>
          {busy ? (zh ? '正在保存…' : 'Saving…') : target === 'passive_checkin' ? (zh ? '保存并启用' : 'Save and activate') : status.engineMode === 'legacy' ? (zh ? '开始 14 天观察' : 'Start 14-day shadow') : (zh ? '保存观察设置' : 'Save shadow settings')}
        </button>
      </PrototypeCard>
    </PrototypeSection>
  )
}
