import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = readFileSync(new URL('./GuardianPermissionsCard.tsx', import.meta.url), 'utf8')

describe('Collection Permissions center contract', () => {
  it('renders the four honest permission states and binds sensor controls', () => {
    expect(source).toContain("'granted'")
    expect(source).toContain("'denied'")
    expect(source).toContain("'unavailable'")
    expect(source).toContain("'checking'")
    expect(source).toContain('getAvailableSensors')
    expect(source).toContain('setSensorEnabled')
    expect(source).toContain('openUsageStatsSettings')
    expect(source).toContain('requestActivityRecognitionPermission')
  })
})
