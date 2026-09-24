import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'

const root = path.resolve('ios-passive-ping/ios/Sources/KcPassivePingPlugin')
const read = (file: string) => fs.readFileSync(path.join(root, file), 'utf8')

describe('iOS positive-evidence static contract', () => {
  it('preserves unread Health history and reports actual registration outcomes', () => {
    const source = read('HealthWake.swift')
    expect(source).toContain('allQueriesSucceeded')
    expect(source).toMatch(/if allQueriesSucceeded[\s\S]*?set\(end\.timeIntervalSince1970/)
    expect(source).toContain('backgroundDeliveryEnabled')
    expect(source).toContain('queryGeneration')
    expect(source).toContain('queryInFlight')
    expect(source).toContain('lastQuerySucceeded')
  })

  it('re-arms Health and retries history after configure, unlock, and silent push wakes', () => {
    const guard = read('PassiveGuard.swift')
    const configure = guard.slice(guard.indexOf('func configure('), guard.indexOf('func clear()'))
    expect(configure).toContain('HealthWake.shared.resume()')
    expect(guard).toContain('HealthWake.shared.retryHistory()')
    expect(read('HealthWake.swift')).toContain('onWake(captureSample: false, reportCoverageLease: reportCoverageLease)')
    const pushWake = guard.slice(guard.indexOf('func handleWake'), guard.indexOf('// MARK: - CLLocationManagerDelegate'))
    expect(pushWake).toContain('HealthWake.shared.retryHistory(reportCoverageLease: false)')
    expect(pushWake.indexOf('HealthWake.shared.retryHistory')).toBeLessThan(pushWake.indexOf('captureSample(trigger: "push-wake")'))
  })

  it('does not consume failed CoreMotion history or let an old upload finish a new account queue', () => {
    const sample = read('DeviceSample.swift')
    expect(sample).toMatch(/generation == self.historyGeneration, finished.stepsSinceLastSample != nil/)
    const guard = read('PassiveGuard.swift')
    expect(guard).toContain('generation == evidenceSendGeneration')
    expect(guard).toContain('sampleBindingId == self.defaults.string(forKey: Key.evidenceBindingId)')
    expect(guard).toContain('EvidenceUploadPolicy.disposition(')
    expect(guard).toContain('finishBackgroundEvidence(deadline:')
  })

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
