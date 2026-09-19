import { describe, expect, it, vi } from 'vitest'
import { createPwaEvidenceCollector } from './pwaEvidence'

function harness() {
  let owner: string | null = 'alice'
  let now = Date.parse('2026-09-19T00:00:00Z')
  const send = vi.fn().mockResolvedValue('inserted')
  const bind = vi.fn().mockResolvedValue({ bindingId: 'binding-alice' })
  const revoke = vi.fn().mockResolvedValue(true)
  const deps = {
    eligible: () => true, visible: () => true, getUserId: async () => owner,
    now: () => now, randomUUID: () => 'event-1', instanceId: 'pwa-instance',
    bind, send, revoke,
  }
  return { deps, send, bind, revoke, setOwner: (value: string | null) => { owner = value }, advance: (ms: number) => { now += ms } }
}

describe('qualified PWA evidence', () => {
  it('emits nothing on boot/retry, synthetic events or hidden interaction', async () => {
    const h = harness()
    const collector = createPwaEvidenceCollector('alice', h.deps)
    await collector.retry()
    await collector.interaction(false)
    h.deps.visible = () => false
    await collector.interaction(true)
    expect(h.bind).not.toHaveBeenCalled()
    expect(h.send).not.toHaveBeenCalled()
  })

  it('binds deliberate interaction to its account and sends normalized evidence', async () => {
    const h = harness()
    const collector = createPwaEvidenceCollector('alice', h.deps)
    await collector.interaction(true)
    expect(h.bind).toHaveBeenCalledWith('pwa-instance', 'pwa_browser', expect.any(String))
    expect(h.send).toHaveBeenCalledWith('binding-alice', expect.objectContaining({
      eventId: 'event-1', sequence: 0, observedAt: '2026-09-19T00:00:00.000Z',
      evidenceClass: 'direct_device_use', qualificationFacts: { interaction: true },
    }))
    await collector.interaction(true)
    expect(h.send).toHaveBeenCalledTimes(1)
  })

  it('retries network failure with the original event, never a retry-time activity', async () => {
    const h = harness()
    h.send.mockRejectedValueOnce(new Error('offline'))
    const collector = createPwaEvidenceCollector('alice', h.deps)
    await collector.interaction(true)
    h.advance(60_000)
    await collector.retry()
    expect(h.send).toHaveBeenCalledTimes(2)
    expect(h.send.mock.calls[1]).toEqual(h.send.mock.calls[0])
  })

  it('drops stale PWA evidence and never transfers a queued event to a different account', async () => {
    const h = harness()
    h.send.mockRejectedValue(new Error('offline'))
    const collector = createPwaEvidenceCollector('alice', h.deps)
    await collector.interaction(true)
    h.setOwner('bob')
    await collector.retry()
    expect(h.send).toHaveBeenCalledTimes(1)
    h.setOwner('alice')
    // Even switching back promptly must not resurrect a prior session's event.
    await collector.retry()
    expect(h.send).toHaveBeenCalledTimes(1)
  })

  it('drops expired offline observations instead of refreshing their timestamp', async () => {
    const h = harness()
    h.send.mockRejectedValueOnce(new Error('offline'))
    const collector = createPwaEvidenceCollector('alice', h.deps)
    await collector.interaction(true)
    h.advance(5 * 60_000 + 1)
    await collector.retry()
    expect(h.send).toHaveBeenCalledTimes(1)
  })

  it('stops an in-flight bind from uploading after disposal', async () => {
    const h = harness()
    let release!: (value: { bindingId: string }) => void
    h.bind.mockImplementation(() => new Promise((resolve) => { release = resolve }))
    const collector = createPwaEvidenceCollector('alice', h.deps)
    const pending = collector.interaction(true)
    await vi.waitFor(() => expect(h.bind).toHaveBeenCalledOnce())
    collector.stop()
    release({ bindingId: 'old-binding' })
    await pending
    expect(h.send).not.toHaveBeenCalled()
    expect(h.revoke).toHaveBeenCalledWith('old-binding')
  })

  it('does not reinterpret an explicit server rejection as successful collection', async () => {
    const h = harness()
    h.send.mockResolvedValueOnce('revoked')
    const collector = createPwaEvidenceCollector('alice', h.deps)
    await collector.interaction(true)
    h.advance(5 * 60_000)
    await collector.interaction(true)
    expect(h.bind).toHaveBeenCalledTimes(2)
  })
})
