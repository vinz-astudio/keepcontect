// Keep Contact Service Worker：接收 Web Push 并展示本地化通知。
// iOS 要求：push 必须展示可见通知（userVisibleOnly）。

const DICT = {
  zh: {
    self: '检测到异常沉默，请打开 App 完成解锁报平安。',
    group: '{name} 出现异常沉默，请尽快联系确认其安全。',
    community: '社区警示：{name} 长时间失联且其小组无人响应，请协助推动联系。',
    terminal: '紧急：{name} 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。',
    on_it: '{actor} 正在跟进 {target} 的情况。',
    resolved: '{target} 已确认安全，告警解除。',
    task_invite: '{name} 为你设置了报平安任务，请打开 App 确认是否接受。',
    task_due: '到点报平安啦，点开 App 完成确认。',
    task_missed: '{name} 未完成定时报平安，请关注。',
    task_accepted: '{name} 接受了你设置的报平安任务。',
    task_declined: '{name} 拒绝了你设置的报平安任务。',
    task_updated: '你的报平安任务已被修改，请留意新的时间安排。',
    test: '这是一条测试通知，用来确认推送是否出声、醒目。',
    concern: '{name} 在关心你，请打开 App 完成解锁报平安。',
    someone: '某位成员',
    title: 'Keep Contact',
  },
  en: {
    self: 'Unusual silence detected. Open the app and unlock to check in.',
    group: '{name} has gone unusually silent. Please reach out and make sure they are safe.',
    community: 'Community alert: {name} is unreachable and their group has not responded.',
    terminal: 'URGENT: {name} is unresponsive. Their address and emergency contact are unlocked for you.',
    on_it: '{actor} is following up on {target}.',
    resolved: '{target} is confirmed safe. Alert resolved.',
    task_invite: '{name} set up a check-in task for you. Open the app to accept or decline.',
    task_due: 'Time to check in — open the app to confirm.',
    task_missed: '{name} missed a scheduled check-in. Please look in on them.',
    task_accepted: '{name} accepted your check-in task.',
    task_declined: '{name} declined your check-in task.',
    task_updated: 'Your check-in task was changed. Please note the new schedule.',
    test: 'This is a test notification — checking whether push is audible and prominent.',
    concern: '{name} is checking on you — please open the app and check in.',
    someone: 'A member',
    title: 'Keep Contact',
  },
}

function render(data) {
  const lang = (self.navigator.language || 'en').toLowerCase().startsWith('zh')
    ? 'zh'
    : 'en'
  const d = DICT[lang]
  const tpl = d[data.kind]
  if (!tpl) return data.body || d.title
  const p = data.params || {}
  return tpl
    .replaceAll('{name}', p.name || d.someone)
    .replaceAll('{actor}', p.actor || d.someone)
    .replaceAll('{target}', p.target || d.someone)
}

self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('push', (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch {
    data = { body: event.data ? event.data.text() : '' }
  }
  const body = render(data)
  const options = {
    body,
    icon: '/icons/icon-192.png',
    badge: '/icons/icon-192.png',
    silent: false, // 明确要求系统出声（最终仍受设备通知设置控制）
    vibrate: [200, 100, 200], // Android 震动提示；iOS 忽略，无害
    data: { url: '/' },
  }
  // 同一告警的多条推送合并；renotify 让“更新”仍重新提醒而非静默替换
  // 注意：renotify 必须与 tag 一起出现，否则部分浏览器会抛错
  if (data.alertId) {
    options.tag = data.alertId
    options.renotify = true
  }
  const tasks = [self.registration.showNotification('Keep Contact', options)]
  // 主屏图标角标：未读数（后台收到推送时更新）
  if (typeof data.badge === 'number' && self.navigator && self.navigator.setAppBadge) {
    tasks.push(self.navigator.setAppBadge(data.badge).catch(() => {}))
  }
  event.waitUntil(Promise.all(tasks))
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  // 点击通知：聚焦已有窗口并叫它立刻查告警弹解锁界面；没有窗口则新开（带标记）
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((list) => {
        for (const c of list) {
          if ('focus' in c) {
            c.postMessage({ type: 'kc-open-alert' })
            return c.focus()
          }
        }
        return self.clients.openWindow('/?from=notif')
      }),
  )
})
