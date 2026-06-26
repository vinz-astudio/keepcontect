import { supabase } from '@/lib/supabase'

/** 粗略活跃桶（绝不返回精确时间）：
 *  self=本人 / active=近期活跃 / quiet=已静默数小时 / silent=超过一天 /
 *  unknown=暂无数据 / hidden=对方未公开或你无权查看 */
export type ActivityStatus =
  | 'self'
  | 'active'
  | 'quiet'
  | 'silent'
  | 'alert'
  | 'unknown'
  | 'hidden'

export type GroupVisibility = 'watchers_only' | 'group_wide'

export interface GroupMemberStatus {
  user_id: string
  name: string
  is_me: boolean
  status: ActivityStatus
  hours: number | null
  last_behavior_at?: string | null
  last_heartbeat_at?: string | null
  threshold_hours?: number | null
  /** 是否处于已升级到 group+ 的开放告警（异常沉默，需关注） */
  alerted: boolean
}

export interface GroupActivity {
  visibility: GroupVisibility
  is_owner: boolean
  i_share: boolean
  members: GroupMemberStatus[]
}

/** 读取一个 Group 的平安看板（成员 + 粗略活跃状态） */
export async function getGroupActivity(groupId: string): Promise<GroupActivity> {
  const { data, error } = await supabase.rpc('get_group_activity', {
    _group: groupId,
  })
  if (error) throw error
  return data as unknown as GroupActivity
}

/** 本人开关"公开我的活跃状态"（opt-in） */
export async function setShareActivity(share: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_share_activity', { _share: share })
  if (error) throw error
}

/** 向同组成员发"关怀"——催对方打开 App 解锁报平安，确认是否误报 */
export async function sendConcern(target: string): Promise<void> {
  const { error } = await supabase.rpc('send_concern', { _target: target })
  if (error) throw error
}

/** 组主设置本组可见范围 */
export async function setGroupVisibility(
  groupId: string,
  visibility: GroupVisibility,
): Promise<void> {
  const { error } = await supabase.rpc('set_group_visibility', {
    _group: groupId,
    _visibility: visibility,
  })
  if (error) throw error
}
