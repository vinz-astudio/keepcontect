import { beforeEach, describe, expect, it, vi } from 'vitest'

const getUser = vi.fn()
const rpc = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser },
    rpc,
  },
}))

const { setMonitoringDirection } = await import('@/features/relationships/api')

describe('relationship api', () => {
  beforeEach(() => {
    getUser.mockResolvedValue({ data: { user: { id: 'user-1' } } })
    rpc.mockResolvedValue({ error: null })
  })

  it('sends false monitored values through the monitoring direction RPC', async () => {
    await setMonitoringDirection('group-1', { monitored: false })

    expect(rpc).toHaveBeenCalledWith('set_monitoring_direction', {
      _group: 'group-1',
      _monitored: false,
      _watching: null,
    })
  })

  it('sends false watching values through the monitoring direction RPC', async () => {
    await setMonitoringDirection('group-1', { watching: false })

    expect(rpc).toHaveBeenCalledWith('set_monitoring_direction', {
      _group: 'group-1',
      _monitored: null,
      _watching: false,
    })
  })
})
