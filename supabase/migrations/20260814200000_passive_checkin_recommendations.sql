-- ADR-0042 package 7: advisory-only personal reference and platform-floor mapping.

CREATE TABLE public.passive_checkin_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  revision_number bigint NOT NULL CHECK(revision_number>0),
  estimator_version text NOT NULL DEFAULT 'passive-gap-b1-v1',
  config_version text NOT NULL DEFAULT 'passive-recommendation-v1',
  eligible_episode_ids uuid[] NOT NULL DEFAULT '{}',
  eligible_episode_sha256 text NOT NULL CHECK(eligible_episode_sha256~'^[a-f0-9]{64}$'),
  eligible_episode_count integer NOT NULL CHECK(eligible_episode_count>=0),
  evidence_days integer NOT NULL CHECK(evidence_days>=0),
  excluded_counts jsonb NOT NULL DEFAULT '{}',
  source_confidence text NOT NULL CHECK(source_confidence IN('insufficient','low','medium','high')),
  reference_minutes integer NOT NULL CHECK(reference_minutes>0),
  proposed_interval_minutes integer NOT NULL CHECK(proposed_interval_minutes BETWEEN 20 AND 360),
  proposed_consecutive_misses integer NOT NULL CHECK(proposed_consecutive_misses BETWEEN 1 AND 1000000),
  proposed_horizon_minutes bigint NOT NULL CHECK(proposed_horizon_minutes>0),
  platform_d_floor_minutes integer NOT NULL CHECK(platform_d_floor_minutes>0),
  platform_h_floor_minutes integer NOT NULL CHECK(platform_h_floor_minutes>0),
  platform_floor_basis text[] NOT NULL,
  expected_interruptions_per_day numeric NOT NULL CHECK(expected_interruptions_per_day>=0),
  generated_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(user_id,revision_number)
);
ALTER TABLE public.passive_checkin_recommendations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.passive_checkin_recommendations FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.reject_passive_recommendation_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN RAISE EXCEPTION 'passive recommendations are immutable' USING ERRCODE='55000'; END $$;
CREATE TRIGGER passive_checkin_recommendations_immutable
BEFORE UPDATE ON public.passive_checkin_recommendations
FOR EACH ROW EXECUTE FUNCTION private.reject_passive_recommendation_mutation();

