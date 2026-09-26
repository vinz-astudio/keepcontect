import { readFileSync } from 'node:fs'
import { PGlite } from '@electric-sql/pglite'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'
const read=(f:string)=>readFileSync(new URL(`../../../${f}`,import.meta.url),'utf8')
const a='a0000000-0000-4000-8000-000000000001', b='a0000000-0000-4000-8000-000000000002'
const old='b0000000-0000-4000-8000-000000000001', newer='b0000000-0000-4000-8000-000000000002'
const install='c0000000-0000-4000-8000-000000000001', otherInstall='c0000000-0000-4000-8000-000000000002'
const secret='1'.repeat(64), secretB='2'.repeat(64)
let db:PGlite
const user=(id:string)=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id])
const create=(id=old,generation=1,installation=install,capability=secret)=>db.query('select create_push_binding($1,$2,$3,encode(sha256(convert_to($4,\'UTF8\')),\'hex\'))',[id,installation,generation,capability])
describe('durable native binding database contracts',()=>{
  beforeAll(async()=>{
    db=new PGlite()
    await db.exec(read('supabase/tests/fixtures/activity_resolution.sql'))
    const ingest=read('supabase/migrations/20260814190000_passive_evidence_ingest.sql')
    await db.exec(ingest.slice(0,ingest.indexOf('CREATE TABLE private.passive_evidence_events')))
    // pgcrypto-only random transport is stubbed for this isolated fixture. The
    // ownership, locking, identity, cursor and revocation code is real migration SQL.
    await db.exec(`create function extensions.gen_random_bytes(n integer) returns bytea language sql as $$ select sha256(convert_to(gen_random_uuid()::text,'UTF8')) $$;
      create function extensions.digest(t text,algorithm text) returns bytea language sql as $$ select sha256(convert_to(t,'UTF8')) $$;
      create table public.push_tokens(token text primary key,user_id uuid not null,platform text not null,updated_at timestamptz not null)`)
    await db.exec(read('supabase/migrations/20260926184133_resume_passive_collector.sql'))
    await db.exec(read('supabase/migrations/20260926184136_push_binding_revocation.sql'))
  },30000)
  afterAll(async()=>{await db?.close()})
  beforeEach(async()=>{
    await db.exec(`truncate push_tokens,private.push_bindings,private.push_installations,private.passive_collector_bindings,passive_checkin_accounts cascade;
      insert into passive_checkin_accounts(user_id,engine_mode,active_epoch_id) values('${a}','passive_checkin',gen_random_uuid()),('${b}','passive_checkin',gen_random_uuid());`)
    await user(a)
  })
  it('resumes the same collector ID/cursor and rotates only the credential',async()=>{
    await db.query(`insert into private.passive_collector_bindings(id,user_id,collector_instance_id,surface_type,collector_contract,client_version,credential_sha256,sequence_cursor)
      values($1,$2,'device','tauri_native','tauri-passive-evidence-v1','old',repeat('a',64),17)`,[old,a])
    const res=await db.query<{value:{binding_id:string;credential:string;next_sequence:number;credential_version:number}}>("select resume_passive_collector($1,'new') value",[old])
    expect(res.rows[0].value).toMatchObject({binding_id:old,next_sequence:18,credential_version:2})
    expect(res.rows[0].value.credential).toHaveLength(64)
    await user(b)
    await expect(db.query("select resume_passive_collector($1,'new')",[old])).rejects.toThrow('collector not owned')
    await user(a); await db.query('update private.passive_collector_bindings set revoked_at=clock_timestamp() where id=$1',[old])
    await expect(db.query("select resume_passive_collector($1,'new')",[old])).rejects.toThrow('revoked or unavailable')
    expect((await db.query('select id from private.passive_collector_bindings')).rows).toHaveLength(1)
  })
  it('revokes offline by capability without retaining account credentials',async()=>{
    await create(); await db.query("select register_push_token($1,'token-device-a','ios')",[old])
    await user('')
    expect((await db.query<{ok:boolean}>('select revoke_push_binding($1,$2) ok',[old,secretB])).rows[0].ok).toBe(false)
    expect((await db.query('select * from push_tokens')).rows).toHaveLength(1)
    await db.query('select revoke_push_binding($1,$2)',[old,secret])
    await db.query('select revoke_push_binding($1,$2)',[old,secret])
    expect((await db.query('select * from push_tokens')).rows).toHaveLength(0)
    await user(a)
    await expect(db.query("select register_push_token($1,'token-device-a','ios')",[old])).rejects.toThrow('revoked')
  })
  it('does not resurrect a create request that finishes after logout',async()=>{
    await user(''); await db.query('select revoke_push_binding($1,$2)',[old,secret]); await user(a)
    await expect(create()).rejects.toThrow('revoked or conflicting')
    expect((await db.query('select * from private.push_installations')).rows).toHaveLength(0)
  })
  it('keeps the new owner and other devices when a previous logout retries late',async()=>{
    await create(); await db.query("select register_push_token($1,'shared-fcm-token','ios')",[old])
    const other='b0000000-0000-4000-8000-000000000003'
    await create(other,1,otherInstall); await db.query("select register_push_token($1,'other-fcm-token','android')",[other])
    await user(b); await create(newer,2,install,secretB)
    await db.query("select register_push_token($1,'shared-fcm-token','android')",[newer])
    await user(''); await db.query("select revoke_push_binding($1,$2,'shared-fcm-token')",[old,secret])
    expect((await db.query<{user_id:string;platform:string}>("select user_id,platform from push_tokens where token='shared-fcm-token'")).rows[0]).toEqual({user_id:b,platform:'android'})
    expect((await db.query('select * from push_tokens')).rows).toHaveLength(2)
    await user(a)
    await expect(create()).rejects.toThrow('revoked or conflicting')
    await db.query("select register_fcm_token('shared-fcm-token','ios')")
    expect((await db.query<{user_id:string}>("select user_id from push_tokens where token='shared-fcm-token'")).rows[0].user_id).toBe(b)
  })
  it('allows legacy token revocation but forbids anonymous registration or collector resume',async()=>{
    await db.query("select register_fcm_token('old-unbound-token','ios')")
    await user(''); await db.query("select revoke_push_binding($1,$2,'old-unbound-token')",[old,secret])
    expect((await db.query('select * from push_tokens')).rows).toHaveLength(0)
    const res=await db.query<{create_allowed:boolean;resume_allowed:boolean;revoke_allowed:boolean}>(`select
      has_function_privilege('anon','public.create_push_binding(uuid,uuid,bigint,text)','execute') create_allowed,
      has_function_privilege('anon','public.resume_passive_collector(uuid,text)','execute') resume_allowed,
      has_function_privilege('anon','public.revoke_push_binding(uuid,text,text)','execute') revoke_allowed`)
    expect(res.rows[0]).toEqual({create_allowed:false,resume_allowed:false,revoke_allowed:true})
  })
})
