import { Capacitor, registerPlugin } from '@capacitor/core'
import { SUPABASE_URL } from '@/lib/config'

interface PassivePingPlugin {
  configure(options: { supabaseUrl: string; token: string }): Promise<void>
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
    await PassivePing.configure({ supabaseUrl: SUPABASE_URL, token })
    await PassivePing.pingApp()
  } catch {
    // Native bridge is best-effort; PWA ping URLs remain the fallback.
  }
}
