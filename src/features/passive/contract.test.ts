import { describe, expect, it, vi, beforeEach } from 'vitest'
import { getAutomaticPingSource, PING_SOURCES } from '@/features/passive/api'
import { isStandalone, isTauri } from '@/lib/platform'
import { Capacitor } from '@capacitor/core'
import fs from 'node:fs'
import path from 'node:path'

// 1. Mocks for low-level platform checks
vi.mock('@/lib/platform', () => ({
  isStandalone: vi.fn(),
  isTauri: vi.fn(),
  getPlatform: vi.fn(),
}))

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: vi.fn(),
    getPlatform: vi.fn().mockReturnValue('web'),
  },
}))

// 2. Mocks for Supabase auth + behavior_pings DB operations
const mockInsert = vi.fn().mockResolvedValue({ error: null })
const mockRpc = vi.fn().mockResolvedValue({ data: 'inserted', error: null })
const mockSelect = vi.fn().mockReturnValue({
  eq: () => ({
    gte: () => ({
      order: () => ({
        limit: () => Promise.resolve({ data: [], error: null })
      })
    })
  })
})

const mockGetSession = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: () => mockGetSession()
    },
    rpc: (fn: string, args?: any) => mockRpc(fn, args),
    from: (table: string) => {
      if (table === 'behavior_pings') {
        return {
          insert: mockInsert,
          select: mockSelect,
        }
      }
      return {}
    }
  }
}))

// 3. In-memory Mock of IndexedDB to test recordSignal / syncSignalsWithServer
interface FakeSignal {
  id?: number
  t: number
  kind: string
  uploaded: boolean
  source?: string | null
  user_id?: string | null
}

const fakeStore: FakeSignal[] = []
let idCounter = 1

const fakeDb = {
  transaction: () => {
    const tx = {
      objectStore: () => ({
        add: (item: FakeSignal) => {
          // V5 update: Persist exactly the item passed by recordSignal plus generated ID.
          // Never call mockGetSession or inject user_id inside IndexedDB mock.
          const itemWithId = {
            ...item,
            id: idCounter++
          }
          fakeStore.push(itemWithId)
          const req = { onsuccess: null as any, onerror: null as any, result: itemWithId.id }
          setTimeout(() => {
            req.onsuccess?.()
            tx.oncomplete?.()
          }, 0)
          return req
        },
        get: (id: number) => {
          // Harness fix: implement get(id)
          const item = fakeStore.find(x => x.id === id)
          const req = { onsuccess: null as any, onerror: null as any, result: item ? { ...item } : undefined }
          setTimeout(() => {
            req.onsuccess?.()
            tx.oncomplete?.()
          }, 0)
          return req
        },
        getAll: () => {
          const req = { onsuccess: null as any, onerror: null as any, result: [...fakeStore] }
          setTimeout(() => {
            req.onsuccess?.()
            tx.oncomplete?.()
          }, 0)
          return req
        },
        put: (item: FakeSignal) => {
          const idx = fakeStore.findIndex(x => x.id === item.id)
          if (idx !== -1) {
            fakeStore[idx] = item
          }
          const req = { onsuccess: null as any, onerror: null as any }
          setTimeout(() => {
            req.onsuccess?.()
            tx.oncomplete?.()
          }, 0)
          return req
        }
      }),
      oncomplete: null as any,
      onerror: null as any
    }
    return tx
  },
  close: () => {}
}

const fakeIndexedDB = {
  open: () => {
    const req = { onsuccess: null as any, onerror: null as any, result: fakeDb }
    setTimeout(() => {
      req.onsuccess?.()
    }, 0)
    return req
  }
}

vi.stubGlobal('indexedDB', fakeIndexedDB)

// 4. Stub localStorage for debounce check in recordSignal
const storeMap = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (key: string) => storeMap.get(key) ?? null,
  setItem: (key: string, value: string) => storeMap.set(key, value),
  clear: () => storeMap.clear(),
})

// Import functions under test (must be imported after global stubs/mocks)
const { recordSignal, syncSignalsWithServer } = await import('@/features/signals/store')

