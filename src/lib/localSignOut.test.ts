import { describe,expect,it,vi } from 'vitest'
import { localSignOutTransport,clearLocalAuthSession } from './localSignOut'
import { createClient } from '@supabase/supabase-js'
describe('offline local signout transport',()=>{
  it('also cancels a refresh whose response body never completes',async()=>{
    const transport=localSignOutTransport(vi.fn().mockResolvedValue(new Response(new ReadableStream())))
    const response=transport.fetch('https://kc.invalid/auth/v1/token?grant_type=refresh_token',{method:'POST'})
    await new Promise(resolve=>setTimeout(resolve,0))
    await transport.run(async()=>{})
    expect((await (await response).json()).code).toBe('refresh_token_not_found')
  })
  it('preserves refresh responses outside an explicit local logout',async()=>{
    const transport=localSignOutTransport(vi.fn().mockResolvedValue(new Response('{"access_token":"fixture"}',{status:200,headers:{'X-Fixture':'yes'}})))
    const response=await transport.fetch('https://kc.invalid/auth/v1/token?grant_type=refresh_token',{method:'POST'})
    expect(response.headers.get('X-Fixture')).toBe('yes')
    expect(await response.json()).toEqual({access_token:'fixture'})
  })
  it('cancels an already in-flight SDK refresh and ignores its late successful response',async()=>{
    let respond!: (response: Response) => void
    let started!: () => void
    const entered = new Promise<void>(resolve => { started=resolve })
    const network=vi.fn(() => { started(); return new Promise<Response>(resolve => { respond=resolve }) })
    const transport=localSignOutTransport(network)
    const values=new Map<string,string>()
    const key='inflight-auth-fixture'
    const session={access_token:'current.jwt.signature',refresh_token:'old-refresh-secret',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:'old-user'}}
    values.set(key,JSON.stringify(session))
    const client=createClient('https://kc.example.invalid','anon',{global:{fetch:transport.fetch},auth:{storageKey:key,autoRefreshToken:false,detectSessionInUrl:false,storage:{getItem:k=>values.get(k)??null,setItem:(k,v)=>{values.set(k,v)},removeItem:k=>{values.delete(k)}}}})
    await client.auth.getSession()
    const refreshing=client.auth.refreshSession()
    await entered
    values.set(key,JSON.stringify({...session,expires_at:1}))
    await clearLocalAuthSession(client.auth,transport)
    expect(values.has(key)).toBe(false)
    expect((await refreshing).error?.code).toBe('refresh_token_not_found')
    respond(new Response(JSON.stringify({...session,access_token:'late.jwt.signature'}),{status:200,headers:{'Content-Type':'application/json'}}))
    await new Promise(resolve=>setTimeout(resolve,0))
    expect((await client.auth.getSession()).data.session).toBeNull()
    expect(values.has(key)).toBe(false)
    await client.auth.stopAutoRefresh()
  })
  it('uses the installed SDK to remove an expired offline session and restarts automatic refresh',async()=>{
    const network=vi.fn().mockRejectedValue(new Error('offline'))
    const transport=localSignOutTransport(network)
    const values=new Map<string,string>()
    const key='expired-auth-fixture'
    values.set(key,JSON.stringify({access_token:'expired.jwt.signature',refresh_token:'old-refresh-secret',expires_at:1,expires_in:3600,token_type:'bearer',user:{id:'old-user'}}))
    const client=createClient('https://kc.example.invalid','anon',{global:{fetch:transport.fetch},auth:{storageKey:key,autoRefreshToken:false,detectSessionInUrl:false,storage:{getItem:k=>values.get(k)??null,setItem:(k,v)=>{values.set(k,v)},removeItem:k=>{values.delete(k)}}}})
    const restart=vi.spyOn(client.auth,'startAutoRefresh')
    await clearLocalAuthSession(client.auth,transport)
    expect((await client.auth.getSession()).data.session).toBeNull()
    expect(values.has(key)).toBe(false)
    expect(network).not.toHaveBeenCalled()
    expect(restart).toHaveBeenCalledOnce()
    await client.auth.stopAutoRefresh()
  })
  it('lets auth SDK remove credentials while offline without contacting its logout endpoint',async()=>{
    const network=vi.fn().mockRejectedValue(new Error('offline'))
    const transport=localSignOutTransport(network)
    let removed=false
    await transport.run(async()=>{
      const result=await transport.fetch('https://kc.invalid/auth/v1/logout?scope=local',{method:'POST'})
      if(result.ok)removed=true
    })
    expect(removed).toBe(true);expect(network).not.toHaveBeenCalled()
    await expect(transport.fetch('https://kc.invalid/auth/v1/logout',{method:'POST'})).rejects.toThrow('offline')
  })
  it('never intercepts login, refresh, or RPC traffic and resets on cleanup failure',async()=>{
    const network=vi.fn().mockResolvedValue(new Response('{}'))
    const transport=localSignOutTransport(network)
    await expect(transport.run(async()=>{
      await transport.fetch('https://kc.invalid/auth/v1/token',{method:'POST'})
      throw Error('cleanup failed')
    })).rejects.toThrow('cleanup failed')
    await transport.fetch('https://kc.invalid/auth/v1/logout',{method:'POST'})
    expect(network).toHaveBeenCalledTimes(2)
  })
})
