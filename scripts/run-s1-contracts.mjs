import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'
import { S1_CONTRACTS, classifyAssertion, validateCatalog } from './s1-contract-catalog.mjs'

export function groupRunnableRows(rows) {
  const groups = new Map()
  for (const row of rows) {
    if (row.layer === 'external') continue
    const key = `${row.layer}\0${row.file}`
    if (!groups.has(key)) groups.set(key, { layer: row.layer, file: row.file, rows: [] })
    groups.get(key).rows.push(row)
  }
  return [...groups.values()]
}

function commandFor(group) {
  if (group.layer === 'pgtap') {
    return ['exec', '--package=supabase@2.109.1', '--', 'supabase', 'test', 'db', '--local', group.file]
  }
  if (group.layer === 'vitest') return ['exec', '--', 'vitest', 'run', '--reporter=verbose', group.file]
  throw new Error(`unsupported layer: ${group.layer}`)
}

async function defaultExecute(group, { root }) {
  const args = commandFor(group)
  const executable = process.platform === 'win32' ? 'npm.cmd' : 'npm'
  const run = spawnSync(executable, args, { cwd: root, encoding: 'utf8' })
  return {
    exitCode: run.status ?? 1,
    output: `${run.stdout ?? ''}${run.stderr ?? ''}`,
    command: `npm ${args.join(' ')}`,
  }
}

export async function runCatalog(rows, { root, execute = defaultExecute }) {
  const byId = new Map()
  for (const group of groupRunnableRows(rows)) {
    const execution = await execute(group, { root })
    const output = String(execution.output ?? '')
    const hash = crypto.createHash('sha256').update(output).digest('hex')
    for (const row of group.rows) {
      byId.set(row.id, {
        ...row,
        result: classifyAssertion(row.expected, row.id, output),
        command: execution.command ?? null,
        exitCode: execution.exitCode ?? null,
        outputSha256: hash,
      })
    }
  }

  return rows.map((row) => byId.get(row.id) ?? {
    ...row,
    result: row.expected === 'blocked' ? 'BLOCKED' : 'HARNESS_FAILURE',
    command: null,
    exitCode: null,
    outputSha256: null,
  })
}

function cell(value) {
  return String(value ?? '—').replaceAll('|', '\\|').replaceAll('\n', ' ')
}

export function renderBaseline(rows, { head, generatedAt }) {
  const counts = Object.fromEntries(['PASS', 'RED', 'BLOCKED', 'HARNESS_FAILURE'].map((key) => [key, 0]))
  for (const row of rows) counts[row.result] = (counts[row.result] ?? 0) + 1
  const green = rows.length > 0 && rows.every((row) => row.result === 'PASS')
  const summary = `PASS ${counts.PASS} · RED ${counts.RED} · BLOCKED ${counts.BLOCKED} · HARNESS_FAILURE ${counts.HARNESS_FAILURE}`
  const lines = [
    '# S1 Contract Baseline',
    '',
    `Generated: ${generatedAt}`,
    `HEAD: \`${head}\``,
    '',
    `Summary: ${summary}`,
    `Status: **${green ? 'green' : 'not green'}**`,
    '',
    '> Local evidence only. No production deployment, release, or remote database mutation.',
    '',
    '| ID | Pack | Result | Route | Invariant | Command | Output SHA-256 |',
    '| --- | --- | --- | --- | --- | --- | --- |',
  ]
  for (const row of rows) {
    lines.push(`| ${cell(row.id)} | ${cell(row.pack)} | ${cell(row.result)} | ${cell(row.route)} | ${cell(row.invariant)} | ${cell(row.command)} | ${cell(row.outputSha256)} |`)
  }
  return `${lines.join('\n')}\n`
}

async function main() {
  const args = process.argv.slice(2)
  if (!args.includes('--local')) throw new Error('refusing to run without --local')
  const outIndex = args.indexOf('--out')
  const out = outIndex >= 0 ? args[outIndex + 1] : null
  if (!out) throw new Error('--out <path> is required')
  const root = process.cwd()
  const errors = validateCatalog(S1_CONTRACTS, root, { final: true })
  if (errors.length) throw new Error(`invalid S1 catalog:\n${errors.join('\n')}`)
  const rows = await runCatalog(S1_CONTRACTS, { root })
  const git = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' })
  const markdown = renderBaseline(rows, {
    head: git.status === 0 ? git.stdout.trim() : 'unknown',
    generatedAt: new Date().toISOString(),
  })
  fs.mkdirSync(path.dirname(path.resolve(root, out)), { recursive: true })
  fs.writeFileSync(path.resolve(root, out), markdown, 'utf8')
  if (rows.some((row) => row.result === 'HARNESS_FAILURE')) process.exitCode = 2
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error}\n`)
    process.exitCode = 2
  })
}
