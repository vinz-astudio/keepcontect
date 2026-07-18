import { describe, expect, it } from 'vitest'
import {
  clearViewportTrace,
  exportCompactViewportTraceText,
  exportFullViewportTraceText,
  readViewportTrace,
  writeViewportTraceEntry,
  type ViewportTraceEntry,
} from '@/lib/viewportDiagnostics'

type EnrichedDisplay = ViewportTraceEntry['display']

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
      iosStandaloneClass: false,
      viewportUnits: {
        vhPx: null,
        dvhPx: null,
      },
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

function enrichEntry(entry: ViewportTraceEntry, height: number): ViewportTraceEntry {
  const display = entry.display as EnrichedDisplay
  display.iosStandaloneClass = true
  display.viewportUnits = { vhPx: height, dvhPx: height }
  entry.viewport.innerHeight = height
  entry.viewport.clientHeight = height
  entry.visualViewport = {
    width: 390,
    height,
    offsetTop: 0,
    offsetLeft: 0,
    scale: 1,
    pageTop: 0,
    pageLeft: 0,
  }
  entry.elements.tabbar = {
    selector: '.tabbar',
    rect: { top: height - 92, right: 390, bottom: height, left: 0, width: 390, height: 92 },
    offsetHeight: 92,
    clientHeight: 92,
    scrollHeight: 92,
    styles: {
      display: 'flex',
      position: 'fixed',
      height: '92px',
      minHeight: '0px',
      maxHeight: 'none',
      paddingTop: '6px',
      paddingBottom: '6px',
      marginTop: '0px',
      marginBottom: '0px',
      overflowY: 'visible',
      flex: '0 1 auto',
      flexBasis: 'auto',
    },
  }
  return entry
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

  it('exports at most 12 distinct compact states without URLs or full styles', () => {
    const entries = Array.from({ length: 30 }, (_, index) => {
      const state = Math.floor(index / 2)
      const entry = enrichEntry(makeEntry(30 - index), 797 - state)
      entry.label = `event-${index}`
      entry.url = `https://secret.example/invite?token=${index}#private`
      return entry
    })

    const compactText = exportCompactViewportTraceText(entries)
    const compact = JSON.parse(compactText) as {
      format: string
      totalEntries: number
      includedStates: number
      entries: Array<{ display: EnrichedDisplay }>
    }

    expect(compact.format).toBe('kc-viewport-compact-v2')
    expect(compact.totalEntries).toBe(30)
    expect(compact.includedStates).toBe(12)
    expect(compact.entries).toHaveLength(12)
    expect(compact.entries[0].display.iosStandaloneClass).toBe(true)
    expect(compact.entries[0].display.viewportUnits).toEqual({ vhPx: 797, dvhPx: 797 })
    expect(compactText).not.toContain('secret.example')
    expect(compactText).not.toContain('token=')
    expect(compactText).not.toContain('"styles"')
    expect(compactText.length).toBeLessThan(20_000)
  })

  it('keeps the existing full forensic payload behind an explicit exporter', () => {
    const entry = enrichEntry(makeEntry(1), 797)
    entry.url = 'https://example.test/?from=notif'
    const full = JSON.parse(exportFullViewportTraceText([entry])) as {
      entries: ViewportTraceEntry[]
    }

    expect(full.entries).toHaveLength(1)
    expect(full.entries[0].url).toBe(entry.url)
    expect(full.entries[0].elements).toEqual(entry.elements)
  })
})
