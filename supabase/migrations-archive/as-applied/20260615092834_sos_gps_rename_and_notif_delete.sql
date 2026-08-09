-- 通知：允许本人删除自己的通知（清除单个/全部）
do $$ begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'notifications' and policyname = 'notifications_delete'
  ) then
    create policy notifications_delete on public.notifications
      for delete using ((select auth.uid()) = recipient_id);
  end if;
end $$;

-- Group / Community 重命名（仅创建者）
create or replace function public.rename_group(_group uuid, _name text)
returns void language plpgsql security definer set search_path = '' as $$
declare _clean text := nullif(btrim(_name), '');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if _clean is null then raise exception 'name required'; end if;
  update public.groups set name = left(_clean, 40)
    where id = _group and created_by = auth.uid();
  if not found then raise exception 'not group owner'; end if;
end; $$;
revoke execute on function public.rename_group(uuid, text) from public, anon;
grant execute on function public.rename_group(uuid, text) to authenticated;

create or replace function public.rename_community(_community uuid, _name text)
returns void language plpgsql security definer set search_path = '' as $$
declare _clean text := nullif(btrim(_name), '');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if _clean is null then raise exception 'name required'; end if;
  update public.communities set name = left(_clean, 40)
    where id = _community and created_by = auth.uid();
  if not found then raise exception 'not community owner'; end if;
end; $$;
revoke execute on function public.rename_community(uuid, text) from public, anon;
grant execute on function public.rename_community(uuid, text) to authenticated;

-- SOS 带实时 GPS：alerts 加坐标列，raise_sos 接收并写入
alter table public.alerts add column if not exists sos_lat double precision;
alter table public.alerts add column if not exists sos_lng double precision;

drop function if exists public.raise_sos();
create or replace function public.raise_sos(
  _lat double precision default null,
  _lng double precision default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select id into _aid from public.alerts where user_id = _uid and status = 'open';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, sos_lat, sos_lng)
    values (_uid, 'sos', 'group', now(), now() + interval '1 hour', _lat, _lng)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'raised');
  else
    update public.alerts set cause = 'sos', stage = 'group', stage_entered_at = now(),
      next_deadline = now() + interval '1 hour', paused_until = null,
      sos_lat = coalesce(_lat, sos_lat), sos_lng = coalesce(_lng, sos_lng),
      updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, 'escalated', 'sos');
  end if;
  perform private.notify_stage(_aid, _uid, 'group');
  return _aid;
end; $$;
revoke execute on function public.raise_sos(double precision, double precision) from public, anon;
grant execute on function public.raise_sos(double precision, double precision) to authenticated;