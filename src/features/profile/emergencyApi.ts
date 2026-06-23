import { supabase } from '@/lib/supabase'
import type { Tables } from '@/lib/database.types'
import { encryptText, decryptText, deriveKeyFromPassword } from '@/lib/crypto'
import { listMyGroups, listGroupMembers } from '@/features/relationships/api'

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

export async function getEncryptionKey(userId: string): Promise<CryptoKey | null> {
  try {
    const groups = await listMyGroups()
    if (groups.length > 0) {
      const g = groups[0].group
      if (g.invite_code) {
        const salt = new TextEncoder().encode(g.id)
        return await deriveKeyFromPassword(g.invite_code, salt)
      }
    }
  } catch (e) {
    console.error('Failed to get group key:', e)
  }

  const patternHash = localStorage.getItem('kc.patternHash')
  if (patternHash) {
    const salt = new TextEncoder().encode(userId)
    return deriveKeyFromPassword(patternHash, salt)
  }
  return null
}

export async function getDecryptionKeyForUser(targetUserId: string): Promise<CryptoKey | null> {
  try {
    const groups = await listMyGroups()
    for (const g of groups) {
      const members = await listGroupMembers(g.group.id)
      if (members.some((m) => m.user_id === targetUserId)) {
        if (g.group.invite_code) {
          const salt = new TextEncoder().encode(g.group.id)
          return await deriveKeyFromPassword(g.group.invite_code, salt)
        }
      }
    }
  } catch (e) {
    console.error('Failed to get decryption key:', e)
  }

  // Fallback to personal pattern key if target is self
  const uid = await requireUid()
  if (targetUserId === uid) {
    const patternHash = localStorage.getItem('kc.patternHash')
    if (patternHash) {
      const salt = new TextEncoder().encode(uid)
      return deriveKeyFromPassword(patternHash, salt)
    }
  }
  return null
}

async function encryptField(value: string, key: CryptoKey | null): Promise<string | null> {
  if (!value) return null
  if (!key) return value
  const encrypted = await encryptText(value, key)
  return `__e2ee__:${JSON.stringify(encrypted)}`
}

async function decryptField(value: string | null, key: CryptoKey | null): Promise<string | null> {
  if (!value) return null
  if (!value.startsWith('__e2ee__:')) return value
  if (!key) return '[Encrypted]'
  try {
    const jsonStr = value.substring('__e2ee__:'.length)
    const { ciphertext, iv } = JSON.parse(jsonStr)
    return await decryptText(ciphertext, iv, key)
  } catch (e) {
    console.error('Failed to decrypt field:', e)
    return '[Decryption Failed]'
  }
}

export async function getEmergencyInfoForUser(targetUserId: string): Promise<EmergencyInfo | null> {
  const { data, error } = await supabase
    .from('emergency_info')
    .select('*')
    .eq('user_id', targetUserId)
    .maybeSingle()
  if (error) throw error
  if (!data) return null

  const key = await getDecryptionKeyForUser(targetUserId)
  return {
    ...data,
    home_address: await decryptField(data.home_address, key),
    medical_notes: await decryptField(data.medical_notes, key),
    emergency_contact_name: await decryptField(data.emergency_contact_name, key),
    emergency_contact_phone: await decryptField(data.emergency_contact_phone, key),
  }
}

export async function getEmergencyInfo(): Promise<EmergencyInfo | null> {
  const uid = await requireUid()
  return getEmergencyInfoForUser(uid)
}

export async function saveEmergencyInfo(input: EmergencyInfoInput): Promise<void> {
  const uid = await requireUid()
  const key = await getEncryptionKey(uid)

  const { error } = await supabase.from('emergency_info').upsert(
    {
      user_id: uid,
      home_address: await encryptField(input.home_address, key),
      medical_notes: await encryptField(input.medical_notes, key),
      emergency_contact_name: await encryptField(input.emergency_contact_name, key),
      emergency_contact_phone: await encryptField(input.emergency_contact_phone, key),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) throw error
}

export async function saveSOSLocation(
  lat: number,
  lng: number,
  accuracy: number,
): Promise<void> {
  const uid = await requireUid()
  const { error } = await supabase.from('emergency_info').upsert(
    {
      user_id: uid,
      latitude: lat,
      longitude: lng,
      location_accuracy: accuracy,
      location_updated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) throw error
}
