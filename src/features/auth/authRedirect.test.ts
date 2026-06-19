import { describe, expect, it } from 'vitest'
import {
  NATIVE_AUTH_CALLBACK_URL,
  authRedirectUrl,
  deepLinkToInternalAuthUrl,
  webAuthCallbackUrl,
} from '@/features/auth/authRedirect'

function loc(href: string): Location {
  return new URL(href) as unknown as Location
}

describe('auth redirect URLs', () => {
  it('uses a stable same-origin callback for web and PWA auth', () => {
    expect(webAuthCallbackUrl(loc('https://keep-contact-mauve.vercel.app/profile?x=1#y'))).toBe(
      'https://keep-contact-mauve.vercel.app/auth/callback',
    )
  })

  it('uses the app scheme for native Capacitor auth', () => {
    expect(authRedirectUrl({ native: true, location: loc('https://keep-contact-mauve.vercel.app/') })).toBe(
      NATIVE_AUTH_CALLBACK_URL,
    )
  })

  it('keeps web auth on the web callback', () => {
    expect(authRedirectUrl({ native: false, location: loc('https://keep-contact-mauve.vercel.app/') })).toBe(
      'https://keep-contact-mauve.vercel.app/auth/callback',
    )
  })

  it('maps native custom-scheme callbacks back into the app web runtime', () => {
    expect(
      deepLinkToInternalAuthUrl(
        'com.keepcontact.app://auth/callback?code=abc&next=/profile',
        'capacitor://localhost',
      ),
    ).toBe('capacitor://localhost/auth/callback?code=abc&next=/profile')
  })

  it('passes through same-host https callbacks for universal/app links', () => {
    expect(
      deepLinkToInternalAuthUrl(
        'https://keep-contact-mauve.vercel.app/auth/callback?code=abc',
        'https://keep-contact-mauve.vercel.app',
      ),
    ).toBe('https://keep-contact-mauve.vercel.app/auth/callback?code=abc')
  })

  it('ignores unrelated URLs', () => {
    expect(deepLinkToInternalAuthUrl('https://example.com/auth/callback?code=abc', 'https://keep-contact-mauve.vercel.app')).toBeNull()
  })
})
