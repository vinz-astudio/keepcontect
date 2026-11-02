import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

// push-dispatch keeps its own copy because the edge runtime cannot import from
// src/. The two lists must match, or iOS gets a tickle the app expected as an alert.
describe('alert push kinds stay in sync with push-dispatch', () => {
  it('lists the same kinds in both places', () => {
    const read = (p: string) => fs.readFileSync(p, 'utf8')
    const kinds = (src: string) => {
      const m = /SELF_ADDRESSED_KINDS = new Set\(\[([^\]]*)\]\)/.exec(src)
      return (m?.[1] ?? '').split(',').map((k) => k.trim().replace(/['"]/g, '')).filter(Boolean).sort()
    }
    const app = kinds(read('src/features/push/alertPushKinds.ts'))
    expect(app.length).toBeGreaterThan(0)
    expect(kinds(read('supabase/functions/push-dispatch/index.ts'))).toEqual(app)
  })

  // The iOS feed skips these kinds because iOS already drew them from the push.
  // A kind missing here would show twice on the iPhone.
  it('the iOS feed skips the same kinds', () => {
    const swift = fs.readFileSync('ios-passive-ping/ios/Sources/KcPassivePingPlugin/NotifyFeed.swift', 'utf8')
    const m = /selfAddressedKinds: Set<String> = \[([^\]]*)\]/.exec(swift)
    const ios = (m?.[1] ?? '').split(',').map((k) => k.trim().replace(/"/g, '')).filter(Boolean).sort()
    const app = /SELF_ADDRESSED_KINDS = new Set\(\[([^\]]*)\]\)/.exec(fs.readFileSync('src/features/push/alertPushKinds.ts', 'utf8'))?.[1]
      .split(',').map((k) => k.trim().replace(/'/g, '')).filter(Boolean).sort()
    expect(ios).toEqual(app)
  })
})
