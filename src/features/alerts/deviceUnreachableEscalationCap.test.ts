import { readFileSync, readdirSync } from 'node:fs'
import { PGlite } from '@electric-sql/pglite'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'

// Plan A (human decision 2026-11-02; ADR-0039 rev.1, ADR-0040 rev.1): an alert whose
// causal silence was classified `device_unreachable` is an equipment fact, not a missing
// person. It may climb to group and community, but never to terminal, so it can never
// unlock the subject's address and emergency contacts.
//
// This runs whatever `public.process_escalations()` the migrations leave as the newest
// definition, so it checks the function production will actually run.

const migrationsDir = new URL('../../../supabase/migrations/', import.meta.url)
const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8')

function newestProcessEscalations() {
  const files = readdirSync(migrationsDir).filter(name => name.endsWith('.sql')).sort()
  for (let i = files.length - 1; i >= 0; i--) {
    const sql = readFileSync(new URL(files[i], migrationsDir), 'utf8')
    const start = sql.indexOf('CREATE OR REPLACE FUNCTION public.process_escalations()')
    if (start >= 0) return { file: files[i], sql: sql.slice(start, sql.indexOf('$$;', start) + 3) }
  }
  throw new Error('no migration defines public.process_escalations()')
}

function emergencyInfoSelectPolicy() {
  const sql = read('supabase/migrations/20260808160000_baseline_from_production.sql')
  const start = sql.indexOf('CREATE POLICY "emergency_info_select"')
  const policy = sql.slice(start, sql.indexOf(';\n', start) + 1)
  // Guard against extracting the wrong text: the gate under test must be the terminal stage.
  expect(policy).toContain("'terminal'")
  return policy
}

const subject = 'd0000000-0000-4000-8000-000000000001'
const guardian = 'd0000000-0000-4000-8000-000000000002'
const alertId = 'e0000000-0000-4000-8000-000000000001'
let db: PGlite

async function openAlert(stage: string, missKinds: (string | null)[] | null, cause = 'silence') {
  await db.query(
    `insert into alerts(id,user_id,cause,stage,opened_at,next_deadline)
     values($1,$2,$3,$4,now()-interval '3 hours',now()-interval '1 minute')`,
    [alertId, subject, cause, stage])
  // Causal windows are written once, when the alert opens, in ordinal order.
  for (const [ordinal, kind] of (missKinds ?? []).entries()) {
    const window = await db.query<{ id: string }>(
      `insert into passive_checkin_windows(user_id,ordinal,outcome,miss_kind)
       values($1,$2,'missed',$3) returning id`, [subject, ordinal, kind])
    await db.query('insert into private.passive_alert_causal_windows(alert_id,window_id,ordinal) values($1,$2,$3)',
      [alertId, window.rows[0].id, ordinal])
  }
}
async function dueNow() {
  await db.query("update alerts set next_deadline=now()-interval '1 minute' where id=$1 and next_deadline is not null", [alertId])
}
async function run() {
  await db.exec('select public.process_escalations()')
  // The engine swallows per-alert errors into job_failures; a swallowed error must not pass for "did not escalate".
  expect((await db.query('select * from private.job_failures')).rows).toEqual([])
}
async function alertRow() {
  return (await db.query<{ status: string; stage: string; next_deadline: Date | null }>(
    'select status,stage,next_deadline from alerts where id=$1', [alertId])).rows[0]
}
async function sentKinds() {
  const rows = (await db.query<{ kind: string }>('select kind from notifications where alert_id=$1', [alertId])).rows
  return rows.map(row => row.kind).sort()
}
async function escalatedNotes() {
  const rows = (await db.query<{ note: string }>("select note from alert_events where alert_id=$1 and kind='escalated'", [alertId])).rows
  return rows.map(row => row.note).sort()
}
async function guardianCanReadEmergencyInfo() {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [guardian])
  await db.exec('set role authenticated')
  try {
    return (await db.query('select home_address from emergency_info where user_id=$1', [subject])).rows.length === 1
  } finally {
    await db.exec('reset role')
  }
}

