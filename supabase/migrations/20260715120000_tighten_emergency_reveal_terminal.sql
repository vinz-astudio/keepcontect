-- KCA-16 containment (ADR-0015): tighten emergency_info reveal to the urgent stage only.
--
-- The prior policy (20260623160000) revealed home address / contact / medical
-- info to guardians/watchers/community once an alert reached stage
-- 'group', 'community', OR 'terminal'. The product copy, however, promises
-- these details unlock only at the most urgent stage — so ordinary silence
-- escalation was over-exposing personal data one to two stages too early.
--
-- Human decision 2026-07-15: tighten to the most urgent stage.
--
-- Safety-preserving nuance: an SOS is the user's own explicit cry for help and
-- is created at stage 'group' (see public.raise_sos), yet it is maximally
-- urgent by nature — responders need the address immediately. So the reveal
-- gate is "stage = 'terminal' OR cause = 'sos'": silence/dark_device escalation
-- only reveals at 'terminal' (matching notify_stage, whose terminal message is
-- the one that says the address is unlocked; 'community' only asks responders
-- to help make contact), while an explicit SOS still reveals right away.
--
-- Rollback: recreate the previous policy with `a.stage in ('group','community','terminal')`.
-- This does not address the separate emergency_info encryption/key-handling
-- degradation (plaintext fallback, reusable-invite-code-derived key); that
-- remains a distinct future redesign ADR.

drop policy if exists emergency_info_select on public.emergency_info;

create policy emergency_info_select on public.emergency_info
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (
      exists (
        select 1 from public.alerts a
        where a.user_id = emergency_info.user_id
          and a.status = 'open'
          and (a.stage = 'terminal' or a.cause = 'sos')
      )
      and (
        private.is_guardian_of(user_id, (select auth.uid()))
        or private.watches_user((select auth.uid()), emergency_info.user_id)
        or private.shares_community((select auth.uid()), emergency_info.user_id)
      )
    )
  );
