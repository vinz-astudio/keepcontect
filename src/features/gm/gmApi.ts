import { supabase } from '@/lib/supabase'
import { selectLatestVersion, type VersionChannel } from '@/features/update/versionSelection'

export interface GmClient {
  user_id: string
  name: string
  platform: string | null
  app_version: string | null
  first_seen_at?: string | null
  last_seen_at: string | null
  last_heartbeat_at?: string | null
  last_behavior_at?: string | null
  alerted?: boolean
  web_count?: number
  status?: string | null
}

export async function amIGm(): Promise<boolean> {
  const { data, error } = await supabase.rpc('am_i_gm')
  if (error) return false
  return data === true
}

export async function gmListClients(): Promise<GmClient[]> {
  const { data, error } = await supabase.rpc('gm_list_clients')
  if (error) throw error
  return (data as unknown as GmClient[]) ?? []
}

export async function gmNudgeUpdate(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_nudge_update', { _target: target })
  if (error) throw error
}

export async function gmSendConcern(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_send_concern', { _target: target })
  if (error) throw error
}

export async function gmDeleteAccount(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_delete_user', { _target: target })
  if (error) throw error
}

export interface DbVersionInfo {
  version: string
  apk_url: string | null
  exe_url: string | null
  status: VersionChannel
  created_at: string
}

export async function gmListVersions(): Promise<DbVersionInfo[]> {
  const { data, error } = await (supabase as any)
    .from('app_versions')
    .select('version, apk_url, exe_url, status, created_at')
    .order('created_at', { ascending: false })
    .limit(50)
  if (error) throw error
  return (data as DbVersionInfo[]) ?? []
}

export async function gmGetLatestVersion(
  channel: VersionChannel = 'canary',
): Promise<DbVersionInfo | null> {
  const versions = await gmListVersions()
  return selectLatestVersion(versions, channel)
}

export async function gmReleaseVersion(version: string): Promise<void> {
  const { error } = await (supabase as any)
    .from('app_versions')
    .update({ status: 'released' })
    .eq('version', version)
  if (error) throw error
}
