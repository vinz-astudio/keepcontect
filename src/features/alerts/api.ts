import { supabase } from '@/lib/supabase'
import type { Tables } from '@/lib/database.types'

export type AppNotification = Tables<'notifications'>
export type Alert = Tables<'alerts'>
export type EmergencyInfo = Tables<'emergency_info'>

// ---- 设备心跳 / 自解除 / SOS ----

export async function sendHeartbeat(status: 'normal' | 'alert'): Promise<void> {
  const { error } = await supabase.rpc('send_heartbeat', { _status: status })
  if (error) throw error
}

export async function resolveMyAlert(): Promise<void> {
  const { error } = await supabase.rpc('resolve_my_alert')
  if (error) throw error
}

export async function raiseSos(
  lat?: number | null,
  lng?: number | null,
): Promise<string> {
  const { data, error } = await supabase.rpc('raise_sos', {
    _lat: lat ?? null,
    _lng: lng ?? null,
  })
  if (error) throw error
  return data as string
}

// ---- 响应者两段式确认 ----

export async function ackAlert(alertId: string, minutes = 30): Promise<void> {
  const { error } = await supabase.rpc('ack_alert', {
    _alert_id: alertId,
    _minutes: minutes,
  })
  if (error) throw error
}

export async function resolveAlert(alertId: string): Promise<void> {
  const { error } = await supabase.rpc('resolve_alert', { _alert_id: alertId })
  if (error) throw error
}

// ---- 查询 ----

export async function listMyNotifications(limit = 30): Promise<AppNotification[]> {
  const { data, error } = await supabase
    .from('notifications')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error
  return data ?? []
}

export async function markNotificationRead(id: string): Promise<void> {
  const { error } = await supabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('id', id)
  if (error) throw error
}

/** 清除单条通知 */
export async function deleteNotification(id: string): Promise<void> {
  const { error } = await supabase.from('notifications').delete().eq('id', id)
  if (error) throw error
}

/** 清除我的全部通知 */
export async function clearMyNotifications(): Promise<void> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return
  const { error } = await supabase
    .from('notifications')
    .delete()
    .eq('recipient_id', uid)
  if (error) throw error
}

/** 我自己当前是否有 open 告警（驱动本机自证界面的服务器侧确认） */
export async function getMyOpenAlert(): Promise<Alert | null> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return null
  const { data, error } = await supabase
    .from('alerts')
    .select('*')
    .eq('user_id', uid)
    .eq('status', 'open')
    .maybeSingle()
  if (error) throw error
  return data
}

export async function getAlert(alertId: string): Promise<Alert | null> {
  const { data, error } = await supabase
    .from('alerts')
    .select('*')
    .eq('id', alertId)
    .maybeSingle()
  if (error) throw error
  return data
}

/** 取某用户的紧急信息（RLS：仅在该用户有 open 告警且我是授权响应者时返回） */
export async function getEmergencyInfoForUser(
  userId: string,
): Promise<EmergencyInfo | null> {
  const { data, error } = await supabase
    .from('emergency_info')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function getProfileName(userId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('id', userId)
    .maybeSingle()
  if (error) throw error
  return data?.display_name ?? null
}
