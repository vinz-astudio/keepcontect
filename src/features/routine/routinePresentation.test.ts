import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { RoutineScreen } from './RoutineScreen'
import { ROUTINE_SECTION_ORDER } from './routinePresentation'

describe('Routine presentation', () => {
  // 作息类型和「允许匿名作息学习」写的是 routine_mode_cohort_priors,那张表在
  // 生产库里是 0 行,而且没有任何判断路径读它。留着控件等于让用户调一个不起
  // 作用的开关,所以这一版把它们从页面上去掉。
  it('drops the routine-type section that fed a dead cohort pipeline', () => {
    expect(ROUTINE_SECTION_ORDER).not.toContain('routine-type')
  })

  it('puts daily check-in first and keeps sensitivity in the main flow', () => {
    expect(ROUTINE_SECTION_ORDER).toEqual([
      'daily-checkin',
      'sleep',
      'sensitivity',
      'timezone',
    ])
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

    expect(html).toContain('data-routine-sections="daily-checkin,sleep,sensitivity,timezone"')
    expect(html).toContain('Real routine settings')
  })
})
