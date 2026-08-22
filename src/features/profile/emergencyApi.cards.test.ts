import { describe, expect, it, vi, beforeEach } from 'vitest'
import { parseContactsJson, parseAddressesJson, getEmergencyCardsForUser } from './emergencyApi'
import { supabase } from '@/lib/supabase'

describe('emergencyApi structured json parser and card redaction', () => {
  beforeEach(() => {
    const store: Record<string, string> = {}
    const mockStorage = {
      getItem: (k: string) => store[k] ?? null,
      setItem: (k: string, v: string) => { store[k] = v },
      removeItem: (k: string) => { delete store[k] },
      clear: () => { Object.keys(store).forEach(k => delete store[k]) },
      length: 0,
      key: () => null,
    }
    vi.stubGlobal('localStorage', mockStorage)
  })

  it('parses JSON contact array strings correctly', () => {
    const rawJson = JSON.stringify([
      { id: 'c1', name: 'Mom', phone: '+1234567890', relationship: 'Mother', isPrimary: true },
      { id: 'c2', name: 'Dad', phone: '+0987654321', relationship: 'Father', isPrimary: false },
    ])
    const parsed = parseContactsJson(rawJson, '+1234567890')
    expect(parsed).toHaveLength(2)
    expect(parsed[0].name).toBe('Mom')
    expect(parsed[0].phone).toBe('+1234567890')
    expect(parsed[1].name).toBe('Dad')
  })

  it('returns empty array for empty JSON array without creating legacy junk card', () => {
    expect(parseAddressesJson('[]')).toEqual([])
    expect(parseContactsJson('[]', '')).toEqual([])
  })

  it('falls back to single contact for legacy plain string name', () => {
    const parsed = parseContactsJson('Alice Wang', '13800138000')
    expect(parsed).toHaveLength(1)
    expect(parsed[0].name).toBe('Alice Wang')
    expect(parsed[0].phone).toBe('13800138000')
  })

  it('parses JSON address array strings correctly', () => {
    const rawJson = JSON.stringify([
      { id: 'a1', label: 'Home', address: '123 Main St', accessCode: '9988', isPrimary: true },
      { id: 'a2', label: 'Office', address: '456 Market St', accessCode: '', isPrimary: false },
    ])
    const parsedGuardian = parseAddressesJson(rawJson, true)
    expect(parsedGuardian).toHaveLength(2)
    expect(parsedGuardian[0].label).toBe('Home')
    expect(parsedGuardian[0].accessCode).toBe('9988')
    expect(parsedGuardian[1].label).toBe('Office')

    const parsedNonGuardian = parseAddressesJson(rawJson, false)
    expect(parsedNonGuardian[0].accessCode).toBeUndefined()
  })


  it('safely handles malformed contact shapes without throwing', () => {
    const malformed = JSON.stringify([
      { id: 'c1', name: 12345, phone: '+1234567890' },
      { id: 'c2', name: { nested: 'obj' }, phone: 999 },
      null,
      'just-a-string',
    ])
    const parsed = parseContactsJson(malformed, '+1234567890')
    expect(Array.isArray(parsed)).toBe(true)
  })

  it('tests getEmergencyCardsForUser real door access code redaction', async () => {
    const mockRow = {
      user_id: '00000000-0000-4000-8000-000000000001',
      emergency_contact_name: JSON.stringify([{ id: 'c1', name: 'Bob', phone: '111222' }]),
      emergency_contact_phone: '111222',
      home_address: JSON.stringify([{ id: 'a1', label: 'Home', address: '123 Safe St', accessCode: 'Door-9988' }]),
      medical_notes: 'Asthma',
      latitude: 37.7749,
      longitude: -122.4194,
      location_accuracy: 5,
      location_updated_at: '2026-08-21T00:00:00Z',
    }

    vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
      data: { session: { user: { id: '00000000-0000-4000-8000-000000000001' } } },
      error: null,
    } as any)

    const createChainableMock = (data: any) => {
      const builder: any = {
        select: () => builder,
        eq: () => builder,
        maybeSingle: async () => ({ data, error: null }),
      }
      return builder
    }

    vi.spyOn(supabase, 'from').mockImplementation((table: string) => {
      if (table === 'emergency_info') return createChainableMock(mockRow)
      return createChainableMock(null)
    })

    // Non-guardian responder session:
    vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
      data: { session: { user: { id: '00000000-0000-4000-8000-000000000002' } } },
      error: null,
    } as any)

    const nonGuardianResult = await getEmergencyCardsForUser('00000000-0000-4000-8000-000000000001')
    expect(nonGuardianResult).not.toBeNull()
    expect(nonGuardianResult!.addresses[0].address).toBe('123 Safe St')
    expect(Object.hasOwn(nonGuardianResult!.addresses[0], 'accessCode')).toBe(false)
    expect(nonGuardianResult!.medicalNotes).toBe('Asthma')
    expect(nonGuardianResult!.latitude).toBe(37.7749)


    // Active guardian responder session:
    vi.spyOn(supabase, 'from').mockImplementation((table: string) => {
      if (table === 'emergency_info') return createChainableMock(mockRow)
      if (table === 'guardianships') return createChainableMock({ id: 'g1' })
      return createChainableMock(null)
    })

    const guardianResult = await getEmergencyCardsForUser('00000000-0000-4000-8000-000000000001')
    expect(guardianResult).not.toBeNull()
    expect(guardianResult!.addresses[0].address).toBe('123 Safe St')
    expect(guardianResult!.addresses[0].accessCode).toBe('Door-9988')
    expect(guardianResult!.medicalNotes).toBe('Asthma')

    // No emergency_info row exists:
    vi.spyOn(supabase, 'from').mockImplementation(() => createChainableMock(null))
    const nullResult = await getEmergencyCardsForUser('00000000-0000-4000-8000-000000000001')
    expect(nullResult).toBeNull()
  })

  it('guarantees live GPS coordinates and fallback emergency data remain independent', async () => {
    const liveGPSOnlyRow = {
      user_id: '00000000-0000-4000-8000-000000000001',
      emergency_contact_name: null,
      emergency_contact_phone: null,
      home_address: null,
      medical_notes: null,
      latitude: 31.2304,
      longitude: 121.4737,
      location_accuracy: 10,
      location_updated_at: '2026-08-21T12:00:00Z',
    }

    const createChainableMock = (data: any) => {
      const builder: any = {
        select: () => builder,
        eq: () => builder,
        maybeSingle: async () => ({ data, error: null }),
      }
      return builder
    }

    vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
      data: { session: { user: { id: '00000000-0000-4000-8000-000000000002' } } },
      error: null,
    } as any)

    vi.spyOn(supabase, 'from').mockImplementation((table: string) => {
      if (table === 'emergency_info') return createChainableMock(liveGPSOnlyRow)
      return createChainableMock(null)
    })

    const payload = await getEmergencyCardsForUser('00000000-0000-4000-8000-000000000001')
    expect(payload).not.toBeNull()
    expect(payload!.latitude).toBe(31.2304)
    expect(payload!.longitude).toBe(121.4737)
    expect(payload!.contacts).toEqual([])
    expect(payload!.addresses).toEqual([])
  })
})
