# Compact Viewport Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the default ViewportDiagnostics copy payload small enough for chat while adding the exact iOS standalone and viewport-unit measurements required to diagnose the physical 47pt strip.

**Architecture:** Keep the existing full local trace buffer unchanged. Enrich each full trace with standalone-class and computed viewport-unit measurements, then project full traces into a bounded compact schema that deduplicates unchanged states and omits URLs/full style payloads. The profile card uses compact export by default and keeps full export as a secondary action.

**Tech Stack:** TypeScript, React 19, Vitest, browser DOM APIs, localStorage.

## Global Constraints

- Default copied diagnostics contain at most 12 state-changing entries, newest first.
- Compact diagnostics must omit full URL/query/hash and repeated full computed-style payloads.
- Compact diagnostics must include `iosStandaloneClass`, `vhPx` and `dvhPx`.
- Full local trace retention remains bounded at 120 entries and full export stays explicitly available.
- Diagnostics failures must never break app rendering.
- No dependency, database, release-version or production change.
- This feature does not claim the iOS 47pt defect is fixed.

---

### Task 1: Compact trace schema and viewport-unit capture

**Files:**
- Modify: `src/lib/viewportDiagnostics.test.ts`
- Modify: `src/lib/viewportDiagnostics.ts`

**Interfaces:**
- Consumes: existing `ViewportTraceEntry[]`, `readViewportTrace()` and local full-trace storage.
- Produces: `exportCompactViewportTraceText(entries?: ViewportTraceEntry[], maxEntries?: number): string` and `exportFullViewportTraceText(entries?: ViewportTraceEntry[]): string`.
- Extends: `ViewportTraceEntry.display` with `iosStandaloneClass: boolean` and `viewportUnits: { vhPx: number | null; dvhPx: number | null }`.

- [ ] **Step 1: Extend the test fixture and write failing compact/full export tests**

Add the new display fields to `makeEntry`, add a realistic tabbar element, then add tests equivalent to:

```ts
it('exports at most 12 distinct compact states without URLs or full styles', () => {
  const entries = Array.from({ length: 30 }, (_, index) => {
    const state = Math.floor(index / 2)
    const entry = makeEntry(30 - index)
    entry.label = `event-${index}`
    entry.url = `https://secret.example/invite?token=${index}#private`
    entry.viewport.innerHeight = 797 - state
    entry.viewport.clientHeight = 797 - state
    entry.display.iosStandaloneClass = true
    entry.display.viewportUnits = { vhPx: 797 - state, dvhPx: 797 - state }
    return entry
  })

  const compact = JSON.parse(exportCompactViewportTraceText(entries))
  const serialized = JSON.stringify(compact)

  expect(compact.format).toBe('kc-viewport-compact-v2')
  expect(compact.totalEntries).toBe(30)
  expect(compact.includedStates).toBe(12)
  expect(compact.entries).toHaveLength(12)
  expect(compact.entries[0].display.iosStandaloneClass).toBe(true)
  expect(compact.entries[0].display.viewportUnits).toEqual({ vhPx: 797, dvhPx: 797 })
  expect(serialized).not.toContain('secret.example')
  expect(serialized).not.toContain('token=')
  expect(serialized).not.toContain('styles')
})

it('keeps the existing full forensic payload behind an explicit exporter', () => {
  const entry = makeEntry(1)
  entry.url = 'https://example.test/?from=notif'
  const full = JSON.parse(exportFullViewportTraceText([entry]))

  expect(full.entries).toHaveLength(1)
  expect(full.entries[0].url).toBe(entry.url)
  expect(full.entries[0].elements).toEqual(entry.elements)
})
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
npx vitest run src/lib/viewportDiagnostics.test.ts
```

Expected: FAIL because `exportCompactViewportTraceText` and `exportFullViewportTraceText` are not exported and the new display fields do not exist.

- [ ] **Step 3: Add viewport-unit capture fields**

Extend the interface and add a safe probe:

```ts
viewportUnits: {
  vhPx: number | null
  dvhPx: number | null
}
iosStandaloneClass: boolean
```

```ts
function getViewportUnitHeights(): ViewportTraceEntry['display']['viewportUnits'] {
  if (!document.body) return { vhPx: null, dvhPx: null }
  const measure = (height: string): number | null => {
    const probe = document.createElement('div')
    probe.style.cssText = `position:absolute;visibility:hidden;pointer-events:none;width:0;height:${height}`
    document.body.appendChild(probe)
    const value = parsePx(getComputedStyle(probe).height)
    probe.remove()
    return value
  }
  return {
    vhPx: measure('100vh'),
    dvhPx: CSS.supports?.('height: 100dvh') ? measure('100dvh') : null,
  }
}
```

Populate the fields inside `collectViewportTraceEntry()`:

```ts
iosStandaloneClass: document.documentElement.classList.contains('kc-ios-standalone'),
viewportUnits: getViewportUnitHeights(),
```

- [ ] **Step 4: Implement compact projection, state signature and explicit full export**

Create a compact projector containing only event identity, essential heights, visual viewport, display fields, root/home/tabbar rects and derived gaps. Deduplicate newest-first entries by a JSON signature of those state fields, then slice to 12:

```ts
export function exportCompactViewportTraceText(
  entries = readViewportTrace(),
  maxEntries = 12,
): string {
  const projected = entries.map(toCompactEntry)
  const seen = new Set<string>()
  const distinct = projected.filter((entry) => {
    const signature = compactStateSignature(entry)
    if (seen.has(signature)) return false
    seen.add(signature)
    return true
  }).slice(0, maxEntries)

  return JSON.stringify({
    format: 'kc-viewport-compact-v2',
    exportedAt: new Date().toISOString(),
    totalEntries: entries.length,
    includedStates: distinct.length,
    latestSuspects: entries.find((entry) => entry.derived.suspects.length)?.derived.suspects ?? [],
    entries: distinct,
  }, null, 2)
}

