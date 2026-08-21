import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { MeScreen } from './MeScreen'
import { getEmergencyCapabilities, ME_SECTIONS } from './mePresentation'

describe('Me presentation', () => {
  // 账户和已连接设备合并成一块:它们回答的是同一个问题(这个账号是谁,在哪几台
  // 机器上),而且「连接新设备」本来离用户自己的操作区隔了整整一屏。
  // 一个区块一张卡。紧急联络人和紧急地址原本是两个区块两张卡,回答的却是同一个
  // 问题:出事的时候,别人需要知道什么。
  it('uses the approved five-section order', () => {
    expect(ME_SECTIONS).toEqual([
      'account',
      'safety-checkin',
      'guardian-permissions',
      'emergency',
      'preferences-updates',
    ])
  })

  it('does not advertise multi-card or crisis GPS persistence before runtime support', () => {
    expect(getEmergencyCapabilities({
      multiCardApiAvailable: false,
      gpsContractResolved: false,
    })).toEqual({
      multiCardEditing: false,
      crisisGpsPersistence: false,
    })
  })

  it('enables only the independently available emergency capabilities', () => {
    expect(getEmergencyCapabilities({
      multiCardApiAvailable: true,
      gpsContractResolved: false,
    })).toEqual({
      multiCardEditing: true,
      crisisGpsPersistence: false,
    })
  })

  it('renders every real feature destination in order', () => {
    const content = ME_SECTIONS.reduce<Record<string, ReturnType<typeof createElement>>>((result, key) => {
      result[key] = createElement('span', null, `${key} content`)
      return result
    }, {})
    const html = renderToStaticMarkup(createElement(MeScreen, {
      title: 'Me',
      subtitle: 'Your account, this device, and crisis information.',
      account: content.account,
      safetyCheckin: content['safety-checkin'],
      guardianPermissions: content['guardian-permissions'],
      emergency: content.emergency,
      emergencyGps: createElement('span', null, 'emergency gps content'),
      preferencesUpdates: content['preferences-updates'],
    }))

    const positions = ME_SECTIONS.map((key) => html.indexOf(`${key} content`))
    expect(positions.every((position) => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
  })
})
