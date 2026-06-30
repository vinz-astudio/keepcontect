export interface ViewportTraceEntry {
  seq: number
  label: string
  at: string
  ageMs: number
  url: string
  extra?: Record<string, unknown>
  launch: {
    from: string | null
    navType: string | null
    historyLength: number
    visibilityState: DocumentVisibilityState | 'unknown'
    wasDiscarded: boolean | null
    prerendering: boolean | null
  }
  viewport: {
    innerWidth: number
    innerHeight: number
    outerWidth: number
    outerHeight: number
    clientWidth: number
    clientHeight: number
    screenWidth: number
    screenHeight: number
    availWidth: number
    availHeight: number
    orientation: string | null
    devicePixelRatio: number
  }
  visualViewport: null | {
    width: number
    height: number
    offsetTop: number
    offsetLeft: number
    scale: number
    pageTop: number
    pageLeft: number
  }
  display: {
    mode: 'standalone' | 'fullscreen' | 'minimal-ui' | 'browser'
    navigatorStandalone: boolean | null
    safeArea: null | {
      top: string
      right: string
      bottom: string
      left: string
    }
    supportsDvh: boolean | null
  }
  elements: {
    root: ElementTrace | null
    home: ElementTrace | null
    page: ElementTrace | null
    tabbar: ElementTrace | null
  }
  derived: {
    viewportBottom: number
    tabbarGapBelow: number | null
    tabbarVisualGapBelow: number | null
    tabbarPaddingBottomPx: number | null
    homeGapBelow: number | null
    rootGapBelow: number | null
    pageGapToTabbar: number | null
    suspects: string[]
  }
}

export interface ElementTrace {
  selector: string
  rect: RectTrace
  offsetHeight: number
  clientHeight: number
  scrollHeight: number
  styles: {
    display: string
    position: string
    height: string
    minHeight: string
    maxHeight: string
    paddingTop: string
    paddingBottom: string
    marginTop: string
    marginBottom: string
    overflowY: string
    flex: string
    flexBasis: string
  }
}

interface TraceStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

interface RectTrace {
  top: number
  right: number
  bottom: number
  left: number
  width: number
  height: number
}

const TRACE_KEY = 'kc.viewportTrace.v1'
const MAX_TRACE = 120
const STARTED_AT = Date.now()
let installed = false
let seq = 0
let resizeTimer: number | null = null

