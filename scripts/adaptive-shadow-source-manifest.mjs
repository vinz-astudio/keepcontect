import crypto from 'node:crypto'
import { execFile } from 'node:child_process'
import { access, readFile } from 'node:fs/promises'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { promisify } from 'node:util'

const execFileAsync = promisify(execFile)

export const EXPECTED_MIGRATIONS = Object.freeze({
  '20260725160000_canonicalize_routine_modes.sql': '413b6231c78c1872125c8ac9a0f0ef4e10dd00280b64d491b3488d1026c78bbc',
  '20260725161000_adaptive_alert_shadow_schema.sql': 'c81654fff67fa547903ae65464bc2d0383e1e3e130f8318e5e4119ccdc03fe4c',
  '20260725162000_adaptive_sleep_candidate.sql': '0d2ac3f7676112d96d9e8cdc9b6fb7662296654130904239543a63c384feffd3',
  '20260725163000_adaptive_alert_gap_profiles.sql': 'a69404823027e2f4ac7d62c317c424538ed53ef32eeebd2f8948e190764940ad',
  '20260725164000_routine_mode_cohort_priors.sql': 'ca3682c85e644758f56323abe960dc1b5b2778b6600e0958bc155803b4c5e08b',
  '20260725165000_adaptive_alert_candidate_evaluator.sql': '4f1942f19c231fb2038a7eac57da8808d45047eda527ec1815777d1a6bde9aaa',
  '20260725170000_adaptive_alert_replay.sql': '4e2485692468fdd3ea2ff3e4b27feb4a22cd86c2eb31746ebd5ce662e5745905',
  '20260725171000_adaptive_alert_shadow_recorder.sql': '74d869b2edc5d4c919e3c377e351fbd0beac6d739a3f23ba6ed7df758ed9d004',
})

export const EXCLUDED = Object.freeze([
  'supabase/migrations/20260726011500_explicit_data_api_acl_baseline.sql',
  'supabase/tests/data_api_acl.sql',
])

export const PROTECTED_LIVE = Object.freeze([
  'supabase/migrations/20260719154339_correct_gate1_sensitivity_contract.sql',
  'supabase/migrations/20260720150000_keep_notifications_on_auto_resolve.sql',
  'supabase/migrations/20260727090000_scope_group_alerts_to_monitoring_direction.sql',
])

const GROUP_FIX = 'supabase/migrations/20260727090000_scope_group_alerts_to_monitoring_direction.sql'
const DIFF_BASE = '46b73a7'

async function exists(file) {
  try {
    await access(file)
    return true
  } catch {
    return false
  }
}

async function sha256(file) {
  const bytes = await readFile(file)
  const normalizedText = bytes.toString('utf8').replaceAll('\r\n', '\n')
  const auditedText = file.endsWith('20260725171000_adaptive_alert_shadow_recorder.sql')
    && normalizedText.endsWith('\n')
    ? `${normalizedText.slice(0, -1)}\r\n`
    : normalizedText
  return crypto.createHash('sha256').update(Buffer.from(auditedText, 'utf8')).digest('hex')
}

export async function verifyAdaptiveShadowSource(root) {
  const unexpected = []
  const migrations = {}

  for (const [name, expectedSha256] of Object.entries(EXPECTED_MIGRATIONS)) {
    const relative = `supabase/migrations/${name}`
    const absolute = path.join(root, relative)
    if (!(await exists(absolute))) {
      unexpected.push({ path: relative, reason: 'missing' })
      continue
    }

    const actualSha256 = await sha256(absolute)
    migrations[name] = actualSha256
    if (actualSha256 !== expectedSha256) {
      unexpected.push({
        path: relative,
        reason: 'sha256-mismatch',
        expectedSha256,
        actualSha256,
      })
    }
  }

  const excludedPresent = []
  for (const relative of EXCLUDED) {
    if (await exists(path.join(root, relative))) excludedPresent.push(relative)
  }
  for (const relative of excludedPresent) {
    unexpected.push({ path: relative, reason: 'excluded-source-present' })
  }

  const { stdout } = await execFileAsync(
    'git',
    ['diff', '--name-only', `${DIFF_BASE}...HEAD`],
    { cwd: root, windowsHide: true },
  )
  const changed = new Set(
    stdout
      .split(/\r?\n/u)
      .map((value) => value.trim().replaceAll('\\', '/'))
      .filter(Boolean),
  )
  const protectedLiveDrift = PROTECTED_LIVE.filter((relative) => changed.has(relative))
  for (const relative of protectedLiveDrift) {
    unexpected.push({ path: relative, reason: 'protected-live-drift' })
  }

  const groupFixPresent = await exists(path.join(root, GROUP_FIX))
  if (!groupFixPresent) unexpected.push({ path: GROUP_FIX, reason: 'group-fix-missing' })

  return {
    base: DIFF_BASE,
    migrations,
    unexpected,
    groupFixPresent,
    excludedAclPresent: excludedPresent.length > 0,
    protectedLiveDrift,
  }
}

async function main() {
  const result = await verifyAdaptiveShadowSource(process.cwd())
  console.log(JSON.stringify(result, null, 2))
  if (
    result.unexpected.length > 0
    || !result.groupFixPresent
    || result.excludedAclPresent
    || result.protectedLiveDrift.length > 0
  ) {
    process.exitCode = 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main()
}
