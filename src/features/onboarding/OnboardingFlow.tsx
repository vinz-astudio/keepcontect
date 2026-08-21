import {
  PrototypeBadge,
  PrototypeCard,
  PrototypeIcon,
  PrototypeRow,
} from '@/features/prototype/PrototypeUI'
import {
  getProgressLabel,
  type OnboardingStep,
  type SetupCapability,
  type SetupResult,
} from './onboardingPresentation'
import './OnboardingFlow.css'

interface OnboardingFlowProps {
  step: OnboardingStep
  result: SetupResult
  capabilities: SetupCapability[]
  onStepChange: (step: OnboardingStep) => void
  onRefresh: () => void | Promise<void>
  onComplete: () => void
  lang: 'en' | 'zh'
  busy?: boolean
}

const resultCopy = {
  en: {
    ready: ['You’re ready', 'Required settings are on. Keep Contact will keep checking this phone’s collector; iOS or Android may still delay background updates.'],
    limited: ['Limited protection', 'Keep Contact can still help, but this phone may update less reliably. You can finish now and repair setup later.'],
    unknown: ['Setup not verified', 'We could not verify this phone yet. Check the items below and try again.'],
  },
  zh: {
    ready: ['已经准备好', '必需设置已开启。Keep Contact 会继续检查这台手机的采集状态；iOS 或 Android 仍可能延迟后台更新。'],
    limited: ['保护能力有限', 'Keep Contact 仍然可以帮助您，但这台手机的后台更新可能较不稳定。您可以先完成，之后再修复设置。'],
    unknown: ['尚未验证设置', '目前还无法确认这台手机的状态。请检查下方项目后重试。'],
  },
} as const

