import { beforeEach, describe, expect, it, vi } from 'vitest'

const { mockGetUser, mockRpc } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockRpc: vi.fn(),
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  },
}))

import {
  createMyDailyTask,
  createTaskForWard,
  updateTaskForWard,
  respondTask,
} from './api'

describe('tasks api - wall clock time (TDD RED)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockGetUser.mockResolvedValue({ data: { user: { id: 'user-1' } } })
    mockRpc.mockResolvedValue({ error: null })
  })

  it('createMyDailyTask sends create_checkin_task payload with _due_time_local and no timezone-converted daily value / no _first_due', async () => {
    await createMyDailyTask('08:30', 'Morning checkin')

    expect(mockRpc).toHaveBeenCalledWith('create_checkin_task', {
      _ward: 'user-1',
      _kind: 'daily',
      _due_time_local: '08:30',
      _label: 'Morning checkin',
    })

    const callArgs = mockRpc.mock.calls[0][1]
    expect(callArgs).not.toHaveProperty('_due_time_utc')
    expect(callArgs).not.toHaveProperty('_first_due')
  })

  it('createTaskForWard daily branch sends create_checkin_task payload with _due_time_local and no timezone-converted daily value / no _first_due', async () => {
    await createTaskForWard('ward-123', {
      kind: 'daily',
      localHHMM: '14:15',
      label: 'Afternoon task',
    })

    expect(mockRpc).toHaveBeenCalledWith('create_checkin_task', {
      _ward: 'ward-123',
      _kind: 'daily',
      _due_time_local: '14:15',
      _label: 'Afternoon task',
    })

    const callArgs = mockRpc.mock.calls[0][1]
    expect(callArgs).not.toHaveProperty('_due_time_utc')
    expect(callArgs).not.toHaveProperty('_first_due')
  })

  it('updateTaskForWard daily branch sends update_checkin_task payload with _due_time_local and no timezone-converted daily value / no _first_due', async () => {
    await updateTaskForWard('task-456', {
      kind: 'daily',
      localHHMM: '18:45',
      label: 'Evening update',
    })

    expect(mockRpc).toHaveBeenCalledWith('update_checkin_task', {
      _task: 'task-456',
      _kind: 'daily',
      _due_time_local: '18:45',
      _label: 'Evening update',
    })

    const callArgs = mockRpc.mock.calls[0][1]
    expect(callArgs).not.toHaveProperty('_due_time_utc')
    expect(callArgs).not.toHaveProperty('_first_due')
  })

  it('respondTask for a daily task calls respond_checkin_task without _first_due', async () => {
    const dailyTask = {
      id: 'task-789',
      kind: 'daily',
      due_time_local: '08:00',
      due_time_utc: '00:00:00',
      ward_id: 'user-1',
      created_by: 'guardian-1',
      status: 'pending',
      label: 'Morning checkin',
    } as any

    await respondTask(dailyTask, true)

    expect(mockRpc).toHaveBeenCalledWith('respond_checkin_task', {
      _task: 'task-789',
      _accept: true,
    })

    const callArgs = mockRpc.mock.calls[0][1]
    expect(callArgs).not.toHaveProperty('_first_due')
  })

  // 5. The display contract uses due_time_local verbatim.
  // Note: No existing pure helper or exported seam exists for formatting/displaying due_time_local in api.ts
  // (the UI components currently call utcTimeToLocal(task.due_time_utc) directly).
  // Therefore, no helper test is added to avoid editing production code to manufacture a seam in RED phase.
})
