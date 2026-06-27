-- 把服务端真实沉默阈值 + 最后行为时间暴露给前端,
-- 让 Routine 的 "Alert Threshold" 卡显示真正会触发告警的值
-- (private.silence_threshold = user_activity_profiles.hourly_thresholds[hour],而非前端本地引擎的猜测)。
create or replace function public.my_routine_status()
returns jsonb language plpgsql security definer set search_path to '' stable as $$
declare
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  _threshold := private.silence_threshold(_uid);
  select max(at) into _last_at from public.behavior_pings where user_id = _uid;
  return jsonb_build_object(
    'threshold_seconds', extract(epoch from _threshold)::bigint,
    'last_behavior_at', _last_at
  );
end;
$$;
revoke execute on function public.my_routine_status() from public, anon;
grant execute on function public.my_routine_status() to authenticated;
