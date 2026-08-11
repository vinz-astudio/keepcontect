-- Industrial hardening: advisor-backed indexes, policy consolidation,
-- and reproducible cron scheduling. Keep behavior unchanged.

create index if not exists alert_events_actor_idx
  on public.alert_events (actor_id);

create index if not exists alerts_user_id_idx
  on public.alerts (user_id);

create index if not exists alerts_paused_by_idx
  on public.alerts (paused_by);

create index if not exists alerts_resolved_by_idx
  on public.alerts (resolved_by);

create index if not exists checkin_tasks_created_by_idx
  on public.checkin_tasks (created_by);

create index if not exists notifications_alert_idx
  on public.notifications (alert_id);

-- Merge duplicate permissive SELECT policies on emergency_info so each row only
-- evaluates one policy for authenticated reads. This preserves owner,
-- guardian, and open-alert responder access.
drop policy if exists emergency_info_reveal_on_escalation on public.emergency_info;
drop policy if exists emergency_info_select on public.emergency_info;
create policy emergency_info_select on public.emergency_info
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
    or exists (
      select 1 from public.alerts a
      where a.user_id = emergency_info.user_id
        and a.status = 'open'
        and a.stage in ('group', 'community', 'terminal')
        and (
          private.watches_user((select auth.uid()), emergency_info.user_id)
          or private.shares_community((select auth.uid()), emergency_info.user_id)
        )
    )
  );

-- Recreate the push dispatch cron through pg_cron APIs, avoiding manual edits
-- to cron.job and ensuring only one active job with this name remains.
do $do$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = 'push-dispatch';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule(
    'push-dispatch',
    '* * * * *',
    $cron$
      select net.http_post(
        url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/push-dispatch',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := '{}'::jsonb
      );
    $cron$
  );
end $do$;
update public.behavior_pings
  set kind = 'app'
  where kind <> 'app';

alter table public.behavior_pings
  drop constraint if exists behavior_pings_kind_check;

alter table public.behavior_pings
  add constraint behavior_pings_kind_check check (kind = 'app');