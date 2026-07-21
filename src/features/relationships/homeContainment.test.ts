import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

describe('Home Containment & SafeAway Gating Contracts', () => {
  const homeScreenPath = path.resolve('src/features/relationships/HomeScreen.tsx')
  const i18nPath = path.resolve('src/lib/i18n.tsx')

  it('asserts SafeAwayBar import and render are both absent from HomeScreen during Gate 1', () => {
    const homeScreenSource = fs.readFileSync(homeScreenPath, 'utf8')

    // Contract: SafeAwayBar must not be imported or rendered in HomeScreen during Gate 1
    const hasSafeAwayBarImport = homeScreenSource.includes("import { SafeAwayBar }")
    const hasSafeAwayBarRender = homeScreenSource.includes("<SafeAwayBar")

    expect(hasSafeAwayBarImport).toBe(false) // FAIL: SafeAwayBar is imported in current HomeScreen
    expect(hasSafeAwayBarRender).toBe(false) // FAIL: SafeAwayBar is rendered in current HomeScreen
  })

  it('asserts live.safe Chinese and English translations explicitly state local plan and server monitoring remains active', () => {
    const i18nSource = fs.readFileSync(i18nPath, 'utf8')

    // Capture specifically the 'live.safe' translations from i18n.tsx using regex
    // To isolate them and prevent other keys containing "paused" or "暂停" from polluting the assertion.
    const matches = [...i18nSource.matchAll(/'live\.safe':\s*['"](.*?)['"]/g)].map(m => m[1])

    // Assert we found the translation values
    expect(matches.length).toBeGreaterThanOrEqual(2)

    const zhTranslation = matches[0]
    const enTranslation = matches[1]

    // 1. Assert English translation matches exactly
    expect(enTranslation).toBe('Safe but away (local plan only; server monitoring remains active)') // FAIL: currently 'Safe but away (monitoring paused)'

    // 2. Assert Chinese translation properties (using Unicode escapes to prevent mojibake)
    // \u672c\u5730\u4f5c\u606f\u8ba1\u5212 = "本地作息计划"
    const hasZhLocalPlan = zhTranslation.includes('\u672c\u5730\u4f5c\u606f\u8ba1\u5212')
    // \u670d\u52a1\u5668\u5b89\u5168\u76d1\u6d4b\u4ecd\u5728\u8fd0\u884c = "服务器安全监测仍在运行"
    const hasZhServerMonitoring = zhTranslation.includes('\u670d\u52a1\u5668\u5b89\u5168\u76d1\u6d4b\u4ecd\u5728\u8fd0\u884c')

    expect(hasZhLocalPlan).toBe(true) // FAIL: does not exist in live.safe yet
    expect(hasZhServerMonitoring).toBe(true) // FAIL: does not exist in live.safe yet

    // 3. Forbid "paused" / "暂停" (\u6682\u505c) / "守望" (\u5b88\u671b) specifically within the live.safe value
    const hasForbiddenWord = zhTranslation.includes('paused') || zhTranslation.includes('\u6682\u505c') || zhTranslation.includes('\u5b88\u671b')
    expect(hasForbiddenWord).toBe(false) // FAIL: currently contains "暂停守望"
  })
})
