import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { runInNewContext } from 'node:vm'
import { describe, expect, it } from 'vitest'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..')

function read(rel: string): string {
  return readFileSync(path.join(root, rel), 'utf8')
}

describe('system notification second-person copy support', () => {
  it('lets Web Push render target-is-recipient notifications as you', () => {
    const sw = read('public/sw.js')

    expect(sw).toContain('target_is_recipient')
    expect(sw).toContain('on_it_you')
    expect(sw).toContain('resolved_you')
  })

  it('lets Android native notifications render target-is-recipient notifications as you', () => {
    const worker = read('android/app/src/main/java/com/keepcontact/app/NotifyWorker.java')

    expect(worker).toContain('target_is_recipient')
    expect(worker).toContain('on_it_you')
    expect(worker).toContain('resolved_you')
  })

  it('marks push/feed payloads when the notification target is the recipient', () => {
    expect(read('supabase/functions/push-dispatch/index.ts')).toContain('target_is_recipient')
    expect(read('supabase/functions/notify-feed/index.ts')).toContain('target_is_recipient')
  })
})

// ADR-0039 rev.1 / ADR-0040 rev.1: the system notification channels render group and
// community copy themselves, so each must read params.miss_kind like the in-app list does.
describe('system notification device-loss copy', () => {
  function swRender(language: string) {
    const context: Record<string, unknown> = {
      self: { addEventListener() {}, navigator: { language } },
    }
    runInNewContext(read('public/sw.js'), context)
    return context.render as (data: { kind: string; body?: string; params?: Record<string, string> }) => string
  }

  it.each([
    ['zh-CN', 'group', 'device_unreachable', '设备与 KC 失去联系'],
    ['zh-CN', 'community', 'device_unreachable', '设备持续失去联系'],
    ['zh-CN', 'group', 'collection_restricted', '检测被关闭'],
    ['en', 'group', 'device_unreachable', "KC lost contact with Ana's device"],
    ['en', 'community', 'collection_restricted', "KC still can't check on Ana"],
  ])('Web Push (%s) says a %s notice for %s is about the device', (language, kind, missKind, expected) => {
    const copy = swRender(language)({ kind, params: { name: 'Ana', miss_kind: missKind } })
    expect(copy).toContain(expected)
    expect(copy).not.toMatch(/异常沉默|长时间失联|silent|unresponsive/i)
  })

  it('Web Push keeps the silence wording when the person was genuinely silent', () => {
    const render = swRender('en')
    expect(render({ kind: 'group', params: { name: 'Ana', miss_kind: 'silent' } }))
      .toBe(render({ kind: 'group', params: { name: 'Ana' } }))
  })

  it('Android native notifications carry the same device-loss templates and choose them by miss_kind', () => {
    const worker = read('android/app/src/main/java/com/keepcontact/app/NotifyWorker.java')
    expect(worker).toContain('optString("miss_kind"')
    for (const key of ['group_device_unreachable', 'community_device_unreachable',
      'group_collection_restricted', 'community_collection_restricted']) {
      expect(worker.split(`d.put("${key}"`).length - 1).toBe(2) // zh and en
    }
  })
})
