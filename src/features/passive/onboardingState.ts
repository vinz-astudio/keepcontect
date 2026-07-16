export type OnboardingPlatform = 'android_native' | 'ios' | 'android_pwa' | 'desktop_tauri' | 'plain_web'
export type ReadinessState = 'ready' | 'partial' | 'not_applicable_plain_web'

export interface GatingInputs {
  platform: OnboardingPlatform
  usageStatsOk?: boolean
  motionOk?: boolean
  pingOk?: boolean
}

export interface OnboardingData {
  role: 'caregiver' | 'recipient'
  version: number
  completedAt: number
}

/** Determines readiness class based on target platform and permissions/verification status */
export function getReadinessState(inputs: GatingInputs): ReadinessState {
  if (inputs.platform === 'plain_web') {
    return 'not_applicable_plain_web'
  }
  if (inputs.platform === 'android_native') {
    const usage = !!inputs.usageStatsOk
    const motion = !!inputs.motionOk
    const ping = !!inputs.pingOk
    return (usage && motion && ping) ? 'ready' : 'partial'
  }
  // ios, android_pwa, desktop_tauri all require pingOk to be ready
  return inputs.pingOk ? 'ready' : 'partial'
}

/** Formats the user-scoped localStorage key */
export function getOnboardingKey(uid: string): string {
  return `kc.onboardingCompleted.${uid}`
}

/**
 * Checks if the scoped onboarding key is present for the current user and matches their role.
 * If a legacy global 'kc.onboardingCompleted' key exists:
 *   - Write the scoped key for the current user and current role
 *   - Delete the legacy global key 'kc.onboardingCompleted'
 *   - Returns true
 */
export function checkAndMigrateOnboarding(uid: string, isGm: boolean): boolean {
  const scopedKey = getOnboardingKey(uid)
  const role = isGm ? 'caregiver' : 'recipient'

  const rawScoped = localStorage.getItem(scopedKey)
  if (rawScoped) {
    try {
      const parsed = JSON.parse(rawScoped) as OnboardingData
      return parsed.role === role
    } catch {
      // Parse error, treat as uncompleted
    }
  }

  const legacyGlobal = localStorage.getItem('kc.onboardingCompleted')
  if (legacyGlobal === 'true') {
    const data: OnboardingData = {
      role,
      version: 1,
      completedAt: Date.now()
    }
    localStorage.setItem(scopedKey, JSON.stringify(data))
    localStorage.removeItem('kc.onboardingCompleted')
    return true
  }

  return false
}

/** Saves user-scoped onboarding completion payload */
export function saveOnboardingCompleted(uid: string, isGm: boolean): void {
  const scopedKey = getOnboardingKey(uid)
  const role = isGm ? 'caregiver' : 'recipient'
  const data: OnboardingData = {
    role,
    version: 1,
    completedAt: Date.now()
  }
  localStorage.setItem(scopedKey, JSON.stringify(data))
}

/** Removes the user-scoped onboarding completion key */
export function clearOnboardingCompleted(uid: string): void {
  localStorage.removeItem(getOnboardingKey(uid))
}
