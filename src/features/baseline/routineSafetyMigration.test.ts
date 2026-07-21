import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

describe('Routine Safety Migration Static SQL Contracts', () => {
  const migrationsDir = path.resolve('supabase/migrations')

  it('locates the single Gate 1 containment migration and asserts exact SQL requirements', () => {
    const files = fs.readdirSync(migrationsDir)

    // 1. Require exactly one filename containing routine_ai_gate1_containment
    const gate1MigrationFiles = files.filter(file => file.includes('routine_ai_gate1_containment'))
    expect(gate1MigrationFiles.length).toBe(1) // FAIL: No routine_ai_gate1_containment migration file exists yet

    const gate1Migration = gate1MigrationFiles[0]
    const sqlContent = fs.readFileSync(path.join(migrationsDir, gate1Migration), 'utf8')

    // 2. Assert ingest_version = 2 (not just 'v2')
    expect(sqlContent).toContain('ingest_version = 2')

    // 3. Assert received_at and event_id
    expect(sqlContent).toContain('received_at')
    expect(sqlContent).toContain('event_id')

    // 4. Assert partial unique index for idempotency
    expect(sqlContent.toLowerCase()).toContain('create unique index')
    expect(sqlContent.toLowerCase()).toContain('where event_id')

    // 5. Assert auth.uid()-derived <=100 ordered batch query
    expect(sqlContent).toContain('auth.uid()')
    expect(sqlContent.toLowerCase()).toContain('limit 100')
    expect(sqlContent.toLowerCase()).toContain('order by')

    // 6. Assert SQL-specific RPC names
    expect(sqlContent).toContain('record_behavior_ping')
    expect(sqlContent).toContain('record_behavior_pings')

    // 7. Assert revoke direct insert on behavior_pings from authenticated
    expect(sqlContent).toContain('REVOKE INSERT ON TABLE public.behavior_pings FROM authenticated')

    // 8. Assert revoke execute on initializer function
    expect(sqlContent).toContain('REVOKE EXECUTE ON FUNCTION')
    expect(sqlContent).toContain('FROM PUBLIC, anon, authenticated')

    // 9. Assert trigger handler changes / drop trigger
    expect(sqlContent.toLowerCase()).toContain('drop trigger')
    expect(sqlContent).toContain('on_profile_pattern_change')

    // 10. Assert process_checkin_tasks uses v2 received_at
    expect(sqlContent).toContain('received_at')
    expect(sqlContent).toContain('process_checkin_tasks')

    // 11. Assert alert created_at and received/observed drift checks in private handlers
    expect(sqlContent.toLowerCase()).toContain('created_at')
    expect(sqlContent.toLowerCase()).toContain('drift')

    // 12. Extract cron.schedule arguments and verify command is plain Select and lacks $cron$
    // Ensure that select public.run_daily_aggregations(); is in the command but no dollar quoting is nested.
    const cronScheduleIndex = sqlContent.indexOf('cron.schedule')
    expect(cronScheduleIndex).toBeGreaterThan(-1)

    // Locate the command block inside cron.schedule
    const afterCronSchedule = sqlContent.substring(cronScheduleIndex)
    const containsPlainDailyAggregations = afterCronSchedule.includes('select public.run_daily_aggregations();')
    const embedsLiteralCronDollar = afterCronSchedule.includes('$cron$')

    expect(containsPlainDailyAggregations).toBe(true)
    expect(embedsLiteralCronDollar).toBe(false)

    // 13. Regression: Safe ingest default (SET DEFAULT 1, not DEFAULT 2)
    expect(sqlContent).toContain('ingest_version SET DEFAULT 1')
    expect(sqlContent).not.toContain('ingest_version SET DEFAULT 2')

    // 14. Regression: Weekly cron unscheduled
    expect(sqlContent).toContain('update-routine-profiles-weekly')
    expect(sqlContent).toContain('cron.unschedule')

    // 15. Regression: my_routine_status preserved keys
    expect(sqlContent).toContain("'sleep_start'")
    expect(sqlContent).toContain("'sleep_end'")
    expect(sqlContent).toContain("'timezone'")
    expect(sqlContent).toContain("'in_sleep_window'")
    expect(sqlContent).toContain("'model_confidence'")
    expect(sqlContent).toContain("'model_explanation'")
    expect(sqlContent).toContain("'model_version'")

    // 16. Regression: Duplicate lookup scoped by user (prevent leaks)
    expect(sqlContent).toContain('user_id = _user_id AND event_id = _event_id')

    // 17. Regression: Actual sensitivity enum fallback strings ('sensitive', 'balanced', 'relaxed')
    expect(sqlContent).toContain("'sensitive'")
    expect(sqlContent).toContain("'balanced'")
    expect(sqlContent).toContain("'relaxed'")

    // 18. Regression: batch input errors are narrow; real DB failures propagate
    expect(sqlContent).not.toContain('EXCEPTION WHEN OTHERS')
    expect(sqlContent).toContain('invalid_text_representation')
    expect(sqlContent).toContain('invalid_datetime_format')

    // 19. Regression: concurrent retry/coalescing paths are serialized
    expect(sqlContent).toContain('pg_advisory_xact_lock')
    expect(sqlContent).toContain("':event:'")
    expect(sqlContent).toContain("':bucket:'")

    // 20. Regression: the explicit legacy group RPC fallback also uses v2 evidence
    expect(sqlContent).toContain('FUNCTION public.get_group_activity(_group uuid)')
    expect(sqlContent).toContain('REVOKE EXECUTE ON FUNCTION public.get_group_activity(uuid) FROM PUBLIC, anon')

    // 21. Regression: maintenance SECURITY DEFINER entry points are not user callable
    expect(sqlContent).toContain('REVOKE EXECUTE ON FUNCTION private.aggregate_user_daily_activity(uuid, date) FROM PUBLIC, anon, authenticated')
    expect(sqlContent).toContain('REVOKE EXECUTE ON FUNCTION public.run_daily_aggregations() FROM PUBLIC, anon, authenticated')
    expect(sqlContent).toContain('REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid) FROM PUBLIC, anon, authenticated')
  })
})
