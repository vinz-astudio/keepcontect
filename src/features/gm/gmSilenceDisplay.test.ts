import { describe, expect, it } from 'vitest'
import {
  formatThreshold,
  isSilenceJudgeable,
  readSilence,
} from '@/features/gm/gmSilenceDisplay'

describe('readSilence', () => {
  it('reports a dark device as a device problem, not a person problem', () => {
    // Karma Cheki, 2026-08-10: three escalations to terminal while her phone
    // kept accepting pushes. The console showed the same `silent` it shows for
    // somebody who has simply gone quiet.
    expect(readSilence({ status: 'alert', alert_cause: 'dark_device' })).toBe('device_dark')
  })

  it('reports a silence alert as a person going quiet', () => {
    expect(readSilence({ status: 'alert', alert_cause: 'silence' })).toBe('person_quiet')
  })

  it('lets the alert cause win over the heartbeat reading', () => {
    // The badge must not contradict the reason printed next to it.
    expect(readSilence({
      status: 'alert',
      alert_cause: 'dark_device',
      silence_kind: 'person_quiet',
    })).toBe('device_dark')
  })

  it('falls back to the heartbeat for causes that say nothing about the device', () => {
    expect(readSilence({ alert_cause: 'concern', silence_kind: 'device_dark' }))
      .toBe('device_dark')
    expect(readSilence({ alert_cause: 'sos', silence_kind: 'person_quiet' }))
      .toBe('person_quiet')
  })

  it('names a dark device before it has escalated to anything', () => {
    // The whole point of showing this without an alert: a GM can act on a
    // broken collector instead of waiting for it to look like danger.
    expect(readSilence({ status: 'silent', silence_kind: 'device_dark' })).toBe('device_dark')
  })

  it('keeps unknown as unknown rather than guessing', () => {
    expect(readSilence({ status: 'silent', silence_kind: 'unknown' })).toBe('unknown')
    expect(readSilence({ status: 'active' })).toBe(null)
  })
})

describe('isSilenceJudgeable', () => {
  it('says an account with no threshold is not being judged for silence', () => {
    // ADR-0037: no evidence yields no threshold, and no threshold means no
    // silence alert can ever fire — an account can otherwise sit in the console
    // looking monitored while nothing could escalate.
    expect(isSilenceJudgeable({ threshold_minutes: null })).toBe(false)
    expect(isSilenceJudgeable({})).toBe(false)
  })

  it('says an account with a real threshold is', () => {
    expect(isSilenceJudgeable({ threshold_minutes: 330 })).toBe(true)
  })

  it('does not treat zero as a threshold', () => {
    expect(isSilenceJudgeable({ threshold_minutes: 0 })).toBe(false)
  })
})

describe('formatThreshold', () => {
  it('reads as hours and minutes', () => {
    expect(formatThreshold(330)).toBe('5h 30m')
    expect(formatThreshold(120)).toBe('2h')
    expect(formatThreshold(45)).toBe('45m')
  })

  it('shows a dash rather than a number that does not exist', () => {
    expect(formatThreshold(null)).toBe('—')
    expect(formatThreshold(undefined)).toBe('—')
    expect(formatThreshold(0)).toBe('—')
    expect(formatThreshold(Number.NaN)).toBe('—')
  })
})
