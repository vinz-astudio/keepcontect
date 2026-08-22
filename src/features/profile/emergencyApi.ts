import { supabase } from '@/lib/supabase'
import type { Tables } from '@/lib/database.types'
import { encryptText, decryptText, deriveKeyFromPassword } from '@/lib/crypto'
import { listMyGroups, listGroupMembers } from '@/features/relationships/api'
import { getPatternHash } from '@/features/pattern/patternStore'

export type EmergencyInfo = Tables<'emergency_info'>

export interface EmergencyInfoInput {
  home_address: string
  medical_notes: string
  emergency_contact_name: string
  emergency_contact_phone: string
}

async function requireUid(): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession()
  const uid = session?.user?.id
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

  // KCA-04：手势哈希按账户命名空间读取，绝不用他人（或无主遗留）哈希派生密钥。
  const patternHash = getPatternHash(userId)
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

  // Fallback to personal pattern key only when the target is the current user,
  // reading that user's own namespaced hash (KCA-04).
  const uid = await requireUid()
  if (targetUserId === uid) {
    const patternHash = getPatternHash(uid)
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

async function fetchAndDecryptEmergencyData(
  targetUserId: string,
  isGuardian: boolean,
): Promise<EmergencyCardsPayload | null> {
  const { data, error } = await supabase
    .from('emergency_info')
    .select('*')
    .eq('user_id', targetUserId)
    .maybeSingle()
  if (error) throw error
  if (!data) return null

  const key = await getDecryptionKeyForUser(targetUserId)
  const decryptedContactName = await decryptField(data.emergency_contact_name, key)
  const decryptedContactPhone = await decryptField(data.emergency_contact_phone, key)
  const decryptedHomeAddress = await decryptField(data.home_address, key)
  const decryptedMedicalNotes = await decryptField(data.medical_notes, key)

  const contacts = parseContactsJson(decryptedContactName, decryptedContactPhone)
  const addresses = parseAddressesJson(decryptedHomeAddress, isGuardian)

  return {
    contacts,
    addresses,
    medicalNotes: decryptedMedicalNotes ?? '',
    latitude: data.latitude,
    longitude: data.longitude,
    location_accuracy: data.location_accuracy,
    location_updated_at: data.location_updated_at,
  }

}


export interface ContactCardItem {
  id?: string
  name: string
  phone: string
  relationship?: string
  isPrimary?: boolean
  ordinal?: number
}

export interface AddressCardItem {
  id?: string
  label: string
  address: string
  accessCode?: string
  isPrimary?: boolean
  ordinal?: number
}

export interface EmergencyCardsPayload {
  contacts: ContactCardItem[]
  addresses: AddressCardItem[]
  medicalNotes: string
  latitude?: number | null
  longitude?: number | null
  location_accuracy?: number | null
  location_updated_at?: string | null
}


export function parseContactsJson(nameStr: string | null | undefined, phoneStr: string | null | undefined): ContactCardItem[] {
  if (!nameStr && !phoneStr) return []
  const trimmed = (nameStr || '').trim()
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    try {
      const parsed = JSON.parse(trimmed)
      if (Array.isArray(parsed)) {
        return parsed
          .filter((item) => item && typeof item === 'object' && typeof item.name === 'string')
          .map((item, idx) => ({
            id: typeof item.id === 'string' ? item.id : `contact-${idx + 1}`,
            name: String(item.name || ''),
            phone: typeof item.phone === 'string' ? item.phone : '',
            relationship: typeof item.relationship === 'string' ? item.relationship : 'Contact',
            isPrimary: Boolean(item.isPrimary),
            ordinal: typeof item.ordinal === 'number' ? item.ordinal : idx,
          }))
      }
    } catch {
      /* fallback to legacy string below */
    }
  }

  if (!nameStr && !phoneStr) return []
  return [
    {
      id: 'contact-1',
      name: String(nameStr || 'Emergency Contact'),
      phone: String(phoneStr || ''),
      relationship: 'Primary Responder',
      isPrimary: true,
      ordinal: 0,
    },
  ]
}

export function parseAddressesJson(addrStr: string | null | undefined, isGuardian = false): AddressCardItem[] {
  if (!addrStr) return []
  const trimmed = addrStr.trim()
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    try {
      const parsed = JSON.parse(trimmed)
      if (Array.isArray(parsed)) {
        return parsed
          .filter((item) => item && typeof item === 'object' && typeof item.address === 'string')
          .map((item, idx) => {
            const card: AddressCardItem = {
              id: typeof item.id === 'string' ? item.id : `addr-${idx + 1}`,
              label: typeof item.label === 'string' ? item.label : 'Home',
              address: String(item.address || ''),
              isPrimary: Boolean(item.isPrimary),
              ordinal: typeof item.ordinal === 'number' ? item.ordinal : idx,
            }
            if (isGuardian && typeof item.accessCode === 'string' && item.accessCode.length > 0) {
              card.accessCode = item.accessCode
            }
            return card
          })
      }
    } catch {
      /* fallback to legacy string below */
    }
  }

  if (!addrStr.trim()) return []
  return [
    {
      id: 'addr-1',
      label: 'Home',
      address: String(addrStr),
      isPrimary: true,
      ordinal: 0,
    },
  ]
}


export async function getEmergencyCards(): Promise<EmergencyCardsPayload> {
  const info = await getEmergencyInfo()
  return {
    contacts: parseContactsJson(info?.emergency_contact_name, info?.emergency_contact_phone),
    addresses: parseAddressesJson(info?.home_address, true),
    medicalNotes: info?.medical_notes ?? '',
  }
}

export async function getEmergencyCardsForUser(
  targetUserId: string,
): Promise<EmergencyCardsPayload | null> {
  const { checkIsGuardian } = await import('@/features/relationships/api')
  const isGuardian = await checkIsGuardian(targetUserId)
  return fetchAndDecryptEmergencyData(targetUserId, isGuardian)
}





export async function saveEmergencyCards(
  contacts: ContactCardItem[],
  addresses: AddressCardItem[],
  medicalNotes: string,
): Promise<void> {
  const uid = await requireUid()
  const key = await getEncryptionKey(uid)

  const serializedContacts = contacts.length === 1 && !contacts[0].relationship && !contacts[0].isPrimary
    ? contacts[0].name
    : JSON.stringify(contacts)

  const serializedAddresses = addresses.length === 1 && !addresses[0].accessCode && addresses[0].label === 'Home'
    ? addresses[0].address
    : JSON.stringify(addresses)

  const primaryPhone = contacts.find((c) => c.isPrimary)?.phone || contacts[0]?.phone || ''

  const { error } = await supabase.from('emergency_info').upsert(
    {
      user_id: uid,
      emergency_contact_name: await encryptField(serializedContacts, key),
      emergency_contact_phone: await encryptField(primaryPhone, key),
      home_address: await encryptField(serializedAddresses, key),
      medical_notes: await encryptField(medicalNotes, key),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) throw error
}

export async function getEmergencyInfo(): Promise<EmergencyInfo | null> {
  const uid = await requireUid()
  const { data, error } = await supabase
    .from('emergency_info')
    .select('*')
    .eq('user_id', uid)
    .maybeSingle()
  if (error) throw error
  if (!data) return null

  const key = await getEncryptionKey(uid)
  return {
    ...data,
    home_address: await decryptField(data.home_address, key),
    medical_notes: await decryptField(data.medical_notes, key),
    emergency_contact_name: await decryptField(data.emergency_contact_name, key),
    emergency_contact_phone: await decryptField(data.emergency_contact_phone, key),
  }
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
