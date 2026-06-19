import { describe, expect, it } from 'vitest'
import { createClientIssue, rememberClientIssue } from '@/lib/diagnostics'

describe('diagnostics', () => {
  it('normalizes errors without leaking stack traces into the title', () => {
    const issue = createClientIssue('home.status', new Error('load failed'))

    expect(issue.area).toBe('home.status')
    expect(issue.message).toBe('load failed')
    expect(issue.id).toMatch(/^kc_/)
    expect(issue.createdAt).toMatch(/T/)
  })

  it('keeps a bounded newest-first issue buffer', () => {
    const stored: Record<string, string> = {}
    const storage = {
      getItem: (key: string) => stored[key] ?? null,
      setItem: (key: string, value: string) => {
        stored[key] = value
      },
    }

    for (let i = 0; i < 12; i += 1) {
      rememberClientIssue(createClientIssue('test', `issue ${i}`), storage)
    }

    const issues = JSON.parse(stored['kc.clientIssues']) as Array<{ message: string }>
    expect(issues).toHaveLength(10)
    expect(issues[0].message).toBe('issue 11')
    expect(issues[9].message).toBe('issue 2')
  })
})