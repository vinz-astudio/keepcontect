export interface ClientIssue {
  id: string
  area: string
  message: string
  createdAt: string
}

const ISSUE_KEY = 'kc.clientIssues'
const MAX_ISSUES = 10

interface IssueStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

function messageFrom(error: unknown): string {
  if (error instanceof Error && error.message.trim()) return error.message
  if (typeof error === 'string' && error.trim()) return error
  return 'Unknown client error'
}

export function createClientIssue(area: string, error: unknown): ClientIssue {
  return {
    id: `kc_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    area,
    message: messageFrom(error).slice(0, 300),
    createdAt: new Date().toISOString(),
  }
}

export function rememberClientIssue(
  issue: ClientIssue,
  storage: IssueStorage = window.sessionStorage,
): void {
  try {
    const previous = JSON.parse(storage.getItem(ISSUE_KEY) ?? '[]') as ClientIssue[]
    storage.setItem(ISSUE_KEY, JSON.stringify([issue, ...previous].slice(0, MAX_ISSUES)))
  } catch {
    /* Diagnostics must never break the app. */
  }
}

export function reportClientIssue(area: string, error: unknown): ClientIssue {
  const issue = createClientIssue(area, error)
  rememberClientIssue(issue)
  window.dispatchEvent(new CustomEvent('kc-client-issue', { detail: issue }))
  if (import.meta.env.DEV) console.warn('kc-client-issue', issue)
  return issue
}