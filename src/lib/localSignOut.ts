/** The selected offline logout clears this installation through the auth SDK's
 * normal cleanup path, without waiting for a remote session-revocation request. */
export function localSignOutTransport(base: typeof fetch) {
  let localOnly = 0
  const pendingRefreshes = new Set<() => void>()
  const removed = () => new Response(JSON.stringify({
    code: 'refresh_token_not_found', error_code: 'refresh_token_not_found', message: 'Local session removed',
  }), { status: 400, headers: { 'Content-Type': 'application/json' } })
  return {
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input))
      const method = init?.method ?? (input instanceof Request ? input.method : 'GET')
      if (localOnly > 0 && method.toUpperCase() === 'POST' && url.pathname.endsWith('/auth/v1/logout')) {
        return new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } })
      }
      const refresh = url.pathname.endsWith('/auth/v1/token') && url.searchParams.get('grant_type') === 'refresh_token'
      if (!refresh) return base(input, init)
      if (localOnly > 0) return removed()

      // An SDK refresh holds its auth lock and is single-flighted. Resolve it
      // with a terminal result before signOut waits for that lock. Racing the
      // complete body also covers a connection stalled after response headers.
      const controller = new AbortController()
      const sourceSignal = init?.signal ?? (input instanceof Request ? input.signal : undefined)
      const abort = () => controller.abort(sourceSignal?.reason)
      sourceSignal?.addEventListener('abort', abort, { once: true })
      if (sourceSignal?.aborted) abort()
      let cancel!: () => void
      const cancelled = new Promise<Response>(resolve => {
        cancel = () => { resolve(removed()); controller.abort() }
        pendingRefreshes.add(cancel)
      })
      try {
        const response = Promise.resolve().then(() => base(input, { ...init, signal: controller.signal })).then(async result => {
          const body = await result.arrayBuffer()
          return new Response(body.byteLength ? body : null, {
            status: result.status, statusText: result.statusText, headers: result.headers,
          })
        })
        return await Promise.race([cancelled, response])
      } finally {
        pendingRefreshes.delete(cancel)
        sourceSignal?.removeEventListener('abort', abort)
      }
    }) as typeof fetch,
    run: async <T>(cleanup: () => Promise<T>): Promise<T> => {
      localOnly++
      for (const cancel of pendingRefreshes) cancel()
      try { return await cleanup() } finally { localOnly-- }
    },
  }
}

export async function clearLocalAuthSession(auth:LocalAuth,transport:ReturnType<typeof localSignOutTransport>):Promise<void> {
  try {
    await transport.run(async()=>{
      await auth.stopAutoRefresh()
      const {error}=await auth.signOut({scope:'local'})
      if(error && error.code!=='refresh_token_not_found') throw error
      const result=await auth.getSession()
      if(result.data.session!==null) throw new Error('Local session cleanup incomplete')
    })
  } finally {
    // stopAutoRefresh also removes the SDK visibility lifecycle. Re-arm it so
    // the next login can refresh normally; an empty session performs no request.
    await auth.startAutoRefresh()
  }
}
interface LocalAuth {
  stopAutoRefresh():Promise<void>
  startAutoRefresh():Promise<void>
  signOut(options:{scope:'local'}):Promise<{error:{code?:string}|null}>
  getSession():Promise<{data:{session:unknown};error:unknown}>
}
