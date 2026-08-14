-- ADR-0042 package 8a: passive collector health display (split out of
-- 20260814201500_passive_checkin_activation.sql on 2026-08-14 per audit BLK-3).
-- Stage 1 ships read-only health display while the live activation RPC stays
-- deferred in docs/release/deferred/. my_passive_collector_health() itself is
-- defined by 20260814203000 (CREATE OR REPLACE); this file supplies its private
-- summary ingredient and the public ACLs. No live authority is granted here.
CREATE FUNCTION private.passive_collector_health_summary(_user_id uuid,_now timestamptz)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  WITH surfaces AS (
    SELECT b.id,b.collector_instance_id,b.surface_type,b.permission_state,b.capability_state,
      b.last_contact_at,r.expected_contact_cadence,
      CASE
        WHEN b.permission_state IN('denied','revoked') THEN 'permission_'||b.permission_state
        WHEN b.capability_state<>'ok' THEN 'capability_'||b.capability_state
        WHEN r.expected_contact_cadence IS NOT NULL
          AND (b.last_contact_at IS NULL OR _now-b.last_contact_at>r.expected_contact_cadence*2) THEN 'silent'
        ELSE NULL
      END reason
    FROM private.passive_collector_bindings b
    JOIN private.passive_surface_registry r USING(surface_type)
    WHERE b.user_id=_user_id AND b.revoked_at IS NULL
  ), items AS (
    SELECT *,CASE WHEN reason IS NULL THEN 'ready' ELSE 'limited' END state,
      CASE reason
        WHEN 'permission_denied' THEN 'Open system settings and grant the required permission.'
        WHEN 'permission_revoked' THEN 'Bind this device again after restoring permission.'
        WHEN 'capability_unsupported' THEN 'Use another supported device or collector.'
        WHEN 'capability_degraded' THEN 'Review this device setup and background restrictions.'
        WHEN 'silent' THEN 'Open Keep Contact on this device and repair background operation.'
        ELSE NULL
      END repair_action
    FROM surfaces
  )
  SELECT jsonb_build_object(
    'state',CASE WHEN count(*)=0 THEN 'off'
      WHEN bool_or(reason IS NOT NULL) THEN 'limited' ELSE 'ready' END,
    'devices',coalesce(jsonb_agg(jsonb_build_object(
      'binding_id',id,'device',collector_instance_id,'surface_type',surface_type,
      'state',state,'reason',reason,'repair_action',repair_action,
      'last_contact_at',last_contact_at
    ) ORDER BY collector_instance_id),'[]'::jsonb),
    'miss_counting_continues',true,
    'evaluated_at',_now
  ) FROM items
$$;


REVOKE ALL ON FUNCTION private.passive_collector_health_summary(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.my_passive_collector_health() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_passive_collector_health() TO authenticated;

