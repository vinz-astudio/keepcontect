import { getRoutineModeOptions } from '@/features/baseline/routineModeCopy'
import type { RoutineMode } from '@/features/baseline/routineMode'

export const ROUTINE_SECTION_ORDER = [
  'sleep',
  'routine-type',
  'sensitivity',
  'timezone-privacy',
] as const

export const ROUTINE_TYPE_OPTIONS = getRoutineModeOptions('en')

export function resolveRoutineSaveState(
  previous: RoutineMode,
  requested: RoutineMode,
  success: boolean,
): { value: RoutineMode; status: 'saved' | 'rolled-back' } {
  return success
    ? { value: requested, status: 'saved' }
    : { value: previous, status: 'rolled-back' }
}
