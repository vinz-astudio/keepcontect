import { describe, expect, it } from 'vitest'
import { readHistoricalMigration } from '../../../scripts/migration-sources.mjs'

function extractFunction(sql: string, signature: string): string {
  const start = sql.indexOf(signature)
  expect(start).toBeGreaterThanOrEqual(0)
  const next = sql.indexOf('create or replace function ', start + signature.length)
  return sql.slice(start, next === -1 ? sql.length : next)
}

// HISTORICAL. ADR-0022's fixed sensitivity templates were retired by ADR-0037:
// private.silence_threshold now reads the account's learned normal bounds, and
// no evidence means a NULL threshold rather than a two-and-a-quarter hour
// default. Nothing below describes how the live system behaves.
//
// It is kept because the migration it reads is the provenance of the shipping
// baseline, and an edit to that archived text would mean the baseline no longer
// has the history it claims. S0 moved the file into
// supabase/migrations-archive, which is why this reads through
// readHistoricalMigration instead of scanning supabase/migrations — and why it
// now throws a located error rather than failing as "expected 0 to be 1".
describe('ADR-0022 alert threshold migration contract (retired by ADR-0037; archived provenance)', () => {
  it('uses one append-only correction with exact additive sensitivity values', () => {
    // Two files carry this name: the repository's 20260719154339 and
    // production's 20260719162146. Their contents are identical once
    // whitespace is normalised, so this is one correction re-stamped on its way
    // to production, not two corrections — but the pair is why the lookup has
    // to say which history it means rather than assuming a single match.
    const sql = readHistoricalMigration('correct_gate1_sensitivity_contract', {
      origin: 'from-repo',
    }).sql
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
    const gate1 = readHistoricalMigration('routine_ai_gate1_containment')
      .sql
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
