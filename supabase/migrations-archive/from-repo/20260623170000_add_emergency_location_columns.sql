-- Add location coordinates to emergency_info for SOS tracking.
alter table public.emergency_info
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_accuracy double precision,
  add column if not exists location_updated_at timestamp with time zone;
