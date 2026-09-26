import { afterEach,beforeEach,describe,expect,it,vi } from 'vitest'
const mocks=vi.hoisted(()=>({rpc:vi.fn(),configure:vi.fn(),clear:vi.fn(),token:vi.fn(),permission:vi.fn(),heartbeat:vi.fn()}))
vi.mock('@capacitor/core',()=>({Capacitor:{getPlatform:()=> 'ios'}}))
vi.mock('@/lib/config',()=>({SUPABASE_URL:'https://kc.example.invalid',SUPABASE_ANON_KEY:'public-anon-key'}))
vi.mock('@/lib/supabase',()=>({supabase:{rpc:mocks.rpc}}))
vi.mock('@/features/passive/native',()=>({configureNativePushNotifications:mocks.configure,clearNativePushNotifications:mocks.clear,getNativeFcmToken:mocks.token,requestNativeNotificationPermission:mocks.permission}))
vi.mock('@/features/passive/api',()=>({getHeartbeatToken:mocks.heartbeat}))
import { startNativePushLifecycle,stopNativePushForLogout,flushPushRevocations,getNativePushSession } from './nativePushBinding'
import { PUSH_BINDING_KEY } from './pushBindingState'
const values=new Map<string,string>()
const state=()=>JSON.parse(values.get(PUSH_BINDING_KEY)!)
const settle=async()=>{for(let i=0;i<50;i++)await Promise.resolve()}
let cleanups:Array<()=>void>=[]
beforeEach(()=>{
  vi.useFakeTimers();vi.resetAllMocks();values.clear();cleanups=[]
  const target=new EventTarget()
  vi.stubGlobal('window',Object.assign(target,{setInterval:globalThis.setInterval,clearInterval:globalThis.clearInterval}))
  vi.stubGlobal('localStorage',{getItem:(k:string)=>values.get(k)??null,setItem:(k:string,v:string)=>values.set(k,v)})
  let seq=0
  vi.stubGlobal('crypto',{randomUUID:()=>`id-${++seq}`,getRandomValues:(a:Uint8Array)=>a.fill(1),subtle:{digest:async()=>new Uint8Array(32).buffer}})
  vi.stubGlobal('fetch',vi.fn().mockImplementation(async()=>new Response('true')))
  mocks.configure.mockResolvedValue({generation:7});mocks.clear.mockResolvedValue(undefined);mocks.permission.mockResolvedValue(undefined)
  mocks.token.mockResolvedValue('cached-device-fcm-token');mocks.heartbeat.mockResolvedValue('heartbeat');mocks.rpc.mockResolvedValue({data:true,error:null})
})
afterEach(async()=>{cleanups.forEach(fn=>fn());await flushPushRevocations();vi.useRealTimers();vi.unstubAllGlobals()})
describe('native push lifecycle races',()=>{
  it('reuses the binding on a same-account restart, and updates its exact token platform',async()=>{
    const stop=startNativePushLifecycle('A');cleanups.push(stop);await settle()
    const first=state().active.bindingId;stop();cleanups.push(startNativePushLifecycle('A'));await settle()
    expect(state().active.bindingId).toBe(first)
    expect(mocks.rpc).toHaveBeenCalledWith('register_push_token',{_binding_id:first,_token:'cached-device-fcm-token',_platform:'ios'})
    expect(getNativePushSession()?.ownerId).toBe('A')
  })
  it('a create response after logout cannot register its token or re-enable the native owner',async()=>{
    let finish!:(v:unknown)=>void
    mocks.rpc.mockImplementationOnce(()=>new Promise(resolve=>{finish=resolve}))
    cleanups.push(startNativePushLifecycle('A'));await settle()
    expect(mocks.rpc).toHaveBeenCalledWith('create_push_binding',expect.anything())
    const count=mocks.configure.mock.calls.length
    await stopNativePushForLogout();finish({data:true,error:null});await settle()
    expect(state().active).toBeNull();expect(getNativePushSession()).toBeNull()
    expect(mocks.rpc.mock.calls.some(call=>call[0]==='register_push_token')).toBe(false)
    expect(mocks.configure).toHaveBeenCalledTimes(count)
    const request=(fetch as ReturnType<typeof vi.fn>).mock.calls[0]
    expect(request[0]).toBe('https://kc.example.invalid/rest/v1/rpc/revoke_push_binding')
    expect(request[1].headers.Authorization).toBe('Bearer public-anon-key')
    expect(request[1].body).not.toMatch(/refresh_token|access_token|heartbeat/)
  })
  it('retains an offline revoke until a later anonymous retry succeeds',async()=>{
    cleanups.push(startNativePushLifecycle('A'));await settle()
    vi.mocked(fetch).mockRejectedValueOnce(Error('offline'))
    await stopNativePushForLogout();await settle()
    expect(state().pending).toHaveLength(1)
    await flushPushRevocations();expect(state().pending).toHaveLength(0)
  })
})
