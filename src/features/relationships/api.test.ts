import { beforeEach, describe, expect, it, vi } from 'vitest'

const getUser = vi.fn()
const getSession = vi.fn()
const rpc = vi.fn()
const deleteQuery = {
  delete: vi.fn(),
  eq: vi.fn(),
  select: vi.fn(),
}
const from = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser, getSession },
    rpc,
    from,
  },
}))

const { leaveGroup, setMonitoringDirection } = await import('@/features/relationships/api')

describe('relationship api', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getUser.mockResolvedValue({ data: { user: { id: 'user-1' } } })
    // requireUid reads the cached session rather than round-tripping to getUser,
    // so WKWebView cold starts do not fail on a network hop.
    getSession.mockResolvedValue({ data: { session: { user: { id: 'user-1' } } } })
    rpc.mockResolvedValue({ error: null })
    deleteQuery.delete.mockReturnValue(deleteQuery)
    deleteQuery.eq.mockReturnValue(deleteQuery)
    deleteQuery.select.mockResolvedValue({ data: [{ group_id: 'group-1' }], error: null })
    from.mockReturnValue(deleteQuery)
  })

  it('sends false monitored values through the monitoring direction RPC', async () => {
    await setMonitoringDirection('group-1', { monitored: false })

    expect(rpc).toHaveBeenCalledWith('set_monitoring_direction', {
      _group: 'group-1',
      _monitored: false,
      _watching: undefined,
    })
  })

  it('sends false watching values through the monitoring direction RPC', async () => {
    await setMonitoringDirection('group-1', { watching: false })

    expect(rpc).toHaveBeenCalledWith('set_monitoring_direction', {
      _group: 'group-1',
      _monitored: undefined,
      _watching: false,
    })
  })

  it('throws when leaving a group deletes no membership row', async () => {
    deleteQuery.select.mockResolvedValue({ data: [], error: null })

    await expect(leaveGroup('group-1')).rejects.toThrow(/already left/i)
  })

  it('checks guardian status requiring active status in guardianships', async () => {
    const { checkIsGuardian } = await import('@/features/relationships/api')

    // Self check returns true immediately
    expect(await checkIsGuardian('user-1')).toBe(true)

    // Active status query
    const guardianQuery = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      maybeSingle: vi.fn().mockResolvedValue({ data: { id: 'g-1' }, error: null }),
    }
    from.mockReturnValue(guardianQuery)

    const isGuardian = await checkIsGuardian('ward-1')
    expect(isGuardian).toBe(true)
    expect(guardianQuery.eq).toHaveBeenCalledWith('status', 'active')
  })
})
