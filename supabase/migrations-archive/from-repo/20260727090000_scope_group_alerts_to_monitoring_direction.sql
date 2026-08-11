-- A user's monitoring direction is group-scoped. A global open alert may
-- legitimately exist because the user remains monitored in another group,
-- but it must not surface inside a group where this membership opted out.

CREATE OR REPLACE FUNCTION public.get_group_activity_view(_group uuid, _view text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''), 'group');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF _mode NOT IN ('watch', 'group') THEN RAISE EXCEPTION 'invalid activity view'; END IF;

  SELECT EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id and gm.user_id = _uid
             AND gm.role = 'admin' and gm.status = 'active'
         ),
         coalesce(me.watching, false)
    INTO _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id and me.user_id = _uid and me.status = 'active'
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        CASE
          WHEN m.user_id = _uid THEN 'self'
          WHEN not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) THEN 'hidden'
          WHEN coalesce(al.alerted, false) THEN 'alert'
          WHEN bp.last_at IS NULL THEN 'unknown'
          WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
          WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
          ELSE 'silent'
        END,
      'hours',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ), '[]'::jsonb) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) as last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT m.monitored AND exists (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id and a.status = 'open'
        AND a.stage in ('group', 'community', 'terminal')
    ) as alerted
  ) al ON true
  WHERE m.group_id = _group
    AND m.status = 'active'
    AND (
      _mode = 'group'
      OR m.user_id = _uid
      OR (_i_watching and m.monitored)
    );

  RETURN jsonb_build_object(
    'visibility', CASE WHEN _mode = 'watch' THEN 'watchers_only' ELSE 'group_wide' END,
    'view', _mode,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', _members
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_group_activity(_group uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT g.activity_visibility,
         EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id AND gm.user_id = _uid
             AND gm.role = 'admin' AND gm.status = 'active'
         ),
         coalesce(me.watching, false)
    INTO _visibility, _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id AND me.user_id = _uid AND me.status = 'active'
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        CASE
          WHEN m.user_id = _uid THEN 'self'
          WHEN NOT coalesce(us.share_activity, true) AND NOT coalesce(al.alerted, false) THEN 'hidden'
          WHEN _visibility = 'watchers_only' AND NOT _i_watching AND NOT coalesce(al.alerted, false) THEN 'hidden'
          WHEN coalesce(al.alerted, false) THEN 'alert'
          WHEN bp.last_at IS NULL THEN 'unknown'
          WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
          WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
          ELSE 'silent'
        END,
      'hours',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) AS last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT m.monitored AND EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id AND a.status = 'open'
        AND a.stage IN ('group', 'community', 'terminal')
    ) AS alerted
  ) al ON true
  WHERE m.group_id = _group AND m.status = 'active';

  RETURN jsonb_build_object(
    'visibility', _visibility,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', coalesce(_members, '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_group_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_activity(uuid) TO authenticated;
