// DEPLOY NOTE: deploy this function with verify_jwt=false. It authenticates via the
// cron_secret (Authorization: Bearer <cron_secret>), NOT a Supabase JWT. With verify_jwt=true
// the gateway 401s the weekly cron (trigger_weekly_routine_updates) before this code runs.
import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })

type GapStats = {
  samples: number
  p50: number
  p75: number
  p90: number
  p95: number
}

const clamp = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, value))

function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const idx = Math.min(sorted.length - 1, Math.floor(p * sorted.length))
  return sorted[idx]
}

function getLocalHour(iso: string, timeZone: string): number {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hour: 'numeric',
      hour12: false,
    }).formatToParts(new Date(iso))
    const hour = Number(parts.find((part) => part.type === 'hour')?.value)
    return Number.isFinite(hour) ? hour % 24 : new Date(iso).getUTCHours()
  } catch {
    return new Date(iso).getUTCHours()
  }
}

function summarizeGapStats(pings: Array<{ at: string }>, timeZone: string): Array<GapStats | null> {
  const buckets = Array.from({ length: 24 }, () => [] as number[])
  for (let i = 1; i < pings.length; i++) {
    const prev = new Date(pings[i - 1].at).getTime()
    const curr = new Date(pings[i].at).getTime()
    const gapHours = (curr - prev) / 3_600_000
    if (!Number.isFinite(gapHours) || gapHours <= 0 || gapHours > 12) continue
    buckets[getLocalHour(pings[i - 1].at, timeZone)].push(gapHours)
  }

  return buckets.map((bucket) => {
    if (bucket.length === 0) return null
    return {
      samples: bucket.length,
      p50: percentile(bucket, 0.5),
      p75: percentile(bucket, 0.75),
      p90: percentile(bucket, 0.9),
      p95: percentile(bucket, 0.95),
    }
  })
}

function confidenceFromSamples(samples: number): number {
  return clamp(samples / 30, 0.05, 1)
}

function hourlyConfidence(gapStats: Array<GapStats | null>): number[] {
  return gapStats.map((stats) => stats ? confidenceFromSamples(stats.samples) : 0)
}

function modelConfidence(gapStats: Array<GapStats | null>): number {
  const total = gapStats.reduce((sum, stats) => sum + (stats?.samples ?? 0), 0)
  return clamp(total / 1000, 0, 1)
}

function gapStatsJson(gapStats: Array<GapStats | null>) {
  return gapStats.map((stats, hour) => stats ? { hour, ...stats } : { hour, samples: 0 })
}

// Confidence-weighted blend between the cold-start template and the user's own
// gap distribution. With no data we keep the template; as real intervals
// accumulate per hour (confidence -> 1 around ~30 samples) the threshold leans
// fully personal — so it can move *up or down* to match the user's true rhythm,
// not only tighten. This is the cold-start "gradually import personal intervals"
// behavior: a quiet person whose real gaps exceed the template is no longer
// clamped down into constant false alarms.
function tightenThresholdsWithGapStats(
  thresholds: number[],
  gapStats: Array<GapStats | null>,
): number[] {
  return thresholds.map((raw, hour) => {
    const template = clamp(Number(raw) || 6, 1, 12)
    const stats = gapStats[hour]
    if (!stats || stats.samples < 1) return template

    // Personal "usual ceiling": a margin above the 90th-percentile real gap.
    const personal = clamp(Math.max(1.5, stats.p90 * 1.8), 1, 12)
    // Weight grows with per-hour sample count (shrinkage toward the prior).
    const w = clamp(stats.samples / 30, 0, 1)
    return clamp(w * personal + (1 - w) * template, 1, 12)
  })
}

