alter table public.profiles
  add column guardian_code text not null unique default encode(gen_random_bytes(6), 'hex');

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