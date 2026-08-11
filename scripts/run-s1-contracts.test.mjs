import { describe, expect, test } from 'vitest'
import { groupRunnableRows, renderBaseline, runCatalog } from './run-s1-contracts.mjs'

const rows = [
  { id: 'ADR0039-A-01', pack: 'alert-activity', layer: 'pgtap', file: 'a.sql', expected: 'pass', route: 'S1', invariant: 'a' },
  { id: 'ADR0039-A-02', pack: 'alert-activity', layer: 'pgtap', file: 'a.sql', expected: 'red', route: 'S3', invariant: 'b' },
  { id: 'ADR0039-IOS-01', pack: 'platform', layer: 'external', file: null, expected: 'blocked', route: 'S4', invariant: 'c' },
]

describe('S1 runner', () => {
  test('executes each unique file once', () => {
    expect(groupRunnableRows(rows)).toEqual([
      { layer: 'pgtap', file: 'a.sql', rows: rows.slice(0, 2) },
    ])
  })

  test('classifies rows from one shared output', async () => {
    let calls = 0
    const result = await runCatalog(rows, {
      root: 'C:/repo',
      execute: async () => {
        calls += 1
        return { exitCode: 1, output: 'ok 1 - ADR0039-A-01\nnot ok 2 - ADR0039-A-02' }
      },
    })
    expect(calls).toBe(1)
    expect(result.map((row) => row.result)).toEqual(['PASS', 'RED', 'BLOCKED'])
    expect(result[0].outputSha256).toMatch(/^[a-f0-9]{64}$/)
  })

  test('renders explicit non-green summary', () => {
    const markdown = renderBaseline([
      { ...rows[0], result: 'PASS', command: 'cmd', exitCode: 0, outputSha256: 'a'.repeat(64) },
      { ...rows[1], result: 'RED', command: 'cmd', exitCode: 1, outputSha256: 'b'.repeat(64) },
      { ...rows[2], result: 'BLOCKED', command: null, exitCode: null, outputSha256: null },
    ], { head: 'abc', generatedAt: '2026-08-09T00:00:00.000Z' })
    expect(markdown).toContain('PASS 1 · RED 1 · BLOCKED 1 · HARNESS_FAILURE 0')
    expect(markdown).toContain('Status: **not green**')
  })
})
