import { supabase } from '@/lib/supabase'

export interface GmClient {
  user_id: string
  name: string
  platform: string | null
  app_version: string | null
  first_seen_at?: string | null
  last_seen_at: string | null
  /** 设备心跳时间(device_state) — 包含 app 保活心跳，不代表真实行为 */
  last_heartbeat_at?: string | null
  /** 最后一次真实行为信号时间(behavior_pings) — 与 silence 检测同源 */
  last_behavior_at?: string | null
  /** 是否有已升级到 group+ 的 open 告警 */
  alerted?: boolean
  /** 网页会话折叠后代表的会话数(仅 *-web 折叠时 >1) */
  web_count?: number
  /** 基于 behavior_pings 的存活状态(与 process_escalations 同源) */
  status?: string | null
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

export interface DbVersionInfo {
  version: string
  apk_url: string | null
  exe_url: string | null
  status: 'canary' | 'released'
  created_at: string
}

/** 获取最新的版本信息(GM-only, 能够看到所有包括 canary 的版本) */
export async function gmGetLatestVersion(): Promise<DbVersionInfo | null> {
  const { data, error } = await (supabase as any)
    .from('app_versions')
    .select('version, apk_url, exe_url, status, created_at')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data as DbVersionInfo | null
}

/** 全量发布某个内测版本给所有用户 */
export async function gmReleaseVersion(version: string): Promise<void> {
  const { error } = await (supabase as any)
    .from('app_versions')
    .update({ status: 'released' })
    .eq('version', version)
  if (error) throw error
}
