-- Ensure the released baseline has production artifact URLs.
-- Canary rows are written by scripts/release-canary.mjs from immutable GitHub tag assets.
update public.app_versions
set
  apk_url = coalesce(apk_url, 'https://keep-contact-mauve.vercel.app/keep-contact.apk'),
  exe_url = coalesce(exe_url, 'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe')
where version = '0.5.16'
  and status = 'released';

-- Remove stale canary rows created by the retired iteration/preview workflow.
-- A canary row must be recreated by scripts/release-canary.mjs from GitHub tag assets.
delete from public.app_versions
where status = 'canary'
  and (
    apk_url is null
    or apk_url like '%keep-contact-mauve.vercel.app%'
    or apk_url like '%keep-contact-git-iteration%'
  );