export function exportFullViewportTraceText(entries = readViewportTrace()): string {
  return JSON.stringify({
    exportedAt: new Date().toISOString(),
    latestSuspects: entries.find((entry) => entry.derived.suspects.length)?.derived.suspects ?? [],
    entries,
  }, null, 2)
}
```

The compact `elements` object must expose only `{ rect, clientHeight, scrollHeight, paddingBottom }` for root/home/tabbar; it must not include `.page`, `url`, `launch`, `extra`, or the full `.styles` object.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
npx vitest run src/lib/viewportDiagnostics.test.ts
```

Expected: all viewport diagnostics tests PASS.

---

### Task 2: Compact-first diagnostics controls

**Files:**
- Create: `src/features/profile/ViewportDiagnosticsCard.contract.test.ts`
- Modify: `src/features/profile/ViewportDiagnosticsCard.tsx`

**Interfaces:**
- Consumes: `exportCompactViewportTraceText()` and `exportFullViewportTraceText()` from Task 1.
- Produces: primary compact-copy action, secondary full-copy action and existing clear action.

- [ ] **Step 1: Write a failing source contract test**

Create:

```ts
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = readFileSync('src/features/profile/ViewportDiagnosticsCard.tsx', 'utf8')

describe('ViewportDiagnosticsCard copy contract', () => {
  it('uses compact diagnostics as the primary copy and keeps full export explicit', () => {
    expect(source).toMatch(/exportCompactViewportTraceText/)
    expect(source).toMatch(/exportFullViewportTraceText/)
    expect(source).toMatch(/复制精简诊断/)
    expect(source).toMatch(/复制完整日志/)
    expect(source).toMatch(/send the compact result first/i)
  })
})
```

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```bash
npx vitest run src/features/profile/ViewportDiagnosticsCard.contract.test.ts
```

Expected: FAIL because the card still imports the old exporter and has one copy button.

- [ ] **Step 3: Refactor the clipboard action and add compact/full buttons**

Replace the single `copy` function with a shared clipboard helper and two actions:

```ts
const writeClipboard = async (text: string): Promise<boolean> => {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    const box = document.createElement('textarea')
    box.value = text
    box.style.position = 'fixed'
    box.style.left = '-9999px'
    document.body.appendChild(box)
    box.focus()
    box.select()
    const ok = document.execCommand('copy')
    box.remove()
    return ok
  }
}
```

```ts
const copyCompact = async () => {
  recordViewportTrace('manual-copy-compact-viewport-diagnostics')
  const ok = await writeClipboard(exportCompactViewportTraceText())
  setStatus(ok ? compactSuccessCopy : failureCopy)
  refresh()
}

const copyFull = async () => {
  recordViewportTrace('manual-copy-full-viewport-diagnostics')
  const ok = await writeClipboard(exportFullViewportTraceText())
  setStatus(ok ? fullSuccessCopy : failureCopy)
  refresh()
}
```

Render compact as the first primary `.share` button and full as a secondary muted `.share` button. Keep Clear unchanged. Change help copy to “先复制并发送精简诊断；只有我明确要求时才复制完整日志。” / “Copy and send the compact result first; use the full log only when explicitly requested.”

- [ ] **Step 4: Run both focused tests and verify GREEN**

Run:

```bash
npx vitest run src/lib/viewportDiagnostics.test.ts src/features/profile/ViewportDiagnosticsCard.contract.test.ts
```

Expected: all focused tests PASS.

---

### Task 3: Integrated verification and documentation

**Files:**
- Modify only if verification exposes a defect: files listed in Tasks 1–2.
- Update after implementation through Brain runtime: task evidence, Dev Log, Known Issues and Platform Device Matrix.

**Interfaces:**
- Consumes: integrated compact exporter and card controls.
- Produces: verified implementation artifact suitable for a new preview deployment after independent review.

- [ ] **Step 1: Run TypeScript, full tests and production build**

Run:

```bash
npm run typecheck
npm test
npm run build
git diff --check
```

Expected: typecheck PASS; all Vitest files/tests PASS; Vite build PASS; diff check reports no whitespace errors.

- [ ] **Step 2: Measure compact-versus-full output in a deterministic test fixture**

Use the focused test fixture to assert the compact object includes no more than 12 entries and contains neither `url` nor `styles`; record the focused test output as evidence. Do not claim an exact iPhone payload size until the device copies the new compact format.

- [ ] **Step 3: Obtain one independent integrated-diff review**

Provide the final diff, RED/GREEN evidence and constraints to the declared Google reviewer. Accept only a clear PASS/FAIL verdict; resolve valid findings before integration.

- [ ] **Step 4: Write Brain evidence and finish the child task**

Record implementation, tests, independent review and the boundary that the parent 47pt issue remains open. Run `brain-task update`, route/fanin checks and `brain-task finish KC-VIEWPORT-DIAG-COMPACT-001` only after all required evidence is present.

- [ ] **Step 5: Commit the implementation**

```bash
git add src/lib/viewportDiagnostics.ts src/lib/viewportDiagnostics.test.ts src/features/profile/ViewportDiagnosticsCard.tsx src/features/profile/ViewportDiagnosticsCard.contract.test.ts docs/superpowers/plans/2026-07-18-viewport-diagnostics-compact.md
git commit -m "feat(diagnostics): add compact viewport export"
```
