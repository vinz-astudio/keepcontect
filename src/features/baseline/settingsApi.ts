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

// ---- 睡眠窗（本地 HH:MM ↔ 服务器 UTC time）----

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

/** 本地 HH:MM → UTC "HH:MM:00"（作息在本地固定，按当下日期换算时区即可） */
function localToUtcTime(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number)
  const d = new Date()
  d.setHours(h, m, 0, 0)
  return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:00`
}

/** UTC "HH:MM[:SS]" → 本地 HH:MM */
function utcTimeToLocal(t: string): string {
  const [h, m] = t.split(':').map(Number)
  const d = new Date()
  d.setUTCHours(h, m, 0, 0)
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`
}

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
    .select('sleep_start_utc, sleep_end_utc')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  if (!data?.sleep_start_utc || !data?.sleep_end_utc) return null
  return {
    start: utcTimeToLocal(data.sleep_start_utc),
    end: utcTimeToLocal(data.sleep_end_utc),
  }
}

/** 设置睡眠窗（本地 HH:MM） */
export async function setSleepWindow(
  startLocal: string,
  endLocal: string,
): Promise<void> {
  const { error } = await supabase.rpc('set_sleep_window', {
    _start: localToUtcTime(startLocal),
    _end: localToUtcTime(endLocal),
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

