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
