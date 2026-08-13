import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { OnboardingFlow } from './OnboardingFlow'
import {
  getOnboardingSteps,
  getProgressLabel,
  resolveSetupResult,
} from './onboardingPresentation'

describe('Onboarding presentation', () => {
  it('counts two user tasks and not the result', () => {
    expect(getOnboardingSteps()).toEqual(['value', 'phone-setup', 'result'])
    expect(getProgressLabel('value')).toBe('1 of 2')
    expect(getProgressLabel('phone-setup')).toBe('2 of 2')
    expect(getProgressLabel('result')).toBeNull()
  })

  it('never calls stale or missing evidence Ready', () => {
    expect(resolveSetupResult({
      currentRunVerified: false,
      requiredReady: true,
      unavailable: false,
    })).toBe('unknown')
    expect(resolveSetupResult({
      currentRunVerified: true,
      requiredReady: false,
      unavailable: true,
    })).toBe('limited')
  })

  it('returns Ready only for verified current-run evidence', () => {
    expect(resolveSetupResult({
      currentRunVerified: true,
      requiredReady: true,
      unavailable: false,
    })).toBe('ready')
  })

  it('renders value as task one without asking for a device or role', () => {
    const html = renderToStaticMarkup(createElement(OnboardingFlow, {
      step: 'value',
      result: 'unknown',
      capabilities: [],
      onStepChange: () => undefined,
      onRefresh: () => undefined,
      onComplete: () => undefined,
      lang: 'en',
    }))

    expect(html).toContain('1 of 2')
    expect(html).toContain('Stay connected without checking in all day')
    expect(html).toContain('coarse activity timestamps')
    expect(html).not.toContain('Choose your device')
    expect(html).not.toContain('Caregiver Mode')
  })

  it('shows required versus recommended setup and truthful custom states', () => {
    const html = renderToStaticMarkup(createElement(OnboardingFlow, {
      step: 'phone-setup',
      result: 'unknown',
      capabilities: [
        {
          key: 'notifications', icon: 'notifications_active', title: 'Emergency notifications',
          description: 'Allows alerts to reach you.', state: 'ready',
          requirement: 'required',
        },
        {
          key: 'health', icon: 'health_and_safety', title: 'Health wake',
          description: 'Adds another wake opportunity.', state: 'ready',
          requirement: 'recommended', stateLabel: 'Set up',
        },
      ],
      onStepChange: () => undefined,
      onRefresh: () => undefined,
      onComplete: () => undefined,
      lang: 'en',
    }))

    expect(html).toContain('Required')
    expect(html).toContain('Recommended')
    expect(html).toContain('Set up')
  })

  it('does not promise continuous background safety updates on Ready', () => {
    const html = renderToStaticMarkup(createElement(OnboardingFlow, {
      step: 'result',
      result: 'ready',
      capabilities: [],
      onStepChange: () => undefined,
      onRefresh: () => undefined,
      onComplete: () => undefined,
      lang: 'en',
    }))

    expect(html).toContain('Required settings are on')
    expect(html).toContain('may still delay background updates')
    expect(html).not.toContain('keep your safety status up to date in the background')
  })
})
