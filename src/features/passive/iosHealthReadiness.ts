import type { HealthWakeStatus } from './native'

// HealthKit never reveals read authorization. Even a registered observer or a
// successful empty query cannot establish that walking is being collected.
export function iosHealthReadiness(health: HealthWakeStatus | undefined): 'unknown' | 'action' | 'limited' {
  if (!health) return 'unknown'
  if (!health.supported) return 'limited'
  return health.asked ? 'limited' : 'action'
}
