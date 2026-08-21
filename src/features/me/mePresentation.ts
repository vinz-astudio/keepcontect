export const ME_SECTIONS = [
  'account',
  'safety-checkin',
  'guardian-permissions',
  'emergency',
  'preferences-updates',
] as const

export function getEmergencyCapabilities({
  multiCardApiAvailable,
  gpsContractResolved,
}: {
  multiCardApiAvailable: boolean
  gpsContractResolved: boolean
}): {
  multiCardEditing: boolean
  crisisGpsPersistence: boolean
} {
  return {
    multiCardEditing: multiCardApiAvailable,
    crisisGpsPersistence: gpsContractResolved,
  }
}
