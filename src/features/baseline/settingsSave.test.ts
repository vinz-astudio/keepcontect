import { describe, expect, it, vi, beforeEach } from 'vitest'

// Mock supabase client
vi.mock('@/lib/supabase', () => {
  return {
    supabase: {
      rpc: vi.fn(),
      from: vi.fn(() => ({
        select: vi.fn(() => ({
          eq: vi.fn(() => ({
            maybeSingle: vi.fn(),
            single: vi.fn()
          }))
        })),
        update: vi.fn(() => ({
          eq: vi.fn(() => Promise.resolve({ error: new Error('Database Error') as any }))
        }))
      })),
      auth: {
        getUser: vi.fn(() => Promise.resolve({ data: { user: { id: 'test-user-id' } } }))
      }
    }
  }
})

// Mock profileApi functions
vi.mock('@/features/profile/profileApi', () => {
  return {
    updateRoutineProfile: vi.fn(() => Promise.reject(new Error('Update Profile Error')))
  }
})

import { supabase } from '@/lib/supabase'
import { updateRoutineProfile } from '@/features/profile/profileApi'
import {
  saveSensitivitySafe,
  saveSleepWindowSafe,
  clearSleepWindowSafe,
  updateRoutineProfileSafe,
} from './settingsApi'

describe('Transparent Settings Saves (KCA-18)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('reverts sensitivity and returns error on save failure', async () => {
    // Force rpc to fail
    const mockRpc = vi.mocked(supabase.rpc)
    mockRpc.mockResolvedValueOnce({ error: { message: 'RPC Error' } as any, data: null } as any)

    const result = await saveSensitivitySafe('high', 'balanced')

    expect(result.success).toBe(false)
    expect(result.value).toBe('balanced') // Reverted to fallback
    expect(result.error).toBe('RPC Error')
  })

  it('passes sensitivity through on success', async () => {
    const mockRpc = vi.mocked(supabase.rpc)
    mockRpc.mockResolvedValueOnce({ error: null, data: null } as any)

    const result = await saveSensitivitySafe('high', 'balanced')

    expect(result.success).toBe(true)
    expect(result.value).toBe('high')
    expect(result.error).toBeNull()
  })

  it('reverts sleep window and returns error on save failure', async () => {
    const mockRpc = vi.mocked(supabase.rpc)
    mockRpc.mockResolvedValueOnce({ error: { message: 'RPC Sleep Error' } as any, data: null } as any)

    const fallback = { start: '22:00', end: '06:00' }
    const result = await saveSleepWindowSafe('23:00', '07:00', fallback)

    expect(result.success).toBe(false)
    expect(result.value).toEqual(fallback) // Reverted to fallback
    expect(result.error).toBe('RPC Sleep Error')
  })

  it('reverts clear sleep window on save failure', async () => {
    const mockRpc = vi.mocked(supabase.rpc)
    mockRpc.mockResolvedValueOnce({ error: { message: 'RPC Clear Error' } as any, data: null } as any)

    const fallback = { start: '22:00', end: '06:00' }
    const result = await clearSleepWindowSafe(fallback)

    expect(result.success).toBe(false)
    expect(result.value).toEqual(fallback)
    expect(result.error).toBe('RPC Clear Error')
  })

  it('reverts routine profile updates (pattern / consent) on failure', async () => {
    const mockUpdate = vi.mocked(updateRoutineProfile)
    mockUpdate.mockRejectedValueOnce(new Error('API Profile Error'))

    const fallback = { routine_pattern: 'regular_9to5', consent_data_sharing: false }
    const result = await updateRoutineProfileSafe({ consent_data_sharing: true }, fallback)

    expect(result.success).toBe(false)
    expect(result.value).toEqual(fallback) // Reverted to fallback
    expect(result.error).toBe('API Profile Error')
  })
})
