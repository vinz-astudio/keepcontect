import { supabase } from '@/lib/supabase'
import {
  selectLatestVersion,
  type VersionChannel,
  type VersionStatus,
} from '@/features/update/versionSelection'

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
  /** Why an alert is open. `dark_device` is about equipment, `silence` about a
   *  person, and the two call for opposite responses. */
  alert_cause?: 'silence' | 'dark_device' | 'concern' | 'sos' | null
  alert_stage?: string | null
  alert_opened_at?: string | null
  /** Which kind of quiet this is, judged by the device heartbeat rather than by
   *  whether an alert happens to be open yet. */
  silence_kind?: 'person_quiet' | 'device_dark' | 'unknown' | null
  /** The line this account is judged against. Null means no usable evidence,
   *  and therefore no silence alert can fire for them at all (ADR-0037). */
  threshold_minutes?: number | null
  threshold_basis?: {
    has_usable_signal?: boolean | null
    through_date?: string | null
    computed_at?: string | null
    sensitivity?: string | null
    buffer_minutes?: number | null
    normal_upper_bound_minutes?: number | null
    largest_gap_minutes?: number | null
    gap_count?: number | null
    evidence_days?: number | null
    sleep_window_applied?: boolean | null
  } | null
  muted_until?: string | null
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

export async function gmMuteUser(
  target: string,
  until?: string | null,
  reason?: string,
): Promise<void> {
  const { error } = await supabase.rpc('gm_mute_user', {
    _target: target,
    _reason: reason ?? '',
    ...(until ? { _until: until } : {}),
  })
  if (error) throw error
}

export async function gmUnmuteUser(target: string): Promise<void> {
  const { error } = await supabase.rpc('gm_unmute_user', { _target: target })
  if (error) throw error
}

export interface DbVersionInfo {
  version: string
  apk_url: string | null
  exe_url: string | null
  status: VersionStatus
  public_rollout: boolean | null
  created_at: string
}

export async function gmListVersions(): Promise<DbVersionInfo[]> {
  const { data, error } = await (supabase as any)
    .from('app_versions')
    .select('version, apk_url, exe_url, status, public_rollout, created_at')
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
    .update({ status: 'released', public_rollout: false })
    .eq('version', version)
  if (error) throw error
}

export async function gmSetCanaryPublic(version: string, enabled: boolean): Promise<void> {
  const { error } = await (supabase as any)
    .from('app_versions')
    .update({ public_rollout: enabled })
    .eq('version', version)
    .eq('status', 'canary')
  if (error) throw error
}
