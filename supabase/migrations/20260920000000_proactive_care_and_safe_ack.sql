-- Proactive Care & Self-Stage Safe Acknowledge Migration
-- 1. Calls notify_stage in maybe_open_passive_checkin_alert so self-stage notification is sent.
-- 2. Aligns self-stage notification copy to gentle care wording.
-- 3. Provides public.acknowledge_safe() for lock-screen 1-tap resolution.
-- 4. Bridges record_passive_evidence to behavior_pings so Group Board stays in sync.

-- ---------------------------------------------------------------------------
-- 1. maybe_open_passive_checkin_alert with proactive notification dispatch
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.maybe_open_passive_checkin_alert(
  _user_id uuid, _epoch_id uuid, _contract_id uuid, _now timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _chain bigint; _alert_id uuid; _grace interval;
BEGIN
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_user_id;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions WHERE id=_contract_id;
  _chain := private.passive_miss_chain(_epoch_id);
  IF _account.engine_mode<>'passive_checkin' OR _account.kill_switch_active
     OR _chain<_contract.consecutive_misses
     OR private.passive_sleep_relaxed(_user_id,_contract_id,_now)
     OR EXISTS(SELECT 1 FROM public.alerts WHERE user_id=_user_id AND status='open') THEN
    RETURN NULL;
  END IF;
  _grace := pg_catalog.make_interval(
    mins => coalesce(_contract.response_grace_minutes, 30));
  INSERT INTO public.alerts(user_id,cause,stage,stage_entered_at,next_deadline,requires_explicit_unlock)
  VALUES(_user_id,'silence','self',_now,_now+_grace,true)
  RETURNING id INTO _alert_id;
  INSERT INTO public.alert_events(alert_id,kind,note)
  VALUES(_alert_id,'raised','passive_checkin_consecutive_misses');
  INSERT INTO private.passive_alert_causal_windows(alert_id,window_id,ordinal)
  SELECT _alert_id,id,(row_number() OVER(ORDER BY ordinal)-1)::integer
  FROM (SELECT id,ordinal FROM public.passive_checkin_windows
    WHERE epoch_id=_epoch_id AND outcome='missed'
    ORDER BY ordinal DESC LIMIT _contract.consecutive_misses) causal
  ORDER BY ordinal;

  -- Proactive care: trigger self stage notification to subject device
  PERFORM private.notify_stage(_alert_id, _user_id, 'self');

  RETURN _alert_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Update notify_stage and notify_stage_before_passive_checkin wording
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.notify_stage(_alert_id uuid,_user uuid,_stage text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _name text; _params jsonb; _kind text; _body text;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=_alert_id) THEN
    PERFORM private.notify_stage_before_passive_checkin(_alert_id,_user,_stage);
    RETURN;
  END IF;

  -- 本人自证/关怀阶段：温和语气，低打扰
  IF _stage='self' THEN
    SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    VALUES (_user,_alert_id,'self',
      'KC 正在确认您的安全。点开或轻按即完成确认，不会打扰亲友。',
      jsonb_build_object('name',_name,'cause','passive_checkin_lost_contact'));
    RETURN;
  END IF;

  SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;

  SELECT causal_window.miss_kind INTO _kind
  FROM private.passive_alert_causal_windows AS causal
  JOIN public.passive_checkin_windows AS causal_window ON causal_window.id = causal.window_id
  WHERE causal.alert_id = _alert_id
  ORDER BY causal_window.ordinal DESC LIMIT 1;
  _kind := coalesce(_kind,'silent');

  _params:=jsonb_build_object('name',_name,'cause','passive_checkin_lost_contact','miss_kind',_kind);

  IF _stage='group' THEN
    _body := CASE _kind
      WHEN 'collection_restricted' THEN
        'KC 无法确认 '||_name||' 的情况：设备上的检测被关闭了。请尝试联系本人。'
      WHEN 'device_unreachable' THEN
        _name||' 的设备与 KC 失去联系，可能已关机或没电。请尝试联系本人确认。'
      ELSE
        _name||' 一直没有动静，KC 也联系不上。请尝试联系本人确认。'
    END;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT recipient,_alert_id,'group',_body,_params
    FROM (
      SELECT watcher.user_id AS recipient FROM public.group_members subject
      JOIN public.group_members watcher ON watcher.group_id=subject.group_id
      WHERE subject.user_id=_user AND subject.monitored AND subject.status='active'
        AND watcher.watching AND watcher.status='active' AND watcher.user_id<>_user
      UNION SELECT guardian_id FROM public.guardianships
      WHERE ward_id=_user AND status='active'
    ) recipients;

  ELSIF _stage='community' THEN
    _body := CASE _kind
      WHEN 'collection_restricted' THEN
        'KC 仍然无法确认 '||_name||' 的情况且小组尚未响应，请协助联系。'
      WHEN 'device_unreachable' THEN
        'KC 与 '||_name||' 的设备持续失去联系且小组尚未响应，请协助联系。'
      ELSE
        'KC 与 '||_name||' 持续失去联系且小组尚未响应，请协助联系。'
    END;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT member.user_id,_alert_id,'community',_body,_params
    FROM public.community_members subject
    JOIN public.community_members member ON member.community_id=subject.community_id
    WHERE subject.user_id=_user AND subject.status='active'
      AND member.status='active' AND member.user_id<>_user;

  ELSIF _stage='terminal' THEN
    _body := CASE _kind
      WHEN 'collection_restricted' THEN
        '紧急：KC 持续无法确认 '||_name||' 的情况。已解锁其资料，请上门探视或协助报警。'
      WHEN 'device_unreachable' THEN
        '紧急：KC 与 '||_name||' 的设备持续失去联系。已解锁其资料，请上门探视或协助报警。'
      ELSE
        '紧急：'||_name||' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。'
    END;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT recipient,_alert_id,'terminal',_body,_params
    FROM (
      SELECT watcher.user_id AS recipient FROM public.group_members subject
      JOIN public.group_members watcher ON watcher.group_id=subject.group_id
      WHERE subject.user_id=_user AND subject.monitored AND subject.status='active'
        AND watcher.watching AND watcher.status='active' AND watcher.user_id<>_user
      UNION SELECT guardian_id FROM public.guardianships
      WHERE ward_id=_user AND status='active'
    ) recipients;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION private.notify_stage_before_passive_checkin(
  _alert_id uuid, _user uuid, _stage text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
declare _name text; _p jsonb; _sos boolean;
begin
  select coalesce(display_name,'') into _name from public.profiles where id = _user;
  select (cause = 'sos') into _sos from public.alerts where id = _alert_id;
  _p := jsonb_build_object('name', _name);

  if _stage = 'self' then
    if not _sos then
      insert into public.notifications (recipient_id, alert_id, kind, body, params)
      values (_user, _alert_id, 'self',
        'KC 正在确认您的安全。点开或轻按即完成确认，不会打扰亲友。', _p);
    end if;
    return;
  end if;

  if _stage = 'group' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then 'sos' else 'group' end,
      case when _sos then _name || ' 发出了紧急求助！'
           else _name || ' 出现异常沉默，请尽快联系确认其安全。' end,
      _p
    from (
      select w.user_id as r from public.group_members t
        join public.group_members w on w.group_id = t.group_id
        where t.user_id = _user and t.monitored and t.status = 'active'
          and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select guardian_id as r from public.guardianships
        where ward_id = _user and status = 'active'
    ) s;
  elsif _stage = 'community' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct m.user_id, _alert_id, 'community',
      '社区警示：' || _name || ' 长时间失联且其小组无人响应，请协助推动联系。', _p
    from public.community_members m
    where m.community_id in (
      select community_id from public.community_members where user_id = _user and status = 'active'
    ) and m.user_id <> _user and m.status = 'active';
  elsif _stage = 'terminal' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id, 'terminal',
      '紧急：' || _name || ' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。', _p
    from (
      select w.user_id as r from public.group_members t
        join public.group_members w on w.group_id = t.group_id
        where t.user_id = _user and t.monitored and t.status = 'active'
          and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select guardian_id as r from public.guardianships
        where ward_id = _user and status = 'active'
    ) s;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. public.acknowledge_safe for 1-tap lock screen / in-app resolution
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.acknowledge_safe(_alert_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _target_alert_id uuid;
  _cleared boolean := false;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  IF _alert_id IS NOT NULL THEN
    SELECT id INTO _target_alert_id
    FROM public.alerts
    WHERE id = _alert_id AND user_id = _uid AND status = 'open' AND stage = 'self';
  ELSE
    SELECT id INTO _target_alert_id
    FROM public.alerts
    WHERE user_id = _uid AND status = 'open' AND stage = 'self'
    ORDER BY stage_entered_at DESC
    LIMIT 1;
  END IF;

  IF _target_alert_id IS NOT NULL THEN
    UPDATE public.alerts
    SET status = 'resolved',
        resolved_at = clock_timestamp(),
        resolved_by = _uid,
        updated_at = clock_timestamp()
    WHERE id = _target_alert_id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind, note)
    VALUES (_target_alert_id, _uid, 'resolved', 'self_acknowledged');

    _cleared := true;
  END IF;

  -- Record manual checkin behavior ping to refresh liveness
  BEGIN
    PERFORM private.insert_behavior_ping(_uid, extensions.gen_random_uuid(), clock_timestamp(), 'manual', 'manual_checkin');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Clean up active self/concern notifications for this user
  DELETE FROM public.notifications
  WHERE recipient_id = _uid AND kind in ('self', 'concern');

  -- Close any missed windows for this user and finalize
  BEGIN
    UPDATE public.passive_checkin_windows
    SET outcome = 'checked_in', finalized_at = clock_timestamp()
    WHERE user_id = _uid AND outcome = 'missed';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  PERFORM private.trigger_push_dispatch();

  RETURN jsonb_build_object('ok', true, 'cleared_alert', _cleared);
END;
$$;

REVOKE ALL ON FUNCTION public.acknowledge_safe(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_safe(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Bridge record_passive_evidence to behavior_pings
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.record_passive_evidence(
  _subject_id uuid, _binding_id uuid, _credential text, _authenticated_path boolean,
  _event_id uuid, _sequence bigint, _observed_at timestamptz, _evidence_class text,
  _qualification_policy_version text, _correlation_id text, _qualification_facts jsonb,
  _query_started_at timestamptz, _query_ended_at timestamptz, _query_succeeded boolean
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _binding private.passive_collector_bindings%ROWTYPE;
  _registry private.passive_surface_registry%ROWTYPE;
  _existing private.passive_evidence_events%ROWTYPE;
  _now timestamptz := clock_timestamp();
  _payload_sha text;
  _epoch_id uuid;
  _contract_id uuid;
  _started_at timestamptz;
  _interval_minutes integer;
  _window_id uuid;
  _window_start timestamptz;
  _window_end timestamptz;
  _event_row_id uuid;
BEGIN
  SELECT * INTO _binding FROM private.passive_collector_bindings WHERE id = _binding_id FOR UPDATE;
  IF NOT FOUND OR _binding.user_id <> _subject_id THEN RETURN 'unregistered_binding'; END IF;
  IF _binding.revoked_at IS NOT NULL THEN
    INSERT INTO private.passive_evidence_incidents(user_id,binding_id,event_id,collector_sequence,reason)
    VALUES (_subject_id,_binding_id,_event_id,_sequence,'revoked_binding');
    RETURN 'revoked';
  END IF;
  IF NOT _authenticated_path AND (
    _credential IS NULL OR encode(extensions.digest(_credential, 'sha256'), 'hex') <> _binding.credential_sha256
  ) THEN
    INSERT INTO private.passive_evidence_incidents(user_id,binding_id,event_id,collector_sequence,reason)
    VALUES (_subject_id,_binding_id,_event_id,_sequence,'credential_mismatch');
    RETURN 'credential_mismatch';
  END IF;
  SELECT * INTO STRICT _registry FROM private.passive_surface_registry WHERE surface_type = _binding.surface_type;
  IF _authenticated_path AND _binding.surface_type <> 'pwa_browser' THEN RETURN 'invalid'; END IF;
  IF _qualification_policy_version IS DISTINCT FROM 'passive-qualification-v1'
     OR NOT (_evidence_class = ANY(_registry.allowed_evidence_classes))
     OR _sequence < 0 OR _observed_at IS NULL
     OR _observed_at > _now + interval '5 minutes'
     OR _observed_at < _now - interval '7 days'
     OR jsonb_typeof(coalesce(_qualification_facts, '{}'::jsonb)) <> 'object'
     OR (_correlation_id IS NOT NULL AND length(_correlation_id) NOT BETWEEN 1 AND 128)
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(coalesce(_qualification_facts,'{}'::jsonb)) AS key
       WHERE key NOT IN (
         'interaction','steps_positive','floors_positive','pedestrian','automotive',
         'prior_power_state','new_power_state','stable_for_ms'
       )
     )
     OR ((_query_started_at IS NULL) <> (_query_ended_at IS NULL))
     OR (_query_started_at IS NOT NULL AND _query_started_at > _query_ended_at)
     THEN RETURN 'invalid'; END IF;

  IF _evidence_class = 'direct_device_use' AND coalesce((_qualification_facts->>'interaction')::boolean, false) IS NOT TRUE
     OR _evidence_class = 'personal_device_motion' AND NOT (
       coalesce((_qualification_facts->>'pedestrian')::boolean, false)
       AND NOT coalesce((_qualification_facts->>'automotive')::boolean, false)
       AND (coalesce((_qualification_facts->>'steps_positive')::boolean, false)
            OR coalesce((_qualification_facts->>'floors_positive')::boolean, false))
     )
     OR _evidence_class = 'power_transition' AND NOT (
       _qualification_facts->>'prior_power_state' IN ('charging','not_charging')
       AND _qualification_facts->>'new_power_state' IN ('charging','not_charging')
       AND _qualification_facts->>'prior_power_state' <> _qualification_facts->>'new_power_state'
       AND coalesce((_qualification_facts->>'stable_for_ms')::integer, 0) >= 5000
     ) THEN RETURN 'invalid'; END IF;

  IF _observed_at < _now - interval '5 minutes' AND NOT (
    _registry.supports_history AND _query_succeeded
    AND _query_started_at IS NOT NULL AND _query_ended_at IS NOT NULL
    AND _query_started_at <= _observed_at AND _observed_at <= _query_ended_at
  ) THEN RETURN 'invalid'; END IF;

  _payload_sha := private.passive_payload_sha256(
    _binding_id,_event_id,_sequence,_observed_at,_evidence_class,
    _qualification_policy_version,_correlation_id,coalesce(_qualification_facts,'{}'::jsonb),
    _query_started_at,_query_ended_at,_query_succeeded
  );
  SELECT * INTO _existing FROM private.passive_evidence_events WHERE event_id = _event_id;
  IF FOUND THEN
    IF _existing.binding_id = _binding_id AND _existing.payload_sha256 = _payload_sha THEN
      UPDATE private.passive_collector_bindings SET last_contact_at = _now WHERE id = _binding_id;
      RETURN 'duplicate';
    END IF;
    INSERT INTO private.passive_evidence_incidents(
      user_id,binding_id,event_id,collector_sequence,reason,incoming_payload_sha256,existing_payload_sha256
    ) VALUES (_subject_id,_binding_id,_event_id,_sequence,'event_conflict',_payload_sha,_existing.payload_sha256);
    RETURN 'conflict';
  END IF;
  SELECT * INTO _existing FROM private.passive_evidence_events
  WHERE binding_id = _binding_id AND collector_sequence = _sequence;
  IF FOUND THEN
    INSERT INTO private.passive_evidence_incidents(
      user_id,binding_id,event_id,collector_sequence,reason,incoming_payload_sha256,existing_payload_sha256
    ) VALUES (_subject_id,_binding_id,_event_id,_sequence,'sequence_conflict',_payload_sha,_existing.payload_sha256);
    RETURN 'conflict';
  END IF;

  SELECT epoch.id, epoch.contract_version_id, epoch.started_at, contract.interval_minutes
  INTO _epoch_id, _contract_id, _started_at, _interval_minutes
  FROM public.passive_monitoring_epochs AS epoch
  JOIN public.passive_checkin_contract_versions AS contract ON contract.id = epoch.contract_version_id
  WHERE epoch.user_id = _subject_id AND epoch.ended_at IS NULL;
  IF _epoch_id IS NULL OR _observed_at < _started_at THEN RETURN 'outside_epoch'; END IF;

  SELECT live.id, live.window_start INTO _window_id, _window_start
  FROM public.passive_checkin_windows AS live
  WHERE live.epoch_id = _epoch_id AND live.outcome = 'pending'
  ORDER BY live.ordinal LIMIT 1;

  IF _window_id IS NULL OR _observed_at < _window_start THEN
    -- History: the window this report actually falls inside.
    SELECT past.id INTO _window_id
    FROM public.passive_checkin_windows AS past
    WHERE past.epoch_id = _epoch_id
      AND past.window_start <= _observed_at AND past.window_end > _observed_at
    ORDER BY past.ordinal DESC LIMIT 1;
  END IF;

  IF _window_id IS NULL THEN
    -- An epoch whose first window the evaluator has not opened yet.
    _window_end := private.passive_awake_deadline(_subject_id,_started_at,_interval_minutes);
    INSERT INTO public.passive_checkin_windows(
      user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
    ) VALUES (
      _subject_id,_epoch_id,_contract_id,0,_started_at,_window_end,
      _window_end + private.passive_arrival_allowance(_subject_id)
    ) ON CONFLICT (epoch_id,ordinal) DO NOTHING;
    SELECT first_window.id INTO _window_id FROM public.passive_checkin_windows AS first_window
    WHERE first_window.epoch_id = _epoch_id AND first_window.ordinal = 0;
    IF _window_id IS NULL THEN RETURN 'outside_epoch'; END IF;
  END IF;

  PERFORM 1 FROM public.passive_checkin_windows WHERE id = _window_id FOR UPDATE;

  INSERT INTO private.passive_evidence_events(
    user_id,binding_id,epoch_id,window_id,event_id,collector_sequence,collector_time_epoch,
    observed_at,received_at,evidence_class,qualification_policy_version,collector_contract,
    client_version,correlation_id,qualification_facts,query_started_at,query_ended_at,
    query_succeeded,payload_sha256
  ) VALUES (
    _subject_id,_binding_id,_epoch_id,_window_id,_event_id,_sequence,_binding.time_epoch,
    _observed_at,_now,_evidence_class,_qualification_policy_version,_binding.collector_contract,
    _binding.client_version,_correlation_id,coalesce(_qualification_facts,'{}'::jsonb),
    _query_started_at,_query_ended_at,_query_succeeded,_payload_sha
  ) RETURNING id INTO _event_row_id;

  -- Late positive only
  UPDATE public.passive_checkin_windows
  SET outcome = 'checked_in', causal_evidence_id = _event_row_id, finalized_at = _now
  WHERE id = _window_id AND outcome = 'missed';

  UPDATE private.passive_collector_bindings
  SET sequence_cursor = greatest(sequence_cursor,_sequence), last_contact_at = _now,
      last_evidence_at = greatest(coalesce(last_evidence_at,_observed_at),_observed_at)
  WHERE id = _binding_id;

  -- Bridge passive evidence to behavior_pings so Group Board / Usual Behavior reflects this activity:
  BEGIN
    PERFORM private.insert_behavior_ping(
      _subject_id,
      _event_id,
      _observed_at,
      CASE _binding.surface_type
        WHEN 'pwa_browser' THEN 'installed_pwa'
        WHEN 'shortcut' THEN 'shortcut'
        WHEN 'tauri' THEN 'tauri'
        ELSE 'app'
      END,
      CASE _evidence_class
        WHEN 'personal_device_motion' THEN 'steps'
        WHEN 'direct_device_use' THEN 'interaction'
        ELSE 'app'
      END
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN 'inserted';
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  RETURN 'invalid';
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Activity detail privacy levels (simple vs guardians_only vs all)
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS activity_detail_level text NOT NULL DEFAULT 'simple'
  CHECK (activity_detail_level IN ('simple', 'guardians_only', 'all'));

CREATE OR REPLACE FUNCTION public.set_activity_detail_level(_level text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF _level NOT IN ('simple', 'guardians_only', 'all') THEN
    RAISE EXCEPTION 'invalid detail level: must be simple, guardians_only, or all';
  END IF;
  INSERT INTO public.user_settings (user_id, activity_detail_level, updated_at)
  VALUES (_uid, _level, now())
  ON CONFLICT (user_id) DO UPDATE
    SET activity_detail_level = excluded.activity_detail_level, updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.set_activity_detail_level(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_activity_detail_level(text) TO authenticated;

-- Privacy-preserving group activity view
CREATE OR REPLACE FUNCTION public.get_group_activity_view("_group" uuid, "_view" text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''), 'group');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _my_detail_level text;
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

  SELECT coalesce(us.share_activity, true), coalesce(us.activity_detail_level, 'simple')
  INTO _i_share, _my_detail_level
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);
  _my_detail_level := coalesce(_my_detail_level, 'simple');

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
          WHEN m.user_id = _uid THEN floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
          WHEN coalesce(us.activity_detail_level, 'simple') = 'all' THEN floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
          WHEN coalesce(us.activity_detail_level, 'simple') = 'guardians_only' AND EXISTS (
            SELECT 1 FROM public.guardianships g
            WHERE g.ward_id = m.user_id AND g.guardian_id = _uid AND g.status = 'active'
          ) THEN floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
          ELSE null
        END,
      'last_behavior_at',
        CASE
          WHEN bp.last_at IS NULL THEN null
          WHEN m.user_id = _uid THEN bp.last_at
          WHEN coalesce(us.activity_detail_level, 'simple') = 'all' THEN bp.last_at
          WHEN coalesce(us.activity_detail_level, 'simple') = 'guardians_only' AND EXISTS (
            SELECT 1 FROM public.guardianships g
            WHERE g.ward_id = m.user_id AND g.guardian_id = _uid AND g.status = 'active'
          ) THEN bp.last_at
          ELSE null
        END,
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
    'my_activity_detail_level', _my_detail_level,
    'members', _members
  );
END;
$$;
