import { useEffect } from 'react'
import { Capacitor } from '@capacitor/core'
import { getHeartbeatToken } from '@/features/passive/api'
import {
  configureNativePassivePing,
} from '@/features/passive/native'
import {
  startTauriPassiveEvidence,
  startTauriShadowCoverage,
} from '@/features/passive/shadowCoverage'
import { startNativePushLifecycle } from '@/features/push/nativePushBinding'
import { useAuth } from '@/features/auth/AuthProvider'
import { startPwaPassiveEvidence } from './pwaEvidenceBoot'

export function PassivePingBoot() {
  const { user } = useAuth()

  useEffect(() => startPwaPassiveEvidence(user?.id ?? null), [user?.id])
  useEffect(() => user?.id ? startNativePushLifecycle(user.id) : undefined, [user?.id])

  useEffect(() => {
    if (!user?.id) return
    const stopCoverage = startTauriShadowCoverage()
    const stopEvidence = startTauriPassiveEvidence()
    return () => { stopCoverage(); stopEvidence() }
  }, [user?.id])

  useEffect(() => {
    let cancelled = false
    if (!user?.id || !Capacitor.isNativePlatform()) return

    getHeartbeatToken()
      .then(async (token) => {
        if (cancelled) return
        await configureNativePassivePing(token, { expectedOwnerId: user.id })
      })
      .catch(() => {})

    return () => {
      cancelled = true
    }
  }, [user?.id])

  return null
}
