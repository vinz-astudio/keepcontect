import { supabase } from '@/lib/supabase'
import type { Tables } from '@/lib/database.types'

export type EmergencyInfo = Tables<'emergency_info'>

export interface EmergencyInfoInput {
  home_address: string
  medical_notes: string
  emergency_contact_name: string
  emergency_contact_phone: string
}

async function requireUid(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const uid = data.user?.id
  if (!uid) throw new Error('未登录')
  return uid
}

export async function getEmergencyInfo(): Promise<EmergencyInfo | null> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('emergency_info')
    .select('*')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function saveEmergencyInfo(
  input: EmergencyInfoInput,
): Promise<void> {
  const uid = await requireUid()
  const { error } = await supabase.from('emergency_info').upsert(
    {
      user_id: uid,
      home_address: input.home_address || null,
      medical_notes: input.medical_notes || null,
      emergency_contact_name: input.emergency_contact_name || null,
      emergency_contact_phone: input.emergency_contact_phone || null,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) throw error
}
