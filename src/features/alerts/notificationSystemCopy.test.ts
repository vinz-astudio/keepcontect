import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
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
