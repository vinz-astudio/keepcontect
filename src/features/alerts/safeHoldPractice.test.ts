import fs from 'node:fs'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { SafeHoldPractice } from './SafeHoldPractice'

// Human decision 2026-11-02: the 3-second hold can be tried from the self-test
// tools at any time, without an alert and without notifying anyone.
describe('"试按「一切安好」" practice', () => {
  it('renders the same hold ring and says it sends nothing', () => {
    const html = renderToStaticMarkup(createElement(SafeHoldPractice, { lang: 'zh' }))
    expect(html).toContain('role="progressbar"')
    expect(html).toContain('一切安好')
    expect(html).toContain('不会发出任何确认')
  })

  it('cannot confirm anything or reach the server', () => {
    const src = fs.readFileSync('src/features/alerts/SafeHoldPractice.tsx', 'utf8')
    expect(src).toContain('durationMs: SAFE_HOLD_MS')
    expect(src).not.toMatch(/supabase|confirmSafe|acknowledge|pushApi|rpc\(/)
  })

  it('is offered in the self-test tools', () => {
    const card = fs.readFileSync('src/features/alerts/NotificationsCard.tsx', 'utf8')
    expect(card).toContain('试按「一切安好」')
    expect(card).toContain('<SafeHoldPractice')
  })
})
