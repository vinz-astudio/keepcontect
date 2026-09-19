import type { PassiveCollectorBinding } from './evidenceContract'

interface ShortcutSetupDeps {
  getUserId: () => Promise<string | null>
  bind: () => Promise<PassiveCollectorBinding>
  revoke: (bindingId: string) => Promise<boolean>
  remember: (bindingId: string) => void
  baseUrl: string
}

/** Called only by the setup button. Store the revocation handle, never the URL credential. */
export async function createAppOpenShortcut(ownerId: string, deps: ShortcutSetupDeps): Promise<string> {
  if (await deps.getUserId() !== ownerId) throw new Error('Account changed')
  const binding = await deps.bind()
  try {
    if (await deps.getUserId() !== ownerId || binding.surfaceType !== 'shortcut') throw new Error('Account changed')
    const url = new URL('/functions/v1/passive-evidence', deps.baseUrl)
    url.searchParams.set('binding_id', binding.bindingId)
    url.searchParams.set('credential', binding.credential)
    url.searchParams.set('trigger', 'app_open')
    // Keep a revocation handle; the credential stays only in the returned URL.
    deps.remember(binding.bindingId)
    return url.toString()
  } catch (error) {
    await deps.revoke(binding.bindingId).catch(() => false)
    throw error
  }
}
