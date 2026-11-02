import { execFileSync } from 'node:child_process'
import { describe, expect, test } from 'vitest'

// Windows and macOS file systems ignore case. Two modules whose import paths
// differ only by case (DesktopNotifier.tsx next to desktopNotifier.ts) pass on
// Linux CI but break typecheck and the build on the human's Windows machine.
describe('no import paths that differ only by case', () => {
  test('tracked source modules have case-unique import paths', () => {
    const files = execFileSync('git', ['ls-files', 'src', 'scripts'], { encoding: 'utf8' })
      .split('\n').filter(Boolean)
    const byKey = new Map()
    for (const file of files) {
      const importPath = file.replace(/\.(tsx?|jsx?|mjs)$/, '')
      const key = importPath.toLowerCase()
      const seen = byKey.get(key) ?? new Set()
      seen.add(importPath)
      byKey.set(key, seen)
    }
    const clashes = [...byKey.values()].filter((paths) => paths.size > 1).map((paths) => [...paths])
    expect(clashes).toEqual([])
  })
})
