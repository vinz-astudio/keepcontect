import { supabase } from '@/lib/supabase'

type Unsubscribe = () => void

/**
 * Best-effort realtime invalidation for alert/notification surfaces.
 * Polling remains the fallback because production realtime publication can be
 * disabled or delayed on some projects.
 */
export async function subscribeAlertSignals(
  onChange: () => void,
): Promise<Unsubscribe> {
  const { data } = await supabase.auth.getUser()
  const uid = data.user?.id
  if (!uid) return () => {}

  const channel = supabase
    .channel(`alert-signals:${uid}:${Math.random().toString(36).slice(2)}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'notifications',
        filter: `recipient_id=eq.${uid}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'alerts',
        filter: `user_id=eq.${uid}`,
      },
      onChange,
    )
    .subscribe()

  return () => {
    void supabase.removeChannel(channel)
  }
}
