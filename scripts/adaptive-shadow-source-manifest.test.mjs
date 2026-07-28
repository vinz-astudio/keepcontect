import { expect, test } from 'vitest'
import { verifyAdaptiveShadowSource } from './adaptive-shadow-source-manifest.mjs'

test('accepts only the audited adaptive source set', async () => {
  const result = await verifyAdaptiveShadowSource(process.cwd())
  expect(result.unexpected).toEqual([])
  expect(result.groupFixPresent).toBe(true)
  expect(result.excludedAclPresent).toBe(false)
  expect(result.protectedLiveDrift).toHaveLength(0)
})
