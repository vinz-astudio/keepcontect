-- Knock at the people who are about to be judged, and say which silence it was.
--
-- Two problems, one cause: the server had no idea which subjects were close to a
-- deadline.
--
-- `passive-poll` knocked EVERY iOS device on every run. That is a silent push per
-- device per cycle whether or not the subject reported five minutes ago, and it
-- arrives at no particular moment relative to the thing it is supposed to
-- prevent. What the check-in interval is actually supposed to mean is stated in
-- `routineModel.ts`: it is a backstop, and if nothing has arrived by the time it
-- runs out, the server asks the device to look through its own history. That only
-- works if the ask lands BEFORE the deadline, at the subjects who are near one.
--
-- And when a deadline does elapse, the people who get told deserve to know which
-- of three different things happened. "No sign of life" and "the app is not
-- allowed to check" are not the same message and do not call for the same
-- response — the second one is not evidence about the person at all.

-- ---------------------------------------------------------------------------
-- Knock bookkeeping
-- ---------------------------------------------------------------------------

CREATE TABLE private.passive_knock_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  window_id uuid NOT NULL REFERENCES public.passive_checkin_windows(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- How many devices the knock actually reached. Zero is the interesting value:
  -- it means the subject has no reachable surface, which is a health incident
  -- rather than a fact about them.
  surfaces integer NOT NULL DEFAULT 0 CHECK (surfaces >= 0)
);
CREATE INDEX passive_knock_attempts_window_recent
  ON private.passive_knock_attempts(window_id, requested_at DESC);
ALTER TABLE private.passive_knock_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.passive_knock_attempts FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE private.passive_knock_attempts IS
  'One row per time the server asked a subject''s devices to look through their history.';


-- The subjects whose live deadline is close enough to be worth a knock.
--
-- The lead is an hour, not the thirty minutes that first looked sufficient. A
-- silent iOS push is sent at APNs priority 5, which the system is free to hold
-- and coalesce; delivery can take the better part of an hour on a device that is
-- idle and off charge. Thirty minutes of slack would routinely have the answer
-- arrive after the deadline it existed to prevent. An hour costs at most one
-- extra knock per window and buys the delivery latency the platform actually has.
--
-- `DISTINCT ON (ordinal)` picks the same window the evaluator calls live. A legacy
-- epoch can still be carrying several pending windows, and knocking a subject once
-- per stale row would spend pushes on windows nobody is judging.
CREATE FUNCTION public.passive_knock_targets()
RETURNS TABLE(user_id uuid, window_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  SELECT due.user_id, due.window_id FROM (
    SELECT DISTINCT ON (account.user_id)
      account.user_id, live.id AS window_id, live.arrival_deadline
    FROM public.passive_checkin_accounts AS account
    JOIN public.passive_checkin_windows AS live
      ON live.epoch_id = account.active_epoch_id AND live.outcome = 'pending'
    WHERE account.engine_mode IN ('shadow','passive_checkin')
      AND NOT account.kill_switch_active
    ORDER BY account.user_id, live.ordinal
  ) due
  WHERE due.arrival_deadline <= clock_timestamp() + interval '60 minutes'
    AND NOT EXISTS (
      SELECT 1 FROM private.passive_knock_attempts AS prior
      WHERE prior.window_id = due.window_id
        AND prior.requested_at > clock_timestamp() - interval '30 minutes'
    )
$$;

COMMENT ON FUNCTION public.passive_knock_targets() IS
  'Subjects within an hour of an elapsing deadline and not knocked in the last half hour.';

CREATE FUNCTION public.record_passive_knock(
  _user_id uuid, _window_id uuid, _surfaces integer
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  INSERT INTO private.passive_knock_attempts(user_id, window_id, surfaces)
  VALUES (_user_id, _window_id, greatest(coalesce(_surfaces,0),0));
END;
$$;

CREATE FUNCTION private.prune_passive_knock_attempts()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _removed bigint;
BEGIN
  DELETE FROM private.passive_knock_attempts
  WHERE requested_at < clock_timestamp() - interval '35 days';
  GET DIAGNOSTICS _removed = ROW_COUNT;
  RETURN _removed;
END;
$$;

REVOKE ALL ON FUNCTION public.passive_knock_targets() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.passive_knock_targets() TO service_role;
REVOKE ALL ON FUNCTION public.record_passive_knock(uuid,uuid,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_passive_knock(uuid,uuid,integer) TO service_role;
REVOKE ALL ON FUNCTION private.prune_passive_knock_attempts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.prune_passive_knock_attempts() TO service_role;


-- ---------------------------------------------------------------------------
-- Naming the silence
-- ---------------------------------------------------------------------------

-- STILL A DISPATCHER. Alerts that did not come from passive check-in are handed
-- to `notify_stage_before_passive_checkin` untouched; only the passive branch
-- changes. Rewriting this function from the baseline deletes that routing.
CREATE OR REPLACE FUNCTION private.notify_stage(_alert_id uuid,_user uuid,_stage text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _name text; _params jsonb; _kind text; _body text;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=_alert_id) THEN
    PERFORM private.notify_stage_before_passive_checkin(_alert_id,_user,_stage);
    RETURN;
  END IF;

  -- 本人这一层。原来直接 return,理由是本机 overlay 会提示 —— 但 overlay 只在 App
  -- 醒着时出现,而那正是不需要问他的时候。30 天里 43 次 self 阶段只有 16 次给本人
  -- 留下任何通知记录。整条升级链的第一步「先问本人」必须真的送达。
  IF _stage='self' THEN
    SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    VALUES (_user,_alert_id,'self',
      'KC 有一阵子没有确认到您的活动了。您还好吗?点开报个平安,就不会通知任何人。',
      jsonb_build_object('name',_name,'cause','passive_checkin_lost_contact'));
    RETURN;
  END IF;

  SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;

  -- The most recent window that caused this alert decides the wording. Older
  -- windows in the same chain may have failed for a different reason; what the
  -- recipient needs is the current state of affairs.
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
        'KC 始终无法确认 '||_name||' 的情况，请上门探视或协助联系。'
      WHEN 'device_unreachable' THEN
        'KC 与 '||_name||' 的设备始终失去联系，请上门探视或协助联系。'
      ELSE
        'KC 与 '||_name||' 持续失去联系，请上门探视或协助联系。'
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

REVOKE ALL ON FUNCTION private.notify_stage(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.notify_stage(uuid,uuid,text) TO service_role;
