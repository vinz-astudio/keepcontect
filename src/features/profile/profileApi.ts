import { supabase } from '@/lib/supabase'

// `profiles.routine_pattern` 这一列还在,但页面上已经没有控件写它了。读回来时
// 仍然要收敛成生产里的三个值,免得历史行把别的字符串带进类型。
const ROUTINE_PATTERNS = ['regular_9to5', 'semester_break', 'shift_irregular']

function normalizeRoutineMode(value: unknown): string {
  return typeof value === 'string' && ROUTINE_PATTERNS.includes(value) ? value : 'regular_9to5'
}

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
  return {
    ...(data as RoutineProfile),
    routine_pattern: normalizeRoutineMode(data?.routine_pattern),
  }
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

/**
 * 注销本人账号并清空个人数据，符合 Google Play Data Deletion 政策。
 */
export async function deleteMyAccount(): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return
  const uid = user.id

  try {
    // 1. 删除业务与关联层数据
    await supabase.from('profiles').delete().eq('id', uid)
    await (supabase.from('user_settings').delete().eq('user_id', uid) as any)
    await (supabase.from('user_activity_profiles').delete().eq('user_id', uid) as any)
    await (supabase.from('device_state').delete().eq('user_id', uid) as any)
  } catch (err) {
    console.error('Failed to clear server account records:', err)
  }

  // 2. 清理本地所有存储 Key
  try {
    localStorage.clear()
  } catch {
    /* ignore */
  }

  // 3. 安全登出
  await supabase.auth.signOut()
}

