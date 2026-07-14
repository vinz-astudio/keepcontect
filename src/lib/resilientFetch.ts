// iOS installed PWAs can occasionally lose native fetch while XHR still works.
// Automatic fallback is deliberately limited to safe, bodyless reads.

const XHR_TIMEOUT_MS = 20_000

function headersFrom(
  init?: RequestInit,
  input?: RequestInfo | URL,
): Headers {
  if (init?.headers) return new Headers(init.headers)
  if (input instanceof Request) return new Headers(input.headers)
  return new Headers()
}

function effectiveMethod(input: RequestInfo | URL, init?: RequestInit): string {
  const requestMethod = input instanceof Request ? input.method : 'GET'
  return (init?.method ?? requestMethod).toUpperCase()
}

function effectiveSignal(
  input: RequestInfo | URL,
  init?: RequestInit,
): AbortSignal | null {
  const requestSignal = input instanceof Request ? input.signal : null
  return init?.signal !== undefined ? init.signal : requestSignal
}

function effectiveBody(
  input: RequestInfo | URL,
  init?: RequestInit,
): BodyInit | ReadableStream | null | undefined {
  const requestBody = input instanceof Request ? input.body : undefined
  return init?.body !== undefined ? init.body : requestBody
}

function abortError(): DOMException {
  return new DOMException('The operation was aborted.', 'AbortError')
}

export function xhrFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const signal = effectiveSignal(input, init)
    if (signal?.aborted) {
      reject(abortError())
      return
    }

    const url =
      typeof input === 'string'
        ? input
        : input instanceof URL
          ? input.toString()
          : input.url
    const method = effectiveMethod(input, init)
    const xhr = new XMLHttpRequest()
    let settled = false

    function cleanup(): void {
      signal?.removeEventListener('abort', onAbort)
      xhr.onload = null
      xhr.onerror = null
      xhr.ontimeout = null
      xhr.onabort = null
    }

    function settle(action: () => void): void {
      if (settled) return
      settled = true
      cleanup()
      action()
    }

    function onAbort(): void {
      if (settled) return
      xhr.abort()
      settle(() => reject(abortError()))
    }

    try {
      xhr.open(method, url, true)
      headersFrom(init, input).forEach((value, key) => {
        try {
          xhr.setRequestHeader(key, value)
        } catch {
          // Browsers forbid setting some transport-owned headers.
        }
      })
      xhr.responseType = 'text'
      xhr.timeout = XHR_TIMEOUT_MS

      const requestCredentials = input instanceof Request
        ? input.credentials
        : 'same-origin'
      const credentials = init?.credentials ?? requestCredentials
      xhr.withCredentials = credentials === 'include'

      xhr.onload = () => {
        try {
          const headers = new Headers()
          for (const line of xhr.getAllResponseHeaders().trim().split(/[\r\n]+/)) {
            const separator = line.indexOf(': ')
            if (separator > 0) {
              try {
                headers.append(
                  line.slice(0, separator),
                  line.slice(separator + 2),
                )
              } catch {
                // Ignore malformed response headers.
              }
            }
          }
          const response = new Response(xhr.responseText, {
            status: xhr.status,
            statusText: xhr.statusText,
            headers,
          })
          settle(() => resolve(response))
        } catch (error) {
          settle(() => reject(error))
        }
      }
      xhr.onerror = () => settle(() => reject(new TypeError('XHR network error')))
      xhr.ontimeout = () => settle(() => reject(new TypeError('XHR timeout')))
      xhr.onabort = () => settle(() => reject(abortError()))
      signal?.addEventListener('abort', onAbort, { once: true })

      // Close the race between the initial check and listener installation.
      if (signal?.aborted) {
        onAbort()
        return
      }

      xhr.send((init?.body ?? null) as XMLHttpRequestBodyInit | null)
    } catch (error) {
      settle(() => reject(error))
    }
  })
}

/** Native fetch first; only GET/HEAD TypeErrors may automatically fall back to XHR. */
export const resilientFetch: typeof fetch = async (input, init) => {
  const typedInput = input as RequestInfo | URL
  const signal = effectiveSignal(typedInput, init)
  if (signal?.aborted) throw abortError()

  try {
    return await fetch(input, init)
  } catch (error) {
    if (signal?.aborted) throw abortError()
    const method = effectiveMethod(typedInput, init)
    const body = effectiveBody(typedInput, init)
    if (
      error instanceof TypeError &&
      (method === 'GET' || method === 'HEAD') &&
      body == null
    ) {
      return await xhrFetch(typedInput, init)
    }
    throw error
  }
}
