import { describe, expect, it } from 'vitest'
import { shouldShowSelfCheckForNotificationKind } from '@/features/alerts/notificationRouting'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'

describe('notification routing', () => {
  it('only opens the self-check overlay for notifications about the current user', () => {
    expect(shouldShowSelfCheckForNotificationKind('self')).toBe(true)
    expect(shouldShowSelfCheckForNotificationKind('concern')).toBe(true)

    for (const kind of ['group', 'community', 'terminal', 'on_it', 'resolved', 'task_missed', undefined, null]) {
      expect(shouldShowSelfCheckForNotificationKind(kind)).toBe(false)
    }
  })

  it.each([['', 'kc-open-alert'], ['safe','kc-ack-safe']])('web notification action %s routes to %s', async (action, expected) => {
    const handlers: Record<string, (event: unknown) => void> = {}
    const messages: {type: string}[] = []
    const client = { focus: () => Promise.resolve(), postMessage: (message: {type:string}) => messages.push(message) }
    const self = { addEventListener: (name:string, handler:(event:unknown)=>void) => { handlers[name]=handler },
      clients: { matchAll: async () => [client] }, navigator: { language: 'en' } }
    runInNewContext(readFileSync(new URL('../../../public/sw.js',import.meta.url),'utf8'), {self})
    let work: Promise<unknown> | undefined
    handlers.notificationclick({ action, notification: { close() {}, data:{kind:'self',alertId:'alert-1'} },
      waitUntil: (promise:Promise<unknown>) => { work=promise } })
    await work
    expect(messages[0].type).toBe(expected)
  })
})
