import { describe, expect, it, beforeEach, vi } from 'vitest'

// No group key path: force emergencyApi to fall through to the personal pattern-hash key.
vi.mock('@/features/relationships/api', () => ({
  listMyGroups: vi.fn(async () => []),
  listGroupMembers: vi.fn(async () => []),
}))

import { getEncryptionKey } from './emergencyApi'
import { setPattern, patternKey } from '@/features/pattern/patternStore'

// crypto.ts derives keys via window.crypto.subtle; map it to node's WebCrypto.
vi.stubGlobal('window', { crypto: globalThis.crypto })

const storeMap = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (k: string) => storeMap.get(k) ?? null,
  setItem: (k: string, v: string) => storeMap.set(k, v),
  removeItem: (k: string) => storeMap.delete(k),
  clear: () => storeMap.clear(),
  get length() {
    return storeMap.size
  },
  key: (i: number) => [...storeMap.keys()][i] ?? null,
})

const A = 'user-aaa'
const B = 'user-bbb'

describe('emergencyApi cross-account key derivation (KCA-04)', () => {
  beforeEach(() => storeMap.clear())

  it('derives a key for the account that owns a namespaced pattern hash', async () => {
    await setPattern(A, [1, 2, 3, 4])
    const key = await getEncryptionKey(A)
    expect(key).not.toBeNull()
  })

  it('does NOT derive a key for account B from account A’s pattern hash', async () => {
    await setPattern(A, [1, 2, 3, 4]) // only A enrolled
    const key = await getEncryptionKey(B)
    expect(key).toBeNull() // B must not inherit A's key material
  })

  it('ignores a leftover legacy global hash (no cross-account adoption)', async () => {
    storeMap.set('kc.patternHash', 'legacy-global-hash') // ownerless
    const key = await getEncryptionKey(B)
    expect(key).toBeNull()
    // sanity: A's namespaced slot is untouched/empty here
    expect(storeMap.has(patternKey(B))).toBe(false)
  })
})
