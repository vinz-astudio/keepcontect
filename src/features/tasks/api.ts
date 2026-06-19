import { supabase } from '@/lib/supabase'
import type { Tables } from '@/lib/database.types'

export type CheckinTask = Tables<'checkin_tasks'>

async function requireUid(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const uid = data.user?.id
  if (!uid) throw new Error('未登录')
  return uid
}

/** 本地 HH:MM → { UTC 时刻字符串, 首个到期 timestamptz(今天该时刻,已过则明天) } */
export function localTimeToUtc(localHHMM: string): {
  dueTimeUtc: string
  firstDue: string
} {
  const [h, m] = localHHMM.split(':').map(Number)
  const d = new Date()
  d.setHours(h, m, 0, 0)
  if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1)
  const hh = String(d.getUTCHours()).padStart(2, '0')
  const mm = String(d.getUTCMinutes()).padStart(2, '0')
  return { dueTimeUtc: `${hh}:${mm}:00`, firstDue: d.toISOString() }
}

/** UTC 时刻字符串 → 本地 HH:MM(展示用) */
export function utcTimeToLocal(dueTimeUtc: string): string {
  const [h, m] = dueTimeUtc.split(':').map(Number)
  const d = new Date()
  d.setUTCHours(h, m, 0, 0)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

/** 我承担的任务(含待接受) */
export async function listMyTasks(): Promise<CheckinTask[]> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('checkin_tasks')
    .select('*')
    .eq('ward_id', uid)
    .in('status', ['pending', 'active'])
    .order('created_at')
  if (error) throw error
  return data ?? []
}

/** 我(作为守护人)给别人设的任务 */
export async function listTasksISet(): Promise<CheckinTask[]> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('checkin_tasks')
    .select('*')
    .eq('created_by', uid)
    .neq('ward_id', uid)
    .in('status', ['pending', 'active', 'declined'])
    .order('created_at')
  if (error) throw error
  return data ?? []
}

/** 自设每日任务(晨间打卡) */
export async function createMyDailyTask(
  localHHMM: string,
  label: string,
): Promise<void> {
  const uid = await requireUid()
  const { dueTimeUtc, firstDue } = localTimeToUtc(localHHMM)
  const { error } = await supabase.rpc('create_checkin_task', {
    _ward: uid,
    _kind: 'daily',
    _due_time_utc: dueTimeUtc,
    _first_due: firstDue,
    _label: label,
  })
  if (error) throw error
}

/** 守护人给被守护者设任务 */
export async function createTaskForWard(
  wardId: string,
  opts:
    | { kind: 'daily'; localHHMM: string; label: string }
    | { kind: 'interval'; hours: number; label: string },
): Promise<void> {
  if (opts.kind === 'daily') {
    const { dueTimeUtc, firstDue } = localTimeToUtc(opts.localHHMM)
    const { error } = await supabase.rpc('create_checkin_task', {
      _ward: wardId,
      _kind: 'daily',
      _due_time_utc: dueTimeUtc,
      _first_due: firstDue,
      _label: opts.label,
    })
    if (error) throw error
  } else {
    const { error } = await supabase.rpc('create_checkin_task', {
      _ward: wardId,
      _kind: 'interval',
      _interval_hours: opts.hours,
      _label: opts.label,
    })
    if (error) throw error
  }
}

/** 守护人编辑已安排的任务 */
export async function updateTaskForWard(
  taskId: string,
  opts:
    | { kind: 'daily'; localHHMM: string; label: string }
    | { kind: 'interval'; hours: number; label: string },
): Promise<void> {
  if (opts.kind === 'daily') {
    const { dueTimeUtc, firstDue } = localTimeToUtc(opts.localHHMM)
    const { error } = await supabase.rpc('update_checkin_task', {
      _task: taskId,
      _kind: 'daily',
      _due_time_utc: dueTimeUtc,
      _first_due: firstDue,
      _label: opts.label,
    })
    if (error) throw error
  } else {
    const { error } = await supabase.rpc('update_checkin_task', {
      _task: taskId,
      _kind: 'interval',
      _interval_hours: opts.hours,
      _label: opts.label,
    })
    if (error) throw error
  }
}

/** 被守护者响应(接受/拒绝);接受 daily 任务时计算首个到期 */
export async function respondTask(task: CheckinTask, accept: boolean): Promise<void> {
  let firstDue: string | null = null
  if (accept && task.kind === 'daily' && task.due_time_utc) {
    firstDue = localTimeToUtc(utcTimeToLocal(task.due_time_utc)).firstDue
  }
  const { error } = await supabase.rpc('respond_checkin_task', {
    _task: task.id,
    _accept: accept,
    _first_due: firstDue,
  })
  if (error) throw error
}

export async function revokeTask(taskId: string): Promise<void> {
  const { error } = await supabase.rpc('revoke_checkin_task', { _task: taskId })
  if (error) throw error
}
