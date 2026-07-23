import { describe, expect, it, beforeEach, vi } from 'vitest'
import {
  patternKey,
  hasPattern,
  setPattern,
  verifyPattern,
  clearPattern,
  getPatternHash,
  resolvePatternAdoption,
  purgeLocalSafetyState,
} from './patternStore'

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
const SEQ = [0, 1, 2, 5, 8]

describe('patternStore per-account isolation (KCA-04 / ISO-01)', () => {
  beforeEach(() => storeMap.clear())

  it('scopes the storage key by uid', () => {
    expect(patternKey(A)).toBe('kc.patternHash.user-aaa')
    expect(patternKey(B)).toBe('kc.patternHash.user-bbb')
  })

  it('a pattern set for A is invisible to B, and B cannot verify with A pattern', async () => {
    await setPattern(A, SEQ)
    expect(hasPattern(A)).toBe(true)
    // B never enrolled → no pattern, and A's sequence must not verify for B
    expect(hasPattern(B)).toBe(false)
    expect(await verifyPattern(B, SEQ)).toBe(false)
    // A still verifies with its own sequence
    expect(await verifyPattern(A, SEQ)).toBe(true)
  })

  it('reads resolve exactly the current uid namespace — never the legacy global key', async () => {
    // Legacy un-namespaced hash left over from an older build (belongs to nobody now)
    storeMap.set('kc.patternHash', 'legacy-global-hash')
    // A brand-new account B must be treated as unenrolled, not adopt the legacy hash
    expect(hasPattern(B)).toBe(false)
    expect(getPatternHash(B)).toBeNull()
  })

  it('clearPattern removes only the uid-scoped key', async () => {
    await setPattern(A, SEQ)
    await setPattern(B, SEQ)
    clearPattern(A)
    expect(hasPattern(A)).toBe(false)
    expect(hasPattern(B)).toBe(true)
  })

  describe('resolvePatternAdoption — server-gated migration (no cross-account trust)', () => {
    it('never adopts the legacy global hash when the account has no server hash', () => {
      const r = resolvePatternAdoption({ scopedHash: null, legacyHash: 'A-legacy', serverHash: null })
      expect(r.hashToStore).toBeNull() // MUST NOT adopt legacy across accounts
      expect(r.needsSetup).toBe(true)
      expect(r.clearLegacy).toBe(true) // ownerless legacy is purged, never trusted
    })

    it('adopts the account-owned server hash (source of truth), clearing legacy', () => {
      const r = resolvePatternAdoption({ scopedHash: null, legacyHash: 'stale', serverHash: 'server-owned' })
      expect(r.hashToStore).toBe('server-owned')
      expect(r.needsSetup).toBe(false)
      expect(r.clearLegacy).toBe(true)
    })

    it('keeps an already-scoped hash and still purges any legacy global', () => {
      const r = resolvePatternAdoption({ scopedHash: 'mine', legacyHash: 'stale', serverHash: 'server' })
      expect(r.hashToStore).toBeNull() // already present, nothing to write
      expect(r.needsSetup).toBe(false)
      expect(r.clearLegacy).toBe(true)
    })

    it('treats a truly new user (no scoped/legacy/server) as setup', () => {
      const r = resolvePatternAdoption({ scopedHash: null, legacyHash: null, serverHash: null })
      expect(r.needsSetup).toBe(true)
      expect(r.hashToStore).toBeNull()
      expect(r.clearLegacy).toBe(false)
    })
  })

  describe('purgeLocalSafetyState (sign-out cleanup)', () => {
    it('removes legacy + all uid-scoped pattern hashes and openAlert, keeps non-sensitive config', async () => {
      storeMap.set('kc.patternHash', 'legacy')
      await setPattern(A, SEQ)
      await setPattern(B, SEQ)
      storeMap.set('kc.openAlert', '1')
      storeMap.set('kc.lang', 'zh')
      storeMap.set('kc.pushPrompt.dismissed', '1')

      purgeLocalSafetyState()

      expect(storeMap.has('kc.patternHash')).toBe(false)
      expect(storeMap.has(patternKey(A))).toBe(false)
      expect(storeMap.has(patternKey(B))).toBe(false)
      expect(storeMap.has('kc.openAlert')).toBe(false)
      // non-sensitive UI prefs survive
      expect(storeMap.get('kc.lang')).toBe('zh')
      expect(storeMap.get('kc.pushPrompt.dismissed')).toBe('1')
    })
  })
})
