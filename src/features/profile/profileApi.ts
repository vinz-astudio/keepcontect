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
