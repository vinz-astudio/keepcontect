import { describe, expect, it, vi } from 'vitest'
import { createAppOpenShortcut } from './shortcutSetup'

function harness() {
  return {
    getUserId: vi.fn().mockResolvedValue('alice'),
    bind: vi.fn().mockResolvedValue({ bindingId: 'binding-a', credential: 'private-credential', surfaceType: 'shortcut' }),
    revoke: vi.fn().mockResolvedValue(true), remember: vi.fn(),
    baseUrl: 'https://example.invalid',
  }
}
describe('Shortcut setup ownership', () => {
  it('creates only a scoped app-open URL and stores only its revocation handle', async () => {
    const h = harness()
    const url = new URL(await createAppOpenShortcut('alice', h))
    expect(url.pathname).toBe('/functions/v1/passive-evidence')
    expect(Object.fromEntries(url.searchParams)).toEqual({ binding_id: 'binding-a', credential: 'private-credential', trigger: 'app_open' })
    expect(h.remember).toHaveBeenCalledWith('binding-a')
    expect(h.revoke).not.toHaveBeenCalled()
  })
  it('never copies a credential if the account switches while binding', async () => {
    const h = harness()
    h.getUserId.mockResolvedValueOnce('alice').mockResolvedValue('bob')
    await expect(createAppOpenShortcut('alice', h)).rejects.toThrow('Account changed')
    expect(h.remember).not.toHaveBeenCalled()
    expect(h.revoke).toHaveBeenCalledWith('binding-a')
  })
  it('revokes an incomplete setup when its revocation handle cannot be saved', async () => {
    const h = harness()
    h.remember.mockImplementation(() => { throw new Error('storage unavailable') })
    await expect(createAppOpenShortcut('alice', h)).rejects.toThrow('storage unavailable')
    expect(h.revoke).toHaveBeenCalledWith('binding-a')
  })
})
