import { supabase } from '@/lib/supabase'

export interface GmClient {
  user_id: string
  name: string
  platform: string | null
  app_version: string | null
  last_seen_at: string | null
}

/** 当前用户是否 GM(决定是否显示 GM 页) */
export async function amIGm(): Promise<boolean> {
  const { data, error } = await supabase.rpc('am_i_gm')
  if (error) return false
  return data === true
}

/** 所有用户 × 各客户端的版本/平台(GM-only) */
export async function gmListClients(): Promise<GmClient[]> {
  const { data, error } = await supabase.rpc('gm_list_clients')
  if (error) throw error
  return (data as unknown as GmClient[]) ?? []
}

/** 提醒某用户更新版本 */
export async function gmNudgeUpdate(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_nudge_update', { _target: target })
  if (error) throw error
}

/** 向某用户发送关怀 */
export async function gmSendConcern(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_send_concern', { _target: target })
  if (error) throw error
}

/** 删除/封禁用户账号 */
export async function gmDeleteAccount(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_delete_user', { _target: target })
  if (error) throw error
}
