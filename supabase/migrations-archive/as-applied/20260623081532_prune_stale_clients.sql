create extension if not exists pg_cron;

create or replace function public.prune_stale_clients()
returns void language sql security definer set search_path to '' as $$
  delete from public.clients where last_seen_at < now() - interval '30 days';
$$;

do $do$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = 'prune-stale-clients';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule('prune-stale-clients', '17 3 * * *', $$ select public.prune_stale_clients(); $$);
end $do$;