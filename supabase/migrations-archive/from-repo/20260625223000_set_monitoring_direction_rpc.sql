-- Make "watched" / "watching others" toggles deterministic.
-- Direct PostgREST updates can look successful while touching 0 rows when
-- RLS or membership state blocks the update. This RPC updates the caller's
-- own active membership row and raises when nothing was changed.

create or replace function public.set_monitoring_direction(
  _group uuid,
  _monitored boolean default null,
  _watching boolean default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _monitored is null and _watching is null then
    raise exception 'nothing to update';
  end if;

  update public.group_members gm
     set monitored = coalesce(_monitored, gm.monitored),
         watching = coalesce(_watching, gm.watching)
   where gm.group_id = _group
     and gm.user_id = _uid
     and gm.status = 'active';

  if not found then raise exception 'group membership not found'; end if;
end;
$$;

revoke execute on function public.set_monitoring_direction(uuid, boolean, boolean)
  from public, anon;
grant execute on function public.set_monitoring_direction(uuid, boolean, boolean)
  to authenticated;
