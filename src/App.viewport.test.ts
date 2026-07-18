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
  it('enables compensation only for the measured iOS standalone viewport gap', () => {
    expect(html).toMatch(/navigator\.standalone === true/)
    expect(html).toMatch(/window\.screen\.height - window\.innerHeight/)
    expect(html).toMatch(/Math\.abs\(viewportGap - safeTop\) <= 2/)
    expect(html).toMatch(
      /classList\.toggle\('kc-ios-pwa-viewport-gap', shouldCompensate\)/,
    )
  })

  it('extends every 100dvh app container to the measured physical screen height', () => {
    const compensatedContainers = ruleBlock(
      css,
      'html.kc-ios-pwa-viewport-gap,',
    )

    expect(compensatedContainers).toMatch(
      /height:\s*var\(--kc-ios-pwa-screen-height, calc\(100dvh \+ env\(safe-area-inset-top, 0px\)\)\);/,
    )
    expect(css).toMatch(/html\.kc-ios-pwa-viewport-gap #root \.home/)
  })

  it('keeps nav controls above the home indicator after extending the app box', () => {
    expect(css).toMatch(
      /html\.kc-ios-pwa-viewport-gap #root \.tabbar--mobile\s*\{[^}]*padding-bottom:\s*calc\(0\.4rem \+ env\(safe-area-inset-bottom, 0px\)\);/s,
    )
  })

  it('removes the viewport-anchored pseudo strip that cannot reach the missing 47pt', () => {
    expect(css).not.toMatch(/body::after\s*\{/)
  })
})
