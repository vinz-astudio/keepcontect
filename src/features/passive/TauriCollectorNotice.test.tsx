import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { TauriCollectorNotice } from './TauriCollectorNotice'

const state = vi.hoisted(() => ({ desktop: true, state: 'limited', reason: 'retry_pending' }))
vi.mock('@/lib/i18n', () => ({ useI18n: () => ({ lang: 'en' }) }))
vi.mock('@/lib/platform', () => ({ isTauri: () => state.desktop }))
vi.mock('./shadowCoverage', () => ({ getTauriEvidenceStatus: () => ({ state: state.state, reason: state.reason }) }))
beforeEach(() => { state.desktop = true; state.state = 'limited'; state.reason = 'retry_pending' })

describe('local desktop collector failure notice', () => {
  it('keeps a retrying collector visibly Limited without implying missed check-ins pause', () => {
    const html = renderToStaticMarkup(createElement(TauriCollectorNotice))
    expect(html).toContain('Limited collection')
    expect(html).toContain('retry automatically')
    expect(html).toContain('Miss counting continues.')
    expect(html).toContain('role="status"')
  })
  it('requests explicit reconnection for a revoked binding', () => {
    state.reason = 'revoked'
    const html = renderToStaticMarkup(createElement(TauriCollectorNotice))
    expect(html).toContain('off and on')
    expect(html).not.toContain('retry automatically')
  })
  it.each(['ready', 'off'])('is quiet when collection is %s', value => {
    state.state = value
    expect(renderToStaticMarkup(createElement(TauriCollectorNotice))).toBe('')
  })
  it('does not show a desktop notice on mobile or web', () => {
    state.desktop = false
    expect(renderToStaticMarkup(createElement(TauriCollectorNotice))).toBe('')
  })
})