function getRuleBasedProfile(
  pattern: string,
  gapStats: Array<GapStats | null>,
): { hourly_thresholds: number[]; weekend_multiplier: number } {
  const hourly_thresholds = new Array<number>(24)
  let weekend_multiplier = 1.0

  if (pattern === 'regular_9to5') {
    weekend_multiplier = 1.2
    for (let h = 0; h < 24; h++) {
      if (h >= 7 && h < 23) {
        hourly_thresholds[h] = 2.5
      } else {
        hourly_thresholds[h] = 7.0
      }
    }
  } else if (pattern === 'semester_break') {
    weekend_multiplier = 1.15
    for (let h = 0; h < 24; h++) {
      if (h >= 8 && h < 23) {
        hourly_thresholds[h] = 3.5
      } else {
        hourly_thresholds[h] = 8.0
      }
    }
  } else {
    // shift_irregular / default
    weekend_multiplier = 1.0
    for (let h = 0; h < 24; h++) {
      hourly_thresholds[h] = 6.0
    }
  }

  return {
    hourly_thresholds: tightenThresholdsWithGapStats(hourly_thresholds, gapStats),
    weekend_multiplier,
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  // 1. Authenticate with cron_secret
  const authHeader = req.headers.get('Authorization')
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return json({ ok: false, error: 'Missing authorization header' }, 401)
  }

  const { data: configRows, error: configErr } = await supabase.rpc('get_app_config')
  if (configErr || !configRows) {
    console.error('Database app_config query failed:', configErr)
    return json({ ok: false, error: 'Database config error' }, 500)
  }

  const cronSecret = (configRows as Record<string, string>).cron_secret
  const receivedToken = authHeader.substring(7)
  if (!cronSecret || receivedToken !== cronSecret) {
    return json({ ok: false, error: 'Unauthorized' }, 401)
  }

  // 2. Parse request body
  let targetUserId: string | null = null
  try {
    const body = await req.json()
    if (body && typeof body.user_id === 'string') {
      targetUserId = body.user_id
    }
  } catch {
    // Empty body is fine (triggers updates for all users)
  }

  // 3. Determine users to process
  let usersToProcess: string[] = []
  if (targetUserId) {
    usersToProcess = [targetUserId]
  } else {
    const { data: users, error: usersErr } = await supabase
      .from('profiles')
      .select('id')
    if (usersErr) {
      console.error('Failed to query users:', usersErr)
      return json({ ok: false, error: 'Failed to query users' }, 500)
    }
    usersToProcess = (users || []).map((u) => u.id)
  }

  const geminiKey = Deno.env.get('GEMINI_API_KEY')
  const results: Array<{
    user_id: string
    status: string
    method: 'gemini' | 'rule-based'
    model?: string
    error?: string
  }> = []

  let hasFailures = false

  // 4. Process each user
  for (const uid of usersToProcess) {
    try {
      const { data: profile, error: profErr } = await supabase
        .from('profiles')
        .select('routine_pattern, consent_data_sharing')
        .eq('id', uid)
        .single()
      if (profErr || !profile) {
        throw new Error(`Profile not found: ${profErr?.message}`)
      }

      const pattern = profile.routine_pattern || 'regular_9to5'
      const { data: settings, error: settingsErr } = await supabase
        .from('user_settings')
        .select('timezone, sensitivity, sleep_start_utc, sleep_end_utc')
        .eq('user_id', uid)
        .maybeSingle()
      if (settingsErr) {
        throw new Error(`Settings error: ${settingsErr.message}`)
      }
      const timezone = settings?.timezone || 'UTC'
      const sensitivity = settings?.sensitivity || 'balanced'

      // Query historical aggregates (last 90 days)
      const { data: aggregates, error: aggErr } = await supabase
        .from('daily_activity_aggregates')
        .select('date, hourly_density')
        .eq('user_id', uid)
        .order('date', { ascending: false })
        .limit(90)

      if (aggErr) {
        throw new Error(`Failed to query aggregates: ${aggErr.message}`)
      }

      const since = new Date(Date.now() - 90 * 24 * 3_600_000).toISOString()
      const { data: pings, error: pingsErr } = await supabase
        .from('behavior_pings')
        .select('at')
        .eq('user_id', uid)
        .gte('at', since)
        .order('at', { ascending: true })
        .limit(10000)
      if (pingsErr) {
        throw new Error(`Failed to query behavior pings: ${pingsErr.message}`)
      }
      const gapStats = summarizeGapStats(pings || [], timezone)

      let fallbackReason = 'Gemini Key is missing in Deno env'
      if (profile?.consent_data_sharing !== true) {
        fallbackReason = 'User has not consented to data sharing'
      }

      let success = false

      // Check if Gemini is available and if user consented
      if (profile?.consent_data_sharing === true && geminiKey && aggregates && aggregates.length > 0) {
        const modelsToTry = [
          'gemini-3.1-flash-lite',
          'gemini-3.5-flash',
          'gemini-3-flash-preview',
          'gemini-2.5-flash-lite',
          'gemini-2.5-flash',
        ]
        let lastErrorMsg = ''

        const historyStr = aggregates
          .map((a) => `${a.date}: [${(a.hourly_density as number[]).join(',')}]`)
          .join('\n')
        const gapStatsStr = gapStats
          .map((stats, hour) =>
            stats
              ? `${hour}: samples=${stats.samples}, p50=${stats.p50.toFixed(2)}h, p75=${stats.p75.toFixed(2)}h, p90=${stats.p90.toFixed(2)}h, p95=${stats.p95.toFixed(2)}h`
              : `${hour}: no recent sub-12h gap samples`,
          )
          .join('\n')
        const modelConfidenceValue = modelConfidence(gapStats)
        const hourlyConfidenceValue = hourlyConfidence(gapStats)

        const promptText = `You are the Keep Contact Adaptive Routine Engine.
Analyze the user's activity aggregates, real behavior gap percentiles, and routine settings to output a neutral usual behavior model for silence detection.

Inputs:
1. Routine Pattern: "${pattern}"
2. User Timezone: "${timezone}"
3. User Sensitivity Setting: "${sensitivity}" (do not bake this into the model; sensitivity is only a user-facing adjustment tool)
4. Sleep Window: "${settings?.sleep_start_utc || 'not set'}" to "${settings?.sleep_end_utc || 'not set'}" local time
5. Historical Daily Activity Density Matrix:
${historyStr}
6. Real Behavior Gap Percentiles by prior local hour (only gaps <= 12h, in hours):
${gapStatsStr}

Guidelines for generating thresholds (in hours):
- Sleep Hours: Set higher tolerance thresholds (e.g., 6.5 to 8.5 hours) during hours when the user is regularly asleep.
- Standard Active/Commute Hours: Set tighter thresholds (e.g., 1.5 to 2.5 hours) when pings are frequent and regular. If an hour has enough gap samples and p90 is near 1 hour, do not output 3.5+ hours for that hour.
- Off-hours / Transition Hours: Set moderate thresholds (e.g., 3.0 to 4.5 hours).
- Shift / Irregular Pattern: If "shift_irregular" is chosen, or if the density matrix shows erratic hours, keep thresholds flatter and wider (e.g., 5.0 to 6.5 hours) to prevent false alerts.
- Weekend Multiplier: Typically between 1.0 and 1.5. If the user shifts their sleep/wake cycle on weekends, output a multiplier to scale thresholds.
- Sensitivity: Do not bake sensitivity into the profile. The server applies it later.
- Confidence: Consider sample counts, stable active windows, and recent gap distributions. Low sample hours should have lower confidence.

Ensure the returned thresholds represent the neutral usual silence baseline (in hours) before sensitivity adjustment. Thresholds must be double precision floats between 1.0 and 12.0.
`

        for (const modelName of modelsToTry) {
          try {
            console.log(`Attempting Gemini analysis using model ${modelName}...`)
            if (profile.consent_data_sharing !== true) {
              throw new Error('Consent required for Gemini request')
            }
            let response;
            try {
              response = await fetch(
                `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${geminiKey}`,
                {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    contents: [{ parts: [{ text: promptText }] }],
                    generationConfig: {
                      responseMimeType: 'application/json',
                      responseSchema: {
                        type: 'OBJECT',
                        properties: {
                          hourly_thresholds: {
                            type: 'ARRAY',
                            description: '24 double precision floats representing custom hourly thresholds (in hours) starting from hour 0 to hour 23',
                            items: { type: 'NUMBER' },
                          },
                          weekend_multiplier: {
                            type: 'NUMBER',
                            description: 'Multiplier for thresholds on weekends. Must be between 0.8 and 2.0',
                          },
                          reasoning: {
                            type: 'STRING',
                            description: 'Brief explanation of the routine analysis',
                          },
                          model_confidence: {
                            type: 'NUMBER',
                            description: 'Overall confidence from 0.0 to 1.0',
                          },
                          hourly_confidence: {
                            type: 'ARRAY',
                            description: '24 confidence values from 0.0 to 1.0 starting from hour 0 to hour 23',
                            items: { type: 'NUMBER' },
                          },
                          model_explanation: {
                            type: 'STRING',
                            description: 'User-readable explanation of the usual behavior model and confidence',
                          },
                        },
                        required: ['hourly_thresholds', 'weekend_multiplier'],
                      },
                    },
                  }),
                }
              )
            } catch (fetchErr) {
              throw new Error(`Network failure during Gemini API call: ${(fetchErr as Error).message}`)
            }

            if (!response.ok) {
              throw new Error(`Gemini API returned status ${response.status} (${response.statusText}).`)
            }

            const geminiData = await response.json()
            const text = geminiData.candidates?.[0]?.content?.parts?.[0]?.text
            if (!text) {
              throw new Error('Empty text content in Gemini response')
            }

            const parsed = JSON.parse(text)
            if (!Array.isArray(parsed.hourly_thresholds) || parsed.hourly_thresholds.length !== 24) {
              throw new Error('Invalid hourly thresholds array size returned by Gemini')
            }
            const hourly_thresholds = tightenThresholdsWithGapStats(
              parsed.hourly_thresholds,
              gapStats,
            )
            const weekend_multiplier = clamp(Number(parsed.weekend_multiplier) || 1.0, 0.8, 2.0)
            const parsedHourlyConfidence = Array.isArray(parsed.hourly_confidence) && parsed.hourly_confidence.length === 24
              ? parsed.hourly_confidence.map((value: unknown, hour: number) =>
                clamp(Number(value) || hourlyConfidenceValue[hour] || 0, 0, 1))
              : hourlyConfidenceValue
            const parsedModelConfidence = clamp(
              Number(parsed.model_confidence) || modelConfidenceValue,
              0,
              1,
            )
            const modelExplanation =
              typeof parsed.model_explanation === 'string' && parsed.model_explanation.trim()
                ? parsed.model_explanation.trim()
                : typeof parsed.reasoning === 'string' && parsed.reasoning.trim()
                  ? parsed.reasoning.trim()
                  : `Usual behavior model from ${pings?.length ?? 0} recent pings; confidence ${parsedModelConfidence.toFixed(2)}.`

            const { error: upsertErr } = await supabase.from('user_activity_profiles').upsert({
              user_id: uid,
              hourly_thresholds,
              weekend_multiplier,
              model_version: 'usual_behavior_v1',
              model_confidence: parsedModelConfidence,
              hourly_confidence: parsedHourlyConfidence,
              gap_stats: gapStatsJson(gapStats),
              model_explanation: modelExplanation,
              updated_at: new Date().toISOString(),
            })

            if (upsertErr) {
              throw new Error(`Upsert error: ${upsertErr.message}`)
            }

            console.log(`Successfully updated routine profile using model ${modelName}...`)
            results.push({ user_id: uid, status: 'success', method: 'gemini', model: modelName })
            success = true
            break
          } catch (modelErr) {
            console.warn(`Gemini analysis failed using model ${modelName}:`, modelErr)
            lastErrorMsg += ` [${modelName}: ${(modelErr as Error).message}]`
          }
        }

        if (success) {
          continue
        } else {
          fallbackReason = `All Gemini models failed. Last error: ${lastErrorMsg}`
        }
      }

      // 5. Rule-based fallback
      const { hourly_thresholds, weekend_multiplier } = getRuleBasedProfile(pattern, gapStats)
      const fallbackModelConfidence = modelConfidence(gapStats)
      const { error: upsertErr } = await supabase.from('user_activity_profiles').upsert({
        user_id: uid,
        hourly_thresholds,
        weekend_multiplier,
        model_version: 'usual_behavior_v1_rule_based',
        model_confidence: fallbackModelConfidence,
        hourly_confidence: hourlyConfidence(gapStats),
        gap_stats: gapStatsJson(gapStats),
        model_explanation: `Rule-based usual behavior model from ${(pings || []).length} recent pings; confidence ${fallbackModelConfidence.toFixed(2)}. Gemini fallback reason: ${fallbackReason}`,
        updated_at: new Date().toISOString(),
      })

      if (upsertErr) {
        throw new Error(`Upsert error: ${upsertErr.message}`)
      }

      results.push({ user_id: uid, status: 'success', method: 'rule-based', error: fallbackReason })
    } catch (err) {
      console.error(`Failed to process routine profile:`, err)
      results.push({ user_id: uid, status: 'failed', method: 'rule-based', error: (err as Error).message })
    }
  }

  const anyFailed = results.some((r) => r.status === 'failed')
  const statusCode = anyFailed ? 500 : 200
  return json({ ok: !anyFailed, processedCount: results.length, results }, statusCode)
})
