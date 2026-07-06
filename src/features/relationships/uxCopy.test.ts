import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

const i18n = fs.readFileSync('src/lib/i18n.tsx', 'utf8')

describe('P1 UX copy cleanup', () => {
  it('uses plain zh terms for watch/group/community surfaces', () => {
    expect(i18n).not.toContain('Watch页')
    expect(i18n).toContain("'comm.title': '我的社区'")
    expect(i18n).toContain("'group.title': '我的群组'")
    expect(i18n).toContain("'status.empty': '加入社区 / 群组后")
  })

  it('uses clearer safe-away and sleep-off wording', () => {
    expect(i18n).toContain("'live.safeaway': '安心外出'")
    expect(i18n).toContain("'live.sleep.off': '关闭睡眠时段'")
  })
})
