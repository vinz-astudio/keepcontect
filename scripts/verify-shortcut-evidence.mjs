// Isolated Postgres/WASM check. No credentials, network, scheduler or production connection.
// Install the runtime into an untracked local tools directory, then pass its node_modules path:
// npm install --prefix supabase/.temp/passive-repair --ignore-scripts --no-audit --no-fund @electric-sql/pglite@0.5.8 @electric-sql/pglite-pgtap@0.0.9
// node scripts/verify-shortcut-evidence.mjs
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
const runtime = resolve(process.argv[2] ?? 'supabase/.temp/passive-repair/node_modules')
const { PGlite } = await import(pathToFileURL(resolve(runtime, '@electric-sql/pglite/dist/index.js')))
const { pgcrypto } = await import(pathToFileURL(resolve(runtime, '@electric-sql/pglite/dist/contrib/pgcrypto.js')))
const { pgtap } = await import(pathToFileURL(resolve(runtime, '@electric-sql/pglite-pgtap/dist/index.js')))
const db = await PGlite.create({ extensions: { pgcrypto, pgtap } })
const read = (file) => readFile(resolve(file), 'utf8')
try {
  await db.exec(`
    CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA extensions;
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    CREATE EXTENSION pgcrypto WITH SCHEMA extensions; CREATE EXTENSION pgtap;
    CREATE TABLE auth.users(id uuid PRIMARY KEY, email text, aud text, role text);
    CREATE TABLE public.alerts(id uuid PRIMARY KEY);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  `)
  await db.exec(await read('supabase/migrations/20260814183000_passive_checkin_contract.sql'))
  await db.exec(await read('supabase/migrations/20260814190000_passive_evidence_ingest.sql'))
  const rolling = await read('supabase/migrations/20260821020000_deadlines_roll_and_sleep_is_not_counted.sql')
  const start = rolling.indexOf('CREATE OR REPLACE FUNCTION private.record_passive_evidence(')
  if (start < 0) throw new Error('Current validator missing')
  await db.exec(rolling.slice(start, rolling.indexOf('$$;', start) + 3))
  if (!process.argv.includes('--before-fix')) {
    await db.exec(await read('supabase/migrations/20260919032300_scoped_shortcut_evidence.sql'))
  }
  const results = await db.exec(await read('supabase/tests/shortcut_evidence.sql'))
  const lines = results.flatMap((result) => result.rows.flatMap((row) => Object.values(row))).filter((v) => typeof v === 'string' && /^(ok |not ok |1\.\.|#)/.test(v))
  console.log(lines.join('\n'))
  const planned = Number(lines.find((line) => /^1\.\./.test(line))?.slice(3))
  if (!planned || lines.some((line) => /^not ok |^# Looks/.test(line)) || lines.filter((line) => /^ok /.test(line)).length !== planned) throw new Error('Shortcut evidence contract failed')
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
} finally { await db.close() }
