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
    expect(html).not.toContain('Choose your device')
    expect(html).not.toContain('Caregiver Mode')
  })
})
