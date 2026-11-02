import { readFileSync, readdirSync } from 'node:fs'
import { PGlite } from '@electric-sql/pglite'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'

// Human decisions 2026-11-02 (plan A; ADR-0039 rev.1, ADR-0040 rev.1): losing the device
// (passive `device_unreachable`, legacy `dark_device`) or not being allowed to look
// (`collection_restricted`) is an equipment fact, not a missing person. Such an alert may
// climb to group and community, but never to terminal, so it can never unlock the
// subject's address and emergency contacts.
//
// This runs whatever definitions the migrations leave as the newest, so it checks the
// functions production will actually run.

const migrationsDir = new URL('../../../supabase/migrations/', import.meta.url)
const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8')

function newestDefinition(signature: string) {
  const marker = `CREATE OR REPLACE FUNCTION ${signature}`
  const files = readdirSync(migrationsDir).filter(name => name.endsWith('.sql')).sort()
  for (let i = files.length - 1; i >= 0; i--) {
    const sql = readFileSync(new URL(files[i], migrationsDir), 'utf8')
    const start = sql.indexOf(marker)
    if (start >= 0) return sql.slice(start, sql.indexOf('$$;', start) + 3)
  }
  throw new Error(`no migration defines ${signature}`)
}

function newestStatement(prefix: string) {
  const files = readdirSync(migrationsDir).filter(name => name.endsWith('.sql')).sort()
  for (let i = files.length - 1; i >= 0; i--) {
    const sql = readFileSync(new URL(files[i], migrationsDir), 'utf8')
    const start = sql.indexOf(prefix)
    if (start >= 0) return sql.slice(start, sql.indexOf(';', start) + 1)
  }
  throw new Error(`no migration contains ${prefix}`)
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
// A group member who watches the subject. ADR-0039 lets an active Guardian see the profile
// for the whole relationship (not yet implemented); plan A is about alert-scoped unlocks,
// so privacy is checked from a watcher, whose access exists only because of the alert.
const watcher = 'd0000000-0000-4000-8000-000000000003'
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
async function watcherCanReadEmergencyInfo() {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [watcher])
  await db.exec('set role authenticated')
  try {
    return (await db.query('select home_address from emergency_info where user_id=$1', [subject])).rows.length === 1
  } finally {
    await db.exec('reset role')
  }
}

