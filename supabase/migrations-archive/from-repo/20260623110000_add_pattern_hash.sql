-- Add pattern_hash column to user_settings table to sync lock gesture patterns across devices.
alter table public.user_settings add column if not exists pattern_hash text;
