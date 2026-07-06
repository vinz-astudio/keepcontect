import { describe, expect, it } from 'vitest'
import { getRoutineModeOptions, getRoutineModeSummary } from '@/features/baseline/routineModeCopy'

describe('routine mode copy', () => {
  it('explains routine mode as a cold-start template in simple language', () => {
    expect(getRoutineModeSummary('zh')).toContain('新用户')
    expect(getRoutineModeSummary('zh')).not.toContain('threshold')
    expect(getRoutineModeSummary('en')).toContain('starting template')
  })

  it('gives every mode a short description', () => {
    for (const option of getRoutineModeOptions('en')) {
      expect(option.description.length).toBeGreaterThan(10)
      expect(option.description.length).toBeLessThan(90)
    }
  })
})
