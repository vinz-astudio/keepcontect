import { readFileSync, existsSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8')

// One privacy policy, and it must match what the app does (App Review 5.1.1).
describe('privacy policy contract', () => {
  const policy = read('src/features/legal/PrivacyPolicy.tsx')

  it('does not describe the removed significant-location wake (removed 2026-11-02)', () => {
    expect(policy).not.toMatch(/significant[- ]location|重大位置/i)
    expect(policy).toMatch(/does not use location in the background/)
  })

  it('names the service providers and a contact (App Review 5.1.1(i))', () => {
    for (const provider of ['Supabase', 'Firebase Cloud Messaging', 'Apple Push Notification', 'Vercel']) {
      expect(policy).toContain(provider)
    }
    expect(policy).toMatch(/same or equal protection/)
    expect(policy).toContain('mailto:support@keepcontact.app')
  })

  it('keeps a single policy: the old static page redirects to /privacy', () => {
    expect(existsSync(new URL('../../../public/privacy.html', import.meta.url))).toBe(false)
    const vercel = JSON.parse(read('vercel.json'))
    expect(vercel.redirects).toContainEqual({ source: '/privacy.html', destination: '/privacy', permanent: true })
  })
})
