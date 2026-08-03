export type OnboardingStep = 'value' | 'phone-setup' | 'result'
export type SetupResult = 'ready' | 'limited' | 'unknown'
export type SetupCapabilityState = 'ready' | 'action' | 'limited' | 'unknown'

export interface SetupCapability {
  key: string
  icon: string
  title: string
  description: string
  state: SetupCapabilityState
  actionLabel?: string
  onAction?: () => void | Promise<void>
}

export function getOnboardingSteps(): readonly OnboardingStep[] {
  return ['value', 'phone-setup', 'result']
}

export function getProgressLabel(step: OnboardingStep): string | null {
  if (step === 'value') return '1 of 2'
  if (step === 'phone-setup') return '2 of 2'
  return null
}

export function resolveSetupResult({
  currentRunVerified,
  requiredReady,
  unavailable,
}: {
  currentRunVerified: boolean
  requiredReady: boolean
  unavailable: boolean
}): SetupResult {
  if (!currentRunVerified) return 'unknown'
  if (unavailable || !requiredReady) return 'limited'
  return 'ready'
}
