import { useEffect, useRef } from 'react'
import { getHeartbeatToken } from '@/features/passive/api'
import {
  configureNativePassivePing,
  getNativeFcmToken,
  requestNativeNotificationPermission,
} from '@/features/passive/native'
import { supabase } from '@/lib/supabase'

export function PassivePingBoot() {
  const tokenRef = useRef<string | null>(null)

  useEffect(() => {
    let cancelled = false

    getHeartbeatToken()
      .then(async (token) => {
        if (cancelled) return
        tokenRef.current = token
        await configureNativePassivePing(token)
        if (token) {
          await requestNativeNotificationPermission()
          const fcm = await getNativeFcmToken()
          if (fcm) {
            void supabase
              .rpc('register_fcm_token', { _token: fcm })
              .then(() => {})
          }
        }
      })
      .catch(() => {})

    return () => {
      cancelled = true
      tokenRef.current = null
      void configureNativePassivePing(null)
    }
  }, [])

  return null
}