import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'

const root = path.resolve('ios-passive-ping/ios/Sources/KcPassivePingPlugin')
const read = (file: string) => fs.readFileSync(path.join(root, file), 'utf8')

describe('iOS positive-evidence static contract', () => {
  it('turns a Health wake into a positive history query, never an unconditional check-in', () => {
    const source = read('HealthWake.swift')
    expect(source).toContain('HKSampleQuery')
    expect(source).toContain('quantity.doubleValue')
    expect(source).toContain('recordMotionEvidence')
    expect(source).not.toContain('recordEvent(reason: "health-wake"')
    expect(source).toContain('completionHandler()')
  })

  it('promotes positive pedestrian samples and excludes automotive-only motion', () => {
    const source = read('DeviceSample.swift')
    expect(source).toContain('hasPositivePedestrianMotion')
    expect(source).toMatch(/stepsSinceLastSample.*> 0|floorsSinceLastSample.*> 0/s)
    expect(source).toContain('dominantActivity != "automotive"')

    const payload = source.slice(source.indexOf('func asPayload'), source.indexOf('final class DeviceSampleCollector'))
    expect(payload).not.toMatch(/put\("(?:motion_|steps_|floors_|dominant_activity|activity_confidence)/)
  })

  it('keeps location as a coordinate-blind wake with honest force-quit wording', () => {
    const guard = read('PassiveGuard.swift')
    const delegate = guard.slice(
      guard.indexOf('func locationManager(_ manager: CLLocationManager, didUpdateLocations'),
      guard.indexOf('func locationManager(_ manager: CLLocationManager, didFailWithError'),
    )
    expect(delegate).not.toMatch(/locations\s*[.\[]/)
    expect(delegate).not.toContain('recordEvent(')
    expect(guard).not.toMatch(/^\s*locationManager\.startUpdatingLocation\(\)/m)
    expect(guard).toContain('system termination')
    expect(guard).toContain('force-quit remains unproven')

    const plist = fs.readFileSync(path.resolve('ios/App/App/Info.plist'), 'utf8')
    expect(plist).not.toContain('<string>location</string>')
  })

  it('requires stable charging and clears Keychain credentials and the queue', () => {
    const guard = read('PassiveGuard.swift')
    expect(guard).toContain('powerStableSeconds: TimeInterval = 5')
    expect(guard).toContain('powerCorrelationSeconds: TimeInterval = 60')
    expect(guard).toContain('SecItemAdd')
    expect(guard).toContain('SecItemDelete')
    expect(guard).toContain('evidenceQueue')
    expect(guard).toContain('evidenceNextSequence')
  })
})
