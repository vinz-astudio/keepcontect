-- GM Mute: allow GM to temporarily suppress alerts for specific users.
-- Adds gm_mutes table, mute/unmute RPCs, modifies process_escalations + gm_list_clients.

-- 1) gm_mutes table
CREATE TABLE IF NOT EXISTS public.gm_mutes (
  user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  muted_by    uuid NOT NULL REFERENCES auth.users(id),
  muted_at    timestamptz NOT NULL DEFAULT now(),
  muted_until timestamptz,          -- null = indefinite until manual unmute
  reason      text NOT NULL DEFAULT ''
);
ALTER TABLE public.gm_mutes ENABLE ROW LEVEL SECURITY;
-- No direct RLS policies — all access via SECURITY DEFINER RPCs.

-- 2) RPC: mute a user (GM-only)
CREATE OR REPLACE FUNCTION public.gm_mute_user(
  _target uuid,
  _until  timestamptz DEFAULT NULL,
  _reason text DEFAULT ''
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden'; END IF;
  INSERT INTO public.gm_mutes (user_id, muted_by, muted_at, muted_until, reason)
  VALUES (_target, auth.uid(), now(), _until, _reason)
  ON CONFLICT (user_id) DO UPDATE
    SET muted_by = auth.uid(), muted_at = now(), muted_until = _until, reason = _reason;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gm_mute_user(uuid, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_mute_user(uuid, timestamptz, text) TO authenticated;

-- 3) RPC: unmute a user (GM-only)
CREATE OR REPLACE FUNCTION public.gm_unmute_user(_target uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden'; END IF;
  DELETE FROM public.gm_mutes WHERE user_id = _target;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gm_unmute_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_unmute_user(uuid) TO authenticated;

-- 4) Modify process_escalations: skip muted users when raising NEW alerts.
--    Existing open alerts are NOT affected (they continue to escalate normally).
CREATE OR REPLACE FUNCTION public.process_escalations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval '30 minutes';
  _group_dur  CONSTANT interval := interval '1 hour';
  _comm_dur   CONSTANT interval := interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean := false;
BEGIN
  -- First clear open alerts that no longer match current account-level truth.
  FOR r IN
    SELECT a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    FROM public.alerts a
    LEFT JOIN public.device_state ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) as last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        AND ingest_version = 2
        AND abs(extract(epoch from (received_at - at))) <= 300
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) bp ON true
    WHERE a.status = 'open'
      AND a.cause in ('silence', 'dark_device')
      AND (
        (
          a.cause = 'silence'
          AND bp.last_at IS NOT NULL
          AND (
            private.is_in_sleep_window(a.user_id, now())
            OR now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        OR (
          a.cause = 'dark_device'
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval '18 hours'
        )
      )
  LOOP
    UPDATE public.alerts
      SET status = 'resolved', resolved_at = now(), resolved_by = null, updated_at = now()
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note)
      VALUES (r.id, 'auto_resolved', 'condition_cleared');
    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    FROM public.device_state ds
    WHERE (
      ds.status = 'alert'
      OR now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.is_in_sleep_window(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch from (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND exists (SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = ds.user_id and gm.monitored and gm.status = 'active')
      AND NOT exists (SELECT 1 FROM public.alerts a WHERE a.user_id = ds.user_id and a.status = 'open')
      AND NOT exists (
        SELECT 1 FROM public.alerts recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause in ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      -- GM Mute: skip users who are currently muted
      AND NOT exists (
        SELECT 1 FROM public.gm_mutes m
        WHERE m.user_id = ds.user_id
          AND (m.muted_until IS NULL OR m.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    VALUES (r.user_id, CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' end,
            'self', now(), now() + _self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events (alert_id, kind) values (_aid, 'raised');
    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT * FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
              WHEN 'self' THEN 'group'
              WHEN 'group' THEN 'community'
              WHEN 'community' THEN 'terminal'
              ELSE 'terminal' end;
    UPDATE public.alerts
      SET stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = CASE _new WHEN 'group' THEN now() + _group_dur
                                    WHEN 'community' THEN now() + _comm_dur
                                    ELSE null end
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note) VALUES (r.id, 'escalated', _new);
    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.process_escalations() FROM public, anon, authenticated;

-- 5) Modify gm_list_clients: expose muted_until field
CREATE OR REPLACE FUNCTION public.gm_list_clients()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT private.is_admin(_uid) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(obj ORDER BY nm asc, ls desc nulls last)
    FROM (
      SELECT jsonb_build_object(
        'user_id', p.id,
        'name', coalesce(nullif(p.display_name,''), left(p.id::text,8)),
        'platform', c.platform,
        'app_version', c.app_version,
        'first_seen_at', c.first_seen_at,
        'last_seen_at', c.last_seen_at,
        'last_heartbeat_at', ds.last_heartbeat_at,
        'last_behavior_at', bp.last_at,
        'alerted', exists (
          SELECT 1 FROM public.alerts a
          WHERE a.user_id = p.id and a.status = 'open'
            AND a.stage in ('group','community','terminal')
        ),
        'status',
          CASE
            WHEN exists (
              SELECT 1 FROM public.alerts a
              WHERE a.user_id = p.id and a.status = 'open'
                AND a.stage in ('group','community','terminal')
            ) THEN 'alert'
            WHEN bp.last_at IS NULL THEN 'never'
            WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
            WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
            ELSE 'silent'
          END,
        'muted_until',
          CASE
            WHEN mu.user_id IS NOT NULL
              AND (mu.muted_until IS NULL OR mu.muted_until > now())
            THEN coalesce(mu.muted_until::text, 'indefinite')
            ELSE null
          END
      ) as obj,
      coalesce(nullif(p.display_name,''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      FROM public.profiles p
      LEFT JOIN public.clients c ON c.user_id = p.id
      LEFT JOIN public.device_state ds ON ds.user_id = p.id
      LEFT JOIN LATERAL (
        SELECT max(received_at) as last_at
        FROM public.behavior_pings
        WHERE user_id = p.id
          AND ingest_version = 2
          AND abs(extract(epoch from (received_at - at))) <= 300
      ) bp ON true
      LEFT JOIN public.gm_mutes mu ON mu.user_id = p.id
    ) s
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.gm_list_clients() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_list_clients() TO authenticated;
