import { describe, expect, it } from 'vitest'
import { extractLiveFunctionBodies } from '../../../scripts/migration-sources.mjs'

// This guard used to read five migration files by name. S0 folded that history
// into one baseline generated from production, the five names stopped
// resolving, and all three assertions began passing over an empty string —
// every `not.toMatch` is trivially true against nothing. The guard reported
// green for days while checking that no code contained anything.
//
// So it no longer names files. It finds the shadow system by what its
// functions are called, in whatever migration currently defines them, and
// fails if it cannot find them at all — a shadow system that has vanished from
// the shipping set is a finding, not a pass.

const SHADOW_FUNCTION = /(shadow|adaptive_alert|gap_profile|cohort_prior|routine_mode_candidate)/i

describe('ADR-0028 shadow isolation', () => {
  const blocks = extractLiveFunctionBodies(SHADOW_FUNCTION)
  const source = blocks.map((block) => block.body).join('\n')

  it('finds the shadow system in the shipping migration set', () => {
    // Guards the guard: without this, the three assertions below would pass
    // against an empty string the moment these functions move or are renamed.
    expect(blocks.length).toBeGreaterThan(0)
    expect(source.length).toBeGreaterThan(1000)
  })

  it('keeps the complete base scheduler-off', () => {
    expect(source).not.toMatch(/cron\.(schedule|alter_job|unschedule)/i)
  })

  it('contains no live alert DML target', () => {
    expect(source).not.toMatch(
      /\b(insert\s+into|update|delete\s+from)\s+"?public"?\s*\.\s*"?(alerts|alert_events|notifications)"?\b/i,
    )
  })

  it('does not call live escalation or notification functions', () => {
    expect(source).not.toMatch(/\b(process_escalations|notify_stage|push-dispatch)\b/i)
  })
})
