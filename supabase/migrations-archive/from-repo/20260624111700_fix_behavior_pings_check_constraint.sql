-- Alter behavior_pings constraint to allow all valid kinds of user interactions.
alter table public.behavior_pings
  drop constraint if exists behavior_pings_kind_check;

alter table public.behavior_pings
  add constraint behavior_pings_kind_check check (
    kind in ('app', 'interaction', 'steps', 'unlock', 'manual_checkin')
  );
