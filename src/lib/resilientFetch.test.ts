import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resilientFetch, xhrFetch } from '@/lib/resilientFetch'

class FakeXhr {
  static instances: FakeXhr[] = []

  method = ''
  url = ''
  responseType = ''
  responseText = 'fallback'
  status = 200
  statusText = 'OK'
  timeout = 0
  withCredentials = false
  aborted = false
  sendCalls = 0
  sentBody: Document | XMLHttpRequestBodyInit | null | undefined
  onload: (() => void) | null = null
  onerror: (() => void) | null = null
  ontimeout: (() => void) | null = null
  onabort: (() => void) | null = null

  constructor() {
    FakeXhr.instances.push(this)
  }

  open(method: string, url: string) {
    this.method = method
    this.url = url
  }

  setRequestHeader() {}

  getAllResponseHeaders() {
    return 'content-type: text/plain\r\n'
  }

  send(body?: Document | XMLHttpRequestBodyInit | null) {
    this.sendCalls += 1
    this.sentBody = body
  }

  abort() {
    this.aborted = true
    this.onabort?.()
  }
}

describe('resilientFetch', () => {
  beforeEach(() => {
    FakeXhr.instances = []
    vi.stubGlobal('XMLHttpRequest', FakeXhr)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it.each(['POST', 'PATCH', 'PUT', 'DELETE'])('never automatically replays %s', async (method) => {
    const failure = new TypeError('network failed')
    const nativeFetch = vi.fn().mockRejectedValue(failure)
    vi.stubGlobal('fetch', nativeFetch)

    await expect(resilientFetch('https://example.test/write', { method })).rejects.toBe(failure)
    expect(nativeFetch).toHaveBeenCalledTimes(1)
    expect(FakeXhr.instances).toHaveLength(0)
  })

  it('never automatically replays a GET carrying a body', async () => {
    const failure = new TypeError('network failed')
    const nativeFetch = vi.fn().mockRejectedValue(failure)
    vi.stubGlobal('fetch', nativeFetch)

    await expect(
      resilientFetch('https://example.test/read', { method: 'GET', body: 'payload' }),
    ).rejects.toBe(failure)
    expect(nativeFetch).toHaveBeenCalledTimes(1)
    expect(FakeXhr.instances).toHaveLength(0)
  })

  it.each(['GET', 'HEAD'])('falls back through XHR for %s TypeError', async (method) => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('network failed')))

    const pending = resilientFetch('https://example.test/read', { method })
    await vi.waitFor(() => expect(FakeXhr.instances).toHaveLength(1))
    expect(FakeXhr.instances[0].method).toBe(method)
    FakeXhr.instances[0].onload?.()

    await expect(pending).resolves.toBeInstanceOf(Response)
  })

  it('rejects a pre-aborted request before either transport starts', async () => {
    const nativeFetch = vi.fn()
    vi.stubGlobal('fetch', nativeFetch)
    const controller = new AbortController()
    controller.abort()

    await expect(resilientFetch('https://example.test/read', { signal: controller.signal }))
      .rejects.toMatchObject({ name: 'AbortError' })
    expect(nativeFetch).not.toHaveBeenCalled()
    expect(FakeXhr.instances).toHaveLength(0)
  })

  it('rejects pre-aborted explicit xhrFetch without constructing or sending XHR', async () => {
    const controller = new AbortController()
    controller.abort()

    await expect(xhrFetch('https://example.test/read', { signal: controller.signal }))
      .rejects.toMatchObject({ name: 'AbortError' })
    expect(FakeXhr.instances).toHaveLength(0)
  })

  it('propagates a mid-flight abort to the XHR fallback', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('network failed')))
    const controller = new AbortController()

    const pending = resilientFetch('https://example.test/read', { signal: controller.signal })
    await vi.waitFor(() => expect(FakeXhr.instances).toHaveLength(1))
    controller.abort()

    await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    expect(FakeXhr.instances[0].aborted).toBe(true)
  })

  it('cleans abort listeners and settles once on timeout', async () => {
    const controller = new AbortController()
    const addListener = vi.spyOn(controller.signal, 'addEventListener')
    const removeListener = vi.spyOn(controller.signal, 'removeEventListener')

    const pending = xhrFetch('https://example.test/read', { signal: controller.signal })
    const xhr = FakeXhr.instances[0]
    expect(xhr.timeout).toBeGreaterThan(0)
    expect(addListener).toHaveBeenCalledWith('abort', expect.any(Function), { once: true })

    xhr.ontimeout?.()
    xhr.onload?.()

    await expect(pending).rejects.toThrow('XHR timeout')
    expect(removeListener).toHaveBeenCalledWith('abort', expect.any(Function))
  })

  it('preserves credentials and headers when constructing the XHR', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('network failed')))

    const pending = resilientFetch('https://example.test/read', {
      method: 'GET',
      credentials: 'include',
      headers: { 'X-Test': 'yes' },
    })
    await vi.waitFor(() => expect(FakeXhr.instances).toHaveLength(1))
    const xhr = FakeXhr.instances[0]
    expect(xhr.withCredentials).toBe(true)
    xhr.onload?.()

    const response = await pending
    expect(response.status).toBe(200)
    expect(response.headers.get('content-type')).toBe('text/plain')
  })

  it('keeps explicit xhrFetch available for writes', async () => {
    const pending = xhrFetch('https://example.test/write', {
      method: 'POST',
      body: 'payload',
    })
    const xhr = FakeXhr.instances[0]

    expect(xhr.method).toBe('POST')
    expect(xhr.sendCalls).toBe(1)
    expect(xhr.sentBody).toBe('payload')
    xhr.onload?.()

    await expect(pending).resolves.toBeInstanceOf(Response)
  })
})
