export type ActivityTruthSource = 'server' | 'local'

export function chooseLastActivityTruth({
  serverLastAt,
  localLastAt,
  serverTruthRequired,
}: {
  serverLastAt: string | null | undefined
  localLastAt: string | null | undefined
  serverTruthRequired: boolean
}): { iso: string | null; source: ActivityTruthSource } {
  if (serverTruthRequired) {
    return { iso: serverLastAt ?? null, source: 'server' }
  }
  if (serverLastAt) return { iso: serverLastAt, source: 'server' }
  return { iso: localLastAt ?? null, source: 'local' }
}

export function getActiveStatusDisplayState({
  serverLastAt,
  localLastAt,
  serverTruthRequired,
  online,
}: {
  serverLastAt: string | null | undefined
  localLastAt: string | null | undefined
  serverTruthRequired: boolean
  online: boolean
}): {
  iso: string | null
  source: ActivityTruthSource
  showMarker: boolean
  isDegraded: boolean
  degradedHint?: { zh: string; en: string } | null
} {
  // If server truth is required but is missing
  if (serverTruthRequired && !serverLastAt) {
    return {
      iso: null,
      source: 'server',
      showMarker: false,
      isDegraded: true,
      degradedHint: null,
    }
  }

  // If offline
  if (!online) {
    // If local fallback is available and server truth is not strictly required
    if (!serverTruthRequired && localLastAt) {
      return {
        iso: localLastAt,
        source: 'local',
        showMarker: true,
        isDegraded: true,
        degradedHint: {
          zh: '离线,显示本机记录',
          en: 'Offline — showing this device',
        },
      }
    }
    // Offline with nothing (or offline when serverTruthRequired is true and serverLastAt is missing/null,
    // though the serverTruthRequired && !serverLastAt case above already handled !serverLastAt)
    const chosen = chooseLastActivityTruth({
      serverLastAt,
      localLastAt: null,
      serverTruthRequired,
    })
    return {
      iso: chosen.iso,
      source: chosen.source,
      showMarker: false,
      isDegraded: true,
      degradedHint: null,
    }
  }

  // Online
  const chosen = chooseLastActivityTruth({
    serverLastAt,
    localLastAt,
    serverTruthRequired,
  })

  return {
    iso: chosen.iso,
    source: chosen.source,
    showMarker: chosen.source === 'local',
    isDegraded: false,
    degradedHint: null,
  }
}
