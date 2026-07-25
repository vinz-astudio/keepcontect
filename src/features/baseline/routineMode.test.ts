import { describe, expect, it } from 'vitest'
import {
  ROUTINE_MODES,
  normalizeRoutineMode,
} from '@/features/baseline/routineMode'

describe('Routine mode taxonomy', () => {
  it('uses the three human-accepted canonical values', () => {
    expect(ROUTINE_MODES).toEqual([
      'regular_9to5',
      'semester_break',
      'shift_irregular',
    ])
  })

  it.each([
    ['regular_9to5', 'regular_9to5'],
    ['semester_break', 'semester_break'],
    ['student', 'semester_break'],
    ['shift_irregular', 'shift_irregular'],
    ['shift_worker', 'shift_irregular'],
    ['flexible', 'shift_irregular'],
    ['unknown', 'regular_9to5'],
  ] as const)('normalizes %s to %s', (input, expected) => {
    expect(normalizeRoutineMode(input)).toBe(expected)
  })
})
