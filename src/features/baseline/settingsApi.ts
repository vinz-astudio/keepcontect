// 灵敏度同步：客户端选择写到服务器（供 silence_threshold 用），并能从服务器拉回。

import { supabase } from '@/lib/supabase'
import type { Sensitivity } from '@/features/baseline/types'
import { getDailyCheckin, saveDailyCheckin } from '@/features/passive/dailyCheckinApi'

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

/**
 * 手动时区覆盖标记(按设备)。
 *
 * 自动检测是主路径,手动只是附带 —— 但两者会打架:`syncServerTimezone` 每次
 * 启动都跑,会把用户手选的时区盖回系统检测值。所以手选时记一个标记,让自动
 * 同步让位;清掉标记就回到自动。
 */
const TZ_MANUAL_KEY = 'kc.timezone.manual'

export function isTimezoneManual(): boolean {
  try {
    return localStorage.getItem(TZ_MANUAL_KEY) === 'true'
  } catch {
    return false
  }
}

export function detectTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
}

/**
 * 紧急 GPS 同意 —— 账号级真相在服务器,本地只是给 SOS 路径用的快取。
 *
 * 之前它只存在 localStorage,重装即失、服务端不可见、换设备不跟随,而且**没有
 * 任何代码读它** —— dispatchSos 无条件抓取并上传坐标。开关承诺了一个隐私边界
 * 却不执行,比没有这个开关更糟:用户做了决定,决定被丢掉了。
 */
const GPS_CONSENT_KEY = 'kc.emergency_gps_consent'

function mirrorGpsConsentLocally(granted: boolean): void {
  try {
    localStorage.setItem(GPS_CONSENT_KEY, granted ? 'true' : 'false')
  } catch {
    /* 存不进去时 SOS 路径会读不到 → 按未同意处理,这是安全的方向 */
  }
}

/** 拉取账号级同意并同步到本地快取。SOS 时读的是快取,不能等网络。 */
export async function loadEmergencyGpsConsent(): Promise<boolean> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return false
  const { data, error } = await (supabase
    .from('user_settings')
    .select('emergency_gps_consent')
    .eq('user_id', uid)
    .maybeSingle() as any)
  if (error) throw error
  const granted = data?.emergency_gps_consent === true
  mirrorGpsConsentLocally(granted)
  return granted
}

export async function setEmergencyGpsConsent(granted: boolean): Promise<void> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) throw new Error('未登录')
  const { error } = await supabase
    .from('user_settings')
    .update({ emergency_gps_consent: granted } as any)
    .eq('user_id', uid)
  if (error) throw error
  mirrorGpsConsentLocally(granted)
}

/** 读服务器当前生效的时区(可能是自动检测写入的,也可能是手动覆盖的)。 */
export async function getServerTimezone(): Promise<string | null> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) return null
  const { data, error } = await (supabase
    .from('user_settings')
    .select('timezone')
    .eq('user_id', uid)
    .maybeSingle() as any)
  if (error) throw error
  return data?.timezone || null
}

/** 手动设置时区。写服务器 —— 告警的睡眠窗按它换算,不写等于没设。 */
export async function setServerTimezone(tz: string): Promise<void> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) throw new Error('未登录')
  const { error } = await supabase
    .from('user_settings')
    .update({ timezone: tz } as any)
    .eq('user_id', uid)
  if (error) throw error
  try {
    localStorage.setItem(TZ_MANUAL_KEY, tz === detectTimezone() ? 'false' : 'true')
  } catch {
    /* localStorage 不可用时,下次启动会被自动检测盖回,可接受 */
  }
  await syncCheckinContractTimezone(tz)
}

/**
 * 时区存了两份:`user_settings.timezone` 给持续沉默判断用,每日确认契约里
 * 还有自己的一份。只写前者会让两套判断按不同的当地时间跑,用户看不出来。
 *
 * 这里是尽力而为:没有契约、或者写失败,都不该让时区本身的保存失败。
 */
async function syncCheckinContractTimezone(tz: string): Promise<void> {
  try {
    const status = await getDailyCheckin()
    if (!status?.draft || status.draft.timezone === tz) return
    if (status.engineMode !== 'shadow' && status.engineMode !== 'passive_checkin') return
    await saveDailyCheckin({ ...status.draft, timezone: tz }, status.engineMode)
  } catch {
    /* 契约没建立或 RPC 失败:时区主记录已经写成功,不回滚 */
  }
}

/** 检测并同步本地浏览器时区到服务器 */
export async function syncServerTimezone(): Promise<void> {
  // 用户明确手选过就不覆盖。否则自动同步会在下次启动悄悄推翻他的选择。
  if (isTimezoneManual()) return
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


