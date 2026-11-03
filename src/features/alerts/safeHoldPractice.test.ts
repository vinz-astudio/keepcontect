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

  // 2026-11-03: the old toggle sat in the notifications card header, which
  // Home hides inside its sections, so nobody could find it. Human decision:
  // the tools live in the GM console only.
  it('is offered in the self-test tools, which live in the GM console', () => {
    const tools = fs.readFileSync('src/features/alerts/SelfTestTools.tsx', 'utf8')
    expect(tools).toContain('试按「一切安好」')
    expect(tools).toContain('<SafeHoldPractice')
    const gm = fs.readFileSync('src/features/gm/GMScreen.tsx', 'utf8')
    expect(gm).toContain('<SelfTestTools showUnlockTest />')
    const card = fs.readFileSync('src/features/alerts/NotificationsCard.tsx', 'utf8')
    expect(card).not.toContain('SelfTestTools')
    expect(card).not.toContain('notif-tools-toggle')
  })
})
