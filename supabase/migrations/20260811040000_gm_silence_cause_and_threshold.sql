-- GM console: say which kind of silence this is, and on what threshold.
--
-- The console showed `silent` for anyone with no activity ping in 24 hours and
-- stopped there, which collapses the two things a GM most needs to tell apart.
-- Karma Cheki on 2026-08-10 is the case: three escalations to terminal, and
-- from the console it looked identical to a person who had gone quiet. It was
-- not. Her phone was accepting pushes the whole time — `delivery_outcome` was
-- `sent` — and nothing answered them, because the app had been killed. The
-- alerts said so, with cause `dark_device`, but the console never showed the
-- cause.
--
-- Those two states call for opposite actions. A person who has gone quiet is a
-- welfare question and belongs to the alert funnel. A dark device is a
-- maintenance question: nobody is watching, and telling the group that somebody
-- may be in danger is the wrong move — it spends the group's willingness to
-- respond on a technical fault. ADR-0039 puts it as: a known failure must be
-- visible, and must not be dressed up as danger.
--
-- So two additions.
--
-- 1. What kind of silence this is, distinguished by evidence rather than by
--    guesswork: `device_state.last_heartbeat_at` says whether the device is
--    still reporting at all. Heartbeat fresh but no activity is a person being
--    quiet. Heartbeat stale as well means we lost the device, and the honest
--    reading is that we cannot see this person, not that this person is fine
--    or in trouble.
--
-- 2. The threshold each account is actually judged against, plus enough of its
--    basis to argue with. `private.silence_threshold` returns NULL where there
--    is no usable evidence (ADR-0037), and a NULL threshold means no silence
--    alert can fire for that person at all — which is a fact a GM currently has
--    no way to discover. Showing the number without its basis would invite the
--    opposite error, so the sample size and the window it was learned from come
--    with it.
--
-- Read-only, GM-gated exactly as before. No new authority.

CREATE OR REPLACE FUNCTION public.gm_list_clients()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
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
        'alerted', al.stage IS NOT NULL,
        -- Why the alert exists, not merely that it does. `dark_device` is a
        -- statement about equipment; `silence` is a statement about a person.
        'alert_cause', al.cause,
        'alert_stage', al.stage,
        'alert_opened_at', al.opened_at,
        'status',
          CASE
            WHEN al.stage IS NOT NULL THEN 'alert'
            WHEN bp.last_at IS NULL THEN 'never'
            WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
            WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
            ELSE 'silent'
          END,
        -- Which kind of quiet this is, whether or not an alert is open. The
        -- device heartbeat is the discriminator: it keeps arriving while the
        -- collector runs, and stops when the app is killed or the phone is off.
        'silence_kind',
          CASE
            WHEN bp.last_at IS NOT NULL AND bp.last_at > now() - interval '6 hours'
              THEN NULL
            WHEN ds.last_heartbeat_at IS NULL THEN 'unknown'
            WHEN ds.last_heartbeat_at > now() - interval '1 hour'
              THEN 'person_quiet'
            ELSE 'device_dark'
          END,
        -- The line this account is actually judged against. NULL is not zero
        -- and not a default: it means no usable evidence, so no silence alert
        -- can fire for this person at all.
        'threshold_minutes',
          round(extract(epoch FROM private.silence_threshold(p.id)) / 60)::integer,
        -- Enough basis to disagree with the number.
        'threshold_basis', CASE WHEN nb.user_id IS NULL THEN NULL ELSE jsonb_build_object(
          'has_usable_signal', nb.has_usable_signal,
          'through_date', nb.through_date,
          'computed_at', nb.computed_at,
          'sensitivity', nb.sensitivity,
          'buffer_minutes', nb.buffer_minutes,
          'normal_upper_bound_minutes', nb.normal_upper_bound_minutes,
          'largest_gap_minutes', nb.largest_gap_minutes,
          'gap_count', nb.gap_count,
          'evidence_days', nb.evidence_days,
          'sleep_window_applied', nb.sleep_window_applied
        ) END,
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
      -- The alert that is actually escalating, and its cause. Same predicate as
      -- the old `alerted` flag, so the badge cannot disagree with the reason
      -- printed beside it.
      LEFT JOIN LATERAL (
        SELECT a.cause, a.stage, a.opened_at
        FROM public.alerts a
        WHERE a.user_id = p.id
          AND a.status = 'open'
          AND a.stage in ('group','community','terminal')
        ORDER BY a.opened_at DESC
        LIMIT 1
      ) al ON true
      -- The bounds row the live threshold is read from: most recent first, so
      -- the basis shown is the basis used.
      LEFT JOIN LATERAL (
        SELECT b.*
        FROM public.account_normal_bounds b
        WHERE b.user_id = p.id
        ORDER BY b.through_date DESC, b.computed_at DESC
        LIMIT 1
      ) nb ON true
      LEFT JOIN public.gm_mutes mu ON mu.user_id = p.id
    ) s
  ), '[]'::jsonb);
END;
$function$;
