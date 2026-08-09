import fs from 'node:fs'
import path from 'node:path'

export const REQUIRED_PACKS = ['alert-activity', 'coverage-learning', 'care-authority', 'platform']

export const S1_CONTRACTS = [
  {
    id: 'ADR0039-ACTIVITY-01',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/activity_never_answers_an_alert_in_cron.sql',
    expected: 'pass',
    route: 'S1',
    invariant: 'Passive activity never answers an alert',
  },
  {
    id: 'ADR0039-CONCERN-01',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Concern requires an existing active alert',
  },
  {
    id: 'ADR0039-CONCERN-02',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'GM Concern requires an existing active alert',
  },
  {
    id: 'ADR0039-CONCERN-03',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
    expected: 'pass',
    route: 'S3',
    invariant: 'Concern preserves the active alert identity and status',
  },
  {
    id: 'ADR0039-CONCERN-04',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
    expected: 'pass',
    route: 'S3',
    invariant: 'Concern is alert-bound notification only, never activity or confirmation',
  },
  {
    id: 'ADR0039-GUARDIAN-CONFIRM-01',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
    expected: 'pass',
    route: 'S2',
    invariant: 'Guardian confirmation records external actor and confirmed_safe provenance',
  },
  {
    id: 'ADR0039-GUARDIAN-CONFIRM-02',
    pack: 'alert-activity',
    layer: 'pgtap',
    file: 'supabase/tests/s1_alert_activity_concern_contract.sql',
    expected: 'pass',
    route: 'S2',
    invariant: 'External confirmation never becomes Ward activity evidence',
  },
  {
    id: 'ADR0039-LEARN-01',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Normal bounds require observation coverage intervals',
  },
  {
    id: 'ADR0039-LEARN-02',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Learning excludes manual, Guardian, Shortcut, and replay evidence',
  },
  {
    id: 'ADR0039-LEARN-03',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Exceptional long gaps require two independent comparable dates',
  },
  {
    id: 'ADR0039-LEARN-04',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Only coverage-valid evidence may mutate learned bounds',
  },
  {
    id: 'ADR0039-HEALTH-01',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Server exposes authoritative protection health',
  },
  {
    id: 'ADR0039-HEALTH-02',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Protection health exposes readiness, incidents, and recovery evidence',
  },
  {
    id: 'ADR0039-HEALTH-03',
    pack: 'coverage-learning',
    layer: 'pgtap',
    file: 'supabase/tests/s1_coverage_learning_health_contract.sql',
    expected: 'red',
    route: 'S3',
    invariant: 'Acknowledgement is not recovery and outage does not create personal alerts',
  },
  {
    id: 'ADR0039-IOS-EXT-01',
    pack: 'platform',
    layer: 'external',
    file: null,
    expected: 'blocked',
    route: 'S4',
    invariant: 'iOS native guardian behavior is proven on signed hardware and App Review evidence',
  },
  {
    id: 'ADR0039-AAB-EXT-01',
    pack: 'platform',
    layer: 'external',
    file: null,
    expected: 'blocked',
    route: 'S4',
    invariant: 'AAB guardian behavior is proven by Play review and real-device evidence',
  },
  {
    id: 'ADR0039-TAURI-EXT-01',
    pack: 'platform',
    layer: 'external',
    file: null,
    expected: 'blocked',
    route: 'S4',
    invariant: 'Signed Tauri background, notification, and update behavior is proven on target desktops',
  },
]

const ENUMS = {
  pack: new Set(REQUIRED_PACKS),
  layer: new Set(['pgtap', 'vitest', 'external']),
  expected: new Set(['pass', 'red', 'blocked']),
  route: new Set(['S1', 'S2', 'S3', 'S4', 'human']),
}

export function validateCatalog(rows, root, { final = false } = {}) {
  const errors = []
  const seen = new Set()

  for (const row of rows) {
    if (!row || typeof row !== 'object') {
      errors.push('invalid row')
      continue
    }
    if (!/^ADR0039-[A-Z0-9-]+$/.test(row.id ?? '')) errors.push(`invalid id: ${row.id ?? ''}`)
    if (seen.has(row.id)) errors.push(`duplicate id: ${row.id}`)
    seen.add(row.id)

    for (const [field, allowed] of Object.entries(ENUMS)) {
      if (!allowed.has(row[field])) errors.push(`invalid ${field}: ${row[field] ?? ''}`)
    }
    if (!row.invariant || typeof row.invariant !== 'string') errors.push(`missing invariant: ${row.id ?? ''}`)
    if (row.layer === 'external') {
      if (row.expected !== 'blocked') errors.push(`external row must be blocked: ${row.id}`)
    } else if (!row.file || typeof row.file !== 'string') {
      errors.push(`missing file: ${row.file ?? ''}`)
    } else if (!fs.existsSync(path.resolve(root, row.file))) {
      errors.push(`missing file: ${row.file}`)
    }
  }

  if (final) {
    const packs = new Set(rows.map((row) => row.pack))
    for (const pack of REQUIRED_PACKS) {
      if (!packs.has(pack)) errors.push(`missing pack: ${pack}`)
    }
  }
  return errors
}

export function classifyAssertion(expected, id, output) {
  if (expected === 'blocked') return 'BLOCKED'
  if (/Bail out!|ERR_MODULE_NOT_FOUND|Cannot find module|failed to load|\bERROR\b/i.test(output)) {
    return 'HARNESS_FAILURE'
  }

  const line = String(output).split(/\r?\n/).find((candidate) => candidate.includes(id))
  if (!line) return 'HARNESS_FAILURE'

  const failed = /\bnot ok\b|(?:^|\s)(?:FAIL|Ã—|×)(?:\s|$)/i.test(line)
  const passed = !failed && (/\bok\b|(?:^|\s)(?:PASS|âœ“|✓)(?:\s|$)/i.test(line))
  if (failed) return expected === 'red' ? 'RED' : 'UNEXPECTED_RED'
  if (passed) return expected === 'pass' ? 'PASS' : 'UNEXPECTED_PASS'
  return 'HARNESS_FAILURE'
}
