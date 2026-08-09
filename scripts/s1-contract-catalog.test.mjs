import { describe, expect, test } from 'vitest'
import {
  REQUIRED_PACKS,
  S1_CONTRACTS,
  classifyAssertion,
  validateCatalog,
} from './s1-contract-catalog.mjs'

describe('S1 contract catalog', () => {
  test('current catalog is valid during build phase', () => {
    expect(validateCatalog(S1_CONTRACTS, process.cwd(), { final: false })).toEqual([])
  })

  test('final validation requires all packs', () => {
    const rows = S1_CONTRACTS.filter((row) => row.pack === 'platform')
    const errors = validateCatalog(rows, process.cwd(), { final: true })
    for (const pack of REQUIRED_PACKS.filter((pack) => pack !== 'platform')) {
      expect(errors).toContain(`missing pack: ${pack}`)
    }
  })

  test('rejects duplicate ids and missing files', () => {
    const duplicate = { ...S1_CONTRACTS[0] }
    const missing = { ...S1_CONTRACTS[0], id: 'ADR0039-MISSING-01', file: 'missing.sql' }
    const errors = validateCatalog([...S1_CONTRACTS, duplicate, missing], process.cwd(), { final: false })
    expect(errors).toContain(`duplicate id: ${duplicate.id}`)
    expect(errors).toContain('missing file: missing.sql')
  })
})

describe('S1 assertion classification', () => {
  test('classifies named TAP pass and semantic red independently', () => {
    const output = [
      'ok 1 - ADR0039-ACTIVITY-01 activity stays separate',
      'not ok 2 - ADR0039-CONCERN-01 Concern cannot create alert',
    ].join('\n')
    expect(classifyAssertion('pass', 'ADR0039-ACTIVITY-01', output)).toBe('PASS')
    expect(classifyAssertion('red', 'ADR0039-CONCERN-01', output)).toBe('RED')
  })

  test('rejects aborts and missing named assertions as harness failures', () => {
    expect(classifyAssertion('red', 'ADR0039-CONCERN-01', 'Bail out! fixture failed')).toBe('HARNESS_FAILURE')
    expect(classifyAssertion('red', 'ADR0039-CONCERN-01', 'ok 1 - another assertion')).toBe('HARNESS_FAILURE')
  })

  test('preserves expected-result drift', () => {
    expect(classifyAssertion('pass', 'ADR0039-X-01', 'not ok 1 - ADR0039-X-01')).toBe('UNEXPECTED_RED')
    expect(classifyAssertion('red', 'ADR0039-X-01', 'ok 1 - ADR0039-X-01')).toBe('UNEXPECTED_PASS')
    expect(classifyAssertion('blocked', 'ADR0039-X-01', '')).toBe('BLOCKED')
  })
})
