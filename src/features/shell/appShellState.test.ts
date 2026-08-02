import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { I18nProvider } from '@/lib/i18n'
import { AppShell } from './AppShell'
import { getSosHoldProgress, isPrimaryTab } from './appShellState'

describe('AppShell state', () => {
  it('accepts only the four ordinary tabs', () => {
    expect(isPrimaryTab('watch')).toBe(true)
    expect(isPrimaryTab('routine')).toBe(true)
    expect(isPrimaryTab('circles')).toBe(true)
    expect(isPrimaryTab('me')).toBe(true)
    expect(isPrimaryTab('gm')).toBe(false)
    expect(isPrimaryTab('home')).toBe(false)
  })

  it('uses the production 1.4 second SOS hold', () => {
    expect(getSosHoldProgress(1000, 1700)).toBe(50)
    expect(getSosHoldProgress(1000, 2400)).toBe(100)
  })

  it('clamps missing, early, and late hold progress', () => {
    expect(getSosHoldProgress(null, 1700)).toBe(0)
    expect(getSosHoldProgress(2000, 1700)).toBe(0)
    expect(getSosHoldProgress(1000, 4000)).toBe(100)
  })

  it('renders four tabs, a raised SOS action, and no GM tab', () => {
    const html = renderToStaticMarkup(
      createElement(
        I18nProvider,
        null,
        createElement(
          AppShell,
          {
            activeTab: 'watch',
            onTabChange: () => undefined,
            onSos: () => undefined,
            displayName: 'AI GM',
            unreadCount: 3,
          },
          createElement('p', null, 'Watch content'),
        ),
      ),
    )

    expect(html).toContain('data-tab="watch"')
    expect(html).toContain('data-tab="routine"')
    expect(html).toContain('data-tab="circles"')
    expect(html).toContain('data-tab="me"')
    expect(html).toContain('aria-current="page"')
    expect(html).toContain('SOS')
    expect(html).not.toContain('data-tab="gm"')
    expect(html).not.toContain('<svg')
  })
})
