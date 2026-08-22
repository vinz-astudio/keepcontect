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
 * 注销本人账号并清空个人数据，符合 Google Play Data Deletion 与 Apple App Store 5.1.1(v) 政策。
 * 遵循 Fail-Closed 原则：服务端删除失败立即抛出异常，绝不吞错假冒登出。
 */
export async function deleteMyAccount(): Promise<void> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('未检测到有效登录会话')

  // 1. 调用服务端 delete-account Edge Function
  const { data, error: fnError } = await supabase.functions.invoke('delete-account')
  if (fnError) {
    throw new Error(fnError.message || '账户注销服务调用失败')
  }
  if (!data?.ok) {
    throw new Error(data?.error || '服务端数据销毁失败')
  }

  // 2. 清理本地所有存储 Key (Fail-Closed: 严禁吞错)
  try {
    localStorage.clear()
  } catch (lsErr: any) {
    throw new Error(`本地存储清理失败: ${lsErr?.message || String(lsErr)}`)
  }

  // 3. 清理 IndexedDB 信号数据 (Fail-Closed)
  const { clearLocalSignalStore } = await import('@/features/signals/store')
  await clearLocalSignalStore()

  // 4. 安全登出
  await supabase.auth.signOut()
}
