begin;
select plan(15);

select is(private.canonical_routine_mode('regular_9to5'), 'regular_9to5');
select is(private.canonical_routine_mode('semester_break'), 'semester_break');
select is(private.canonical_routine_mode('student'), 'semester_break');
select is(private.canonical_routine_mode('shift_irregular'), 'shift_irregular');
select is(private.canonical_routine_mode('shift_worker'), 'shift_irregular');
select is(private.canonical_routine_mode('flexible'), 'shift_irregular');
select is(private.canonical_routine_mode('bad-value'), 'regular_9to5');
select has_check('public', 'profiles', 'profiles_routine_pattern_canonical');
select function_privs_are(
  'private', 'canonical_routine_mode', array['text'],
  'authenticated', array[]::text[]
);

select ok(
  (select c.relrowsecurity
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'routine_mode_cohort_invalidations'),
  'routine-mode invalidations keep RLS enabled'
);

select results_eq(
  $$
  with roles(role_name) as (
    values
      ('PUBLIC'::text),
      ('anon'::text),
      ('authenticated'::text),
      ('service_role'::text)
  ),
  actions(privilege_name) as (
    values
      ('DELETE'::text),
      ('INSERT'::text),
      ('MAINTAIN'::text),
      ('REFERENCES'::text),
      ('SELECT'::text),
      ('TRIGGER'::text),
      ('TRUNCATE'::text),
      ('UPDATE'::text)
  )
  select
    role_name,
    string_agg(privilege_name, ',' order by privilege_name)
      filter (where case
        when role_name = 'PUBLIC' then exists (
          select 1
          from pg_class c
          cross join lateral aclexplode(
            coalesce(c.relacl, acldefault('r', c.relowner))
          ) acl
          where c.oid = 'public.routine_mode_cohort_invalidations'::regclass
            and acl.grantee = 0
            and acl.privilege_type = privilege_name
        )
        else has_table_privilege(
          role_name,
          'public.routine_mode_cohort_invalidations',
          privilege_name
        )
      end) as privileges
  from roles
  cross join actions
  group by role_name
  order by case role_name
    when 'PUBLIC' then 0
    when 'anon' then 1
    when 'authenticated' then 2
    when 'service_role' then 3
  end
  $$,
  $$
  values
    ('PUBLIC'::text, null::text),
    ('anon'::text, null::text),
    ('authenticated'::text, null::text),
    ('service_role'::text, null::text)
  $$,
  'routine-mode invalidations have no effective table privileges for Data API roles'
);

select ok(
  not has_function_privilege('public', 'private.canonical_routine_mode(text)', 'execute')
  and not has_function_privilege('anon', 'private.canonical_routine_mode(text)', 'execute')
  and not has_function_privilege('service_role', 'private.canonical_routine_mode(text)', 'execute'),
  'canonical normalizer is not directly executable by Data API roles'
);

select ok(
  not has_function_privilege('public', 'private.invalidate_routine_mode_cohort()', 'execute')
  and not has_function_privilege('anon', 'private.invalidate_routine_mode_cohort()', 'execute')
  and not has_function_privilege('authenticated', 'private.invalidate_routine_mode_cohort()', 'execute')
  and not has_function_privilege('service_role', 'private.invalidate_routine_mode_cohort()', 'execute'),
  'invalidation trigger function is not directly executable by Data API roles'
);

insert into auth.users (id, email, aud, role)
values (
  'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380c33',
  'routine-mode@example.com',
  'authenticated',
  'authenticated'
);

update public.profiles
set routine_pattern = 'semester_break'
where id = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380c33';

select results_eq(
  $$
  select routine_mode
  from public.routine_mode_cohort_invalidations
  order by routine_mode
  $$,
  $$
  values ('regular_9to5'::text), ('semester_break'::text)
  $$,
  'routine changes invalidate both previous and replacement cohort modes'
);

delete from public.routine_mode_cohort_invalidations;

update public.profiles
set consent_data_sharing = true
where id = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380c33';

select results_eq(
  $$
  select routine_mode, invalidated_at is not null
  from public.routine_mode_cohort_invalidations
  $$,
  $$
  values ('semester_break'::text, true)
  $$,
  'consent changes invalidate the current routine-mode cohort'
);

select * from finish();
rollback;