export function OnboardingFlow({
  step,
  result,
  capabilities,
  onStepChange,
  onRefresh,
  onComplete,
  lang,
  busy = false,
}: OnboardingFlowProps) {
  const progress = getProgressLabel(step)
  const isZh = lang === 'zh'
  const stateLabel = (capability: SetupCapability) => capability.stateLabel
    ?? (isZh
      ? ({ ready: '已开启', limited: '受限', unknown: '未知', action: '需处理' } as const)[capability.state]
      : capability.state)
  const requirementLabel = (capability: SetupCapability) => capability.requirement
    ? (isZh
      ? (capability.requirement === 'required' ? '必需' : '建议')
      : (capability.requirement === 'required' ? 'Required' : 'Recommended'))
    : null

  return (
    <main className="onboarding-flow">
      <header className="onboarding-flow__header">
        <div className="onboarding-flow__brand">
          <span className="onboarding-flow__brand-mark"><PrototypeIcon name="favorite" /></span>
          <span>Keep Contact</span>
        </div>
        {progress && <span className="onboarding-flow__progress">{progress}</span>}
      </header>

      {step === 'value' && (
        <section className="onboarding-flow__hero">
          <div className="onboarding-flow__hero-icon"><PrototypeIcon name="shield_with_heart" /></div>
          <p className="onboarding-flow__eyebrow">{isZh ? '安静守护，不用反复报平安' : 'Quiet reassurance'}</p>
          <h1>{isZh ? '保持联系，不必整天报平安' : 'Stay connected without checking in all day'}</h1>
          <p>
            {isZh
              ? 'Keep Contact 会记录这台手机支持的粗粒度活动时间。只有您明确启用被动联系确认后，长时间失去联系才可能让它先询问您，再通知您信任的人。'
              : 'Keep Contact records coarse activity timestamps supported by this phone. After you explicitly enable passive check-ins, a long loss of contact can make it ask you first and then notify people you trust.'}
          </p>
          <PrototypeCard className="onboarding-flow__value-card">
            <PrototypeRow icon="phone_iphone" title={isZh ? '自动识别这台手机' : 'This phone is detected automatically'} subtitle={isZh ? '不需要选择设备或使用身份。' : 'No device or role selection is needed.'} />
            <PrototypeRow icon="notifications_active" title={isZh ? '异常时才提醒' : 'Alerts only when needed'} subtitle={isZh ? '平常不会要求您反复打卡。' : 'Normal days stay quiet.'} />
            <PrototypeRow icon="groups" title={isZh ? '由您决定谁能关照您' : 'You choose who can support you'} subtitle={isZh ? '关系与责任之后都可以调整。' : 'Relationships and responsibilities can be changed later.'} />
          </PrototypeCard>
          <button type="button" className="prototype-button prototype-button--primary onboarding-flow__primary" onClick={() => onStepChange('phone-setup')}>
            {isZh ? '设置这台手机' : 'Set up this phone'}
            <PrototypeIcon name="arrow_forward" />
          </button>
        </section>
      )}

      {step === 'phone-setup' && (
        <section className="onboarding-flow__content">
          <p className="onboarding-flow__eyebrow">{isZh ? '本机设置' : 'Phone setup'}</p>
          <h1>{isZh ? '让 Keep Contact 在需要时找到您' : 'Help Keep Contact notice that you’re okay'}</h1>
          <p>{isZh ? '只处理这台手机实际支持的权限。您可以随时在 Me 页回来修复。' : 'Only settings supported by this phone are shown. You can repair them later from Me.'}</p>
          <PrototypeCard>
            {capabilities.map((capability) => (
              <PrototypeRow
                key={capability.key}
                icon={capability.icon}
                title={capability.title}
                subtitle={<>
                  {requirementLabel(capability) && <><strong>{requirementLabel(capability)}</strong> · </>}
                  {capability.description}
                </>}
                trailing={capability.state === 'action' && capability.onAction
                  ? <button type="button" className="prototype-button prototype-button--ghost onboarding-flow__action" disabled={busy} onClick={() => void capability.onAction?.()}>{capability.actionLabel}</button>
                  : <PrototypeBadge tone={capability.state}>{stateLabel(capability)}</PrototypeBadge>}
              />
            ))}
          </PrototypeCard>
          <div className="onboarding-flow__buttons">
            <button type="button" className="prototype-button prototype-button--ghost" onClick={() => onStepChange('value')}>{isZh ? '返回' : 'Back'}</button>
            <button type="button" className="prototype-button prototype-button--primary" disabled={busy} onClick={() => void onRefresh()}>
              {busy ? (isZh ? '正在检查…' : 'Checking…') : (isZh ? '检查设置' : 'Check setup')}
            </button>
          </div>
        </section>
      )}

      {step === 'result' && (
        <section className="onboarding-flow__result">
          <div className={`onboarding-flow__result-icon onboarding-flow__result-icon--${result}`}>
            <PrototypeIcon name={result === 'ready' ? 'verified_user' : result === 'limited' ? 'shield_lock' : 'help'} />
          </div>
          <PrototypeBadge tone={result}>{result}</PrototypeBadge>
          <h1>{resultCopy[lang][result][0]}</h1>
          <p>{resultCopy[lang][result][1]}</p>
          {capabilities.length > 0 && (
            <PrototypeCard compact>
              {capabilities.map((capability) => (
                <PrototypeRow key={capability.key} icon={capability.icon} title={capability.title} trailing={<PrototypeBadge tone={capability.state}>{stateLabel(capability)}</PrototypeBadge>} />
              ))}
            </PrototypeCard>
          )}
          <div className="onboarding-flow__buttons onboarding-flow__buttons--stacked">
            {result === 'unknown' ? (
              <button type="button" className="prototype-button prototype-button--primary" disabled={busy} onClick={() => void onRefresh()}>{isZh ? '重新检查' : 'Check again'}</button>
            ) : (
              <button type="button" className="prototype-button prototype-button--primary" onClick={onComplete}>{isZh ? '进入 Keep Contact' : 'Enter Keep Contact'}</button>
            )}
            <button type="button" className="prototype-button prototype-button--ghost" onClick={() => onStepChange('phone-setup')}>{isZh ? '查看设置' : 'Review setup'}</button>
          </div>
        </section>
      )}
    </main>
  )
}
