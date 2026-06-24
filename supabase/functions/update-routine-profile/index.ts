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

function getRuleBasedProfile(pattern: string): { hourly_thresholds: number[]; weekend_multiplier: number } {
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

  return { hourly_thresholds, weekend_multiplier }
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
  const results: Array<{ user_id: string; status: string; method: 'gemini' | 'rule-based'; error?: string }> = []

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

      // Query historical aggregates (last 90 days)
      let { data: aggregates, error: aggErr } = await supabase
        .from('daily_activity_aggregates')
        .select('date, hourly_density')
        .eq('user_id', uid)
        .order('date', { ascending: false })
        .limit(90)

      if (aggErr) {
        throw new Error(`Failed to query aggregates: ${aggErr.message}`)
      }

      // Self-healing: if no aggregates exist, seed them now
      if (!aggregates || aggregates.length === 0) {
        console.log(`Seeding initial routine aggregates for user ${uid}`)
        const { error: seedErr } = await supabase.rpc('initialize_user_routine_data', { _user_id: uid })
        if (seedErr) {
          console.error(`Failed to seed routine aggregates for ${uid}:`, seedErr)
        } else {
          // Re-fetch
          const { data: refetched } = await supabase
            .from('daily_activity_aggregates')
            .select('date, hourly_density')
            .eq('user_id', uid)
            .order('date', { ascending: false })
            .limit(90)
          aggregates = refetched
        }
      }

      // Check if Gemini is available and if user consented or if it's personal optimization
      // (Note: even without consent for sharing data globally, we can use AI to optimize their own thresholds locally)
      if (geminiKey && aggregates && aggregates.length > 0) {
        try {
          const historyStr = aggregates
            .map((a) => `${a.date}: [${(a.hourly_density as number[]).join(',')}]`)
            .join('\n')

          const promptText = `You are the Keep Contact Adaptive Routine Engine.
Analyze the user's daily activity aggregates and routine pattern settings to output a dynamic 24-hour timeout threshold profile (in hours) for silence detection.

Inputs:
1. Routine Pattern: "${pattern}"
2. Historical Daily Activity Density Matrix:
${historyStr}

Guidelines for generating thresholds (in hours):
- Sleep Hours: Set higher tolerance thresholds (e.g., 6.5 to 8.5 hours) during hours when the user is regularly asleep.
- Standard Active/Commute Hours: Set tighter thresholds (e.g., 1.5 to 2.5 hours) when pings are frequent and regular.
- Off-hours / Transition Hours: Set moderate thresholds (e.g., 3.0 to 4.5 hours).
- Shift / Irregular Pattern: If "shift_irregular" is chosen, or if the density matrix shows erratic hours, keep thresholds flatter and wider (e.g., 5.0 to 6.5 hours) to prevent false alerts.
- Weekend Multiplier: Typically between 1.0 and 1.5. If the user shifts their sleep/wake cycle on weekends, output a multiplier to scale thresholds.

Ensure the returned thresholds represent the maximum allowed silence (in hours) before triggering an alert. High values = low sensitivity (fewer false alerts but slower alarm), low values = high sensitivity (quick alarm but higher false alert risk). Thresholds must be double precision floats between 1.0 and 12.0.
`

          const response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`,
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
                        description: 'Multiplier for thresholds on weekends (Saturday and Sunday). Must be between 0.8 and 2.0',
                      },
                      reasoning: {
                        type: 'STRING',
                        description: 'Brief explanation of the routine analysis',
                      },
                    },
                    required: ['hourly_thresholds', 'weekend_multiplier'],
                  },
                },
              }),
            }
          )

          if (!response.ok) {
            throw new Error(`Gemini API returned status ${response.status}: ${response.statusText}`)
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

          await supabase.from('user_activity_profiles').upsert({
            user_id: uid,
            hourly_thresholds: parsed.hourly_thresholds,
            weekend_multiplier: parsed.weekend_multiplier || 1.0,
            updated_at: new Date().toISOString(),
          })

          results.push({ user_id: uid, status: 'success', method: 'gemini' })
          continue
        } catch (geminiError) {
          console.error(`Gemini analysis failed for user ${uid}, falling back to rule-based:`, geminiError)
        }
      }

      // 5. Rule-based fallback (if gemini is disabled, missing key, or failed)
      const { hourly_thresholds, weekend_multiplier } = getRuleBasedProfile(pattern)
      await supabase.from('user_activity_profiles').upsert({
        user_id: uid,
        hourly_thresholds,
        weekend_multiplier,
        updated_at: new Date().toISOString(),
      })

      results.push({ user_id: uid, status: 'success', method: 'rule-based' })
    } catch (err) {
      console.error(`Failed to process routine profile for user ${uid}:`, err)
      results.push({ user_id: uid, status: 'failed', method: 'rule-based', error: (err as Error).message })
    }
  }

  return json({ ok: true, processedCount: results.length, results })
})
