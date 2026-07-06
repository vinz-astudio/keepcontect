// Sync one app_versions rollout row.
// Usage:
//   node scripts/sync-app-version.mjs canary 0.5.17 https://...apk https://...exe
//   node scripts/sync-app-version.mjs released 0.5.17 https://...apk https://...exe

import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'
import { tmpdir } from 'node:os'
import { createClient } from '@supabase/supabase-js'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

function parseEnvLine(line) {
  const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/)
  if (!match) return null
  const key = match[1]
  let value = match[2].trim()
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1)
  }
  return [key, value]
}

function loadLocalEnv() {
  const env = { ...process.env }
  for (const name of ['.env', '.env.local', '.env.development.local']) {
    const path = join(root, name)
    if (!existsSync(path)) continue
    for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
      const pair = parseEnvLine(line)
      if (pair && env[pair[0]] == null) env[pair[0]] = pair[1]
    }
  }
  return env
}

function sqlFor(row) {
  const esc = (value) => String(value ?? '').replaceAll("'", "''")
  return [
    'insert into public.app_versions (version, status, apk_url, exe_url, public_rollout)',
    `values ('${esc(row.version)}', '${esc(row.status)}', '${esc(row.apk_url)}', '${esc(row.exe_url)}', false)`,
    'on conflict (version) do update set',
    '  status = excluded.status,',
    '  apk_url = excluded.apk_url,',
    '  exe_url = excluded.exe_url,',
    '  public_rollout = false;',
  ].join('\n')
}

function warnManual(row, reason) {
  console.warn(`   ! Could not sync app_versions automatically: ${reason}`)
  console.warn('   ! Run this SQL as a GM/admin instead:')
  console.warn(sqlFor(row))
}

function trySupabaseCli(row, env) {
  if (!env.SUPABASE_ACCESS_TOKEN) return false

  const dir = mkdtempSync(join(tmpdir(), 'kc-rollout-'))
  const file = join(dir, 'sync.sql')
  writeFileSync(file, sqlFor(row))

  try {
    if (process.platform === 'win32') {
      execFileSync(
        'cmd.exe',
        ['/d', '/s', '/c', `npx supabase db query --linked --file ${file}`],
        {
          cwd: root,
          env: { ...process.env, SUPABASE_ACCESS_TOKEN: env.SUPABASE_ACCESS_TOKEN },
          stdio: 'inherit',
        },
      )
    } else {
      execFileSync(
        'npx',
        ['supabase', 'db', 'query', '--linked', '--file', file],
        {
          cwd: root,
          env: { ...process.env, SUPABASE_ACCESS_TOKEN: env.SUPABASE_ACCESS_TOKEN },
          stdio: 'inherit',
        },
      )
    }
    console.log(`   - app_versions synced via Supabase CLI: ${row.status} v${row.version}`)
    return true
  } catch (error) {
    console.warn(`   ! Supabase CLI sync failed: ${error instanceof Error ? error.message : String(error)}`)
    return false
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

const [channel, version, apkUrl = '', exeUrl = ''] = process.argv.slice(2)
if (!['canary', 'released'].includes(channel) || !version) {
  console.error('Usage: node scripts/sync-app-version.mjs <canary|released> <version> [apkUrl] [exeUrl]')
  process.exit(1)
}

const row = {
  version,
  status: channel,
  apk_url: apkUrl,
  exe_url: exeUrl,
  public_rollout: false,
}

const env = loadLocalEnv()
const supabaseUrl = env.VITE_SUPABASE_URL
const anonKey = env.VITE_SUPABASE_ANON_KEY
const email = env.KC_ROLLOUT_EMAIL || env.VITE_DEV_EMAIL
const password = env.KC_ROLLOUT_PASSWORD || env.VITE_DEV_PASSWORD

if (trySupabaseCli(row, env)) {
  process.exit(0)
}

if (!supabaseUrl || !anonKey || !email || !password) {
  warnManual(row, 'missing VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY, KC_ROLLOUT_EMAIL/KC_ROLLOUT_PASSWORD, or VITE_DEV_EMAIL/VITE_DEV_PASSWORD')
  process.exit(0)
}

const supabase = createClient(supabaseUrl, anonKey)
const { error: signInError } = await supabase.auth.signInWithPassword({ email, password })
if (signInError) {
  warnManual(row, signInError.message)
  process.exit(0)
}

const { error } = await supabase
  .from('app_versions')
  .upsert(row, { onConflict: 'version' })

if (error) {
  warnManual(row, error.message)
  process.exit(0)
}

console.log(`   - app_versions synced: ${channel} v${version}`)
