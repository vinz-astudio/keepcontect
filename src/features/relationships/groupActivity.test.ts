import { beforeEach, describe, expect, it, vi } from 'vitest'

const rpc = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc },
}))

const { getGroupActivity } = await import('@/features/relationships/groupActivity')

describe('group activity api', () => {
  beforeEach(() => {
    rpc.mockReset()
  })

  it('requests the scoped watch view for Watch page data', async () => {
    rpc.mockResolvedValueOnce({
      data: { visibility: 'watchers_only', view: 'watch', members: [] },
      error: null,
    })

    await getGroupActivity('group-1', 'watch')

    expect(rpc).toHaveBeenCalledWith('get_group_activity_view', {
      _group: 'group-1',
      _view: 'watch',
    })
  })

  it('falls back to the legacy RPC while the migration is not deployed yet', async () => {
    rpc
      .mockResolvedValueOnce({
        data: null,
        error: { code: 'PGRST202', message: 'get_group_activity_view not found' },
      })
      .mockResolvedValueOnce({
        data: { visibility: 'group_wide', members: [] },
        error: null,
      })

    await getGroupActivity('group-1', 'group')

    expect(rpc).toHaveBeenNthCalledWith(1, 'get_group_activity_view', {
      _group: 'group-1',
      _view: 'group',
    })
    expect(rpc).toHaveBeenNthCalledWith(2, 'get_group_activity', {
      _group: 'group-1',
    })
  })
})
