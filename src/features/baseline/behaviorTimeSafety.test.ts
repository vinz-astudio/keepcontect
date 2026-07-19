import { describe, expect, it } from 'vitest'
// @ts-ignore - Legitimate RED: isEventLivenessQualifying is an expected helper that does not exist in production yet
import { isEventLivenessQualifying } from '@/features/passive/api'
import fs from 'node:fs'
import path from 'node:path'

describe('Behavior Time Safety Contracts', () => {
  it('imports the expected helper from passive/api.ts with correct signature', () => {
    // Legitimate RED: will fail because isEventLivenessQualifying is not exported
    expect(isEventLivenessQualifying).toBeTypeOf('function')
  })

  it('verifies event qualification rules based on helper contract parameters', () => {
    const nowMs = 1718900000000 // Fixed mock time
    const alertCreatedAtMs = nowMs - 1 * 3600_000 // Alert created 1 hour ago

    const context = { nowMs, alertCreatedAtMs }

    // 1. Ingest version 1 is NOT qualifying for live safety refresh
    const v1Event = {
      observedAtMs: nowMs - 30 * 1000,
      receivedAtMs: nowMs,
      ingestVersion: 1,
      kind: 'unlock'
    }
    expect(isEventLivenessQualifying(v1Event, context)).toBe(false)

    // 2. Future event (> 5 minutes clock-drift buffer) is NOT qualifying (abs drift <= 5m)
    const futureEvent = {
      observedAtMs: nowMs + 6 * 60_000,
      receivedAtMs: nowMs,
      ingestVersion: 2,
      kind: 'unlock'
    }
    expect(isEventLivenessQualifying(futureEvent, context)).toBe(false)

    // 3. Offline old event (observed_at < alertCreatedAtMs) is NOT qualifying to resolve safety
    const oldOfflineEvent = {
      observedAtMs: alertCreatedAtMs - 1000,
      receivedAtMs: nowMs,
      ingestVersion: 2,
      kind: 'unlock'
    }
    expect(isEventLivenessQualifying(oldOfflineEvent, context)).toBe(false)

    // 4. Offline old event (received_at < alertCreatedAtMs) is NOT qualifying to resolve safety
    const oldReceivedEvent = {
      observedAtMs: nowMs - 10 * 1000,
      receivedAtMs: alertCreatedAtMs - 1000,
      ingestVersion: 2,
      kind: 'unlock'
    }
    expect(isEventLivenessQualifying(oldReceivedEvent, context)).toBe(false)

    // 5. V2 current event IS qualifying
    const v2CurrentEvent = {
      observedAtMs: nowMs - 10 * 1000,
      receivedAtMs: nowMs,
      ingestVersion: 2,
      kind: 'unlock'
    }
    expect(isEventLivenessQualifying(v2CurrentEvent, context)).toBe(true)

    // 6. Server-timed manual checkin IS qualifying
    // Server-timed manual pings have observedAtMs === receivedAtMs
    const serverTimedManual = {
      observedAtMs: nowMs,
      receivedAtMs: nowMs,
      ingestVersion: 2,
      kind: 'manual_checkin'
    }
    expect(isEventLivenessQualifying(serverTimedManual, context)).toBe(true)
  })

  it('asserts statically that received_at and ingest_version are not accepted as client overrides in the API payload', () => {
    const pingFuncPath = path.resolve('supabase/functions/ping/index.ts')
    const pingSource = fs.readFileSync(pingFuncPath, 'utf8')

    // Contract: Edge function must NOT parse received_at, receivedAt, ingest_version, or ingestVersion
    // from client query params or request JSON body to prevent client-side overrides.
    const parsesClientReceivedAt = pingSource.includes("searchParams.get('received_at')") ||
                                   pingSource.includes("searchParams.get('receivedAt')") ||
                                   /body\.(received_at|receivedAt)/.test(pingSource)

    const parsesClientIngestVersion = pingSource.includes("searchParams.get('ingest_version')") ||
                                      pingSource.includes("searchParams.get('ingestVersion')") ||
                                      /body\.(ingest_version|ingestVersion)/.test(pingSource)

    expect(parsesClientReceivedAt).toBe(false)
    expect(parsesClientIngestVersion).toBe(false)
  })
})
