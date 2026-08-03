import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { CirclesScreen } from './CirclesScreen'
import { CIRCLE_SECTIONS, getCircleActions } from './circlesPresentation'

describe('Circles presentation', () => {
  it('uses the approved section order', () => {
    expect(CIRCLE_SECTIONS).toEqual(['circles', 'community', 'responsibilities'])
  })

  it('does not grant Ward task management from membership alone', () => {
    expect(getCircleActions({ role: 'member', hasCommunity: true }))
      .not.toContain('manage-ward-task')
    expect(getCircleActions({ role: 'guardian', hasCommunity: true }))
      .toContain('manage-ward-task')
  })

  it('keeps Community management role-gated', () => {
    expect(getCircleActions({ role: 'member', hasCommunity: true }))
      .not.toContain('manage-community')
    expect(getCircleActions({ role: 'gm', hasCommunity: true }))
      .toContain('manage-community')
  })

  it('renders Circles, Community, and Responsibilities in order', () => {
    const html = renderToStaticMarkup(createElement(CirclesScreen, {
      title: 'Circles & Community',
      subtitle: 'Trusted relationships and escalation networks.',
      circles: createElement('span', null, 'Circles content'),
      community: createElement('span', null, 'Community content'),
      responsibilities: createElement('span', null, 'Responsibilities content'),
    }))

    const positions = ['Circles content', 'Community content', 'Responsibilities content']
      .map((label) => html.indexOf(label))
    expect(positions.every((position) => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
  })
})