function getStorage(): TraceStorage | null {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

function round(n: number): number {
  return Math.round(n * 100) / 100
}

function parsePx(value: string | undefined): number | null {
  if (!value) return null
  const n = Number.parseFloat(value)
  return Number.isFinite(n) ? n : null
}

function rectTrace(rect: DOMRect): RectTrace {
  return {
    top: round(rect.top),
    right: round(rect.right),
    bottom: round(rect.bottom),
    left: round(rect.left),
    width: round(rect.width),
    height: round(rect.height),
  }
}

function getDisplayMode(): ViewportTraceEntry['display']['mode'] {
  if (window.matchMedia?.('(display-mode: standalone)').matches) return 'standalone'
  if (window.matchMedia?.('(display-mode: fullscreen)').matches) return 'fullscreen'
  if (window.matchMedia?.('(display-mode: minimal-ui)').matches) return 'minimal-ui'
  return 'browser'
}

function getNavigationType(): string | null {
  try {
    const nav = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming | undefined
    return nav?.type ?? null
  } catch {
    return null
  }
}

function getSafeArea(): ViewportTraceEntry['display']['safeArea'] {
  if (!document.body) return null
  const probe = document.createElement('div')
  probe.style.cssText = [
    'position:absolute',
    'left:-9999px',
    'top:-9999px',
    'padding-top:env(safe-area-inset-top)',
    'padding-right:env(safe-area-inset-right)',
    'padding-bottom:env(safe-area-inset-bottom)',
    'padding-left:env(safe-area-inset-left)',
  ].join(';')
  document.body.appendChild(probe)
  const cs = getComputedStyle(probe)
  const out = {
    top: cs.paddingTop,
    right: cs.paddingRight,
    bottom: cs.paddingBottom,
    left: cs.paddingLeft,
  }
  probe.remove()
  return out
}

function getElementTrace(selector: string): ElementTrace | null {
  const el = document.querySelector<HTMLElement>(selector)
  if (!el) return null
  const cs = getComputedStyle(el)
  return {
    selector,
    rect: rectTrace(el.getBoundingClientRect()),
    offsetHeight: el.offsetHeight,
    clientHeight: el.clientHeight,
    scrollHeight: el.scrollHeight,
    styles: {
      display: cs.display,
      position: cs.position,
      height: cs.height,
      minHeight: cs.minHeight,
      maxHeight: cs.maxHeight,
      paddingTop: cs.paddingTop,
      paddingBottom: cs.paddingBottom,
      marginTop: cs.marginTop,
      marginBottom: cs.marginBottom,
      overflowY: cs.overflowY,
      flex: cs.flex,
      flexBasis: cs.flexBasis,
    },
  }
}

function buildSuspects(args: {
  mode: ViewportTraceEntry['display']['mode']
  tabbar: ElementTrace | null
  page: ElementTrace | null
  home: ElementTrace | null
  root: ElementTrace | null
  viewportBottom: number
  visualViewportBottom: number | null
}): ViewportTraceEntry['derived'] {
  const tabbarGapBelow = args.tabbar ? round(args.viewportBottom - args.tabbar.rect.bottom) : null
  const tabbarVisualGapBelow = args.tabbar && args.visualViewportBottom != null
    ? round(args.visualViewportBottom - args.tabbar.rect.bottom)
    : null
  const tabbarPaddingBottomPx = parsePx(args.tabbar?.styles.paddingBottom)
  const homeGapBelow = args.home ? round(args.viewportBottom - args.home.rect.bottom) : null
  const rootGapBelow = args.root ? round(args.viewportBottom - args.root.rect.bottom) : null
  const pageGapToTabbar = args.page && args.tabbar ? round(args.tabbar.rect.top - args.page.rect.bottom) : null
  const suspects: string[] = []

  if (tabbarGapBelow != null && Math.abs(tabbarGapBelow) > 2) {
    suspects.push('tabbar bottom is ' + tabbarGapBelow + 'px from layout viewport bottom')
  }
  if (tabbarVisualGapBelow != null && Math.abs(tabbarVisualGapBelow) > 2) {
    suspects.push('tabbar bottom is ' + tabbarVisualGapBelow + 'px from visualViewport bottom')
  }
  if (args.mode !== 'standalone' && tabbarPaddingBottomPx != null && tabbarPaddingBottomPx > 14) {
    suspects.push('browser/webview tabbar padding-bottom is high: ' + tabbarPaddingBottomPx + 'px')
  }
  if (args.mode === 'standalone' && tabbarPaddingBottomPx != null && tabbarPaddingBottomPx < 6) {
    suspects.push('standalone tabbar padding-bottom is unexpectedly low: ' + tabbarPaddingBottomPx + 'px')
  }
  if (pageGapToTabbar != null && Math.abs(pageGapToTabbar) > 2) {
    suspects.push('page bottom and tabbar top differ by ' + pageGapToTabbar + 'px')
  }
  if (homeGapBelow != null && Math.abs(homeGapBelow) > 2) {
    suspects.push('home bottom differs from viewport by ' + homeGapBelow + 'px')
  }
  if (rootGapBelow != null && Math.abs(rootGapBelow) > 2) {
    suspects.push('root bottom differs from viewport by ' + rootGapBelow + 'px')
  }

  return {
    viewportBottom: round(args.viewportBottom),
    tabbarGapBelow,
    tabbarVisualGapBelow,
    tabbarPaddingBottomPx,
    homeGapBelow,
    rootGapBelow,
    pageGapToTabbar,
    suspects,
  }
}

export function readViewportTrace(storage: TraceStorage | null = getStorage()): ViewportTraceEntry[] {
  if (!storage) return []
  try {
    const raw = storage.getItem(TRACE_KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? parsed as ViewportTraceEntry[] : []
  } catch {
    return []
  }
}

export function writeViewportTraceEntry(
  entry: ViewportTraceEntry,
  storage: TraceStorage | null = getStorage(),
  maxEntries = MAX_TRACE,
): void {
  if (!storage) return
  try {
    const previous = readViewportTrace(storage)
    storage.setItem(TRACE_KEY, JSON.stringify([entry, ...previous].slice(0, maxEntries)))
  } catch {
    /* Diagnostics must never break the app. */
  }
}

export function clearViewportTrace(storage: TraceStorage | null = getStorage()): void {
  try {
    storage?.removeItem(TRACE_KEY)
  } catch {
    /* Diagnostics must never break the app. */
  }
}

export function collectViewportTraceEntry(
  label: string,
  extra?: Record<string, unknown>,
): ViewportTraceEntry | null {
  if (typeof window === 'undefined' || typeof document === 'undefined') return null
  const docAny = document as Document & { wasDiscarded?: boolean; prerendering?: boolean }
  const vv = window.visualViewport
  const root = getElementTrace('#root')
  const home = getElementTrace('.home')
  const page = getElementTrace('.home__page')
  const tabbar = getElementTrace('.tabbar')
  const viewportBottom = window.innerHeight
  const visualViewportBottom = vv ? vv.offsetTop + vv.height : null
  const mode = getDisplayMode()
  const params = new URLSearchParams(window.location.search)

  return {
    seq: ++seq,
    label,
    at: new Date().toISOString(),
    ageMs: Date.now() - STARTED_AT,
    url: window.location.href,
    extra,
    launch: {
      from: params.get('from'),
      navType: getNavigationType(),
      historyLength: window.history.length,
      visibilityState: document.visibilityState ?? 'unknown',
      wasDiscarded: typeof docAny.wasDiscarded === 'boolean' ? docAny.wasDiscarded : null,
      prerendering: typeof docAny.prerendering === 'boolean' ? docAny.prerendering : null,
    },
    viewport: {
      innerWidth: window.innerWidth,
      innerHeight: window.innerHeight,
      outerWidth: window.outerWidth,
      outerHeight: window.outerHeight,
      clientWidth: document.documentElement.clientWidth,
      clientHeight: document.documentElement.clientHeight,
      screenWidth: window.screen.width,
      screenHeight: window.screen.height,
      availWidth: window.screen.availWidth,
      availHeight: window.screen.availHeight,
      orientation: screen.orientation?.type ?? null,
      devicePixelRatio: window.devicePixelRatio,
    },
    visualViewport: vv
      ? {
          width: round(vv.width),
          height: round(vv.height),
          offsetTop: round(vv.offsetTop),
          offsetLeft: round(vv.offsetLeft),
          scale: vv.scale,
          pageTop: round(vv.pageTop),
          pageLeft: round(vv.pageLeft),
        }
      : null,
    display: {
      mode,
      navigatorStandalone: typeof (navigator as Navigator & { standalone?: boolean }).standalone === 'boolean'
        ? Boolean((navigator as Navigator & { standalone?: boolean }).standalone)
        : null,
      safeArea: getSafeArea(),
      supportsDvh: typeof CSS !== 'undefined' && CSS.supports ? CSS.supports('height: 100dvh') : null,
    },
    elements: { root, home, page, tabbar },
    derived: buildSuspects({
      mode,
      tabbar,
      page,
      home,
      root,
      viewportBottom,
      visualViewportBottom,
    }),
  }
}

export function recordViewportTrace(label: string, extra?: Record<string, unknown>): ViewportTraceEntry | null {
  const entry = collectViewportTraceEntry(label, extra)
  if (entry) writeViewportTraceEntry(entry)
  if (import.meta.env.DEV && entry?.derived.suspects.length) {
    console.info('kc-viewport-trace', entry.label, entry.derived.suspects)
  }
  return entry
}

function recordSoon(label: string, delayMs: number, extra?: Record<string, unknown>): void {
  window.setTimeout(() => recordViewportTrace(label, extra), delayMs)
}

function recordAnimationFrame(label: string, extra?: Record<string, unknown>): void {
  window.requestAnimationFrame(() => recordViewportTrace(label, extra))
}

function recordResize(label: string, extra?: Record<string, unknown>): void {
  if (resizeTimer != null) window.clearTimeout(resizeTimer)
  resizeTimer = window.setTimeout(() => {
    resizeTimer = null
    recordViewportTrace(label, extra)
  }, 80)
}

export function installViewportDiagnostics(): void {
  if (installed || typeof window === 'undefined' || typeof document === 'undefined') return
  installed = true

  recordViewportTrace('install')
  recordAnimationFrame('first-animation-frame')
  recordSoon('after-250ms', 250)
  recordSoon('after-1000ms', 1000)
  recordSoon('after-2500ms', 2500)

  if (new URLSearchParams(window.location.search).get('from') === 'notif') {
    recordViewportTrace('launch-from-notification-query')
  }

  window.addEventListener('pageshow', (event) => {
    recordViewportTrace('pageshow', { persisted: event.persisted })
    recordAnimationFrame('pageshow-animation-frame', { persisted: event.persisted })
  })
  window.addEventListener('pagehide', (event) => {
    recordViewportTrace('pagehide', { persisted: event.persisted })
  })
  document.addEventListener('visibilitychange', () => {
    recordViewportTrace('visibilitychange', { visibilityState: document.visibilityState })
    if (document.visibilityState === 'visible') recordAnimationFrame('visible-animation-frame')
  })
  window.addEventListener('focus', () => {
    recordViewportTrace('focus')
    recordAnimationFrame('focus-animation-frame')
  })
  window.addEventListener('blur', () => recordViewportTrace('blur'))
  window.addEventListener('resize', () => recordResize('window-resize'))
  window.addEventListener('orientationchange', () => {
    recordViewportTrace('orientationchange')
    recordSoon('orientationchange-after-500ms', 500)
  })
  window.visualViewport?.addEventListener('resize', () => recordResize('visualViewport-resize'))
  window.visualViewport?.addEventListener('scroll', () => recordResize('visualViewport-scroll'))
  navigator.serviceWorker?.addEventListener('message', (event) => {
    const data = event.data as { type?: string } | undefined
    recordViewportTrace('service-worker-message', { type: data?.type ?? 'unknown' })
  })
}

export function exportViewportTraceText(): string {
  const entries = readViewportTrace()
  return JSON.stringify(
    {
      exportedAt: new Date().toISOString(),
      latestSuspects: entries.find((entry) => entry.derived.suspects.length)?.derived.suspects ?? [],
      entries,
    },
    null,
    2,
  )
}
