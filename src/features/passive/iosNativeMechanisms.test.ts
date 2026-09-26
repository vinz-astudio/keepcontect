import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
const root = path.resolve('ios-passive-ping/ios/Sources/KcPassivePingPlugin')
const read = (name: string) => fs.readFileSync(path.join(root, name), 'utf8')
describe('iOS native repair wiring', () => {
  it('never promotes protected data availability or persisted wake samples to activity', () => {
    const guard = read('PassiveGuard.swift')
    const wake = guard.slice(guard.indexOf('func handleWake('), guard.indexOf('// MARK: - CLLocationManagerDelegate'))
    expect(wake).not.toContain('recordEvent(')
    expect(guard).toContain('entry["reason"] as? String == "wake-sample"')
    expect(guard).toContain('forName: UIApplication.protectedDataDidBecomeAvailableNotification')
    expect(guard).toContain('recordDirectEvidence(observedAt: Date())')
  })
  it('normalizes a bounded positive interval separately from diagnostic collection time', () => {
    expect(read('MotionEvidenceWindow.swift')).toContain('maximumWidth: TimeInterval = 60')
    expect(read('PassiveGuard.swift')).toContain('observedAt: motionStart')
    expect(read('DeviceSample.swift')).toContain('func commitHistory(')
    expect(read('DeviceSample.swift')).toContain('ProcessInfo.processInfo.systemUptime')
  })
  it('bridges durable notification actions and clears them separately from sensor collection', () => {
    const plugin = read('KcPassivePingPlugin.swift')
    for (const method of ['getPendingNotificationActions', 'completeNotificationAction', 'clearPushNotifications']) {
      expect(plugin).toContain(`CAPPluginMethod(name: "${method}"`)
    }
    expect(plugin).toContain('notifyListeners("notificationActionPending"')
    const tap = read('NotificationTap.swift')
    expect(tap).toContain('NotificationActionQueue.shared.append')
    expect(tap).toContain('"ackSafe": false')
    expect(read('NotifyFeed.swift')).toContain('content.userInfo =')
    expect(plugin).toContain('call.getString("generation")')
    expect(read('NotificationActionQueue.swift')).toContain('matchesPushBinding(item["pushBindingId"] as? String)')
    expect(read('NotificationActionQueue.swift')).toContain('retryPendingRevocations()')
    expect(read('NotificationActionQueue.swift')).toContain('kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly')
    expect(read('NotificationActionQueue.swift')).toContain('body["_legacy_token"] = legacyToken')
    expect(plugin).toContain('call.getString("legacyToken")')
    expect(read('NotificationActionQueue.swift')).toContain('func complete(eventId: String, generation')
  })
})
