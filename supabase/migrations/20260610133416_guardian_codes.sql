-- 守护人邀请码：每个用户一个个人守护码；分享码=同意被守护，对方输入后成为守护人。
-- 被守护者可在守护关系列表里随时撤销（知情可见可撤销）。

alter table public.profiles
  add column guardian_code text not null unique default encode(gen_random_bytes(6), 'hex');

-- 凭对方的守护码成为其守护人（SECURITY DEFINER：避免按码查全表，防枚举）
create or replace function public.become_guardian_by_code(_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
  _ward uuid;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;
  select id into _ward from public.profiles where guardian_code = _code;
  if not found then
    raise exception 'invalid guardian code';
  end if;
  if _ward = _uid then
    raise exception 'cannot guard yourself';
  end if;
  insert into public.guardianships (guardian_id, ward_id, status)
  values (_uid, _ward, 'active')
  on conflict (guardian_id, ward_id) do update set status = 'active';
  return _ward;
end;
$$;

revoke execute on function public.become_guardian_by_code(text) from public, anon;
grant execute on function public.become_guardian_by_code(text) to authenticated;
