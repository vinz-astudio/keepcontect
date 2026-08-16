import { describe, expect, it } from 'vitest'
import { desktopHasRealUpdate, desktopOfferedVersion } from './desktopOffer'
import { isNewer } from './versionSelection'

describe('desktopOfferedVersion', () => {
  it('reads the version out of the installer file name', () => {
    expect(desktopOfferedVersion(
      'https://github.com/o/r/releases/download/v0.7.3/KeepContact-0.7.3-Setup.exe',
    )).toBe('0.7.3')
  })

  it('falls back to the release tag when the file name carries no version', () => {
    expect(desktopOfferedVersion(
      'https://github.com/o/r/releases/download/v0.7.2/setup.exe',
    )).toBe('0.7.2')
  })

  it('prefers the file name when the tag disagrees, because the file is what runs', () => {
    expect(desktopOfferedVersion(
      'https://github.com/o/r/releases/download/v0.7.3/KeepContact-0.7.1-Setup.exe',
    )).toBe('0.7.1')
  })

  it('reports nothing for the unversioned path that served a stale build', () => {
    expect(desktopOfferedVersion(
      'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe',
    )).toBeNull()
  })

  it('reports nothing when there is no URL at all', () => {
    expect(desktopOfferedVersion(undefined)).toBeNull()
    expect(desktopOfferedVersion(null)).toBeNull()
    expect(desktopOfferedVersion('')).toBeNull()
  })
})

describe('desktopHasRealUpdate', () => {
  it('offers an update the installer can actually deliver', () => {
    expect(desktopHasRealUpdate(
      '0.7.1',
      'https://github.com/o/r/releases/download/v0.7.3/KeepContact-0.7.3-Setup.exe',
      isNewer,
    )).toBe(true)
  })

  it('closes the loop that kept a 0.7.1 install on 0.7.1', () => {
    // Production shape on 2026-08-16: the row said 0.7.2 was available while
    // exe_url still pointed at the 0.7.1 installer. Installing it changed
    // nothing, so the offer returned on the next check, forever.
    expect(desktopHasRealUpdate(
      '0.7.1',
      'https://github.com/o/r/releases/download/v0.7.1/KeepContact-0.7.1-Setup.exe',
      isNewer,
    )).toBe(false)
  })

  it('offers nothing when the URL cannot say what it installs', () => {
    expect(desktopHasRealUpdate(
      '0.7.1',
      'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe',
      isNewer,
    )).toBe(false)
  })
})
