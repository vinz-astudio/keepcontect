import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { RoutineScreen } from './RoutineScreen'
import {
  ROUTINE_SECTION_ORDER,
  ROUTINE_TYPE_OPTIONS,
  resolveRoutineSaveState,
} from './routinePresentation'

describe('Routine presentation', () => {
  it('keeps exactly the three production routine values', () => {
    expect(ROUTINE_TYPE_OPTIONS.map((item) => item.value)).toEqual([
      'regular_9to5',
      'semester_break',
      'shift_irregular',
    ])
  })

  it('places Routine type immediately after sleep settings', () => {
    expect(ROUTINE_SECTION_ORDER).toEqual([
      'sleep',
      'routine-type',
      'sensitivity',
      'timezone-privacy',
    ])
  })

  it('rolls a failed save back to the last server-confirmed value', () => {
    expect(resolveRoutineSaveState('regular_9to5', 'shift_irregular', false))
      .toEqual({ value: 'regular_9to5', status: 'rolled-back' })
  })

  it('keeps a successful save and reports it as confirmed', () => {
    expect(resolveRoutineSaveState('regular_9to5', 'shift_irregular', true))
      .toEqual({ value: 'shift_irregular', status: 'saved' })
  })

  it('renders the approved screen order as an inspectable contract', () => {
    const html = renderToStaticMarkup(createElement(
      RoutineScreen,
      {
        title: 'Your routine',
        subtitle: 'Settings follow your local time.',
      },
      createElement('span', null, 'Real routine settings'),
    ))

    expect(html).toContain('data-routine-sections="sleep,routine-type,sensitivity,timezone-privacy"')
    expect(html).toContain('Real routine settings')
  })
})