CREATE FUNCTION private.rebuild_passive_checkin_recommendation(_user_id uuid,_now timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' SET TimeZone TO 'UTC' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _lookback_start timestamptz:=date_trunc('day',_now)-interval '30 days';
  _lookback_end timestamptz:=date_trunc('day',_now);
  _episode_ids uuid[]:='{}'; _episode_hash text; _episode_count integer:=0; _days integer:=0;
  _excluded jsonb; _confidence text; _rank integer; _candidate integer; _reference integer;
  _previous integer; _candidate_id uuid; _candidate_date date;
  _d_floor integer; _h_floor integer; _d integer; _n integer; _h bigint;
  _basis text[]; _revision bigint; _id uuid;
BEGIN
  IF _now IS NULL THEN RAISE EXCEPTION 'recommendation time is required'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_user_id FOR UPDATE;
  IF NOT FOUND OR _account.active_contract_version_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id;
  SELECT min(registry.d_floor_minutes),min(registry.h_floor_minutes),
    array_agg(DISTINCT binding.surface_type ORDER BY binding.surface_type)
  INTO _d_floor,_h_floor,_basis
  FROM private.passive_collector_bindings binding
  JOIN private.passive_surface_registry registry USING(surface_type)
  WHERE binding.user_id=_user_id AND binding.revoked_at IS NULL;
  IF _d_floor IS NULL OR _h_floor IS NULL THEN RETURN NULL; END IF;

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.passive_recommendation_episodes(
    episode_id uuid,started_at timestamptz,ended_at timestamptz,gap_minutes integer,
    local_date date,eligible boolean,exclusion_reason text
  ) ON COMMIT DROP;
  TRUNCATE pg_temp.passive_recommendation_episodes;
  INSERT INTO pg_temp.passive_recommendation_episodes
  WITH ordered AS (
    SELECT event.*,
      lag(event.id) OVER(ORDER BY event.observed_at,event.id) AS prior_id,
      lag(event.observed_at) OVER(ORDER BY event.observed_at,event.id) AS prior_at,
      lag(event.epoch_id) OVER(ORDER BY event.observed_at,event.id) AS prior_epoch,
      lag(binding.surface_type) OVER(ORDER BY event.observed_at,event.id) AS prior_surface,
      binding.surface_type
    FROM private.passive_evidence_events event
    JOIN private.passive_collector_bindings binding ON binding.id=event.binding_id
    WHERE event.user_id=_user_id AND event.observed_at>=_lookback_start-interval '2 days'
      AND event.observed_at<_lookback_end
  ), pairs AS (
    SELECT *,(
      substr(md5(prior_id::text||':'||id::text),1,8)||'-'||substr(md5(prior_id::text||':'||id::text),9,4)||'-4'||
      substr(md5(prior_id::text||':'||id::text),14,3)||'-8'||substr(md5(prior_id::text||':'||id::text),18,3)||'-'||
      substr(md5(prior_id::text||':'||id::text),21,12)
    )::uuid AS episode_id,
    ceil(extract(epoch FROM(observed_at-prior_at))/60)::integer AS gap_minutes
    FROM ordered WHERE prior_id IS NOT NULL AND observed_at>=_lookback_start
  ), classified AS (
    SELECT pairs.*,
      CASE
        WHEN observed_at<=prior_at OR epoch_id<>prior_epoch THEN 'contract_or_clock_boundary'
        WHEN surface_type='shortcut' OR prior_surface='shortcut' THEN 'shortcut'
        WHEN EXISTS(SELECT 1 FROM public.passive_checkin_windows w
          WHERE w.user_id=_user_id AND w.window_start<observed_at AND w.window_end>prior_at
            AND w.outcome IN('pending','superseded')) THEN 'nonterminal_or_superseded'
        WHEN EXISTS(SELECT 1 FROM private.passive_surface_health_intervals health
          WHERE health.user_id=_user_id AND health.started_at<observed_at
            AND coalesce(health.ended_at,'infinity'::timestamptz)>prior_at) THEN 'surface_health'
        WHEN EXISTS(SELECT 1 FROM public.alerts alert
          WHERE alert.user_id=_user_id AND alert.opened_at<observed_at
            AND coalesce(alert.resolved_at,'infinity'::timestamptz)>prior_at) THEN 'alert_lifecycle'
        WHEN private.passive_sleep_relaxed(_user_id,_contract.id,prior_at)
          OR private.passive_sleep_relaxed(_user_id,_contract.id,observed_at)
          OR private.passive_sleep_relaxed(_user_id,_contract.id,prior_at+(observed_at-prior_at)/2) THEN 'sleep_or_postwake'
        ELSE NULL
      END AS reason
    FROM pairs
  )
  SELECT episode_id,prior_at,observed_at,gap_minutes,
    (observed_at AT TIME ZONE coalesce(_contract.timezone,'UTC'))::date,
    reason IS NULL,reason FROM classified;

  SELECT coalesce(array_agg(episode_id ORDER BY ended_at,episode_id),'{}'),count(*)::integer,
    count(DISTINCT local_date)::integer
  INTO _episode_ids,_episode_count,_days
  FROM pg_temp.passive_recommendation_episodes WHERE eligible;
  SELECT coalesce(jsonb_object_agg(exclusion_reason,total),'{}'::jsonb) INTO _excluded
  FROM (SELECT exclusion_reason,count(*)::integer total FROM pg_temp.passive_recommendation_episodes
    WHERE NOT eligible GROUP BY exclusion_reason) reasons;
  _episode_hash:=encode(extensions.digest(array_to_string(_episode_ids,','),'sha256'),'hex');
  SELECT reference_minutes INTO _previous FROM public.passive_checkin_recommendations
  WHERE user_id=_user_id ORDER BY revision_number DESC LIMIT 1;

  IF _episode_count<3 OR _days<3 THEN
    _reference:=360; _confidence:='insufficient';
  ELSE
    _confidence:=CASE WHEN _episode_count>=30 AND _days>=21 THEN 'high'
      WHEN _episode_count>=10 AND _days>=7 THEN 'medium' ELSE 'low' END;
    _rank:=least(1+round(_days::numeric/30)::integer,_episode_count);
    SELECT episode_id,gap_minutes,local_date INTO _candidate_id,_candidate,_candidate_date
    FROM pg_temp.passive_recommendation_episodes WHERE eligible
    ORDER BY gap_minutes DESC,ended_at DESC OFFSET _rank-1 LIMIT 1;
    IF _previous IS NOT NULL AND _candidate>_previous*1.5 AND NOT EXISTS(
      SELECT 1 FROM pg_temp.passive_recommendation_episodes other
      WHERE other.eligible AND other.episode_id<>_candidate_id AND other.local_date<>_candidate_date
        AND greatest(other.gap_minutes,_candidate)::numeric/least(other.gap_minutes,_candidate)<=1.25
    ) THEN _candidate:=_previous; END IF;
    _reference:=greatest(5,ceil(_candidate::numeric/5)::integer*5);
  END IF;
  _d:=greatest(_contract.interval_minutes,_d_floor);
  _n:=greatest(1,ceil(_reference::numeric/_d)::integer);
  _h:=greatest(_d::bigint*_n::bigint,_h_floor::bigint);
  _n:=ceil(_h::numeric/_d)::integer;
  _h:=_d::bigint*_n::bigint;
  SELECT coalesce(max(revision_number),0)+1 INTO _revision
  FROM public.passive_checkin_recommendations WHERE user_id=_user_id;
  INSERT INTO public.passive_checkin_recommendations(
    user_id,revision_number,eligible_episode_ids,eligible_episode_sha256,
    eligible_episode_count,evidence_days,excluded_counts,source_confidence,
    reference_minutes,proposed_interval_minutes,proposed_consecutive_misses,
    proposed_horizon_minutes,platform_d_floor_minutes,platform_h_floor_minutes,
    platform_floor_basis,expected_interruptions_per_day,generated_at
  ) VALUES(_user_id,_revision,_episode_ids,_episode_hash,_episode_count,_days,_excluded,
    _confidence,_reference,_d,_n,_h,_d_floor,_h_floor,_basis,1440::numeric/_h,_now)
  RETURNING id INTO _id;
  RETURN _id;
END;
$$;

CREATE FUNCTION public.my_passive_checkin_recommendation()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _r public.passive_checkin_recommendations%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO _r FROM public.passive_checkin_recommendations WHERE user_id=_uid
  ORDER BY revision_number DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id',_r.id,'revision_number',_r.revision_number,'estimator_version',_r.estimator_version,
    'config_version',_r.config_version,'eligible_episode_count',_r.eligible_episode_count,
    'evidence_days',_r.evidence_days,'excluded_counts',_r.excluded_counts,
    'source_confidence',_r.source_confidence,'reference_minutes',_r.reference_minutes,
    'proposed_interval_minutes',_r.proposed_interval_minutes,
    'proposed_consecutive_misses',_r.proposed_consecutive_misses,
    'proposed_horizon_minutes',_r.proposed_horizon_minutes,
    'platform_d_floor_minutes',_r.platform_d_floor_minutes,
    'platform_h_floor_minutes',_r.platform_h_floor_minutes,
    'platform_floor_basis',_r.platform_floor_basis,
    'expected_interruptions_per_day',_r.expected_interruptions_per_day,
    'generated_at',_r.generated_at);
