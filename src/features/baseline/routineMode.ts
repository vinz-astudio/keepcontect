export const ROUTINE_MODES = [
  'regular_9to5',
  'semester_break',
  'shift_irregular',
] as const

export type RoutineMode = (typeof ROUTINE_MODES)[number]

export function normalizeRoutineMode(value: unknown): RoutineMode {
  if (value === 'semester_break' || value === 'student') return 'semester_break'
  if (
    value === 'shift_irregular' ||
    value === 'shift_worker' ||
    value === 'flexible'
  ) return 'shift_irregular'
  return 'regular_9to5'
}
