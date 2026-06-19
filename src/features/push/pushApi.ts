// Web Push 订阅管理：请求权限（iOS 必须用户手势触发）、订阅、上报 Supabase。

import { supabase } from '@/lib/supabase'
import { VAPID_PUBLIC_KEY } from '@/lib/config'

export type PushStatus =
  | 'unsupported'
  | 'need_permission'
  | 'denied'
  | 'subscribed'

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4)
  const b64 = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(b64)
  const arr = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i)
  return arr
}

export function pushSupported(): boolean {
  return (
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window &&
    !!VAPID_PUBLIC_KEY
  )
}

export async function getPushStatus(): Promise<PushStatus> {
  if (!pushSupported()) return 'unsupported'
  if (Notification.permission === 'denied') return 'denied'
  if (Notification.permission !== 'granted') return 'need_permission'
  const reg = await navigator.serviceWorker.ready
  const sub = await reg.pushManager.getSubscription()
  return sub ? 'subscribed' : 'need_permission'
}

async function saveSubscription(sub: PushSubscription): Promise<void> {
  const { data: u } = await supabase.auth.getUser()
  const uid = u.user?.id
  if (!uid) throw new Error('未登录')
  const json = sub.toJSON()
  const { error } = await supabase.from('push_subscriptions').upsert(
    {
      user_id: uid,
      endpoint: sub.endpoint,
      p256dh: json.keys?.p256dh ?? '',
      auth: json.keys?.auth ?? '',
    },
    { onConflict: 'endpoint' },
  )
  if (error) throw error
}

/** 必须由用户手势调用（iOS 限制）。返回最终状态。 */
export async function enablePush(): Promise<PushStatus> {
  if (!pushSupported()) return 'unsupported'
  const perm = await Notification.requestPermission()
  if (perm !== 'granted') return perm === 'denied' ? 'denied' : 'need_permission'
  const reg = await navigator.serviceWorker.ready
  const sub =
    (await reg.pushManager.getSubscription()) ??
    (await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY!).buffer as ArrayBuffer,
    }))
  await saveSubscription(sub)
  return 'subscribed'
}

/** 已授权时静默确保订阅在线（登录后调用） */
export async function ensurePushSubscription(): Promise<void> {
  if (!pushSupported() || Notification.permission !== 'granted') return
  try {
    const reg = await navigator.serviceWorker.ready
    const sub =
      (await reg.pushManager.getSubscription()) ??
      (await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY!).buffer as ArrayBuffer,
      }))
    await saveSubscription(sub)
  } catch {
    // 静默失败：下次用户手势再试
  }
}

/** SOS 等需要即时触达的场景：直接触发服务端派发，不等 cron */
export async function triggerPushDispatch(): Promise<void> {
  try {
    await supabase.functions.invoke('push-dispatch', { body: {} })
  } catch {
    // 失败无妨，cron 一分钟内会兜底
  }
}

/** 给自己发一条测试通知并立即派发——用于真机确认推送是否出声/醒目 */
export async function sendTestNotification(): Promise<void> {
  const { error } = await supabase.rpc('send_test_notification')
  if (error) throw error
  await triggerPushDispatch()
}

/** 造一个不会升级打扰他人的测试告警 + 本人推送——用来验证"点通知→解锁界面" */
export async function sendTestUnlock(): Promise<void> {
  const { error } = await supabase.rpc('raise_test_alert')
  if (error) throw error
  await triggerPushDispatch()
}