describe('Client Surface Gating Contract', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    fakeStore.length = 0
    storeMap.clear()
    idCounter = 1
    // Default session context is User A
    mockGetSession.mockResolvedValue({ data: { session: { user: { id: 'test-user-id' } } } })
    mockRpc.mockResolvedValue({ data: 'inserted', error: null })
  })

  it('identifies plain browser (no standalone, no tauri, no capacitor) and returns null source', () => {
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(false)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    expect(getAutomaticPingSource()).toBeNull()
  })

  it('identifies Tauri desktop app and returns tauri source', () => {
    vi.mocked(isTauri).mockReturnValue(true)
    vi.mocked(isStandalone).mockReturnValue(false)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    expect(getAutomaticPingSource()).toBe(PING_SOURCES.TAURI)
  })

  it('identifies installed PWA and returns installed_pwa source', () => {
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(true)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    expect(getAutomaticPingSource()).toBe(PING_SOURCES.INSTALLED_PWA)
  })

  it('identifies Capacitor native app and returns capacitor source', () => {
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(false)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(true)

    expect(getAutomaticPingSource()).toBe(PING_SOURCES.CAPACITOR)
  })

  it('proves that a plain-browser automatic signal is never uploaded even after switching to tauri', async () => {
    // 1. We are on plain browser
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(false)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    // 2. Record an automatic signal 'interaction'
    await recordSignal('interaction')

    // Expect no immediate insert (because we are on plain browser)
    expect(mockInsert).not.toHaveBeenCalled()
    // Confirm it was written to IndexedDB with source: null
    expect(fakeStore).toHaveLength(1)
    expect(fakeStore[0].kind).toBe('interaction')
    expect(fakeStore[0].source).toBeNull()

    // 3. Switch to an eligible surface (e.g. Tauri)
    vi.mocked(isTauri).mockReturnValue(true)

    // Call syncSignalsWithServer
    await syncSignalsWithServer('test-user-id')

    // Confirm that the 'interaction' signal from plain-browser was NOT uploaded!
    // Since it had source = null, the sync filter should have excluded it.
    expect(mockInsert).not.toHaveBeenCalled()
  })

  it('proves that a manual checkin is always uploaded with manual source even on plain browser', async () => {
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(false)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    // Record a manual checkin
    await recordSignal('manual_checkin')

    expect(mockRpc).toHaveBeenCalledTimes(1)
    expect(mockRpc).toHaveBeenCalledWith('record_behavior_ping', {
      event_id: expect.any(String),
      observed_at: expect.any(String),
      source: 'manual',
      kind: 'manual_checkin',
    })
  })

  it('proves that local signals are partitioned by user ID to prevent cross-user syncing', async () => {
    // Set PWA context first
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(true)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    // If User A records a signal:
    await recordSignal('unlock')

    // In production, we expect the record in IndexedDB to be partitioned by user_id
    expect(fakeStore[0]).toHaveProperty('user_id', 'test-user-id') // FAIL: user_id is missing in local IndexedDB record
  })

  it('quarantines ownerless signals recorded when no user session exists', async () => {
    // Mock session to return null (no logged in user)
    mockGetSession.mockResolvedValue({ data: { session: null } })

    // Set PWA context
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(true)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    await recordSignal('unlock')

    // Expect the signal to be stored locally but quarantined as ownerless (user_id: null)
    expect(fakeStore[0]).toHaveProperty('user_id', null) // FAIL: user_id is missing/undefined in local store
    expect(mockRpc).not.toHaveBeenCalled()
  })

  it('proves User B sync cannot upload or mark User A offline records and ownerless signals stay quarantined', async () => {
    // Set PWA context
    vi.mocked(isTauri).mockReturnValue(false)
    vi.mocked(isStandalone).mockReturnValue(true)
    vi.mocked(Capacitor.isNativePlatform).mockReturnValue(false)

    // 1. Manually seed User A local signal (simulate partitioned IndexedDB data from other sessions)
    fakeStore.push({
      t: Date.now() - 60_000,
      kind: 'unlock',
      uploaded: false,
      source: 'installed_pwa',
      user_id: 'user-a'
    })

    // 2. Manually seed Ownerless local signal
    fakeStore.push({
      t: Date.now() - 30_000,
      kind: 'interaction',
      uploaded: false,
      source: 'installed_pwa',
      user_id: null
    })

    // Assert stored owners are exactly ['user-a', null]
    const owners = fakeStore.map(x => x.user_id)
    expect(owners).toEqual(['user-a', null])

    // 3. Authenticate User B
    mockGetSession.mockResolvedValue({ data: { session: { user: { id: 'user-b' } } } })
    mockInsert.mockClear()

    // 4. Run sync as User B
    await syncSignalsWithServer('user-b')

    // User B sync must cause ZERO inserts on User A or quarantined events
    expect(mockRpc).not.toHaveBeenCalled()

    // User A and Ownerless local records must not be marked as uploaded
    expect(fakeStore[0].uploaded).toBe(false)
    expect(fakeStore[1].uploaded).toBe(false)
  })

  it('asserts that PassivePingBoot does NOT add activity handlers because sources.ts owns foreground collection', () => {
    // Contract: PassivePingBoot must NOT itself add focus/pageshow/visibilitychange/pointerdown activity handlers.
    // Instead, sources.ts manages the PWA foreground collection.
    const bootFile = path.resolve('src/features/passive/PassivePingBoot.tsx')
    const bootSource = fs.readFileSync(bootFile, 'utf8')

    // The handler hookups should be absent from PassivePingBoot
    const registersFocus = bootSource.includes("addEventListener('focus'") || bootSource.includes('addEventListener("focus"')
    const registersPageshow = bootSource.includes("addEventListener('pageshow'") || bootSource.includes('addEventListener("pageshow"')
    const registersVisibility = bootSource.includes("addEventListener('visibilitychange'") || bootSource.includes('addEventListener("visibilitychange"')
    const registersPointer = bootSource.includes("addEventListener('pointerdown'") || bootSource.includes('addEventListener("pointerdown"')

    expect(registersFocus).toBe(false) // FAIL: currently registers focus listeners directly
    expect(registersPageshow).toBe(false) // FAIL: currently registers pageshow listeners directly
    expect(registersVisibility).toBe(false) // FAIL: currently registers visibilitychange listeners directly
    expect(registersPointer).toBe(false) // FAIL: currently registers pointerdown listeners directly
  })
})
