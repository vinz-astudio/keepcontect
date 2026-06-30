import { describe, expect, it } from 'vitest'
import {
  clearViewportTrace,
  readViewportTrace,
  writeViewportTraceEntry,
  type ViewportTraceEntry,
} from '@/lib/viewportDiagnostics'

function makeEntry(seq: number): ViewportTraceEntry {
  return {
    seq,
    label: `entry-${seq}`,
    at: '2026-06-30T00:00:00.000Z',
    ageMs: seq,
    url: 'https://example.test/',
    launch: {
      from: null,
      navType: 'navigate',
      historyLength: 1,
      visibilityState: 'visible',
      wasDiscarded: null,
      prerendering: null,
    },
    viewport: {
      innerWidth: 390,
      innerHeight: 844,
      outerWidth: 390,
      outerHeight: 844,
      clientWidth: 390,
      clientHeight: 844,
      screenWidth: 390,
      screenHeight: 844,
      availWidth: 390,
      availHeight: 844,
      orientation: 'portrait-primary',
      devicePixelRatio: 3,
    },
    visualViewport: null,
    display: {
      mode: 'standalone',
      navigatorStandalone: true,
      safeArea: null,
      supportsDvh: true,
    },
    elements: {
      root: null,
      home: null,
      page: null,
      tabbar: null,
    },
    derived: {
      viewportBottom: 844,
      tabbarGapBelow: null,
      tabbarVisualGapBelow: null,
      tabbarPaddingBottomPx: null,
      homeGapBelow: null,
      rootGapBelow: null,
      pageGapToTabbar: null,
      suspects: [],
    },
  }
}

describe('viewport diagnostics', () => {
  it('stores newest-first viewport traces with a bounded buffer', () => {
    const stored: Record<string, string> = {}
    const storage = {
      getItem: (key: string) => stored[key] ?? null,
      setItem: (key: string, value: string) => {
        stored[key] = value
      },
      removeItem: (key: string) => {
        delete stored[key]
      },
    }

    writeViewportTraceEntry(makeEntry(1), storage, 2)
    writeViewportTraceEntry(makeEntry(2), storage, 2)
    writeViewportTraceEntry(makeEntry(3), storage, 2)

    const entries = readViewportTrace(storage)
    expect(entries.map((entry) => entry.seq)).toEqual([3, 2])
  })

  it('clears stored viewport traces', () => {
    const stored: Record<string, string> = {}
    const storage = {
      getItem: (key: string) => stored[key] ?? null,
      setItem: (key: string, value: string) => {
        stored[key] = value
      },
      removeItem: (key: string) => {
        delete stored[key]
      },
    }

    writeViewportTraceEntry(makeEntry(1), storage)
    clearViewportTrace(storage)

    expect(readViewportTrace(storage)).toEqual([])
  })
})
