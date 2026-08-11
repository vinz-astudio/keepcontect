-- Fix: gm_list_clients now uses behavior_pings.max(at) for status classification,
-- consistent with process_escalations. Also exposes last_behavior_at separately
-- so the GM console can display the true last human activity time.
create or replace function public.gm_list_clients()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid();
begin
  if not private.is_admin(_uid) then raise exception 'forbidden'; end if;
  return coalesce((
    select jsonb_agg(obj order by nm asc, ls desc nulls last)
    from (
      select jsonb_build_object(
        'user_id', p.id,
        'name', coalesce(nullif(p.display_name,''), left(p.id::text,8)),
        'platform', c.platform,
        'app_version', c.app_version,
        'first_seen_at', c.first_seen_at,
        'last_seen_at', c.last_seen_at,
        'last_heartbeat_at', ds.last_heartbeat_at,
        'last_behavior_at', bp.last_at,
        'alerted', exists (
          select 1 from public.alerts a
          where a.user_id = p.id and a.status = 'open'
            and a.stage in ('group','community','terminal')
        ),
        -- Status now uses behavior_pings.max(at), matching process_escalations logic.
        -- This prevents GM console from showing "active" based on app heartbeat alone.
        'status',
          case
            when exists (
              select 1 from public.alerts a
              where a.user_id = p.id and a.status = 'open'
                and a.stage in ('group','community','terminal')
            ) then 'alert'
            when bp.last_at is null then 'never'
            when bp.last_at > now() - interval '6 hours' then 'active'
            when bp.last_at > now() - interval '24 hours' then 'quiet'
            else 'silent'
          end
      ) as obj,
      coalesce(nullif(p.display_name,''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      from public.profiles p
      left join public.clients c on c.user_id = p.id
      left join public.device_state ds on ds.user_id = p.id
      left join lateral (
        select max(at) as last_at
        from public.behavior_pings
        where user_id = p.id
      ) bp on true
    ) s
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.gm_list_clients() to authenticated;
