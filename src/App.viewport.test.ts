import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const css = readFileSync('src/index.css', 'utf8')
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

describe('iOS installed-PWA viewport regression', () => {
  it('marks iOS Home Screen mode before the app shell renders', () => {
    expect(html).toMatch(/navigator\.standalone === true/)
    expect(html).toMatch(
      /classList\.add\('kc-ios-standalone'\)/,
    )
    expect(html).not.toMatch(/window\.screen\.height - window\.innerHeight/)
    expect(html).not.toMatch(/kc-ios-pwa-viewport-gap/)
  })

  it('keeps 100dvh for browser chrome but uses WebKit full-height 100vh in iOS standalone', () => {
    expect(css).toMatch(
      /@supports \(height: 100dvh\)[\s\S]*height:\s*100dvh;/,
    )

    const standaloneContainers = ruleBlock(
      css,
      'html.kc-ios-standalone,',
    )

    expect(standaloneContainers).toMatch(/height:\s*100vh;/)
    expect(css).toMatch(/html\.kc-ios-standalone #root \.home/)
  })

  it('uses the same standalone height while the startup splash is visible', () => {
    expect(css).toMatch(
      /html\.kc-ios-standalone \.splash\s*\{[^}]*height:\s*100vh;/s,
    )
  })

  it('removes both disproved viewport-overflow workarounds', () => {
    expect(css).not.toMatch(/body::after\s*\{/)
    expect(css).not.toMatch(/--kc-ios-pwa-screen-height/)
    expect(css).not.toMatch(/kc-ios-pwa-viewport-gap/)
  })
})
