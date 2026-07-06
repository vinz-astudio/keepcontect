export type VersionStatus = 'canary' | 'released'
export type VersionChannel = VersionStatus | 'public'

export interface VersionRecord {
  version: string
  status?: VersionStatus | null
  public_rollout?: boolean | null
  created_at?: string | null
}

function parseVersion(version: string): number[] {
  return version
    .replace(/^v/i, '')
    .split('.')
    .map((part) => parseInt(part, 10) || 0)
}

export function compareVersions(left: string, right: string): number {
  const a = parseVersion(left)
  const b = parseVersion(right)
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0)
    if (diff !== 0) return diff
  }
  return 0
}

export function isNewer(latest: string, current: string): boolean {
  return compareVersions(latest, current) > 0
}

function createdAtMs(record: VersionRecord): number {
  return record.created_at ? new Date(record.created_at).getTime() || 0 : 0
}

function newestFirst<T extends VersionRecord>(a: T, b: T): number {
  const versionDiff = compareVersions(b.version, a.version)
  if (versionDiff !== 0) return versionDiff
  return createdAtMs(b) - createdAtMs(a)
}

function isReleased(record: VersionRecord): boolean {
  return record.status == null || record.status === 'released'
}

function isPublicVisible(record: VersionRecord): boolean {
  return isReleased(record) || (record.status === 'canary' && record.public_rollout === true)
}

export function selectLatestCanary<T extends VersionRecord>(records: T[]): T | null {
  return [...records.filter((record) => record.status === 'canary')].sort(newestFirst)[0] ?? null
}

export function selectLatestVersion<T extends VersionRecord>(
  records: T[],
  channel: VersionChannel,
): T | null {
  const primary = (() => {
    if (channel === 'canary') return records.filter((record) => record.status === 'canary')
    if (channel === 'public') return records.filter(isPublicVisible)
    return records.filter(isReleased)
  })()

  const candidates =
    channel === 'canary' && primary.length === 0
      ? records.filter(isReleased)
      : primary

  return [...candidates].sort(newestFirst)[0] ?? null
}

export function isClientBehindTarget(
  clientVersion: string | null | undefined,
  targetVersion: string,
): boolean {
  return clientVersion ? isNewer(targetVersion, clientVersion) : true
}
