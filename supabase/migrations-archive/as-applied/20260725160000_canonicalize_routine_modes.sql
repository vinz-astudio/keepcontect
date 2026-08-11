-- ADR-0023: canonical Routine-mode taxonomy for candidate-only alert learning.
-- This migration deliberately does not alter the live alert state machine.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE routine_pattern IS NOT NULL
      AND routine_pattern NOT IN (
        'regular_9to5', 'semester_break', 'shift_irregular',
        'student', 'shift_worker', 'flexible'
      )
  ) THEN
    RAISE EXCEPTION 'unknown routine_pattern blocks canonical migration';
  END IF;
END;
$$;

UPDATE public.profiles
SET routine_pattern = CASE routine_pattern
  WHEN 'student' THEN 'semester_break'
  WHEN 'shift_worker' THEN 'shift_irregular'
  WHEN 'flexible' THEN 'shift_irregular'
  ELSE routine_pattern
END
WHERE routine_pattern IN ('student', 'shift_worker', 'flexible');

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_routine_pattern_canonical
  CHECK (routine_pattern IN (
    'regular_9to5', 'semester_break', 'shift_irregular'
  ));

CREATE OR REPLACE FUNCTION private.canonical_routine_mode(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE _value
    WHEN 'semester_break' THEN 'semester_break'
    WHEN 'student' THEN 'semester_break'
    WHEN 'shift_irregular' THEN 'shift_irregular'
    WHEN 'shift_worker' THEN 'shift_irregular'
    WHEN 'flexible' THEN 'shift_irregular'
    ELSE 'regular_9to5'
  END;
$$;

CREATE TABLE public.routine_mode_cohort_invalidations (
  routine_mode text PRIMARY KEY CHECK (routine_mode IN (
    'regular_9to5', 'semester_break', 'shift_irregular'
  )),
  invalidated_at timestamptz NOT NULL
);

ALTER TABLE public.routine_mode_cohort_invalidations ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION private.invalidate_routine_mode_cohort()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.routine_mode_cohort_invalidations (
    routine_mode,
    invalidated_at
  )
  SELECT affected.routine_mode, timestamped.invalidated_at
  FROM (
    SELECT DISTINCT routine_mode
    FROM (
      VALUES
        (private.canonical_routine_mode(OLD.routine_pattern)),
        (private.canonical_routine_mode(NEW.routine_pattern))
    ) AS normalized(routine_mode)
  ) AS affected
  CROSS JOIN (SELECT clock_timestamp() AS invalidated_at) AS timestamped
  ON CONFLICT (routine_mode) DO UPDATE
  SET invalidated_at = EXCLUDED.invalidated_at;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_routine_mode_cohort_invalidation
ON public.profiles;

CREATE TRIGGER on_profile_routine_mode_cohort_invalidation
AFTER UPDATE OF routine_pattern, consent_data_sharing
ON public.profiles
FOR EACH ROW
WHEN (
  OLD.routine_pattern IS DISTINCT FROM NEW.routine_pattern
  OR OLD.consent_data_sharing IS DISTINCT FROM NEW.consent_data_sharing
)
EXECUTE FUNCTION private.invalidate_routine_mode_cohort();

REVOKE ALL PRIVILEGES ON TABLE public.routine_mode_cohort_invalidations
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.canonical_routine_mode(text)
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.invalidate_routine_mode_cohort()
FROM PUBLIC, anon, authenticated, service_role;
