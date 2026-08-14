import { describe, expect, it } from 'vitest'
import { evaluatePassiveShadowReport } from './passive-checkin-shadow-report.mjs'

const passing = {
  schema_version: 'passive-shadow-report-v1', duration_days: 14,
  cohorts: [{ platform_mix: 'android_native', client_contract_version: 'passive-checkin-v1',
    subjects: 20, median_interruptions_per_user_day: 0.2, p90_interruptions_per_user_day: 1 }],
  hard_invariants: { late_absence_miss: 0, passive_resolution: 0, guardian_as_subject_evidence: 0,
    cross_account_acceptance: 0, dual_engine_alert: 0, prohibited_raw_fields: 0 },
  global_kill_switch: { active: false },
}

describe('passive shadow rollout report', () => {
  it('passes only at every inclusive threshold', () => {
    expect(evaluatePassiveShadowReport(passing)).toEqual({ passed: true, failures: [] })
  })

  it.each([
    [{ duration_days: 13.99 }, 'shadow duration'],
    [{ cohorts: [{ ...passing.cohorts[0], subjects: 19 }] }, 'subjects is below'],
    [{ cohorts: [{ ...passing.cohorts[0], median_interruptions_per_user_day: 0.201 }] }, 'median interruptions'],
    [{ cohorts: [{ ...passing.cohorts[0], p90_interruptions_per_user_day: 1.01 }] }, 'p90 interruptions'],
    [{ hard_invariants: { ...passing.hard_invariants, cross_account_acceptance: 1 } }, 'hard invariant cross_account_acceptance'],
    [{ hard_invariants: { ...passing.hard_invariants, dual_engine_alert: 1 } }, 'hard invariant dual_engine_alert'],
    [{ global_kill_switch: { active: true } }, 'kill switch is active'],
  ])('fails a rollout threshold with an actionable reason', (change, message) => {
    const result = evaluatePassiveShadowReport({ ...passing, ...change })
    expect(result.passed).toBe(false)
    expect(result.failures.join('\n')).toContain(message)
  })

  it('fails closed on missing cohorts or invariant counters', () => {
    expect(evaluatePassiveShadowReport({ ...passing, cohorts: [] }).failures).toContain('no qualifying platform cohort was reported')
    expect(evaluatePassiveShadowReport({ ...passing, hard_invariants: null }).failures).toContain('hard-invariant counters are missing')
  })
})
