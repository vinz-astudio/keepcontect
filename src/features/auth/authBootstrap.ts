import type { Session } from '@supabase/supabase-js'

export interface BootstrapResult {
  session: Session | null
  error: Error | null
  timedOut: boolean
}

/**
 * Wraps initial session fetching with a timeout boundary.
 * If the fetch hangs or fails, returns appropriate status to prevent infinite loading.
 */
export async function bootstrapSession(
  getSessionFn: () => Promise<{ data: { session: Session | null }; error: any }>,
  timeoutMs = 5000
): Promise<BootstrapResult> {
  let timeoutId: any
  const timeoutPromise = new Promise<BootstrapResult>((resolve) => {
    timeoutId = setTimeout(() => {
      resolve({ session: null, error: null, timedOut: true })
    }, timeoutMs)
  })

  const fetchPromise = (async (): Promise<BootstrapResult> => {
    try {
      const res = await getSessionFn()
      if (res.error) {
        return {
          session: null,
          error: res.error instanceof Error ? res.error : new Error(String(res.error)),
          timedOut: false,
        }
      }
      return { session: res.data.session, error: null, timedOut: false }
    } catch (err) {
      return {
        session: null,
        error: err instanceof Error ? err : new Error(String(err)),
        timedOut: false,
      }
    }
  })()

  try {
    const result = await Promise.race([fetchPromise, timeoutPromise])
    return result
  } finally {
    if (timeoutId) {
      clearTimeout(timeoutId)
    }
  }
}
