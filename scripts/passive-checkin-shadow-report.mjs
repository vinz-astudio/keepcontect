import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

export const SHADOW_GATE = Object.freeze({
  minimumDays: 14,
  minimumSubjectsPerCohort: 20,
  maximumMedianInterruptionsPerUserDay: 0.2,
  maximumP90InterruptionsPerUserDay: 1,
})

function number(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

export function evaluatePassiveShadowReport(report) {
  const failures = []
  if (!report || report.schema_version !== 'passive-shadow-report-v1') {
    return { passed: false, failures: ['unsupported or missing report schema'] }
  }
  const days = number(report.duration_days)
  if (days === null || days < SHADOW_GATE.minimumDays) {
    failures.push(`shadow duration ${days ?? 'invalid'}d is below ${SHADOW_GATE.minimumDays}d`)
  }
  if (!Array.isArray(report.cohorts) || report.cohorts.length === 0) {
    failures.push('no qualifying platform cohort was reported')
  } else {
    for (const cohort of report.cohorts) {
      const label = `${cohort.platform_mix ?? 'unknown'}/${cohort.client_contract_version ?? 'unknown'}`
      if (!Number.isInteger(cohort.subjects) || cohort.subjects < SHADOW_GATE.minimumSubjectsPerCohort) {
        failures.push(`${label}: ${cohort.subjects ?? 'invalid'} subjects is below ${SHADOW_GATE.minimumSubjectsPerCohort}`)
      }
      const median = number(cohort.median_interruptions_per_user_day)
      if (median === null || median > SHADOW_GATE.maximumMedianInterruptionsPerUserDay) {
        failures.push(`${label}: median interruptions ${median ?? 'invalid'} exceeds ${SHADOW_GATE.maximumMedianInterruptionsPerUserDay}/day`)
      }
      const p90 = number(cohort.p90_interruptions_per_user_day)
      if (p90 === null || p90 > SHADOW_GATE.maximumP90InterruptionsPerUserDay) {
        failures.push(`${label}: p90 interruptions ${p90 ?? 'invalid'} exceeds ${SHADOW_GATE.maximumP90InterruptionsPerUserDay}/day`)
      }
    }
  }
  if (!report.hard_invariants || typeof report.hard_invariants !== 'object') {
    failures.push('hard-invariant counters are missing')
  } else {
    for (const [name, count] of Object.entries(report.hard_invariants)) {
      if (!Number.isInteger(count) || count !== 0) failures.push(`hard invariant ${name} has ${count ?? 'invalid'} violation(s)`)
    }
  }
  if (report.global_kill_switch?.active === true) failures.push('global passive kill switch is active')
  return { passed: failures.length === 0, failures }
}

function runCli() {
  const input = process.argv[2]
  if (!input) {
    console.error('Usage: npm run passive:shadow:report -- <aggregate-report.json>')
    process.exitCode = 2
    return
  }
  let report
  try {
    report = JSON.parse(readFileSync(input, 'utf8'))
  } catch (error) {
    console.error(`Could not read report: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 2
    return
  }
  const result = evaluatePassiveShadowReport(report)
  if (result.passed) {
    console.log('PASS: passive check-in shadow rollout gate')
  } else {
    console.error('FAIL: passive check-in shadow rollout gate')
    for (const failure of result.failures) console.error(`- ${failure}`)
    process.exitCode = 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) runCli()