END;
$$;

REVOKE ALL ON FUNCTION private.reject_passive_recommendation_mutation() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.rebuild_passive_checkin_recommendation(uuid,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.rebuild_passive_checkin_recommendation(uuid,timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.my_passive_checkin_recommendation() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_passive_checkin_recommendation() TO authenticated;

COMMENT ON FUNCTION private.rebuild_passive_checkin_recommendation(uuid,timestamptz) IS
  'Advisory-only B=1 learner. Its function body contains no active-contract, window or alert mutation.';

-- Extend the existing unscheduled retention primitive without changing its authority.
CREATE OR REPLACE FUNCTION private.prune_passive_checkin_data()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _evidence bigint; _incidents bigint; _health bigint; _windows bigint;
  _recommendations bigint;
BEGIN
  DELETE FROM private.passive_evidence_events
  WHERE received_at < clock_timestamp() - interval '35 days';
  GET DIAGNOSTICS _evidence = ROW_COUNT;
  DELETE FROM private.passive_evidence_incidents
  WHERE received_at < clock_timestamp() - interval '35 days';
  GET DIAGNOSTICS _incidents = ROW_COUNT;
  DELETE FROM private.passive_surface_health_intervals
  WHERE ended_at IS NOT NULL AND ended_at < clock_timestamp() - interval '90 days';
  GET DIAGNOSTICS _health = ROW_COUNT;
  DELETE FROM public.passive_checkin_recommendations
  WHERE generated_at < clock_timestamp() - interval '90 days';
  GET DIAGNOSTICS _recommendations = ROW_COUNT;
  DELETE FROM public.passive_checkin_windows AS w
  WHERE w.window_end < clock_timestamp() - interval '90 days'
    AND NOT EXISTS (
      SELECT 1 FROM private.passive_alert_causal_windows causal
      WHERE causal.window_id = w.id
    );
  GET DIAGNOSTICS _windows = ROW_COUNT;
  RETURN jsonb_build_object(
    'evidence',_evidence,'incidents',_incidents,'health',_health,
    'recommendations',_recommendations,'windows',_windows
  );
END;
$$;
