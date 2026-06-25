import { supabase } from '@/lib/supabase'
import type { Tables } from '@/lib/database.types'

export type Group = Tables<'groups'>
export type Community = Tables<'communities'>
export type Profile = Tables<'profiles'>

export interface MyGroup {
  group: Group
  role: string
  monitored: boolean
  watching: boolean
}

export interface GroupMemberView {
  user_id: string
  role: string
  monitored: boolean
  watching: boolean
  display_name: string | null
}

async function requireUid(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const uid = data.user?.id
  if (!uid) throw new Error('未登录')
  return uid
}

export async function listMyGroups(): Promise<MyGroup[]> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('group_members')
    .select('role, monitored, watching, groups(*)')
    .eq('user_id', uid)
  if (error) throw error
  return (data ?? [])
    .filter((r) => r.groups)
    .map((r) => ({
      group: r.groups as unknown as Group,
      role: r.role,
      monitored: r.monitored,
      watching: r.watching,
    }))
}

export async function listMyCommunities(): Promise<Community[]> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('community_members')
    .select('communities(*)')
    .eq('user_id', uid)
  if (error) throw error
  return (data ?? [])
    .map((r) => r.communities as unknown as Community)
    .filter(Boolean)
}

export async function createCommunity(name: string): Promise<Community> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('communities')
    .insert({ name, created_by: uid })
    .select()
    .single()
  if (error) throw error
  return data
}

export async function createGroup(
  name: string,
  communityId: string | null,
): Promise<Group> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('groups')
    .insert({ name, created_by: uid, community_id: communityId })
    .select()
    .single()
  if (error) throw error
  return data
}

export async function joinGroupByCode(code: string): Promise<string> {
  const { data, error } = await supabase.rpc('join_group_by_code', {
    _code: code.trim(),
  })
  if (error) throw error
  return data as string
}

export async function joinCommunityByCode(code: string): Promise<string> {
  const { data, error } = await supabase.rpc('join_community_by_code', {
    _code: code.trim(),
  })
  if (error) throw error
  return data as string
}

export async function setGroupCommunity(
  groupId: string,
  communityId: string | null,
): Promise<void> {
  const { error } = await supabase.rpc('set_group_community', {
    _group: groupId,
    _community: communityId,
  })
  if (error) throw error
}

export async function renameGroup(groupId: string, name: string): Promise<void> {
  const { error } = await supabase.rpc('rename_group', {
    _group: groupId,
    _name: name,
  })
  if (error) throw error
}

export async function renameCommunity(
  communityId: string,
  name: string,
): Promise<void> {
  const { error } = await supabase.rpc('rename_community', {
    _community: communityId,
    _name: name,
  })
  if (error) throw error
}

export async function leaveGroup(groupId: string): Promise<void> {
  const uid = await requireUid()
  const { error } = await supabase
    .from('group_members')
    .delete()
    .eq('group_id', groupId)
    .eq('user_id', uid)
  if (error) throw error
}

export async function setMonitoringDirection(
  groupId: string,
  patch: { monitored?: boolean; watching?: boolean },
): Promise<void> {
  await requireUid()
  const { error } = await supabase.rpc('set_monitoring_direction', {
    _group: groupId,
    _monitored: patch.monitored ?? null,
    _watching: patch.watching ?? null,
  })
  if (error) throw error
}

export async function listGroupMembers(
  groupId: string,
): Promise<GroupMemberView[]> {
  // 注意：group_members.user_id 外键指向 auth.users 而非 profiles，
  // 无法用 PostgREST 内嵌；分两步查询再合并（RLS 允许读同组成员 profile）。
  const { data: members, error } = await supabase
    .from('group_members')
    .select('user_id, role, monitored, watching')
    .eq('group_id', groupId)
  if (error) throw error
  const rows = members ?? []
  if (rows.length === 0) return []

  const ids = rows.map((m) => m.user_id)
  const { data: profs, error: pErr } = await supabase
    .from('profiles')
    .select('id, display_name')
    .in('id', ids)
  if (pErr) throw pErr
  const nameById = new Map(
    (profs ?? []).map((p) => [p.id, p.display_name] as const),
  )

  return rows.map((r) => ({
    user_id: r.user_id,
    role: r.role,
    monitored: r.monitored,
    watching: r.watching,
    display_name: nameById.get(r.user_id) ?? null,
  }))
}

// ── Admin actions ─────────────────────────────────────────

export async function deleteCommunity(communityId: string): Promise<void> {
  const { error } = await supabase
    .from('communities')
    .delete()
    .eq('id', communityId)
  if (error) throw error
}

export async function deleteGroup(groupId: string): Promise<void> {
  const { error } = await supabase
    .from('groups')
    .delete()
    .eq('id', groupId)
  if (error) throw error
}

export async function promoteGroupMemberToAdmin(
  groupId: string,
  userId: string,
): Promise<void> {
  const { error } = await supabase
    .from('group_members')
    .update({ role: 'admin' })
    .eq('group_id', groupId)
    .eq('user_id', userId)
  if (error) throw error
}

export async function promoteCommunityMemberToAdmin(
  communityId: string,
  userId: string,
): Promise<void> {
  const { error } = await supabase
    .from('community_members')
    .update({ role: 'admin' })
    .eq('community_id', communityId)
    .eq('user_id', userId)
  if (error) throw error
}

export async function listCommunityMembers(
  communityId: string,
): Promise<{ user_id: string; role: string; display_name: string | null }[]> {
  const { data: members, error } = await supabase
    .from('community_members')
    .select('user_id, role')
    .eq('community_id', communityId)
  if (error) throw error
  const rows = members ?? []
  if (rows.length === 0) return []

  const ids = rows.map((m) => m.user_id)
  const { data: profs, error: pErr } = await supabase
    .from('profiles')
    .select('id, display_name')
    .in('id', ids)
  if (pErr) throw pErr
  const nameById = new Map(
    (profs ?? []).map((p) => [p.id, p.display_name] as const),
  )

  return rows.map((r) => ({
    user_id: r.user_id,
    role: r.role,
    display_name: nameById.get(r.user_id) ?? null,
  }))
}

