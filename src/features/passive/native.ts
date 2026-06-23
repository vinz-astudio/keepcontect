import { Capacitor, registerPlugin } from '@capacitor/core'
import { SUPABASE_URL } from '@/lib/config'
import { isSensorEnabled } from '@/features/signals/sensors'

interface PassivePingPlugin {
  configure(options: {
    supabaseUrl: string
    token: string
    allowUnlock?: boolean
    allowCharging?: boolean
  }): Promise<void>
  clear(): Promise<void>
  pingApp(): Promise<void>
}

const PassivePing = registerPlugin<PassivePingPlugin>('PassivePing')

export async function configureNativePassivePing(
  token: string | null,
): Promise<void> {
  if (Capacitor.getPlatform() !== 'android') return
  try {
    if (!token) {
      await PassivePing.clear()
      return
    }
    const allowUnlock = isSensorEnabled('phone_unlock')
    const allowCharging = isSensorEnabled('phone_charger')
    await PassivePing.configure({
      supabaseUrl: SUPABASE_URL,
      token,
      allowUnlock,
      allowCharging,
    })
    await PassivePing.pingApp()
  } catch {
    // Native bridge is best-effort; PWA ping URLs remain the fallback.
  }
}
