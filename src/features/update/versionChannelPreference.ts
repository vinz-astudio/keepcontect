import { useCallback, useEffect, useState } from 'react'
import type { VersionStatus } from '@/features/update/versionSelection'

const GM_VERSION_CHANNEL_KEY = 'kc.gm.versionChannel'
const GM_VERSION_CHANNEL_EVENT = 'kc:gm-version-channel'

function isVersionStatus(value: string | null): value is VersionStatus {
  return value === 'canary' || value === 'released'
}

export function readGmVersionChannel(): VersionStatus {
  try {
    if (typeof localStorage === 'undefined') return 'canary'
    const stored = localStorage.getItem(GM_VERSION_CHANNEL_KEY)
    return isVersionStatus(stored) ? stored : 'canary'
  } catch {
    return 'canary'
  }
}

export function writeGmVersionChannel(channel: VersionStatus): void {
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(GM_VERSION_CHANNEL_KEY, channel)
    }
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent(GM_VERSION_CHANNEL_EVENT, { detail: channel }))
    }
  } catch {
    // Local preference failures should not block update checks.
  }
}

export function useGmVersionChannel(enabled = true): [VersionStatus, (channel: VersionStatus) => void] {
  const [channel, setChannel] = useState<VersionStatus>(() =>
    enabled ? readGmVersionChannel() : 'released',
  )

  useEffect(() => {
    if (!enabled) {
      setChannel('released')
      return
    }
    setChannel(readGmVersionChannel())
    const sync = () => setChannel(readGmVersionChannel())
    window.addEventListener('storage', sync)
    window.addEventListener(GM_VERSION_CHANNEL_EVENT, sync)
    return () => {
      window.removeEventListener('storage', sync)
      window.removeEventListener(GM_VERSION_CHANNEL_EVENT, sync)
    }
  }, [enabled])

  const update = useCallback((next: VersionStatus) => {
    setChannel(next)
    writeGmVersionChannel(next)
  }, [])

  return [channel, update]
}
