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


const GROUP_STATUS_TABLES = [
  'alerts',
  'device_state',
  'behavior_pings',
  'group_members',
  'community_members',
  'groups',
  'communities',
  'user_settings',
  'profiles',
] as const

const GM_STATUS_TABLES = [
  'alerts',
  'behavior_pings',
  'device_state',
  'clients',
  'profiles',
] as const

async function subscribeTableInvalidation(
  name: string,
  tables: readonly string[],
  onChange: () => void,
): Promise<Unsubscribe> {
  const { data } = await supabase.auth.getUser()
  const uid = data.user?.id
  if (!uid) return () => {}

  let channel = supabase.channel(
    name + ':' + uid + ':' + Math.random().toString(36).slice(2),
  )
  for (const table of tables) {
    channel = channel.on(
      'postgres_changes',
      { event: '*', schema: 'public', table },
      onChange,
    )
  }
  channel.subscribe()

  return () => {
    void supabase.removeChannel(channel)
  }
}

export async function subscribeGroupStatusSignals(
  onChange: () => void,
): Promise<Unsubscribe> {
  return subscribeTableInvalidation('group-status-signals', GROUP_STATUS_TABLES, onChange)
}

export async function subscribeGmStatusSignals(
  onChange: () => void,
): Promise<Unsubscribe> {
  return subscribeTableInvalidation('gm-status-signals', GM_STATUS_TABLES, onChange)
}
