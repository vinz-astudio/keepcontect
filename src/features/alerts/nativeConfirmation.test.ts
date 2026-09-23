import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const read = (name: string) => readFileSync(new URL(`../../../android/app/src/main/java/com/keepcontact/app/${name}.java`, import.meta.url),'utf8')

describe('native safety confirmation authority', () => {
  it('never turns an unacknowledged local unlock into a confirmed-safe notification', () => {
    expect(read('PassivePingReceiver')).not.toContain('updateNotificationToSafe')
    expect(read('NotifyWorker')).not.toContain('updateNotificationToSafe')
  })
  it('keeps a standard confirmation action without promising a pattern bypass', () => {
    const worker = read('NotifyWorker')
    expect(worker).toContain('builder.addAction(0, safeActionTitle, safePending)')
    expect(worker).not.toContain('点开或轻按即完成确认')
  })
})
