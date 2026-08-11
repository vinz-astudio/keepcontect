-- S3-B · Special Attention: a private, default-off notification preference.
--
-- Why this exists
-- ---------------
-- ADR-0039: an ordinary group member sees a name and a status in the list, and
-- nothing more. If they want to be told when one particular person's protection
-- coverage breaks, the only honest way to offer that is a preference that is
--
--   * private        — the subject never learns who is watching out for them,
--                      and no other member can enumerate subscribers;
--   * off by default — the absence of a row means off, and no migration seeds one;
--   * powerless      — it adds no data visibility and no operational authority.
--
-- Without it the alternatives are worse: widen everyone's notifications until
-- people learn to ignore them, or push members into a care relationship that
-- carries authority they should not have.
--
-- This package builds the subscription and the eligibility surface only. The
-- notice itself ("device or app coverage was interrupted; this does not mean
-- the person is in danger") is emitted by S3-C, which owns protection health
-- and the subject's own prompt plus the extra health grace that must precede it.
--
-- Append-only: no historical migration is edited.

CREATE TABLE IF NOT EXISTS public.special_attention_subscriptions (
  subscriber_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  subject_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (subscriber_id, subject_id),
  CONSTRAINT special_attention_not_self CHECK (subscriber_id <> subject_id)
);

COMMENT ON TABLE public.special_attention_subscriptions IS
  'ADR-0039 private, default-off notification preference. No row means off. Never exposed through the Data API; owner-scoped RPCs only.';

CREATE INDEX IF NOT EXISTS special_attention_subject_idx
  ON public.special_attention_subscriptions (subject_id);

ALTER TABLE public.special_attention_subscriptions ENABLE ROW LEVEL SECURITY;

-- Deliberately no policy and no grant. Subscriber identity is private, so there
-- is no Data API path at all: every read and write goes through an owner-scoped
-- SECURITY DEFINER function below.
REVOKE ALL ON TABLE public.special_attention_subscriptions FROM PUBLIC;
REVOKE ALL ON TABLE public.special_attention_subscriptions FROM anon;
REVOKE ALL ON TABLE public.special_attention_subscriptions FROM authenticated;

-- Explicit default-off setter. Enabling requires a currently active
-- relationship; disabling never does, so somebody can always withdraw.
CREATE OR REPLACE FUNCTION public.set_special_attention(_subject uuid, _enabled boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  _uid uuid := auth.uid();
  _eligible boolean;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _subject is null then raise exception 'bad target'; end if;
  if _uid = _subject then raise exception 'bad target'; end if;

  select
    exists (
      select 1
      from public.group_members as mine
      join public.group_members as theirs on theirs.group_id = mine.group_id
      where mine.user_id = _uid
        and theirs.user_id = _subject
        and mine.status = 'active'
        and theirs.status = 'active'
    )
    or exists (
      select 1
      from public.guardianships as g
      where g.ward_id = _subject
        and g.guardian_id = _uid
        and g.status = 'active'
    )
  into _eligible;

  if _enabled is not true then
    delete from public.special_attention_subscriptions
    where subscriber_id = _uid and subject_id = _subject;
    return;
  end if;

  if _eligible is not true then
    raise exception 'relationship not active';
  end if;

  insert into public.special_attention_subscriptions (subscriber_id, subject_id)
  values (_uid, _subject)
  on conflict (subscriber_id, subject_id)
  do update set updated_at = now();
end;
$function$;

-- Owner-scoped reader. A caller can only ever see their own preferences, which
-- is what keeps the subject from learning who subscribed.
CREATE OR REPLACE FUNCTION public.my_special_attention()
RETURNS TABLE (subject_id uuid, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  select s.subject_id, s.created_at
  from public.special_attention_subscriptions as s
  where s.subscriber_id = auth.uid()
  order by s.created_at;
$function$;

-- Notification eligibility. A stored preference is not a standing entitlement:
-- it only counts while the relationship that justified it is still active. A
-- relationship that has gone inactive, or a guardianship that was revoked,
-- stops producing notices immediately, without silently deleting the person's
-- own preference — if the relationship comes back, so does their choice.
CREATE OR REPLACE FUNCTION public.special_attention_recipients(_subject uuid)
RETURNS TABLE (subscriber_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  select distinct s.subscriber_id
  from public.special_attention_subscriptions as s
  where s.subject_id = _subject
    and (
      exists (
        select 1
        from public.group_members as mine
        join public.group_members as theirs on theirs.group_id = mine.group_id
        where mine.user_id = s.subscriber_id
          and theirs.user_id = _subject
          and mine.status = 'active'
          and theirs.status = 'active'
      )
      or exists (
        select 1
        from public.guardianships as g
        where g.ward_id = _subject
          and g.guardian_id = s.subscriber_id
          and g.status = 'active'
          and g.status not in ('revoked', 'inactive')
      )
    );
$function$;

REVOKE ALL ON FUNCTION public.set_special_attention(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.my_special_attention() FROM PUBLIC;
-- Supabase grants EXECUTE on new public functions to anon and authenticated by
-- default, so revoking from PUBLIC alone is not enough here: recipient
-- resolution must be revoked from the client roles by name.
REVOKE ALL ON FUNCTION public.special_attention_recipients(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.special_attention_recipients(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.special_attention_recipients(uuid) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.set_special_attention(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_special_attention() TO authenticated;
-- Recipient resolution is a server-side concern only; no client may enumerate
-- who is watching out for a given person.
