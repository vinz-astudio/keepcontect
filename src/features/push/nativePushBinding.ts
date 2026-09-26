import { Capacitor } from '@capacitor/core'
import { SUPABASE_ANON_KEY, SUPABASE_URL } from '@/lib/config'
import { supabase } from '@/lib/supabase'
import { configureNativePushNotifications, clearNativePushNotifications, getNativeFcmToken, requestNativeNotificationPermission } from '@/features/passive/native'
import { getHeartbeatToken } from '@/features/passive/api'
import { activatePushBinding, retirePushBinding, readPushBindingState, PUSH_BINDING_KEY, type PushBindingState } from './pushBindingState'

let epoch=0
let session: {ownerId:string;generation:string|number;epoch:number;pushBindingId:string}|null=null
export const getNativePushSession=()=>session
const read=()=>readPushBindingState(localStorage,()=>crypto.randomUUID())
const save=(state:PushBindingState)=>localStorage.setItem(PUSH_BINDING_KEY,JSON.stringify(state))
const signal=()=>window.dispatchEvent(new Event('kc-native-push-ready'))
const native=()=>['ios','android'].includes(Capacitor.getPlatform())
const rpc=async(name:string,args:Record<string,unknown>)=>{
  const {data,error}=await supabase.rpc(name as never,args as never)
  if(error) throw error
  if(data!==true) throw new Error(`${name} rejected`)
}
const digest=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(b=>b.toString(16).padStart(2,'0')).join('')

let draining:Promise<void>|null=null
export function flushPushRevocations():Promise<void> {
  if(draining) return draining
  draining=(async()=>{
    for(const binding of read().pending) {
      try {
        // Anonymous transport: no account access or refresh token survives logout.
        const response=await fetch(`${SUPABASE_URL}/rest/v1/rpc/revoke_push_binding`,{
          method:'POST',headers:{apikey:SUPABASE_ANON_KEY,Authorization:`Bearer ${SUPABASE_ANON_KEY}`,'Content-Type':'application/json'},
          body:JSON.stringify({_binding_id:binding.bindingId,_revoke_secret:binding.secret,_legacy_token:binding.token??null}),
          signal:AbortSignal.timeout(8000),
        })
        if(!response.ok || await response.json()!==true) continue
        const current=read(); current.pending=current.pending.filter(row=>row.bindingId!==binding.bindingId); save(current)
      } catch { /* Durable queue retries on reconnect/resume, even at the login page. */ }
    }
  })().finally(()=>{draining=null})
  return draining
}

export function startPushRevocationRetry():()=>void {
  if(!native()) return ()=>{}
  const retry=()=>{void flushPushRevocations()}
  retry(); window.addEventListener('online',retry); window.addEventListener('focus',retry)
  const timer=window.setInterval(retry,60_000)
  return ()=>{clearInterval(timer);window.removeEventListener('online',retry);window.removeEventListener('focus',retry)}
}

export function startNativePushLifecycle(ownerId:string):()=>void {
  if(!native()) return ()=>{}
  const currentEpoch=++epoch
  session=null
  const state=read()
  const binding=activatePushBinding(state,ownerId,()=>crypto.randomUUID(),()=>Array.from(crypto.getRandomValues(new Uint8Array(32))).map(b=>b.toString(16).padStart(2,'0')).join(''))
  save(state) // Must precede create: a concurrent logout can always revoke this ID.
  let stopped=false, inFlight=false
  const current=()=>!stopped && currentEpoch===epoch && read().active?.bindingId===binding.bindingId
  const options={recipientUserId:ownerId,pushBindingId:binding.bindingId,revokeSecret:binding.secret,supabaseUrl:SUPABASE_URL,anonKey:SUPABASE_ANON_KEY}
  const sync=async()=>{
    if(inFlight||!current())return
    inFlight=true
    try {
      const configured=await configureNativePushNotifications(options)
      if(!current())return
      session={ownerId,generation:configured.generation,epoch:currentEpoch,pushBindingId:binding.bindingId};signal()
      void flushPushRevocations()
      await requestNativeNotificationPermission()
      if(!current())return
      const token=await getNativeFcmToken()
      if(!current())return
      if(token){binding.token=token;const latest=read();if(latest.active?.bindingId===binding.bindingId){latest.active.token=token;save(latest)}}
      if(token) await configureNativePushNotifications({...options,legacyToken:token})
      if(!current())return
      await rpc('create_push_binding',{_binding_id:binding.bindingId,_installation_id:state.installationId,_generation:binding.generation,_revoke_sha256:await digest(binding.secret)})
      if(!current())return
      if(token) await rpc('register_push_token',{_binding_id:binding.bindingId,_token:token,_platform:Capacitor.getPlatform()})
      if(!current())return
      const heartbeat=await getHeartbeatToken()
      if(heartbeat&&current()) await configureNativePushNotifications({...options,token:heartbeat})
    } catch(error) {
      if(current()) console.warn('[push] registration pending; will retry',error instanceof Error?error.message:'unavailable')
    } finally {inFlight=false}
  }
  const retry=()=>{void sync()}
  retry();window.addEventListener('online',retry);window.addEventListener('focus',retry)
  const timer=window.setInterval(retry,60_000)
  return ()=>{stopped=true;if(epoch===currentEpoch){epoch++;session=null;signal()}clearInterval(timer);window.removeEventListener('online',retry);window.removeEventListener('focus',retry)}
}

export async function stopNativePushForLogout():Promise<void> {
  if(!native())return
  ++epoch;session=null;signal()
  const state=read();retirePushBinding(state);save(state)
  try {await clearNativePushNotifications()} catch { /* Old shell: JS tombstone still revokes server delivery. */ }
  void flushPushRevocations()
}
