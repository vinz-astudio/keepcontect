export type NativeNotificationReadiness = 'ready' | 'action' | 'unknown'

export function resolveNativeNotificationReadiness({
  permissionGranted,
  tokenAvailable,
}: {
  permissionGranted: boolean
  tokenAvailable: boolean
}): NativeNotificationReadiness {
  if (!permissionGranted) return 'action'
  if (!tokenAvailable) return 'unknown'
  return 'ready'
}

export function isAndroidRequiredSetupReady({
  notification,
  usageGranted,
  guardEnabled,
}: {
  notification: NativeNotificationReadiness
  usageGranted: boolean
  guardEnabled: boolean
}): boolean {
  return notification === 'ready' && usageGranted && guardEnabled
}

export function isIosRequiredSetupReady({
  notification,
  guardEnabled,
}: {
  notification: NativeNotificationReadiness
  guardEnabled: boolean
}): boolean {
  return notification === 'ready' && guardEnabled
}
