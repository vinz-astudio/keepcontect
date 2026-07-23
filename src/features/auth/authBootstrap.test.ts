import { describe, expect, it, vi } from 'vitest'
import { bootstrapSession } from './authBootstrap'
import type { Session } from '@supabase/supabase-js'

describe('Bounded Auth Bootstrap (KCA-25)', () => {
  it('passes session through on success', async () => {
    const mockSession = { user: { id: 'user-123' } } as unknown as Session
    const getSession = vi.fn().mockResolvedValue({ data: { session: mockSession }, error: null })

    const result = await bootstrapSession(getSession, 100)

    expect(result.session).toBe(mockSession)
    expect(result.error).toBeNull()
    expect(result.timedOut).toBe(false)
  })

  it('returns error on getSession rejection', async () => {
    const getSession = vi.fn().mockRejectedValue(new Error('Network offline'))

    const result = await bootstrapSession(getSession, 100)

    expect(result.session).toBeNull()
    expect(result.error).toBeInstanceOf(Error)
    expect((result.error as Error).message).toBe('Network offline')
    expect(result.timedOut).toBe(false)
  })

  it('returns error when supabase returns a structured error', async () => {
    const getSession = vi.fn().mockResolvedValue({ data: { session: null }, error: new Error('Auth server error') })

    const result = await bootstrapSession(getSession, 100)

    expect(result.session).toBeNull()
    expect(result.error).toBeInstanceOf(Error)
    expect((result.error as Error).message).toBe('Auth server error')
    expect(result.timedOut).toBe(false)
  })

  it('resolves with timedOut=true when getSession hangs', async () => {
    // A promise that never resolves
    const getSession = vi.fn().mockReturnValue(new Promise(() => {}))

    const result = await bootstrapSession(getSession, 50)

    expect(result.session).toBeNull()
    expect(result.error).toBeNull()
    expect(result.timedOut).toBe(true)
  })
})
