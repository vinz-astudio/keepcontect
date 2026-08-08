-- FCM device tokens for the native Android fast path (ADR-0004 Phase 2).
-- The token is an opaque routing handle; notification CONTENT never goes
-- through FCM (push-dispatch sends a data-only wake tickle, the device then
-- pulls content from notify-feed). Auth is untouched: rows key off auth.uid().
create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);

alter table public.push_tokens enable row level security;
-- No RLS policies on purpose: only the service role (push-dispatch) and the
-- SECURITY DEFINER RPC below ever touch this table.

create or replace function public.register_fcm_token(_token text, _platform text default 'android')
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if _token is null or length(_token) < 10 then
    return;
  end if;
  insert into public.push_tokens (token, user_id, platform, updated_at)
  values (_token, auth.uid(), coalesce(_platform, 'android'), now())
  on conflict (token) do update
    set user_id = excluded.user_id, updated_at = now();
end;
$$;

revoke execute on function public.register_fcm_token(text, text) from anon, public;
grant execute on function public.register_fcm_token(text, text) to authenticated;
