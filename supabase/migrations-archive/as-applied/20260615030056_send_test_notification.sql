-- 给自己发一条测试通知（用于在真机上验证推送是否出声/醒目）
create or replace function public.send_test_notification()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.notifications (recipient_id, kind, body, params)
  values (auth.uid(), 'test', '这是一条测试通知，用来确认推送是否出声、醒目。', '{}'::jsonb);
end; $$;
revoke execute on function public.send_test_notification() from public, anon;
grant execute on function public.send_test_notification() to authenticated;