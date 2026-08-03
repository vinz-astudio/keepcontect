import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

const css = fs.readFileSync('src/features/shell/AppShell.css', 'utf8')

describe('mobile header layout guardrails', () => {
  it('keeps the app name on one line and protects header controls from shrinking', () => {
    expect(css).toMatch(/\.app-shell__brand\s*\{[\s\S]*white-space:\s*nowrap;/)
    expect(css).toMatch(/\.app-shell__user\s*\{[\s\S]*flex-shrink:\s*0;/)
  })
})
