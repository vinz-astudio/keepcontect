import { supabase } from '@/lib/supabase'

export interface GuardianLink {
  id: string
  otherUserId: string
  otherName: string | null
  direction: 'i_guard' | 'guards_me'
  status: string
  requirePattern: boolean
}

async function requireUid(): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession()
  const uid = session?.user?.id
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
  const { data: policies, error: policyError } = await supabase.rpc('my_guardian_pattern_requirements' as never)
  if (policyError) throw policyError
  const patternByLink = new Map(
    ((policies ?? []) as { guardianship_id: string; require_pattern: boolean }[])
      .map((p) => [p.guardianship_id, p.require_pattern]),
  )

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
      requirePattern: patternByLink.get(r.id) === true,
    }
  })
}

export async function setGuardianPatternRequirement(id: string, required: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_guardian_pattern_requirement' as never,
    { _guardianship_id: id, _required: required } as never)
  if (error) {
    if (error.message?.includes('ward_pattern_not_set')) {
      throw new Error(localStorage.getItem('kc.lang') === 'en'
        ? 'Ask this person to set a pattern in Me first.' : '请先让对方在“我”页面设置手势。')
    }
    throw error
  }
}

export async function revokeGuardianship(id: string): Promise<void> {
  const { error } = await supabase.from('guardianships').delete().eq('id', id)
  if (error) throw error
}
