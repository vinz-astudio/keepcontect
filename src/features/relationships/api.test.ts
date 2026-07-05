import { beforeEach, describe, expect, it, vi } from 'vitest'

const getUser = vi.fn()
const rpc = vi.fn()
const deleteQuery = {
  delete: vi.fn(),
  eq: vi.fn(),
  select: vi.fn(),
}
const from = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser },
    rpc,
    from,
  },
}))

const { leaveGroup, setMonitoringDirection } = await import('@/features/relationships/api')

describe('relationship api', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getUser.mockResolvedValue({ data: { user: { id: 'user-1' } } })
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
})
