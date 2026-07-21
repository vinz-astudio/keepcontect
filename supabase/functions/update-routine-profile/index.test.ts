import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

describe('Update Routine Profile Edge Function Source Code Contract', () => {
  const funcPath = path.resolve('supabase/functions/update-routine-profile/index.ts')

  it('asserts that the edge function gates Gemini API calls strictly on user consent (consent_data_sharing) within the conditional logic block', () => {
    const source = fs.readFileSync(funcPath, 'utf8')

    // Find the loop or check immediately preceding Deno fetch / modelsToTry check
    const geminiFetchIndex = source.indexOf('generativelanguage.googleapis.com')
    expect(geminiFetchIndex).toBeGreaterThan(-1)

    // Locate the surrounding check that gates this: e.g. the if block
    // It must check profile.consent_data_sharing in the condition immediately guarding the fetch block
    const fetchBlockPreContext = source.substring(geminiFetchIndex - 1200, geminiFetchIndex)

    // Assert that the if statement in this context checks consent_data_sharing
    const checksConsentInIfCondition = /if\s*\(.*consent_data_sharing.*\)/.test(fetchBlockPreContext)
    expect(checksConsentInIfCondition).toBe(true) // FAIL: Deno fetch is not guarded immediately by consent_data_sharing
  })

  it('asserts that database-level initialization seed call (initialize_user_routine_data) is removed to avoid random reset', () => {
    const source = fs.readFileSync(funcPath, 'utf8')

    // Contract: Self-healing or automatic initializers that trigger random seed resets must be removed.
    const containsSeedCall = source.includes('initialize_user_routine_data')
    expect(containsSeedCall).toBe(false) // FAIL: contains random-seeding seed call in Deno function
  })

  it('asserts that the Gemini API key prefix is never written to logs or substrings', () => {
    const source = fs.readFileSync(funcPath, 'utf8')

    // Contract: Security check. Logging key prefix combinations (substring/slice/log) is forbidden.
    const logsKeyPrefix = /geminiKey.*?(\.substring|\.slice|\.substr)/.test(source)
    expect(logsKeyPrefix).toBe(false) // FAIL: logs key prefix on fallback failure
  })

  it('asserts that settings, profile, aggregates, and upsert queries destructure error objects and check them, yielding a non-2xx status on aggregate failure', () => {
    const source = fs.readFileSync(funcPath, 'utf8')

    // 1. Destructuring check for profiles query
    const destructuresProfileErr = /\{\s*data:\s*profile\s*,\s*error:\s*profErr\s*\}/.test(source) ||
                                   /\{\s*error:\s*profErr\s*,\s*data:\s*profile\s*\}/.test(source)
    expect(destructuresProfileErr).toBe(true)

    // 2. Destructuring check for user_settings query
    const destructuresSettingsErr = /\{\s*data:\s*settings\s*,\s*error:\s*settingsErr\s*\}/.test(source) ||
                                    /\{\s*error:\s*settingsErr\s*,\s*data:\s*settings\s*\}/.test(source)
    expect(destructuresSettingsErr).toBe(true) // FAIL: user_settings error is not destructured

    // 3. Destructuring check for daily_activity_aggregates query
    const destructuresAggregatesErr = /\{\s*data:\s*aggregates\s*,\s*error:\s*aggErr\s*\}/.test(source) ||
                                      /\{\s*error:\s*aggErr\s*,\s*data:\s*aggregates\s*\}/.test(source)
    expect(destructuresAggregatesErr).toBe(true)

    // 4. Destructuring check for user_activity_profiles upsert query
    const destructuresUpsertErr = /from\(\s*['"]user_activity_profiles['"]\s*\)\s*\.\s*upsert\([\s\S]*?error:\s*upsertErr/.test(source)
    expect(destructuresUpsertErr).toBe(true) // FAIL: upsert error is not destructured

    // 5. Named errors must be explicitly checked in if statements
    expect(source.includes('if (profErr')).toBe(true)
    expect(source.includes('if (settingsErr')).toBe(true) // FAIL: settingsErr is not checked
    expect(source.includes('if (aggErr')).toBe(true)
    expect(source.includes('if (upsertErr')).toBe(true) // FAIL: upsertErr is not checked

    // 6. If any individual or batch user profile update fails, the overall response status must reflect the aggregate failure (non-2xx)
    // currently the endpoint processes all users and returns 200 even if some users failed to process.
    const returnsNon2xxOnFailureFlag = source.includes('results.some') && (source.includes('500') || source.includes('400'))
    expect(returnsNon2xxOnFailureFlag).toBe(true) // FAIL: aggregate failures do not return non-2xx status
  })
})
