import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

const files = [
  'supabase/migrations/20260727173000_adaptive_alert_shadow_coverage_contract.sql',
  'supabase/migrations/20260727173500_align_android_coverage_client_platform.sql',
  'supabase/migrations/20260727174000_adaptive_alert_shadow_operational_schema.sql',
  'supabase/migrations/20260727175000_adaptive_alert_shadow_operational_cycle.sql',
]

describe('ADR-0028 shadow isolation', () => {
  it('keeps the complete base scheduler-off', () => {
    const source = files.map((file) => fs.readFileSync(file, 'utf8')).join('\n')
    expect(source).not.toMatch(/cron\.(schedule|alter_job|unschedule)/i)
  })

  it('contains no live alert DML target', () => {
    const source = files.map((file) => fs.readFileSync(file, 'utf8')).join('\n')
    expect(source).not.toMatch(
      /\b(insert\s+into|update|delete\s+from)\s+public\.(alerts|alert_events|notifications)\b/i,
    )
  })

  it('does not call live escalation or notification functions', () => {
    const source = files.map((file) => fs.readFileSync(file, 'utf8')).join('\n')
    expect(source).not.toMatch(
      /\b(process_escalations|notify_stage|push-dispatch)\b/i,
    )
  })
})
