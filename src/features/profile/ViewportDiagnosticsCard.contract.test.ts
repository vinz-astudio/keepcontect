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