describe('device_unreachable alerts are capped below terminal', () => {
  beforeAll(async () => {
    db = new PGlite()
    await db.exec(read('supabase/tests/fixtures/activity_resolution.sql'))
    await db.exec(`
      alter table public.passive_checkin_windows add column miss_kind text;
      -- Out of scope here (covered by activityResolutionDb.test.ts): activity recovery and pattern policy.
      create function private.resolve_activity_alerts(uuid) returns void language sql as $$ select $$;
      create function private.guardian_requires_pattern(uuid) returns boolean language sql as $$ select false $$;
      create table public.emergency_info(user_id uuid primary key, home_address text, medical_notes text,
        emergency_contact_name text, emergency_contact_phone text);
      alter table public.emergency_info enable row level security;
      create function private.is_guardian_of(_ward uuid, _guardian uuid) returns boolean
        language sql stable security definer set search_path to '' as $$
        select exists (select 1 from public.guardianships g
          where g.ward_id=_ward and g.guardian_id=_guardian and g.status='active') $$;
      create function private.watches_user(_watcher uuid, _target uuid) returns boolean language sql as $$ select false $$;
      create function private.shares_community(_a uuid, _b uuid) returns boolean language sql as $$ select false $$;
      grant usage on schema public, private, auth to authenticated;
      grant select on public.alerts, public.guardianships, public.emergency_info to authenticated;
    `)
    await db.exec(emergencyInfoSelectPolicy())
    await db.exec(newestProcessEscalations().sql)
  }, 30000)
  afterAll(async () => { await db?.close() })
  beforeEach(async () => {
    await db.exec(`truncate alerts,alert_events,notifications,guardianships,profiles,emergency_info,
      passive_checkin_windows,private.passive_alert_causal_windows,private.job_failures cascade;
      insert into profiles values('${subject}','Subject'),('${guardian}','Guardian');
      insert into guardianships(guardian_id,ward_id) values('${guardian}','${subject}');
      insert into emergency_info values('${subject}','1 Home Street','allergy','Emergency Contact','+10000000000');`)
  })

  it('stops a device_unreachable alert at community: still open, clock stopped, no terminal notice', async () => {
    await openAlert('community', ['device_unreachable'])
    await run()
    const row = await alertRow()
    expect(row.status).toBe('open')
    expect(row.stage).toBe('community')
    expect(row.next_deadline).toBeNull()
    expect(await sentKinds()).toEqual([])
    expect(await escalatedNotes()).toEqual([])
  })

  it('is stable: running the engine again changes and sends nothing', async () => {
    await openAlert('community', ['device_unreachable'])
    await run()
    await run()
    await run()
    expect((await alertRow()).stage).toBe('community')
    expect(await sentKinds()).toEqual([])
    expect((await db.query('select * from alert_events where alert_id=$1', [alertId])).rows).toEqual([])
  })

  it('still climbs self -> group -> community, notifying each stage once, then stops', async () => {
    await openAlert('self', ['device_unreachable'])
    await run()
    expect((await alertRow()).stage).toBe('group')
    await dueNow(); await run()
    expect((await alertRow()).stage).toBe('community')
    await dueNow(); await run()
    const row = await alertRow()
    expect(row.stage).toBe('community')
    expect(row.next_deadline).toBeNull()
    expect(await sentKinds()).toEqual(['community', 'group'])
    expect(await escalatedNotes()).toEqual(['community', 'group'])
  })

  it('never lets the guardian read address and emergency contacts for a capped alert', async () => {
    await openAlert('community', ['device_unreachable'])
    await run()
    expect(await guardianCanReadEmergencyInfo()).toBe(false)
  })

  it('leaves a genuinely silent alert unchanged: it reaches terminal and the guardian can read the profile', async () => {
    await openAlert('community', ['silent'])
    expect(await guardianCanReadEmergencyInfo()).toBe(false)
    await run()
    const row = await alertRow()
    expect(row.stage).toBe('terminal')
    expect(row.next_deadline).toBeNull()
    expect(await sentKinds()).toEqual(['terminal'])
    expect(await escalatedNotes()).toEqual(['terminal'])
    // Control for the capped case above: proves this harness can see an unlock when there is one.
    expect(await guardianCanReadEmergencyInfo()).toBe(true)
  })

  it('leaves an alert with no causal windows (legacy path) unchanged', async () => {
    await openAlert('community', null)
    await run()
    expect((await alertRow()).stage).toBe('terminal')
  })

  it('does not extend the cap to collection_restricted (not authorised; stays as before)', async () => {
    await openAlert('community', ['collection_restricted'])
    await run()
    expect((await alertRow()).stage).toBe('terminal')
  })

  it('reads the kind from the highest-ordinal causal window, as notify_stage does', async () => {
    await openAlert('community', ['silent', 'device_unreachable'])
    await run()
    expect((await alertRow()).stage).toBe('community')

    await db.exec('truncate alerts,alert_events,notifications,passive_checkin_windows,private.passive_alert_causal_windows')
    await openAlert('community', ['device_unreachable', 'silent'])
    await run()
    expect((await alertRow()).stage).toBe('terminal')
  })
})
