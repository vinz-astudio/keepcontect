import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import {
  PrototypeBadge,
  PrototypeCard,
  PrototypeDisclosure,
  PrototypeIcon,
  PrototypeRow,
  PrototypeSection,
  PrototypeSegmented,
  PrototypeStatePanel,
} from './PrototypeUI'

describe('Prototype UI primitives', () => {
  it('renders semantic sections and Material Symbols without inline SVG', () => {
    const html = renderToStaticMarkup(
      createElement(
        PrototypeSection,
        { title: 'Notifications', subtitle: 'Recent activity' },
        createElement(PrototypeIcon, { name: 'notifications' }),
        createElement(PrototypeBadge, { tone: 'ready' }, 'Ready'),
      ),
    )

    expect(html).toContain('<section')
    expect(html).toContain('material-symbols-rounded')
    expect(html).toContain('prototype-badge--ready')
    expect(html).not.toContain('<svg')
  })

  it('connects each section heading to its semantic region', () => {
    const html = renderToStaticMarkup(
      createElement(PrototypeSection, { title: 'Everyone’s Status' }),
    )

    const headingId = html.match(/<h2 id="([^"]+)"/)?.[1]
    expect(headingId).toBeTruthy()
    expect(html).toContain(`aria-labelledby="${headingId}"`)
  })

  it('renders rows, disclosure, segmented choices, and recovery states accessibly', () => {
    const html = renderToStaticMarkup(
      createElement(
        PrototypeCard,
        null,
        createElement(PrototypeRow, {
          icon: 'schedule',
          title: 'Routine type',
          subtitle: 'Ordinary routine',
          trailing: createElement(PrototypeBadge, { tone: 'limited' }, 'Review'),
        }),
        createElement(
          PrototypeDisclosure,
          { label: 'Details', defaultOpen: true },
          createElement('p', null, 'Private details'),
        ),
        createElement(PrototypeSegmented, {
          label: 'Theme',
          value: 'light',
          options: [
            { value: 'light', label: 'Light' },
            { value: 'dark', label: 'Dark' },
          ],
          onChange: () => undefined,
        }),
        createElement(PrototypeStatePanel, {
          state: 'error',
          title: 'Could not load',
          message: 'Check your connection.',
          retryLabel: 'Try again',
          onRetry: () => undefined,
        }),
      ),
    )

    expect(html).toContain('prototype-row')
    expect(html).toContain('aria-expanded="true"')
    expect(html).toContain('role="radiogroup"')
    expect(html).toContain('aria-checked="true"')
    expect(html).toContain('Try again')
  })
})
