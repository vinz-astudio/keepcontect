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
