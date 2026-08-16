-- The health writer closed and opened intervals in two separate statements.
-- Under READ COMMITTED each statement takes its own snapshot, so a collector
-- that made contact between them could be seen as recovered by the close and
-- still silent by the open, manufacturing an outage that never happened.
--
-- Both operations now run as data-modifying CTEs of one statement, which share
-- a single snapshot. They cannot collide on a row: the close only touches open
-- intervals whose condition has cleared, and the insert only adds intervals
-- whose condition holds.
CREATE OR REPLACE FUNCTION private.evaluate_passive_surface_health(_now timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE _opened integer := 0; _closed integer := 0;
BEGIN
  WITH cond AS MATERIALIZED (
    SELECT * FROM private.passive_surface_health_conditions(_now)
  ), shut AS (
    UPDATE private.passive_surface_health_intervals h
       SET ended_at = greatest(h.started_at, c.closes_at)
      FROM cond c
     WHERE h.binding_id = c.binding_id AND h.reason = c.reason
       AND h.ended_at IS NULL AND NOT c.unhealthy
    RETURNING 1
  ), born AS (
    INSERT INTO private.passive_surface_health_intervals (user_id, binding_id, started_at, reason)
    SELECT c.user_id, c.binding_id, least(c.opens_at, _now), c.reason
      FROM cond c
     WHERE c.unhealthy
       AND NOT EXISTS (
         SELECT 1 FROM private.passive_surface_health_intervals h
          WHERE h.binding_id = c.binding_id AND h.reason = c.reason AND h.ended_at IS NULL)
    RETURNING 1
  )
  SELECT (SELECT count(*) FROM shut)::integer, (SELECT count(*) FROM born)::integer
  INTO _closed, _opened;

  RETURN jsonb_build_object('opened', _opened, 'closed', _closed, 'evaluated_at', _now);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO private.job_failures (job_name, sqlstate, message)
  VALUES ('evaluate_passive_surface_health', SQLSTATE, SQLERRM);
  RETURN jsonb_build_object('error', SQLERRM, 'evaluated_at', _now);
END;
$fn$;
