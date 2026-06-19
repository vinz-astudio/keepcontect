# Operations Checklist

## Release verification

Run these before every production deploy:

```bash
npm run typecheck
npm test
npm run build
npm run cap:sync
vercel --prod --yes
```

After deployment, verify:

```bash
vercel inspect keep-contact-mauve.vercel.app
curl.exe -I https://keep-contact-mauve.vercel.app/
curl.exe -I https://keep-contact-mauve.vercel.app/sw.js
```

Expected `sw.js` cache policy:

```text
Cache-Control: no-cache, no-store, must-revalidate
```

## Supabase health checks

Use the connected Supabase plugin against project `byekgmqyqlftgoveqnku`.

Check cron jobs:

```sql
select jobid, jobname, schedule, command, active
from cron.job
order by jobid;
```

Check recent cron runs:

```sql
select jobid, status, return_message, start_time, end_time
from cron.job_run_details
where start_time > now() - interval '30 minutes'
order by start_time desc;
```

Run Supabase security and performance advisors after every migration.

## Known remaining hardening work

- Move intentionally callable privileged RPC internals out of exposed `public` functions, keeping only narrow public wrappers.
- Move `pg_net` extension out of `public` if Supabase platform support and existing cron references allow it.
- Enable leaked password protection in Supabase Auth dashboard.
- Add end-to-end tests for SOS, group activity visibility, push dispatch, and passive ping ingestion.