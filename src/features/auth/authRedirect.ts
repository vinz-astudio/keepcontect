import { Capacitor } from '@capacitor/core'

export const AUTH_CALLBACK_PATH = '/auth/callback'
export const NATIVE_AUTH_SCHEME = 'com.keepcontact.app'
export const NATIVE_AUTH_CALLBACK_URL = `${NATIVE_AUTH_SCHEME}://auth/callback`

interface AuthRedirectOptions {
  native?: boolean
  location?: Location
}

export function webAuthCallbackUrl(locationLike: Location = window.location): string {
  const url = new URL(locationLike.href)
  url.pathname = AUTH_CALLBACK_PATH
  url.search = ''
  url.hash = ''
  return url.toString()
}

export function authRedirectUrl({
  native = Capacitor.isNativePlatform(),
  location = window.location,
}: AuthRedirectOptions = {}): string {
  return native ? NATIVE_AUTH_CALLBACK_URL : webAuthCallbackUrl(location)
}

function urlBase(url: URL): string {
  return url.origin === 'null' ? `${url.protocol}//${url.host}` : url.origin
}

export function deepLinkToInternalAuthUrl(openedUrl: string, appOrigin: string = window.location.origin): string | null {
  let incoming: URL
  let origin: URL
  try {
    incoming = new URL(openedUrl)
    origin = new URL(appOrigin)
  } catch {
    return null
  }

  if (incoming.protocol === `${NATIVE_AUTH_SCHEME}:`) {
    if (incoming.hostname !== 'auth' || incoming.pathname !== '/callback') return null
    return `${urlBase(origin)}${AUTH_CALLBACK_PATH}${incoming.search}${incoming.hash}`
  }

  if (incoming.protocol === origin.protocol && incoming.host === origin.host) {
    if (incoming.pathname !== AUTH_CALLBACK_PATH) return null
    return incoming.toString()
  }

  return null
}
