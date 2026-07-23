// 灵敏度同步：客户端选择写到服务器（供 silence_threshold 用），并能从服务器拉回。

import { supabase } from '@/lib/supabase'
import type { Sensitivity } from '@/features/baseline/types'

export async function setServerSensitivity(s: Sensitivity): Promise<void> {
  const { error } = await supabase.rpc('set_sensitivity', { _s: s })
  if (error) throw error
}

export async function getServerSensitivity(): Promise<Sensitivity | null> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return null
  const { data, error } = await supabase
    .from('user_settings')
    .select('sensitivity')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  const s = data?.sensitivity
  return s === 'high' || s === 'balanced' || s === 'low' ? s : null
}

// ---- 睡眠窗（本地 HH:MM）----

export interface SleepWindow {
  start: string // 本地 HH:MM
  end: string
}

/** 读取睡眠窗（无则 null） */
export async function getSleepWindow(): Promise<SleepWindow | null> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return null
  const { data, error } = await supabase
    .from('user_settings')
    .select('sleep_start_local, sleep_end_local')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  if (!data?.sleep_start_local || !data?.sleep_end_local) return null
  return {
    start: data.sleep_start_local.slice(0, 5),
    end: data.sleep_end_local.slice(0, 5),
  }
}

/** 设置睡眠窗（本地 HH:MM） */
export async function setSleepWindow(
  startLocal: string,
  endLocal: string,
): Promise<void> {
  // 必须始终携带 _tz:缺省会触发服务端的旧客户端垫片(把数字当 UTC 换算)。
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
  const { error } = await supabase.rpc('set_sleep_window', {
    _start: `${startLocal}:00`,
    _end: `${endLocal}:00`,
    _tz: tz,
  })
  if (error) throw error
}

/** 关闭睡眠窗(省略参数 = SQL 端默认 null,与旧传 null 语义一致) */
export async function clearSleepWindow(): Promise<void> {
  const { error } = await supabase.rpc('set_sleep_window', {})
  if (error) throw error
}

export async function getServerPatternHash(): Promise<string | null> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return null
  const { data, error } = await supabase
    .from('user_settings')
    .select('pattern_hash')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  return data?.pattern_hash || null
}

export async function setServerPatternHash(hash: string): Promise<void> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return
  const { error } = await supabase
    .from('user_settings')
    .update({ pattern_hash: hash })
    .eq('user_id', uid)
  if (error) throw error
}

/** 检测并同步本地浏览器时区到服务器 */
export async function syncServerTimezone(): Promise<void> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (!tz) return

  const { data, error } = await (supabase
    .from('user_settings')
    .select('timezone')
    .eq('user_id', uid)
    .maybeSingle() as any)
  if (error) throw error

  if (!data || data.timezone !== tz) {
    const { error: updateErr } = await supabase
      .from('user_settings')
      .update({ timezone: tz } as any)
      .eq('user_id', uid)
    if (updateErr) throw updateErr
  }
}

export interface SaveResult<T> {
  success: boolean
  value: T
  error: string | null
}

export async function saveSensitivitySafe(
  newValue: Sensitivity,
  fallbackValue: Sensitivity
): Promise<SaveResult<Sensitivity>> {
  try {
    await setServerSensitivity(newValue)
    return { success: true, value: newValue, error: null }
  } catch (err: any) {
    return {
      success: false,
      value: fallbackValue,
      error: err?.message || String(err),
    }
  }
}

export async function saveSleepWindowSafe(
  startLocal: string,
  endLocal: string,
  fallback: { start: string; end: string } | null
): Promise<SaveResult<{ start: string; end: string } | null>> {
  try {
    await setSleepWindow(startLocal, endLocal)
    return { success: true, value: { start: startLocal, end: endLocal }, error: null }
  } catch (err: any) {
    return {
      success: false,
      value: fallback,
      error: err?.message || String(err),
    }
  }
}

export async function clearSleepWindowSafe(
  fallback: { start: string; end: string } | null
): Promise<SaveResult<{ start: string; end: string } | null>> {
  try {
    await clearSleepWindow()
    return { success: true, value: null, error: null }
  } catch (err: any) {
    return {
      success: false,
      value: fallback,
      error: err?.message || String(err),
    }
  }
}

import { updateRoutineProfile, type RoutineProfile } from '@/features/profile/profileApi'

export async function updateRoutineProfileSafe(
  updates: Partial<RoutineProfile>,
  fallback: RoutineProfile
): Promise<SaveResult<RoutineProfile>> {
  try {
    await updateRoutineProfile(updates)
    return { success: true, value: { ...fallback, ...updates }, error: null }
  } catch (err: any) {
    return {
      success: false,
      value: fallback,
      error: err?.message || String(err),
    }
  }
}


