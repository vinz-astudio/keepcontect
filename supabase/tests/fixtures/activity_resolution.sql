-- Isolated PostgreSQL fixture. No network, production credentials or real users.
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE FUNCTION extensions.gen_random_uuid() RETURNS uuid LANGUAGE sql AS $$ SELECT gen_random_uuid() $$;
CREATE TABLE public.profiles(id uuid PRIMARY KEY, display_name text);
CREATE TABLE public.user_settings(user_id uuid PRIMARY KEY, pattern_hash text);
CREATE TABLE public.guardianships(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), guardian_id uuid NOT NULL,
  ward_id uuid NOT NULL, status text NOT NULL DEFAULT 'active', UNIQUE(guardian_id,ward_id));
CREATE TABLE public.behavior_pings(id bigserial PRIMARY KEY, user_id uuid NOT NULL, event_id uuid,
  kind text, source text, at timestamptz, received_at timestamptz, ingest_version smallint DEFAULT 1,
  UNIQUE(user_id,event_id));
CREATE TABLE public.device_state(user_id uuid PRIMARY KEY, status text, last_heartbeat_at timestamptz, updated_at timestamptz);
CREATE TABLE public.alerts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL,
  cause text NOT NULL,stage text NOT NULL,status text NOT NULL DEFAULT 'open',opened_at timestamptz DEFAULT now(),
  stage_entered_at timestamptz DEFAULT now(),next_deadline timestamptz,paused_until timestamptz,paused_by uuid,
  resolved_at timestamptz,resolved_by uuid,updated_at timestamptz DEFAULT now(),requires_explicit_unlock boolean DEFAULT false);
CREATE TABLE public.alert_events(id uuid DEFAULT gen_random_uuid(),alert_id uuid,actor_id uuid,
  kind text,note text,at timestamptz DEFAULT now());
CREATE TABLE public.notifications(id uuid DEFAULT gen_random_uuid(),recipient_id uuid,alert_id uuid,
  kind text,body text,params jsonb DEFAULT '{}',created_at timestamptz DEFAULT now(),read_at timestamptz,
  pushed_at timestamptz,delivery_outcome text,delivery_lease_expiry timestamptz);
CREATE TABLE public.group_members(user_id uuid,group_id uuid,monitored boolean,watching boolean,status text);
CREATE TABLE public.gm_mutes(user_id uuid,muted_until timestamptz);
CREATE TABLE public.passive_checkin_accounts(user_id uuid PRIMARY KEY,engine_mode text,active_contract_version_id uuid,
  active_epoch_id uuid,updated_at timestamptz);
CREATE TABLE public.passive_checkin_contract_versions(id uuid PRIMARY KEY,user_id uuid,interval_minutes integer);
CREATE TABLE public.passive_monitoring_epochs(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,
  contract_version_id uuid,started_at timestamptz,ended_at timestamptz,start_reason text NOT NULL
    CHECK(start_reason IN('contract_saved','explicit_resolution','manual_reset','rollback')),end_reason text);
CREATE UNIQUE INDEX passive_monitoring_epochs_one_active_per_user ON public.passive_monitoring_epochs(user_id) WHERE ended_at IS NULL;
CREATE TABLE public.passive_checkin_windows(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,epoch_id uuid,
  contract_version_id uuid,ordinal bigint,window_start timestamptz,window_end timestamptz,arrival_deadline timestamptz,
  outcome text DEFAULT 'pending',finalized_at timestamptz,superseded_reason text);
CREATE TABLE private.passive_checkin_runtime_control(singleton boolean,globally_disabled boolean);
INSERT INTO private.passive_checkin_runtime_control VALUES(true,true);
CREATE TABLE private.passive_alert_causal_windows(alert_id uuid,window_id uuid,ordinal integer);
CREATE TABLE private.job_failures(job_name text,subject_id uuid,sqlstate text,message text);
CREATE FUNCTION private.trigger_push_dispatch() RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION private.sleep_relaxed(uuid,timestamptz) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION private.passive_sleep_relaxed(uuid,uuid,timestamptz) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION private.silence_threshold(uuid) RETURNS interval LANGUAGE sql AS $$ SELECT interval '2 hours' $$;
CREATE FUNCTION public.process_passive_checkins() RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION private.notify_stage(_id uuid,_uid uuid,_stage text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.notifications(recipient_id,alert_id,kind,body) VALUES(_uid,_id,_stage,'test notification') $$;
CREATE FUNCTION private.notify_auto_resolved(uuid,uuid) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION private.passive_awake_deadline(uuid,timestamptz,integer) RETURNS timestamptz LANGUAGE sql
  AS $$ SELECT $2+make_interval(mins=>$3) $$;
CREATE FUNCTION private.passive_window_arrival_allowance(uuid,timestamptz,timestamptz) RETURNS interval LANGUAGE sql
  AS $$ SELECT interval '0 minutes' $$;
