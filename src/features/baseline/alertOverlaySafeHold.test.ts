import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

// Human decision 2026-11-02: "一切安好" is a 3-second hold with a ring, not a tap.
describe('"一切安好" is press-and-hold', () => {
  const overlay = fs.readFileSync('src/features/baseline/AlertOverlay.tsx', 'utf8')
  const button = overlay.slice(overlay.indexOf('className={`overlay__safe-hold'), overlay.indexOf('id="overlay-safe-hint"'))

  it('confirms only through the hold, never on a tap', () => {
    expect(overlay).toContain('durationMs: SAFE_HOLD_MS')
    expect(button).toContain('{...safeHold.handlers}')
    expect(button).toContain('<HoldRing progress={safeHold.progress}')
    expect(button).not.toContain('onClick')
  })

  it('tells the user to hold, in both languages', () => {
    expect(overlay).toContain('按住“一切安好”3 秒即可')
    expect(overlay).toContain('Hold “I am safe” for 3 seconds')
    expect(overlay).not.toContain('轻按“一切安好”')
  })
})
