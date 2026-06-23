-- 客户端遥测保留期:每日清理 30 天未上报的设备行,让"目前在用设备"列表自愈,
-- 而不是只在读取时折叠隐藏。与前端 30 天在用判定一致。
-- 遥测本身只含 user_id/平台/版本/时间戳,非敏感;删除的也只是早已不再上报的旧行。
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
