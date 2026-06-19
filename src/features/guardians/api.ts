import { supabase } from '@/lib/supabase'

export interface GuardianLink {
  id: string
  otherUserId: string
  otherName: string | null
  direction: 'i_guard' | 'guards_me'
  status: string
}

async function requireUid(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const uid = data.user?.id
  if (!uid) throw new Error('未登录')
  return uid
}

export async function getMyGuardianCode(): Promise<string> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('profiles')
    .select('guardian_code')
    .eq('id', uid)
    .single()
  if (error) throw error
  return data.guardian_code
}

export async function becomeGuardianByCode(code: string): Promise<string> {
  const { data, error } = await supabase.rpc('become_guardian_by_code', {
    _code: code.trim(),
  })
  if (error) throw error
  return data as string
}

export async function listGuardianships(): Promise<GuardianLink[]> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('guardianships')
    .select('id, guardian_id, ward_id, status')
    .or(`guardian_id.eq.${uid},ward_id.eq.${uid}`)
  if (error) throw error
  const rows = data ?? []
  if (rows.length === 0) return []

  const otherIds = rows.map((r) =>
    r.guardian_id === uid ? r.ward_id : r.guardian_id,
  )
  const { data: profs, error: pErr } = await supabase
    .from('profiles')
    .select('id, display_name')
    .in('id', otherIds)
  if (pErr) throw pErr
  const nameById = new Map(
    (profs ?? []).map((p) => [p.id, p.display_name] as const),
  )

  return rows.map((r) => {
    const iGuard = r.guardian_id === uid
    const otherUserId = iGuard ? r.ward_id : r.guardian_id
    return {
      id: r.id,
      otherUserId,
      otherName: nameById.get(otherUserId) ?? null,
      direction: iGuard ? 'i_guard' : 'guards_me',
      status: r.status,
    }
  })
}

export async function revokeGuardianship(id: string): Promise<void> {
  const { error } = await supabase.from('guardianships').delete().eq('id', id)
  if (error) throw error
}
