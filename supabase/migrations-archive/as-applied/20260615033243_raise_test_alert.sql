-- 造一个"测试用"的本人 open 告警 + 发本人推送，用来验证"点通知→解锁界面"。
-- next_deadline=null ⇒ process_escalations 永不升级它 ⇒ 绝不打扰 group/community。
create or replace function public.raise_test_alert()
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  -- 已有 open 告警就复用（避免重复造），否则建一个不升级的测试告警
  select id into _aid from public.alerts where user_id = _uid and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, 'silence', 'self', now(), null)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, 'raised');
  end if;
  insert into public.notifications (recipient_id, kind, body, params, alert_id)
  values (_uid, 'self', '（测试）检测到异常沉默，点开 App 完成解锁报平安。', '{}'::jsonb, _aid);
end; $$;
revoke execute on function public.raise_test_alert() from public, anon;
grant execute on function public.raise_test_alert() to authenticated;