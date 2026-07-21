import { supabase } from '@/lib/supabase'
import { emitAlertChange } from '@/features/alerts/alertBus'
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
  emitAlertChange()
}

export async function raiseSos(): Promise<string> {
  const { data, error } = await supabase.rpc('raise_sos')
  if (error) throw error
  return data as string
}

export async function updateSosLocation(
  lat: number,
  lng: number,
): Promise<boolean> {
  const { data, error } = await supabase.rpc('update_sos_location', {
    _lat: lat,
    _lng: lng,
  })
  if (error) throw error
  return !!data
}

// ---- 响应者两段式确认 ----

export async function ackAlert(alertId: string, minutes = 30): Promise<void> {
  const { error } = await supabase.rpc('ack_alert', {
    _alert_id: alertId,
    _minutes: minutes,
  })
  if (error) throw error
  emitAlertChange()
}

export async function resolveAlert(alertId: string): Promise<void> {
  const { error } = await supabase.rpc('resolve_alert', { _alert_id: alertId })
  if (error) throw error
  emitAlertChange()
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

/**
 * 清除「已完成」的通知,保留仍需我处理的(对应仍 open 的告警)。
 * keep 判定在服务端 RPC 里做:客户端 items 状态可能陈旧/为空(构建窗口、
 * limit 30),曾导致 open 告警的通知也被清掉、响应卡片无法重建。
 */
export async function clearFinishedNotifications(): Promise<void> {
  // 类型待 database.types.ts 重新生成后补上(该文件归 KC-R4 SOS 任务写集)
  const { error } = await supabase.rpc('clear_finished_notifications' as any)
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
  const { getEmergencyInfoForUser: decryptGet } = await import('@/features/profile/emergencyApi')
  return decryptGet(userId)
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

export interface ClientDevice {
  client_id: string
  platform: string | null
  app_version: string | null
  first_seen_at: string
  last_seen_at: string
}

export async function getUserClients(userId: string): Promise<ClientDevice[]> {
  const { data, error } = await supabase
    .from('clients' as any)
    .select('client_id, platform, app_version, first_seen_at, last_seen_at')
    .eq('user_id', userId)
  if (error) {
    // Fail silently on permission error (RLS)
    return []
  }
  return (data as unknown as ClientDevice[]) ?? []
}
