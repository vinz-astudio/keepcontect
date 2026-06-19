// fetch 降级层：iOS 主屏 PWA 存在 fetch 全局失败(TypeError)而 XHR 仍可用的
// WebKit 故障模式。原生 fetch 抛 TypeError 时自动改走 XMLHttpRequest。

function headersFrom(
  init?: RequestInit,
  input?: RequestInfo | URL,
): Headers {
  if (init?.headers) return new Headers(init.headers)
  if (input instanceof Request) return new Headers(input.headers)
  return new Headers()
}

export function xhrFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const url =
      typeof input === 'string'
        ? input
        : input instanceof URL
          ? input.toString()
          : input.url
    const method =
      init?.method ?? (input instanceof Request ? input.method : 'GET')

    const xhr = new XMLHttpRequest()
    xhr.open(method, url, true)
    headersFrom(init, input).forEach((v, k) => {
      try {
        xhr.setRequestHeader(k, v)
      } catch { /* 受限头部忽略 */ }
    })
    xhr.responseType = 'text'
    xhr.onload = () => {
      const headers = new Headers()
      for (const line of xhr.getAllResponseHeaders().trim().split(/[\r\n]+/)) {
        const i = line.indexOf(': ')
        if (i > 0) {
          try {
            headers.append(line.slice(0, i), line.slice(i + 2))
          } catch { /* ignore */ }
        }
      }
      resolve(
        new Response(xhr.responseText, {
          status: xhr.status,
          statusText: xhr.statusText,
          headers,
        }),
      )
    }
    xhr.onerror = () => reject(new TypeError('XHR network error'))
    xhr.ontimeout = () => reject(new TypeError('XHR timeout'))
    xhr.send((init?.body ?? null) as XMLHttpRequestBodyInit | null)
  })
}

/** 原生 fetch 优先；TypeError(网络层死亡)时降级 XHR */
export const resilientFetch: typeof fetch = async (input, init) => {
  try {
    return await fetch(input, init)
  } catch (e) {
    if (e instanceof TypeError) {
      return await xhrFetch(input as RequestInfo | URL, init)
    }
    throw e
  }
}
