import { useEffect, useRef } from 'react'
import { Capacitor } from '@capacitor/core'
import { getHeartbeatToken } from '@/features/passive/api'
import {
  configureNativePassivePing,
  getNativeFcmToken,
  requestNativeNotificationPermission,
} from '@/features/passive/native'
import { startTauriShadowCoverage } from '@/features/passive/shadowCoverage'
import { supabase } from '@/lib/supabase'

export function PassivePingBoot() {
  const tokenRef = useRef<string | null>(null)

  useEffect(() => {
    let cancelled = false
    let stopShadowCoverage: () => void = () => {}

    getHeartbeatToken()
      .then(async (token) => {
        if (cancelled) return
        tokenRef.current = token
        await configureNativePassivePing(token)
        if (cancelled) return
        if (token) {
          stopShadowCoverage = startTauriShadowCoverage()
          await requestNativeNotificationPermission()
          const fcm = await getNativeFcmToken()
          if (fcm) {
            void supabase
              .rpc('register_fcm_token', {
                _token: fcm,
                // The RPC defaults to 'android', so an iOS token would be
                // mislabelled and never selected by a platform-targeted send.
                _platform: Capacitor.getPlatform(),
              })
              .then(() => {})
          }
        }
      })
      .catch(() => {})

    return () => {
      cancelled = true
      stopShadowCoverage()
      tokenRef.current = null
    }
  }, [])

  return null
}
