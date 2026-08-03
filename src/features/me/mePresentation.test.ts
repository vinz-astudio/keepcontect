import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { MeScreen } from './MeScreen'
import { getEmergencyCapabilities, ME_SECTIONS } from './mePresentation'

describe('Me presentation', () => {
  it('uses the approved eight-section order', () => {
    expect(ME_SECTIONS).toEqual([
      'account',
      'safety-checkin',
      'this-device',
      'linked-devices',
      'emergency-contacts',
      'emergency-addresses',
      'emergency-gps',
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

  it('renders all eight real feature destinations in order', () => {
    const content = ME_SECTIONS.reduce<Record<string, ReturnType<typeof createElement>>>((result, key) => {
      result[key] = createElement('span', null, `${key} content`)
      return result
    }, {})
    const html = renderToStaticMarkup(createElement(MeScreen, {
      title: 'Me',
      subtitle: 'Your account, this device, and crisis information.',
      account: content.account,
      safetyCheckin: content['safety-checkin'],
      thisDevice: content['this-device'],
      linkedDevices: content['linked-devices'],
      emergencyContacts: content['emergency-contacts'],
      emergencyAddresses: content['emergency-addresses'],
      emergencyGps: content['emergency-gps'],
      preferencesUpdates: content['preferences-updates'],
    }))

    const positions = ME_SECTIONS.map((key) => html.indexOf(`${key} content`))
    expect(positions.every((position) => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
  })
})
