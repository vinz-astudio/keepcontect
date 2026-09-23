import { readFileSync } from 'node:fs'
import { PGlite } from '@electric-sql/pglite'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8')
const ward = 'a0000000-0000-4000-8000-000000000001'
const guardian = 'a0000000-0000-4000-8000-000000000002'
const stranger = 'a0000000-0000-4000-8000-000000000003'
const link = 'b0000000-0000-4000-8000-000000000001'
const alert = 'c0000000-0000-4000-8000-000000000001'
let db: PGlite

function baselineFunction(name: string) {
  const sql = read('supabase/migrations/20260808160000_baseline_from_production.sql')
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION "private"."${name}"`)
  return sql.slice(start, sql.indexOf('$$;', start) + 3)
}

async function asUser(uid: string) {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [uid])
}
async function openAlert(cause = 'silence', stage = 'self') {
  await db.query(`insert into alerts(id,user_id,cause,stage,opened_at,next_deadline)
    values($1,$2,$3,$4,now()-interval '31 minutes',now()-interval '1 minute')`, [alert,ward,cause,stage])
}
async function ping(age = '1 minute', observedAge = age, version = 2, uid = ward) {
  await db.query(`insert into behavior_pings(user_id,event_id,kind,source,at,received_at,ingest_version)
    values($1,gen_random_uuid(),'app','app',clock_timestamp()-$2::interval,clock_timestamp()-$3::interval,$4)`,
  [uid,observedAge,age,version])
}
async function activity() {
  await db.query(`select private.apply_liveness_side_effects($1,at,received_at)
    from behavior_pings where user_id=$1 order by received_at desc limit 1`, [ward])
}
async function state() {
  return (await db.query<{status:string;stage:string;requires_explicit_unlock:boolean}>('select * from alerts where id=$1',[alert])).rows[0]
}

describe('activity auto-resolution in PostgreSQL', () => {
  beforeAll(async () => {
    db = new PGlite()
    await db.exec(read('supabase/tests/fixtures/activity_resolution.sql'))
    await db.exec(baselineFunction('apply_liveness_side_effects'))
    await db.exec(baselineFunction('insert_behavior_ping'))
    const engine = read('supabase/migrations/20260814193000_passive_window_engine.sql')
    const start = engine.indexOf('CREATE OR REPLACE FUNCTION public.process_escalations()')
    await db.exec(engine.slice(start,engine.indexOf('$$;',start)+3))
    const rolling = read('supabase/migrations/20260821020000_deadlines_roll_and_sleep_is_not_counted.sql')
    const restart = rolling.indexOf('CREATE OR REPLACE FUNCTION private.restart_passive_epoch_after_resolution()')
    await db.exec(rolling.slice(restart,rolling.indexOf('$$;',restart)+3))
    await db.exec(`create trigger alerts_restart_passive_epoch_after_resolution after update of status on alerts
      for each row execute function private.restart_passive_epoch_after_resolution()`)
    const migration = read('supabase/migrations/20260923054905_activity_auto_resolution_guardian_pattern.sql')
    await db.exec(migration)
  }, 30000)
  afterAll(async () => { await db?.close() })
  beforeEach(async () => {
    await db.exec(`truncate alerts,alert_events,notifications,behavior_pings,device_state,guardianships,user_settings,profiles,
      passive_checkin_accounts,passive_checkin_contract_versions,passive_monitoring_epochs,passive_checkin_windows,
      private.passive_alert_causal_windows cascade;
      insert into profiles values('${ward}','Ward'),('${guardian}','Guardian'),('${stranger}','Other');
      insert into user_settings values('${ward}',encode(sha256(convert_to('kc:0-1-2-5','UTF8')),'hex'));
      insert into guardianships(id,guardian_id,ward_id) values('${link}','${guardian}','${ward}');`)
    await asUser(ward)
  })

  it.each(['self','group','community','terminal'])('closes an ordinary %s alert on new activity', async stage => {
    await openAlert('silence',stage)
    await ping()
    await activity()
    expect((await state()).status).toBe('resolved')
    expect((await db.query('select * from alert_events where kind=\'auto_resolved\'')).rows).toHaveLength(1)
    await activity()
    expect((await db.query('select * from alert_events')).rows).toHaveLength(1)
  })
  it('replays Bernardo: recovered activity prevents the pending group escalation', async () => {
    await openAlert()
    await ping('17 minutes')
    await db.exec('select public.process_escalations()')
    expect((await state()).status).toBe('resolved')
    expect((await db.query("select * from notifications where kind='group'")).rows).toHaveLength(0)
  })
  it.each([
    ['40 minutes','40 minutes',2], ['1 minute','1 hour',2], ['1 minute','-2 minutes',2], ['1 minute','1 minute',1],
  ])('rejects pre-alert, historical, future or v1 evidence (%s, %s, %s)', async (age,atAge,version) => {
    await openAlert(); await ping(age,atAge,version); await activity()
    expect((await state()).status).toBe('open')
  })
  it('does not treat heartbeat, cross-user activity, or forged helper arguments as an answer', async () => {
    await openAlert()
    await db.query('select private.apply_liveness_side_effects($1,now(),now())',[ward])
    await ping('1 minute','1 minute',2,stranger)
    await db.exec('select public.process_escalations()')
    expect((await state()).status).toBe('open')
  })
  it('keeps an intentional SOS open', async () => {
    await openAlert('sos'); await ping(); await activity()
    expect((await state()).status).toBe('open')
    expect((await state()).requires_explicit_unlock).toBe(false)
    await db.query('select public.acknowledge_safe($1)', [alert])
    expect((await state()).status).toBe('resolved')
  })
  it('allows only an active designated guardian to enable pattern', async () => {
    await expect(db.query('select public.set_guardian_pattern_requirement($1,true)',[link])).rejects.toThrow()
    await asUser(stranger)
    await expect(db.query('select public.set_guardian_pattern_requirement($1,true)',[link])).rejects.toThrow()
    await asUser(guardian)
    await db.query('select public.set_guardian_pattern_requirement($1,true)',[link])
    await asUser(ward); await openAlert(); await ping(); await activity()
    expect((await state()).status).toBe('open')
    expect((await state()).requires_explicit_unlock).toBe(true)
    await expect(db.query('select public.acknowledge_safe($1)',[alert])).rejects.toThrow('pattern_required')
    await expect(db.exec('select public.resolve_my_alert()')).rejects.toThrow('pattern_required')
    await expect(db.query('select public.acknowledge_safe_with_pattern($1,$2)',[alert,[0,1,2,3]])).rejects.toThrow('invalid_pattern')
    await db.query('select public.acknowledge_safe_with_pattern($1,$2)',[alert,[0,1,2,5]])
    expect((await state()).status).toBe('resolved')
  })
  it('revoking the guardian removes the requirement for an already open alert', async () => {
    await asUser(guardian); await db.query('select public.set_guardian_pattern_requirement($1,true)',[link])
    await asUser(ward); await openAlert()
    await db.query('delete from guardianships where id=$1',[link])
    expect((await state()).requires_explicit_unlock).toBe(false)
    await ping(); await activity()
    expect((await state()).status).toBe('resolved')
  })
  it('ordinary users can confirm with a button at every stage without a pattern', async () => {
    await openAlert('silence','terminal')
    await db.query('select public.acknowledge_safe($1)',[alert])
    expect((await state()).status).toBe('resolved')
  })

  it('requires an existing subject pattern before a guardian can turn the setting on', async () => {
    await db.exec('delete from user_settings')
    await asUser(guardian)
    await expect(db.query('select public.set_guardian_pattern_requirement($1,true)',[link])).rejects.toThrow('ward_pattern_not_set')
  })

  it('any active guardian requirement wins; disabling the last one restores automatic resolution', async () => {
    const otherLink = 'b0000000-0000-4000-8000-000000000002'
    await db.query('insert into guardianships(id,guardian_id,ward_id) values($1,$2,$3)',[otherLink,stranger,ward])
    await asUser(stranger); await db.query('select public.set_guardian_pattern_requirement($1,true)',[otherLink])
    await asUser(guardian); await db.query('select public.set_guardian_pattern_requirement($1,false)',[link])
    await asUser(ward); await openAlert(); await ping(); await activity()
    expect((await state()).status).toBe('open')
    await asUser(stranger); await db.query('select public.set_guardian_pattern_requirement($1,false)',[otherLink])
    await asUser(ward); await activity()
    expect((await state()).status).toBe('resolved')
  })

  it('does not let another user confirm an alert or read its guardian policy', async () => {
    await openAlert(); await asUser(stranger)
    const result = await db.query<{result:{ok:boolean}}>('select public.acknowledge_safe($1) result',[alert])
    expect(result.rows[0].result.ok).toBe(false)
    expect((await state()).status).toBe('open')
    expect((await db.query('select * from public.my_guardian_pattern_requirements()')).rows).toHaveLength(0)
  })

  it('closes from the real validator, withdraws queued alerts, and does not notify uninvolved group members', async () => {
    await openAlert()
    await db.query("insert into notifications(recipient_id,alert_id,kind,body) values($1,$2,'self','prompt')",[ward,alert])
    await db.query("select private.insert_behavior_ping($1,gen_random_uuid(),clock_timestamp(),'app','app')",[ward])
    expect((await state()).status).toBe('resolved')
    expect((await db.query("select * from notifications where kind='self' and pushed_at is null")).rows).toHaveLength(0)
    expect((await db.query('select distinct recipient_id from notifications')).rows).toEqual([{recipient_id:ward}])
  })

  it('does not let authenticated or anonymous callers invoke internal mutators directly', async () => {
    const result = await db.query<{private_allowed:boolean;anonymous_allowed:boolean;public_allowed:boolean}>(`select
      has_function_privilege('authenticated','private.resolve_activity_alerts(uuid)','EXECUTE') private_allowed,
      has_function_privilege('anon','public.acknowledge_safe(uuid)','EXECUTE') anonymous_allowed,
      has_function_privilege('authenticated','public.acknowledge_safe(uuid)','EXECUTE') public_allowed`)
    expect(result.rows[0]).toEqual({private_allowed:false,anonymous_allowed:false,public_allowed:true})
  })

  it('does not clear a newer alert when an old notification is acknowledged', async () => {
    await openAlert(); await db.query('select public.acknowledge_safe($1)',[alert])
    const newer='c0000000-0000-4000-8000-000000000002'
    await db.query("insert into alerts(id,user_id,cause,stage) values($1,$2,'silence','self')",[newer,ward])
    await db.query('select public.acknowledge_safe($1)',[alert])
    expect((await db.query<{status:string}>('select status from alerts where id=$1',[newer])).rows[0].status).toBe('open')
  })

  it.each(['activity','button'])('starts a fresh passive window after %s instead of re-alerting for old misses', async method => {
    const contract='d0000000-0000-4000-8000-000000000001'
    const epoch='e0000000-0000-4000-8000-000000000001'
    await db.query('insert into passive_checkin_contract_versions values($1,$2,60)',[contract,ward])
    await db.query("insert into passive_checkin_accounts(user_id,engine_mode,active_contract_version_id,active_epoch_id) values($1,'passive_checkin',$2,$3)",[ward,contract,epoch])
    await db.query("insert into passive_monitoring_epochs(id,user_id,contract_version_id,started_at,start_reason) values($1,$2,$3,now()-interval '2 hours','contract_saved')",[epoch,ward,contract])
    await db.query("insert into passive_checkin_windows(user_id,epoch_id,ordinal,outcome) values($1,$2,0,'missed'),($1,$2,1,'pending')",[ward,epoch])
    await openAlert()
    await db.query('insert into private.passive_alert_causal_windows(alert_id) values($1)',[alert])
    if(method==='activity') { await ping(); await activity() }
    else await db.query('select public.acknowledge_safe($1)',[alert])
    expect((await state()).status).toBe('resolved')
    const current = await db.query<{start_reason:string;id:string}>("select * from passive_monitoring_epochs where ended_at is null")
    expect(current.rows).toHaveLength(1)
    expect(current.rows[0].id).not.toBe(epoch)
    expect(current.rows[0].start_reason).toBe(method==='activity'?'activity_resolution':'explicit_resolution')
    const pending = await db.query<{window_end:Date;window_start:Date}>("select * from passive_checkin_windows where outcome='pending'")
    expect(pending.rows).toHaveLength(1)
    expect(new Date(pending.rows[0].window_end).getTime()-new Date(pending.rows[0].window_start).getTime()).toBe(3600000)
    expect((await db.query("select * from passive_checkin_windows where outcome='missed'")).rows).toHaveLength(1)
  })
})
