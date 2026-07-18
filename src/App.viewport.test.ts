import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const indexCss = readFileSync('src/index.css', 'utf8')
const homeCss = readFileSync('src/features/relationships/HomeScreen.css', 'utf8')
const tabBarCss = readFileSync('src/features/nav/TabBar.css', 'utf8')
const html = readFileSync('index.html', 'utf8')

function ruleBlock(source: string, prelude: string): string {
  const preludeStart = source.indexOf(prelude)
  if (preludeStart < 0) return ''

  const blockStart = source.indexOf('{', preludeStart + prelude.length)
  if (blockStart < 0) return ''

  let depth = 0
  for (let index = blockStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1
    if (source[index] === '}') depth -= 1
    if (depth === 0) return source.slice(blockStart + 1, index)
  }

  return ''
}

describe('iOS installed-PWA full-height regression', () => {
  it('marks only iOS Home Screen mode before the app shell renders', () => {
    const marker = "classList.add('kc-ios-standalone')"
    expect(html).toMatch(/iPad\|iPhone\|iPod/)
    expect(html).toMatch(/navigator\.standalone === true/)
    expect(html).toContain(marker)
    expect(html.indexOf(marker)).toBeLessThan(html.indexOf('<div id="root">'))
  })

  it('keeps Safari on 100dvh but gives the complete standalone flex chain 100vh', () => {
    expect(indexCss).toMatch(
      /@supports \(height: 100dvh\)[\s\S]*height:\s*100dvh;/,
    )

    const standaloneContainers = ruleBlock(
      indexCss,
      'html.kc-ios-standalone,',
    )

    expect(standaloneContainers).toMatch(/height:\s*100vh;/)
    expect(indexCss).toMatch(/html\.kc-ios-standalone #root \.home/)
  })

  it('lets the mobile TabBar follow the corrected home flex height instead of a fixed viewport anchor', () => {
    expect(homeCss).toMatch(/\.home\s*\{[\s\S]*height:\s*100dvh;/)
    expect(tabBarCss).toMatch(/\.tabbar\s*\{[\s\S]*flex:\s*0 0 auto;/)
    expect(ruleBlock(tabBarCss, '.tabbar')).not.toMatch(/position:\s*fixed/)

    const standaloneTabBar = ruleBlock(
      indexCss,
      'html.kc-ios-standalone #root .tabbar--mobile',
    )
    expect(standaloneTabBar).toMatch(
      /padding-bottom:\s*calc\(0\.4rem \+ env\(safe-area-inset-bottom, 0px\)\);/,
    )
  })

  it('uses 100vh during the standalone splash and removes unreachable fixed-strip workarounds', () => {
    expect(html).toMatch(
      /html\.kc-ios-standalone \.splash\s*\{[^}]*height:\s*100vh;/s,
    )
    expect(indexCss).not.toMatch(/body::after\s*\{/)
    expect(indexCss).not.toMatch(/kc-ios-pwa-viewport-gap/)
    expect(indexCss).not.toMatch(/--kc-ios-pwa-screen-height/)
  })
})
