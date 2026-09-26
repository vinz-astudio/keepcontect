import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc, emitAlertChange } = vi.hoisted(() => ({
  rpc: vi.fn(),
  emitAlertChange: vi.fn(),
}))
vi.mock('@/lib/supabase', () => ({ supabase: { rpc } }))
vi.mock('./alertBus', () => ({ emitAlertChange }))

import { acknowledgeSafe } from './api'

describe('acknowledgeSafe', () => {
  beforeEach(() => vi.resetAllMocks())

  it('rejects an unscoped confirmation before issuing an RPC', async () => {
    await expect(acknowledgeSafe()).rejects.toThrow('alert_id_required')
    expect(rpc).not.toHaveBeenCalled()
  })

  it('reports success after the server clears the alert', async () => {
    rpc.mockResolvedValue({ data: { ok: true, cleared_alert: true }, error: null })
    await expect(acknowledgeSafe('alert-1')).resolves.toBe(true)
    expect(rpc).toHaveBeenCalledWith('acknowledge_safe', { _alert_id: 'alert-1' })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(emitAlertChange).toHaveBeenCalledTimes(1)
  })

  it('accepts an already-resolved alert without targeting a newer one', async () => {
    rpc.mockResolvedValue({ data: { ok: true, already_resolved: true }, error: null })
    await expect(acknowledgeSafe('alert-old')).resolves.toBe(true)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(emitAlertChange).toHaveBeenCalledTimes(1)
  })

  it('does not claim success when both confirmation calls fail', async () => {
    rpc.mockResolvedValue({ data: null, error: new Error('not authenticated') })
    await expect(acknowledgeSafe('alert-1')).rejects.toThrow('not authenticated')
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(emitAlertChange).not.toHaveBeenCalled()
  })

  it('propagates a network failure instead of claiming the alert was cleared', async () => {
    rpc.mockRejectedValue(new Error('offline'))
    await expect(acknowledgeSafe('alert-1')).rejects.toThrow('offline')
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(emitAlertChange).not.toHaveBeenCalled()
  })

  it('does not accept cleared_alert when the response explicitly rejects the action', async () => {
    rpc.mockResolvedValueOnce({ data: { ok: false, cleared_alert: true }, error: null })
    await expect(acknowledgeSafe('alert-1')).rejects.toThrow('confirmation rejected')
    expect(emitAlertChange).not.toHaveBeenCalled()
  })

  it('does not fall back around a guardian pattern requirement', async () => {
    rpc.mockResolvedValue({ error: new Error('pattern_required') })
    await expect(acknowledgeSafe('alert-1')).rejects.toThrow('pattern_required')
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(emitAlertChange).not.toHaveBeenCalled()
  })

  it('sends an entered pattern to the server for verification', async () => {
    rpc.mockResolvedValue({ data: { ok: true, cleared_alert: true }, error: null })
    await expect(acknowledgeSafe('alert-1', [0,1,2,5])).resolves.toBe(true)
    expect(rpc).toHaveBeenCalledWith('acknowledge_safe_with_pattern', { _alert_id: 'alert-1', _pattern: [0,1,2,5] })
  })
})
