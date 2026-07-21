import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

function extractFunction(sql: string, signature: string): string {
  const start = sql.indexOf(signature)
  expect(start).toBeGreaterThanOrEqual(0)
  const next = sql.indexOf('create or replace function ', start + signature.length)
  return sql.slice(start, next === -1 ? sql.length : next)
}

describe('ADR-0022 alert threshold migration contract', () => {
  const migrationsDir = path.resolve('supabase/migrations')

  it('uses one append-only correction with exact additive sensitivity values', () => {
    const correctionFiles = fs
      .readdirSync(migrationsDir)
      .filter((file) => file.includes('correct_gate1_sensitivity_contract'))

    expect(correctionFiles).toHaveLength(1)

    const sql = fs.readFileSync(
      path.join(migrationsDir, correctionFiles[0]),
      'utf8',
    )
    const normalized = sql.toLowerCase()

    expect(sql).toContain(
      'CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)',
    )
    expect(normalized).toContain('stable security definer')
    expect(normalized).toContain("set search_path = ''")
    expect(normalized).toMatch(
      /when\s+'high'\s+then\s+interval\s+'1\.5 hours'/,
    )
    expect(normalized).toMatch(
      /when\s+'sensitive'\s+then\s+interval\s+'1\.5 hours'/,
    )
    expect(normalized).toMatch(
      /when\s+'low'\s+then\s+interval\s+'3 hours'/,
    )
    expect(normalized).toMatch(
      /when\s+'relaxed'\s+then\s+interval\s+'3 hours'/,
    )
    expect(normalized).toContain("else interval '2.25 hours'")
    expect(normalized).toContain(
      'revoke execute on function private.silence_threshold(uuid) from public, anon, authenticated',
    )

    expect(normalized).not.toContain('user_activity_profiles')
    expect(normalized).not.toContain('hourly_thresholds')
    expect(normalized).not.toContain('gemini')
    expect(normalized).not.toContain('openai')
  })

  it('preserves all established consumers and keeps GM descriptive bands separate', () => {
    const gate1Files = fs
      .readdirSync(migrationsDir)
      .filter((file) => file.includes('routine_ai_gate1_containment'))
    expect(gate1Files).toHaveLength(1)

    const gate1 = fs
      .readFileSync(path.join(migrationsDir, gate1Files[0]), 'utf8')
      .toLowerCase()

    const processEscalations = extractFunction(
      gate1,
      'create or replace function public.process_escalations()',
    )
    const routineStatus = extractFunction(
      gate1,
      'create or replace function public.my_routine_status()',
    )
    const groupActivityView = extractFunction(
      gate1,
      'create or replace function public.get_group_activity_view(',
    )
    const groupActivity = extractFunction(
      gate1,
      'create or replace function public.get_group_activity(',
    )
    expect(processEscalations).toContain('private.silence_threshold')
    expect(routineStatus).toContain('private.silence_threshold')
    expect(groupActivityView).toContain('private.silence_threshold')
    expect(groupActivity).toContain('private.silence_threshold')

    const gmDefinition = extractFunction(
      gate1,
      'create or replace function public.gm_list_clients()',
    )
    expect(gmDefinition).toContain("interval '6 hours'")
    expect(gmDefinition).toContain("interval '24 hours'")
    expect(gmDefinition).not.toContain('private.silence_threshold')
  })
})
