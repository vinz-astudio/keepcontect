-- These columns count EPISODES, not alert rows: one per distinct silence that
-- would cross the rule's threshold, however long that silence runs.
--
-- The alerts table holds far more rows than that. A single unbroken silence
-- re-alerts roughly every 30 minutes after each human resolution, because the
-- guardian-resolution cooldown expires while the user is still silent. Karma
-- Cheki has 101 silence alert rows over the same 30 days these columns score as
-- 13 episodes. Naming them alerts_* invited exactly the wrong comparison, on
-- data whose whole purpose is deciding when to wake someone's family.

ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_live TO episodes_live;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_candidate_floored TO episodes_candidate_floored;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_candidate_unfloored TO episodes_candidate_unfloored;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_candidate_only TO episodes_candidate_only;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_live_only TO episodes_live_only;

COMMENT ON TABLE public.account_threshold_shadow IS
  'ADR-0035 step 2, record only. Episode counts compare the candidate threshold against the live one on identical gap history; they are not a reconstruction of the alerts table.';