describe('device-loss alerts are capped below terminal', () => {
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
      create function private.watches_user(_watcher uuid, _target uuid) returns boolean language sql
        as $$ select _watcher='${watcher}'::uuid and _target='${subject}'::uuid $$;
      create function private.shares_community(_a uuid, _b uuid) returns boolean language sql as $$ select false $$;
      create table public.community_members(community_id uuid, user_id uuid, status text);
      grant usage on schema public, private, auth to authenticated;
      grant select on public.alerts, public.guardianships, public.emergency_info to authenticated;
    `)
    await db.exec(emergencyInfoSelectPolicy())
    await db.exec(newestDefinition('public.process_escalations()'))
    await db.exec(newestDefinition('private.notify_stage_before_passive_checkin('))
    await db.exec(newestDefinition('private.device_loss_alert_never_terminal()'))
    await db.exec(newestStatement('CREATE TRIGGER alerts_device_loss_never_terminal'))
  }, 30000)
  afterAll(async () => { await db?.close() })
  beforeEach(async () => {
    await db.exec(`truncate alerts,alert_events,notifications,guardianships,profiles,emergency_info,community_members,
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

  it('never lets a watcher read address and emergency contacts for a capped alert', async () => {
    await openAlert('community', ['device_unreachable'])
    await run()
    expect(await watcherCanReadEmergencyInfo()).toBe(false)
  })

  it('leaves a genuinely silent alert unchanged: it reaches terminal and the guardian can read the profile', async () => {
    await openAlert('community', ['silent'])
    expect(await watcherCanReadEmergencyInfo()).toBe(false)
    await run()
    const row = await alertRow()
    expect(row.stage).toBe('terminal')
    expect(row.next_deadline).toBeNull()
    expect(await sentKinds()).toEqual(['terminal'])
    expect(await escalatedNotes()).toEqual(['terminal'])
    // Control for the capped cases: proves this harness can see an unlock when there is one.
    expect(await watcherCanReadEmergencyInfo()).toBe(true)
  })

  describe('database guard: no code path may move a device-loss alert to terminal', () => {
    const toTerminal = () => db.query("update alerts set stage='terminal' where id=$1", [alertId])

    it.each([
      ['device_unreachable', ['device_unreachable'], 'silence'],
      ['collection_restricted', ['collection_restricted'], 'silence'],
      ['dark_device', null, 'dark_device'],
    ] as const)('refuses a direct update to terminal for %s', async (_label, kinds, cause) => {
      await openAlert('community', kinds ? [...kinds] : null, cause)
      await expect(toTerminal()).rejects.toThrow('device_loss_alert_never_terminal')
      expect((await alertRow()).stage).toBe('community')
      expect(await watcherCanReadEmergencyInfo()).toBe(false)
    })

    it.each([
      ['silent', ['silent'], 'silence'],
      ['legacy silence', null, 'silence'],
    ] as const)('still allows terminal for %s', async (_label, kinds, cause) => {
      await openAlert('community', kinds ? [...kinds] : null, cause)
      await toTerminal()
      expect((await alertRow()).stage).toBe('terminal')
    })

    it('keeps rows that were already terminal updatable (history is left as it is)', async () => {
      await openAlert('community', ['device_unreachable'])
      await db.exec('alter table alerts disable trigger alerts_device_loss_never_terminal')
      await toTerminal()
      await db.exec('alter table alerts enable trigger alerts_device_loss_never_terminal')
      await db.query("update alerts set stage='terminal',status='resolved' where id=$1", [alertId])
      expect((await alertRow()).status).toBe('resolved')
    })

    it('holds the line even if process_escalations is replaced by the pre-fix body', async () => {
      const preFix = read('supabase/migrations/20260923054905_activity_auto_resolution_guardian_pattern.sql')
      const start = preFix.indexOf('CREATE OR REPLACE FUNCTION public.process_escalations()')
      await db.exec(preFix.slice(start, preFix.indexOf('$$;', start) + 3))
      try {
        await openAlert('community', ['device_unreachable'])
        await db.exec('select public.process_escalations()')
        expect((await alertRow()).stage).toBe('community')
        expect(await sentKinds()).toEqual([])
        expect(await watcherCanReadEmergencyInfo()).toBe(false)
        // The regression is loud, not silent: it lands in job_failures every run.
        const failures = (await db.query<{ message: string }>('select message from private.job_failures')).rows
        expect(failures.map(row => row.message).join()).toContain('device_loss_alert_never_terminal')
      } finally {
        await db.exec(newestDefinition('public.process_escalations()'))
      }
    })
  })

  it('leaves an alert with no causal windows (legacy path) unchanged', async () => {
    await openAlert('community', null)
    await run()
    expect((await alertRow()).stage).toBe('terminal')
  })

  it('caps collection_restricted too: detection being off says nothing about the person', async () => {
    await openAlert('community', ['collection_restricted'])
    await run()
    const row = await alertRow()
    expect(row.stage).toBe('community')
    expect(row.next_deadline).toBeNull()
    expect(await sentKinds()).toEqual([])
    expect(await watcherCanReadEmergencyInfo()).toBe(false)
  })

  it('caps a legacy dark_device alert: it climbs to community, stops, and never unlocks the profile', async () => {
    await openAlert('self', null, 'dark_device')
    await run()
    expect((await alertRow()).stage).toBe('group')
    await dueNow(); await run()
    expect((await alertRow()).stage).toBe('community')
    await dueNow(); await run()
    const row = await alertRow()
    expect(row.status).toBe('open')
    expect(row.stage).toBe('community')
    expect(row.next_deadline).toBeNull()
    expect(await sentKinds()).toEqual(['community', 'group'])
    expect(await watcherCanReadEmergencyInfo()).toBe(false)
  })

  it('leaves SOS untouched: it still reveals the profile immediately', async () => {
    await openAlert('group', null, 'sos')
    expect(await watcherCanReadEmergencyInfo()).toBe(true)
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

  describe('legacy notifier names a dark device as lost contact', () => {
    const community = 'f0000000-0000-4000-8000-000000000001'
    async function notice(cause: string, stage: string) {
      await db.exec('truncate alerts,notifications')
      await db.query("insert into alerts(id,user_id,cause,stage) values($1,$2,$3,$4)", [alertId, subject, cause, stage])
      await db.query('select private.notify_stage_before_passive_checkin($1,$2,$3)', [alertId, subject, stage])
      return (await db.query<{ recipient_id: string; body: string; params: Record<string, string> }>(
        'select recipient_id,body,params from notifications where alert_id=$1', [alertId])).rows
    }
    beforeEach(async () => {
      await db.query("insert into community_members values($1,$2,'active'),($1,$3,'active')", [community, subject, guardian])
    })

    it.each(['group', 'community'])('tells %s recipients the device lost contact and says so in params', async stage => {
      const rows = await notice('dark_device', stage)
      expect(rows.map(row => row.recipient_id)).toEqual([guardian])
      expect(rows[0].body).toContain('设备')
      expect(rows[0].body).toContain('失去联系')
      expect(rows[0].body).not.toMatch(/异常沉默|长时间失联/)
      expect(rows[0].params).toMatchObject({ name: 'Subject', miss_kind: 'device_unreachable', cause: 'dark_device' })
    })

    it.each(['group', 'community'])('keeps the %s wording and params for a legacy silence alert', async stage => {
      const rows = await notice('silence', stage)
      expect(rows[0].body).toMatch(/异常沉默|长时间失联/)
      expect(rows[0].params).toEqual({ name: 'Subject' })
    })

    it('keeps the SOS wording', async () => {
      const rows = await notice('sos', 'group')
      expect(rows[0].body).toContain('紧急求助')
      expect(rows[0].params).toEqual({ name: 'Subject' })
    })
  })
})
