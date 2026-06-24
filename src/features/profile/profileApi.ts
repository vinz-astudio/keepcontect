import { supabase } from '@/lib/supabase'

/**
 * 设置本人显示名：同步更新 profiles.display_name（别人看到的名字）
 * 与 auth user_metadata.display_name（本机头部展示）。
 */
export async function setDisplayName(name: string): Promise<void> {
  const clean = name.trim()
  if (!clean) throw new Error('name required')
  const { error } = await supabase.rpc('set_display_name', { _name: clean })
  if (error) throw error
  // 更新 metadata：会触发 onAuthStateChange，头部名字即时刷新
  await supabase.auth.updateUser({ data: { display_name: clean } })
}

export interface RoutineProfile {
  routine_pattern: string
  consent_data_sharing: boolean
}

export async function getRoutineProfile(): Promise<RoutineProfile> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not authenticated')
  const { data, error } = await (supabase
    .from('profiles')
    .select('routine_pattern, consent_data_sharing')
    .eq('id', user.id)
    .single() as any)
  if (error) throw error
  return data as RoutineProfile
}

export async function updateRoutineProfile(updates: Partial<RoutineProfile>): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not authenticated')
  const { error } = await (supabase
    .from('profiles')
    .update(updates as any)
    .eq('id', user.id) as any)
  if (error) throw error
}

