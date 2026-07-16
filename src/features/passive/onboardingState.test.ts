import { describe, expect, it, vi, beforeEach } from 'vitest'
import {
  getReadinessState,
  getOnboardingKey,
  checkAndMigrateOnboarding,
  saveOnboardingCompleted,
  clearOnboardingCompleted,
} from './onboardingState'

const storeMap = new Map<string, string>()

vi.stubGlobal('localStorage', {
  getItem: (key: string) => storeMap.get(key) ?? null,
  setItem: (key: string, value: string) => storeMap.set(key, value),
  removeItem: (key: string) => storeMap.delete(key),
  clear: () => storeMap.clear(),
})

describe('Onboarding State Gating & Scoping Helpers', () => {
  beforeEach(() => {
    storeMap.clear()
  })

  describe('getReadinessState', () => {
    it('returns not_applicable_plain_web for plain_web regardless of inputs', () => {
      expect(getReadinessState({ platform: 'plain_web', pingOk: true })).toBe('not_applicable_plain_web')
      expect(getReadinessState({ platform: 'plain_web', usageStatsOk: true, motionOk: true, pingOk: true })).toBe('not_applicable_plain_web')
    })

    it('returns ready for android_native only when usage, motion, and ping are all ok', () => {
      expect(getReadinessState({ platform: 'android_native', usageStatsOk: false, motionOk: false, pingOk: false })).toBe('partial')
      expect(getReadinessState({ platform: 'android_native', usageStatsOk: true, motionOk: false, pingOk: false })).toBe('partial')
      expect(getReadinessState({ platform: 'android_native', usageStatsOk: true, motionOk: true, pingOk: false })).toBe('partial')
      expect(getReadinessState({ platform: 'android_native', usageStatsOk: true, motionOk: true, pingOk: true })).toBe('ready')
    })

    it('returns ready for ios, android_pwa, and desktop_tauri when pingOk is true', () => {
      expect(getReadinessState({ platform: 'ios', pingOk: false })).toBe('partial')
      expect(getReadinessState({ platform: 'ios', pingOk: true })).toBe('ready')

      expect(getReadinessState({ platform: 'android_pwa', pingOk: false })).toBe('partial')
      expect(getReadinessState({ platform: 'android_pwa', pingOk: true })).toBe('ready')

      expect(getReadinessState({ platform: 'desktop_tauri', pingOk: false })).toBe('partial')
      expect(getReadinessState({ platform: 'desktop_tauri', pingOk: true })).toBe('ready')
    })
  })

  describe('Scoped local storage keys & migrations', () => {
    const uid = 'user-123'

    it('generates the correct scoped key', () => {
      expect(getOnboardingKey(uid)).toBe('kc.onboardingCompleted.user-123')
    })

    it('returns false and does not write scoped keys when no onboarding flag exists', () => {
      const completed = checkAndMigrateOnboarding(uid, false)
      expect(completed).toBe(false)
      expect(storeMap.has(getOnboardingKey(uid))).toBe(false)
    })

    it('migrates legacy global flag to scoped key and clears the legacy flag', () => {
      storeMap.set('kc.onboardingCompleted', 'true')
      const completed = checkAndMigrateOnboarding(uid, false)
      expect(completed).toBe(true)
      expect(storeMap.get('kc.onboardingCompleted')).toBeUndefined()
      expect(storeMap.has(getOnboardingKey(uid))).toBe(true)

      const parsed = JSON.parse(storeMap.get(getOnboardingKey(uid))!)
      expect(parsed.role).toBe('recipient')
      expect(parsed.version).toBe(1)
      expect(parsed.completedAt).toBeLessThanOrEqual(Date.now())
    })

    it('honors scoped key if role matches', () => {
      saveOnboardingCompleted(uid, true) // caregiver
      expect(checkAndMigrateOnboarding(uid, true)).toBe(true)
      expect(checkAndMigrateOnboarding(uid, false)).toBe(false) // role mismatch
    })

    it('can clear the scoped key', () => {
      saveOnboardingCompleted(uid, false)
      expect(storeMap.has(getOnboardingKey(uid))).toBe(true)
      clearOnboardingCompleted(uid)
      expect(storeMap.has(getOnboardingKey(uid))).toBe(false)
    })
  })
})
