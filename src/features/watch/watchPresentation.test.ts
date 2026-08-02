import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { WatchScreen } from './WatchScreen'
import { buildWatchSections, getPersonActions } from './watchPresentation'

describe('Watch presentation', () => {
  it('puts GM tools above notifications only for GM accounts', () => {
    expect(buildWatchSections({ hasOwnTask: false, isGm: true, hasActiveAlert: false }))
      .toEqual(['summary', 'gm-tools', 'notifications', 'people'])
    expect(buildWatchSections({ hasOwnTask: false, isGm: false, hasActiveAlert: false }))
      .toEqual(['summary', 'notifications', 'people'])
  })

  it('puts a due check-in at the top and alert response last', () => {
    expect(buildWatchSections({ hasOwnTask: true, isGm: true, hasActiveAlert: true }))
      .toEqual(['summary', 'own-task', 'gm-tools', 'notifications', 'people', 'alert-response'])
  })

  it('never offers concern in normal, limited, or unknown states', () => {
    for (const evidenceQuality of ['ready', 'limited', 'unknown'] as const) {
      expect(getPersonActions({
        hasActiveAlert: false,
        canManageWardTasks: false,
        concernEligible: true,
        evidenceQuality,
      })).not.toContain('send-concern')
    }
  })

  it('keeps Ward task management separate from concern', () => {
    expect(getPersonActions({
      hasActiveAlert: false,
      canManageWardTasks: true,
      concernEligible: false,
      evidenceQuality: 'ready',
    })).toEqual(['manage-checkin-task'])
  })

  it('offers concern and direct contact only for an eligible active alert', () => {
    expect(getPersonActions({
      hasActiveAlert: true,
      canManageWardTasks: false,
      concernEligible: true,
      evidenceQuality: 'ready',
    })).toEqual(['send-concern', 'contact'])
  })

  it('renders screen slots in the approved order', () => {
    const html = renderToStaticMarkup(createElement(WatchScreen, {
      title: 'No active alerts right now',
      subtitle: 'Coverage is shown separately.',
      isGm: true,
      hasOwnTask: true,
      hasActiveAlert: true,
      summary: createElement('span', null, 'Summary'),
      ownTask: createElement('span', null, 'Own task'),
      gmTools: createElement('span', null, 'Manager tools'),
      notifications: createElement('span', null, 'Notifications content'),
      people: createElement('span', null, 'People content'),
      alertResponse: createElement('span', null, 'Alert response'),
    }))

    const labels = ['Summary', 'Own task', 'Manager tools', 'Notifications content', 'People content', 'Alert response']
    const positions = labels.map((label) => html.indexOf(label))
    expect(positions.every((position) => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
  })
})
