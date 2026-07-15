import { describe, expect, it, vi, beforeEach } from 'vitest'
import { getAutomaticPingSource, PING_SOURCES } from '@/features/passive/api'
import { isStandalone, isTauri } from '@/lib/platform'
import { Capacitor } from '@capacitor/core'

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
const mockSelect = vi.fn().mockReturnValue({
  eq: () => ({
    gte: () => ({
      order: () => ({
        limit: () => Promise.resolve({ data: [], error: null })
      })
    })
  })
})

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: () => Promise.resolve({ data: { session: { user: { id: 'test-user-id' } } } })
    },
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
}

const fakeStore: FakeSignal[] = []
let idCounter = 1

const fakeDb = {
  transaction: () => ({
    objectStore: () => ({
      add: (item: FakeSignal) => {
        const itemWithId = { ...item, id: idCounter++ }
        fakeStore.push(itemWithId)
        const req = { onsuccess: null as any, onerror: null as any, result: itemWithId.id }
        setTimeout(() => req.onsuccess?.(), 0)
        return req
      },
      getAll: () => {
        const req = { onsuccess: null as any, onerror: null as any, result: [...fakeStore] }
        setTimeout(() => req.onsuccess?.(), 0)
        return req
      },
      put: (item: FakeSignal) => {
        const idx = fakeStore.findIndex(x => x.id === item.id)
        if (idx !== -1) {
          fakeStore[idx] = item
        }
        const req = { onsuccess: null as any, onerror: null as any }
        setTimeout(() => req.onsuccess?.(), 0)
        return req
      }
    }),
    oncomplete: null as any,
    onerror: null as any
  }),
  close: () => {}
}

const fakeIndexedDB = {
  open: () => {
    const req = { onsuccess: null as any, onerror: null as any, result: fakeDb }
    setTimeout(() => {
      req.onsuccess?.()
      req.result.transaction().oncomplete?.()
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

    // Expect immediate insert with source: 'manual'
    expect(mockInsert).toHaveBeenCalledTimes(1)
    expect(mockInsert).toHaveBeenCalledWith({
      user_id: 'test-user-id',
      kind: 'manual_checkin',
      at: expect.any(String),
      source: 'manual',
    })
  })
})
